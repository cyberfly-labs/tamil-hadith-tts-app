import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../models/quran_verse.dart';
import '../services/bookmark_service.dart';
import '../services/tts_engine.dart';
import '../services/audio_player_service.dart';
import '../services/audio_cache_service.dart';
import '../widgets/waveform_animation.dart';

// Re-use the same shared singletons from hadith_detail_screen
import 'hadith_detail_screen.dart' show sharedTtsEngine, sharedAudioCache, sharedAudioPlayer;

/// Detail screen for Quran sura playback.
/// Receives the full list of verses for a sura and a start index.
/// When play is tapped, it synthesizes and plays from startIndex through
/// the end of the sura sequentially.
class QuranVerseDetailScreen extends StatefulWidget {
  final List<QuranVerse> verses;
  final int startIndex;

  const QuranVerseDetailScreen({
    super.key,
    required this.verses,
    required this.startIndex,
  });

  @override
  State<QuranVerseDetailScreen> createState() => _QuranVerseDetailScreenState();
}

class _QuranVerseDetailScreenState extends State<QuranVerseDetailScreen> {
  static final TtsEngine ttsEngine = sharedTtsEngine;
  static final AudioPlayerService _audioPlayer = sharedAudioPlayer;
  static final AudioCacheService audioCache = sharedAudioCache;
  static bool _servicesInitialized = false;
  static Future<void>? _servicesInitFuture;

  StreamSubscription<bool>? _playingSub;

  bool _isSynthesizing = false;
  bool _isPlaying = false;
  bool _isSuraPlaying = false; // true when sequential sura playback is active
  String _statusText = '';
  double _fontSize = 18.0;
  double _playbackSpeed = 1.0;
  int _currentVerseIndex = 0; // which verse is currently being played
  bool _cancelRequested = false;

  // Lookahead: pre-synthesize next verse while current one plays
  Future<void>? _prefetchFuture;
  String? _prefetchCacheKey;

  static const List<double> _speedOptions = [0.75, 1.0, 1.25, 1.5];

  final ScrollController _scrollController = ScrollController();
  late final List<GlobalKey> _verseKeys;

  QuranVerse get _currentVerse => widget.verses[_currentVerseIndex];
  int get _suraNumber => widget.verses.first.sura;
  String get _suraName => SuraNames.getName(_suraNumber);

  @override
  void initState() {
    super.initState();
    _verseKeys = List.generate(widget.verses.length, (_) => GlobalKey());
    _currentVerseIndex = widget.startIndex;
    _initServices();
    _playingSub = _audioPlayer.playingStream.listen((playing) {
      if (mounted) {
        setState(() => _isPlaying = playing);
      }
    });
  }

  Future<void> _initServices() async {
    if (_servicesInitialized) return;

    // Coalesce concurrent calls (initState + first-tap play)
    _servicesInitFuture ??= () async {
      await _audioPlayer.initialize();
      await audioCache.initialize();
      try {
        await ttsEngine.initialize();
      } catch (e) {
        debugPrint('TTS init warning: $e');
      }
      _servicesInitialized = true;
    }();

    await _servicesInitFuture;
  }

  @override
  void dispose() {
    _cancelRequested = true;
    _cancelPrefetch();
    _playingSub?.cancel();
    _scrollController.dispose();
    // Cancel any in-flight synthesis so the isolate doesn't keep working
    // for a screen that's already gone.
    ttsEngine.cancelSynthesis();
    super.dispose();
  }

