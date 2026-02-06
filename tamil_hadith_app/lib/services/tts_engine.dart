import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tokenizer.dart';
import 'tts_isolate.dart';

/// VITS inference parameters from mms-tts-tam config.json
class VitsConfig {
  static const double noiseScale = 0.667;
  static const double lengthScale = 1.0;
  static const double noiseScaleW = 0.8;
  static const int sampleRate = 16000;
}

/// High-level TTS engine service for Tamil text-to-speech.
///
/// All MNN inference runs in a **background isolate** so the UI thread
/// is never blocked. The public API is unchanged --- callers still use
/// [synthesizeStreaming] to get a stream of PCM chunks.
class TtsEngine {
  final TtsIsolateRunner _runner = TtsIsolateRunner();
  final TamilTokenizer _tokenizer = TamilTokenizer();
  bool _isInitialized = false;
  bool _initializing = false;

  bool get isInitialized => _isInitialized;
  bool get isNativeAvailable => _runner.isNativeAvailable;
  TamilTokenizer get tokenizer => _tokenizer;

  /// Initialize the TTS engine.
  ///
  /// 1. Copies tokens.txt from assets to a file (isolate cannot use rootBundle)
  /// 2. Spawns a background isolate that loads the model + tokenizer
  /// 3. Returns when the engine is ready
  Future<void> initialize() async {
    if (_isInitialized || _initializing) return;
    _initializing = true;

    try {
      // Load tokenizer on main isolate too (for vocabSize getter etc.)
      await _tokenizer.load();
      debugPrint('TTS Tokenizer loaded: ${_tokenizer.vocabSize} tokens');

      final dir = await getApplicationDocumentsDirectory();
      final modelPath = p.join(dir.path, 'models', 'model_fp32.mnn');

      if (!File(modelPath).existsSync()) {
        debugPrint('TTS: Model file not found at $modelPath');
        _isInitialized = true;
        return;
      }
      debugPrint('TTS Model found at: $modelPath');

      // Copy tokens.txt from assets to documents so the isolate can read it
      final tokensPath = p.join(dir.path, 'models', 'tokens.txt');
      if (!File(tokensPath).existsSync()) {
        final data = await rootBundle.loadString('assets/models/tokens.txt');
        await File(tokensPath).writeAsString(data, flush: true);
      }

      // Spawn the background isolate and init the engine inside it
      final ready = await _runner.start(modelPath, tokensPath);
      debugPrint('TTS Engine initialized in background isolate '
          '(native=${ready ? "yes" : "no"})');

      _isInitialized = true;
    } catch (e) {
      debugPrint('TTS Engine initialization failed: $e');
      _isInitialized = true;
    } finally {
      _initializing = false;
    }
  }

  /// Cancel any in-progress streaming synthesis.
  void cancelSynthesis() {
    _runner.cancel();
  }

  /// Stream-synthesize Tamil text, yielding each chunk audio as soon as
  /// it is ready. **Runs entirely in a background isolate** so the UI
  /// thread is never blocked.
  ///
  /// Each emitted [Float32List] is a trimmed, crossfaded PCM chunk.
  Stream<Float32List> synthesizeStreaming(String text, {
    double noiseScale = VitsConfig.noiseScale,
    double lengthScale = VitsConfig.lengthScale,
    double noiseScaleW = VitsConfig.noiseScaleW,
  }) {
    if (!_isInitialized) {
      return Stream.error(StateError('TTS engine not initialized'));
    }

    if (!isNativeAvailable) {
      return Stream.value(_generatePlaceholderAudio(100));
    }

    return _runner.synthesizeStreaming(text);
  }

  /// Synthesize the full text and return a single combined PCM buffer.
  /// Still runs in the background isolate --- collects all chunks.
  Future<Float32List?> synthesize(String text, {
    double noiseScale = VitsConfig.noiseScale,
    double lengthScale = VitsConfig.lengthScale,
    double noiseScaleW = VitsConfig.noiseScaleW,
  }) async {
    if (!_isInitialized) {
      throw StateError('TTS engine not initialized');
    }

    if (!isNativeAvailable) {
      return _generatePlaceholderAudio(100);
    }

    final chunks = <Float32List>[];
    await for (final chunk in _runner.synthesizeStreaming(text)) {
      chunks.add(chunk);
    }

    if (chunks.isEmpty) return null;
    if (chunks.length == 1) return chunks.first;

    final totalLen = chunks.fold<int>(0, (sum, c) => sum + c.length);
    final combined = Float32List(totalLen);
    int offset = 0;
    for (final chunk in chunks) {
      combined.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return combined;
  }

  /// Generate placeholder audio (sine wave) when native engine is unavailable
  Float32List _generatePlaceholderAudio(int tokenCount) {
    const sampleRate = VitsConfig.sampleRate;
    final durationSamples = (tokenCount * 0.1 * sampleRate).toInt();
    final audio = Float32List(durationSamples);
    for (int i = 0; i < durationSamples; i++) {
      final t = i / sampleRate;
      audio[i] = 0.3 * sin(2 * pi * 440 * t) * exp(-t * 2);
    }
    return audio;
  }

  /// Dispose the engine and kill the background isolate.
  void dispose() {
    _runner.dispose();
    _isInitialized = false;
  }
}
