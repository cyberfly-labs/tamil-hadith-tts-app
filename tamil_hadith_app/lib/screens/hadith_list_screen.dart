import 'package:flutter/material.dart';

import '../models/hadith.dart';
import '../services/hadith_database.dart';
import 'hadith_detail_screen.dart';

/// Screen showing list of hadiths for a specific book
class HadithListScreen extends StatefulWidget {
  final HadithDatabase database;
  final String book;

  const HadithListScreen({
    super.key,
    required this.database,
    required this.book,
  });

  @override
  State<HadithListScreen> createState() => _HadithListScreenState();
}

class _HadithListScreenState extends State<HadithListScreen> {
  final List<Hadith> _hadiths = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;
  bool _isLoadingMore = false;
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
      offset: 0,
      limit: _pageSize,
      book: widget.book,
    );
    setState(() {
      _hadiths.addAll(hadiths);
      _isLoading = false;
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);
    final hadiths = await widget.database.getHadithsPaginated(
      offset: _hadiths.length,
      limit: _pageSize,
      book: widget.book,
    );
    setState(() {
      _hadiths.addAll(hadiths);
      _isLoadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _hadiths.length + (_isLoadingMore ? 1 : 0),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'ஹதீஸ் #${hadith.hadithNumber}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.volume_up_outlined,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                hadith.preview,
                style: const TextStyle(fontSize: 15, height: 1.6),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
