import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../models/hadith.dart';
import '../services/tts_engine.dart';
import '../services/audio_player_service.dart';
import '../services/audio_cache_service.dart';
import '../services/bookmark_service.dart';
import '../widgets/waveform_animation.dart';

/// Detail screen for a single hadith with TTS audio playback
/// Shared singletons for TTS engine, audio cache, and audio player.
/// Used by both HadithDetailScreen, QuranVerseDetailScreen, and SettingsScreen.
final sharedTtsEngine = TtsEngine();
final sharedAudioCache = AudioCacheService();
final sharedAudioPlayer = AudioPlayerService();

class HadithDetailScreen extends StatefulWidget {
  final Hadith hadith;

  const HadithDetailScreen({super.key, required this.hadith});

  @override
  State<HadithDetailScreen> createState() => _HadithDetailScreenState();
}

class _HadithDetailScreenState extends State<HadithDetailScreen> {
  // TTS engine and audio player are obtained from the app-level singletons
  static final TtsEngine ttsEngine = sharedTtsEngine;
  static final AudioPlayerService _audioPlayer = sharedAudioPlayer;
  static final AudioCacheService audioCache = sharedAudioCache;
  static final BookmarkService _bookmarkService = BookmarkService();
  static bool _servicesInitialized = false;
  static Future<void>? _servicesInitFuture;
  static String? _currentlyLoadedHadith; // Track which hadith audio is loaded

  StreamSubscription<bool>? _playingSub;

  bool _isSynthesizing = false;
  bool _isPlaying = false;
  String _statusText = '';
  double _fontSize = 18.0;
  double _playbackSpeed = 1.0;

  static const List<double> _speedOptions = [0.75, 1.0, 1.25, 1.5];

  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Collapsing header with hadith info ──
          SliverAppBar(
            expandedHeight: 130,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF1B4D3E),
            foregroundColor: const Color(0xFFFAF7F2),
            title: Text('ஹதீஸ் #${widget.hadith.hadithNumber}'),
            actions: [
              IconButton(
                icon: Icon(
                  _bookmarkService.isBookmarked(widget.hadith.cacheKey)
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_outline_rounded,
                ),
                onPressed: _toggleBookmark,
                tooltip: 'புக்மார்க்',
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
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          _InfoChip(
                            icon: Icons.library_books_rounded,
                            label: widget.hadith.collection.shortName,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: _InfoChip(
                              icon: Icons.auto_stories_rounded,
                              label: widget.hadith.book,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _InfoChip(
                            icon: Icons.tag_rounded,
                            label: '#${widget.hadith.hadithNumber}',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Chapter heading ──
          if (widget.hadith.chapter.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4A04A).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFD4A04A).withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    widget.hadith.chapter,
                    style: TextStyle(
                      fontSize: _fontSize,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1B4D3E),
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),

          // ── Narrator (Bukhari only) ──
          if (widget.hadith.narratedBy.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: [
                    Icon(Icons.person_rounded,
                        size: 16,
                        color: const Color(0xFF6B6B6B)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.hadith.narratedBy,
                        style: TextStyle(
                          fontSize: _fontSize - 2,
                          fontStyle: FontStyle.italic,
                          color: const Color(0xFF6B6B6B),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Ornamental divider ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFD4A04A).withValues(alpha: 0.0),
                            const Color(0xFFD4A04A).withValues(alpha: 0.4),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: const Color(0xFFD4A04A).withValues(alpha: 0.5),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFD4A04A).withValues(alpha: 0.4),
                            const Color(0xFFD4A04A).withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Hadith text body ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFDF9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFE8DDD0),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SelectableText(
                  widget.hadith.textTamil,
                  style: TextStyle(
                    fontSize: _fontSize,
                    height: 1.85,
                    color: const Color(0xFF1A1A1A),
                    letterSpacing: 0.1,
                  ),
                ),
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
                        Text(
                          _statusText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? const Color(0xFF9E9E9E)
                                : const Color(0xFF6B6B6B),
                          ),
                        ),
                    ],
                  ),
                ),

