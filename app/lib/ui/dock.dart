// The phone's one bar: three filled segments along the bottom edge, each the
// door to one kind of place.
//
//   workspace   which workspace you are in - filled in its colour
//   where       which view of it: Tasks, Notes, Parked, History
//   more        what belongs to no workspace: Calendar, the list, Thoughts,
//               Settings
//
// It replaced three controls spread over the screen - the workspace pill at the
// top, the four-icon view bar at the bottom, and the calendar / list / settings
// buttons in the title bar - and the reason is the order you think in. "Where
// am I, what am I looking at, what else is there" is one question asked left
// to right, and it now reads left to right in the place a thumb already rests.
//
// **Press, slide, let go.** Touching a segment grows its menu upward out of
// it; the row under the finger lights as the finger slides up, and letting go
// goes there. One gesture with nothing to aim at twice - the menu's rows are
// as wide as a thumb is careless. Letting go anywhere off the menu does
// nothing, which is how you change your mind. A plain tap leaves the menu open
// instead, so a careful hand can still tap-then-tap.
//
// **Slide right for the second thing.** A row that has another action keeps it
// at its right-hand end - edit a workspace, add a task, write a thought - and
// carrying the finger over to it is how you ask for it. The row's label says
// what letting go there will do, so the gesture explains itself while it runs.
//
// **Sliding along the bar switches menus,** the way a desktop menu bar does once
// one menu is open. A finger that landed on the wrong segment does not have to
// lift.
//
// Why a Listener and not gesture recognisers: the whole thing is one pointer's
// life, from the press on a segment to the release over a row that did not
// exist when it started. Pointer events go to whatever was hit at the press for
// as long as the pointer is down, so the segment's Listener sees every move and
// can ask the menu's render box where the finger is - no arena, nothing to win.
//
// Geometry goes through RenderBox transforms (`globalToLocal`,
// `localToGlobal(ancestor:)`), never through raw `position` arithmetic: UiScale
// sits between the screen and this widget, and a pointer's global position is
// in screen pixels while the overlay lays out in layout units.

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'thought_pressure.dart';

