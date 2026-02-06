import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Manages hadith bookmarks in a local SQLite database.
///
/// Bookmarks are stored in a separate writable DB (not the read-only hadith DB).
/// Path: <documents>/bookmarks.db
///
/// Key is `{collection}_{hadithNumber}` to uniquely identify across collections.
class BookmarkService extends ChangeNotifier {
  Database? _db;

  /// Singleton instance so bookmark state is shared across screens.
  static final BookmarkService _instance = BookmarkService._();
  factory BookmarkService() => _instance;
  BookmarkService._();

  bool get isOpen => _db != null;

  /// Initialize the bookmarks database, creating the table if needed.
  Future<void> initialize() async {
    if (_db != null) return;

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'bookmarks.db');

    _db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS bookmarks (
            key TEXT PRIMARY KEY,
            collection TEXT NOT NULL DEFAULT 'bukhari',
            hadith_number INTEGER NOT NULL,
            book TEXT NOT NULL,
            chapter TEXT NOT NULL DEFAULT '',
            text_tamil TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Migrate from v1 (hadith_number PK) to v2 (key PK with collection)
          await db.execute('''
            CREATE TABLE IF NOT EXISTS bookmarks_v2 (
              key TEXT PRIMARY KEY,
              collection TEXT NOT NULL DEFAULT 'bukhari',
              hadith_number INTEGER NOT NULL,
              book TEXT NOT NULL,
              chapter TEXT NOT NULL DEFAULT '',
              text_tamil TEXT NOT NULL DEFAULT '',
              created_at INTEGER NOT NULL
            )
          ''');
          // Copy old data — all old bookmarks are from bukhari
          final old = await db.query('bookmarks');
          for (final row in old) {
            final num = row['hadith_number'] as int;
            await db.insert('bookmarks_v2', {
              'key': 'bukhari_$num',
              'collection': 'bukhari',
              'hadith_number': num,
              'book': row['book'] ?? '',
              'chapter': row['chapter'] ?? '',
              'text_tamil': row['text_tamil'] ?? '',
              'created_at': row['created_at'] ?? 0,
            });
          }
          await db.execute('DROP TABLE IF EXISTS bookmarks');
          await db.execute('ALTER TABLE bookmarks_v2 RENAME TO bookmarks');
        }
      },
    );

    debugPrint('BookmarkService: initialized at $dbPath');
  }

  void _ensureOpen() {
    if (_db == null) {
      throw StateError('BookmarkService not initialized');
    }
  }

  /// Check if a hadith is bookmarked by its cache key.
  bool isBookmarked(String key) {
    if (_db == null) return false;
    return _bookmarkedSet.contains(key);
  }

  /// In-memory set for fast sync lookups.
  final Set<String> _bookmarkedSet = {};

  /// Load all bookmarked keys into the in-memory set.
  Future<void> loadBookmarks() async {
    _ensureOpen();
    final rows = await _db!.query('bookmarks', columns: ['key']);
    _bookmarkedSet.clear();
    for (final row in rows) {
      _bookmarkedSet.add(row['key'] as String);
    }
    debugPrint('BookmarkService: loaded ${_bookmarkedSet.length} bookmarks');
  }

  /// Toggle bookmark state. Returns the new bookmarked state.
  Future<bool> toggleBookmark({
    required String key,
    required String collection,
    required int hadithNumber,
    required String book,
    String chapter = '',
    String textTamil = '',
  }) async {
    _ensureOpen();

    if (_bookmarkedSet.contains(key)) {
      // Remove
      await _db!.delete(
        'bookmarks',
        where: 'key = ?',
        whereArgs: [key],
      );
      _bookmarkedSet.remove(key);
      debugPrint('BookmarkService: removed $key');
      notifyListeners();
      return false;
    } else {
      // Add
      await _db!.insert(
        'bookmarks',
        {
          'key': key,
          'collection': collection,
          'hadith_number': hadithNumber,
          'book': book,
          'chapter': chapter,
          'text_tamil': textTamil,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _bookmarkedSet.add(key);
      debugPrint('BookmarkService: added $key');
      notifyListeners();
      return true;
    }
  }

  /// Get all bookmarked rows (ordered by most recent first).
  Future<List<Map<String, dynamic>>> getBookmarks() async {
    _ensureOpen();
    return _db!.query('bookmarks', orderBy: 'created_at DESC');
  }

  /// Get count of bookmarks.
  int get count => _bookmarkedSet.length;

  /// Close the database.
  Future<void> close() async {
    await _db?.close();
    _db = null;
    _bookmarkedSet.clear();
  }
}
