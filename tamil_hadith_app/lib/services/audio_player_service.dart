import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'audio_cache_service.dart';

/// Audio player service that plays PCM float32 audio from TTS.
/// Supports true streaming playback: audio starts on the first chunk
/// while remaining chunks are still being synthesized.
///
/// Uses a simple file-queue approach instead of ConcatenatingAudioSource
/// for maximum reliability across Android versions.
class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  String? _tempDir;
  int _chunkIndex = 0;
  int _sessionStartIndex = 0; // first chunk index of current streaming session

  // ── Streaming queue state ──
  final List<String> _chunkQueue = [];
  bool _streamingMode = false;
  bool _allChunksSent = false;
  bool _isAdvancing = false;  // Reentrancy guard for _advanceQueue
  Completer<void>? _streamingCompleter;
  StreamSubscription<ProcessingState>? _stateSub;

  AudioPlayer get player => _player;

  bool get isPlaying => _player.playing;

  Future<void> initialize() async {
    final dir = await getApplicationCacheDirectory();
    _tempDir = dir.path;

    // Inform the OS that we're a speech player (keeps audio on screen-off)
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());

    // Handle audio interruptions (phone call, etc.)
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        if (_player.playing) _player.pause();
      } else {
        if (!_player.playing &&
            _player.processingState != ProcessingState.idle &&
            _player.processingState != ProcessingState.completed) {
          _player.play();
        }
      }
    });

    // Handle when user unplugs headphones
    session.becomingNoisyEventStream.listen((_) {
      _player.pause();
    });
  }

  /// Play raw PCM float32 audio by converting to WAV first
  Future<void> playPcmAudio(Float32List pcmData, {int sampleRate = 16000}) async {
    if (pcmData.isEmpty) return;

    _tempDir ??= (await getApplicationCacheDirectory()).path;

    final wavBytes = AudioCacheService.pcmToWav(pcmData, sampleRate);
    final wavFile = File(p.join(_tempDir!, 'tts_output.wav'));
    await wavFile.writeAsBytes(wavBytes);

    await _player.setFilePath(wavFile.path);
    await _player.play();
  }

  // ════════════════════════════════════════════════════════════
  // Streaming playback — queue-based, starts on first chunk
  // ════════════════════════════════════════════════════════════

  /// Start a new streaming session. Call before [addStreamingChunk].
  Future<void> startStreaming() async {
    debugPrint('AudioPlayer: startStreaming()');
    _tempDir ??= (await getApplicationCacheDirectory()).path;

    // Stop any old playback (could be from a different hadith or cached file)
    await _player.stop();

    // Use a fresh index range so new chunk filenames never collide with
    // stale files being cleaned up in the background.
    _chunkIndex = DateTime.now().millisecondsSinceEpoch % 1000000 * 100;
    _sessionStartIndex = _chunkIndex;
    _chunkQueue.clear();
    _streamingMode = true;
    _allChunksSent = false;
    _isAdvancing = false;
    _streamingCompleter = Completer<void>();

    // Clean up previous chunk files in the background — don't block
    // the synthesis pipeline waiting for disk I/O.
    cleanupChunks();

    // Listen for each chunk finishing so we auto-advance the queue
    _stateSub?.cancel();
    _stateSub = _player.processingStateStream.listen((state) {
      if (_streamingMode && state == ProcessingState.completed) {
        _advanceQueue();
      }
    });
  }

  /// Add a PCM chunk. Playback starts immediately on the first chunk;
  /// subsequent chunks are queued and play seamlessly after the current one.
  Future<void> addStreamingChunk(Float32List pcmData, {int sampleRate = 16000}) async {
    if (pcmData.isEmpty || !_streamingMode) return;

    _tempDir ??= (await getApplicationCacheDirectory()).path;

    final wavBytes = AudioCacheService.pcmToWav(pcmData, sampleRate);
    final wavPath = p.join(_tempDir!, 'tts_chunk_${_chunkIndex++}.wav');
    // Sync write: small WAV files (<100KB) — async overhead exceeds I/O time
    File(wavPath).writeAsBytesSync(wavBytes, flush: false);

    _chunkQueue.add(wavPath);

    // If the player is idle / just finished, kick off the next chunk now.
    // The _isAdvancing guard prevents racing with the _stateSub callback.
    if (!_isAdvancing &&
        (_player.processingState == ProcessingState.idle ||
         _player.processingState == ProcessingState.completed)) {
      await _advanceQueue();
    }
  }

  /// Signal that no more chunks will arrive.
  /// Playback continues until the queue drains, then streaming completes.
  void finishStreaming() {
    debugPrint('AudioPlayer: finishStreaming() queue=${_chunkQueue.length} playing=${_player.playing} state=${_player.processingState}');
    _allChunksSent = true;
    // If the queue is already empty and player is done → complete now
    if (_chunkQueue.isEmpty &&
        (_player.processingState == ProcessingState.completed ||
         _player.processingState == ProcessingState.idle)) {
      _completeStreaming();
    }
  }

  /// Returns a future that completes when all queued chunks have played.
  Future<void> awaitStreamingComplete() async {
    return _streamingCompleter?.future ?? Future.value();
  }

  /// Play the next chunk from the queue, or finish if done.
  /// Guarded against reentrancy — two concurrent callers (subscription +
  /// addStreamingChunk) cannot both pop-and-play at the same time.
  ///
  /// IMPORTANT: We do NOT await `_player.play()` because just_audio 0.10.x
  /// returns a Future that blocks until playback finishes. Awaiting it would
  /// hold `_isAdvancing = true` for the entire chunk duration, causing the
  /// `_stateSub` completed-event to be rejected. Instead we fire-and-forget
  /// `play()` (it sets `_player.playing = true` synchronously) and let the
  /// `_stateSub` listener drive chunk-to-chunk advancement.
  Future<void> _advanceQueue() async {
    if (_isAdvancing) {
      return;
    }
    _isAdvancing = true;
    try {
      if (_chunkQueue.isNotEmpty) {
        final path = _chunkQueue.removeAt(0);
        try {
          await _player.setFilePath(path);
          _player.play().catchError((e) {
            debugPrint('AudioPlayer: play() error: $e');
          });
        } catch (e) {
          debugPrint('AudioPlayer: Chunk setFilePath failed: $e');
        }
      } else if (_allChunksSent) {
        _completeStreaming();
      }
    } finally {
      _isAdvancing = false;
      // Race-condition safety net: check both pending-chunks and
      // stream-completion so no state is silently dropped.
      if (_streamingMode &&
          (_player.processingState == ProcessingState.completed ||
           _player.processingState == ProcessingState.idle)) {
        if (_chunkQueue.isNotEmpty) {
          Future.microtask(() => _advanceQueue());
        } else if (_allChunksSent) {
          _completeStreaming();
        }
      }
    }
  }

  void _completeStreaming() {
    _streamingMode = false;
    _stateSub?.cancel();
    _stateSub = null;
    if (_streamingCompleter != null && !_streamingCompleter!.isCompleted) {
      _streamingCompleter!.complete();
    }
  }

  // ════════════════════════════════════════════════════════════
  // Direct file playback (for cached audio)
  // ════════════════════════════════════════════════════════════

  /// Play a WAV file directly from disk (e.g. from audio cache).
  /// Blocks until playback finishes (suitable for single-play scenarios).
  Future<void> playFromFile(String filePath) async {
    await _player.setFilePath(filePath);
    await _player.play();
  }

  /// Start playing a WAV file without blocking.
  /// Returns immediately after playback begins.
  /// Use [awaitPlaybackComplete] to wait for it to finish.
  Future<void> startPlayingFile(String filePath) async {
    await _player.setFilePath(filePath);
    _player.play().catchError((e) {
      debugPrint('AudioPlayer: startPlayingFile error: $e');
    });
  }

  /// Wait until the player finishes the current track (not streaming).
  /// Handles pause: waits for resume→complete rather than timing out.
  Future<void> awaitPlaybackComplete() async {
    if (_player.processingState == ProcessingState.completed ||
        _player.processingState == ProcessingState.idle) {
      return;
    }
    final completer = Completer<void>();
    late StreamSubscription<ProcessingState> sub;
    sub = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed || state == ProcessingState.idle) {
        if (!completer.isCompleted) completer.complete();
        sub.cancel();
      }
    });
    await completer.future;
  }

  /// Clean up temporary chunk WAV files.
  /// By default, only deletes files from previous sessions to avoid
  /// removing chunks still being played or stitched into cache.
  /// Pass [all] = true to force-delete everything (e.g. on explicit stop).
  Future<void> cleanupChunks({bool all = false}) async {
    if (_tempDir == null) return;
    final dir = Directory(_tempDir!);
    if (!await dir.exists()) return;
    int deleted = 0;
    await for (final f in dir.list()) {
      if (f is File && p.basename(f.path).startsWith('tts_chunk_')) {
        if (all) {
          try { await f.delete(); deleted++; } catch (_) {}
        } else {
          final idx = _indexFromName(f.path);
          if (idx < _sessionStartIndex) {
            try { await f.delete(); deleted++; } catch (_) {}
          }
        }
      }
    }
    if (deleted > 0) debugPrint('AudioPlayer: Cleaned up $deleted chunk files');
  }

  /// List chunk WAV files created during the current/last streaming session.
  /// Only includes files from the current session (filters out stale leftovers).
  /// Returned paths are sorted in playback order (by numeric index).
  Future<List<String>> listChunkFiles() async {
    _tempDir ??= (await getApplicationCacheDirectory()).path;
    final dir = Directory(_tempDir!);
    if (!await dir.exists()) return const [];

    final files = <String>[];
    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (name.startsWith('tts_chunk_') && name.endsWith('.wav')) {
          final idx = _indexFromName(entity.path);
          // Only include files from the current session
          if (idx >= _sessionStartIndex) {
            files.add(entity.path);
          }
        }
      }
    }

    files.sort((a, b) => _indexFromName(a).compareTo(_indexFromName(b)));
    return files;
  }

  static int _indexFromName(String path) {
    final name = p.basename(path);
    final m = RegExp(r'^tts_chunk_(\d+)\.wav$').firstMatch(name);
    return int.tryParse(m?.group(1) ?? '') ?? 1 << 30;
  }

  // ── Playback speed ──

  double get speed => _player.speed;
  Stream<double> get speedStream => _player.speedStream;

  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  /// Stop current playback and cancel streaming.
  Future<void> stop() async {
    _streamingMode = false;
    _allChunksSent = true;
    _chunkQueue.clear();
    _stateSub?.cancel();
    _stateSub = null;
    if (_streamingCompleter != null && !_streamingCompleter!.isCompleted) {
      _streamingCompleter!.complete();
    }
    await _player.stop();
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> resume() async {
    await _player.play();
  }

  /// Get the player stream for listening to state changes
  Stream<bool> get playingStream => _player.playingStream;

  /// Dispose resources
  void dispose() {
    _stateSub?.cancel();
    _player.dispose();
  }
}
