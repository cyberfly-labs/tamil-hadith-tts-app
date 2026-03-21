import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/quran_verse.dart';

/// Database service for accessing Tamil Quran translation (IFT)
class QuranDatabase {
  Database? _db;
  Database? _tafsirDb;

  bool get isOpen => _db != null;

  /// Initialize database by copying from assets if needed
  Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'tamil_ift.db');
    final tafsirPath = p.join(dir.path, 'tamil_mokhtasar.db');

    await _copyAssetDbIfMissing('assets/db/tamil_ift.db', dbPath);
    await _copyAssetDbIfMissing('assets/db/tamil_mokhtasar.db', tafsirPath);

    _db = await openDatabase(dbPath, readOnly: true);
    _tafsirDb = await openDatabase(tafsirPath, readOnly: true);
  }

  Future<void> _copyAssetDbIfMissing(String assetPath, String filePath) async {
    if (await File(filePath).exists()) return;
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    await File(filePath).writeAsBytes(bytes, flush: true);
  }

  /// Get all distinct sura numbers
  Future<List<int>> getSuras() async {
    _ensureOpen();
    final result = await _db!.rawQuery(
      'SELECT DISTINCT sura FROM tamil_ift ORDER BY sura',
    );
    return result.map((row) => row['sura'] as int).toList();
  }

  /// Get all verses for a specific sura
  Future<List<QuranVerse>> getVersesBySura(int sura) async {
    _ensureOpen();
    final result = await _db!.query(
      'tamil_ift',
      where: 'sura = ?',
      whereArgs: [sura],
      orderBy: 'aya ASC',
    );
    final verses = result.map((row) => QuranVerse.fromMap(row)).toList();
    return _attachTafsirForSura(sura, verses);
  }

  /// Get a single verse by sura and aya
  Future<QuranVerse?> getVerse(int sura, int aya) async {
    _ensureOpen();
    final result = await _db!.query(
      'tamil_ift',
      where: 'sura = ? AND aya = ?',
      whereArgs: [sura, aya],
      limit: 1,
    );
    if (result.isEmpty) return null;
    final verse = QuranVerse.fromMap(result.first);
    final tafsir = await getTafsir(sura, aya);
    return verse.copyWith(tafsir: tafsir);
  }

  /// Get a single verse by ID
  Future<QuranVerse?> getVerseById(int id) async {
    _ensureOpen();
    final result = await _db!.query(
      'tamil_ift',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (result.isEmpty) return null;
    final verse = QuranVerse.fromMap(result.first);
    final tafsir = await getTafsir(verse.sura, verse.aya);
    return verse.copyWith(tafsir: tafsir);
  }

  /// Search verses by Tamil text
  Future<List<QuranVerse>> searchVerses(String query) async {
    _ensureOpen();
    final result = await _db!.query(
      'tamil_ift',
      where: 'text LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'sura ASC, aya ASC',
      limit: 50,
    );
    final verses = result.map((row) => QuranVerse.fromMap(row)).toList();
    return _attachTafsirToVerses(verses);
  }

  /// Get total verse count
  Future<int> getCount() async {
    _ensureOpen();
    final result = await _db!.rawQuery('SELECT COUNT(*) as cnt FROM tamil_ift');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get verse count for a sura
  Future<int> getVerseCount(int sura) async {
    _ensureOpen();
    final result = await _db!.rawQuery(
      'SELECT COUNT(*) as cnt FROM tamil_ift WHERE sura = ?',
      [sura],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get verses paginated
  Future<List<QuranVerse>> getVersesPaginated({
    required int offset,
    required int limit,
    int? sura,
  }) async {
    _ensureOpen();
    if (sura != null) {
      final result = await _db!.query(
        'tamil_ift',
        where: 'sura = ?',
        whereArgs: [sura],
        orderBy: 'aya ASC',
        limit: limit,
        offset: offset,
      );
      final verses = result.map((row) => QuranVerse.fromMap(row)).toList();
      return _attachTafsirForSura(sura, verses);
    }
    final result = await _db!.query(
      'tamil_ift',
      orderBy: 'sura ASC, aya ASC',
      limit: limit,
      offset: offset,
    );
    final verses = result.map((row) => QuranVerse.fromMap(row)).toList();
    return _attachTafsirToVerses(verses);
  }

  Future<String> getTafsir(int sura, int aya) async {
    _ensureOpen();
    final tafsirMap = await _getTafsirMapForSura(sura);
    return tafsirMap[aya] ?? '';
  }

  Future<List<QuranVerse>> _attachTafsirForSura(
    int sura,
    List<QuranVerse> verses,
  ) async {
    if (verses.isEmpty) return verses;
    final tafsirMap = await _getTafsirMapForSura(sura);
    return verses
        .map((verse) => verse.copyWith(tafsir: tafsirMap[verse.aya] ?? ''))
        .toList();
  }

  Future<List<QuranVerse>> _attachTafsirToVerses(
    List<QuranVerse> verses,
  ) async {
    if (verses.isEmpty) return verses;

    final versesBySura = <int, List<QuranVerse>>{};
    for (final verse in verses) {
      versesBySura.putIfAbsent(verse.sura, () => []).add(verse);
    }

    final tafsirMaps = <int, Map<int, String>>{};
    for (final sura in versesBySura.keys) {
      tafsirMaps[sura] = await _getTafsirMapForSura(sura);
    }

    return verses
        .map(
          (verse) =>
              verse.copyWith(tafsir: tafsirMaps[verse.sura]?[verse.aya] ?? ''),
        )
        .toList();
  }

  Future<Map<int, String>> _getTafsirMapForSura(int sura) async {
    final tafsirDb = _tafsirDb;
    if (tafsirDb == null) return const {};

    final rows = await tafsirDb.query(
      'tafsir',
      where: 'from_ayah LIKE ?',
      whereArgs: ['$sura:%'],
    );

    final tafsirMap = <int, String>{};
    for (final row in rows) {
      final fromAya = _parseAyahNumber(row['from_ayah'] as String?);
      final toAya = _parseAyahNumber(row['to_ayah'] as String?) ?? fromAya;
      final text = (row['text'] as String? ?? '').trim();
      if (fromAya == null || toAya == null || text.isEmpty) continue;

      for (int aya = fromAya; aya <= toAya; aya++) {
        tafsirMap[aya] = text;
      }
    }

    return tafsirMap;
  }

  int? _parseAyahNumber(String? ayahKey) {
    if (ayahKey == null || ayahKey.isEmpty) return null;
    final parts = ayahKey.split(':');
    if (parts.length != 2) return null;
    return int.tryParse(parts[1]);
  }

  void _ensureOpen() {
    if (_db == null) {
      throw StateError(
        'QuranDatabase not initialized. Call initialize() first.',
      );
    }
  }

  Future<void> close() async {
    await _db?.close();
    await _tafsirDb?.close();
    _db = null;
    _tafsirDb = null;
  }
}
