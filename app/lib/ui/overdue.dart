// Overdue: a task whose reminder has gone off and that is still open.
//
// The row itself already says so (warn-tinted, the bell turns to a "!"), but
// only on that workspace's own list - and a reminder swiped away on a day
// off is then on a list nobody opens until it is too late (Marco,
// 2026-11-24, "uploading the solutions for the tutorial"). So it is said
// *across* workspaces as well, in the places that name a workspace:
//
//   - the dock's workspace segment **blinks** while anything anywhere is
//     overdue - the thought pile's pulse on More is the model, in warn
//     rather than the thoughts' colour (dock.dart, [DockSegment.alert]);
//   - the workspace menu's rows, the home squares and a project's row carry
//     an [OverdueMark] with the count.
//
// It stops when the reminder is cleared or moved, or the task is ticked:
// the reminder *is* the overdue state, there is no "seen" to store. Warn,
// not danger: T.warn is "attention that costs nothing", and an overdue
// reminder is the example the token was written for.

import 'package:flutter/material.dart';

import '../theme.dart';

/// How long one blink takes, there and back - the dock's and the marks', so
/// everything saying "overdue" on screen at once says it in step.
const kOverdueBlink = Duration(milliseconds: 1100);

/// A blinking warn dot, with the count beside it when there is room for one.
class OverdueMark extends StatefulWidget {
  const OverdueMark({
    super.key,
    required this.count,
    this.label = false,
    this.ink,
  });

  final int count;

  /// "2 overdue" rather than a bare "2".
  final bool label;

  /// The count's colour - the ink of whatever the mark sits on. Null draws
  /// the dot alone.
  final Color? ink;

  @override
  State<OverdueMark> createState() => _OverdueMarkState();
}

class _OverdueMarkState extends State<OverdueMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: kOverdueBlink,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = widget.ink;
    return Semantics(
      label: '${widget.count} overdue',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween(
              begin: 1.0,
              end: 0.25,
            ).animate(CurvedAnimation(parent: _blink, curve: Curves.easeInOut)),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: T.warn,
                shape: BoxShape.circle,
                // A ring, so the dot reads on a workspace whose own colour
                // is near warn.
                border: Border.all(color: T.bgSolid, width: 1.5),
              ),
            ),
          ),
          if (ink != null) ...[
            const SizedBox(width: 4),
            Text(
              widget.label ? '${widget.count} overdue' : '${widget.count}',
              style: TextStyle(
                fontFamily: T.fontDisplay,
                fontSize: T.fsMeta,
                fontWeight: T.wMedium,
                color: ink,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
