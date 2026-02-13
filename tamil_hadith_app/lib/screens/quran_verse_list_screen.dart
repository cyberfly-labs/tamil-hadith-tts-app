import 'package:flutter/material.dart';

import '../models/quran_verse.dart';
import '../services/quran_database.dart';
import '../widgets/animated_press_card.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/scroll_to_top_fab.dart';
import 'quran_verse_detail_screen.dart';

/// Screen showing list of verses for a specific sura
class QuranVerseListScreen extends StatefulWidget {
  final QuranDatabase database;
  final int suraNumber;

  const QuranVerseListScreen({
    super.key,
    required this.database,
    required this.suraNumber,
  });

  @override
  State<QuranVerseListScreen> createState() => _QuranVerseListScreenState();
}

class _QuranVerseListScreenState extends State<QuranVerseListScreen> {
  List<QuranVerse> _allVerses = []; // full sura loaded at once for playback
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();

  String get _suraName => SuraNames.getName(widget.suraNumber);

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final verses = await widget.database.getVersesBySura(widget.suraNumber);
    setState(() {
      _allVerses = verses;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_suraName),
        backgroundColor: const Color(0xFF1B4D3E),
        foregroundColor: const Color(0xFFFAF8F3),
        elevation: 0,
        actions: [
          // Play whole sura button
          if (!_isLoading && _allVerses.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.play_circle_rounded),
              tooltip: 'சூரா முழுவதும் ஒலிக்கவும்',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => QuranVerseDetailScreen(
                      verses: _allVerses,
                      startIndex: 0,
                    ),
                  ),
                );
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Color(0xFFD4A04A),
                  width: 1,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A04A).withValues(alpha: 0.1),
                      border: Border.all(
                        color: const Color(0xFFD4A04A).withValues(alpha: 0.3),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'சூரா ${widget.suraNumber} • ${_allVerses.length} வசனங்கள்',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD4A04A),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const SingleChildScrollView(child: SkeletonList(itemCount: 6))
          : ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: _allVerses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final verse = _allVerses[index];
                return AnimatedPressCard(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => QuranVerseDetailScreen(
                          verses: _allVerses,
                          startIndex: index,
                        ),
                      ),
                    );
                  },
                  child: _VerseCard(
                    verse: verse,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QuranVerseDetailScreen(
                            verses: _allVerses,
                            startIndex: index,
                          ),
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

class _VerseCard extends StatelessWidget {
  final QuranVerse verse;
  final VoidCallback onTap;

  const _VerseCard({required this.verse, required this.onTap});

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
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Verse number badge
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
                    '${verse.aya}',
                    style: const TextStyle(
                      color: Color(0xFFD4A04A),
                      fontWeight: FontWeight.w800,
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
                        verse.preview,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: Color(0xFF1A1A1A),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.graphic_eq_rounded,
                              size: 13,
                              color: const Color(0xFF1B4D3E).withValues(alpha: 0.5)),
                          const SizedBox(width: 4),
                          Text(
                            'AI ஒலி',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1B4D3E).withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: const Icon(Icons.chevron_right_rounded,
                      size: 20, 
                      color: Color(0xFFD4A04A)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
