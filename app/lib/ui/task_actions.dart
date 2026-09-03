// A task's actions, as an overlay that is asked for rather than a bar the row
// carries.
//
// **What this replaces, and why.** The row used to draw its actions inline, in
// two shapes: hover-revealed icons at the right-hand end under a pointer, and
// an always-visible bar of fingertips below the title on touch. Both were
// paying for the actions with the row's own width, all the time, for the one
// second in a hundred anybody wanted them:
//
//   - On desktop the icons were invisible at rest but **still in the layout**
//     (that was deliberate - revealing them must not reflow the text), so in a
//     narrow window most of the row's horizontal space belonged to controls
//     that were not on screen. The title got what was left.
//   - On touch the bar was a second line under every row, on the screen with
//     the least of it, and it wrapped to a *third* line on a task that asked
//     for everything.
//
// So the actions moved off the row and into a floating bar, opened by the one
// gesture each pointer has spare: **right-click** with a mouse, a **short tap
// on the text** with a finger. The row goes back to being a tick box and a
// title at every width, and the actions are drawn at whatever size the pointer
// needs because they are no longer competing with the text for room.
//
// It is an icon bar and not a menu of labelled rows on purpose: it is the same
// set of controls that used to be in the row, in the same order, so the muscle
// memory built on the old bar still points at the right glyph.
//
// Two things about the anchoring:
//
//   - The anchor is a rect **in the overlay's coordinate space**, not the
//     screen's. `UiScale` sits above the Navigator, so everything below it -
//     this route included - lays out in layout units while `localToGlobal`
//     with no ancestor reports scaled screen pixels. Anchoring on the latter
//     would put the bar a fifth of the way down the screen from the row on a
//     phone. `taskActionAnchor` is the one place that conversion happens.
//   - The bar is placed by a [SingleChildLayoutDelegate] rather than a
//     `Positioned`, because where it goes depends on how big it turns out to
//     be - the item list is built per row and a `Wrap` decides its own line
//     count - and a delegate is handed the child's size.

import 'package:flutter/material.dart';

import '../layout.dart';
import '../theme.dart';

/// Everything the bar can offer. The row decides which of these it hands over;
/// an action whose callback is null is simply not in the list.
enum TaskAction {
  remind,
  priority,
  attach,
  unplan,
  park,
  focus,
  expand,
  edit,
  delete,
}

/// One button: what it does, and how it is drawn for *this* task. The colour
/// and the label are state-dependent (an armed bell is accented, a flagged task
/// shows a filled flag), which is why the row builds these rather than the bar
/// deriving them from the enum.
@immutable
class TaskActionItem {
  const TaskActionItem({
    required this.action,
    required this.icon,
    required this.label,
    this.color = T.muted,
  });

  final TaskAction action;
  final IconData icon;

  /// The tooltip under a pointer and the semantic label everywhere. One string
  /// rather than two: a fingertip gets no tooltip (a long press belongs to
  /// reordering), so the label would otherwise only ever be read aloud.
  final String label;

  final Color color;
}

/// Where a bar opened for [key]'s widget should point, in the overlay's space.
///
/// [at] is a pointer position in *global* coordinates - a right-click - and
/// wins when it is given; otherwise the anchor is the whole widget's box, which
/// is what a tap on a row wants.
Rect? taskActionAnchor(
  BuildContext context, {
  GlobalKey? key,
  Offset? at,
}) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return null;

  if (at != null) {
    final local = overlay.globalToLocal(at);
    return Rect.fromLTWH(local.dx, local.dy, 0, 0);
  }

  final box = key?.currentContext?.findRenderObject() as RenderBox?;
  if (box == null) return null;
  return box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
}

/// Opens the bar and resolves to the action pressed, or null if it was
/// dismissed. The caller runs the action: the bar knows nothing about tasks.
Future<TaskAction?> showTaskActions(
  BuildContext context, {
  required Rect anchor,
  required List<TaskActionItem> items,
  required Layout layout,
}) {
  return showGeneralDialog<TaskAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    // Transparent, unlike a form sheet's: this is a popup over a row you can
    // still see, and dimming the list to open a toolbar for one line of it
    // would read as a modal dialog rather than as a menu.
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (context, _, _) => CustomSingleChildLayout(
      delegate: _NearAnchor(anchor),
      child: _ActionsBar(items: items, layout: layout),
    ),
    transitionBuilder: (context, anim, _, child) => FadeTransition(
      opacity: anim,
      child: Transform.scale(
        scale: 0.94 + 0.06 * T.sheetEase.transform(anim.value),
        alignment: Alignment.topLeft,
        child: child,
      ),
    ),
  );
}

/// Below the anchor if it fits, above it if not, and never off an edge.
class _NearAnchor extends SingleChildLayoutDelegate {
  const _NearAnchor(this.anchor);

  final Rect anchor;

  /// The gap between the bar and the thing it belongs to, and the margin it
  /// keeps from the window's edges.
  static const _gap = 6.0;
  static const _margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          (constraints.maxWidth - _margin * 2).clamp(0.0, constraints.maxWidth),
          constraints.maxHeight,
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = anchor.left;
    if (x + childSize.width > size.width - _margin) {
      x = size.width - _margin - childSize.width;
    }
    if (x < _margin) x = _margin;

    var y = anchor.bottom + _gap;
    if (y + childSize.height > size.height - _margin) {
      final above = anchor.top - _gap - childSize.height;
      // Above the row if there is room for it there; otherwise pinned to the
      // bottom edge, which covers part of the row but keeps every button on
      // screen. A bar half off the bottom is a bar with a missing delete.
      y = above >= _margin
          ? above
          : (size.height - _margin - childSize.height).clamp(_margin, size.height);
    }

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_NearAnchor oldDelegate) => oldDelegate.anchor != anchor;
}

class _ActionsBar extends StatelessWidget {
  const _ActionsBar({required this.items, required this.layout});

  final List<TaskActionItem> items;
  final Layout layout;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: T.bgSolid,
      elevation: 10,
      shadowColor: const Color(0x88000000),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x1FFFFFFF)),
        ),
        padding: const EdgeInsets.all(4),
        // Wraps rather than shrinking, for the reason the touch bar used to:
        // nine fingertips is wider than a phone, and a tap target below a
        // fingertip is an action the phone does not really have.
        child: Wrap(
          children: [
            for (final item in items)
              _ActionButton(item: item, layout: layout),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.item, required this.layout});

  final TaskActionItem item;
  final Layout layout;

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      label: item.label,
      button: true,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(item.action),
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: layout.tapTarget,
          height: layout.tapTarget,
          child: Icon(item.icon, size: layout.actionIcon, color: item.color),
        ),
      ),
    );

    // No tooltip on touch: it needs a hover or a long press, and neither is
    // available here - the long press over the list is how a row is picked up
    // to be reordered.
    if (layout.touch) return button;
    return Tooltip(message: item.label, child: button);
  }
}
