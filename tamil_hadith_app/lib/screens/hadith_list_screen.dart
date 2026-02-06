import 'package:flutter/material.dart';

import '../models/hadith.dart';
import '../services/hadith_database.dart';
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${widget.collection.shortName} · ${_hadiths.length}${_hasMore ? '+' : ''} ஹதீஸ்கள்',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
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
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final hadith = _hadiths[index];
                return _HadithCard(
                  hadith: hadith,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HadithDetailScreen(hadith: hadith),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _HadithCard extends StatelessWidget {
  final Hadith hadith;
  final VoidCallback onTap;

  const _HadithCard({required this.hadith, required this.onTap});

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
              // Hadith number badge
              Container(
                width: 46,
                height: 46,
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
                    Text(
                      hadith.preview,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.6,
                        color: cs.onSurface,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.graphic_eq_rounded,
                            size: 14,
                            color: cs.primary.withValues(alpha: 0.5)),
                        const SizedBox(width: 4),
                        Text(
                          'AI ஒலி',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: cs.primary.withValues(alpha: 0.6),
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
                    size: 20, color: cs.onSurface.withValues(alpha: 0.25)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
