import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/hadith.dart';

/// Database service for accessing Bukhari hadith collection
class HadithDatabase {
  Database? _db;

  bool get isOpen => _db != null;

  /// Initialize database by copying from assets if needed
  Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'bukhari.db');

    // Copy from assets if not exists
    if (!await File(dbPath).exists()) {
      final data = await rootBundle.load('assets/db/bukhari.db');
      final bytes = data.buffer.asUint8List();
      await File(dbPath).writeAsBytes(bytes, flush: true);
    }

    _db = await openDatabase(dbPath, readOnly: true);
  }

  /// Get all distinct books
  Future<List<String>> getBooks() async {
    _ensureOpen();
    final result = await _db!.rawQuery(
        'SELECT DISTINCT book FROM hadiths ORDER BY id');
    return result.map((row) => row['book'] as String).toList();
  }

  /// Get hadiths for a specific book
  Future<List<Hadith>> getHadithsByBook(String book) async {
    _ensureOpen();
    final result = await _db!.query(
      'hadiths',
      where: 'book = ?',
      whereArgs: [book],
      orderBy: 'hadith_number ASC',
    );
    return result.map((row) => Hadith.fromMap(row)).toList();
  }

  /// Get a single hadith by ID
  Future<Hadith?> getHadith(int id) async {
    _ensureOpen();
    final result = await _db!.query(
      'hadiths',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return Hadith.fromMap(result.first);
  }

  /// Get hadiths by hadith number
  Future<List<Hadith>> getHadithsByNumber(int number) async {
    _ensureOpen();
    final result = await _db!.query(
      'hadiths',
      where: 'hadith_number = ?',
      whereArgs: [number],
    );
    return result.map((row) => Hadith.fromMap(row)).toList();
  }

  /// Search hadiths by Tamil text
  Future<List<Hadith>> searchHadiths(String query) async {
    _ensureOpen();
    final result = await _db!.query(
      'hadiths',
      where: 'text_tamil LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'hadith_number ASC',
      limit: 50,
    );
    return result.map((row) => Hadith.fromMap(row)).toList();
  }

  /// Get total hadith count
  Future<int> getCount() async {
    _ensureOpen();
    final result = await _db!.rawQuery('SELECT COUNT(*) as cnt FROM hadiths');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get hadiths paginated
  Future<List<Hadith>> getHadithsPaginated({
    required int offset,
    required int limit,
    String? book,
  }) async {
    _ensureOpen();
    if (book != null) {
      final result = await _db!.query(
        'hadiths',
        where: 'book = ?',
        whereArgs: [book],
        orderBy: 'hadith_number ASC',
        limit: limit,
        offset: offset,
      );
      return result.map((row) => Hadith.fromMap(row)).toList();
    }
    final result = await _db!.query(
      'hadiths',
      orderBy: 'id ASC',
      limit: limit,
      offset: offset,
    );
    return result.map((row) => Hadith.fromMap(row)).toList();
  }

  void _ensureOpen() {
    if (_db == null) {
      throw StateError('Database not initialized. Call initialize() first.');
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
