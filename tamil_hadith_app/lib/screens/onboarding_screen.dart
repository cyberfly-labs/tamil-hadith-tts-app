import 'dart:io';

import 'package:flutter/material.dart';

import '../services/model_download_service.dart';

/// Onboarding screen shown on first launch.
/// Downloads the TTS model (~28 MB INT8) from HuggingFace with progress UI.
class OnboardingScreen extends StatefulWidget {
  /// Called when the model is ready and onboarding is complete.
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final ModelDownloadService _downloadService = ModelDownloadService();

  _DownloadState _state = _DownloadState.idle;
  double _progress = 0.0;
  String _statusText = '';
  String _errorText = '';
  int _totalBytes = 0;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim =
        Tween<double>(begin: 0.85, end: 1.0).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    _checkAndDownload();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkAndDownload() async {
    await _downloadService.initialize();

    // Already downloaded? Skip onboarding.
    if (await _downloadService.isModelDownloaded) {
      widget.onComplete();
      return;
    }

    _startDownload();
  }

  Future<void> _startDownload() async {
    setState(() {
      _state = _DownloadState.downloading;
      _progress = 0;
      _statusText = 'ஒலி மாதிரியை பதிவிறக்குகிறது...';
      _errorText = '';
    });

    try {
      await _downloadService.downloadModel(
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _totalBytes = total;
            if (total > 0) {
              _progress = received / total;
              final receivedMB = (received / (1024 * 1024)).toStringAsFixed(1);
              final totalMB = (total / (1024 * 1024)).toStringAsFixed(0);
              _statusText = '$receivedMB / $totalMB MB';
            } else {
              final receivedMB = (received / (1024 * 1024)).toStringAsFixed(1);
              _statusText = '$receivedMB MB பதிவிறக்கம்...';
            }
          });
        },
      );

      if (mounted) {
        setState(() {
          _state = _DownloadState.complete;
          _progress = 1.0;
          _statusText = 'பதிவிறக்கம் முடிந்தது!';
        });

        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) widget.onComplete();
      }
    } on SocketException catch (e) {
      if (mounted) {
        setState(() {
          _state = _DownloadState.error;
          _errorText = 'இணைய இணைப்பு இல்லை.\n$e';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _DownloadState.error;
          _errorText = 'பதிவிறக்க பிழை:\n$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.primary.withValues(alpha: 0.06),
              cs.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 48),

                      // ── Animated branding ──
                      ScaleTransition(
                        scale: _pulseAnim,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                cs.primary,
                                cs.primary.withValues(alpha: 0.7),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: cs.primary.withValues(alpha: 0.3),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.auto_stories_rounded,
                            size: 44,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      Text(
                        'புகாரி ஹதீஸ்',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'AI தமிழ் ஒலி பதிப்பு',
                        style: TextStyle(
                          fontSize: 15,
                          color: cs.onSurface.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 40),

                      // ── Download states ──
                      if (_state == _DownloadState.idle)
                        CircularProgressIndicator(
                          strokeWidth: 3,
                          color: cs.primary,
                        ),

                      if (_state == _DownloadState.downloading) ...[
                        // Feature highlights
                        _FeatureRow(
                          icon: Icons.wifi_off_rounded,
                          text: 'இணையம் இல்லாமல் வேலை செய்யும்',
                          color: cs,
                        ),
                        const SizedBox(height: 10),
                        _FeatureRow(
                          icon: Icons.record_voice_over_rounded,
                          text: 'AI ஒலி - முதல் முறை மட்டும் தேவை',
                          color: cs,
                        ),
                        const SizedBox(height: 24),

                        // Progress bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: _totalBytes > 0 ? _progress : null,
                            minHeight: 10,
                            backgroundColor: cs.surfaceContainerHighest,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Percentage + size text
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _statusText,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                            if (_totalBytes > 0)
                              Text(
                                '${(_progress * 100).toInt()}%',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: cs.primary,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ஒலி AI மாதிரி (~28 MB)',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.35),
                          ),
                        ),
                      ],

                      if (_state == _DownloadState.complete) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded,
                              size: 40, color: Colors.green),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _statusText,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ],

                      if (_state == _DownloadState.error) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cs.error.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child:
                              Icon(Icons.cloud_off_rounded, size: 40, color: cs.error),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorText,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: cs.error, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _startDownload,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('மீண்டும் முயற்சி'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                          ),
                        ),
                      ],

                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final ColorScheme color;

  const _FeatureRow({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: color.onSurface.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

enum _DownloadState { idle, downloading, complete, error }
