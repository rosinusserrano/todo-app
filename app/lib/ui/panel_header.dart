// The strip at the top of a content view - Notes, Parked, History - and the way
// back out of it.
//
// This label used to be plain text, which left those three views with no visible
// exit: Esc worked, and re-picking the item in the ▾ views menu closed it, but
// nothing on screen said either of those things. Making the label itself the
// back control puts the way out exactly where the eye already is - on the thing
// that says which view you are in - and costs no extra row on a 340px window.
//
// Deliberately *not* the workspace tab: that is the edit control, and it answers
// "which workspace", not "which view".

import 'package:flutter/material.dart';

import '../theme.dart';

class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const [],
    this.count,
    this.color = T.text,
    this.backTooltip = 'Back to tasks (Esc)',
  });

  final String title;

  /// Back to the task list. Esc does the same thing, and the tooltip says so -
  /// the shortcut should not have to be discovered separately. Null for a view
  /// with no "back" of its own (the thought pile is left through the dock).
  final VoidCallback? onBack;

  /// What Esc and the arrow actually do here. Overridden where this bar is one
  /// rung of a ladder rather than the way out of a view - the journal's reader
  /// backs out to its own list, and saying "back to tasks" there would be
  /// wrong about both the arrow and the key.
  final String backTooltip;

  /// Trailing controls belonging to the view itself (new group, new note).
  final List<Widget> actions;

  /// How many things the view holds, set beside the title in the same size
  /// and a quieter colour - "Parked 4" - rather than as a badge. Null draws
  /// nothing.
  final int? count;

  /// The title's colour. A workspace's list is titled in the workspace's.
  final Color color;

  @override
  Widget build(BuildContext context) {
    // The title is set large: it is the one thing on screen that says where
    // you are, and at the size of the rows under it it read as one more row.
    // Its left edge is the content's (T.s4), so the title and the list under
    // it start on one line.
    final heading = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (onBack != null) ...[
          const Icon(Icons.arrow_back_rounded, size: 18, color: T.muted),
          const SizedBox(width: T.s2),
        ],
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: T.fsTitle,
              fontFamily: T.fontDisplay,
              color: color,
              fontWeight: T.wMedium,
              height: 1.2,
            ),
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: T.s2),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: T.fsTitle,
              fontFamily: T.fontDisplay,
              color: T.muted,
              fontWeight: T.wNormal,
              height: 1.2,
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s4 - T.s1, T.s1, T.s2, T.s3),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: onBack == null
                  ? Padding(padding: const EdgeInsets.all(T.s1), child: heading)
                  : Tooltip(
                      message: backTooltip,
                      child: InkWell(
                        onTap: onBack,
                        borderRadius: BorderRadius.circular(T.radius),
                        child: Padding(
                          padding: const EdgeInsets.all(T.s1),
                          child: heading,
                        ),
                      ),
                    ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
