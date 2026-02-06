import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'mnn_tts_bindings.dart';
import 'tokenizer.dart';

// ══════════════════════════════════════════════════════════════
// Messages between main isolate and TTS worker isolate
// ══════════════════════════════════════════════════════════════

/// Sent from main → worker to initialise the engine.
class _InitRequest {
  final String modelPath;
  final String tokensPath;
  _InitRequest(this.modelPath, this.tokensPath);
}

/// Sent from main → worker for a streaming synthesis job.
class _SynthRequest {
  final int id;
  final String text;
  _SynthRequest(this.id, this.text);
}

/// Sent from main → worker to cancel the current job.
class _CancelRequest {
  const _CancelRequest();
}

/// Sent from worker → main: one audio chunk.
class TtsChunk {
  final int requestId;
  final Float32List audio;
  TtsChunk(this.requestId, this.audio);
}

/// Sent from worker → main: job finished (no more chunks).
class TtsDone {
  final int requestId;
  TtsDone(this.requestId);
}

/// Sent from worker → main: engine ready.
class TtsReady {
  final bool nativeAvailable;
  TtsReady(this.nativeAvailable);
}

/// Sent from worker → main: error.
class TtsError {
  final int requestId;
  final String message;
  TtsError(this.requestId, this.message);
}

// ══════════════════════════════════════════════════════════════
// TtsIsolateRunner — manages the long-lived background isolate
// ══════════════════════════════════════════════════════════════

/// Runs all MNN TTS inference in a dedicated background isolate
/// so the UI thread is never blocked.
///
/// Usage:
/// ```dart
/// final runner = TtsIsolateRunner();
/// await runner.start(modelPath, tokensPath);
/// await for (final chunk in runner.synthesizeStreaming('text')) { ... }
/// runner.cancel();
/// runner.dispose();
/// ```
class TtsIsolateRunner {
  Isolate? _isolate;
  SendPort? _sendPort;
  final _readyCompleter = Completer<bool>();
  int _nextRequestId = 0;
  StreamController<Float32List>? _currentStream;
  int _currentRequestId = -1;

  bool _nativeAvailable = false;
  bool get isNativeAvailable => _nativeAvailable;
  bool get isRunning => _isolate != null;

  /// Spawn the background isolate and initialise the TTS engine inside it.
  Future<bool> start(String modelPath, String tokensPath) async {
    if (_isolate != null) return _nativeAvailable;

    final receivePort = ReceivePort();

    _isolate = await Isolate.spawn(
      _isolateEntry,
      receivePort.sendPort,
    );

    final completer = Completer<SendPort>();

    receivePort.listen((message) {
      if (message is SendPort) {
        completer.complete(message);
      } else if (message is TtsReady) {
        _nativeAvailable = message.nativeAvailable;
        if (!_readyCompleter.isCompleted) _readyCompleter.complete(message.nativeAvailable);
      } else if (message is TtsChunk) {
        if (message.requestId == _currentRequestId) {
          _currentStream?.add(message.audio);
        }
      } else if (message is TtsDone) {
        if (message.requestId == _currentRequestId) {
          _currentStream?.close();
          _currentStream = null;
        }
      } else if (message is TtsError) {
        debugPrint('TTS isolate error: ${message.message}');
        if (message.requestId == _currentRequestId) {
          _currentStream?.addError(Exception(message.message));
          _currentStream?.close();
          _currentStream = null;
        }
      }
    });

    _sendPort = await completer.future;

    // Send init request
    _sendPort!.send(_InitRequest(modelPath, tokensPath));

    return _readyCompleter.future;
  }

  /// Start streaming synthesis. Returns a stream of PCM Float32List chunks.
  /// Each chunk can be played immediately while the next is being synthesized.
  Stream<Float32List> synthesizeStreaming(String text) {
    if (_sendPort == null) {
      return Stream.error(StateError('TTS isolate not started'));
    }

    // Cancel any in-flight job
    cancel();

    _currentRequestId = _nextRequestId++;
    _currentStream = StreamController<Float32List>();

    _sendPort!.send(_SynthRequest(_currentRequestId, text));

    return _currentStream!.stream;
  }

