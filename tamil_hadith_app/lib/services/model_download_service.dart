import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ══════════════════════════════════════════════════════════════
// Model variant definitions
// ══════════════════════════════════════════════════════════════

/// Available TTS model variants, ordered by size.
enum TtsModelVariant {
  /// INT8 quantised — smallest, fastest.
  int8(
    fileName: 'model_int8.mnn',
    label: 'INT8',
    description: 'வேகமான, குறைந்த அளவு',
    sizeMB: 28,
    sha256: '435d49e8861e38fd4c633e12e36d87116f5cd90a5ae8d5e1b8b81ce0e3d389ec',
    url:
        'https://huggingface.co/developerabu/mms-tts-tam-mnn/resolve/main/model_int8.mnn',
  );

  const TtsModelVariant({
    required this.fileName,
    required this.label,
    required this.description,
    required this.sizeMB,
    required this.sha256,
    required this.url,
  });

  final String fileName;
  final String label;
  final String description;
  final int sizeMB;
  final String sha256;
  final String url;

  /// Look up a variant by its file name, fallback to [int8].
  static TtsModelVariant fromFileName(String name) {
    for (final v in values) {
      if (v.fileName == name) return v;
    }
    return int8;
  }
}

// ══════════════════════════════════════════════════════════════
// ModelDownloadService — multi-model support
// ══════════════════════════════════════════════════════════════

/// Downloads and caches the MNN TTS INT8 model from HuggingFace.
class ModelDownloadService {
  // ── Singleton ──
  static final ModelDownloadService _instance = ModelDownloadService._();
  factory ModelDownloadService() => _instance;
  ModelDownloadService._();

  /// Partial download suffix — renamed to final name only after success.
  static const String _partialSuffix = '.part';

  String? _modelsDir;

  TtsModelVariant get selectedVariant => TtsModelVariant.int8;

  /// Initialize the models directory.
  Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    _modelsDir = p.join(dir.path, 'models');
    await Directory(_modelsDir!).create(recursive: true);
  }

  Future<void> _ensureDir() async {
    if (_modelsDir != null) return;
    await initialize();
  }

  /// Full path to the INT8 model file.
  Future<String> get modelPath async {
    await _ensureDir();
    return p.join(_modelsDir!, TtsModelVariant.int8.fileName);
  }

  /// Whether the INT8 model has been downloaded.
  Future<bool> get isModelDownloaded async =>
      isVariantDownloaded(TtsModelVariant.int8);

  /// Whether a specific variant has been downloaded.
  Future<bool> isVariantDownloaded(TtsModelVariant variant) async {
    await _ensureDir();
    final file = File(p.join(_modelsDir!, variant.fileName));
    if (!await file.exists()) return false;
    final size = await file.length();
    if (size <= 5 * 1024 * 1024) return false; // at least 5 MB

    final actualHash = await _hashFile(file);
    final matches = actualHash == variant.sha256;
    if (!matches) {
      debugPrint(
        'ModelDownload: Hash mismatch for ${variant.fileName} '
        '(expected ${variant.sha256}, got $actualHash)',
      );
    }
    return matches;
  }

  Future<String> _hashFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Download a specific model variant with progress reporting.
  ///
  /// [onProgress] receives (bytesReceived, totalBytes).
  /// Returns the path to the downloaded model file.
  Future<String> downloadModel({
    TtsModelVariant? variant,
    void Function(int bytesReceived, int totalBytes)? onProgress,
  }) async {
    await _ensureDir();
    final v = variant ?? TtsModelVariant.int8;
    final finalPath = p.join(_modelsDir!, v.fileName);
    final partialPath = '$finalPath$_partialSuffix';

    // Already downloaded — skip
    final finalFile = File(finalPath);
    if (await finalFile.exists()) {
      final isValid = await isVariantDownloaded(v);
      if (isValid) {
        debugPrint('ModelDownload: ${v.fileName} already exists');
        onProgress?.call(1, 1);
        return finalPath;
      }
      debugPrint('ModelDownload: Removing invalid cached ${v.fileName}');
      await finalFile.delete();
    }

    // Clean up any previous partial download
    final partialFile = File(partialPath);
    if (await partialFile.exists()) {
      await partialFile.delete();
    }

    debugPrint(
      'ModelDownload: Starting download of ${v.fileName} from ${v.url}',
    );
    final stopwatch = Stopwatch()..start();

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(v.url));
      request.followRedirects = true;
      request.maxRedirects = 5;

      final response = await request.close();

      if (response.statusCode != 200) {
        throw HttpException(
          'Download failed: HTTP ${response.statusCode} ${response.reasonPhrase}',
        );
      }

      final totalBytes = response.contentLength;
      int bytesReceived = 0;

      final sink = partialFile.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        bytesReceived += chunk.length;
        onProgress?.call(bytesReceived, totalBytes);
      }

      await sink.flush();
      await sink.close();

      final downloadedSize = await partialFile.length();
      if (downloadedSize < 5 * 1024 * 1024) {
        await partialFile.delete();
        throw Exception(
          'Downloaded file too small ($downloadedSize bytes). '
          'Expected ~${v.sizeMB} MB.',
        );
      }

      final actualHash = await _hashFile(partialFile);
      if (actualHash != v.sha256) {
        await partialFile.delete();
        throw Exception(
          'Downloaded file hash mismatch for ${v.fileName}. '
          'Expected ${v.sha256}, got $actualHash.',
        );
      }

      // Atomic rename: partial → final
      await partialFile.rename(finalPath);

      stopwatch.stop();
      final sizeMB = (downloadedSize / (1024 * 1024)).toStringAsFixed(1);
      final seconds = stopwatch.elapsedMilliseconds / 1000;
      debugPrint(
        'ModelDownload: ${v.fileName} complete — '
        '$sizeMB MB in ${seconds.toStringAsFixed(1)}s',
      );

      return finalPath;
    } finally {
      client.close();
    }
  }

  /// Delete a specific variant's cached file.
  Future<void> deleteVariant(TtsModelVariant variant) async {
    await _ensureDir();
    final file = File(p.join(_modelsDir!, variant.fileName));
    if (await file.exists()) await file.delete();
    final partial = File(
      p.join(_modelsDir!, '${variant.fileName}$_partialSuffix'),
    );
    if (await partial.exists()) await partial.delete();
    debugPrint('ModelDownload: ${variant.fileName} deleted');
  }

  /// Delete all cached models.
  Future<void> deleteAllModels() async {
    for (final v in TtsModelVariant.values) {
      await deleteVariant(v);
    }
  }

  /// Get download size of a specific variant in bytes, or 0 if not downloaded.
  Future<int> variantSize(TtsModelVariant variant) async {
    await _ensureDir();
    final file = File(p.join(_modelsDir!, variant.fileName));
    if (!await file.exists()) return 0;
    return file.length();
  }

  /// Get the size of the INT8 model in bytes, or 0.
  Future<int> get modelSize => variantSize(TtsModelVariant.int8);
}
