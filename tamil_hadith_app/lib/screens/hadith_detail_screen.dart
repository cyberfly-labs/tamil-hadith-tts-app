import 'package:flutter/material.dart';

import '../models/hadith.dart';
import '../services/tts_engine.dart';
import '../services/audio_player_service.dart';

/// Detail screen for a single hadith with TTS audio playback
class HadithDetailScreen extends StatefulWidget {
  final Hadith hadith;

  const HadithDetailScreen({super.key, required this.hadith});

  @override
  State<HadithDetailScreen> createState() => _HadithDetailScreenState();
}

class _HadithDetailScreenState extends State<HadithDetailScreen> {
  // TTS engine and audio player are obtained from the app-level singletons
  static final TtsEngine _ttsEngine = TtsEngine();
  static final AudioPlayerService _audioPlayer = AudioPlayerService();
  static bool _servicesInitialized = false;

  bool _isSynthesizing = false;
  bool _isPlaying = false;
  String _statusText = '';
  double _fontSize = 18.0;

  @override
  void initState() {
    super.initState();
    _initServices();
    _audioPlayer.playingStream.listen((playing) {
      if (mounted) {
        setState(() => _isPlaying = playing);
      }
    });
  }

  Future<void> _initServices() async {
    if (!_servicesInitialized) {
      await _audioPlayer.initialize();
      try {
        await _ttsEngine.initialize();
      } catch (e) {
        debugPrint('TTS init warning: $e');
      }
      _servicesInitialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ஹதீஸ் #${widget.hadith.hadithNumber}'),
        actions: [
          // Font size controls
          IconButton(
            icon: const Icon(Icons.text_decrease),
            onPressed: () => setState(() => _fontSize = (_fontSize - 2).clamp(14, 30)),
            tooltip: 'எழுத்து சிறிதாக்கு',
          ),
          IconButton(
            icon: const Icon(Icons.text_increase),
            onPressed: () => setState(() => _fontSize = (_fontSize + 2).clamp(14, 30)),
            tooltip: 'எழுத்து பெரிதாக்கு',
          ),
        ],
      ),
      body: Column(
        children: [
          // Hadith content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Book & number badge
                  Wrap(
                    spacing: 8,
                    children: [
                      _Badge(
                        text: widget.hadith.book,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      _Badge(
                        text: 'ஹதீஸ் #${widget.hadith.hadithNumber}',
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ],
                  ),
                  if (widget.hadith.chapter.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.hadith.chapter,
                      style: TextStyle(
                        fontSize: _fontSize + 2,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                  const Divider(height: 24),
                  // Main hadith text
                  SelectableText(
                    widget.hadith.textTamil,
                    style: TextStyle(
                      fontSize: _fontSize,
                      height: 1.8,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 80), // Space for bottom bar
                ],
              ),
            ),
          ),
          // TTS playback bar
          _buildPlaybackBar(context),
        ],
      ),
    );
  }

  Widget _buildPlaybackBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_statusText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _statusText,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Play/Pause button
                FilledButton.icon(
                  onPressed: _isSynthesizing ? null : _onPlayPause,
                  icon: _isSynthesizing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  label: Text(
                    _isSynthesizing
                        ? 'ஒலிப்பதிவு...'
                        : _isPlaying
                            ? 'நிறுத்து'
                            : 'ஒலிக்கவும்',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                // Stop button
                if (_isPlaying)
                  IconButton.filled(
                    onPressed: _onStop,
                    icon: const Icon(Icons.stop),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onPlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
      return;
    }

    setState(() {
      _isSynthesizing = true;
      _statusText = 'உரையை ஒலியாக மாற்றுகிறது...';
    });

    try {
      // Synthesize the hadith text
      final text = widget.hadith.textTamil;
      final audio = await _ttsEngine.synthesize(text);

      if (audio != null && audio.isNotEmpty) {
        setState(() {
          _statusText = 'ஒலிக்கிறது...';
          _isSynthesizing = false;
        });
        await _audioPlayer.playPcmAudio(audio);
      } else {
        setState(() {
          _statusText = 'ஒலிப்பதிவு தோல்வி';
          _isSynthesizing = false;
        });
      }
    } catch (e) {
      debugPrint('TTS Error: $e');
      setState(() {
        _statusText = 'பிழை: $e';
        _isSynthesizing = false;
      });
    }
  }

  Future<void> _onStop() async {
    await _audioPlayer.stop();
    setState(() {
      _statusText = '';
    });
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}