  /// Cancel the current synthesis job.
  void cancel() {
    _sendPort?.send(const _CancelRequest());
    _currentStream?.close();
    _currentStream = null;
  }

  /// Shut down the isolate.
  void dispose() {
    cancel();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
  }
}

// ══════════════════════════════════════════════════════════════
// Isolate entry point — runs entirely in the background isolate
// ══════════════════════════════════════════════════════════════

void _isolateEntry(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  final worker = _TtsWorker(mainSendPort);

  receivePort.listen((message) {
    if (message is _InitRequest) {
      worker.init(message.modelPath, message.tokensPath);
    } else if (message is _SynthRequest) {
      worker.synthesize(message.id, message.text);
    } else if (message is _CancelRequest) {
      worker.cancelled = true;
    }
  });
}

/// The actual TTS worker that lives inside the background isolate.
/// It owns the native engine pointer, tokenizer, and does all FFI calls.
class _TtsWorker {
  final SendPort _mainPort;

  MnnTtsBindings? _bindings;
  Pointer<Void>? _enginePtr;
  final TamilTokenizer _tokenizer = TamilTokenizer();
  bool _isInitialized = false;
  bool cancelled = false;

  bool get _isNativeAvailable => _enginePtr != null && _enginePtr != nullptr;

  static const int _maxTokensPerChunk = 250;
  static const int _crossfadeSamples = 400;
  static const double _silenceThreshold = 0.01;

  // ── Normalization (same as TtsEngine) ──

  static final RegExp _parenAbbrevPattern = RegExp(
    r'\(\s*(ஸல்|அலை|ரலி)\s*\)',
  );

  static const Map<String, String> _honorificExpansions = {
    'ஸல்': 'ஸல்லலாஹு அலைஹி வஸல்லம்',
    'அலை': 'அலைஹிஸ்ஸலாம்',
    'ரலி': 'ரலியல்லாஹு அன்ஹு',
  };

  static const Map<String, String> _pronunciationFixes = {
    'அல்லாஹ்': 'அல்லாஹு',
    'ரஸூல்': 'ரசூல்',
    'ஹதீஸ்': 'ஹதீது',
    'இப்னு': 'இப்னு',
    'அப்துல்லாஹ்': 'அப்துல்லாஹி',
    'உமர்': 'உமரு',
    'உஸ்மான்': 'உதுமான்',
    'ஸஹீஹ்': 'ஸஹீஹு',
    'ஃபி': 'ஃபி',
  };

  static final RegExp _hadithNumPattern = RegExp(
    r'ஹதீது\s*\d+|ஹதீஸ்\s*\d+|எண்\s*:\s*\d+',
  );

  static const Map<String, String> _narrationPauses = {
    'என நபி': 'என நபி ... ',
    'கூறினார்கள்': 'கூறினார்கள் ... ',
    'அறிவித்தார்கள்': 'அறிவித்தார்கள் ... ',
    'என்று கூறினார்': 'என்று கூறினார் ... ',
    'என அறிவித்தார்': 'என அறிவித்தார் ... ',
    'அவர்கள் கூறினார்': 'அவர்கள் கூறினார் ... ',
  };

  static final List<RegExp> _waqfPatterns = [
    RegExp(r'என்று நபி\s*ஸல்லலாஹு அலைஹி வஸல்லம்\s*அவர்கள்'),
    RegExp(r'நபி\s*ஸல்லலாஹு அலைஹி வஸல்லம்\s*கூறினார்'),
    RegExp(r'அல்லாஹுவின் தூதர்.*?கூறினார்'),
    RegExp(r'என்று அறிவித்தார்'),
    RegExp(r'என அறிவித்தார்'),
    RegExp(r'என்று கூறினார்'),
  ];

  static const int _waqfPauseMs = 400;
  static const int _sampleRate = 16000;

  _TtsWorker(this._mainPort);

