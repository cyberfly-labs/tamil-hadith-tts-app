import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

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

    final wavBytes = _pcmToWav(pcmData, sampleRate);
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

    _chunkIndex = 0;
    _chunkQueue.clear();
    _streamingMode = true;
    _allChunksSent = false;
    _isAdvancing = false;
    _streamingCompleter = Completer<void>();

    // Clean up previous chunk files
    await cleanupChunks();

    // Listen for each chunk finishing so we auto-advance the queue
    _stateSub?.cancel();
    _stateSub = _player.processingStateStream.listen((state) {
      debugPrint('AudioPlayer: processingState=$state streaming=$_streamingMode queue=${_chunkQueue.length} allSent=$_allChunksSent');
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

    final wavBytes = _pcmToWav(pcmData, sampleRate);
    final wavFile = File(p.join(_tempDir!, 'tts_chunk_${_chunkIndex++}.wav'));
    await wavFile.writeAsBytes(wavBytes);

    _chunkQueue.add(wavFile.path);
    debugPrint('AudioPlayer: addChunk #${_chunkIndex - 1} (${pcmData.length} samples, ${(pcmData.length / sampleRate).toStringAsFixed(2)}s) queue=${_chunkQueue.length} playing=${_player.playing} state=${_player.processingState} advancing=$_isAdvancing');

    // If the player is idle / just finished, kick off the next chunk now.
    // The _isAdvancing guard prevents racing with the _stateSub callback.
    if (!_isAdvancing &&
        !_player.playing &&
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
        !_player.playing &&
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
  Future<void> _advanceQueue() async {
    if (_isAdvancing) {
      debugPrint('AudioPlayer: _advanceQueue skipped (already advancing)');
      return;
    }
    _isAdvancing = true;
    try {
      if (_chunkQueue.isNotEmpty) {
        final path = _chunkQueue.removeAt(0);
        debugPrint('AudioPlayer: Playing chunk $path (remaining=${_chunkQueue.length})');
        try {
          await _player.setFilePath(path);
          await _player.play();
          debugPrint('AudioPlayer: play() returned, playing=${_player.playing}');
        } catch (e) {
          debugPrint('AudioPlayer: Chunk play failed: $e');
        }
      } else if (_allChunksSent) {
        debugPrint('AudioPlayer: Queue drained, completing stream');
        _completeStreaming();
      } else {
        debugPrint('AudioPlayer: Queue empty, waiting for more chunks');
      }
    } finally {
      _isAdvancing = false;
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
  Future<void> playFromFile(String filePath) async {
    await _player.setFilePath(filePath);
    await _player.play();
  }

  /// Clean up all temporary chunk WAV files.
  Future<void> cleanupChunks() async {
    if (_tempDir == null) return;
    final dir = Directory(_tempDir!);
    if (!await dir.exists()) return;
    await for (final f in dir.list()) {
      if (f is File && p.basename(f.path).startsWith('tts_chunk_')) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    debugPrint('AudioPlayer: Chunk files cleaned up');
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

  /// Convert PCM float32 to WAV byte array
  Uint8List _pcmToWav(Float32List pcmData, int sampleRate) {
    const numChannels = 1;
    const bitsPerSample = 16;
    final numSamples = pcmData.length;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final blockAlign = numChannels * bitsPerSample ~/ 8;
    final dataSize = numSamples * blockAlign;
    final fileSize = 36 + dataSize;

    final buffer = ByteData(44);
    int offset = 0;

    // RIFF header
    buffer.setUint8(offset++, 0x52); // 'R'
    buffer.setUint8(offset++, 0x49); // 'I'
    buffer.setUint8(offset++, 0x46); // 'F'
    buffer.setUint8(offset++, 0x46); // 'F'
    buffer.setUint32(offset, fileSize, Endian.little);
    offset += 4;
    buffer.setUint8(offset++, 0x57); // 'W'
    buffer.setUint8(offset++, 0x41); // 'A'
    buffer.setUint8(offset++, 0x56); // 'V'
    buffer.setUint8(offset++, 0x45); // 'E'

    // fmt chunk
    buffer.setUint8(offset++, 0x66); // 'f'
    buffer.setUint8(offset++, 0x6D); // 'm'
    buffer.setUint8(offset++, 0x74); // 't'
    buffer.setUint8(offset++, 0x20); // ' '
    buffer.setUint32(offset, 16, Endian.little);
    offset += 4;
    buffer.setUint16(offset, 1, Endian.little); // PCM format
    offset += 2;
    buffer.setUint16(offset, numChannels, Endian.little);
    offset += 2;
    buffer.setUint32(offset, sampleRate, Endian.little);
    offset += 4;
    buffer.setUint32(offset, byteRate, Endian.little);
    offset += 4;
    buffer.setUint16(offset, blockAlign, Endian.little);
    offset += 2;
    buffer.setUint16(offset, bitsPerSample, Endian.little);
    offset += 2;

    // data chunk
    buffer.setUint8(offset++, 0x64); // 'd'
    buffer.setUint8(offset++, 0x61); // 'a'
    buffer.setUint8(offset++, 0x74); // 't'
    buffer.setUint8(offset++, 0x61); // 'a'
    buffer.setUint32(offset, dataSize, Endian.little);

    // float32 → int16
    final samples = Int16List(numSamples);
    for (int i = 0; i < numSamples; i++) {
      samples[i] = (pcmData[i] * 32767).toInt().clamp(-32767, 32767);
    }
    final sampleBytes = samples.buffer.asUint8List();
    final result = Uint8List(44 + dataSize);
    result.setRange(0, 44, buffer.buffer.asUint8List());
    result.setRange(44, 44 + dataSize, sampleBytes);
    return result;
  }
}
