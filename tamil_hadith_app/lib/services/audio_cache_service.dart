import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Caches synthesized TTS audio per hadith number on disk.
///
/// On first play, the streaming chunks are saved to a WAV file.
/// Subsequent plays load directly from cache — zero synthesis latency.
class AudioCacheService {
  String? _cacheDir;

  /// Initialize the cache directory.
  Future<void> initialize() async {
    final dir = await getApplicationCacheDirectory();
    _cacheDir = p.join(dir.path, 'tts_cache');
    await Directory(_cacheDir!).create(recursive: true);
  }

  /// Get the cache file path for a hadith number.
  String _cachePath(int hadithNumber) {
    return p.join(_cacheDir!, '$hadithNumber.wav');
  }

  /// Check if audio is cached for a given hadith number.
  bool isCached(int hadithNumber) {
    if (_cacheDir == null) return false;
    return File(_cachePath(hadithNumber)).existsSync();
  }

  /// Get the cached audio file path, or null if not cached.
  String? getCachedPath(int hadithNumber) {
    if (!isCached(hadithNumber)) return null;
    return _cachePath(hadithNumber);
  }

  /// Save PCM float32 audio as a WAV file in the cache.
  Future<String> saveToCache(int hadithNumber, Float32List pcmData, {int sampleRate = 16000}) async {
    _cacheDir ??= (await (() async {
      final dir = await getApplicationCacheDirectory();
      return p.join(dir.path, 'tts_cache');
    })());
    await Directory(_cacheDir!).create(recursive: true);

    final wavBytes = pcmToWav(pcmData, sampleRate);
    final file = File(_cachePath(hadithNumber));
    await file.writeAsBytes(wavBytes);
    debugPrint('AudioCache: Saved hadith #$hadithNumber '
        '(${pcmData.length} samples, ${(pcmData.length / sampleRate).toStringAsFixed(1)}s)');
    return file.path;
  }

  /// Clear all cached audio files.
  Future<void> clearCache() async {
    if (_cacheDir == null) return;
    final dir = Directory(_cacheDir!);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
      debugPrint('AudioCache: Cache cleared');
    }
  }

  /// Get total cache size in bytes.
  Future<int> getCacheSize() async {
    if (_cacheDir == null) return 0;
    final dir = Directory(_cacheDir!);
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  /// Convert PCM float32 to WAV byte array (16-bit, mono).
  static Uint8List pcmToWav(Float32List pcmData, int sampleRate) {
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

    // Batch-convert float32 → int16
    final samples = Int16List(numSamples);
    for (int i = 0; i < numSamples; i++) {
      samples[i] = (pcmData[i].clamp(-1.0, 1.0) * 32767).toInt();
    }
    final sampleBytes = samples.buffer.asUint8List();
    final result = Uint8List(44 + dataSize);
    result.setRange(0, 44, buffer.buffer.asUint8List());
    result.setRange(44, 44 + dataSize, sampleBytes);
    return result;
  }
}
