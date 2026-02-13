import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/hadith.dart';
import '../services/hadith_database.dart';
import '../services/quran_database.dart';
import '../widgets/animated_press_card.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/scroll_to_top_fab.dart';
import 'bookmarks_screen.dart';
import 'hadith_detail_screen.dart';
import 'hadith_list_screen.dart';
import 'quran_sura_list_screen.dart';
import 'settings_screen.dart';

/// Home screen with bottom navigation for Hadith and Quran
class HomeScreen extends StatefulWidget {
  final HadithDatabase hadithDatabase;
  final QuranDatabase quranDatabase;

  const HomeScreen({
    super.key,
    required this.hadithDatabase,
    required this.quranDatabase,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;

  @override
  Widget build(BuildContext context) {
    final bodies = [
      QuranSuraListScreen(
        database: widget.quranDatabase,
        hadithDatabase: widget.hadithDatabase,
      ),
      _HadithHomeBody(database: widget.hadithDatabase),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentTab,
        children: bodies,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1E1E1E)
              : const Color(0xFFFFFDF9),
          border: Border(
            top: BorderSide(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF2E2E2E)
                  : const Color(0xFFE8DDD0),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _currentTab,
          onDestinationSelected: (i) {
            HapticFeedback.selectionClick();
            setState(() => _currentTab = i);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book_rounded),
              label: 'குர்ஆன்',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_stories_outlined),
              selectedIcon: Icon(Icons.auto_stories_rounded),
              label: 'ஹதீஸ்',
            ),
          ],
        ),
      ),
    );
  }
}

/// The hadith home body with collection tabs and book index
class _HadithHomeBody extends StatefulWidget {
  final HadithDatabase database;

  const _HadithHomeBody({required this.database});

  @override
  State<_HadithHomeBody> createState() => _HadithHomeBodyState();
}

class _HadithHomeBodyState extends State<_HadithHomeBody>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  HadithCollection _selectedCollection = HadithCollection.bukhari;

  // Book index + counts per collection
  final Map<HadithCollection, List<HadithBookIndex>> _bookIndices = {};
  final Map<HadithCollection, int> _totalCounts = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedCollection = _tabController.index == 0
              ? HadithCollection.bukhari
              : HadithCollection.muslim;
        });
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final bukhariIndex =
        await widget.database.getBookIndex(HadithCollection.bukhari);
    final muslimIndex =
        await widget.database.getBookIndex(HadithCollection.muslim);
    final bukhariCount =
        await widget.database.getCount(HadithCollection.bukhari);
    final muslimCount =
        await widget.database.getCount(HadithCollection.muslim);

    setState(() {
      _bookIndices[HadithCollection.bukhari] = bukhariIndex;
      _bookIndices[HadithCollection.muslim] = muslimIndex;
      _totalCounts[HadithCollection.bukhari] = bukhariCount;
      _totalCounts[HadithCollection.muslim] = muslimCount;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 240,
              floating: false,
              pinned: true,
              backgroundColor: const Color(0xFF1B4D3E),
              foregroundColor: const Color(0xFFFAF8F3),
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1B4D3E), Color(0xFF0D3020)],
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(child: SkeletonList(itemCount: 6)),
          ],
        ),
      );
    }

    final books = _bookIndices[_selectedCollection] ?? [];
    final totalCount = _totalCounts[_selectedCollection] ?? 0;

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // ── Collapsing App Bar with hero header ──
          SliverAppBar(
            expandedHeight: 240,
            floating: false,
            pinned: true,
            stretch: true,
            backgroundColor: const Color(0xFF1B4D3E),
            foregroundColor: const Color(0xFFFAF8F3),
            actions: [
              IconButton(
                icon: const Icon(Icons.bookmark_rounded),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BookmarksScreen(
                      database: widget.database,
                      quranDatabase: (context.findAncestorWidgetOfExactType<HomeScreen>()?.quranDatabase) ??
                          (context.findAncestorStateOfType<_HomeScreenState>()?.widget.quranDatabase)!,
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
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1B4D3E),
                      Color(0xFF0D3020),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Decorative icon with border
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
                              Icons.auto_stories_rounded,
                              color: Color(0xFFD4A04A),
                              size: 28,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      Text(
                        _selectedCollection.displayName,
                        style: const TextStyle(
                          color: Color(0xFFFAF8F3),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'ஹதீஸ் தொகுப்பு',
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
                          '${books.length} புத்தகங்கள் • $totalCount ஹதீஸ்கள்',
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
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                color: const Color(0xFFFFFDF9),
                child: TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(text: HadithCollection.bukhari.shortName),
                    Tab(text: HadithCollection.muslim.shortName),
                  ],
                  indicatorSize: TabBarIndicatorSize.label,
                  indicatorColor: const Color(0xFFD4A04A),
                  indicatorWeight: 2.5,
                  labelColor: const Color(0xFF1B4D3E),
                  unselectedLabelColor: const Color(0xFF6B6B6B),
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                  dividerHeight: 0,
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
                      Icon(Icons.search_rounded,
                          color: const Color(0xFF6B6B6B),
                          size: 22),
                      const SizedBox(width: 12),
                      Text(
                        'ஹதீஸ் தேடுங்கள்...',
                        style: TextStyle(
                          color: const Color(0xFF9E9E9E),
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
                'புத்தகங்கள்',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1B4D3E),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),

          // ── Book index list ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final bookIdx = books[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AnimatedPressCard(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => HadithListScreen(
                              database: widget.database,
                              collection: _selectedCollection,
                              bookNumber: bookIdx.bookNumber,
                              bookTitle: bookIdx.bookTitle,
                            ),
                          ),
                        );
                      },
                      child: _BookIndexCard(
                        bookIndex: bookIdx,
                        index: index + 1,
                        collection: _selectedCollection,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HadithListScreen(
                                database: widget.database,
                                collection: _selectedCollection,
                                bookNumber: bookIdx.bookNumber,
                                bookTitle: bookIdx.bookTitle,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
                childCount: books.length,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: ScrollToTopFab(
        scrollController: _scrollController,
        heroTag: 'hadith_scroll_top',
      ),
    );
  }

  void _showSearch(BuildContext context) {
    showSearch(
      context: context,
      delegate: _HadithSearchDelegate(widget.database, _selectedCollection),
    );
  }
}

