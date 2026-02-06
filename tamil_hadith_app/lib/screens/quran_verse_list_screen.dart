import 'package:flutter/material.dart';

import '../models/quran_verse.dart';
import '../services/quran_database.dart';
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

  String get _suraName => SuraNames.getName(widget.suraNumber);

  @override
  void initState() {
    super.initState();
    _loadAll();
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_suraName),
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
          preferredSize: const Size.fromHeight(32),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.tertiary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'சூரா ${widget.suraNumber} · ${_allVerses.length} வசனங்கள்',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.tertiary,
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: _allVerses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final verse = _allVerses[index];
                return _VerseCard(
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
                );
              },
            ),
    );
  }
}

class _VerseCard extends StatelessWidget {
  final QuranVerse verse;
  final VoidCallback onTap;

  const _VerseCard({required this.verse, required this.onTap});

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
              // Verse number badge
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${verse.aya}',
                  style: TextStyle(
                    color: cs.onTertiaryContainer,
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
                      verse.preview,
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
                            color: cs.tertiary.withValues(alpha: 0.5)),
                        const SizedBox(width: 4),
                        Text(
                          'AI ஒலி',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: cs.tertiary.withValues(alpha: 0.6),
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