              // Main controls row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Play/Pause — larger and more prominent
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
                          label: const Text('ஒலிப்பதிவு...'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 14),
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
                              size: 24,
                            ),
                          ),
                          label: Text(
                            _isPlaying ? 'நிறுத்து' : 'ஒலிக்கவும்',
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 14),
                          ),
                        ),
                  if (_isPlaying || _isSynthesizing) ...[
                    const SizedBox(width: 12),
                    IconButton.outlined(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _onStop();
                      },
                      icon: const Icon(Icons.stop_rounded, size: 22),
                      style: IconButton.styleFrom(
                        side: BorderSide(color: borderColor),
                        padding: const EdgeInsets.all(10),
                      ),
                    ),
                  ],
                ],
              ),

              // Speed chips — more compact and elegant
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
                        Icon(Icons.speed_rounded,
                            size: 14,
                            color: isDark
                                ? const Color(0xFF9E9E9E)
                                : const Color(0xFF9E9E9E)),
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
    // ── Global crash protection: never let TTS crash the app ──
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

    if (_isPlaying) {
      await _audioPlayer.pause();
      return;
    }

    // If paused AND same hadith, resume from where we left off
    if (_currentlyLoadedHadith == widget.hadith.cacheKey &&
        _audioPlayer.player.processingState != ProcessingState.idle &&
        _audioPlayer.player.processingState != ProcessingState.completed) {
      await _audioPlayer.resume();
      return;
    }

    // Different hadith or fresh start — stop any old playback
    await _audioPlayer.stop();
    _currentlyLoadedHadith = widget.hadith.cacheKey;

    // ── Model-not-downloaded guard ──
    if (!ttsEngine.isNativeAvailable) {
      if (mounted) {
        setState(() => _statusText = '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('தமிழ் ஒலி மாதிரி பதிவிறக்கம் செய்யப்படவில்லை.\n'
                'முகப்புப் பக்கத்திலிருந்து பதிவிறக்கவும்.'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final hadithKey = widget.hadith.cacheKey;

    // ── Check audio cache first ──
    final cachedPath = audioCache.getCachedPathByKey(hadithKey);
    if (cachedPath != null) {
      debugPrint('AudioCache: Hit for $hadithKey');
      setState(() => _statusText = 'தற்காலிக சேமிப்பிலிருந்து ஒலிக்கிறது...');
      // Use startPlayingFile (non-blocking) + awaitPlaybackComplete
      // so the user can pause/stop during cached playback.
      await _audioPlayer.startPlayingFile(cachedPath);
      if (mounted) setState(() => _statusText = 'ஒலிக்கிறது...');
      await _audioPlayer.awaitPlaybackComplete();
      if (mounted) {
        setState(() {
          _statusText = '';
          _isPlaying = false;
        });
      }
      return;
    }

    // ── No cache — synthesize and save ──
    setState(() {
      _isSynthesizing = true;
      _statusText = 'உரையை ஒலியாக மாற்றுகிறது...';
    });

    try {
      final text = widget.hadith.textTamil;
      debugPrint('TTS: Starting synthesis for $hadithKey (${text.length} chars)');

      // Start the streaming playlist
      await _audioPlayer.startStreaming();

      bool firstChunk = true;
      int chunkCount = 0;

      await for (final chunkAudio in ttsEngine.synthesizeStreaming(text)) {
        if (!mounted) {
          debugPrint('TTS: Widget unmounted during synthesis, cancelling');
          ttsEngine.cancelSynthesis();
          break;
        }

        chunkCount++;
        debugPrint('TTS: Chunk #$chunkCount received (${chunkAudio.length} samples, ${(chunkAudio.length / 16000).toStringAsFixed(2)}s)');
        await _audioPlayer.addStreamingChunk(chunkAudio);

        if (firstChunk) {
          firstChunk = false;
          if (mounted) {
            setState(() {
              _isSynthesizing = false;
              _statusText = 'ஒலிக்கிறது...';
            });
          }
        } else if (mounted) {
          setState(() {
            _statusText = 'ஒலிக்கிறது... (பகுதி $chunkCount)';
          });
        }
      }

      debugPrint('TTS: Synthesis loop ended. chunkCount=$chunkCount mounted=$mounted');

      if (mounted && chunkCount == 0) {
        setState(() {
          _statusText = 'ஒலிப்பதிவு தோல்வி';
          _isSynthesizing = false;
        });
      } else if (mounted) {
        setState(() => _statusText = 'ஒலிக்கிறது...');
      }

      // Signal: no more chunks coming — player will drain the queue
      _audioPlayer.finishStreaming();

      // ── Save to cache by stitching the already-written WAV chunks ──
      // This avoids keeping all Float32 PCM chunks in RAM.
      Future<String>? saveFuture;
      try {
        final chunkFiles = await _audioPlayer.listChunkFiles();
        if (chunkFiles.isNotEmpty) {
          saveFuture = audioCache.saveWavChunksToCacheByKey(hadithKey, chunkFiles);
          saveFuture.then((_) {
            debugPrint('AudioCache: Saved $hadithKey to cache (stitched)');
          }).catchError((e) {
            debugPrint('AudioCache: Failed to save $hadithKey (stitched): $e');
          });
        }
      } catch (e) {
        debugPrint('AudioCache: chunk list failed for $hadithKey: $e');
      }

      // ── Reset UI when all chunks finish playing ──
      _audioPlayer.awaitStreamingComplete().then((_) {
        if (mounted) {
          setState(() {
            _statusText = '';
            _isSynthesizing = false;
          });
        }
      });

      // ── Cleanup chunk files only after playback + cache-save are done ──
      Future.wait([
        _audioPlayer.awaitStreamingComplete(),
        if (saveFuture != null) saveFuture,
      ]).then((_) {
        _audioPlayer.cleanupChunks(all: true);
      }).catchError((_) {});
    } catch (e) {
      debugPrint('TTS Error: $e');
      if (mounted) {
        setState(() {
          _statusText = 'பிழை: $e';
          _isSynthesizing = false;
        });
      }
    }
  }

  Future<void> _onStop() async {
    try {
      ttsEngine.cancelSynthesis();
      await _audioPlayer.stop();
      await _audioPlayer.cleanupChunks(all: true);
    } catch (e) {
      debugPrint('Stop error: $e');
    }
    _currentlyLoadedHadith = null; // reset so next play does a fresh start
    if (mounted) {
      setState(() {
        _statusText = '';
        _isSynthesizing = false;
      });
    }
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    // Cancel any in-flight synthesis so the isolate doesn't keep working
    // for a screen that's already gone.
    ttsEngine.cancelSynthesis();
    // Stop the player to resolve any pending awaitPlaybackComplete() or
    // awaitStreamingComplete() futures from _onPlayPauseInternal.
    _audioPlayer.stop();
    _currentlyLoadedHadith = null;
    super.dispose();
  }

  void _onSpeedChange(double speed) {
    setState(() => _playbackSpeed = speed);
    _audioPlayer.setSpeed(speed);
  }

  Future<void> _toggleBookmark() async {
    HapticFeedback.mediumImpact();
    final hadith = widget.hadith;
    final nowBookmarked = await _bookmarkService.toggleBookmark(
      key: hadith.cacheKey,
      collection: hadith.collection.name,
      hadithNumber: hadith.hadithNumber,
      book: hadith.book,
      chapter: hadith.chapter,
      textTamil: hadith.textTamil,
    );
    if (mounted) {
      setState(() {}); // Rebuild to update icon
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(nowBookmarked
              ? 'புக்மார்க் சேர்க்கப்பட்டது'
              : 'புக்மார்க் நீக்கப்பட்டது'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// Gold-accented info chip for the collapsing header
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFD4A04A),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
