// Two panes side by side with a boundary you can move, and a left pane you can
// fold away.
//
// Used wherever the task list sits beside something else - a view past
// [Layout.splitMinWidth], the calendar past [Layout.calendarSplitMinWidth].
// Both splits used to be fixed (5:4, and 340px beside the grid), which made a
// wide window a trade nobody had chosen: a note could not be given the width to
// be read in, and "just show me the notes" was not something a big window
// could do at all, because the list always came along.
//
// Three gestures on the boundary, all of them saying where it should be:
//
//   - **drag** moves it. The position is kept as a *fraction* of the width, so
//     resizing the window keeps the proportion that was chosen rather than a
//     pixel count that meant something at the old size.
//   - **drag it past the left edge** (below half the left pane's minimum) and
//     the left pane folds into [SplitPane.collapsedWidth] - one strip with one
//     control on it that brings the pane back. That is the "only the notes"
//     case, and it is remembered like the position is.
//   - **double-click** puts it back to the default.
//
// The chevron on the handle does the fold without the drag, which is the
// discoverable half.
//
// **The children keep their elements through all of it.** The row always has
// the same three slots with the same keys - the strip replaces the left pane's
// *content*, not its slot - so collapsing does not rebuild the right pane. A
// calendar that lost its scroll position every time the list beside it was
// folded would be punishing exactly the action that gives it room.

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../theme.dart';

class SplitPane extends StatefulWidget {
  const SplitPane({
    super.key,
    required this.left,
    required this.right,
    required this.fraction,
    required this.defaultLeft,
    required this.collapsed,
    required this.onFraction,
    required this.onCollapsed,
    this.minLeft = 260,
    this.minRight = 260,
    this.collapsedIcon = Icons.checklist_rounded,
    this.collapsedTooltip = 'Show the task list',
  });

  final Widget left;
  final Widget right;

  /// The left pane's share of the width, or null for [defaultLeft].
  final double? fraction;

  /// The left pane's width when nothing has been chosen, given the total.
  final double Function(double width) defaultLeft;

  final bool collapsed;

  /// A drag finished (the new fraction), or a double-click reset it (null).
  final ValueChanged<double?> onFraction;

  final ValueChanged<bool> onCollapsed;

  final double minLeft;
  final double minRight;

  final IconData collapsedIcon;
  final String collapsedTooltip;

  /// The folded left pane.
  static const collapsedWidth = 28.0;

  /// The grab area. Wider than the line drawn in it, because a 1px target is
  /// one nobody can hit.
  static const handleWidth = 9.0;

  @override
  State<SplitPane> createState() => _SplitPaneState();
}

class _SplitPaneState extends State<SplitPane> {
  /// The left width while a drag is in flight, unclamped so the collapse
  /// threshold can be crossed. Null the rest of the time.
  double? _dragging;

  bool _hovered = false;

  double _leftWidth(double total) {
    final wanted =
        _dragging ??
        (widget.fraction != null
            ? widget.fraction! * total
            : widget.defaultLeft(total));
    final max = total - widget.handleWidthAndRight;
    // A window too narrow for both minimums still has to draw something; the
    // left pane gives first, since the right is what was opened on purpose.
    if (max < widget.minLeft) return max.clamp(0, total);
    return wanted.clamp(widget.minLeft, max);
  }

  bool get _wouldCollapse =>
      _dragging != null && _dragging! < widget.minLeft / 2;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;
        final collapsed = widget.collapsed;
        final leftWidth = collapsed
            ? SplitPane.collapsedWidth
            : _leftWidth(total);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: const ValueKey('split-left'),
              width: leftWidth,
              child: collapsed
                  ? _CollapsedStrip(
                      icon: widget.collapsedIcon,
                      tooltip: widget.collapsedTooltip,
                      onTap: () => widget.onCollapsed(false),
                    )
                  : AnimatedOpacity(
                      // Says "let go here and it folds" before it happens.
                      opacity: _wouldCollapse ? 0.35 : 1,
                      duration: const Duration(milliseconds: 120),
                      child: widget.left,
                    ),
            ),
            SizedBox(
              key: const ValueKey('split-handle'),
              width: collapsed ? 1 : SplitPane.handleWidth,
              child: collapsed ? const _Line() : _handle(total, leftWidth),
            ),
            Expanded(key: const ValueKey('split-right'), child: widget.right),
          ],
        );
      },
    );
  }

  Widget _handle(double total, double leftWidth) {
    final active = _hovered || _dragging != null;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // From the press, not from where the drag was recognised: otherwise
        // the boundary trails the pointer by the gesture slop for the whole
        // drag and lands short of where it was let go.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (_) => setState(() => _dragging = leftWidth),
        onHorizontalDragUpdate: (d) =>
            setState(() => _dragging = (_dragging ?? leftWidth) + d.delta.dx),
        onHorizontalDragEnd: (_) {
          final collapse = _wouldCollapse;
          final width = _leftWidth(total);
          setState(() => _dragging = null);
          if (collapse) {
            widget.onCollapsed(true);
          } else if (total > 0) {
            widget.onFraction(width / total);
          }
        },
        onHorizontalDragCancel: () => setState(() => _dragging = null),
        onDoubleTap: () => widget.onFraction(null),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            _Line(highlight: active),
            // The fold, without having to know the drag does it too. Only
            // while the pointer is on the boundary: at rest a button on every
            // split would be a mark on the page for a control used rarely.
            if (_hovered && _dragging == null)
              Tooltip(
                message: 'Hide this pane (or drag the edge all the way left)',
                child: InkWell(
                  onTap: () => widget.onCollapsed(true),
                  borderRadius: BorderRadius.circular(T.radius),
                  child: Container(
                    width: SplitPane.handleWidth + 8,
                    height: 34,
                    decoration: BoxDecoration(
                      color: T.bgSolid,
                      borderRadius: BorderRadius.circular(T.radius),
                      border: Border.all(color: T.surfaceHover),
                    ),
                    child: const Icon(
                      Icons.chevron_left_rounded,
                      size: 14,
                      color: T.muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

extension on SplitPane {
  double get handleWidthAndRight => SplitPane.handleWidth + minRight;
}

class _Line extends StatelessWidget {
  const _Line({this.highlight = false});

  final bool highlight;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: highlight ? 2 : 1,
      color: highlight
          ? T.accent.withValues(alpha: 0.6)
          : const Color(0x14FFFFFF),
    ),
  );
}

/// The left pane, folded. One control, and it is the way back.
class _CollapsedStrip extends StatelessWidget {
  const _CollapsedStrip({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: T.s2),
          child: Column(
            children: [
              Icon(icon, size: 15, color: T.muted),
              const SizedBox(height: T.s1),
              const Icon(Icons.chevron_right_rounded, size: 14, color: T.muted),
            ],
          ),
        ),
      ),
    );
  }
}
