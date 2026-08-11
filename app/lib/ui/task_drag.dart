// Dragging a task out of the list onto something beside it.
//
// There are two such targets now - a calendar block ("do this then") and a
// parked group ("not now") - and they are the same gesture with the same
// feedback, so the target lives here rather than in either of them. It started
// out in `calendar/time_grid.dart`; a parked panel importing the calendar to
// get at a drop target would have been the wrong shape of dependency.
//
// The drag *source* is still in main.dart, because whether a row can be dragged
// at all is a question about the layout - there has to be something beside the
// list to drop onto - and the shell is what knows the layout.

import 'package:flutter/material.dart';

import '../sync/models.dart';
import '../theme.dart';

/// Accepts a task dragged out of the list beside it, and says so while it is
/// over the target.
///
/// The highlight is the whole feedback: a drop changes a count somewhere and
/// nothing else, which is too quiet to be the only thing that happens when you
/// let go of something.
class TaskDropTarget extends StatelessWidget {
  const TaskDropTarget({
    super.key,
    required this.onDrop,
    required this.color,
    required this.child,
    this.radius = 5,
  });

  /// Null makes this the child and nothing more - which is how a target that
  /// has no list beside it to be dragged from simply does not exist.
  final void Function(Task)? onDrop;
  final Color color;
  final Widget child;

  /// Matched to whatever is being outlined: a calendar blob is 5, a parked
  /// group's card is 9. A halo that does not follow the corner it is drawn
  /// around reads as a rendering bug rather than as a target.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final drop = onDrop;
    if (drop == null) return child;

    return DragTarget<Task>(
      onAcceptWithDetails: (d) => drop(d.data),
      builder: (context, candidates, _) {
        if (candidates.isEmpty) return child;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: color, width: 1.5),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 8),
            ],
          ),
          child: child,
        );
      },
    );
  }
}

/// What follows the pointer during such a drag: the task's own title, small, in
/// the workspace colour. A ghost of the whole row would be 340px of widget
/// dragged across the thing it is about to cover.
class TaskDragFeedback extends StatelessWidget {
  const TaskDragFeedback({super.key, required this.task, required this.accent});

  final Task task;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        margin: const EdgeInsets.only(left: 10, top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Color.lerp(T.bgSolid, accent, 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.7)),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 12),
          ],
        ),
        child: Text(
          task.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: T.text),
        ),
      ),
    );
  }
}
