// What can be done to several tasks at once, in place of the add field while
// any are selected.
//
// In place of it rather than beside or over it, for two reasons. The add field
// is the one control at the top of the list that is always there, so a bar in
// its slot is where the eye already goes; and adding a task in the middle of
// moving five others is not a thing anybody does, so nothing is lost for the
// few seconds a selection lives.
//
// Park and move are one button, because they are one question - where does
// this belong - and move_picker.dart answers both in one menu. It hands its
// rect back so the shell can open that menu under the button that asked.

import 'package:flutter/material.dart';

import '../layout.dart';
import '../theme.dart';

class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.count,
    required this.accent,
    required this.onComplete,
    required this.onMove,
    required this.onDelete,
    required this.onClear,
  });

  final int count;
  final Color accent;
  final VoidCallback onComplete;
  final ValueChanged<RelativeRect> onMove;

  final VoidCallback onDelete;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final size = layout.touch ? 20.0 : 15.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s2, T.s1, T.s2, T.s1),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: T.s1),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(T.radius),
          border: Border.all(color: accent.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            _Button(
              icon: Icons.close_rounded,
              tooltip: 'Clear the selection (Esc)',
              size: size,
              onTap: (_) => onClear(),
            ),
            Expanded(
              child: Text(
                '$count selected',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: T.fsLabel,
                  fontWeight: T.wMedium,
                  color: T.text,
                ),
              ),
            ),
            _Button(
              icon: Icons.check_rounded,
              tooltip: 'Mark them done',
              size: size,
              onTap: (_) => onComplete(),
            ),
            _Button(
              icon: Icons.drive_file_move_outline,
              tooltip: 'Park or move them - a shelf, or another workspace',
              size: size,
              onTap: onMove,
            ),
            _Button(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Delete them',
              size: size,
              color: T.danger,
              onTap: (_) => onDelete(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.icon,
    required this.tooltip,
    required this.size,
    required this.onTap,
    this.color = T.muted,
  });

  final IconData icon;
  final String tooltip;
  final double size;
  final ValueChanged<RelativeRect> onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Tooltip(
      message: tooltip,
      child: Builder(
        builder: (context) => InkWell(
          borderRadius: BorderRadius.circular(T.radius),
          onTap: () => onTap(_anchor(context)),
          child: SizedBox(
            width: layout.tapTarget + 4,
            height: layout.tapTarget + 4,
            child: Icon(icon, size: size, color: color),
          ),
        ),
      ),
    );
  }

  /// The button's box as a menu position, in the overlay's space - the same
  /// reason task_actions.dart anchors that way: UiScale sits above the
  /// Navigator, so screen coordinates would land the menu in the wrong place
  /// on a phone.
  static RelativeRect _anchor(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return RelativeRect.fill;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final rect = topLeft & box.size;
    return RelativeRect.fromRect(
      Rect.fromLTWH(rect.left, rect.bottom, rect.width, 0),
      Offset.zero & overlay.size,
    );
  }
}
