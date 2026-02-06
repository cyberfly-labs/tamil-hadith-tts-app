import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Audio player service that plays PCM float32 audio from TTS
class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  String? _tempDir;

  AudioPlayer get player => _player;

  bool get isPlaying => _player.playing;

  Future<void> initialize() async {
    final dir = await getApplicationCacheDirectory();
    _tempDir = dir.path;
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

    // Batch-convert float32 → int16 using typed list for speed
    final samples = Int16List(numSamples);
    for (int i = 0; i < numSamples; i++) {
      samples[i] = (pcmData[i].clamp(-1.0, 1.0) * 32767).toInt();
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
