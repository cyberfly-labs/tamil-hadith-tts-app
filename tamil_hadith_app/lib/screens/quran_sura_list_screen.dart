import 'package:flutter/material.dart';

import '../models/quran_verse.dart';
import '../services/quran_database.dart';
import 'quran_verse_list_screen.dart';
import 'quran_verse_detail_screen.dart';

/// Home screen for Quran — list of 114 suras
class QuranSuraListScreen extends StatefulWidget {
  final QuranDatabase database;

  const QuranSuraListScreen({super.key, required this.database});

  @override
  State<QuranSuraListScreen> createState() => _QuranSuraListScreenState();
}

class _QuranSuraListScreenState extends State<QuranSuraListScreen> {
  bool _isLoading = true;
  int _totalVerses = 0;

  @override
  void initState() {
    super.initState();
    _load();
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
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // ── Collapsing App Bar ──
                SliverAppBar(
                  expandedHeight: 220,
                  floating: false,
                  pinned: true,
                  stretch: true,
                  backgroundColor: const Color(0xFF1B4D3E),
                  foregroundColor: const Color(0xFFFAF8F3),
                  centerTitle: true,
                  title: const Text('திருக்குர்ஆன்'),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.search_rounded),
                      onPressed: () => _showSearch(context),
                      tooltip: 'தேடு',
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF1B4D3E),
                            const Color(0xFF0D3020),
                          ],
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
                                      color: const Color(0xFFD4A04A),
                                      width: 1.5,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD4A04A).withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.menu_book_rounded,
                                    color: Color(0xFFD4A04A),
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
                            const Text(
                              'தமிழ் மொழிபெயர்ப்பு',
                              style: TextStyle(
                                color: Color(0xFFD4A04A),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 8),

                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFFD4A04A).withValues(alpha: 0.4),
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '114 சூராக்கள் • $_totalVerses வசனங்கள்',
                                style: const TextStyle(
                                  color: Color(0xFFD4A04A),
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
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFDF9),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE8DDD0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search_rounded,
                                color: Color(0xFF6B6B6B),
                                size: 22),
                            const SizedBox(width: 12),
                            Text(
                              'வசனம் தேடுங்கள்...',
                              style: const TextStyle(
                                color: Color(0xFF9E9E9E),
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Section header ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      'சூராக்கள்',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1B4D3E),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),

                // ── Sura list ──
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final suraNum = index + 1;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
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
                        );
                      },
                      childCount: 114,
                    ),
                  ),
                ),
              ],
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFE8DDD0),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Sura number badge with ornament
                Container(
                  width: 48,
                  height: 48,
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
                    '$suraNumber',
                    style: const TextStyle(
                      color: Color(0xFFD4A04A),
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
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A1A),
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$verseCount வசனங்கள்',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF6B6B6B),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFFD4A04A), size: 22),
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

  @override
  String get searchFieldLabel => 'வசனம் தேடுங்கள்...';

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

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.length < 2) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded,
                size: 48,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Text(
              'குறைந்தது 2 எழுத்துகள் தட்டச்சு செய்யவும்',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    return FutureBuilder<List<QuranVerse>>(
      future: database.searchVerses(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final results = snapshot.data ?? [];
        if (results.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off_rounded,
                    size: 48,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.15)),
                const SizedBox(height: 12),
                Text(
                  'முடிவுகள் இல்லை',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final verse = results[index];
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  close(context, null);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          QuranVerseDetailScreen(
                            verses: [verse],
                            startIndex: 0,
                          ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFDF9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE8DDD0)),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B4D3E),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${verse.sura}:${verse.aya}',
                              style: const TextStyle(
                                color: Color(0xFFD4A04A),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              SuraNames.getName(verse.sura),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B6B6B),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        verse.preview,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Color(0xFF1A1A1A),
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
