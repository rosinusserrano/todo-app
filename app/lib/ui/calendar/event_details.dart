// What a click on a calendar entry opens.
//
// A click used to open the edit form, which is the wrong default: most of the
// time you click a block to *find out* something - when it ends, what is in it,
// whether the file you attached is on it - and a form full of live fields is a
// poor way to read, as well as one stray keystroke away from changing what you
// only meant to look at.
//
// So a click reads and the ways to write are named: Edit, Plan todos, Delete,
// on this card and in the right-click / long-press menu that offers the same
// four things without opening anything first.
//
// It stays a *dialog* rather than a sheet, unlike Settings and the sublist: it
// is a glance that is gone in seconds, which is exactly the case the sheet rule
// in main.dart carves out. Nothing here takes typing, so there is no state to
// lose to the barrier.

import 'package:flutter/material.dart';

import '../../sync/models.dart';
import '../../theme.dart';
import '../markdown_text.dart';
import 'time_grid.dart' show hhmm;

/// What the user asked for on the way out. Null (the dialog dismissed) is
/// "nothing", which is the common case for a view whose job is to be read.
enum EventAction { edit, plan, delete }

Future<EventAction?> showEventDetails(
  BuildContext context, {
  required CalendarEvent event,
  required String calendarName,
  required Color color,
  required Future<List<Task>> Function() loadTasks,
  required Future<List<Attachment>> Function() loadAttachments,
}) {
  return showDialog<EventAction>(
    context: context,
    builder: (context) => _DetailsDialog(
      event: event,
      calendarName: calendarName,
      color: color,
      loadTasks: loadTasks,
      loadAttachments: loadAttachments,
    ),
  );
}

/// "10 min before", and the two states that are not a lead time at all.
String describeNotify(int? minutes) {
  if (minutes == null) return 'Calendar default';
  if (minutes == CalendarEvent.notifySilent) return 'None';
  if (minutes == 0) return 'At the start';
  if (minutes % 1440 == 0) {
    final days = minutes ~/ 1440;
    return days == 1 ? '1 day before' : '$days days before';
  }
  if (minutes % 60 == 0) {
    final hours = minutes ~/ 60;
    return hours == 1 ? '1 hour before' : '$hours hours before';
  }
  return '$minutes min before';
}

/// How long the block runs - "1 h 30 min". Shown beside the span because the
/// length is the thing you are usually working out from it.
String describeLength(Duration d) {
  final minutes = d.inMinutes;
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours >= 24) {
    final days = hours ~/ 24;
    final leftover = hours % 24;
    return leftover == 0 ? '$days d' : '$days d $leftover h';
  }
  return rest == 0 ? '$hours h' : '$hours h $rest min';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _day(DateTime d) => '${d.day} ${_months[d.month - 1]}';

class _DetailsDialog extends StatefulWidget {
  const _DetailsDialog({
    required this.event,
    required this.calendarName,
    required this.color,
    required this.loadTasks,
    required this.loadAttachments,
  });

  final CalendarEvent event;
  final String calendarName;
  final Color color;
  final Future<List<Task>> Function() loadTasks;
  final Future<List<Attachment>> Function() loadAttachments;

  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  List<Task>? _tasks;
  List<Attachment>? _attachments;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tasks = await widget.loadTasks();
    final attachments = await widget.loadAttachments();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _attachments = attachments;
    });
  }

  /// "5 Aug · 09:00 – 11:00", or both dates when the block crosses midnight.
  ///
  /// A whole day is named by its days and nothing else, and its *last* day is
  /// the one before the stored end - that end is exclusive, so printing it
  /// would add a day to every all-day event on this card.
  String get _when {
    final e = widget.event;
    final from = e.start;
    final to = e.end;
    if (e.allDay) {
      final last = to.subtract(const Duration(days: 1));
      final oneDay = last.year == from.year &&
          last.month == from.month &&
          last.day == from.day;
      return oneDay
          ? '${_day(from)} · all day'
          : '${_day(from)} – ${_day(last)} · all day';
    }
    final sameDay =
        from.year == to.year && from.month == to.month && from.day == to.day;
    if (sameDay) {
      return '${_day(from)} · ${hhmm(from)} – ${hhmm(to)}';
    }
    return '${_day(from)} ${hhmm(from)} – ${_day(to)} ${hhmm(to)}';
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final tasks = _tasks;
    final attachments = _attachments;

    return AlertDialog(
      backgroundColor: T.bgSolid,
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The calendar's colour, said the same way the block on the grid says
          // it: a bar down the leading edge.
          Container(
            width: 3,
            height: 30,
            margin: const EdgeInsets.only(right: 9, top: 1),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  style: const TextStyle(fontSize: 15, height: 1.2),
                ),
                if (widget.calendarName.isNotEmpty)
                  Text(
                    widget.calendarName,
                    style: const TextStyle(fontSize: 11, color: T.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Line(
                icon: Icons.schedule_rounded,
                text: '$_when  ·  ${describeLength(e.end.difference(e.start))}',
              ),
              _Line(
                icon: Icons.notifications_none_rounded,
                text: describeNotify(e.notifyMinutes),
              ),
              // Only when it repeats. "Once" on every other block would be a
              // line of noise on the card that exists to answer questions.
              if (e.repeats)
                _Line(
                  icon: Icons.repeat_rounded,
                  text: Recur.label(e.recur!),
                ),
              if (e.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                // Markdown, like a task's notes. This card is already the
                // read-only half of the read/write split described above, so
                // there is no editor to toggle into - Edit is one of the four
                // named ways out.
                MarkdownText(
                  e.description,
                  style: const TextStyle(
                      fontSize: 12.5, color: T.text, height: 1.35),
                ),
              ],
              const SizedBox(height: 12),
              _Section(
                label: 'Todos in this block',
                // Null is still loading; the two are different states and
                // showing "none" while a query is in flight would be a lie
                // that arrives a frame before the truth.
                empty: tasks != null && tasks.isEmpty,
                emptyText: 'Nothing planned yet.',
                loading: tasks == null,
                children: [
                  for (final t in tasks ?? const <Task>[])
                    _Bullet(icon: Icons.check_box_outline_blank, text: t.text),
                ],
              ),
              if (attachments == null || attachments.isNotEmpty) ...[
                const SizedBox(height: 10),
                _Section(
                  label: 'Attachments',
                  empty: false,
                  emptyText: '',
                  loading: attachments == null,
                  children: [
                    for (final a in attachments ?? const <Attachment>[])
                      _Bullet(icon: Icons.attach_file, text: a.filename),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(10, 0, 12, 10),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, EventAction.delete),
          child: const Text('Delete',
              style: TextStyle(color: T.danger, fontSize: 12.5)),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.pop(context, EventAction.plan),
          child: const Text('Todos', style: TextStyle(fontSize: 12.5)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, EventAction.edit),
          child: const Text('Edit', style: TextStyle(fontSize: 12.5)),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: T.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: T.text, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.empty,
    required this.emptyText,
    required this.loading,
    required this.children,
  });

  final String label;
  final bool empty;
  final String emptyText;
  final bool loading;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: T.muted)),
        const SizedBox(height: 4),
        if (loading)
          const Text('…', style: TextStyle(fontSize: 11.5, color: T.muted))
        else if (empty)
          Text(emptyText,
              style: const TextStyle(fontSize: 11.5, color: T.muted))
        else
          ...children,
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: T.muted),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: T.text),
            ),
          ),
        ],
      ),
    );
  }
}
