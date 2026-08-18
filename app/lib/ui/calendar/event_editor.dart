// The form behind a drag on the grid, and behind tapping an existing event.
//
// A drag has already said when, so the form opens with the times filled in and
// the caret in the title - the one field that is required and the only thing
// the drag could not have told us.
//
// Attachments and todos appear only when editing a saved event: both are rows
// keyed by the event's uuid, and a new event does not have one until it is
// saved. Asking the user to save first is better than inventing an id for a
// form they might cancel, which would leave orphaned bytes on disk.
//
// The todo list is the *workspace's* open tasks with a tick beside each, not a
// place to write new ones: planning a block is choosing among things you have
// already decided to do. A task planned into some other block says so rather
// than being hidden, because taking it is a legitimate thing to want and
// silently omitting it would look like the task had disappeared.

import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../sync/models.dart';
import '../../theme.dart';
import 'time_grid.dart' show hhmm;

/// What the form produced. [delete] is the one case that carries nothing else.
class EventEdit {
  const EventEdit({
    required this.calendarUuid,
    required this.title,
    required this.description,
    required this.start,
    required this.end,
    required this.notifyMinutes,
    required this.recur,
    required this.allDay,
    this.delete = false,
  });

  const EventEdit.delete()
      : calendarUuid = '',
        title = '',
        description = '',
        start = null,
        end = null,
        notifyMinutes = null,
        recur = null,
        allDay = false,
        delete = true;

  final String calendarUuid;
  final String title;
  final String description;
  final DateTime? start;
  final DateTime? end;

  /// Null inherits the calendar's rule; [CalendarEvent.notifySilent] overrides
  /// it to stay quiet.
  final int? notifyMinutes;

  /// One of [Recur.rules], or null for a block that happens once.
  final String? recur;

  /// A whole day or run of days. [end] is then the **exclusive** end - midnight
  /// on the day after the last one - which is what the store and .ics both use;
  /// the form displays the inclusive day, because that is what a person means
  /// by "ends on the 20th".
  final bool allDay;

  final bool delete;
}

Future<EventEdit?> showEventForm(
  BuildContext context, {
  CalendarEvent? existing,
  required List<Calendar> calendars,
  required String Function(Calendar) nameFor,
  required Color Function(Calendar) colorFor,
  required String initialCalendarUuid,
  required DateTime initialStart,
  required DateTime initialEnd,
  Future<List<Attachment>> Function()? loadAttachments,
  Future<void> Function(File)? onAddAttachment,
  Future<void> Function(Attachment)? onRemoveAttachment,
  Future<List<Task>> Function()? loadTasks,
  Future<void> Function(Task, bool)? onPlanTask,
}) {
  return showDialog<EventEdit>(
    context: context,
    builder: (context) => _EventDialog(
      existing: existing,
      calendars: calendars,
      nameFor: nameFor,
      colorFor: colorFor,
      initialCalendarUuid: initialCalendarUuid,
      initialStart: initialStart,
      initialEnd: initialEnd,
      loadAttachments: loadAttachments,
      onAddAttachment: onAddAttachment,
      onRemoveAttachment: onRemoveAttachment,
      loadTasks: loadTasks,
      onPlanTask: onPlanTask,
    ),
  );
}

class _EventDialog extends StatefulWidget {
  const _EventDialog({
    required this.existing,
    required this.calendars,
    required this.nameFor,
    required this.colorFor,
    required this.initialCalendarUuid,
    required this.initialStart,
    required this.initialEnd,
    required this.loadAttachments,
    required this.onAddAttachment,
    required this.onRemoveAttachment,
    required this.loadTasks,
    required this.onPlanTask,
  });

  final CalendarEvent? existing;
  final List<Calendar> calendars;
  final String Function(Calendar) nameFor;
  final Color Function(Calendar) colorFor;
  final String initialCalendarUuid;
  final DateTime initialStart;
  final DateTime initialEnd;
  final Future<List<Attachment>> Function()? loadAttachments;
  final Future<void> Function(File)? onAddAttachment;
  final Future<void> Function(Attachment)? onRemoveAttachment;

  /// The tasks that could be planned into this block - the workspace's open
  /// list, with the ones already planned marked by their own [Task.eventUuid].
  final Future<List<Task>> Function()? loadTasks;

  /// Plan a task into this block, or take it out again.
  final Future<void> Function(Task, bool)? onPlanTask;

  @override
  State<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<_EventDialog> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _description =
      TextEditingController(text: widget.existing?.description ?? '');

