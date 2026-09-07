// A task, read rather than edited.
//
// The composer has always been able to *show* notes rendered, but it is a form:
// it opens with fields, a Save and a Cancel, and reading a checked list of
// steps in it means being one stray keystroke away from editing them. This is
// the other half - everything the row is carrying, laid out to be read and
// nothing else. No controls, no text fields, no way to change anything.
//
// It is the same widget at both sizes, and only its frame differs:
//
//   - Under a pointer the row grows in place ([TaskDetail] on its own, below
//     the title), so the tasks above and below stay where they were and the
//     list still scrolls past them.
//   - On a phone it takes the content area ([TaskDetailScreen]), the way an
//     open journal entry does, because the chrome around a 390pt screen is most
//     of the height a paragraph of notes needs. The way out is the header's
//     back arrow, which is the control the eye is already on.
//
// The meta line is chips rather than a table because it is a *sparse* set: a
// task usually carries one or two of these and a table would be five empty
// rows with one filled. Everything in it is state the row can only hint at in
// an icon, spelled out - "Reminder tomorrow 09:00" rather than a bell.

import 'package:flutter/material.dart';

import '../sync/models.dart';
import '../theme.dart';
import 'markdown_text.dart';
import 'panel_header.dart';
import 'reminder_menu.dart';

/// The read-only body: the meta chips, then the notes.
///
/// [showTitle] is false where the thing that opened this is already showing the
/// title - which is the row, whose own text is directly above.
class TaskDetail extends StatelessWidget {
  const TaskDetail({
    super.key,
    required this.task,
    required this.accent,
    this.attachmentCount = 0,
    this.showTitle = false,
  });

  final Task task;
  final Color accent;
  final int attachmentCount;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final armed = task.remindAtTime;
    final due = task.isDue();

    final chips = <Widget>[
      if (task.isHighPriority)
        const _Chip(
          icon: Icons.flag_rounded,
          label: 'High priority',
          color: T.flagged,
        ),
      if (armed != null)
        _Chip(
          icon: due
              ? Icons.notification_important_rounded
              : Icons.notifications_active_rounded,
          label: 'Reminder ${describeReminder(armed)}',
          color: due ? T.warn : accent,
        ),
      if (task.recur != null)
        _Chip(
          icon: Icons.repeat_rounded,
          label: Recur.label(task.recur!),
          color: accent,
        ),
      if (task.inProgress)
        _Chip(
          icon: Icons.play_arrow_rounded,
          label: 'Being worked on',
          color: accent,
        ),
      if (task.isPlanned)
        _Chip(
          icon: Icons.event_available_rounded,
          label: 'Planned into a block',
          color: accent,
        ),
      if (attachmentCount > 0)
        _Chip(
          icon: Icons.attach_file_rounded,
          label: attachmentCount == 1 ? '1 document' : '$attachmentCount documents',
          color: accent,
        ),
      _Chip(
        icon: Icons.schedule_rounded,
        label: 'Added ${_when(task.createdAt)}',
        color: T.muted,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTitle) ...[
          Text(
            task.text,
            style: const TextStyle(
              fontSize: T.fsMenu,
              height: 1.3,
              color: T.text,
              fontWeight: T.wMedium,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(spacing: 6, runSpacing: 4, children: chips),
        const SizedBox(height: 8),
        if (task.hasNotes)
          // The point of the whole view: the notes as they were written, with
          // the headings, lists and maths actually rendered, at a size meant
          // for reading rather than for a one-line preview.
          MarkdownText(
            task.notes,
            style: const TextStyle(fontSize: T.fsBody, color: T.text, height: 1.45),
          )
        else
          const Text(
            'No notes on this one.',
            style: TextStyle(fontSize: T.fsLabel, color: T.muted, height: 1.35),
          ),
      ],
    );
  }

  /// "3 Sep 2026". Deliberately not the time: the exact minute a task was
  /// captured has never answered anything, and the date is what places it.
  static String _when(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return 'some time ago';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

/// The same body with the content area to itself: a header that collapses it,
/// and a scroll, because notes are as long as they are.
class TaskDetailScreen extends StatelessWidget {
  const TaskDetailScreen({
    super.key,
    required this.task,
    required this.accent,
    required this.onCollapse,
    this.attachmentCount = 0,
  });

  final Task task;
  final Color accent;
  final VoidCallback onCollapse;
  final int attachmentCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelHeader(
          title: 'Task',
          onBack: onCollapse,
          backTooltip: 'Collapse (Esc)',
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(T.s3, 0, T.s3, T.s4),
            child: TaskDetail(
              task: task,
              accent: accent,
              attachmentCount: attachmentCount,
              showTitle: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: T.s2, vertical: 3),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: T.fsMeta, color: color)),
        ],
      ),
    );
  }
}
