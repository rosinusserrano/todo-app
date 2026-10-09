// The three content views and the thought pile, as icons along the bottom
// edge. Wherever there is no rail (`Layout.hasViewBar`): it began touch-only,
// and the narrow desktop window got it too once the menu's cost - views you
// cannot see until you press something - turned out to be paid by a mouse as
// well.
//
// On a desktop these live behind the workspace bar's ▾ menu, and that is right
// there: they are opened occasionally, the window is 340px wide, and a menu
// costs one click that a mouse pays easily.
//
// A thumb does not. The menu is a small target at the top of the screen - the
// far end of the phone from the hand holding it - and it hides which views
// exist behind a press, so the answer to "where are my notes" is something you
// have to remember rather than something you can see. A bar of four along the
// bottom is where every phone application has put this for a decade, and the
// reason is the same each time: it is the part of the screen a thumb reaches
// without regripping.
//
// **Views only.** The workspace stays in the pill at the top, deliberately: it
// is a different question. This bar answers "which view of this workspace",
// the pill answers "which workspace" - and a bar that mixed the two would have
// its selection mean two things at once. That is also why Tasks is an entry
// here and not simply the state of having nothing selected: the way back has to
// be as visible as the way in.
//
// **Side thoughts are the fourth entry, and History gave up its place.** The
// pile used to be reached through a bubble floating over the list, opened by
// swiping the bubble up - a gesture on a small floating target that nothing on
// screen announced. Thoughts are written and emptied all day; History is looked
// back at occasionally, which is a settings-sheet kind of visit, so it moved
// there (desktop keeps it in the ▾ menu). Two things came with the move:
//
//   the pressure   the whole bar tints and pulses as the pile grows - the same
//                  escalation the desktop footer runs, on the same numbers
//                  (ThoughtPulse) - and the Thoughts entry carries the count.
//   writing one    a swipe **up** on the bar opens the capture pane. It is the
//                  commonest capture there is and the bar is where the thumb
//                  already rests, so it is one gesture with nothing to aim at.
//                  The bar lifts with the finger, which is how the gesture
//                  shows itself; and while the pile is open a line just above
//                  the bar says so in words, since that is the moment someone
//                  is looking at the thoughts and wondering how to add one.
//
// The swipe has to *start* on the bar. It sits inside the shell's SafeArea,
// above the iOS home indicator, and a swipe from the very bottom edge belongs
// to the system.

import 'package:flutter/material.dart';

import '../layout.dart';
import '../theme.dart';
import 'thought_pressure.dart';
import 'workspace_bar.dart' show WorkspaceView;

/// The views this bar offers, left to right. Also the order a swipe moves
/// through them - see `_swipeView` in main.dart, which reads this list so the
/// two navigations cannot disagree about what is next to what.
///
/// Null is Tasks. It is first because it is the one you return to.
const kBarViews = <WorkspaceView?>[
  null,
  WorkspaceView.notes,
  WorkspaceView.parked,
  WorkspaceView.thoughts,
];

class ViewBar extends StatefulWidget {
  const ViewBar({
    super.key,
    required this.accent,
    required this.openView,
    required this.onSelect,
    required this.parkedReviewDue,
    this.thoughtCount = 0,
    this.onSwipeUp,
  });

  final Color accent;

  /// Null while the task list is showing.
  final WorkspaceView? openView;

  final ValueChanged<WorkspaceView?> onSelect;

  /// A parked group has gone past its review interval. The dot is the only
  /// thing that says so while the panel is closed.
  final bool parkedReviewDue;

  /// How many side thoughts are waiting. Drives the Thoughts entry's count and
  /// the bar's tint and pulse.
  final int thoughtCount;

  /// A swipe up on the bar: write a thought. Null switches the gesture off.
  final VoidCallback? onSwipeUp;

  /// How far the bar can be pulled up, and how far is far enough to mean it.
  static const _lift = 28.0;
  static const _commit = 18.0;

  static const swipeHint = 'Slide up to add a thought';

  static const _icons = {
    null: (Icons.check_circle_outline_rounded, 'Tasks'),
    WorkspaceView.notes: (Icons.notes_rounded, 'Notes'),
    WorkspaceView.parked: (Icons.inbox_rounded, 'Parked'),
    WorkspaceView.thoughts: (Icons.cloud_outlined, 'Thoughts'),
  };

  @override
  State<ViewBar> createState() => _ViewBarState();
}

class _ViewBarState extends State<ViewBar> with SingleTickerProviderStateMixin {
  late final ThoughtPulse _pulse = ThoughtPulse(this);

  /// How far the finger has pulled the bar up, in points.
  double _pulled = 0;

