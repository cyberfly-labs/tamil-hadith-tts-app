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
  static const int _sampleRate = 16000;

  // ══════════════════════════════════════════════════════════════
  // 1. ABBREVIATION EXPANSION — expand Islamic honorific abbreviations
  //    Must run FIRST so later rules can match the expanded forms.
  // ══════════════════════════════════════════════════════════════

  /// Parenthesized abbreviations: நபி(ஸல்), அலி(ரலி), etc.
  static final RegExp _parenAbbrevPattern = RegExp(
    r'\(\s*(ஸல்|அலை|ரலி|ரழி)\s*\)',
  );

  /// Standalone abbreviations (word-boundary aware)
  static const Map<String, String> _honorificExpansions = {
    'ஸல்':  'ஸல்லல்லாஹு அலைஹி வசல்லம்',
    'அலை':  'அலைஹிஸ்ஸலாம்',
    'ரலி':  'ரழியல்லாஹு அன்ஹு',
    'ரழி':  'ரழியல்லாஹு அன்ஹு',
  };

  // ══════════════════════════════════════════════════════════════
  // 2. ARABIC / ISLAMIC PRONUNCIATION CORRECTIONS
  //    Tamil TTS model mispronounces Arabic-origin words.
  //    Minimal phonetic nudges — NOT aggressive rewriting.
  // ══════════════════════════════════════════════════════════════

  static const Map<String, String> _pronunciationFixes = {
    // ── Name endings: remove trailing -u that model adds ──
    'முஹம்மது':     'முஹம்மத்',
    'அஹ்மது':      'அஹ்மத்',
    // ── Common Arabic terms ──
    'ரஸூல்':       'ரசூல்',
    'ஹதீஸ்':       'ஹதீஸ்',
    'அப்துல்லாஹ்':  'அப்துல்லாஹ்',
    'ஸஹீஹ்':       'ஸஹீஹ்',
    'ஸஹீஹ':        'ஸஹீஹ்',
    // ── Long vowel enforcement ──
    'அல்லா ':      'அல்லாஹ் ',    // incomplete → proper ending
    'ரஹ்மான':      'ரஹ்மான்',
    'ரஹீம':        'ரஹீம்',
    // ── Common mispronounced names ──
    'இப்ராஹிம்':   'இப்ராஹீம்',
    'இஸ்மாயில்':   'இஸ்மாஈல்',
    'ஸுலைமான்':    'ஸுலைமான்',
  };

  // ══════════════════════════════════════════════════════════════
  // 3. SMART PAUSE INSERTION — makes speech sound human
  //    Add comma AFTER narration flow words.
  //    Add comma BEFORE contrast/conjunction words.
  // ══════════════════════════════════════════════════════════════

  /// Words after which a comma is inserted (narration flow)
  static const List<String> _pauseAfterWords = [
    'கூறினார்கள்',
    'அறிவித்தார்கள்',
    'கூறினார்',
    'அறிவித்தார்',
    'என்று',
    'ஆக',
    'பின்னர்',
    'மேலும்',
    'அதனால்',
    'இதனால்',
    'எனவே',
    'அப்போது',
    'பிறகு',
    'ஆகவே',
    'இறுதியாக',
    'அடுத்து',
  ];

  /// Words before which a comma is inserted (contrast/shift)
  static const List<String> _pauseBeforeWords = [
    'ஆனால்',
    'எனினும்',
    'அல்லது',
    'ஆயினும்',
    'இருப்பினும்',
  ];

  // ══════════════════════════════════════════════════════════════
  // 4. SACRED REFERENCE PAUSES — respectful slight pause before
  //    mentions of Allah, Prophet, Rasool
  // ══════════════════════════════════════════════════════════════

  static const List<String> _sacredWords = [
    'அல்லாஹ்',
    'அல்லாஹு',
    'நபி',
    'ரசூல்',
    'ரஸூல்',
  ];

  // ══════════════════════════════════════════════════════════════
  // 5. WAQF (long pause) PATTERNS — inserted as silence after chunk
  // ══════════════════════════════════════════════════════════════

  static final List<RegExp> _waqfPatterns = [
    RegExp(r'ஸல்லல்லாஹு அலைஹி வசல்லம்'),  // salawat — respectful pause
    RegExp(r'ரழியல்லாஹு அன்ஹு'),             // radi allahu anhu
    RegExp(r'அலைஹிஸ்ஸலாம்'),                  // alaihissalam
    RegExp(r'என்று நபி\s*ஸல்லல்லாஹு அலைஹி வசல்லம்\s*அவர்கள்'),
    RegExp(r'நபி\s*ஸல்லல்லாஹு அலைஹி வசல்லம்\s*கூறினார்'),
    RegExp(r'அல்லாஹுவின் தூதர்.*?கூறினார்'),
    RegExp(r'என்று அறிவித்தார்'),
    RegExp(r'என அறிவித்தார்'),
    RegExp(r'என்று கூறினார்'),
  ];

  /// Variable pause durations — human narration never pauses the exact same
  /// duration twice. Using randomized ranges removes robotic rhythm.
  final Random _rng = Random();

  /// Waqf / salawat pause scaled by sentence length — imam-style pacing.
  /// Longer sentences get proportionally longer pauses for scholarly feel.
  int _waqfPauseFor(String chunk) {
    final len = chunk.length;
    if (len > 180) return 520 + _rng.nextInt(180);
    if (len > 100) return 420 + _rng.nextInt(150);
    return 320 + _rng.nextInt(120);
  }

  /// Sentence boundary: 160–280ms (natural gap)
  int get _sentenceGapMs => 160 + _rng.nextInt(120);

  /// Comma / semicolon: 60–120ms (breathing rhythm)
  int get _commaGapMs => 60 + _rng.nextInt(60);

  /// Sacred word pre-delay: 100–160ms (respectful tone)
  int get _sacredPreDelayMs => 100 + _rng.nextInt(60);

  /// Paragraph-start extra pause: 100–180ms (intentional opening)
  int get _paragraphStartMs => 100 + _rng.nextInt(80);

  /// Long chunk breath: 180–300ms (narrator breathing after >4s)
  int get _longChunkBreathMs => 180 + _rng.nextInt(120);

  /// Check if chunk contains sacred references (Allah, Nabi, Rasool)
  bool _containsSacred(String text) {
    for (final word in _sacredWords) {
      if (text.contains(word)) return true;
    }
    return false;
  }

  // ══════════════════════════════════════════════════════════════
  // 5b. ARABIC NAME CONSONANT STOPS
  //     Tamil VITS adds trailing "உ" to Arabic names ending in
  //     consonant clusters (virama). Adding comma after the name
  //     forces a prosodic stop, preventing the epenthetic vowel.
  //     e.g. முஹம்மத் → "muhammatthu" becomes clean "muhammath"
  // ══════════════════════════════════════════════════════════════

  static const List<String> _arabicNameStops = [
    'முஹம்மத்',
    'அஹ்மத்',
    'இப்ராஹீம்',
    'இஸ்மாஈல்',
    'ஸுலைமான்',
    'உஸ்மான்',
    'அப்துர்ரஹ்மான்',
    'அப்துல்லாஹ்',
    'ஸஹீஹ்',
    'யூசுஃப்',
    'ஆயிஷா',
  ];

  // ══════════════════════════════════════════════════════════════
  // 5c. LONG VOWEL ELONGATION
  //     Tamil TTS shortens Arabic long-aa/ee sounds.
  //     Duplicate the vowel sign (ா→ாா, ீ→ீீ) so VITS sustains
  //     the vowel longer. Only for key Islamic terms.
  // ══════════════════════════════════════════════════════════════

  static const Map<String, String> _longVowelFixes = {
    'அல்லாஹ்': 'அல்லாாஹ்',     // elongate laa in Allah
    'ரஹ்மான்': 'ரஹ்மாான்',      // elongate maa in Rahman
    'ரஹீம்':   'ரஹீீம்',        // elongate hee in Raheem
    'குர்ஆன்': 'குர்ஆான்',      // elongate aa in Quran
    'சுப்ஹான்': 'சுப்ஹாான்',    // elongate haa in Subhan
    'ஈமான்':   'ஈமாான்',        // elongate maa in Iman
    'ரமலான்':  'ரமலாான்',       // elongate laa in Ramadan
  };

  // ══════════════════════════════════════════════════════════════
  // 5d. EMPHASIS WORDS — add comma pause for stress in narration
  // ══════════════════════════════════════════════════════════════

  static const List<String> _emphasisWords = [
    'உண்மையாக',
    'நிச்சயமாக',
    'கவனியுங்கள்',
    'எச்சரிக்கை',
    'கட்டாயமாக',
    'அறிந்துகொள்ளுங்கள்',
  ];

  // ══════════════════════════════════════════════════════════════
  // 6. HADITH NUMBER STRIPPING — numbers like "ஹதீஸ் 1234" are noise
  // ══════════════════════════════════════════════════════════════

  static final RegExp _hadithNumPattern = RegExp(
    r'ஹதீஸ்\s*(?:எண்\s*:?\s*)?\d+|ஹதீது\s*\d+|எண்\s*:\s*\d+',
  );

  // ══════════════════════════════════════════════════════════════
  // 7. TAMIL NUMBER WORDS — convert digits to spoken Tamil
  // ══════════════════════════════════════════════════════════════

  static const Map<int, String> _tamilOnes = {
    0: 'பூஜ்ஜியம்',
    1: 'ஒன்று', 2: 'இரண்டு', 3: 'மூன்று', 4: 'நான்கு', 5: 'ஐந்து',
    6: 'ஆறு', 7: 'ஏழு', 8: 'எட்டு', 9: 'ஒன்பது', 10: 'பத்து',
    11: 'பதினொன்று', 12: 'பன்னிரண்டு', 13: 'பதிமூன்று', 14: 'பதினான்கு',
    15: 'பதினைந்து', 16: 'பதினாறு', 17: 'பதினேழு', 18: 'பதினெட்டு',
    19: 'பத்தொன்பது',
  };

  static const Map<int, String> _tamilTens = {
    2: 'இருபது', 3: 'முப்பது', 4: 'நாற்பது', 5: 'ஐம்பது',
    6: 'அறுபது', 7: 'எழுபது', 8: 'எண்பது', 9: 'தொண்ணூறு',
  };

  static const Map<int, String> _tamilTenPrefixes = {
    2: 'இருபத்து', 3: 'முப்பத்து', 4: 'நாற்பத்து', 5: 'ஐம்பத்து',
    6: 'அறுபத்து', 7: 'எழுபத்து', 8: 'எண்பத்து', 9: 'தொண்ணூற்று',
  };

  static const Map<int, String> _tamilHundreds = {
    1: 'நூறு', 2: 'இருநூறு', 3: 'முந்நூறு', 4: 'நானூறு', 5: 'ஐநூறு',
    6: 'அறுநூறு', 7: 'எழுநூறு', 8: 'எண்ணூறு', 9: 'தொள்ளாயிரம்',
  };

  static const Map<int, String> _tamilHundredPrefixes = {
    1: 'நூற்று', 2: 'இருநூற்று', 3: 'முந்நூற்று', 4: 'நானூற்று',
    5: 'ஐநூற்று', 6: 'அறுநூற்று', 7: 'எழுநூற்று', 8: 'எண்ணூற்று',
    9: 'தொள்ளாயிரத்து',
  };

  /// Convert an integer (0–9999) to Tamil words.
  static String _numberToTamil(int n) {
    if (n < 0) return 'கழித்தல் ${_numberToTamil(-n)}';
    if (n <= 19) return _tamilOnes[n]!;
    if (n < 100) {
      final tens = n ~/ 10;
      final ones = n % 10;
      if (ones == 0) return _tamilTens[tens]!;
      return '${_tamilTenPrefixes[tens]!} ${_tamilOnes[ones]!}';
    }
    if (n < 1000) {
      final hundreds = n ~/ 100;
      final remainder = n % 100;
      if (remainder == 0) return _tamilHundreds[hundreds]!;
      return '${_tamilHundredPrefixes[hundreds]!} ${_numberToTamil(remainder)}';
    }
    if (n < 10000) {
      final thousands = n ~/ 1000;
      final remainder = n % 1000;
      final prefix = thousands == 1 ? 'ஆயிரத்து' : '${_numberToTamil(thousands)} ஆயிரத்து';
      if (remainder == 0) {
        return thousands == 1 ? 'ஆயிரம்' : '${_numberToTamil(thousands)} ஆயிரம்';
      }
      return '$prefix ${_numberToTamil(remainder)}';
    }
    // >9999: just return digit string (rare in hadith)
    return n.toString();
  }

  /// Replace standalone numbers in text with Tamil words.
  /// Matches 1–4 digit numbers bounded by word boundaries.
  static final RegExp _standaloneNumberPattern = RegExp(r'(?<=\s|^)(\d{1,4})(?=\s|[.,;:!?]|$)');

  static String _convertNumbers(String text) {
    return text.replaceAllMapped(_standaloneNumberPattern, (m) {
      final n = int.tryParse(m.group(1)!);
      if (n == null || n > 9999) return m.group(0)!;
      return _numberToTamil(n);
    });
  }

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
      bool isFirstAudioChunk = true;

      for (int i = 0; i < sentences.length; i++) {
        if (cancelled) break;

        final chunk = sentences[i];
        if (chunk.trim().isEmpty) continue;
        // ── Guard: skip punctuation-only fragments ──
        //    Aggressive comma insertion can create bare "," or "." fragments
        //    that crash or confuse the native VITS engine.
        if (RegExp(r'^[\s,;:.!?।]+$').hasMatch(chunk.trim())) continue;

        final chunkTokens = _tokenizer.tokenize(chunk);
        // ── Guard: minimum token threshold ──
        //    VITS needs ≥3 tokens for stable synthesis; fewer tokens
        //    can produce silence, garbage, or native-level crashes.
        if (chunkTokens.length < 3) {
          debugPrint('TTS-Isolate: chunk ${i+1} skipped (${chunkTokens.length} tokens)');
          continue;
        }

        debugPrint('TTS-Isolate: chunk ${i+1}/${sentences.length} (${chunkTokens.length} tokens)');

        // ── Build pre-silence buffer (merged into audio, NOT sent separately) ──
        //    Sending tiny separate chunks causes a race condition in the audio
        //    player where the completion event is lost, stalling playback.
        Float32List? preSilence;
        if (isFirstAudioChunk) {
          preSilence = _roomTone(_paragraphStartMs);
        } else {
          if (_containsSacred(chunk)) {
            // Micro pitch reset + sacred pre-delay merged
            final micro = _roomTone(12);
            final sacred = _roomTone(_sacredPreDelayMs);
            preSilence = Float32List(micro.length + sacred.length);
            preSilence.setRange(0, micro.length, micro);
            preSilence.setRange(micro.length, preSilence.length, sacred);
          } else {
            preSilence = _roomTone(12); // micro pitch reset only
          }
        }

        // ── Synthesize with native FFI (guarded against crashes) ──
        Float32List? raw;
        try {
          raw = _synthesizeNative(chunkTokens);
        } catch (e) {
          debugPrint('TTS-Isolate: chunk ${i+1} native error: $e');
          continue;
        }
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

        // First successful audio produced
        isFirstAudioChunk = false;

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

        // ── Post-chunk pause hierarchy (variable durations) ──
        if (_shouldInsertWaqf(chunk)) {
          emitAudio = _appendSilence(emitAudio, _waqfPauseFor(chunk));
        } else if (i < sentences.length - 1) {
          final trimEnd = chunk.trimRight();
          if (trimEnd.endsWith(',') || trimEnd.endsWith(';')) {
            emitAudio = _appendSilence(emitAudio, _commaGapMs);
          } else {
            emitAudio = _appendSilence(emitAudio, _sentenceGapMs);
          }
        }

        // ── Long-chunk breathing: narrator inhale after >4s of speech ──
        if (trimmed.length > _sampleRate * 4) {
          emitAudio = _appendSilence(emitAudio, _longChunkBreathMs);
        }

        // ── Prepend pre-silence into the audio (one chunk = one WAV file) ──
        if (preSilence != null) {
          final combined = Float32List(preSilence.length + emitAudio.length);
          combined.setRange(0, preSilence.length, preSilence);
          combined.setRange(preSilence.length, combined.length, emitAudio);
          emitAudio = combined;
        }

        _mainPort.send(TtsChunk(requestId, emitAudio));
      }

      prevTail = null;
      _mainPort.send(TtsDone(requestId));
    } catch (e) {
      _mainPort.send(TtsError(requestId, e.toString()));
    }
  }

  // ══════════════════════════════════════════════════════════════
  // TEXT NORMALIZATION PIPELINE — runs in order:
  //   1. Unicode cleanup
  //   2. Double-punctuation normalization
  //   3. Hadith number stripping
  //   4. Abbreviation expansion  (ஸல் → ஸல்லல்லாஹு அலைஹி வசல்லம்)
  //   5. Arabic pronunciation fixes
  //   6. Number → Tamil words
  //   7. Smart pause insertion (commas for natural flow)
  //   8. Sacred reference pauses
  //   9. Final whitespace collapse
  // ══════════════════════════════════════════════════════════════

  String _normalizeText(String text) {
    // 1. Unicode cleanup (strip zero-width chars, NBSP, etc.)
    String s = TamilTokenizer.normalize(text);

    // 2. Double-punctuation normalization — prevent stutter
    s = s.replaceAll('..', '.');
    s = s.replaceAll(',,', ',');
    s = s.replaceAll('!!', '!');
    s = s.replaceAll('??', '?');
    s = s.replaceAll(';;', ';');
    s = s.replaceAll('::',':');

    // 3. Strip hadith reference numbers (noise for TTS)
    s = s.replaceAll(_hadithNumPattern, '');

    // 4. Expand parenthesized abbreviations: நபி(ஸல்) → நபி ஸல்லல்லாஹு அலைஹி வசல்லம்
    s = s.replaceAllMapped(_parenAbbrevPattern, (m) {
      final abbr = m.group(1)!;
      final expansion = _honorificExpansions[abbr] ?? abbr;
      return ' $expansion';
    });

    // Expand standalone abbreviations (word-boundary aware)
    for (final entry in _honorificExpansions.entries) {
      final pattern = RegExp(
        r'(?<=[\s,;:.!?\u0964]|^)' + RegExp.escape(entry.key) + r'(?=[\s,;:.!?\u0964]|$)',
      );
      s = s.replaceAll(pattern, entry.value);
    }

    // 4b. Strip non-pronounceable characters remaining after abbreviation expansion
    //     Quotes and parentheses are not in the Tamil VITS vocabulary;
    //     they tokenize as spaces and waste tokens.
    s = s
        .replaceAll('\u2018', '').replaceAll('\u2019', '')  // smart single quotes
        .replaceAll('\u201C', '').replaceAll('\u201D', '')  // smart double quotes
        .replaceAll("'", '').replaceAll('"', '')            // straight quotes
        .replaceAll('(', '').replaceAll(')', '')            // parentheses
        .replaceAll('[', '').replaceAll(']', '');           // brackets

    // 5. Arabic / Islamic pronunciation corrections
    for (final entry in _pronunciationFixes.entries) {
      s = s.replaceAll(entry.key, entry.value);
    }

    // 5b. Long-aa vowel elongation — sustain Arabic vowels
    //     Duplicate vowel sign so VITS holds the sound longer.
    //     Apply only ONCE per word to prevent sing-song over-stretching.
    for (final entry in _longVowelFixes.entries) {
      s = s.replaceFirst(entry.key, entry.value);
    }

    // 6. Number → Tamil words (1–9999)
    s = _convertNumbers(s);

    // 7. Smart pause insertion — add commas for natural narration flow
    //    AFTER narration words: கூறினார்கள் → கூறினார்கள்,
    //    IMPORTANT: requires whitespace on BOTH sides to prevent matching
    //    a short word inside a longer one (e.g. "கூறினார்" inside "கூறினார்கள்").
    for (final word in _pauseAfterWords) {
      s = s.replaceAllMapped(
        RegExp(r'(?<=\s|^)' + RegExp.escape(word) + r'\s+(?=[^\s,;:.!?])'),
        (m) => '$word, ',
      );
    }

    //    BEFORE contrast words: ...text ஆனால் → ...text, ஆனால்
    for (final word in _pauseBeforeWords) {
      // Add comma before if not already preceded by punctuation
      s = s.replaceAllMapped(
        RegExp(r'([^\s,;:.!?])\s+' + RegExp.escape(word)),
        (m) => '${m.group(1)}, $word',
      );
    }

    // 8. Sacred reference pauses — slight comma before Allah/Nabi/Rasool
    for (final word in _sacredWords) {
      // Add comma before sacred word if preceded by a regular word (not punctuation)
      s = s.replaceAllMapped(
        RegExp(r'([அ-ஹொ])\s+' + RegExp.escape(word) + r'(?=\s)'),
        (m) => '${m.group(1)}, $word',
      );
    }

    // 9. Arabic name consonant stops — comma after to prevent trailing "உ"
    //    VITS adds epenthetic vowel after virama-ending Arabic names;
    //    a comma forces a prosodic boundary that cleanly stops the consonant.
    for (final name in _arabicNameStops) {
      s = s.replaceAllMapped(
        RegExp(RegExp.escape(name) + r'\s+(?=[^\s,;:.!?])'),
        (m) => '$name, ',
      );
    }

    // 10. நபி அவர்கள் respectful pause — slow narration for Prophet reference
    s = s.replaceAllMapped(
      RegExp(r'நபி அவர்கள்(?=[^\s,;:.!?]|\s+[^,])'),
      (m) => 'நபி அவர்கள்,',
    );

    // 11. Emphasis words — add comma for stress in narration
    for (final word in _emphasisWords) {
      s = s.replaceAllMapped(
        RegExp(RegExp.escape(word) + r'\s+(?=[^\s,;:.!?])'),
        (m) => '$word, ',
      );
    }

    // 12. Safety: collapse consecutive commas that earlier steps may create
    //     (pause-after + sacred comma can produce ",," which breaks splitting)
    s = s.replaceAll(RegExp(r',{2,}'), ',');

    // 13. Final whitespace collapse
    s = s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

    return s;
  }

  // ── Sentence splitting ──

  List<String> _splitIntoSentences(String text) {
    // Step 1: split on sentence-ending punctuation and colons
    //   Colon is a primary split because hadith text uses "X கூறினார்:" pattern
    final raw = text.split(RegExp(r'(?<=[.!?।:\n])\s*'));
    final List<String> result = [];

    for (final sentence in raw) {
      if (sentence.trim().isEmpty) continue;
      // Skip punctuation-only fragments from comma insertion
      if (RegExp(r'^[\s,;:.!?।]+$').hasMatch(sentence.trim())) continue;
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
        0.667, 1.15, 0.8,  // noiseScale, lengthScale (1.15 = hadith narration pace), noiseScaleW
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

  /// Generate ultra-low room ambience (~−55 dB white noise).
  /// Pure digital silence sounds unnatural to human ears;
  /// faint room tone makes the brain perceive a real recording.
  Float32List _roomTone(int ms) {
    final samples = (_sampleRate * ms / 1000).toInt();
    final out = Float32List(samples);
    for (int i = 0; i < samples; i++) {
      out[i] = (_rng.nextDouble() - 0.5) * 0.0008;
    }
    return out;
  }

  Float32List _appendSilence(Float32List audio, int ms) {
    final tone = _roomTone(ms);
    final result = Float32List(audio.length + tone.length);
    result.setRange(0, audio.length, audio);
    result.setRange(audio.length, result.length, tone);
    return result;
  }
}