/// One row of a segment's menu.
class DockItem {
  const DockItem({
    required this.label,
    required this.onChoose,
    this.icon,
    this.fill,
    this.current = false,
    this.count = 0,
    this.dot = false,
    this.secondaryIcon,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String label;
  final IconData? icon;

  /// The row's own colour - a workspace's. Null is the neutral menu fill.
  final Color? fill;

  /// The place you are now. Drawn as a bar at the row's leading edge.
  final bool current;

  /// A number after the label (the thought pile). Zero draws nothing.
  final int count;

  /// Something here wants looking at (a parked review that is due).
  final bool dot;

  final VoidCallback onChoose;

  /// The row's second action, at its right-hand end. All three or none.
  final IconData? secondaryIcon;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
}

/// One of the bar's segments, and the menu it opens.
class DockSegment {
  const DockSegment({
    required this.label,
    required this.fill,
    required this.ink,
    required this.items,
    this.icon,
    this.dimmed = false,
    this.count = 0,
    this.dot = false,
    this.pressure = 0,
    this.semanticLabel,
    this.width,
  });

  final String label;
  final IconData? icon;
  final Color fill;

  /// Text and icon colour on [fill].
  final Color ink;

  /// Top to bottom, as drawn.
  final List<DockItem> items;

  /// Something that is not this segment's owns the screen (the calendar over
  /// the task list), so what it names is not what you are looking at.
  final bool dimmed;

  final int count;
  final bool dot;

  /// The thought pile's escalation (see [ThoughtPulse]), carried by whichever
  /// segment holds Thoughts. Drives the tint and the pulse.
  final int pressure;

  final String? semanticLabel;

  /// A fixed width. Null shares what is left equally with the other null
  /// segments - the three places do; the quick-action ＋ is a fixed square.
  final double? width;
}

class Dock extends StatefulWidget {
  const Dock({
    super.key,
    required this.segments,
    this.height = 48,
    this.underhang = 0,
  });

  final List<DockSegment> segments;
  final double height;

  /// How far below its own box the bar's colours carry on: the home
  /// indicator's strip on a phone, which the shell's SafeArea keeps content
  /// out of. Without it that strip was a band of bare window under the bar,
  /// and the bar looked like it was hovering a finger's width off the edge.
  /// Painted only - nothing there takes a touch, which is the system's swipe
  /// home anyway. The ancestors between here and the window must not clip
  /// (see `_shell` in main.dart).
  final double underhang;

  /// A menu row. Wide enough for a thumb that is not looking.
  static const rowHeight = 48.0;

  /// The second action's target at a row's right-hand end.
  static const secondaryWidth = 56.0;

  /// The narrowest a menu is drawn, whatever the segment's width - a third of
  /// a phone is not room for a workspace's name and its edit target.
  static const menuMinWidth = 220.0;

  @override
  State<Dock> createState() => DockState();
}

/// Public so a test can read which row the finger is on.
class DockState extends State<Dock> with TickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _menuKey = GlobalKey();
  final _scroll = ScrollController();

  late final ThoughtPulse _pulse = ThoughtPulse(this);

  /// Which segment's menu is open, or null.
  int? _open;

  /// Opened by a tap, and stays until something is picked or it is dismissed.
  /// False while a finger is holding it open.
  bool _sticky = false;

  /// The row under the finger, and whether the finger is on its second action.
  int? _hover;
  bool _hoverSecondary = false;

  int? _pointer;
  Offset _downAt = Offset.zero;
  bool _moved = false;

  /// The press landed on the segment whose menu was already open by a tap, so
  /// lifting without moving closes it.
  bool _tapCloses = false;

  int get _pressure =>
      widget.segments.fold(0, (m, s) => math.max(m, s.pressure));

  @override
  void initState() {
    super.initState();
    _pulse.sync(_pressure);
  }

  @override
  void didUpdateWidget(Dock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pulse.sync(_pressure);
    // The menus are rebuilt from state on every notify. A row that went away
    // under a finger must not stay "hovered" at an index that now means
    // something else.
    final open = _open;
    if (open != null &&
        (open >= widget.segments.length ||
            (_hover ?? 0) >= widget.segments[open].items.length)) {
      _hover = null;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ the gesture

  void _openMenu(int segment, {required bool sticky}) {
    setState(() {
      _open = segment;
      _sticky = sticky;
      _hover = null;
      _hoverSecondary = false;
    });
    if (!_portal.isShowing) _portal.show();
  }

  void close() {
    if (_open == null) return;
    setState(() {
      _open = null;
      _sticky = false;
      _hover = null;
      _hoverSecondary = false;
      _pointer = null;
    });
    _portal.hide();
  }

  void _down(int segment, PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _downAt = e.position;
    _moved = false;
    _tapCloses = _open == segment && _sticky;
    if (_open != segment) HapticFeedback.selectionClick();
    _openMenu(segment, sticky: false);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if (!_moved && (e.position - _downAt).distance > kTouchSlop) {
      _moved = true;
      _tapCloses = false;
    }
    if (!_moved) return;

    // Back down on the bar: switch to whichever segment is under the finger.
    final dock = context.findRenderObject() as RenderBox?;
    if (dock != null && dock.hasSize) {
      final local = dock.globalToLocal(e.position);
      if ((Offset.zero & dock.size).contains(local)) {
        final spans = _spans(dock.size.width);
        var at = spans.length - 1;
        for (var i = 0; i < spans.length; i++) {
          if (local.dx < spans[i].$1 + spans[i].$2) {
            at = i;
            break;
          }
        }
        if (at != _open) {
          HapticFeedback.selectionClick();
          _openMenu(at, sticky: false);
        } else if (_hover != null) {
          setState(() => _hover = null);
        }
        return;
      }
    }

    final (row, secondary) = _rowAt(e.position);
    if (row != _hover || secondary != _hoverSecondary) {
      if (row != null) HapticFeedback.selectionClick();
      setState(() {
        _hover = row;
        _hoverSecondary = secondary;
      });
    }
  }

  void _up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (!_moved) {
      // A tap: leave the menu up for a second tap, or close it if it was
      // already up.
      if (_tapCloses) {
        close();
      } else {
        setState(() => _sticky = true);
      }
      return;
    }
    final open = _open;
    final row = _hover;
    final secondary = _hoverSecondary;
    close();
    if (open == null || row == null) return;
    _fire(widget.segments[open].items[row], secondary);
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (!_sticky) close();
  }

  void _fire(DockItem item, bool secondary) {
    if (secondary && item.onSecondary != null) {
      item.onSecondary!();
    } else {
      item.onChoose();
    }
  }

  /// Which row of the open menu is at [global], and whether it is on that
  /// row's second action. Null off the menu.
  (int?, bool) _rowAt(Offset global) {
    final open = _open;
    final box = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    if (open == null || box == null || !box.hasSize) return (null, false);
    final local = box.globalToLocal(global);
    if (!(Offset.zero & box.size).contains(local)) return (null, false);
    final items = widget.segments[open].items;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final row = ((local.dy + offset) / Dock.rowHeight).floor();
    if (row < 0 || row >= items.length) return (null, false);
    final secondary =
        items[row].onSecondary != null &&
        local.dx >= box.size.width - Dock.secondaryWidth;
    return (row, secondary);
  }

  // ------------------------------------------------------------ drawing

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _menu,
      child: SizedBox(
        height: widget.height,
        child: AnimatedBuilder(
          animation: _pulse.controller,
          builder: (context, _) => Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < widget.segments.length; i++)
                      _sized(
                        widget.segments[i],
                        Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (e) => _down(i, e),
                          onPointerMove: _move,
                          onPointerUp: _up,
                          onPointerCancel: _cancel,
                          child: _segment(widget.segments[i], open: _open == i),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.underhang > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  top: widget.height,
                  height: widget.underhang,
                  child: IgnorePointer(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < widget.segments.length; i++)
                          _sized(
                            widget.segments[i],
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              color: _fillOf(
                                widget.segments[i],
                                open: _open == i,
                              ),
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

  Widget _sized(DockSegment seg, Widget child) => seg.width == null
      ? Expanded(child: child)
      : SizedBox(width: seg.width, child: child);

  /// Each segment's left edge and width across a bar [total] wide - the same
  /// split the Row makes, for the code that has to find a segment from a
  /// point (the slide along the bar) or a menu's place from a segment.
  List<(double, double)> _spans(double total) {
    final fixed = widget.segments.fold(0.0, (w, s) => w + (s.width ?? 0));
    final shared = widget.segments.where((s) => s.width == null).length;
    final each = shared == 0 ? 0.0 : (total - fixed) / shared;
    var x = 0.0;
    return [
      for (final s in widget.segments)
        () {
          final w = s.width ?? each;
          final span = (x, w);
          x += w;
          return span;
        }(),
    ];
  }

  Color _fillOf(DockSegment seg, {required bool open}) {
    var fill = seg.fill;
    if (seg.pressure > 0) {
      final hot = ThoughtPulse.intensityOf(seg.pressure);
      final glow = ThoughtPulse.pulsingAt(seg.pressure)
          ? Curves.easeInOut.transform(_pulse.controller.value)
          : 0.0;
      fill = Color.lerp(
        fill,
        T.complementary(T.thoughts),
        hot * (0.35 + glow * 0.25),
      )!;
    }
    // Dimmed fades the block, not its label: something else owns the screen,
    // so this one steps back - but it is still a door and still has to read.
    if (seg.dimmed) fill = Color.lerp(fill, T.bgSolid, 0.55)!;
    if (open) fill = Color.lerp(fill, Colors.white, 0.14)!;
    return fill;
  }

  Widget _segment(DockSegment seg, {required bool open}) {
    final fill = _fillOf(seg, open: open);
    final ink = seg.dimmed ? T.inkOn(fill).withValues(alpha: 0.75) : seg.ink;

    return Semantics(
      button: true,
      label: seg.semanticLabel ?? seg.label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: fill,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: T.s2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (seg.icon != null) ...[
                      Icon(
                        seg.icon,
                        size: seg.label.isEmpty ? 22 : 18,
                        color: ink,
                      ),
                      if (seg.label.isNotEmpty) const SizedBox(width: T.s1 + 2),
                    ],
                    if (seg.label.isNotEmpty)
                      Flexible(
                        child: Text(
                          seg.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: T.fsLabel,
                            fontFamily: T.fontDisplay,
                            fontWeight: T.wMedium,
                            color: ink,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // The count and the dot sit in the corner, not after the label:
            // inline, they took the room the label needed and "Thoughts 3"
            // came out as "Thoug… 3".
            if (seg.count > 0 || seg.dot)
              Positioned(
                top: T.s1,
                right: T.s1 + 2,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (seg.count > 0)
                      Text(
                        '${seg.count}',
                        style: TextStyle(
                          fontSize: T.fsMeta,
                          fontFamily: T.fontDisplay,
                          fontWeight: T.wMedium,
                          color: ink.withValues(alpha: 0.75),
                        ),
                      ),
                    if (seg.count > 0 && seg.dot) const SizedBox(width: 3),
                    if (seg.dot) const _Dot(),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The open menu, drawn in the overlay: grown up out of its segment, with a
  /// scrim over everything above the bar.
  Widget _menu(BuildContext context) {
    final open = _open;
    final dock = this.context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(this.context).context.findRenderObject() as RenderBox?;
    if (open == null || dock == null || overlay == null || !dock.hasSize) {
      return const SizedBox.shrink();
    }
    final origin = dock.localToGlobal(Offset.zero, ancestor: overlay);
    final dockWidth = dock.size.width;
    final (segLeft, segWidth) = _spans(dockWidth)[open];
    final width = math.min(dockWidth, math.max(segWidth, Dock.menuMinWidth));
    // Over its own segment where it fits, kept inside the bar where it does not:
    // the first menu grows from the left edge, the last from the right.
    final left = (segLeft + segWidth / 2 - width / 2).clamp(
      0.0,
      dockWidth - width,
    );
    final seg = widget.segments[open];
    final maxHeight = math.max(Dock.rowHeight * 2, origin.dy - 24);

    return Stack(
      children: [
        // Over everything above the bar, not the bar itself: a press on
        // another segment has to reach it.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: origin.dy,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => close(),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 140),
              builder: (_, t, _) =>
                  ColoredBox(color: Colors.black.withValues(alpha: 0.38 * t)),
            ),
          ),
        ),
        Positioned(
          left: origin.dx + left,
          width: width,
          bottom: overlay.size.height - origin.dy,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(open),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 150),
            curve: T.sheetEase,
            builder: (_, t, child) => ClipRect(
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: t,
                child: child,
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                controller: _scroll,
                // Scrolling is for a tapped-open menu only. A held one is
                // steered by the finger, and a scroll under it would move the
                // rows away from where the finger is pointing.
                physics: _sticky
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                child: Column(
                  key: _menuKey,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < seg.items.length; i++)
                      _row(
                        seg.items[i],
                        hovered: _hover == i,
                        secondary: _hover == i && _hoverSecondary,
                        // A rule between two rows of one colour; rows that
                        // differ in colour are already told apart.
                        rule:
                            i > 0 && seg.items[i - 1].fill == seg.items[i].fill,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(
    DockItem item, {
    required bool hovered,
    required bool secondary,
    required bool rule,
  }) {
    final own = item.fill;
    final base = own ?? _menuFill;
    final ink = own == null ? T.text : T.inkOn(own);
    final fill = hovered
        ? Color.lerp(base, Colors.white, own == null ? 0.14 : 0.38)!
        : base;
    final label = secondary ? item.secondaryLabel ?? item.label : item.label;

    return Semantics(
      button: true,
      selected: item.current,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Taps only matter in a tapped-open menu; a held one is chosen on
        // release by the segment's Listener, which owns that pointer.
        onTap: () {
          close();
          item.onChoose();
        },
        child: SizedBox(
          height: Dock.rowHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 90),
                  color: fill,
                ),
              ),
              if (rule)
                Positioned(
                  top: 0,
                  left: T.s4,
                  right: T.s4,
                  child: Container(
                    height: 1,
                    color: ink.withValues(alpha: 0.12),
                  ),
                ),
              // Where you are now: a short bar laid over the leading edge, not
              // a box around the row - and not *in* the row either, where it
              // pushed the current row's label sideways out of line with the
              // others.
              Positioned(
                left: 0,
                top: (Dock.rowHeight - 20) / 2,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: item.current ? 4 : 0,
                  height: 20,
                  color: ink,
                ),
              ),
              Positioned.fill(
                child: Row(
                  children: [
                    SizedBox(width: hovered ? T.s4 + 4 : T.s4),
                    if (item.icon != null) ...[
                      Icon(item.icon, size: 18, color: ink),
                      const SizedBox(width: T.s3),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: T.fsMenu,
                          fontFamily: T.fontDisplay,
                          fontWeight: item.current || hovered
                              ? T.wMedium
                              : T.wNormal,
                          color: ink,
                        ),
                      ),
                    ),
                    if (item.count > 0) ...[
                      const SizedBox(width: T.s2),
                      Text(
                        '${item.count}',
                        style: TextStyle(
                          fontSize: T.fsLabel,
                          fontFamily: T.fontDisplay,
                          color: ink.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                    if (item.dot) ...[
                      const SizedBox(width: T.s2),
                      const _Dot(),
                    ],
                    if (item.onSecondary != null)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          close();
                          item.onSecondary!();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 90),
                          width: Dock.secondaryWidth,
                          height: Dock.rowHeight,
                          color: secondary ? ink : Colors.transparent,
                          child: Icon(
                            item.secondaryIcon,
                            size: 18,
                            color: secondary
                                ? fill
                                : ink.withValues(alpha: hovered ? 0.9 : 0.4),
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: T.s4),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static final _menuFill = Color.lerp(T.bgSolid, T.text, 0.10)!;
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: const BoxDecoration(color: T.danger, shape: BoxShape.circle),
  );
}
