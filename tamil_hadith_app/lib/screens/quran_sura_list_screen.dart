import 'package:flutter/material.dart';

import '../models/quran_verse.dart';
import '../services/hadith_database.dart';
import '../services/quran_database.dart';
import '../theme.dart';
import '../widgets/animated_press_card.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/scroll_to_top_fab.dart';
import 'bookmarks_screen.dart';
import 'quran_tafsir_screen.dart';
import 'quran_verse_list_screen.dart';
import 'quran_verse_detail_screen.dart';
import 'settings_screen.dart';

/// Home screen for Quran — list of 114 suras
class QuranSuraListScreen extends StatefulWidget {
  final QuranDatabase database;
  final HadithDatabase hadithDatabase;

  const QuranSuraListScreen({
    super.key,
    required this.database,
    required this.hadithDatabase,
  });

  @override
  State<QuranSuraListScreen> createState() => _QuranSuraListScreenState();
}

class _QuranSuraListScreenState extends State<QuranSuraListScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;
  int _totalVerses = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final count = await widget.database.getCount();
    setState(() {
      _totalVerses = count;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final appBarBg = isDarkMode ? const Color(0xFF5A4500) : AppTheme.emerald;
    final gradientColors = isDarkMode
        ? [const Color(0xFF5A4500), const Color(0xFF4A3800)]
        : [AppTheme.emerald, AppTheme.emeraldDark];
    final heroAccent = isDarkMode ? AppTheme.darkGold : AppTheme.gold;
    return Scaffold(
      body: _isLoading
          ? CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 220,
                  floating: false,
                  pinned: true,
                  backgroundColor: appBarBg,
                  foregroundColor: const Color(0xFFFAF8F3),
                  centerTitle: true,
                  //title: const Text('திருக்குர்ஆன்'),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: gradientColors,
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: SkeletonList(itemCount: 6)),
              ],
            )
          : CustomScrollView(
              controller: _scrollController,
              slivers: [
                // ── Collapsing App Bar ──
                SliverAppBar(
                  expandedHeight: 220,
                  floating: false,
                  pinned: true,
                  stretch: true,
                  backgroundColor: appBarBg,
                  foregroundColor: const Color(0xFFFAF8F3),
                  centerTitle: true,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.bookmark_rounded),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BookmarksScreen(
                            database: widget.hadithDatabase,
                            quranDatabase: widget.database,
                          ),
                        ),
                      ),
                      tooltip: 'புக்மார்க்கள்',
                    ),
                    IconButton(
                      icon: const Icon(Icons.search_rounded),
                      onPressed: () => _showSearch(context),
                      tooltip: 'தேடு',
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_rounded),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      ),
                      tooltip: 'அமைப்புகள்',
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: gradientColors,
                        ),
                      ),
                      child: SafeArea(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Decorative circle with ornament
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: heroAccent,
                                      width: 1.5,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: heroAccent.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.menu_book_rounded,
                                    color: heroAccent,
                                    size: 28,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            const Text(
                              'திருக்குர்ஆன்',
                              style: TextStyle(
                                color: Color(0xFFFAF8F3),
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'தமிழ் மொழிபெயர்ப்பு',
                              style: TextStyle(
                                color: heroAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 8),

                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: heroAccent.withValues(alpha: 0.4),
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '114 சூராக்கள் • $_totalVerses வசனங்கள்',
                                style: TextStyle(
                                  color: heroAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Search bar shortcut ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: GestureDetector(
                      onTap: () => _showSearch(context),
                      child: Builder(
                        builder: (context) {
                          final theme = Theme.of(context);
                          final isDark = theme.brightness == Brightness.dark;
                          final cardBg = isDark ? AppTheme.darkCard : AppTheme.surface;
                          final border = isDark ? AppTheme.darkBorder : AppTheme.warmBorder;
                          final subtle = isDark ? AppTheme.darkSubtle : AppTheme.subtleText;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: border),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.14 : 0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.search_rounded,
                                  color: subtle,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'வசனம் தேடுங்கள்...',
                                  style: TextStyle(
                                    color: isDark ? AppTheme.darkSubtle : AppTheme.mutedText,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                // ── Section header ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Builder(
                      builder: (context) {
                        final emerald = Theme.of(context).brightness == Brightness.dark
                            ? AppTheme.darkEmerald
                            : AppTheme.emerald;
                        return Text(
                          'சூராக்கள்',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: emerald,
                            letterSpacing: 0.5,
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // ── Sura list ──
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final suraNum = index + 1;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AnimatedPressCard(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => QuranVerseListScreen(
                                  database: widget.database,
                                  suraNumber: suraNum,
                                ),
                              ),
                            );
                          },
                          child: _SuraCard(
                            suraNumber: suraNum,
                            suraName: SuraNames.getName(suraNum),
                            verseCount: SuraNames.getVerseCount(suraNum),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => QuranVerseListScreen(
                                    database: widget.database,
                                    suraNumber: suraNum,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    }, childCount: 114),
                  ),
                ),
              ],
            ),
      floatingActionButton: _isLoading
          ? null
          : ScrollToTopFab(
              scrollController: _scrollController,
              heroTag: 'quran_scroll_top',
            ),
    );
  }

  void _showSearch(BuildContext context) {
    showSearch(
      context: context,
      delegate: _QuranSearchDelegate(widget.database),
    );
  }
}

class _SuraCard extends StatelessWidget {
  final int suraNumber;
  final String suraName;
  final int verseCount;
  final VoidCallback onTap;

