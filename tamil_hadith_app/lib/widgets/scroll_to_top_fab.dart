import 'package:flutter/material.dart';
import '../theme.dart';

/// A floating action button that appears when the user scrolls down,
/// providing a smooth scroll-to-top action.
class ScrollToTopFab extends StatefulWidget {
  final ScrollController scrollController;
  final double showOffset;
  final Object? heroTag;

  const ScrollToTopFab({
    super.key,
    required this.scrollController,
    this.showOffset = 400,
    this.heroTag,
  });

  @override
  State<ScrollToTopFab> createState() => _ScrollToTopFabState();
}

class _ScrollToTopFabState extends State<ScrollToTopFab> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final shouldShow =
        widget.scrollController.offset > widget.showOffset;
    if (shouldShow != _show) {
      setState(() => _show = shouldShow);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedScale(
      scale: _show ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: _show ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: FloatingActionButton.small(
          heroTag: widget.heroTag,
          onPressed: () {
            widget.scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
            );
          },
          backgroundColor: isDark ? AppTheme.darkEmerald : AppTheme.emerald,
          foregroundColor: isDark ? AppTheme.darkGold : AppTheme.gold,
          elevation: 4,
          child: const Icon(Icons.keyboard_arrow_up_rounded, size: 24),
        ),
      ),
    );
  }
}
