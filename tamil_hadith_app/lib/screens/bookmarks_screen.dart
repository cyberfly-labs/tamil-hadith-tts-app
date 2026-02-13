import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/hadith.dart';
import '../models/quran_verse.dart';
import '../services/bookmark_service.dart';
import '../services/hadith_database.dart';
import '../services/quran_database.dart';
import '../widgets/animated_press_card.dart';
import '../widgets/shimmer_loading.dart';
import 'hadith_detail_screen.dart';
import 'quran_verse_detail_screen.dart';

/// Screen showing all bookmarked hadiths and quran verses
class BookmarksScreen extends StatefulWidget {
  final HadithDatabase database;
  final QuranDatabase quranDatabase;

  const BookmarksScreen({
    super.key,
    required this.database,
    required this.quranDatabase,
  });

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  final BookmarkService _bookmarkService = BookmarkService();
  List<dynamic> _bookmarks = []; // Can be Hadith or QuranVerse
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
    final List<dynamic> items = [];
    for (final row in rows) {
      final collectionStr = row['collection'] as String? ?? 'bukhari';

      if (collectionStr == 'quran') {
        final suraNumber = int.tryParse(row['book'] as String? ?? '1') ?? 1;
        final ayaNumber = row['hadith_number'] as int;
        
        // Try to load full verse
        final fullVerse = await widget.quranDatabase.getVerse(suraNumber, ayaNumber);
        if (fullVerse != null) {
          items.add(fullVerse);
        } else {
          items.add(QuranVerse(
            id: 0,
            sura: suraNumber,
            aya: ayaNumber,
            text: row['text_tamil'] as String? ?? '',
          ));
        }
      } else {
        final collection = collectionStr == 'muslim'
            ? HadithCollection.muslim
            : HadithCollection.bukhari;
        final hadithNumber = row['hadith_number'] as int;

        // Try to load the full hadith from the database
        final fullHadith =
            await widget.database.getHadith(collection, hadithNumber);
        if (fullHadith != null) {
          items.add(fullHadith);
        } else {
          // Fallback: construct from bookmark data
          items.add(Hadith(
            hadithNumber: hadithNumber,
            collection: collection,
            content: row['text_tamil'] as String? ?? '',
            bookTitle: row['book'] as String? ?? '',
            bookNumber: 0,
            lessionHeading: row['chapter'] as String? ?? '',
          ));
        }
      }
    }
    if (mounted) {
      setState(() {
        _bookmarks = items;
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
          ? const SingleChildScrollView(child: SkeletonList(itemCount: 4))
          : _bookmarks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.elasticOut,
                        builder: (context, value, child) {
                          return Transform.scale(
                            scale: value,
                            child: child,
                          );
                        },
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4A04A).withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFD4A04A).withValues(alpha: 0.2),
                            ),
                          ),
                          child: const Icon(Icons.bookmark_outline_rounded,
                              size: 40,
                              color: Color(0xFFD4A04A)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'புக்மார்க்கள் இல்லை',
                        style: TextStyle(
                          fontSize: 18,
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
                    final item = _bookmarks[index];
                    final String key = item is Hadith ? item.cacheKey : (item as QuranVerse).cacheKey;

                    return Dismissible(
                      key: ValueKey(key),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red.shade400,
                        ),
                      ),
                      confirmDismiss: (_) async {
                        HapticFeedback.mediumImpact();
                        return true;
                      },
                      onDismissed: (_) async {
                        if (item is Hadith) {
                          await _bookmarkService.toggleBookmark(
                            key: item.cacheKey,
                            collection: item.collection.name,
                            hadithNumber: item.hadithNumber,
                            book: item.book,
                          );
                        } else {
                          final v = item as QuranVerse;
                          await _bookmarkService.toggleBookmark(
                            key: v.cacheKey,
                            collection: 'quran',
                            hadithNumber: v.aya,
                            book: v.sura.toString(),
                          );
                        }
                      },
                      child: AnimatedPressCard(
                        onTap: () {
                          if (item is Hadith) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    HadithDetailScreen(hadith: item),
                              ),
                            );
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    QuranVerseDetailScreen(
                                      verses: [item as QuranVerse],
                                      startIndex: 0,
                                    ),
                              ),
                            );
                          }
                        },
                        child: _BookmarkCard(
                          item: item,
                          onTap: () {
                            if (item is Hadith) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      HadithDetailScreen(hadith: item),
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      QuranVerseDetailScreen(
                                        verses: [item as QuranVerse],
                                        startIndex: 0,
                                      ),
                                ),
                              );
                            }
                          },
                          onRemove: () async {
                            HapticFeedback.lightImpact();
                            if (item is Hadith) {
                              await _bookmarkService.toggleBookmark(
                                key: item.cacheKey,
                                collection: item.collection.name,
                                hadithNumber: item.hadithNumber,
                                book: item.book,
                              );
                            } else {
                              final v = item as QuranVerse;
                              await _bookmarkService.toggleBookmark(
                                key: v.cacheKey,
                                collection: 'quran',
                                hadithNumber: v.aya,
                                book: v.sura.toString(),
                              );
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  final dynamic item; // Hadith or QuranVerse
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _BookmarkCard({
    required this.item,
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
                    item is Hadith ? '${(item as Hadith).hadithNumber}' : '${(item as QuranVerse).aya}',
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
                              item is Hadith ? (item as Hadith).collection.shortName : 'குர்ஆன்',
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
                              item is Hadith ? (item as Hadith).book : SuraNames.getName((item as QuranVerse).sura),
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
                        item is Hadith ? (item as Hadith).preview : (item as QuranVerse).preview,
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
