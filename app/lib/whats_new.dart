// What changed, shown once after an update.
//
// The notes are written for the person using the app, not for whoever reads
// the code - FEATURES.md's changelog is the long record; this is the three
// sentences somebody reads on the way back into their list. Each deploy adds
// an entry at the TOP of [kReleaseNotes] with a new [ReleaseNote.id], and that
// new id is the whole of how a device knows it has not shown it yet.
//
// An id rather than the app's version, because the web app is redeployed far
// more often than the version moves: every round published to the server is
// the same 0.29.0 until a release is cut, and each one is still an update to
// the person reloading the page.
//
// Which notes a device has seen is device-local (`whats-new:seen` in
// settings, see AppState.checkWhatsNew): the box is about this screen having
// changed, and every device changes on its own update.

import 'package:flutter/material.dart';

import 'layout.dart';
import 'theme.dart';
import 'ui/form_sheet.dart';

class ReleaseNote {
  const ReleaseNote({
    required this.id,
    required this.title,
    required this.points,
  });

  /// Unique and never reused; the date it was published, with a suffix if
  /// there is ever a second one that day.
  final String id;
  final String title;
  final List<String> points;
}

/// Newest first.
const kReleaseNotes = <ReleaseNote>[
  ReleaseNote(
    id: '2026-10-15',
    title: 'Edit mode, and stretchable events',
    points: [
      'The calendar\'s ⚡ is now ✎ edit mode (Ctrl+E on a desktop). Blocks '
          'only move while it is on, so a stray drag cannot move a meeting.',
      'In edit mode, drag the top or bottom edge of an event to make it '
          'longer or shorter. It snaps to quarter hours.',
      'The red line for "now" is drawn over the events instead of under '
          'them.',
      'On a desktop, a new thought always opens the thought pane: Enter '
          'saves, Ctrl+Enter saves and starts another, Shift+Enter is a new '
          'line.',
      'Clicking the workspace on the dock opens the add field. Swiping '
          'sideways on the list walks Tasks, Notes, Collections, Parked and '
          'History.',
      'Windows app: arrange the window how you like it, rest the mouse on '
          'the □ beside Minimize and choose "Save this window…" to keep that '
          'size and place under a name. One click puts it back.',
      'And this box: it shows once after every update.',
    ],
  ),
];

/// At most this many entries at once. A device that has been away for a
/// dozen updates wants the gist of the latest, not a scroll through all of
/// them.
const kMaxNotesShown = 3;

/// The notes newer than [seen], newest first. All of them (capped) when
/// [seen] is not in the list at all - an id that has gone means a note that
/// was dropped, and everything still listed is newer than whatever it was.
List<ReleaseNote> notesSince(
  String? seen, [
  List<ReleaseNote> notes = kReleaseNotes,
]) {
  return notes.takeWhile((n) => n.id != seen).take(kMaxNotesShown).toList();
}

/// The box. Resolves when it is closed, however it was closed.
Future<void> showWhatsNew(
  BuildContext context, {
  required List<ReleaseNote> notes,
  required Color accent,
}) {
  return showFormSheet<void>(
    context,
    builder: (context, layout) => FormSheet(
      accent: accent,
      layout: layout,
      title: "What's new",
      onClose: () => Navigator.of(context).pop(),
      actions: [
        FormSheet.saveButton(
          touch: layout.touch,
          accent: accent,
          label: 'Got it',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final note in notes) _Note(note: note, layout: layout),
          ],
        ),
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note({required this.note, required this.layout});

  final ReleaseNote note;
  final Layout layout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: T.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note.title,
            style: const TextStyle(
              fontFamily: T.fontDisplay,
              fontSize: T.fsBody,
              fontWeight: T.wMedium,
              color: T.text,
            ),
          ),
          const SizedBox(height: T.s2),
          for (final p in note.points)
            Padding(
              padding: const EdgeInsets.only(bottom: T.s2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '•  ',
                    style: TextStyle(fontSize: T.fsBody, color: T.muted),
                  ),
                  Expanded(
                    child: Text(
                      p,
                      style: const TextStyle(
                        fontSize: T.fsBody,
                        height: 1.35,
                        color: T.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
