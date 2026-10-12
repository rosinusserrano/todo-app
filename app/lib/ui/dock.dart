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
}

class Dock extends StatefulWidget {
  const Dock({super.key, required this.segments, this.height = 48});

  final List<DockSegment> segments;
  final double height;

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
        final n = widget.segments.length;
        final at = (local.dx / (dock.size.width / n)).floor().clamp(0, n - 1);
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
          builder: (context, _) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < widget.segments.length; i++)
                Expanded(
                  child: Listener(
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
      ),
    );
  }

  Widget _segment(DockSegment seg, {required bool open}) {
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
    if (open) fill = Color.lerp(fill, Colors.white, 0.14)!;
    final ink = seg.dimmed ? seg.ink.withValues(alpha: 0.55) : seg.ink;

    return Semantics(
      button: true,
      label: seg.semanticLabel ?? seg.label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: fill,
        padding: const EdgeInsets.symmetric(horizontal: T.s2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (seg.icon != null) ...[
              Icon(seg.icon, size: 18, color: ink),
              const SizedBox(width: T.s1 + 2),
            ],
            Flexible(
              child: Text(
                seg.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: T.fsLabel,
                  fontWeight: T.wMedium,
                  color: ink,
                ),
              ),
            ),
            if (seg.count > 0) ...[
              const SizedBox(width: T.s1),
              Text(
                '${seg.count}',
                style: TextStyle(
                  fontSize: T.fsMeta,
                  color: ink.withValues(alpha: 0.75),
                ),
              ),
            ],
            if (seg.dot) ...[const SizedBox(width: T.s1), const _Dot()],
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
    final n = widget.segments.length;
    final segWidth = dockWidth / n;
    final width = math.min(dockWidth, math.max(segWidth, Dock.menuMinWidth));
    // Over its own segment where it fits, kept inside the bar where it does not:
    // the first menu grows from the left edge, the last from the right.
    final segLeft = segWidth * open;
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
    final ink = own == null ? T.text : _inkOn(own);
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
              Positioned.fill(
                child: Row(
                  children: [
                    // Where you are now: a short bar, not a box around the row.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: item.current ? 4 : 0,
                      height: 20,
                      color: ink,
                    ),
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

/// Dark ink on a light fill, light ink on a dark one. The workspace palette is
/// all pastels, but a workspace's colour is the user's to pick.
Color _inkOn(Color fill) => fill.computeLuminance() > 0.3 ? T.bgSolid : T.text;

/// Public for the shell, which fills the workspace segment with the same rule.
Color dockInkOn(Color fill) => _inkOn(fill);

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: const BoxDecoration(color: T.danger, shape: BoxShape.circle),
  );
}