  void _scrollToVerse(int index) {
    if (index < 0 || index >= _verseKeys.length) return;
    final key = _verseKeys[index];
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.3, // position verse ~30% from top
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalVerses = widget.verses.length;

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // ── Collapsing header ──
          SliverAppBar(
            expandedHeight: 140,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF1B4D3E),
            foregroundColor: const Color(0xFFFAF8F3),
            centerTitle: true,
            title: Text(_suraName),
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
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: 1,
                            color: const Color(0xFFD4A04A).withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _InfoChip(
                                icon: Icons.menu_book_rounded,
                                label: _suraName,
                              ),
                              const SizedBox(width: 12),
                              _InfoChip(
                                icon: Icons.format_list_numbered_rounded,
                                label: '${widget.verses.length} வசனங்கள்',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              _BookmarkButton(
                verse: _currentVerse,
                service: BookmarkService(),
              ),
              IconButton(
                icon: const Icon(Icons.text_decrease_rounded),
                onPressed: () =>
                    setState(() => _fontSize = (_fontSize - 2).clamp(14, 30)),
                tooltip: 'எழுத்து சிறிதாக்கு',
              ),
              IconButton(
                icon: const Icon(Icons.text_increase_rounded),
                onPressed: () =>
                    setState(() => _fontSize = (_fontSize + 2).clamp(14, 30)),
                tooltip: 'எழுத்து பெரிதாக்கு',
              ),
            ],
          ),

          // ── Verse cards ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final verse = widget.verses[index];
                  final isActive = _isSuraPlaying && index == _currentVerseIndex;

                  return Padding(
                    key: _verseKeys[index],
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isActive
                              ? const Color(0xFFD4A04A)
                              : const Color(0xFFE8DDD0),
                          width: isActive ? 2 : 1,
                        ),
                        color: isActive
                            ? const Color(0xFFD4A04A).withValues(alpha: 0.06)
                            : const Color(0xFFFFFDF9),
                        boxShadow: isActive ? [
                          BoxShadow(
                            color: const Color(0xFFD4A04A).withValues(alpha: 0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ] : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
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
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    const Color(0xFF1B4D3E),
                                    const Color(0xFF0D3020),
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
                            Expanded(
                              child: SelectableText(
                                verse.text,
                                style: TextStyle(
                                  fontSize: _fontSize,
                                  height: 1.85,
                                  color: const Color(0xFF1A1A1A),
                                  letterSpacing: 0.1,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (isActive)
                              Padding(
                                padding: const EdgeInsets.only(left: 4, top: 8),
                                child: WaveformAnimation(
                                  isPlaying: _isPlaying && isActive,
                                  color: const Color(0xFFD4A04A),
                                  height: 18,
                                  barCount: 4,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                childCount: totalVerses,
              ),
            ),
          ),
        ],
      ),

      // ── Bottom playback bar ──
      bottomNavigationBar: _buildPlaybackBar(context),
    );
  }

