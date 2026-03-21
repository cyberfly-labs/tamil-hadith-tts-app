import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/hadith.dart';
import '../models/quran_verse.dart';
import '../services/bookmark_service.dart';
import '../services/hadith_database.dart';
import '../services/quran_database.dart';
import '../widgets/animated_press_card.dart';
import '../widgets/shimmer_loading.dart';
import '../theme.dart';
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gold = isDark ? AppTheme.darkGold : AppTheme.gold;
    final textColor = isDark ? const Color(0xFFF5F0E8) : AppTheme.darkText;
    final subtle = isDark ? AppTheme.darkSubtle : AppTheme.subtleText;

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
                            color: gold.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: gold.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Icon(Icons.bookmark_outline_rounded,
                              size: 40, color: gold),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'புக்மார்க்கள் இல்லை',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ஹதீஸ் பக்கத்தில் ★ ஐ தட்டவும்',
                        style: TextStyle(
                          fontSize: 14,
                          color: subtle,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : AppTheme.surface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.warmBorder;
    final gold = isDark ? AppTheme.darkGold : AppTheme.gold;
    final emerald = isDark ? AppTheme.darkEmerald : AppTheme.emerald;
    final textColor = isDark ? const Color(0xFFF5F0E8) : AppTheme.darkText;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.14 : 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [const Color(0xFF5A4500), const Color(0xFF4A3800)]
                          : [AppTheme.emerald, AppTheme.emeraldDark],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: gold, width: 1),
                  ),
                  child: Text(
                    item is Hadith ? '${(item as Hadith).hadithNumber}' : '${(item as QuranVerse).aya}',
                    style: TextStyle(
                      color: gold,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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
                              color: emerald,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item is Hadith ? (item as Hadith).collection.shortName : 'குர்ஆன்',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: gold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item is Hadith ? (item as Hadith).book : SuraNames.getName((item as QuranVerse).sura),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: emerald,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item is Hadith ? (item as Hadith).preview : (item as QuranVerse).preview,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: textColor,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
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
