import 'package:flutter/material.dart';

import '../models/hadith.dart';
import '../services/bookmark_service.dart';
import '../services/hadith_database.dart';
import 'hadith_detail_screen.dart';

/// Screen showing all bookmarked hadiths
class BookmarksScreen extends StatefulWidget {
  final HadithDatabase database;

  const BookmarksScreen({super.key, required this.database});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  final BookmarkService _bookmarkService = BookmarkService();
  List<Hadith> _bookmarks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
    _bookmarkService.addListener(_onBookmarksChanged);
  }

  @override
  void dispose() {
    _bookmarkService.removeListener(_onBookmarksChanged);
    super.dispose();
  }

  void _onBookmarksChanged() {
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final rows = await _bookmarkService.getBookmarks();
    final List<Hadith> hadiths = [];
    for (final row in rows) {
      final collectionStr = row['collection'] as String? ?? 'bukhari';
      final collection = collectionStr == 'muslim'
          ? HadithCollection.muslim
          : HadithCollection.bukhari;
      final hadithNumber = row['hadith_number'] as int;

      // Try to load the full hadith from the database
      final fullHadith =
          await widget.database.getHadith(collection, hadithNumber);
      if (fullHadith != null) {
        hadiths.add(fullHadith);
      } else {
        // Fallback: construct from bookmark data
        hadiths.add(Hadith(
          hadithNumber: hadithNumber,
          collection: collection,
          content: row['text_tamil'] as String? ?? '',
          bookTitle: row['book'] as String? ?? '',
          bookNumber: 0,
          lessionHeading: row['chapter'] as String? ?? '',
        ));
      }
    }
    if (mounted) {
      setState(() {
        _bookmarks = hadiths;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('புக்மார்க்கள்'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bookmarks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4A04A).withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFD4A04A).withValues(alpha: 0.2),
                          ),
                        ),
                        child: const Icon(Icons.bookmark_outline_rounded,
                            size: 36,
                            color: Color(0xFFD4A04A)),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'புக்மார்க்கள் இல்லை',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'ஹதீஸ் பக்கத்தில் ★ ஐ தட்டவும்',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B6B6B),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: _bookmarks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final hadith = _bookmarks[index];
                    return _BookmarkCard(
                      hadith: hadith,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                HadithDetailScreen(hadith: hadith),
                          ),
                        );
                      },
                      onRemove: () async {
                        await _bookmarkService.toggleBookmark(
                          key: hadith.cacheKey,
                          collection: hadith.collection.name,
                          hadithNumber: hadith.hadithNumber,
                          book: hadith.book,
                        );
                      },
                    );
                  },
                ),
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  final Hadith hadith;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _BookmarkCard({
    required this.hadith,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8DDD0), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Number badge — emerald gradient
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF1B4D3E),
                        Color(0xFF0D3020),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFD4A04A),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${hadith.hadithNumber}',
                    style: const TextStyle(
                      color: Color(0xFFD4A04A),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B4D3E),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              hadith.collection.shortName,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFD4A04A),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              hadith.book,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1B4D3E),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hadith.preview,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Color(0xFF1A1A1A),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Remove button
                IconButton(
                  icon: Icon(Icons.bookmark_remove_rounded,
                      color: Colors.red.shade400, size: 20),
                  onPressed: onRemove,
                  tooltip: 'புக்மார்க் நீக்கு',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
