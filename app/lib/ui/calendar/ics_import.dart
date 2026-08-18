// Confirming an .ics import.
//
// Nothing is written until this returns a calendar. An import that just
// happened, silently, into whichever calendar was in front of you is the kind
// of thing you find out about three weeks later when the block is in the wrong
// place - so the events are listed, the destination is chosen, and only then is
// anything saved.
//
// A dialog, like the other transient prompts: modal by nature and over in a
// couple of taps.

import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../sync/ics.dart';
import '../../sync/models.dart' show Recur;
import '../../theme.dart';

/// Shows what was found and asks which calendar it should go on. Returns the
/// chosen calendar's uuid, or null if it was dismissed.
Future<String?> showImportIcs(
  BuildContext context,
  List<IcsEvent> events, {
  required AppState state,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _ImportDialog(events: events, state: state),
  );
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.events, required this.state});

  final List<IcsEvent> events;
  final AppState state;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  String? _target;

  @override
  void initState() {
    super.initState();
    // Defaults to the current workspace's own calendar, which is where an
    // invite you are looking at almost always belongs.
    final calendars = widget.state.calendars;
    _target =
        calendars
            .where((c) => c.uuid == widget.state.currentWorkspaceUuid)
            .firstOrNull
            ?.uuid ??
        (calendars.isEmpty ? null : calendars.first.uuid);
  }

  @override
  Widget build(BuildContext context) {
    final events = widget.events;
    final calendars = widget.state.calendars;

    return AlertDialog(
      backgroundColor: T.bgSolid,
      title: Text(
        events.length == 1 ? 'Add this event?' : 'Add ${events.length} events?',
        style: const TextStyle(fontSize: 15),
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Capped: a subscription file can hold hundreds, and a list
                    // that long is not a preview, it is a scroll.
                    for (final e in events.take(8)) _EventLine(event: e),
                    if (events.length > 8)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '…and ${events.length - 8} more',
                          style: const TextStyle(fontSize: 11, color: T.muted),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Add to',
              style: TextStyle(
                fontSize: 10.5,
                color: T.muted,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 6),
            if (calendars.isEmpty)
              const Text(
                'No calendars yet — make one first.',
                style: TextStyle(fontSize: 11.5, color: T.danger),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in calendars)
                    ChoiceChip(
                      label: Text(
                        widget.state.calendarName(c),
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      selected: _target == c.uuid,
                      onSelected: (_) => setState(() => _target = c.uuid),
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(fontSize: 12.5)),
        ),
        FilledButton(
          onPressed: _target == null
              ? null
              : () => Navigator.pop(context, _target),
          child: const Text('Add', style: TextStyle(fontSize: 12.5)),
        ),
      ],
    );
  }
}

class _EventLine extends StatelessWidget {
  const _EventLine({required this.event});

  final IcsEvent event;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String get _when {
    final s = event.start;
    final date = '${s.day} ${_months[s.month - 1]}';
    if (event.allDay) return '$date · all day';

    String hhmm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    return '$date · ${hhmm(s)}–${hhmm(event.end)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: T.text),
          ),
          Text(
            // The recurrence note belongs here, next to the event, rather than
            // only in the description it is about to be given: this is the
            // moment to notice what a series came across as - the whole rule
            // when the .ics said something we can say, and one block when it
            // did not.
            !event.recurring
                ? _when
                : event.recur != null
                    ? '$_when · ${Recur.label(event.recur!).toLowerCase()}'
                    : '$_when · repeats (first only)',
            style: const TextStyle(fontSize: 11, color: T.muted),
          ),
        ],
      ),
    );
  }
}
