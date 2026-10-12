// The calendar's horizontal swipe: the page follows the finger, and letting go
// either turns it or puts it back.
//
// There is no neighbouring page drawn beside it, deliberately. A real pager
// would need next week's events loaded before anyone asked for them, and
// [AppState.refreshEvents] loads exactly one window. Instead the page you are
// holding slides off, the step happens while it is out of sight, and the new
// one slides in from the other side - **the same child**, never a second
// instance. That is load-bearing: the grid's State holds its vertical scroll,
// so a page keyed per week (an AnimatedSwitcher, say) would land every swipe
// back at the top of the day rather than at the hour you were looking at.
//
// Only the swipe animates. The arrows and Today jump, and so does the edge
// zone that steps the grid under a lifted pending block - that one *must*
// jump, because the drop is resolved against where the grid is drawn and a
// grid half-way through a slide is not where it is drawn.

import 'package:flutter/material.dart';

class TimeSwipe extends StatefulWidget {
  const TimeSwipe({super.key, required this.onStep, required this.child});

  /// One step forwards (1) or back (-1). Awaited: the new page comes in once
  /// its events are loaded, so it never arrives empty and then fills.
  final Future<void> Function(int) onStep;
  final Widget child;

  /// A fling at least this fast turns the page whatever the distance.
  static const flingVelocity = 220.0;

  /// A slow drag turns it once it is past this fraction of the width.
  static const dragFraction = 0.35;

  @override
  State<TimeSwipe> createState() => _TimeSwipeState();
}

class _TimeSwipeState extends State<TimeSwipe>
    with SingleTickerProviderStateMixin {
  /// The offset as a fraction of the width: 0 at rest, -1 fully off to the
  /// left. Unbounded because the drag writes it directly.
  late final AnimationController _offset;
  double _width = 1;

  /// A turn in flight. The finger is ignored until it has landed, or a second
  /// swipe would start from a page that is not there yet.
  bool _turning = false;

  @override
  void initState() {
    super.initState();
    _offset = AnimationController.unbounded(vsync: this);
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  Duration _over(double distance, int fullMs) => Duration(
    milliseconds: (fullMs * distance.abs()).round().clamp(60, fullMs),
  );

  void _update(DragUpdateDetails d) {
    if (_turning) return;
    _offset.value += (d.primaryDelta ?? 0) / _width;
  }

  void _end(DragEndDetails d) {
    if (_turning) return;
    final v = d.primaryVelocity ?? 0;
    final x = _offset.value;
    // Leftwards - the content sliding away to the left - is forwards, which is
    // the direction every calendar on a phone agrees on.
    final dir = v.abs() >= TimeSwipe.flingVelocity
        ? (v < 0 ? 1 : -1)
        : x.abs() >= TimeSwipe.dragFraction
        ? (x < 0 ? 1 : -1)
        : 0;
    if (dir == 0) {
      _settle();
    } else {
      _turn(dir);
    }
  }

  void _settle() {
    if (_turning) return;
    _offset.animateTo(
      0,
      duration: _over(_offset.value, 200),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _turn(int dir) async {
    _turning = true;
    try {
      if (MediaQuery.of(context).disableAnimations) {
        _offset.value = 0;
        await widget.onStep(dir);
        return;
      }
      final out = -dir.toDouble();
      await _offset.animateTo(
        out,
        duration: _over(out - _offset.value, 160),
        curve: Curves.easeIn,
      );
      await widget.onStep(dir);
      if (!mounted) return;
      _offset.value = dir.toDouble();
      await _offset.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _turning = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        _width = box.maxWidth > 0 ? box.maxWidth : 1;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: _update,
          onHorizontalDragEnd: _end,
          onHorizontalDragCancel: _settle,
          // Clipped, or in the split the page slides out over the task list.
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _offset,
              builder: (context, child) {
                final x = _offset.value;
                return FractionalTranslation(
                  translation: Offset(x, 0),
                  // Fading as it goes is what hides that nothing is drawn behind.
                  child: Opacity(
                    opacity: (1 - x.abs() * 0.6).clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}
