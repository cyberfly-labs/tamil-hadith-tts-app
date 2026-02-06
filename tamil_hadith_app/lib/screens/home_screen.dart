import 'package:flutter/material.dart';

import '../models/hadith.dart';
import '../services/hadith_database.dart';
import '../services/quran_database.dart';
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
      QuranSuraListScreen(database: widget.quranDatabase),
      _HadithHomeBody(database: widget.hadithDatabase),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentTab,
        children: bodies,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (i) => setState(() => _currentTab = i),
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
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final books = _bookIndices[_selectedCollection] ?? [];
    final totalCount = _totalCounts[_selectedCollection] ?? 0;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Collapsing App Bar with hero header ──
          SliverAppBar(
            expandedHeight: 200,
            floating: false,
            pinned: true,
            stretch: true,
            backgroundColor: cs.surface,
            foregroundColor: cs.onSurface,
            title: Text(_selectedCollection.shortName),
            actions: [
              IconButton(
                icon: const Icon(Icons.bookmark_rounded),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BookmarksScreen(
                      database: widget.database,
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
                    colors: [
                      cs.primary,
                      cs.primary.withValues(alpha: 0.82),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Decorative icon
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.auto_stories_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _selectedCollection.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${books.length} புத்தகங்கள் · $totalCount ஹதீஸ்கள்',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                color: cs.surface,
                child: TabBar(
                  controller: _tabController,
                  tabs: [
                    Tab(text: HadithCollection.bukhari.shortName),
                    Tab(text: HadithCollection.muslim.shortName),
                  ],
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
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
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded,
                          color: cs.onSurface.withValues(alpha: 0.4),
                          size: 22),
                      const SizedBox(width: 12),
                      Text(
                        'ஹதீஸ் தேடுங்கள்...',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.4),
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
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.5),
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
                  );
                },
                childCount: books.length,
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
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Index badge
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$index',
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
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
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    if (bookIndex.volume != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'தொகுதி ${bookIndex.volume}',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: cs.onSurface.withValues(alpha: 0.3)),
            ],
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

  @override
  String get searchFieldLabel => 'ஹதீஸ் தேடுங்கள்...';

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
    // Search across both collections
    return FutureBuilder<List<Hadith>>(
      future: database.searchHadiths(query),
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
            final hadith = results[index];
            return Card(
              child: InkWell(
                onTap: () {
                  close(context, null);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HadithDetailScreen(hadith: hadith),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Padding(
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
                              color: hadith.collection ==
                                      HadithCollection.bukhari
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : Theme.of(context)
                                      .colorScheme
                                      .tertiaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              hadith.collection.shortName,
                              style: TextStyle(
                                color: hadith.collection ==
                                        HadithCollection.bukhari
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer
                                    : Theme.of(context)
                                        .colorScheme
                                        .onTertiaryContainer,
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '#${hadith.hadithNumber}',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              hadith.bookTitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.5),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hadith.preview,
                        style: const TextStyle(fontSize: 14, height: 1.5),
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