  void init(String modelPath, String tokensPath) {
    try {
      // Load tokenizer from file (no rootBundle in isolates)
      _tokenizer.loadFromFile(tokensPath);

      if (!File(modelPath).existsSync()) {
        _mainPort.send(TtsReady(false));
        _isInitialized = true;
        return;
      }

      // Initialize native engine via FFI
      _bindings = MnnTtsBindings();
      final pathPtr = modelPath.toNativeUtf8();
      // 2 threads: saves battery & heat for a reading app (not latency-critical)
      final rawPtr = _bindings!.createEngine(pathPtr, 2);
      calloc.free(pathPtr);

      if (rawPtr == nullptr) {
        _enginePtr = null;
      } else {
        _enginePtr = rawPtr.cast<Void>();
      }

      _isInitialized = true;
      _mainPort.send(TtsReady(_isNativeAvailable));
    } catch (e) {
      _isInitialized = true;
      _enginePtr = null;
      _mainPort.send(TtsReady(false));
    }
  }

  void synthesize(int requestId, String text) {
    cancelled = false;

    try {
      if (!_isInitialized || !_isNativeAvailable) {
        _mainPort.send(TtsError(requestId, 'Engine not available'));
        return;
      }

      final normalizedText = _normalizeText(text);
      if (normalizedText.isEmpty) {
        debugPrint('TTS-Isolate: normalized text is EMPTY');
        _mainPort.send(TtsDone(requestId));
        return;
      }

      // Always stream chunk-by-chunk for responsive playback
      final sentences = _splitIntoSentences(normalizedText);
      debugPrint('TTS-Isolate: ${sentences.length} chunks from ${normalizedText.length} chars');
      Float32List? prevTail;

      for (int i = 0; i < sentences.length; i++) {
        if (cancelled) break;

        final chunk = sentences[i];
        if (chunk.trim().isEmpty) continue;
        final chunkTokens = _tokenizer.tokenize(chunk);
        if (chunkTokens.isEmpty) continue;

        debugPrint('TTS-Isolate: chunk ${i+1}/${sentences.length} (${chunkTokens.length} tokens)');
        final raw = _synthesizeNative(chunkTokens);
        if (raw == null || raw.isEmpty) {
          debugPrint('TTS-Isolate: chunk ${i+1} synthesize returned null/empty');
          continue;
        }

        final trimmed = _trimSilence(raw);
        if (trimmed.isEmpty) {
          debugPrint('TTS-Isolate: chunk ${i+1} all silence after trim');
          continue;
        }
        debugPrint('TTS-Isolate: chunk ${i+1} raw=${raw.length} trimmed=${trimmed.length} (${(trimmed.length/16000).toStringAsFixed(2)}s)');

        if (prevTail != null) {
          final overlap = min(_crossfadeSamples, min(prevTail.length, trimmed.length));
          for (int s = 0; s < overlap; s++) {
            final t = s / overlap;
            trimmed[s] = prevTail[s] * (1.0 - t) + trimmed[s] * t;
          }
        }

        final tailLen = min(_crossfadeSamples, trimmed.length);
        prevTail = Float32List.sublistView(trimmed, trimmed.length - tailLen);

        Float32List emitAudio;
        if (i < sentences.length - 1 && trimmed.length > tailLen) {
          emitAudio = Float32List.sublistView(trimmed, 0, trimmed.length - tailLen);
        } else {
          emitAudio = trimmed;
        }

        if (_shouldInsertWaqf(chunk)) {
          emitAudio = _appendSilence(emitAudio, _waqfPauseMs);
        }

        // Send chunk back to main isolate via TransferableTypedData for zero-copy
        _mainPort.send(TtsChunk(requestId, emitAudio));
      }

      prevTail = null;
      _mainPort.send(TtsDone(requestId));
    } catch (e) {
      _mainPort.send(TtsError(requestId, e.toString()));
    }
  }

  // ── Text normalization (identical to TtsEngine) ──

