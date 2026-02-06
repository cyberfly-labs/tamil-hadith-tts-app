import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Audio player service that plays PCM float32 audio from TTS.
/// Supports background playback (screen off) via audio_session.
class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  String? _tempDir;
  ConcatenatingAudioSource? _playlist;
  int _chunkIndex = 0;

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
        // Another app interrupted — pause
        if (_player.playing) _player.pause();
      } else {
        // Interruption ended — resume if we were playing
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

    // Convert PCM float32 to WAV file
    final wavBytes = _pcmToWav(pcmData, sampleRate);
    final wavFile = File(p.join(_tempDir!, 'tts_output.wav'));
    await wavFile.writeAsBytes(wavBytes);

    // Play the WAV file
    await _player.setFilePath(wavFile.path);
    await _player.play();
  }

  /// Start streaming playback. Call this once before [addStreamingChunk].
  /// Playback begins as soon as the first chunk is added.
  Future<void> startStreaming() async {
    _tempDir ??= (await getApplicationCacheDirectory()).path;
    _chunkIndex = 0;

    // Clean up previous chunk files
    final dir = Directory(_tempDir!);
    await for (final f in dir.list()) {
      if (f is File && p.basename(f.path).startsWith('tts_chunk_')) {
        await f.delete();
      }
    }

    _playlist = ConcatenatingAudioSource(children: []);
    await _player.setAudioSource(_playlist!, preload: false);
  }

  /// Add a new PCM chunk to the streaming playlist and start playing
  /// if not already playing.
  Future<void> addStreamingChunk(Float32List pcmData, {int sampleRate = 16000}) async {
    if (pcmData.isEmpty || _playlist == null) return;

    _tempDir ??= (await getApplicationCacheDirectory()).path;

    final wavBytes = _pcmToWav(pcmData, sampleRate);
    final wavFile = File(p.join(_tempDir!, 'tts_chunk_${_chunkIndex++}.wav'));
    await wavFile.writeAsBytes(wavBytes);

    await _playlist!.add(AudioSource.file(wavFile.path));

    // Start playback on the first chunk
    if (!_player.playing) {
      await _player.play();
    }
  }

  /// Wait for the current streaming playlist to finish playing.
  /// Returns a future that completes when playback reaches the end.
  Future<void> awaitStreamingComplete() async {
    if (_playlist == null) return;
    // Listen for the player completing (reaching the end of the queue)
    await _player.processingStateStream.firstWhere(
      (state) => state == ProcessingState.completed,
    );
  }

  /// Play a WAV file directly from disk (e.g. from audio cache).
  Future<void> playFromFile(String filePath) async {
    await _player.setFilePath(filePath);
    await _player.play();
  }

  /// Clean up all temporary chunk WAV files.
  /// Call after streaming playback finishes to avoid disk bloat.
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

  /// Current playback speed (1.0 = normal).
  double get speed => _player.speed;

  /// Stream of speed changes.
  Stream<double> get speedStream => _player.speedStream;

  /// Set playback speed. Typical values: 0.75, 1.0, 1.25, 1.5.
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  /// Stop current playback
  Future<void> stop() async {
    await _player.stop();
  }

  /// Pause current playback
  Future<void> pause() async {
    await _player.pause();
  }

  /// Resume playback
  Future<void> resume() async {
    await _player.play();
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

    // Only write the 44-byte WAV header into ByteData; PCM data is bulk-copied
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
    buffer.setUint32(offset, 16, Endian.little); // chunk size
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
    offset += 4;

    // Vectorized float32 → int16 (integer clamp avoids slow double-clamp)
    final samples = Int16List(numSamples);
    for (int i = 0; i < numSamples; i++) {
      samples[i] = (pcmData[i] * 32767).toInt().clamp(-32767, 32767);
    }
    final sampleBytes = samples.buffer.asUint8List();
    final result = Uint8List(44 + dataSize);
    // Copy header
    result.setRange(0, 44, buffer.buffer.asUint8List());
    // Copy PCM data
    result.setRange(44, 44 + dataSize, sampleBytes);
    return result;
  }

  /// Get the player stream for listening to state changes
  Stream<bool> get playingStream => _player.playingStream;

  /// Dispose resources
  void dispose() {
    _player.dispose();
  }
}
