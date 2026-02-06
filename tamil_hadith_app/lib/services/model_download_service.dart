import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Downloads and caches the MNN TTS model from HuggingFace.
///
/// The model (~109 MB) is downloaded once on first launch and stored
/// permanently in the app's documents directory. Subsequent launches
/// skip the download entirely.
class ModelDownloadService {
  static const String _modelUrl =
      'https://huggingface.co/developerabu/mms-tts-tam-mnn/resolve/main/model_fp32.mnn';

  static const String _modelFileName = 'model_fp32.mnn';

  /// Partial download suffix — renamed to final name only after success.
  static const String _partialSuffix = '.part';

  String? _modelsDir;

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

  /// Full path to the cached model file.
  Future<String> get modelPath async {
    await _ensureDir();
    return p.join(_modelsDir!, _modelFileName);
  }

  /// Whether the model has already been downloaded.
  Future<bool> get isModelDownloaded async {
    final path = await modelPath;
    final file = File(path);
    if (!await file.exists()) return false;
    // Sanity check: model should be > 10 MB (avoid corrupt/truncated files)
    final size = await file.length();
    return size > 10 * 1024 * 1024;
  }

  /// Download the model with progress reporting.
  ///
  /// [onProgress] receives (bytesReceived, totalBytes).
  /// totalBytes may be -1 if the server doesn't send Content-Length.
  ///
  /// Returns the path to the downloaded model file.
  /// Throws on network errors or cancellation.
  Future<String> downloadModel({
    void Function(int bytesReceived, int totalBytes)? onProgress,
  }) async {
    await _ensureDir();
    final finalPath = p.join(_modelsDir!, _modelFileName);
    final partialPath = '$finalPath$_partialSuffix';

    // Already downloaded — skip
    final finalFile = File(finalPath);
    if (await finalFile.exists() && await finalFile.length() > 10 * 1024 * 1024) {
      debugPrint('ModelDownload: Model already exists at $finalPath');
      onProgress?.call(1, 1);
      return finalPath;
    }

    // Clean up any previous partial download
    final partialFile = File(partialPath);
    if (await partialFile.exists()) {
      await partialFile.delete();
    }

    debugPrint('ModelDownload: Starting download from $_modelUrl');
    final stopwatch = Stopwatch()..start();

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_modelUrl));
      // Follow redirects (HuggingFace uses CDN redirects)
      request.followRedirects = true;
      request.maxRedirects = 5;

      final response = await request.close();

      if (response.statusCode != 200) {
        throw HttpException(
          'Download failed: HTTP ${response.statusCode} ${response.reasonPhrase}',
        );
      }

      final totalBytes = response.contentLength; // -1 if unknown
      int bytesReceived = 0;

      final sink = partialFile.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        bytesReceived += chunk.length;
        onProgress?.call(bytesReceived, totalBytes);
      }

      await sink.flush();
      await sink.close();

      // Verify the download is reasonable size
      final downloadedSize = await partialFile.length();
      if (downloadedSize < 10 * 1024 * 1024) {
        await partialFile.delete();
        throw Exception(
          'Downloaded file too small (${downloadedSize} bytes). '
          'Expected ~109 MB. Download may have been truncated.',
        );
      }

      // Atomic rename: partial → final
      await partialFile.rename(finalPath);

      stopwatch.stop();
      final sizeMB = (downloadedSize / (1024 * 1024)).toStringAsFixed(1);
      final seconds = stopwatch.elapsedMilliseconds / 1000;
      debugPrint('ModelDownload: Complete — $sizeMB MB in ${seconds.toStringAsFixed(1)}s');

      return finalPath;
    } finally {
      client.close();
    }
  }

  /// Delete the cached model (e.g. to force re-download).
  Future<void> deleteModel() async {
    await _ensureDir();
    final file = File(p.join(_modelsDir!, _modelFileName));
    if (await file.exists()) await file.delete();
    final partial = File(p.join(_modelsDir!, '$_modelFileName$_partialSuffix'));
    if (await partial.exists()) await partial.delete();
    debugPrint('ModelDownload: Model deleted');
  }

  /// Get the size of the cached model in bytes, or 0 if not downloaded.
  Future<int> get modelSize async {
    final path = await modelPath;
    final file = File(path);
    if (!await file.exists()) return 0;
    return file.length();
  }
}