  String _normalizeText(String text) {
    String result = TamilTokenizer.normalize(text);
    result = result.replaceAll(_hadithNumPattern, '');
    result = result.replaceAllMapped(_parenAbbrevPattern, (m) => ' ${m.group(1)!} ');
    for (final entry in _honorificExpansions.entries) {
      final pattern = RegExp(
        r'(?<=[\s,;:.!?\u0964]|^)' + RegExp.escape(entry.key) + r'(?=[\s,;:.!?\u0964]|$)',
      );
      result = result.replaceAll(pattern, entry.value);
    }
    for (final entry in _pronunciationFixes.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    for (final entry in _narrationPauses.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    result = result.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return result;
  }

  // ── Sentence splitting ──

  List<String> _splitIntoSentences(String text) {
    // Step 1: split on sentence-ending punctuation
    final raw = text.split(RegExp(r'(?<=[.!?।\n])\s*'));
    final List<String> result = [];

    for (final sentence in raw) {
      if (sentence.trim().isEmpty) continue;
      final tokens = _tokenizer.tokenize(sentence);
      if (tokens.length <= _maxTokensPerChunk) {
        result.add(sentence);
        continue;
      }

      // Step 2: split long sentences on commas / semicolons / colons
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
      if (buf.isNotEmpty) {
        final remaining = buf.toString();
        final remTokens = _tokenizer.tokenize(remaining).length;
        if (remTokens <= _maxTokensPerChunk) {
          result.add(remaining);
        } else {
          // Step 3: split on word boundaries (spaces)
          _splitByWords(remaining, result);
        }
      }
    }
    return result;
  }

  /// Final fallback: split text on spaces to stay within chunk limit.
  void _splitByWords(String text, List<String> out) {
    final words = text.split(' ');
    final StringBuffer buf = StringBuffer();
    int bufTokens = 0;
    for (final word in words) {
      final wTokens = _tokenizer.tokenize(word).length;
      if (bufTokens + wTokens > _maxTokensPerChunk && bufTokens > 0) {
        out.add(buf.toString().trim());
        buf.clear();
        bufTokens = 0;
      }
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(word);
      bufTokens += wTokens;
    }
    if (buf.isNotEmpty) out.add(buf.toString().trim());
  }

  // ── Native FFI inference ──

  Float32List? _synthesizeNative(List<int> tokenIds) {
    final engine = _enginePtr!.cast<MNN_TTS_Engine>();
    final inputPtr = calloc<Int64>(tokenIds.length);
    for (int i = 0; i < tokenIds.length; i++) {
      inputPtr[i] = tokenIds[i];
    }
    final outputDataPtr = calloc<Pointer<Float>>();
    final outputLenPtr = calloc<IntPtr>();

    try {
      final result = _bindings!.synthesize(
        engine, inputPtr, tokenIds.length,
        0.667, 1.0, 0.8,  // noiseScale, lengthScale, noiseScaleW
        outputDataPtr, outputLenPtr,
      );

      if (result == 0) {
        final outputLen = outputLenPtr.value;
        final outputPtr = outputDataPtr.value;
        if (outputLen > 0 && outputPtr != nullptr) {
          final nativeView = outputPtr.asTypedList(outputLen);
          final audioData = Float32List.fromList(nativeView);
          // No freeOutput call needed — buffer is engine-owned (reusable).
          return audioData;
        }
      }
      return null;
    } finally {
      calloc.free(inputPtr);
      calloc.free(outputDataPtr);
      calloc.free(outputLenPtr);
    }
  }

  // ── Audio helpers ──

  Float32List _trimSilence(Float32List audio) {
    int start = 0;
    int end = audio.length;
    while (start < end && audio[start].abs() < _silenceThreshold) start++;
    while (end > start && audio[end - 1].abs() < _silenceThreshold) end--;
    start = (start - 64).clamp(0, audio.length);
    end = (end + 64).clamp(0, audio.length);
    if (start >= end) return Float32List(0);
    return Float32List.sublistView(audio, start, end);
  }

  bool _shouldInsertWaqf(String text) {
    for (final pattern in _waqfPatterns) {
      if (pattern.hasMatch(text)) return true;
    }
    return false;
  }

  Float32List _appendSilence(Float32List audio, int ms) {
    final silenceSamples = (_sampleRate * ms / 1000).toInt();
    final result = Float32List(audio.length + silenceSamples);
    result.setRange(0, audio.length, audio);
    return result;
  }
}
