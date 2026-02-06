import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Permanently caches synthesized TTS audio per hadith number on disk.
///
/// Uses the **documents** directory (NOT cache) so files survive
/// Android cache clears. Path: <docs>/hadith_audio/<id>.wav
///
/// On first play the streaming chunks are saved to a WAV file.
/// Subsequent plays load directly from cache — zero synthesis latency.
class AudioCacheService {
  String? _audioDir;

  /// In-flight write futures keyed by cache key.
  /// Prevents concurrent writes to the same file (double-tap crash).
  final Map<String, Future<String>> _writeLocks = {};

  /// Maximum cache size in bytes (1 GB). Oldest files are evicted when exceeded.
  static const int maxCacheBytes = 1024 * 1024 * 1024;

  /// Initialize the permanent audio directory.
  Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    _audioDir = p.join(dir.path, 'hadith_audio');
    await Directory(_audioDir!).create(recursive: true);
  }

  /// Ensure directory is ready (lazy init for late callers).
  Future<void> _ensureDir() async {
    if (_audioDir != null) return;
    final dir = await getApplicationDocumentsDirectory();
    _audioDir = p.join(dir.path, 'hadith_audio');
    await Directory(_audioDir!).create(recursive: true);
  }

  /// Get the cache file path for a hadith number.
  String _cachePath(int hadithNumber) {
    return p.join(_audioDir!, '$hadithNumber.wav');
  }

  /// Check if audio is cached for a given hadith number.
  bool isCached(int hadithNumber) {
    if (_audioDir == null) return false;
    return File(_cachePath(hadithNumber)).existsSync();
  }

  /// Get the cached audio file path, or null if not cached.
  /// Performs a corruption check — deletes files < 1 KB (half-written).
  String? getCachedPath(int hadithNumber) {
    if (_audioDir == null) return null;
    final file = File(_cachePath(hadithNumber));
    if (!file.existsSync()) return null;

    // Corruption guard: a valid WAV must be > 1 KB (header + some audio)
    final len = file.lengthSync();
    if (len < 1000) {
      debugPrint('AudioCache: Corrupt file for #$hadithNumber — deleting');
      try { file.deleteSync(); } catch (_) {}
      return null;
    }

    // Additional guard: reject extremely short audio (< 0.5s)
    // WAV header is 44 bytes, PCM 16-bit mono = 2 bytes/sample @ 16kHz
    const int minSamples = 16000 ~/ 2; // 0.5 seconds
    const int minDataBytes = minSamples * 2;
    if (len < 44 + minDataBytes) {
      debugPrint('AudioCache: Too-short audio for #$hadithNumber (${len} bytes) — deleting');
      try { file.deleteSync(); } catch (_) {}
      return null;
    }

    return file.path;
  }

  /// Get the number of cached hadith audio files.
  Future<int> getCachedCount() async {
    await _ensureDir();
    final dir = Directory(_audioDir!);
    if (!await dir.exists()) return 0;
    int count = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.wav')) count++;
    }
    return count;
  }

  // ════════════════════════════════════════════════════════════
  // Generic key-based cache (used for Quran verses, etc.)
  // ════════════════════════════════════════════════════════════

  /// Get cache file path for a string key (e.g. "quran_2_255").
  String _cachePathByKey(String key) {
    return p.join(_audioDir!, '$key.wav');
  }

  /// Check if audio is cached for a given string key.
  bool isCachedByKey(String key) {
    if (_audioDir == null) return false;
    return File(_cachePathByKey(key)).existsSync();
  }

  /// Get cached audio file path by key, or null if not cached.
  /// Same corruption guards as [getCachedPath].
  String? getCachedPathByKey(String key) {
    if (_audioDir == null) return null;
    final file = File(_cachePathByKey(key));
    if (!file.existsSync()) return null;

    final len = file.lengthSync();
    if (len < 1000) {
      debugPrint('AudioCache: Corrupt file for key $key — deleting');
      try { file.deleteSync(); } catch (_) {}
      return null;
    }

    const int minSamples = 16000 ~/ 2;
    const int minDataBytes = minSamples * 2;
    if (len < 44 + minDataBytes) {
      debugPrint('AudioCache: Too-short audio for key $key ($len bytes) — deleting');
      try { file.deleteSync(); } catch (_) {}
      return null;
    }

    return file.path;
  }

  /// Save PCM float32 audio to cache with a string key.
  Future<String> saveToCacheByKey(String key, Float32List pcmData, {int sampleRate = 16000}) async {
    if (_writeLocks.containsKey(key)) {
      return _writeLocks[key]!;
    }

    final future = _saveInternalByKey(key, pcmData, sampleRate);
    _writeLocks[key] = future;

    try {
      final path = await future;
      return path;
    } finally {
      _writeLocks.remove(key);
    }
  }

  Future<String> _saveInternalByKey(String key, Float32List pcmData, int sampleRate) async {
    await _ensureDir();

    final wavBytes = pcmToWav(pcmData, sampleRate);
    final file = File(_cachePathByKey(key));
    await file.writeAsBytes(wavBytes, flush: true);
    debugPrint('AudioCache: Saved key=$key '
        '(${pcmData.length} samples, ${(pcmData.length / sampleRate).toStringAsFixed(1)}s)');

    _enforceCacheLimit().catchError((e) {
      debugPrint('AudioCache: eviction error: $e');
    });

    return file.path;
  }

  // ════════════════════════════════════════════════════════════
  // Hadith-specific (legacy, delegates to key-based)
  // ════════════════════════════════════════════════════════════

  /// Save PCM float32 audio as a WAV file in the permanent store.
  /// Uses a per-hadith write lock so double-taps never corrupt the file.
  Future<String> saveToCache(int hadithNumber, Float32List pcmData, {int sampleRate = 16000}) async {
    return saveToCacheByKey('$hadithNumber', pcmData, sampleRate: sampleRate);
  }

  /// Evict oldest cached files until total size is below 80% of [maxCacheBytes].
  Future<void> _enforceCacheLimit() async {
    await _ensureDir();
    final dir = Directory(_audioDir!);
    if (!await dir.exists()) return;

    // Collect files with their sizes and modification times
    final List<File> files = [];
    int totalSize = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.wav')) {
        files.add(entity);
        totalSize += await entity.length();
      }
    }

    if (totalSize <= maxCacheBytes) return;

    debugPrint('AudioCache: Cache ${(totalSize / (1024 * 1024)).toStringAsFixed(0)} MB '
        'exceeds limit ${(maxCacheBytes / (1024 * 1024)).toStringAsFixed(0)} MB — evicting');

    // Sort oldest first
    files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

    final target = (maxCacheBytes * 0.8).toInt();
    for (final file in files) {
      if (totalSize <= target) break;
      try {
        final len = await file.length();
        await file.delete();
        totalSize -= len;
        debugPrint('AudioCache: Evicted ${p.basename(file.path)}');
      } catch (_) {}
    }
  }

  /// Delete a single hadith's cached audio.
  Future<void> deleteCached(int hadithNumber) async {
    await _ensureDir();
    final file = File(_cachePath(hadithNumber));
    if (await file.exists()) await file.delete();
  }

  /// Clear all cached audio files.
  Future<void> clearCache() async {
    await _ensureDir();
    final dir = Directory(_audioDir!);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
      debugPrint('AudioCache: Cache cleared');
    }
  }

  /// Get total cache size in bytes.
  Future<int> getCacheSize() async {
    await _ensureDir();
    final dir = Directory(_audioDir!);
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

    // Vectorized float32 → int16 (avoid double-clamp on floats)
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