  @override
  void initState() {
    super.initState();
    _pulse.sync(widget.thoughtCount);
  }

  @override
  void didUpdateWidget(ViewBar old) {
    super.didUpdateWidget(old);
    if (old.thoughtCount != widget.thoughtCount) {
      _pulse.sync(widget.thoughtCount);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _dragUpdate(DragUpdateDetails d) {
    setState(() {
      _pulled = (_pulled - d.delta.dy).clamp(0.0, ViewBar._lift);
    });
  }

  void _dragEnd(DragEndDetails d) {
    final flung = (d.primaryVelocity ?? 0) < -400;
    final far = _pulled >= ViewBar._commit;
    setState(() => _pulled = 0);
    if (flung || far) widget.onSwipeUp?.call();
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final count = widget.thoughtCount;
    final alarm = T.complementary(widget.accent);
    final hot = ThoughtPulse.intensityOf(count);
    final swipe = widget.onSwipeUp != null;

    final row = Row(
      children: [
        for (final view in kBarViews)
          Expanded(
            child: _Entry(
              icon: ViewBar._icons[view]!.$1,
              label: ViewBar._icons[view]!.$2,
              selected: widget.openView == view,
              // The pile is global, so its entry is lit in the thoughts'
              // own colour rather than this workspace's.
              accent: view == WorkspaceView.thoughts ? T.thoughts : widget.accent,
              height: layout.tapTarget,
              // Only on Parked, and only while something is actually due.
              dot: view == WorkspaceView.parked && widget.parkedReviewDue,
              count: view == WorkspaceView.thoughts ? count : 0,
              countColor: Color.lerp(T.muted, alarm, hot)!,
              onTap: () => widget.onSelect(view),
            ),
          ),
      ],
    );

    final bar = AnimatedBuilder(
      animation: _pulse.controller,
      builder: (context, child) {
        final glow = Curves.easeInOut.transform(_pulse.controller.value);
        return Container(
          decoration: BoxDecoration(
            // A hairline rather than a filled bar while the pile is empty: the
            // shell is translucent and a solid strip along the bottom would
            // read as a second window. It fills in only as the pile grows.
            color: alarm.withValues(alpha: hot * 0.22),
            border: Border(
              top: BorderSide(
                color: count == 0
                    ? T.text.withValues(alpha: 0.08)
                    : alarm.withValues(alpha: hot * 0.55),
              ),
            ),
            boxShadow: [
              if (ThoughtPulse.pulsingAt(count))
                BoxShadow(
                  color: alarm.withValues(alpha: glow * hot * 0.95),
                  blurRadius: 18,
                  offset: const Offset(0, -3),
                ),
            ],
          ),
          child: child,
        );
      },
      child: row,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (swipe && widget.openView == WorkspaceView.thoughts)
          const Padding(
            padding: EdgeInsets.only(bottom: T.s1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.keyboard_arrow_up_rounded, size: 16, color: T.muted),
                SizedBox(width: T.s1),
                Text(
                  ViewBar.swipeHint,
                  style: TextStyle(fontSize: T.fsMeta, color: T.muted),
                ),
              ],
            ),
          ),
        GestureDetector(
          // Vertical only, and only once the finger has moved past the slop:
          // a tap on an entry is still a tap.
          onVerticalDragUpdate: swipe ? _dragUpdate : null,
          onVerticalDragEnd: swipe ? _dragEnd : null,
          onVerticalDragCancel: swipe ? () => setState(() => _pulled = 0) : null,
          child: Transform.translate(offset: Offset(0, -_pulled), child: bar),
        ),
      ],
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.height,
    required this.dot,
    required this.onTap,
    this.count = 0,
    this.countColor = T.muted,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final double height;
  final bool dot;
  final VoidCallback onTap;

  /// A number beside the icon, for the thought pile. Zero draws nothing.
  final int count;
  final Color countColor;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : T.muted;

    return Semantics(
      label: count > 0 ? '$label, $count waiting' : label,
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 19, color: color),
                  if (dot)
                    Positioned(
                      right: -2,
                      top: -1,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: T.danger,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  if (count > 0)
                    Positioned(
                      left: 21,
                      top: -3,
                      child: ExcludeSemantics(
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: T.fsMeta,
                            height: 1,
                            fontWeight: T.wMedium,
                            color: countColor,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              // The label is small and always there rather than shown only for
              // the selected entry: four unlabelled glyphs is a guessing game,
              // and a label that appears only when selected is one you can
              // never read before choosing.
              Text(
                label,
                style: TextStyle(
                  fontSize: 8.5,
                  height: 1,
                  color: color,
                  fontWeight: selected ? T.wMedium : T.wNormal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
