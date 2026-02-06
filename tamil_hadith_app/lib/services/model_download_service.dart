import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ══════════════════════════════════════════════════════════════
// Model variant definitions
// ══════════════════════════════════════════════════════════════

/// Available TTS model variants, ordered by size.
enum TtsModelVariant {
  /// INT8 quantised — smallest, fastest, slightly lower quality.
  int8(
    fileName: 'model_int8.mnn',
    label: 'சிறிய (INT8)',
    description: 'வேகமான, குறைந்த அளவு',
    sizeMB: 28,
    url: 'https://huggingface.co/developerabu/mms-tts-tam-mnn/resolve/main/model_int8.mnn',
  ),

  /// FP16+INT8 hybrid — balanced quality / size.
  fp16Int8(
    fileName: 'model_fp16_int8.mnn',
    label: 'நடுத்தர (FP16+INT8)',
    description: 'சிறந்த தரம், நடுத்தர அளவு',
    sizeMB: 55,
    url: 'https://huggingface.co/developerabu/mms-tts-tam-mnn/resolve/main/model_fp16_int8.mnn',
  );

  const TtsModelVariant({
    required this.fileName,
    required this.label,
    required this.description,
    required this.sizeMB,
    required this.url,
  });

  final String fileName;
  final String label;
  final String description;
  final int sizeMB;
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

/// Downloads and caches MNN TTS models from HuggingFace.
///
/// On first launch the small INT8 model (~28 MB) is downloaded.
/// Users can switch to the higher-quality FP16+INT8 model from settings.
class ModelDownloadService {
  static const String _prefKey = 'selected_model';

  /// Partial download suffix — renamed to final name only after success.
  static const String _partialSuffix = '.part';

  String? _modelsDir;

  /// The currently-selected variant (persisted via SharedPreferences).
  TtsModelVariant _selected = TtsModelVariant.int8;
  TtsModelVariant get selectedVariant => _selected;

  /// Initialize the models directory and load the persisted selection.
  Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    _modelsDir = p.join(dir.path, 'models');
    await Directory(_modelsDir!).create(recursive: true);

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    if (stored != null) {
      _selected = TtsModelVariant.fromFileName(stored);
    }
  }

  Future<void> _ensureDir() async {
    if (_modelsDir != null) return;
    await initialize();
  }

  /// Persist the user's model choice.
  Future<void> setSelectedVariant(TtsModelVariant variant) async {
    _selected = variant;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, variant.fileName);
  }

  /// Full path to the currently-selected model file.
  Future<String> get modelPath async {
    await _ensureDir();
    return p.join(_modelsDir!, _selected.fileName);
  }

  /// Full path for an arbitrary variant.
  Future<String> pathForVariant(TtsModelVariant variant) async {
    await _ensureDir();
    return p.join(_modelsDir!, variant.fileName);
  }

  /// Whether the currently-selected model has been downloaded.
  Future<bool> get isModelDownloaded async =>
      isVariantDownloaded(_selected);

  /// Whether a specific variant has been downloaded.
  Future<bool> isVariantDownloaded(TtsModelVariant variant) async {
    await _ensureDir();
    final file = File(p.join(_modelsDir!, variant.fileName));
    if (!await file.exists()) return false;
    final size = await file.length();
    return size > 5 * 1024 * 1024; // at least 5 MB
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
    final v = variant ?? _selected;
    final finalPath = p.join(_modelsDir!, v.fileName);
    final partialPath = '$finalPath$_partialSuffix';

    // Already downloaded — skip
    final finalFile = File(finalPath);
    if (await finalFile.exists() && await finalFile.length() > 5 * 1024 * 1024) {
      debugPrint('ModelDownload: ${v.fileName} already exists');
      onProgress?.call(1, 1);
      return finalPath;
    }

    // Clean up any previous partial download
    final partialFile = File(partialPath);
    if (await partialFile.exists()) {
      await partialFile.delete();
    }

    debugPrint('ModelDownload: Starting download of ${v.fileName} from ${v.url}');
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
          'Downloaded file too small (${downloadedSize} bytes). '
          'Expected ~${v.sizeMB} MB.',
        );
      }

      // Atomic rename: partial → final
      await partialFile.rename(finalPath);

      stopwatch.stop();
      final sizeMB = (downloadedSize / (1024 * 1024)).toStringAsFixed(1);
      final seconds = stopwatch.elapsedMilliseconds / 1000;
      debugPrint('ModelDownload: ${v.fileName} complete — '
          '$sizeMB MB in ${seconds.toStringAsFixed(1)}s');

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
    final partial = File(p.join(_modelsDir!, '${variant.fileName}$_partialSuffix'));
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

  /// Get the size of the currently-selected model in bytes, or 0.
  Future<int> get modelSize => variantSize(_selected);
}
