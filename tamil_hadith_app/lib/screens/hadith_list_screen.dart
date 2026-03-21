import 'package:flutter/material.dart';

import '../models/hadith.dart';
import '../services/hadith_database.dart';
import '../theme.dart';
import '../widgets/animated_press_card.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/scroll_to_top_fab.dart';
import 'hadith_detail_screen.dart';

/// Screen showing list of hadiths for a specific book in a collection
class HadithListScreen extends StatefulWidget {
  final HadithDatabase database;
  final HadithCollection collection;
  final int bookNumber;
  final String bookTitle;

  const HadithListScreen({
    super.key,
    required this.database,
    required this.collection,
    required this.bookNumber,
    required this.bookTitle,
  });

  @override
  State<HadithListScreen> createState() => _HadithListScreenState();
}

class _HadithListScreenState extends State<HadithListScreen> {
  final List<Hadith> _hadiths = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  static const _pageSize = 30;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final hadiths = await widget.database.getHadithsPaginated(
      collection: widget.collection,
      bookNumber: widget.bookNumber,
      offset: 0,
      limit: _pageSize,
    );
    setState(() {
      _hadiths.addAll(hadiths);
      _hasMore = hadiths.length >= _pageSize;
      _isLoading = false;
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);
    final hadiths = await widget.database.getHadithsPaginated(
      collection: widget.collection,
      bookNumber: widget.bookNumber,
      offset: _hadiths.length,
      limit: _pageSize,
    );
    setState(() {
      _hadiths.addAll(hadiths);
      _hasMore = hadiths.length >= _pageSize;
      _isLoadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(40),
          child: Builder(builder: (context) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final accent = isDark ? AppTheme.darkGold : AppTheme.gold;
            return Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: accent, width: 1),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.1),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.3),
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${widget.collection.shortName} · ${_hadiths.length}${_hasMore ? '+' : ''} ஹதீஸ்கள்',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
      body: _isLoading
          ? const SingleChildScrollView(child: SkeletonList(itemCount: 6))
          : ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: _hadiths.length + (_isLoadingMore ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index >= _hadiths.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  );
                }

                final hadith = _hadiths[index];
                return AnimatedPressCard(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HadithDetailScreen(hadith: hadith),
                      ),
                    );
                  },
                  child: _HadithCard(
                    hadith: hadith,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HadithDetailScreen(hadith: hadith),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
      floatingActionButton: ScrollToTopFab(scrollController: _scrollController),
    );
  }
}

class _HadithCard extends StatelessWidget {
  final Hadith hadith;
  final VoidCallback onTap;

  const _HadithCard({required this.hadith, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkCard : AppTheme.surface;
    final border = isDark ? AppTheme.darkBorder : AppTheme.warmBorder;
    final gold = isDark ? AppTheme.darkGold : AppTheme.gold;
    final emerald = isDark ? AppTheme.darkEmerald : AppTheme.emerald;
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
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
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
                    '${hadith.hadithNumber}',
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
                      Text(
                        hadith.preview,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.6,
                          color: textColor,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.graphic_eq_rounded,
                              size: 14,
                              color: emerald.withValues(alpha: 0.6)),
                          const SizedBox(width: 4),
                          Text(
                            'AI ஒலி',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: subtle,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 20, color: gold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
