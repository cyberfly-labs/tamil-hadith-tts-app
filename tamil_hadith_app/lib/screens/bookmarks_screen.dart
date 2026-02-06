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
    final cs = Theme.of(context).colorScheme;

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
                      Icon(Icons.bookmark_outline_rounded,
                          size: 56,
                          color: cs.onSurface.withValues(alpha: 0.15)),
                      const SizedBox(height: 16),
                      Text(
                        'புக்மார்க்கள் இல்லை',
                        style: TextStyle(
                          fontSize: 16,
                          color: cs.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ஹதீஸ் பக்கத்தில் ★ ஐ தட்டவும்',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.3),
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
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Number badge
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${hadith.hadithNumber}',
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
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
                            color: cs.tertiaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            hadith.collection.shortName,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: cs.onTertiaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            hadith.book,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hadith.preview,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: cs.onSurface,
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
                    color: cs.error.withValues(alpha: 0.7), size: 20),
                onPressed: onRemove,
                tooltip: 'புக்மார்க் நீக்கு',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