  Widget _buildPlaybackBar(BuildContext context) {
    final showSpeed = _isPlaying ||
        _audioPlayer.player.processingState != ProcessingState.idle;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFDF9);
    final borderColor = isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE8DDD0);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(top: BorderSide(color: borderColor, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status row with waveform
              if (_statusText.isNotEmpty || _isPlaying)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isPlaying) ...[
                        WaveformAnimation(
                          isPlaying: _isPlaying,
                          color: const Color(0xFFD4A04A),
                          height: 16,
                          barCount: 4,
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (_isSynthesizing) ...[
                        const PulsingDot(color: Color(0xFFD4A04A), size: 6),
                        const SizedBox(width: 6),
                      ],
                      if (_statusText.isNotEmpty)
                        Flexible(
                          child: Text(
                            _statusText,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? const Color(0xFF9E9E9E)
                                  : const Color(0xFF6B6B6B),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),

              // Main controls row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Previous verse
                  if (_isSuraPlaying)
                    IconButton.outlined(
                      onPressed: _currentVerseIndex > 0
                          ? () {
                              HapticFeedback.lightImpact();
                              _skipToVerse(_currentVerseIndex - 1);
                            }
                          : null,
                      icon: const Icon(Icons.skip_previous_rounded, size: 20),
                      style: IconButton.styleFrom(
                        side: BorderSide(color: borderColor),
                      ),
                    ),
                  if (_isSuraPlaying) const SizedBox(width: 8),

                  // Play / Pause
                  _isSynthesizing
                      ? FilledButton.icon(
                          onPressed: null,
                          icon: const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          label: Text(
                            'வசனம் ${_currentVerse.aya}/${widget.verses.length}',
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                          ),
                        )
                      : FilledButton.icon(
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            _onPlayPause();
                          },
                          icon: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            transitionBuilder: (child, anim) =>
                                ScaleTransition(scale: anim, child: child),
                            child: Icon(
                              _isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              key: ValueKey(_isPlaying),
                              size: 22,
                            ),
                          ),
                          label: Text(
                            _isPlaying
                                ? 'வசனம் ${_currentVerse.aya}/${widget.verses.length}'
                                : (_isSuraPlaying
                                    ? 'தொடர்'
                                    : 'சூரா ஒலிக்கவும்'),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                          ),
                        ),

                  // Stop
                  if (_isPlaying || _isSuraPlaying) ...[
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _onStop();
                      },
                      icon: const Icon(Icons.stop_rounded, size: 20),
                      style: IconButton.styleFrom(
                        side: BorderSide(color: borderColor),
                      ),
                    ),
                  ],

                  // Next verse
                  if (_isSuraPlaying) const SizedBox(width: 8),
                  if (_isSuraPlaying)
                    IconButton.outlined(
                      onPressed:
                          _currentVerseIndex < widget.verses.length - 1
                              ? () {
                                  HapticFeedback.lightImpact();
                                  _skipToVerse(_currentVerseIndex + 1);
                                }
                              : null,
                      icon: const Icon(Icons.skip_next_rounded, size: 20),
                      style: IconButton.styleFrom(
                        side: BorderSide(color: borderColor),
                      ),
                    ),
                ],
              ),

              // Speed chips — compact pill
              if (showSpeed)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : const Color(0xFF1B4D3E).withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.speed_rounded,
                            size: 14,
                            color: Color(0xFF9E9E9E)),
                        const SizedBox(width: 4),
                        for (final speed in _speedOptions)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 1),
                            child: ChoiceChip(
                              label: Text('${speed}x',
                                  style: const TextStyle(fontSize: 11)),
                              selected: _playbackSpeed == speed,
                              onSelected: (_) {
                                HapticFeedback.selectionClick();
                                _onSpeedChange(speed);
                              },
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              labelPadding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onPlayPause() async {
    try {
      await _onPlayPauseInternal();
    } catch (e, stack) {
      debugPrint('TTS CRASH caught: $e\n$stack');
      if (mounted) {
        setState(() {
          _statusText = 'ஒலிப்பதிவு பிழை ஏற்பட்டது';
          _isSynthesizing = false;
        });
      }
    }
  }

  Future<void> _onPlayPauseInternal() async {
    // Ensure audio session/player + cache + TTS are ready before first play.
    await _initServices();

    // If currently playing, pause
    if (_isPlaying) {
      await _audioPlayer.pause();
      return;
    }

    // If paused mid-sura, resume
    if (_isSuraPlaying &&
        _audioPlayer.player.processingState != ProcessingState.idle &&
        _audioPlayer.player.processingState != ProcessingState.completed) {
      await _audioPlayer.resume();
      return;
    }

    // Model guard
    if (!ttsEngine.isNativeAvailable) {
      if (mounted) {
        setState(() => _statusText = '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'தமிழ் ஒலி மாதிரி பதிவிறக்கம் செய்யப்படவில்லை.\n'
                'முகப்புப் பக்கத்திலிருந்து பதிவிறக்கவும்.'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Start whole-sura sequential playback from startIndex
    _cancelRequested = false;
    setState(() => _isSuraPlaying = true);
    await _playSuraSequential();
  }

  /// Pre-synthesize the next uncached verse so it's ready when needed.
  /// Called after the current verse's synthesis is done (TTS engine is free).
  void _startPrefetch(int fromIndex) {
    if (_cancelRequested || !mounted) return;

    for (int i = fromIndex; i < widget.verses.length; i++) {
      final verse = widget.verses[i];
      final key = verse.cacheKey;
      if (audioCache.getCachedPathByKey(key) != null) continue; // already cached
      if (_prefetchCacheKey == key) return; // already prefetching this one

      debugPrint('SuraPlay: Prefetching verse ${verse.sura}:${verse.aya}');
      _prefetchCacheKey = key;
      _prefetchFuture = _synthesizeToCache(verse);
      return;
    }
  }

  /// Synthesize a verse and save to cache (used by prefetch).
  Future<void> _synthesizeToCache(QuranVerse verse) async {
    try {
      final audio = await ttsEngine.synthesize(verse.text);
      if (audio != null && !_cancelRequested) {
        await audioCache.saveToCacheByKey(verse.cacheKey, audio);
        debugPrint('SuraPlay: Prefetch done ${verse.sura}:${verse.aya}');
      }
    } catch (e) {
      debugPrint('SuraPlay: Prefetch error ${verse.sura}:${verse.aya}: $e');
    }
  }

  void _cancelPrefetch() {
    _prefetchFuture = null;
    _prefetchCacheKey = null;
  }

  /// Plays verses sequentially from _currentVerseIndex to end of sura.
  /// Uses lookahead: while verse N plays, pre-synthesizes verse N+1 so
  /// there is no gap between verses.
  Future<void> _playSuraSequential() async {
    while (_currentVerseIndex < widget.verses.length) {
      if (_cancelRequested || !mounted) break;

      final verse = widget.verses[_currentVerseIndex];
      final cacheKey = verse.cacheKey;
      final nextIndex = _currentVerseIndex + 1;
      final hasNext = nextIndex < widget.verses.length;

      if (mounted) {
        setState(() {
          _statusText =
              'வசனம் ${verse.aya}/${widget.verses.length} ஒலிக்கிறது...';
        });
        _scrollToVerse(_currentVerseIndex);
      }

      // ── 1. Check disk cache (may have been filled by prefetch) ──
      String? cachedPath = audioCache.getCachedPathByKey(cacheKey);

      // ── 2. If not cached, check if prefetch is running for this verse ──
      if (cachedPath == null &&
          _prefetchCacheKey == cacheKey &&
          _prefetchFuture != null) {
        debugPrint('SuraPlay: Waiting for prefetch of $cacheKey');
        if (mounted) setState(() => _isSynthesizing = true);
        await _prefetchFuture;
        _prefetchFuture = null;
        _prefetchCacheKey = null;
        if (mounted) setState(() => _isSynthesizing = false);
        cachedPath = audioCache.getCachedPathByKey(cacheKey);
      }

      // ── 3. Play from cache if available ──
      if (cachedPath != null) {
        debugPrint('SuraPlay: Cache hit for ${verse.sura}:${verse.aya}');
        // Start playback without blocking so prefetch can run concurrently.
        await _audioPlayer.startPlayingFile(cachedPath);
        // Prefetch next verse while this one plays
        if (hasNext) _startPrefetch(nextIndex);
        await _audioPlayer.awaitPlaybackComplete();
        if (_cancelRequested || !mounted) break;
        setState(() => _currentVerseIndex++);
        continue;
      }

      // ── 4. No cache — cancel stale prefetch, synthesize via streaming ──
      _cancelPrefetch();
      if (mounted) setState(() => _isSynthesizing = true);

      try {
        final text = verse.text;
        debugPrint(
            'SuraPlay: Synthesizing ${verse.sura}:${verse.aya} (${text.length} chars)');

        await _audioPlayer.startStreaming();

        bool firstChunk = true;
        int chunkCount = 0;
        Future<String>? saveFuture;

        await for (final chunkAudio in ttsEngine.synthesizeStreaming(text)) {
          if (_cancelRequested || !mounted) {
            ttsEngine.cancelSynthesis();
            break;
          }

          chunkCount++;
          await _audioPlayer.addStreamingChunk(chunkAudio);

          if (firstChunk) {
            firstChunk = false;
            if (mounted) {
              setState(() {
                _isSynthesizing = false;
                _statusText =
                    'வசனம் ${verse.aya}/${widget.verses.length} ஒலிக்கிறது...';
              });
            }
          }
        }

        if (_cancelRequested || !mounted) break;

        if (chunkCount == 0) {
          debugPrint('SuraPlay: No audio for ${verse.sura}:${verse.aya}');
          if (mounted) setState(() => _isSynthesizing = false);
          setState(() => _currentVerseIndex++);
          continue;
        }

        _audioPlayer.finishStreaming();

        // Save to cache by stitching the already-written WAV chunks.
        try {
          final chunkFiles = await _audioPlayer.listChunkFiles();
          if (chunkFiles.isNotEmpty) {
            saveFuture = audioCache.saveWavChunksToCacheByKey(cacheKey, chunkFiles);
            saveFuture.catchError((e) {
              debugPrint('AudioCache: Failed to save $cacheKey (stitched): $e');
              return '';
            });
          }
        } catch (e) {
          debugPrint('AudioCache: chunk list failed for $cacheKey: $e');
        }

        // ── KEY: Prefetch next verse while this one still plays ──
        if (hasNext) _startPrefetch(nextIndex);

        // Wait for ALL chunks to finish playing (not just the first one).
        // awaitStreamingComplete() resolves only after the queue drains.
        await _audioPlayer.awaitStreamingComplete();
        if (_cancelRequested || !mounted) break;

        if (saveFuture != null) {
          try {
            await saveFuture;
          } catch (_) {}
        }
        await _audioPlayer.cleanupChunks(all: true);
      } catch (e) {
        debugPrint('SuraPlay: Error on ${verse.sura}:${verse.aya}: $e');
        if (mounted) setState(() => _isSynthesizing = false);
      }

      if (mounted) {
        setState(() {
          _currentVerseIndex++;
          _isSynthesizing = false;
        });
      }
    }

    // Sura playback finished
    _cancelPrefetch();
    if (mounted) {
      setState(() {
        _isSuraPlaying = false;
        _isSynthesizing = false;
        _statusText = _cancelRequested ? '' : 'சூரா முடிந்தது';
        _currentVerseIndex = widget.startIndex; // reset for replay
      });
    }
  }

  void _skipToVerse(int index) {
    // Cancel current synthesis + prefetch, stop playback, jump to new verse
    _cancelRequested = true;
    _cancelPrefetch();
    ttsEngine.cancelSynthesis();
    _audioPlayer.stop().then((_) {
      _audioPlayer.cleanupChunks(all: true);
      if (mounted) {
        setState(() {
          _currentVerseIndex = index;
          _isSynthesizing = false;
          _isSuraPlaying = false;
          _cancelRequested = false;
        });
        // Restart playback from the new verse
        _onPlayPause();
      }
    });
  }

  Future<void> _onStop() async {
    _cancelRequested = true;
    _cancelPrefetch();
    try {
      ttsEngine.cancelSynthesis();
      await _audioPlayer.stop();
      await _audioPlayer.cleanupChunks(all: true);
    } catch (e) {
      debugPrint('Stop error: $e');
    }
    if (mounted) {
      setState(() {
        _statusText = '';
        _isSynthesizing = false;
        _isSuraPlaying = false;
      });
    }
  }

  void _onSpeedChange(double speed) {
    setState(() => _playbackSpeed = speed);
    _audioPlayer.setSpeed(speed);
  }
}

/// Gold-accented info chip for the collapsing header
class _BookmarkButton extends StatelessWidget {
  final QuranVerse verse;
  final BookmarkService service;

  const _BookmarkButton({required this.verse, required this.service});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final isBookmarked = service.isBookmarked(verse.cacheKey);
        return IconButton(
          icon: Icon(
            isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
            color: isBookmarked ? const Color(0xFFD4A04A) : null,
          ),
          onPressed: () async {
            HapticFeedback.mediumImpact();
            await service.toggleBookmark(
              key: verse.cacheKey,
              collection: 'quran',
              hadithNumber: verse.aya,
              book: verse.sura.toString(),
              chapter: SuraNames.getName(verse.sura),
              textTamil: verse.text,
            );
          },
          tooltip: isBookmarked ? 'புக்மார்க் நீக்கு' : 'புக்மார்க் செய்',
        );
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFD4A04A).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFD4A04A).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFD4A04A)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFD4A04A),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
