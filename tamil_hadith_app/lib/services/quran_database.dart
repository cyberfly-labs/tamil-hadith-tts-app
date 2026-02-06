import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/quran_verse.dart';

/// Database service for accessing Tamil Quran translation (IFT)
class QuranDatabase {
  Database? _db;

  bool get isOpen => _db != null;

  /// Initialize database by copying from assets if needed
  Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'tamil_ift.db');

    // Copy from assets if not exists
    if (!await File(dbPath).exists()) {
      final data = await rootBundle.load('assets/db/tamil_ift.db');
      final bytes = data.buffer.asUint8List();
      await File(dbPath).writeAsBytes(bytes, flush: true);
    }

    _db = await openDatabase(dbPath, readOnly: true);
  }

  /// Get all distinct sura numbers
  Future<List<int>> getSuras() async {
    _ensureOpen();
    final result = await _db!.rawQuery(
        'SELECT DISTINCT sura FROM tamil_ift ORDER BY sura');
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
    return result.map((row) => QuranVerse.fromMap(row)).toList();
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
    return QuranVerse.fromMap(result.first);
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
    return QuranVerse.fromMap(result.first);
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
    return result.map((row) => QuranVerse.fromMap(row)).toList();
  }

  /// Get total verse count
  Future<int> getCount() async {
    _ensureOpen();
    final result =
        await _db!.rawQuery('SELECT COUNT(*) as cnt FROM tamil_ift');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get verse count for a sura
  Future<int> getVerseCount(int sura) async {
    _ensureOpen();
    final result = await _db!.rawQuery(
        'SELECT COUNT(*) as cnt FROM tamil_ift WHERE sura = ?', [sura]);
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
      return result.map((row) => QuranVerse.fromMap(row)).toList();
    }
    final result = await _db!.query(
      'tamil_ift',
      orderBy: 'sura ASC, aya ASC',
      limit: limit,
      offset: offset,
    );
    return result.map((row) => QuranVerse.fromMap(row)).toList();
  }

  void _ensureOpen() {
    if (_db == null) {
      throw StateError(
          'QuranDatabase not initialized. Call initialize() first.');
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