  late String _calendarUuid = widget.initialCalendarUuid;
  late DateTime _start = widget.initialStart;
  late DateTime _end = widget.initialEnd;
  late int? _notify = widget.existing?.notifyMinutes;
  late String? _recur = widget.existing?.recur;
  late bool _allDay = widget.existing?.allDay ?? false;

  List<Attachment>? _attachments;
  List<Task>? _tasks;

  /// Null is "follow the calendar", which is the default and the one most
  /// events should keep - the point of a per-calendar rule is not having to
  /// answer this question per event.
  static const _notifyOptions = <int?, String>{
    null: 'Calendar default',
    CalendarEvent.notifySilent: 'None',
    0: 'At start',
    10: '10 min before',
    30: '30 min before',
    60: '1 hour before',
    1440: '1 day before',
  };

  @override
  void initState() {
    super.initState();
    _reloadAttachments();
    _reloadTasks();
  }

  Future<void> _reloadAttachments() async {
    final load = widget.loadAttachments;
    if (load == null) return;
    final list = await load();
    if (mounted) setState(() => _attachments = list);
  }

  Future<void> _reloadTasks() async {
    final load = widget.loadTasks;
    if (load == null) return;
    final list = await load();
    if (mounted) setState(() => _tasks = list);
  }

  /// Ticking a task writes it straight through rather than waiting for Save.
  ///
  /// The tick is an edit to the *task*, not to the event being composed, so
  /// there is nothing on this form for it to be part of - and Cancel meaning
  /// "undo the times but keep the todos" would be a worse surprise than the
  /// list simply doing what it says. Same reason attachments write immediately.
  Future<void> _plan(Task t, bool on) async {
    final plan = widget.onPlanTask;
    if (plan == null) return;
    await plan(t, on);
    await _reloadTasks();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    // The end button shows the inclusive last day when this is a whole-day
    // event, so that is also what the picker has to open on and what the
    // answer means.
    final current = isStart ? _start : (_allDay ? _lastDay : _end);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 5),
      lastDate: DateTime(current.year + 5),
    );
    // The picker is a route, so the editor underneath it can be gone by the
    // time it answers - a back gesture that pops both, or the shell clearing
    // its overlays.
    if (picked == null || !mounted) return;
    setState(() {
      final moved = DateTime(
        picked.year,
        picked.month,
        picked.day,
        current.hour,
        current.minute,
      );
      if (isStart) {
        // Keep the length when the start moves, which is almost always what
        // was meant by moving it.
        final length = _end.difference(_start);
        _start = moved;
        _end = moved.add(length);
      } else {
        _end = _allDay ? moved.add(const Duration(days: 1)) : moved;
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final moved = DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      );
      if (isStart) {
        final length = _end.difference(_start);
        _start = moved;
        _end = moved.add(length);
      } else {
        _end = moved;
      }
    });
  }

  /// Whole days are displayed inclusively - "18 Aug to 18 Aug" is one day -
  /// and stored exclusively. The conversion lives here, at the one boundary
  /// between what a person means and what the overlap tests need.
  DateTime get _lastDay {
    final e = _end.subtract(const Duration(days: 1));
    final day = DateTime(e.year, e.month, e.day);
    final first = DateTime(_start.year, _start.month, _start.day);
    return day.isBefore(first) ? first : day;
  }

  void _toggleAllDay(bool on) {
    setState(() {
      _allDay = on;
      if (on) {
        // Keep the days the user had; drop the hours, which no longer mean
        // anything, and make the end exclusive.
        final first = DateTime(_start.year, _start.month, _start.day);
        final last = DateTime(_end.year, _end.month, _end.day);
        _start = first;
        _end = last.isAfter(first) ? last : first.add(const Duration(days: 1));
      } else {
        // Coming back to a timed block, midnight to midnight would be a
        // 24-hour meeting nobody asked for; a working hour is the honest
        // default and is one tap from anything else.
        _start = DateTime(_start.year, _start.month, _start.day, 9);
        _end = _start.add(const Duration(hours: 1));
      }
    });
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(
      context,
      EventEdit(
        calendarUuid: _calendarUuid,
        title: title,
        description: _description.text.trim(),
        start: _start,
        end: _end,
        notifyMinutes: _notify,
        recur: _recur,
        allDay: _allDay,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;

    return AlertDialog(
      backgroundColor: T.bgSolid,
      title: Text(
        editing ? 'Edit event' : 'New event',
        style: const TextStyle(fontSize: 15),
      ),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(hintText: 'Title'),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 4,
                style: const TextStyle(fontSize: 12.5),
                decoration: const InputDecoration(
                  hintText: 'Description (optional)',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const SizedBox(
                    width: 46,
                    child: Text('All day',
                        style: TextStyle(fontSize: 11.5, color: T.muted)),
                  ),
                  Switch(
                    value: _allDay,
                    onChanged: _toggleAllDay,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _WhenRow(
                label: 'Starts',
                at: _start,
                onDate: () => _pickDate(isStart: true),
                onTime: _allDay ? null : () => _pickTime(isStart: true),
              ),
              const SizedBox(height: 6),
              _WhenRow(
                // Whole days read inclusively: one day is "18 Aug" to
                // "18 Aug", not to the midnight that ends it.
                label: 'Ends',
                at: _allDay ? _lastDay : _end,
                // An end before the start is the one combination the form must
                // not hand back; the store also guards it, but saying so here
                // is better than silently correcting it after the fact.
                warn: !_end.isAfter(_start),
                onDate: () => _pickDate(isStart: false),
                onTime: _allDay ? null : () => _pickTime(isStart: false),
              ),
              const SizedBox(height: 14),
              const Text('Calendar',
                  style: TextStyle(fontSize: 11.5, color: T.muted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in widget.calendars)
                    ChoiceChip(
                      label: Text(
                        widget.nameFor(c),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      avatar: CircleAvatar(
                        backgroundColor: widget.colorFor(c),
                        radius: 5,
                      ),
                      selected: _calendarUuid == c.uuid,
                      onSelected: (_) => setState(() => _calendarUuid = c.uuid),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Notify',
                  style: TextStyle(fontSize: 11.5, color: T.muted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in _notifyOptions.entries)
                    ChoiceChip(
                      label: Text(e.value,
                          style: const TextStyle(fontSize: 11.5)),
                      selected: _notify == e.key,
                      onSelected: (_) => setState(() => _notify = e.key),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Repeats',
                  style: TextStyle(fontSize: 11.5, color: T.muted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Once',
                        style: TextStyle(fontSize: 11.5)),
                    selected: _recur == null,
                    onSelected: (_) => setState(() => _recur = null),
                  ),
                  for (final r in Recur.rules)
                    ChoiceChip(
                      label: Text(Recur.label(r),
                          style: const TextStyle(fontSize: 11.5)),
                      selected: _recur == r,
                      onSelected: (_) => setState(() => _recur = r),
                    ),
                ],
              ),
              // Said once, here, rather than on every occurrence: this form is
              // always the series - see _editEvent, which opens `event.stored`
              // - so the times above are the first occurrence's and a change to
              // any of it changes every one of them. Editing a single
              // occurrence needs somewhere to record the exception and is
              // deliberately not in this version.
              if (_recur != null) ...[
                const SizedBox(height: 6),
                const Text(
                  'Changes apply to the whole series.',
                  style: TextStyle(fontSize: 11, color: T.muted),
                ),
              ],
              if (editing && widget.loadTasks != null) ...[
                const SizedBox(height: 14),
                _TodosSection(
                  tasks: _tasks,
                  eventUuid: widget.existing!.uuid,
                  onPlan: widget.onPlanTask == null ? null : _plan,
                ),
              ],
              if (editing && widget.loadAttachments != null) ...[
                const SizedBox(height: 14),
                _AttachmentsSection(
                  attachments: _attachments,
                  onAdd: widget.onAddAttachment == null
                      ? null
                      : () async {
                          await _pickAndAdd();
                        },
                  onRemove: widget.onRemoveAttachment == null
                      ? null
                      : (a) async {
                          await widget.onRemoveAttachment!(a);
                          await _reloadAttachments();
                        },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (editing)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const EventEdit.delete()),
            child: const Text('Delete',
                style: TextStyle(color: T.danger, fontSize: 12.5)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(fontSize: 12.5)),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save', style: TextStyle(fontSize: 12.5)),
        ),
      ],
    );
  }

  Future<void> _pickAndAdd() async {
    final add = widget.onAddAttachment;
    if (add == null) return;
    // lockParentWindow: the widget is always-on-top on Windows, so without it
    // the picker can open *behind* the thing that asked for it.
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Attach to this event',
      lockParentWindow: true,
    );
    final path = result?.files.singleOrNull?.path;
    if (path == null) return;
    await add(File(path));
    await _reloadAttachments();
  }
}

class _WhenRow extends StatelessWidget {
  const _WhenRow({
    required this.label,
    required this.at,
    required this.onDate,
    required this.onTime,
    this.warn = false,
  });

  final String label;
  final DateTime at;
  final VoidCallback onDate;

  /// Null on a whole-day event, where there is no time to pick. The button is
  /// removed rather than disabled: a greyed control invites a second attempt at
  /// pressing it.
  final VoidCallback? onTime;

  final bool warn;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 46,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: warn ? T.danger : T.muted,
            ),
          ),
        ),
        OutlinedButton(
          onPressed: onDate,
          child: Text(
            '${at.day} ${_months[at.month - 1]} ${at.year}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        if (onTime != null) ...[
          const SizedBox(width: 6),
          OutlinedButton(
            onPressed: onTime,
            child: Text(hhmm(at), style: const TextStyle(fontSize: 12)),
          ),
        ],
      ],
    );
  }
}

