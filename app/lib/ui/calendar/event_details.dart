// What a click on a calendar entry opens.
//
// A click used to open the edit form, which is the wrong default: most of the
// time you click a block to *find out* something - when it ends, what is in it,
// whether the file you attached is on it - and a form full of live fields is a
// poor way to read, as well as one stray keystroke away from changing what you
// only meant to look at.
//
// So a click reads and the ways to write are named: Edit and Delete, on this
// card and in the right-click / long-press menu that offers the same things
// without opening anything first.
//
// It stays a modal *route* rather than a sheet in the shell's Stack, unlike
// Settings and the sound sheet: it is a glance that is gone in seconds, which is
// exactly the case the sheet rule in main.dart carves out. Nothing here takes
// typing, so there is no state to lose to the barrier.
//
// It is drawn on the same panel as the two forms (form_sheet.dart) rather than
// as an `AlertDialog`, and that is not only for the look. As a dialog its
// named actions went into Material's `OverflowBar` with a `Spacer` between
// them, which on a phone gave the title, Delete, and then a tall empty slab of
// Material's own surface running to the bottom of the screen - the card's own
// content squeezed into nothing above it. The panel lays the actions out in a
// Wrap that takes a second line when the finger-sized buttons do not fit.
//
// **A double click (or double tap) edits.** The first click has already
// opened this card by the time the second arrives, so the second lands on the
// card or its barrier, never on the block. For [kDoubleTapTimeout] after it
// opens the card therefore ignores the pointer - the second click falls
// through to the barrier, which closes it - and a pointer pressed anywhere in
// that window (`_SecondClick`, a global pointer route) turns the close into
// Edit. Ignoring the card's own buttons is the point: the second click of a
// double click must not land on Delete. Nobody aims at a button in the first
// 300ms of a card existing.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../layout.dart';
import '../../sync/models.dart';
import '../../theme.dart';
import '../form_sheet.dart';
import '../markdown_text.dart';
import 'time_grid.dart' show hhmm;

/// What the user asked for on the way out. Null (the dialog dismissed) is
/// "nothing", which is the common case for a view whose job is to be read.
///
/// [openWorkspace] is offered only for a block on a workspace's own calendar:
/// a standalone calendar belongs to no list, so there is nowhere to go.
enum EventAction { edit, delete, openWorkspace }

Future<EventAction?> showEventDetails(
  BuildContext context, {
  required CalendarEvent event,
  required String calendarName,
  required Color color,
  required Future<List<Task>> Function() loadTasks,
  required Future<List<Attachment>> Function() loadAttachments,
  bool offerWorkspace = false,
  String? feedName,
}) async {
  final second = _SecondClick();
  final action = await showFormSheet<EventAction>(
    context,
    builder: (context, layout) => _DetailsDialog(
      offerWorkspace: offerWorkspace,
      feedName: feedName,
      event: event,
      calendarName: calendarName,
      color: color,
      loadTasks: loadTasks,
      loadAttachments: loadAttachments,
      layout: layout,
      second: second,
    ),
  );
  second.stop();
  // A feed's event has no Edit to give (see [_DetailsDialog.feedName]).
  if (action == null && second.hit && feedName == null) {
    return EventAction.edit;
  }
  return action;
}

/// Whether a pointer went down while the card was new: the second half of a
/// double click. Global, because that click lands on the barrier as often as
/// on the card.
class _SecondClick {
  bool hit = false;
  bool _listening = false;
  Timer? _timer;

  void start(VoidCallback onWindowClosed) {
    if (_listening) return;
    _listening = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
    _timer = Timer(kDoubleTapTimeout, () {
      stop();
      onWindowClosed();
    });
  }

  void _route(PointerEvent e) {
    if (e is PointerDownEvent) hit = true;
  }

  void stop() {
    _timer?.cancel();
    if (!_listening) return;
    _listening = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_route);
  }
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
    required this.layout,
    this.offerWorkspace = false,
    this.feedName,
    this.second,
  });

  final _SecondClick? second;

  /// The subscription this event came from, or null for one made here. Set,
  /// the card has nothing to offer but reading: Edit and Delete would both be
  /// undone by the feed's next refresh.
  final String? feedName;

  /// The block's calendar is a workspace's, so the card can take you to that
  /// workspace's list - which is usually the next question after "what is this
  /// block for".
  final bool offerWorkspace;

  final CalendarEvent event;
  final String calendarName;
  final Color color;
  final Future<List<Task>> Function() loadTasks;
  final Future<List<Attachment>> Function() loadAttachments;

  /// Passed down rather than read from context - this widget is built by a
  /// route, above the shell's LayoutScope.
  final Layout layout;

  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  List<Task>? _tasks;
  List<Attachment>? _attachments;

  /// Inside the double-click window: see the header.
  bool _young = true;

  @override
  void initState() {
    super.initState();
    _load();
    final second = widget.second;
    if (second == null) {
      _young = false;
    } else {
      second.start(() {
        if (mounted) setState(() => _young = false);
      });
    }
  }

  @override
  void dispose() {
    widget.second?.stop();
    super.dispose();
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

    final touch = widget.layout.touch;

    return IgnorePointer(
      ignoring: _young,
      child: FormSheet(
      // The calendar's own colour, so the card belongs to the block it was
      // opened from - the same rule the editor and the composer follow.
      accent: widget.color,
      layout: widget.layout,
      title: e.title,
      onClose: () => Navigator.pop(context),
      actions: [
        if (widget.feedName == null)
          FormSheet.dangerButton(
            touch: touch,
            onTap: () => Navigator.pop(context, EventAction.delete),
          ),
        if (widget.offerWorkspace)
          FormSheet.plainButton(
            touch: touch,
            icon: Icons.checklist_rounded,
            label: 'Go to workspace',
            onTap: () => Navigator.pop(context, EventAction.openWorkspace),
          ),
        if (widget.feedName == null)
          FormSheet.saveButton(
            touch: touch,
            accent: widget.color,
            label: 'Edit',
            onTap: () => Navigator.pop(context, EventAction.edit),
          )
        else
          FormSheet.cancelButton(
            touch: touch,
            label: 'Close',
            onTap: () => Navigator.pop(context),
          ),
      ],
      child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Which calendar, under the title the panel is already showing.
              if (widget.calendarName.isNotEmpty) ...[
                _Line(
                  icon: Icons.circle,
                  iconColor: widget.color,
                  text: widget.calendarName,
                ),
              ],
              if (widget.feedName != null)
                _Line(
                  icon: Icons.sync_rounded,
                  text: 'From ${widget.feedName} - read-only here',
                ),
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
                      fontSize: T.fsLabel, color: T.text, height: 1.35),
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
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.iconColor});

  final IconData icon;
  final String text;

  /// The calendar's colour on the line that names it; muted everywhere else.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: iconColor == null ? 13 : 9,
              color: iconColor ?? T.muted),
          SizedBox(width: iconColor == null ? 8 : 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: T.fsLabel, color: T.text, height: 1.3),
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
        Text(label, style: const TextStyle(fontSize: T.fsMeta, color: T.muted)),
        const SizedBox(height: 4),
        if (loading)
          const Text('…', style: TextStyle(fontSize: T.fsMeta, color: T.muted))
        else if (empty)
          Text(emptyText,
              style: const TextStyle(fontSize: T.fsMeta, color: T.muted))
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
              style: const TextStyle(fontSize: T.fsLabel, color: T.text),
            ),
          ),
        ],
      ),
    );
  }
}
