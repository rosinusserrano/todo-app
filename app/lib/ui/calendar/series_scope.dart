// "Only this one, or every one of them?" - asked before anything is written
// through one occurrence of a repeating block.
//
// A transient prompt, so a dialog like the other confirmations (see the sheet
// rule in main.dart). It replaced the confirmation a series delete used to
// have: there is no undo behind either answer, and naming both is what makes
// the press that removes fifty-two Tuesdays a deliberate one.
//
// "This one" writes an exception row (`CalendarEvent.detached`); "all of them"
// writes the series, which is what every change did before there was a choice.

import 'package:flutter/material.dart';

import '../../sync/models.dart';
import '../../theme.dart';

enum SeriesScope { one, all }

/// Ask which of [event]'s series a change applies to. Null is "cancel".
///
/// [deleting] changes the words, not the question. Not asked for a one-off,
/// which has only the one answer - callers check [CalendarEvent.inSeries].
Future<SeriesScope?> askSeriesScope(
  BuildContext context, {
  required CalendarEvent event,
  bool deleting = false,
}) {
  final rule = event.recur;
  final about = rule != null
      ? '"${event.title}" repeats ${Recur.label(rule).toLowerCase()}.'
      : '"${event.title}" is one occurrence of a repeating event, already '
          'changed on its own.';
  return showDialog<SeriesScope>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: T.bgSolid,
      title: Text(
        deleting ? 'Delete a repeating event' : 'Change a repeating event',
        style: const TextStyle(fontSize: T.fsMenu),
      ),
      content: Text(
        deleting
            ? '$about Delete only this occurrence, or the whole series?'
            : '$about Change only this occurrence, or the whole series?',
        style: const TextStyle(
          fontSize: T.fsLabel,
          color: T.muted,
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, SeriesScope.all),
          child: const Text('Whole series'),
        ),
        // The common answer, so the filled one: a series is set up once and
        // its occurrences are moved about every week.
        FilledButton(
          onPressed: () => Navigator.pop(context, SeriesScope.one),
          child: const Text('Only this one'),
        ),
      ],
    ),
  );
}