/// The workspace's open tasks, ticked into this block or not.
///
/// A plain scrolling list of ticks rather than a picker dialog: planning is
/// several of these in a row, and a dialog per task would put two presses
/// around each one. It is height-capped because the dialog itself scrolls -
/// without the cap a workspace with forty open tasks would push Save off the
/// bottom of a 480px window.
class _TodosSection extends StatelessWidget {
  const _TodosSection({
    required this.tasks,
    required this.eventUuid,
    required this.onPlan,
  });

  final List<Task>? tasks;
  final String eventUuid;
  final Future<void> Function(Task, bool)? onPlan;

  @override
  Widget build(BuildContext context) {
    final list = tasks;
    final planned =
        list == null ? 0 : list.where((t) => t.eventUuid == eventUuid).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Todos in this block',
                style: TextStyle(fontSize: 11.5, color: T.muted)),
            const Spacer(),
            if (planned > 0)
              Text('$planned',
                  style: const TextStyle(fontSize: 11.5, color: T.muted)),
          ],
        ),
        if (list == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('…', style: TextStyle(fontSize: 11.5, color: T.muted)),
          )
        else if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'This workspace has nothing open to plan.',
              style: TextStyle(fontSize: 11.5, color: T.muted),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 172),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final t in list)
                    _TodoTick(
                      task: t,
                      here: t.eventUuid == eventUuid,
                      // Planned into a *different* block. Ticking it moves it
                      // here, which is one column of state doing what it says -
                      // a task is in at most one block.
                      elsewhere: t.eventUuid != null && t.eventUuid != eventUuid,
                      onPlan: onPlan,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TodoTick extends StatelessWidget {
  const _TodoTick({
    required this.task,
    required this.here,
    required this.elsewhere,
    required this.onPlan,
  });

  final Task task;
  final bool here;
  final bool elsewhere;
  final Future<void> Function(Task, bool)? onPlan;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPlan == null ? null : () => onPlan!(task, !here),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: Row(
          children: [
            Icon(
              here ? Icons.check_box : Icons.check_box_outline_blank,
              size: 15,
              color: here ? T.accent : T.muted,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                task.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: here ? T.text : T.muted,
                ),
              ),
            ),
            if (elsewhere)
              const Tooltip(
                message: 'Planned into another block — ticking moves it here',
                child: Icon(Icons.event_available_rounded,
                    size: 12, color: T.muted),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentsSection extends StatelessWidget {
  const _AttachmentsSection({
    required this.attachments,
    required this.onAdd,
    required this.onRemove,
  });

  final List<Attachment>? attachments;
  final Future<void> Function()? onAdd;
  final Future<void> Function(Attachment)? onRemove;

  @override
  Widget build(BuildContext context) {
    final list = attachments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Attachments',
                style: TextStyle(fontSize: 11.5, color: T.muted)),
            const Spacer(),
            if (onAdd != null)
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('Add', style: TextStyle(fontSize: 11.5)),
              ),
          ],
        ),
        if (list == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('…', style: TextStyle(fontSize: 11.5, color: T.muted)),
          )
        else if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('None',
                style: TextStyle(fontSize: 11.5, color: T.muted)),
          )
        else
          for (final a in list)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.attach_file, size: 12, color: T.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      a.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                  if (onRemove != null)
                    IconButton(
                      onPressed: () => onRemove!(a),
                      icon: const Icon(Icons.close, size: 13),
                      color: T.muted,
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                    ),
                ],
              ),
            ),
      ],
    );
  }
}
