import 'package:flutter/material.dart';

import '../models/hadith.dart';
import '../services/bookmark_service.dart';
import 'hadith_detail_screen.dart';

/// Screen showing all bookmarked hadiths
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

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
    final hadiths = rows.map((row) {
      return Hadith(
        id: 0, // Not needed for display
        hadithNumber: row['hadith_number'] as int,
        book: row['book'] as String? ?? '',
        chapter: row['chapter'] as String? ?? '',
        textTamil: row['text_tamil'] as String? ?? '',
      );
    }).toList();
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
                    Text(
                      hadith.book,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
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
