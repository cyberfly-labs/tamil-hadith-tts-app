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
  /// ~800 tokens ≈ 1-2s inference on mid-range phone CPU.
  static const int _maxTokensPerChunk = 800;

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

    // Tokenize the text (add_blank is handled by tokenizer)
    final tokenIds = _tokenizer.tokenize(text);
    if (tokenIds.isEmpty) {
      debugPrint('TTS: Empty token sequence for text: $text');
      return null;
    }

    debugPrint('TTS: Tokenized ${text.length} chars -> ${tokenIds.length} tokens (with blanks)');

    // If native engine is available, use it
    if (isNativeAvailable && _bindings != null) {
      // Short input – synthesize directly
      if (tokenIds.length <= _maxTokensPerChunk) {
        return _synthesizeNative(tokenIds, noiseScale, lengthScale, noiseScaleW);
      }
      // Long input – split into chunks to avoid ANR
      return _synthesizeChunked(text, noiseScale, lengthScale, noiseScaleW);
    }

    // Software fallback: generate placeholder audio
    return _generatePlaceholderAudio(tokenIds.length);
  }

  /// Split [text] into sentence-level chunks, synthesize each one separately
  /// and concatenate the PCM results. An async yield between chunks lets the
  /// main isolate process UI events so the system won't fire an ANR.
  Future<Float32List?> _synthesizeChunked(
    String text,
    double noiseScale,
    double lengthScale,
    double noiseScaleW,
  ) async {
    final sentences = _splitIntoSentences(text);
    debugPrint('TTS: Split text into ${sentences.length} chunks for synthesis');

    final List<Float32List> audioParts = [];
    int totalSamples = 0;

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
        audioParts.add(audio);
        totalSamples += audio.length;
      }
    }

    if (audioParts.isEmpty) return null;
    if (audioParts.length == 1) return audioParts.first;

    // Concatenate all chunks into a single buffer
    final combined = Float32List(totalSamples);
    int offset = 0;
    for (final part in audioParts) {
      combined.setRange(offset, offset + part.length, part);
      offset += part.length;
    }

    debugPrint('TTS: Combined ${audioParts.length} chunks -> '
        '$totalSamples samples (${(totalSamples / VitsConfig.sampleRate).toStringAsFixed(2)}s)');
    return combined;
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
          // Copy output to Dart-managed buffer
          final audioData = Float32List(outputLen);
          for (int i = 0; i < outputLen; i++) {
            audioData[i] = outputPtr[i];
          }
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
