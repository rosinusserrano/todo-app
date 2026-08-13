// Where a sheet sits in the shell, and how it arrives and leaves.
//
// The three panels that cover the content area - Settings, the sound sheet and
// a block's sublist - were each a bare `if (_open) Sheet(...)` in the shell's
// Stack, which meant they appeared and vanished between two frames. That reads
// as a glitch rather than as a panel: nothing tells the eye where the thing
// came from, and on the way out the content behind it seems to flash.
//
// This owns **how a sheet moves, not where it sits.** Each sheet still returns
// its own `Positioned(top: TitleBar.height, …)` - that rule (a sheet stops below
// the title bar so the window stays draggable, pinnable and closable) is the
// sheet's own statement about itself, and it is the one thing in main.dart's
// header that must not become action-at-a-distance.
//
// Which is why the child goes into a nested `Stack`: a `Positioned` is only
// legal as a direct child of one, and it has to be wrapped in something that
// can be translated. The inner Stack fills the shell, so `top` and `bottom`
// resolve against exactly the box they did before.
//
// The transition is a slide from the bottom edge - the direction the gesture
// implies, and the same one the task composer uses, so every panel in the app
// arrives the same way.
//
// The exit is the half that needs the machinery. A widget removed from the tree
// cannot animate itself out, so this keeps the last child it built and goes on
// showing it until the reverse finishes - which is also why the builder is a
// callback rather than a widget. The sublist sheet is built from `_sublist!`,
// and that goes null the instant it is closed; without the cached child the
// closing animation would rebuild from a null and crash.

import 'package:flutter/material.dart';

import '../theme.dart';

class SheetTransition extends StatefulWidget {
  const SheetTransition({
    super.key,
    required this.open,
    required this.builder,
  });

  final bool open;

  /// Called only while [open]. See the header for why the result is cached
  /// rather than rebuilt on the way out.
  final WidgetBuilder builder;

  @override
  State<SheetTransition> createState() => _SheetTransitionState();
}

class _SheetTransitionState extends State<SheetTransition>
    with SingleTickerProviderStateMixin {
  /// Built in [initState], **not** as a `late final` initialiser.
  ///
  /// A sheet that is never opened never reads this from `build` - the closed
  /// case returns early - so a lazy field would first be touched by `dispose`,
  /// where `vsync: this` looks up `TickerMode.of(context)` on an element that
  /// has already been deactivated. That throws "looking up a deactivated
  /// widget's ancestor is unsafe" during teardown, which is a crash in exactly
  /// the case that does nothing.
  late final AnimationController _c;

  /// The last thing built while open, shown for the length of the exit.
  Widget? _closed;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: T.sheetDur,
      // Opening already-open (a hot reload, a rebuild with the flag set) must
      // not replay the entrance.
      value: widget.open ? 1 : 0,
    )..addStatusListener((status) {
        // Fully closed: let go of the child so the sheet's state, its
        // controllers and any listener it holds are actually disposed. Without
        // this the panel is invisible but still alive.
        if (status == AnimationStatus.dismissed && mounted) {
          setState(() => _closed = null);
        }
      });
  }

  @override
  void didUpdateWidget(SheetTransition old) {
    super.didUpdateWidget(old);
    if (widget.open == old.open) return;
    if (widget.open) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.open) _closed = widget.builder(context);
    final child = _closed;

    // Nothing to show and nothing to finish showing.
    //
    // **Positioned, and that is load-bearing.** A Stack sizes itself to its
    // *non-positioned* children: `width` starts at `constraints.minWidth` and
    // grows to the widest of them. Under tight constraints that is harmless,
    // but the shell's Stack sits in a Scaffold body, which lays out **loose** -
    // so a bare `SizedBox.shrink()` here made the maximum zero and collapsed
    // the entire window to 0x0. The background and border still painted, since
    // they are drawn by the AnimatedContainer above; everything inside was
    // clipped away. The app opened blank.
    //
    // A positioned child never contributes to that maximum, so with all
    // children positioned the Stack falls back to `constraints.biggest` and
    // fills the window as it did before this widget existed.
    if (child == null) {
      return const Positioned(width: 0, height: 0, child: SizedBox.shrink());
    }

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, inner) {
          final t = T.sheetEase.transform(_c.value);
          return FractionalTranslation(
            // Its own height below the shell at rest, so the panel comes up
            // from the bottom edge rather than growing out of the middle.
            translation: Offset(0, 1 - t),
            child: Opacity(
              // Reaches full opacity early in the slide: a sheet still mostly
              // off screen looks like it is dissolving as well as moving.
              opacity: Curves.easeOut.transform((t * 1.6).clamp(0.0, 1.0)),
              child: inner,
            ),
          );
        },
        // The nested Stack is what lets the sheet keep its own Positioned.
        child: Stack(children: [child]),
      ),
    );
  }
}