class _BookIndexCard extends StatelessWidget {
  final HadithBookIndex bookIndex;
  final int index;
  final HadithCollection collection;
  final VoidCallback onTap;

  const _BookIndexCard({
    required this.bookIndex,
    required this.index,
    required this.collection,
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Index badge — emerald gradient
                Container(
                  width: 42,
                  height: 42,
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
                    '$index',
                    style: const TextStyle(
                      color: Color(0xFFD4A04A),
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bookIndex.bookTitle,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      if (bookIndex.volume != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'தொகுதி ${bookIndex.volume}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B6B6B),
                          ),
                        ),
                      ],
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

class _HadithSearchDelegate extends SearchDelegate<Hadith?> {
  final HadithDatabase database;
  final HadithCollection activeCollection;

  _HadithSearchDelegate(this.database, this.activeCollection);

  // Cache search results so scroll position is preserved on back-navigation
  String _lastQuery = '';
  Future<List<Hadith>>? _cachedFuture;
  List<Hadith>? _cachedResults;

  @override
  String get searchFieldLabel => 'உரை அல்லது எண் தேடுங்கள்...';

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
  Widget buildResults(BuildContext context) {
    return _buildSearchResults();
  }

  /// Check if query is a hadith number (pure digits)
  static final RegExp _numberPattern = RegExp(r'^\d+$');

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
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
              'உரை அல்லது ஹதீஸ் எண் தேடுங்கள்',
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
    // Allow single-char queries for number search
    if (!_numberPattern.hasMatch(query.trim()) && query.length < 2) {
      return Center(
        child: Text(
          'குறைந்தது 2 எழுத்துகள் தட்டச்சு செய்யவும்',
          style: TextStyle(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.4),
          ),
        ),
      );
    }
    return _buildSearchResults();
  }

  /// Search by number or by text depending on query format
  Future<List<Hadith>> _searchByQuery() async {
    final trimmed = query.trim();
    if (_numberPattern.hasMatch(trimmed)) {
      final number = int.tryParse(trimmed);
      if (number != null && number > 0) {
        // Search by exact hadith number across both collections
        final results = <Hadith>[];
        final bukhari = await database.getHadith(HadithCollection.bukhari, number);
        if (bukhari != null) results.add(bukhari);
        final muslim = await database.getHadith(HadithCollection.muslim, number);
        if (muslim != null) results.add(muslim);
        return results;
      }
    }
    return database.searchHadiths(query);
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
    return FutureBuilder<List<Hadith>>(
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

  Widget _buildResultsList(List<Hadith> results) {
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 48,
                color: const Color(0xFF1A1A1A).withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Text(
              'முடிவுகள் இல்லை',
              style: TextStyle(
                color: const Color(0xFF1A1A1A).withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      key: const PageStorageKey('hadith_search_results'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final hadith = results[index];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HadithDetailScreen(hadith: hadith),
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
                          // Collection badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B4D3E),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              hadith.collection.shortName,
                              style: const TextStyle(
                                color: Color(0xFFD4A04A),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD4A04A).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFD4A04A).withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              '#${hadith.hadithNumber}',
                              style: const TextStyle(
                                color: Color(0xFFB8860B),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              hadith.bookTitle,
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
                        hadith.preview,
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
  }
}

