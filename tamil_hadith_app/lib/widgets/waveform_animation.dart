import 'dart:math';
import 'package:flutter/material.dart';

/// Animated waveform bars visualization for audio playback.
/// Shows a mini audio waveform that pulses while playing.
class WaveformAnimation extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  final double height;
  final int barCount;

  const WaveformAnimation({
    super.key,
    required this.isPlaying,
    this.color = const Color(0xFF1B4D3E),
    this.height = 20,
    this.barCount = 5,
  });

  @override
  State<WaveformAnimation> createState() => _WaveformAnimationState();
}

class _WaveformAnimationState extends State<WaveformAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final _random = Random();
  late List<double> _phases;

  @override
  void initState() {
    super.initState();
    _phases = List.generate(widget.barCount, (_) => _random.nextDouble() * pi);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.isPlaying) _controller.repeat();
  }

  @override
  void didUpdateWidget(WaveformAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(widget.barCount, (i) {
            final phase = _phases[i];
            final t = _controller.value * 2 * pi + phase;
            final barHeight = widget.isPlaying
                ? widget.height * (0.3 + 0.7 * ((sin(t) + 1) / 2))
                : widget.height * 0.25;

            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 1.2),
              child: AnimatedContainer(
                duration: Duration(milliseconds: widget.isPlaying ? 100 : 400),
                width: 3,
                height: barHeight,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// A pulsing dot indicator (e.g. for synthesizing state).
class PulsingDot extends StatefulWidget {
  final Color color;
  final double size;

  const PulsingDot({
    super.key,
    this.color = const Color(0xFFD4A04A),
    this.size = 8,
  });

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}