  const _SuraCard({
    required this.suraNumber,
    required this.suraName,
    required this.verseCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : AppTheme.surface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.warmBorder;
    final gold = isDark ? AppTheme.darkGold : AppTheme.gold;
    final textColor = isDark ? const Color(0xFFF5F0E8) : AppTheme.darkText;
    final subtle = isDark ? AppTheme.darkSubtle : AppTheme.subtleText;

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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
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
                    '$suraNumber',
                    style: TextStyle(
                      color: gold,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suraName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$verseCount வசனங்கள்',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: subtle,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: gold,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuranSearchDelegate extends SearchDelegate<QuranVerse?> {
  final QuranDatabase database;

  _QuranSearchDelegate(this.database);

  // Cache search results so scroll position is preserved on back-navigation
  String _lastQuery = '';
  Future<List<QuranVerse>>? _cachedFuture;
  List<QuranVerse>? _cachedResults;

  @override
  String get searchFieldLabel => 'உரை அல்லது சூரா:வசனம் தேடுங்கள்...';

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: TextStyle(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          fontSize: 16,
        ),
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear_rounded),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults();

  /// Matches sura:aya pattern (e.g. "2:255", "114:1")
  static final RegExp _verseRefPattern = RegExp(r'^(\d+):(\d+)$');

  /// Matches standalone sura number (e.g. "2", "114")
  static final RegExp _suraNumPattern = RegExp(r'^\d+$');

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_rounded,
              size: 48,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 12),
            Text(
              'உரை அல்லது சூரா:வசனம் தேடுங்கள்',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }
    // Allow single-char queries for number-based search
    final trimmed = query.trim();
    final isNumeric =
        _verseRefPattern.hasMatch(trimmed) || _suraNumPattern.hasMatch(trimmed);
    if (!isNumeric && query.length < 2) {
      return Center(
        child: Text(
          'குறைந்தது 2 எழுத்துகள் தட்டச்சு செய்யவும்',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      );
    }
    return _buildSearchResults();
  }

  /// Search by sura:aya, sura number, or text depending on query format
  Future<List<QuranVerse>> _searchByQuery() async {
    final trimmed = query.trim();

    // Pattern: "2:255" → specific verse
    final refMatch = _verseRefPattern.firstMatch(trimmed);
    if (refMatch != null) {
      final sura = int.tryParse(refMatch.group(1)!);
      final aya = int.tryParse(refMatch.group(2)!);
      if (sura != null && aya != null && sura >= 1 && sura <= 114) {
        final verse = await database.getVerse(sura, aya);
        return verse != null ? [verse] : [];
      }
    }

    // Pattern: "2" → all verses of sura 2
    if (_suraNumPattern.hasMatch(trimmed)) {
      final sura = int.tryParse(trimmed);
      if (sura != null && sura >= 1 && sura <= 114) {
        return database.getVersesBySura(sura);
      }
    }

    return database.searchVerses(query);
  }

  Widget _buildSearchResults() {
    // Only re-query when the search text actually changes
    if (query != _lastQuery) {
      _lastQuery = query;
      _cachedResults = null;
      _cachedFuture = _searchByQuery().then((results) {
        _cachedResults = results;
        return results;
      });
    }
    // If results are already cached, show them immediately (no loading frame)
    if (_cachedResults != null) {
      return _buildResultsList(_cachedResults!);
    }
    return FutureBuilder<List<QuranVerse>>(
      future: _cachedFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final results = snapshot.data ?? [];
        _cachedResults = results;
        return _buildResultsList(results);
      },
    );
  }

  Widget _buildResultsList(List<QuranVerse> results) {
    if (results.isEmpty) {
      return Builder(builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? const Color(0xFFF5F0E8) : AppTheme.darkText;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 48,
                color: textColor.withValues(alpha: 0.15),
              ),
              const SizedBox(height: 12),
              Text(
                'முடிவுகள் இல்லை',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        );
      });
    }
    return ListView.separated(
      key: const PageStorageKey('quran_search_results'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: results.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final verse = results[index];
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final cardBg = isDark ? AppTheme.darkCard : AppTheme.surface;
        final border = isDark ? AppTheme.darkBorder : AppTheme.warmBorder;
        final gold = isDark ? AppTheme.darkGold : AppTheme.gold;
        final emerald = isDark ? AppTheme.darkEmerald : AppTheme.emerald;
        final textColor = isDark ? const Color(0xFFF5F0E8) : AppTheme.darkText;
        final subtle = isDark ? AppTheme.darkSubtle : AppTheme.subtleText;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      QuranVerseDetailScreen(verses: [verse], startIndex: 0),
                ),
              );
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: emerald,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${verse.sura}:${verse.aya}',
                          style: TextStyle(
                            color: gold,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          SuraNames.getName(verse.sura),
                          style: TextStyle(
                            fontSize: 12,
                            color: subtle,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    verse.preview,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: textColor,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (verse.tafsirPreview.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: emerald.withValues(alpha: isDark ? 0.12 : 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: gold.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        verse.tafsirPreview,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: isDark ? const Color(0xFFD4A07A) : const Color(0xFF5D4037),
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => QuranTafsirScreen(verse: verse),
                            ),
                          );
                        },
                        icon: const Icon(Icons.menu_book_outlined, size: 14),
                        label: const Text('தஃப்ஸீர்'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: emerald,
                          side: BorderSide(
                            color: gold.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
