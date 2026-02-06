import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Manages hadith bookmarks in a local SQLite database.
///
/// Bookmarks are stored in a separate writable DB (not the read-only hadith DB).
/// Path: <documents>/bookmarks.db
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
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS bookmarks (
            hadith_number INTEGER PRIMARY KEY,
            book TEXT NOT NULL,
            chapter TEXT NOT NULL DEFAULT '',
            text_tamil TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );

    debugPrint('BookmarkService: initialized at $dbPath');
  }

  void _ensureOpen() {
    if (_db == null) {
      throw StateError('BookmarkService not initialized');
    }
  }

  /// Check if a hadith is bookmarked.
  bool isBookmarked(int hadithNumber) {
    if (_db == null) return false;
    // Use a cached sync check (preloaded set)
    return _bookmarkedSet.contains(hadithNumber);
  }

  /// In-memory set for fast sync lookups.
  final Set<int> _bookmarkedSet = {};

  /// Load all bookmarked hadith numbers into the in-memory set.
  Future<void> loadBookmarks() async {
    _ensureOpen();
    final rows = await _db!.query('bookmarks', columns: ['hadith_number']);
    _bookmarkedSet.clear();
    for (final row in rows) {
      _bookmarkedSet.add(row['hadith_number'] as int);
    }
    debugPrint('BookmarkService: loaded ${_bookmarkedSet.length} bookmarks');
  }

  /// Toggle bookmark state. Returns the new bookmarked state.
  Future<bool> toggleBookmark({
    required int hadithNumber,
    required String book,
    String chapter = '',
    String textTamil = '',
  }) async {
    _ensureOpen();

    if (_bookmarkedSet.contains(hadithNumber)) {
      // Remove
      await _db!.delete(
        'bookmarks',
        where: 'hadith_number = ?',
        whereArgs: [hadithNumber],
      );
      _bookmarkedSet.remove(hadithNumber);
      debugPrint('BookmarkService: removed #$hadithNumber');
      notifyListeners();
      return false;
    } else {
      // Add
      await _db!.insert(
        'bookmarks',
        {
          'hadith_number': hadithNumber,
          'book': book,
          'chapter': chapter,
          'text_tamil': textTamil,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      _bookmarkedSet.add(hadithNumber);
      debugPrint('BookmarkService: added #$hadithNumber');
      notifyListeners();
      return true;
    }
  }

  /// Get all bookmarked hadith numbers (ordered by most recent first).
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
