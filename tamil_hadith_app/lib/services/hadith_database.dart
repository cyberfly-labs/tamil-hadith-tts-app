import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/hadith.dart';

/// Database service for accessing multiple hadith collections (Bukhari + Muslim)
class HadithDatabase {
  Database? _db;

  bool get isOpen => _db != null;

  /// Initialize database by copying from assets if needed
  Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'hadith.db');

    // Copy from assets if not exists
    if (!await File(dbPath).exists()) {
      final data = await rootBundle.load('assets/db/hadith.db');
      final bytes = data.buffer.asUint8List();
      await File(dbPath).writeAsBytes(bytes, flush: true);
    }

    _db = await openDatabase(dbPath, readOnly: true);
  }

  // ─────────────────────── Book Index ───────────────────────

  /// Get the book index (head table) for a collection
  Future<List<HadithBookIndex>> getBookIndex(HadithCollection collection) async {
    _ensureOpen();
    final table = collection.headTableName;

    if (collection == HadithCollection.bukhari) {
      final rows = await _db!.rawQuery(
        'SELECT * FROM $table ORDER BY volume ASC, book ASC',
      );
      return rows.map((r) => HadithBookIndex.fromBukhariHead(r)).toList();
    } else {
      final rows = await _db!.rawQuery(
        'SELECT * FROM $table ORDER BY book ASC',
      );
      return rows.map((r) => HadithBookIndex.fromMuslimHead(r)).toList();
    }
  }

  // ─────────────────────── Hadiths ───────────────────────

  /// Get hadiths for a specific book number within a collection
  Future<List<Hadith>> getHadithsByBook(
    HadithCollection collection,
    int bookNumber,
  ) async {
    _ensureOpen();
    final table = collection.tableName;
    final orderCol =
        collection == HadithCollection.bukhari ? 'sno' : 'hadithno';

    final rows = await _db!.query(
      table,
      where: 'book = ?',
      whereArgs: [bookNumber],
      orderBy: '$orderCol ASC',
    );

    return rows.map((r) {
      return collection == HadithCollection.bukhari
          ? Hadith.fromBukhari(r)
          : Hadith.fromMuslim(r);
    }).toList();
  }

  /// Get hadiths paginated for a specific book
  Future<List<Hadith>> getHadithsPaginated({
    required HadithCollection collection,
    required int bookNumber,
    required int offset,
    required int limit,
  }) async {
    _ensureOpen();
    final table = collection.tableName;
    final orderCol =
        collection == HadithCollection.bukhari ? 'sno' : 'hadithno';

    final rows = await _db!.query(
      table,
      where: 'book = ?',
      whereArgs: [bookNumber],
      orderBy: '$orderCol ASC',
      limit: limit,
      offset: offset,
    );

    return rows.map((r) {
      return collection == HadithCollection.bukhari
          ? Hadith.fromBukhari(r)
          : Hadith.fromMuslim(r);
    }).toList();
  }

  /// Get count of hadiths in a specific book
  Future<int> getBookHadithCount(
    HadithCollection collection,
    int bookNumber,
  ) async {
    _ensureOpen();
    final table = collection.tableName;
    final result = await _db!.rawQuery(
      'SELECT COUNT(*) as cnt FROM $table WHERE book = ?',
      [bookNumber],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get total hadith count for a collection
  Future<int> getCount(HadithCollection collection) async {
    _ensureOpen();
    final table = collection.tableName;
    final result =
        await _db!.rawQuery('SELECT COUNT(*) as cnt FROM $table');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Search hadiths by Tamil text across a collection (or both)
  Future<List<Hadith>> searchHadiths(
    String query, {
    HadithCollection? collection,
  }) async {
    _ensureOpen();
    final pattern = '%$query%';
    final List<Hadith> results = [];

    if (collection == null || collection == HadithCollection.bukhari) {
      final rows = await _db!.rawQuery(
        'SELECT * FROM bukhari WHERE content LIKE ? ORDER BY sno ASC LIMIT 30',
        [pattern],
      );
      results.addAll(rows.map((r) => Hadith.fromBukhari(r)));
    }

    if (collection == null || collection == HadithCollection.muslim) {
      final limit = collection == null ? 30 : 50;
      final rows = await _db!.rawQuery(
        'SELECT * FROM sahihmuslim WHERE content LIKE ? ORDER BY hadithno ASC LIMIT ?',
        [pattern, limit],
      );
      results.addAll(rows.map((r) => Hadith.fromMuslim(r)));
    }

    return results;
  }

  /// Get a single hadith by number and collection
  Future<Hadith?> getHadith(
    HadithCollection collection,
    int hadithNumber,
  ) async {
    _ensureOpen();
    final table = collection.tableName;
    final col = collection == HadithCollection.bukhari ? 'sno' : 'hadithno';

    final rows = await _db!.query(
      table,
      where: '$col = ?',
      whereArgs: [hadithNumber],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return collection == HadithCollection.bukhari
        ? Hadith.fromBukhari(rows.first)
        : Hadith.fromMuslim(rows.first);
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
