// Choosing when to be reminded.
//
// Presets rather than a date picker, and not only to save taps: the window is
// 340px wide, and Material's date picker wants roughly that on its own, so it
// would either overflow or force the widget to grow into something that is no
// longer a sticky note. The presets cover what a scratchpad todo actually needs
// - "not now, but don't let me forget" at a few horizons.

import 'package:flutter/material.dart';

import '../sync/models.dart';
import '../theme.dart';

class ReminderPreset {
  const ReminderPreset(this.label, this.at);

  final String label;
  final DateTime at;
}

/// The offered times, relative to [now].
///
/// The two fixed points (evening, tomorrow morning) are skipped when they have
/// already passed, so the menu never offers a reminder in the past - which
/// would fire instantly and read as a bug.
List<ReminderPreset> reminderPresets(DateTime now) {
  final out = <ReminderPreset>[
    ReminderPreset('In 10 minutes', now.add(const Duration(minutes: 10))),
    ReminderPreset('In 1 hour', now.add(const Duration(hours: 1))),
    ReminderPreset('In 3 hours', now.add(const Duration(hours: 3))),
  ];

  final evening = DateTime(now.year, now.month, now.day, 18);
  if (evening.isAfter(now)) {
    out.add(ReminderPreset('This evening (18:00)', evening));
  }

  final tomorrow = DateTime(now.year, now.month, now.day, 9)
      .add(const Duration(days: 1));
  out.add(ReminderPreset('Tomorrow (09:00)', tomorrow));

  return out;
}

/// Short, human phrasing for an armed reminder: "in 25m", "at 18:00",
/// "tomorrow 09:00". Long enough to be useful in a tooltip, short enough that
/// it could sit in the row later without crowding the text.
String describeReminder(DateTime at, [DateTime? nowOverride]) {
  final now = nowOverride ?? DateTime.now();
  final delta = at.difference(now);
  final hhmm = '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  if (delta.isNegative) return 'due since $hhmm';
  if (delta.inMinutes < 60) return 'in ${delta.inMinutes + 1}m';

  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = day.difference(today).inDays;

  return switch (days) {
    0 => 'at $hhmm',
    1 => 'tomorrow $hhmm',
    _ => 'in $days days, $hhmm',
  };
}

/// The menu itself. Returns the chosen time, or null for "no reminder" - the
/// caller cannot tell that apart from a dismissed menu, so [cleared] reports it.
Future<void> showReminderMenu({
  required BuildContext context,
  required RelativeRect position,
  required Task task,
  required Future<void> Function(DateTime?) onChosen,
}) async {
  final now = DateTime.now();
  final armed = task.remindAtTime;

  final chosen = await showMenu<Object>(
    context: context,
    position: position,
    color: T.bgSolid,
    items: [
      if (armed != null) ...[
        PopupMenuItem<Object>(
          enabled: false,
          height: 30,
          child: Text(
            'Reminder ${describeReminder(armed, now)}',
            style: const TextStyle(fontSize: 11, color: T.muted),
          ),
        ),
        const PopupMenuItem<Object>(
          value: _clear,
          height: 34,
          child: Text('Clear reminder',
              style: TextStyle(fontSize: 12.5, color: T.danger)),
        ),
        const PopupMenuDivider(),
      ],
      for (final p in reminderPresets(now))
        PopupMenuItem<Object>(
          value: p.at,
          height: 34,
          child: Text(p.label, style: const TextStyle(fontSize: 12.5)),
        ),
    ],
  );

  if (chosen == null) return;
  await onChosen(chosen == _clear ? null : chosen as DateTime);
}

const _clear = 'clear';
