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
    required this.onBack,
    this.actions = const [],
  });

  final String title;

  /// Back to the task list. Esc does the same thing, and the tooltip says so -
  /// the shortcut should not have to be discovered separately.
  final VoidCallback onBack;

  /// Trailing controls belonging to the view itself (new group, new note).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Tighter on the left than the old plain label, so the arrow starts where
      // the text used to and the title lands just right of it.
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      child: Row(
        children: [
          Tooltip(
            message: 'Back to tasks (Esc)',
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.arrow_back_rounded,
                      size: 13,
                      color: T.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        color: T.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}
