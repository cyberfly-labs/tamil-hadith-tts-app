import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import 'tokenizer.dart';
import 'mnn_tts_bindings.dart';

/// VITS inference parameters from mms-tts-tam config.json
/// Reference: https://huggingface.co/facebook/mms-tts-tam/blob/main/config.json
class VitsConfig {
  /// Controls audio variation (default from config.json)
  static const double noiseScale = 0.667;

  /// Controls speaking rate (1.0 = normal)
  static const double lengthScale = 1.0;

  /// Controls phoneme duration variation (default from config.json)
  static const double noiseScaleW = 0.8;

  /// Output sample rate
  static const int sampleRate = 16000;
}

/// High-level TTS engine service for Tamil text-to-speech
/// Uses facebook/mms-tts-tam VITS model via MNN inference + FFI
///
/// NOTE: MNN inference runs on the main isolate because the native engine
/// pointer cannot be transferred across Dart isolates. The MNN C++ code
/// uses its own thread pool for internal parallelism.
class TtsEngine {
  MnnTtsBindings? _bindings;
  Pointer<Void>? _enginePtr;
  final TamilTokenizer _tokenizer = TamilTokenizer();
  bool _isInitialized = false;
  String? _modelPath;

  bool get isInitialized => _isInitialized;
  bool get isNativeAvailable => _enginePtr != null && _enginePtr != nullptr;
  TamilTokenizer get tokenizer => _tokenizer;

  /// Initialize the TTS engine
  /// Copies the model from assets to a writable directory and loads it
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Load tokenizer
    await _tokenizer.load();
    debugPrint('TTS Tokenizer loaded: ${_tokenizer.vocabSize} tokens');

    // Copy model to writable location
    _modelPath = await _copyAssetToFile(
      'assets/models/model_fp16_int8.mnn',
      'model_fp16_int8.mnn',
    );
    debugPrint('TTS Model copied to: $_modelPath');

