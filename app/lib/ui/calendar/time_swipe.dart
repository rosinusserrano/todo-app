// The calendar's horizontal swipe: the page follows the finger, and letting go
// either turns it or puts it back.
//
// **The neighbouring page is drawn beside it.** Dragging a little shows the
// edge of next week (or tomorrow) and letting go short of the threshold puts
// it back - a glimpse without going there. That costs nothing extra to load:
// [AppState.calendarLoadRange] fetches one step either side of the visible
// window, so the neighbour's events are already in memory when the finger
// arrives. Each neighbour is built only while the page is off centre.
//
// The page in the middle is still **the same child** across a turn, never a
// second instance swapped in. That is load-bearing: the grid's State holds its
// vertical scroll, so a page keyed per week would land every swipe back at the
// top of the day rather than at the hour you were looking at. A turn slides
// the neighbour all the way in, steps, and then puts the offset back to zero
// in the same frame the middle page is rebuilt for the new week ([page]
// changing is what says so) - and since the neighbour was reading the same
// shared scroll offset, the swap is invisible.
//
// Where there is no neighbour to draw (the year), the old trick is kept: the
// page slides off, the step happens out of sight, and it slides in from the
// other side, fading so that nothing being behind it does not show.
//
// Only the swipe animates. The arrows and Today jump, and so does the edge
// zone that steps the grid under a lifted pending block - that one *must*
// jump, because the drop is resolved against where the grid is drawn and a
// grid half-way through a slide is not where it is drawn.

import 'package:flutter/material.dart';

import 'time_grid.dart' show kHourHeight;

class TimeSwipe extends StatefulWidget {
  const TimeSwipe({
    super.key,
    required this.onStep,
    required this.page,
    required this.builder,
  });

  /// One step forwards (1) or back (-1). Awaited: the new page comes in once
  /// its events are loaded, so it never arrives empty and then fills.
  final Future<void> Function(int) onStep;

  /// What the middle page is showing - the first day of the window, say. When
  /// it changes the offset goes back to zero in the same frame.
  final Object page;

  /// The page [delta] steps away from the current one, sharing [scroll] - the
  /// vertical offset every page reads, so a neighbour is drawn at the hour
  /// the middle page is scrolled to. Null for a neighbour that cannot be
  /// drawn; delta 0 must always build.
  final Widget? Function(int delta, ValueNotifier<double> scroll) builder;

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

  /// Where the day is scrolled to, shared by the page and its neighbours.
  /// Opens on the working day, as the grid always has.
  final _scroll = ValueNotifier<double>(7 * kHourHeight);

  /// A turn in flight. The finger is ignored until it has landed, or a second
  /// swipe would start from a page that is not there yet.
  bool _turning = false;

  @override
  void initState() {
    super.initState();
    _offset = AnimationController.unbounded(vsync: this);
  }

  @override
  void didUpdateWidget(TimeSwipe old) {
    super.didUpdateWidget(old);
    // The step landed: the middle page now shows what the neighbour did.
    if (widget.page != old.page) {
      _offset.stop();
      _offset.value = 0;
    }
  }

  @override
  void dispose() {
    _offset.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _hasNeighbour(int dir) => widget.builder(dir, _scroll) != null;

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
      if (_hasNeighbour(dir)) {
        // Bring the neighbour the rest of the way in; the step then makes it
        // the middle page and didUpdateWidget zeroes the offset under it.
        await _offset.animateTo(
          out,
          duration: _over(out - _offset.value, 240),
          curve: Curves.easeOutCubic,
        );
        await widget.onStep(dir);
        if (mounted) _offset.value = 0;
        return;
      }
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
                // Moving left uncovers what comes after; right, before.
                final dir = x < 0 ? 1 : (x > 0 ? -1 : 0);
                final neighbour = dir == 0
                    ? null
                    : widget.builder(dir, _scroll);
                // One shape whether a neighbour is drawn or not, and the
                // middle page keyed: a parent that changed would rebuild the
                // grid from scratch and drop its scroll.
                return Stack(
                  children: [
                    if (neighbour != null)
                      Positioned.fill(
                        key: ValueKey(dir),
                        child: FractionalTranslation(
                          translation: Offset(x + dir, 0),
                          // Looked at, not used: it becomes usable by
                          // becoming the middle page.
                          child: IgnorePointer(
                            child: ExcludeSemantics(child: neighbour),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      key: const ValueKey('page'),
                      child: FractionalTranslation(
                        translation: Offset(x, 0),
                        // With nothing beside it, fading as it goes is what
                        // hides that nothing is drawn behind.
                        child: Opacity(
                          opacity: neighbour != null
                              ? 1
                              : (1 - x.abs() * 0.6).clamp(0.0, 1.0),
                          child: child,
                        ),
                      ),
                    ),
                  ],
                );
              },
              child: widget.builder(0, _scroll)!,
            ),
          ),
        );
      },
    );
  }
}
