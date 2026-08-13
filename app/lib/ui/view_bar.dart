// The four content views, as icons along the bottom edge. Touch only.
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
// Side thoughts are not here either. The pile is global rather than
// per-workspace and its way in is the count on the footer directly below, which
// is where the pressure is already shown; a second door to it in the bar above
// would be two controls for one pile, one of which says how full it is.

import 'package:flutter/material.dart';

import '../layout.dart';
import '../theme.dart';
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
  WorkspaceView.history,
];

class ViewBar extends StatelessWidget {
  const ViewBar({
    super.key,
    required this.accent,
    required this.openView,
    required this.onSelect,
    required this.parkedReviewDue,
  });

  final Color accent;

  /// Null while the task list is showing.
  final WorkspaceView? openView;

  final ValueChanged<WorkspaceView?> onSelect;

  /// A parked group has gone past its review interval. The dot is the only
  /// thing that says so while the panel is closed.
  final bool parkedReviewDue;

  static const _icons = {
    null: (Icons.check_circle_outline_rounded, 'Tasks'),
    WorkspaceView.notes: (Icons.notes_rounded, 'Notes'),
    WorkspaceView.parked: (Icons.inbox_rounded, 'Parked'),
    WorkspaceView.history: (Icons.history_rounded, 'History'),
  };

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);

    return Container(
      decoration: BoxDecoration(
        // A hairline rather than a filled bar: the shell is translucent and a
        // solid strip along the bottom would read as a second window.
        border: Border(
          top: BorderSide(color: T.text.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          for (final view in kBarViews)
            Expanded(
              child: _Entry(
                icon: _icons[view]!.$1,
                label: _icons[view]!.$2,
                selected: openView == view,
                accent: accent,
                height: layout.tapTarget,
                // Only on Parked, and only while something is actually due.
                dot: view == WorkspaceView.parked && parkedReviewDue,
                onTap: () => onSelect(view),
              ),
            ),
        ],
      ),
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
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final double height;
  final bool dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : T.muted;

    return Semantics(
      label: label,
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
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