    // Initialize native engine via FFI
    try {
      _bindings = MnnTtsBindings();
      final pathPtr = _modelPath!.toNativeUtf8();
      final rawPtr = _bindings!.createEngine(pathPtr, 4);
      calloc.free(pathPtr);

      if (rawPtr == nullptr) {
        debugPrint('TTS Engine creation returned null');
        throw Exception('Failed to create MNN TTS engine');
      }

      _enginePtr = rawPtr.cast<Void>();
      _isInitialized = true;
      debugPrint('TTS Engine initialized successfully (VITS/mms-tts-tam)');
    } catch (e) {
      debugPrint('TTS Engine FFI initialization failed: $e');
      debugPrint('Falling back to software synthesis mode');
      _isInitialized = true;
      _enginePtr = null;
    }
  }

  /// Maximum tokens per chunk to keep each FFI call short and avoid ANR.
  /// ~1200 tokens ≈ 2-3s inference on a mid-range phone CPU.
  static const int _maxTokensPerChunk = 1200;

  /// Crossfade length in samples (25 ms at 16 kHz) to smooth chunk boundaries.
  static const int _crossfadeSamples = 400;

  /// Amplitude threshold below which samples are considered silence.
  static const double _silenceThreshold = 0.01;

  /// Islamic honorific abbreviations commonly used in Tamil hadith texts.
  /// Expanded before tokenization so the TTS model pronounces the full form.
  static const Map<String, String> _honorificExpansions = {
    'ஸல்': 'ஸல்லலாஹு அலைஹிவஸல்லம்',
    'அலை': 'அலைஹிவஸல்லம்',
    'ரலி': 'ரலியல்லாஹு அன்ஹா',
  };

  /// Expand abbreviated honorifics so the model speaks the full phrase.
  /// Only expands when the abbreviation appears as a standalone word
  /// (surrounded by whitespace / punctuation / parentheses).
  String _expandHonorifics(String text) {
    String result = text;
    for (final entry in _honorificExpansions.entries) {
      // Word-boundary: preceded/followed by space, punctuation, parens, or start/end
      final pattern = RegExp(
        r'(?<=[\s\(\)\[\].,;:!?\u0964]|^)' +
        RegExp.escape(entry.key) +
        r'(?=[\s\(\)\[\].,;:!?\u0964]|$)',
      );
      result = result.replaceAll(pattern, entry.value);
    }
    return result;
  }

  /// Synthesize Tamil text to PCM audio (Float32, 16kHz mono)
  /// Returns raw PCM float32 samples.
  ///
  /// Long texts are split into sentence-sized chunks so that each native
  /// FFI call finishes quickly. An async yield between chunks keeps the
  /// UI thread responsive and prevents ANR.
  Future<Float32List?> synthesize(String text, {
    double noiseScale = VitsConfig.noiseScale,
    double lengthScale = VitsConfig.lengthScale,
    double noiseScaleW = VitsConfig.noiseScaleW,
  }) async {
    if (!_isInitialized) {
      throw StateError('TTS engine not initialized');
    }

    // Expand honorific abbreviations before tokenization
    final normalizedText = _expandHonorifics(text);

    // Tokenize the text (add_blank is handled by tokenizer)
    final tokenIds = _tokenizer.tokenize(normalizedText);
    if (tokenIds.isEmpty) {
      debugPrint('TTS: Empty token sequence for text: $text');
      return null;
    }

    debugPrint('TTS: Tokenized ${normalizedText.length} chars -> ${tokenIds.length} tokens (with blanks)');

    // If native engine is available, use it
    if (isNativeAvailable && _bindings != null) {
      // Short input – synthesize directly
      if (tokenIds.length <= _maxTokensPerChunk) {
        return _synthesizeNative(tokenIds, noiseScale, lengthScale, noiseScaleW);
      }
      // Long input – split into chunks to avoid ANR
      return _synthesizeChunked(normalizedText, noiseScale, lengthScale, noiseScaleW);
    }

    // Software fallback: generate placeholder audio
    return _generatePlaceholderAudio(tokenIds.length);
  }

  /// Split [text] into sentence-level chunks, synthesize each one separately
  /// and join with crossfade. An async yield between chunks lets the main
  /// isolate process UI events so the system won't fire an ANR.
  Future<Float32List?> _synthesizeChunked(
    String text,
    double noiseScale,
    double lengthScale,
    double noiseScaleW,
  ) async {
    final sentences = _splitIntoSentences(text);
    debugPrint('TTS: Split text into ${sentences.length} chunks for synthesis');

    final List<Float32List> audioParts = [];

    for (int i = 0; i < sentences.length; i++) {
      final chunk = sentences[i];
      if (chunk.trim().isEmpty) continue;

      final chunkTokens = _tokenizer.tokenize(chunk);
      if (chunkTokens.isEmpty) continue;

      debugPrint('TTS: Chunk ${i + 1}/${sentences.length}: '
          '${chunk.length} chars, ${chunkTokens.length} tokens');

      // Yield to the event loop so the UI stays responsive
      await Future<void>.delayed(Duration.zero);

      final audio = _synthesizeNative(
        chunkTokens, noiseScale, lengthScale, noiseScaleW,
      );
      if (audio != null && audio.isNotEmpty) {
        // Trim leading/trailing silence so chunks join cleanly
        final trimmed = _trimSilence(audio);
        if (trimmed.isNotEmpty) audioParts.add(trimmed);
      }
    }

    if (audioParts.isEmpty) return null;
    if (audioParts.length == 1) return audioParts.first;

    // Crossfade-join all chunks into a single buffer
    return _crossfadeJoin(audioParts);
  }

  /// Remove leading and trailing near-silence samples from [audio].
  Float32List _trimSilence(Float32List audio) {
    int start = 0;
    int end = audio.length;

    // Scan forward past silence
    while (start < end && audio[start].abs() < _silenceThreshold) {
      start++;
    }
    // Scan backward past silence
    while (end > start && audio[end - 1].abs() < _silenceThreshold) {
      end--;
    }

    // Keep a tiny ramp margin (64 samples ≈ 4 ms) so crossfade has material
    start = (start - 64).clamp(0, audio.length);
    end = (end + 64).clamp(0, audio.length);

    if (start >= end) return Float32List(0);
    return Float32List.sublistView(audio, start, end);
  }

  /// Join audio chunks using a short linear crossfade to eliminate gaps.
  Float32List _crossfadeJoin(List<Float32List> parts) {
    final int fade = _crossfadeSamples;

    // Calculate total length accounting for overlaps
    int totalLen = parts[0].length;
    for (int i = 1; i < parts.length; i++) {
      final overlap = min(fade, min(parts[i - 1].length, parts[i].length));
      totalLen += parts[i].length - overlap;
    }

    final combined = Float32List(totalLen);

    // Copy first part
    combined.setRange(0, parts[0].length, parts[0]);
    int writePos = parts[0].length;

    for (int p = 1; p < parts.length; p++) {
      final prev = parts[p - 1];
      final curr = parts[p];
      final overlap = min(fade, min(prev.length, curr.length));

      // Back up write position by overlap
      writePos -= overlap;

      // Crossfade the overlapping region
      for (int i = 0; i < overlap; i++) {
        final t = i / overlap; // 0 → 1
        final fadeOut = combined[writePos + i] * (1.0 - t);
        final fadeIn = curr[i] * t;
        combined[writePos + i] = fadeOut + fadeIn;
      }

      // Copy the rest of the current chunk after the overlap
      if (overlap < curr.length) {
        combined.setRange(
          writePos + overlap,
          writePos + curr.length,
          curr,
          overlap,
        );
      }
      writePos += curr.length;
    }

    final actualLen = writePos.clamp(0, combined.length);
    debugPrint('TTS: Crossfade-joined ${parts.length} chunks -> '
        '$actualLen samples (${(actualLen / VitsConfig.sampleRate).toStringAsFixed(2)}s)');
    return Float32List.sublistView(combined, 0, actualLen);
  }

  /// Split Tamil text into sentence-sized pieces.
  /// Splits on common Tamil / Indic punctuation and newlines, then further
  /// subdivides any sentence whose token count exceeds [_maxTokensPerChunk].
  List<String> _splitIntoSentences(String text) {
    // Split on sentence-ending punctuation or newlines
    final raw = text.split(RegExp(r'(?<=[.!?।\n])\s*'));

    final List<String> result = [];
    for (final sentence in raw) {
      if (sentence.trim().isEmpty) continue;
      final tokens = _tokenizer.tokenize(sentence);
      if (tokens.length <= _maxTokensPerChunk) {
        result.add(sentence);
      } else {
        // Further split long sentences on commas / semicolons
        final parts = sentence.split(RegExp(r'(?<=[,;:])\s*'));
        final StringBuffer buf = StringBuffer();
        int bufTokens = 0;
        for (final part in parts) {
          final pTokens = _tokenizer.tokenize(part).length;
          if (bufTokens + pTokens > _maxTokensPerChunk && bufTokens > 0) {
            result.add(buf.toString());
            buf.clear();
            bufTokens = 0;
          }
          buf.write(part);
          bufTokens += pTokens;
        }
        if (buf.isNotEmpty) result.add(buf.toString());
      }
    }
    return result;
  }

  /// Run native MNN VITS inference on the main isolate.
  /// The MNN Module API uses its own thread pool internally, so this
  /// is already parallelized at the C++ level.
  Float32List? _synthesizeNative(
    List<int> tokenIds,
    double noiseScale,
    double lengthScale,
    double noiseScaleW,
  ) {
    final engine = _enginePtr!.cast<MNN_TTS_Engine>();

    // Allocate native input buffer (int64 for FFI, cast to int32 in C++)
    final inputPtr = calloc<Int64>(tokenIds.length);
    for (int i = 0; i < tokenIds.length; i++) {
      inputPtr[i] = tokenIds[i];
    }

    // Allocate output pointers
    final outputDataPtr = calloc<Pointer<Float>>();
    final outputLenPtr = calloc<IntPtr>();

    try {
      // Run VITS inference with all parameters
      final result = _bindings!.synthesize(
        engine,
        inputPtr,
        tokenIds.length,
        noiseScale,
        lengthScale,
        noiseScaleW,
        outputDataPtr,
        outputLenPtr,
      );

      if (result == 0) {
        // TTS_SUCCESS
        final outputLen = outputLenPtr.value;
        final outputPtr = outputDataPtr.value;

        if (outputLen > 0 && outputPtr != nullptr) {
          // Zero-copy view then bulk-copy to Dart-managed buffer
          final nativeView = outputPtr.asTypedList(outputLen);
          final audioData = Float32List.fromList(nativeView);
          _bindings!.freeOutput(outputPtr);
          debugPrint('TTS: Synthesized $outputLen samples (${(outputLen / VitsConfig.sampleRate).toStringAsFixed(2)}s)');
          return audioData;
        }
      } else {
        final errorMsg = _bindings!.getLastError(engine).toDartString();
        debugPrint('TTS synthesis error ($result): $errorMsg');
      }

      return null;
    } catch (e) {
      debugPrint('TTS native inference error: $e');
      return null;
    } finally {
      calloc.free(inputPtr);
      calloc.free(outputDataPtr);
      calloc.free(outputLenPtr);
    }
  }

  /// Generate placeholder audio (sine wave) when native engine is unavailable
  Float32List _generatePlaceholderAudio(int tokenCount) {
    const sampleRate = VitsConfig.sampleRate;
    // Approximate duration: ~100ms per token
    final durationSamples = (tokenCount * 0.1 * sampleRate).toInt();
    final audio = Float32List(durationSamples);

    for (int i = 0; i < durationSamples; i++) {
      final t = i / sampleRate;
      audio[i] = 0.3 * sin(2 * pi * 440 * t) * exp(-t * 2);
    }

    return audio;
  }

  /// Copy an asset file to the app's documents directory
  Future<String> _copyAssetToFile(String assetPath, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, fileName));

    if (!await file.exists()) {
      final data = await rootBundle.load(assetPath);
      await file.writeAsBytes(data.buffer.asUint8List());
    }

    return file.path;
  }

  /// Dispose the engine
  void dispose() {
    if (_enginePtr != null && _bindings != null) {
      _bindings!.destroyEngine(_enginePtr!.cast());
      _enginePtr = null;
    }
    _isInitialized = false;
  }
}
