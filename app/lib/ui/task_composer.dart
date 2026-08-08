// The long form of a task: notes, priority and a reminder, in one place.
//
// The add field at the top of the list is one line on purpose - most tasks are
// one line, and a capture box you have to fill in is a capture box you stop
// using. This is the other case: the task that needs a paragraph, or that has
// to be flagged and armed the moment you think of it. Ctrl+D opens it *from*
// the add field, carrying whatever has been typed as the title, because a
// shortcut that made you retype the line would not be worth pressing.
//
// It lands in the notes box, not the title: the title is either already there
// or is the one thing the quick field would have done anyway.
//
// A dialog rather than a sheet, unlike Settings and the sublist. The rule in
// main.dart is about things that live on screen while you work *around* them -
// a sheet leaves the title bar reachable so the window can still be dragged and
// closed. This is modal by nature (it is one task's fields, saved or cancelled)
// and it is the same shape as the event and workspace forms, which are dialogs
// for the same reason.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sync/models.dart';
import '../theme.dart';
import 'reminder_menu.dart';
import 'reminder_picker.dart';

/// What the composer produced. There is no delete here - a task nobody wants is
/// dismissed from its row, where the ✕ already is.
class TaskDraft {
  const TaskDraft({
    required this.text,
    required this.notes,
    required this.priority,
    required this.remindAt,
  });

  final String text;
  final String notes;
  final int priority;

  /// Null is "no reminder", which on an existing task means clear the one it
  /// has - see AppState.saveTaskDetails.
  final DateTime? remindAt;
}

/// [existing] null composes a new task; otherwise the same form edits that one.
/// [initialText] seeds the title of a new task with whatever was already typed
/// into the add field.
Future<TaskDraft?> showTaskComposer(
  BuildContext context, {
  Task? existing,
  String initialText = '',
}) {
  return showDialog<TaskDraft>(
    context: context,
    builder: (context) => _ComposerDialog(
      existing: existing,
      initialText: existing?.text ?? initialText,
    ),
  );
}

class _ComposerDialog extends StatefulWidget {
  const _ComposerDialog({required this.existing, required this.initialText});

  final Task? existing;
  final String initialText;

  @override
  State<_ComposerDialog> createState() => _ComposerDialogState();
}

class _ComposerDialogState extends State<_ComposerDialog> {
  late final _title = TextEditingController(text: widget.initialText);
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');

  late int _priority = widget.existing?.priority ?? 0;
  late DateTime? _remindAt = widget.existing?.remindAtTime;

  /// The presets are relative to *now*, and "now" has to be the same instant
  /// for the whole life of the dialog or the chip labels drift under the
  /// selection they made.
  final _openedAt = DateTime.now();

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    final text = _title.text.trim();
    if (text.isEmpty) return;
    Navigator.pop(
      context,
      TaskDraft(
        text: text,
        notes: _notes.text.trim(),
        priority: _priority,
        remindAt: _remindAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presets = reminderPresets(_openedAt);
    // An armed time that is not one of the presets - an existing task's
    // reminder, or one set from the row's menu - still has to be shown as
    // chosen rather than silently missing from the row of chips.
    final armedIsPreset =
        _remindAt != null && presets.any((p) => p.at == _remindAt);

    // Ctrl+Enter saves from inside the notes box, where a plain Enter is a new
    // line and has to stay one.
    //
    // This wraps the *whole* dialog rather than the Save button, and has to:
    // CallbackShortcuts builds a Focus node that only sees key events bubbling
    // up from its own subtree. Around the button it never fired, because the
    // primary focus is the autofocused notes field over in `content:` - a
    // sibling branch - so the only way to reach it was to tab onto Save, where
    // a plain Enter already saves.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
      },
      child: AlertDialog(
        backgroundColor: T.bgSolid,
        title: Text(
          widget.existing == null ? 'New task' : 'Task',
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
                  style: const TextStyle(fontSize: 13.5),
                  decoration: const InputDecoration(hintText: 'What is it?'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                // Autofocus lands here, which is the whole point of the shortcut:
                // the title is either already typed or is the thing the one-line
                // field would have captured on its own.
                TextField(
                  controller: _notes,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 10,
                  style: const TextStyle(fontSize: 12.5, height: 1.35),
                  decoration: const InputDecoration(
                    hintText: 'Notes — links, the address, what "done" means…',
                  ),
                ),
                const SizedBox(height: 14),
                const _Label('Priority'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _Flag(
                      on: _priority >= Task.priorityHigh,
                      onTap: () => setState(
                        () => _priority = _priority >= Task.priorityHigh
                            ? 0
                            : Task.priorityHigh,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const _Label('Remind me'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text(
                        'No reminder',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      selected: _remindAt == null,
                      onSelected: (_) => setState(() => _remindAt = null),
                    ),
                    if (_remindAt != null && !armedIsPreset)
                      ChoiceChip(
                        label: Text(
                          describeReminder(_remindAt!, _openedAt),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        selected: true,
                        onSelected: (_) {},
                      ),
                    for (final p in presets)
                      ChoiceChip(
                        label: Text(
                          p.label,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        selected: _remindAt == p.at,
                        onSelected: (_) => setState(() => _remindAt = p.at),
                      ),
                    // The exact-time door, the same one the row's reminder menu
                    // ends with. An ActionChip rather than a ChoiceChip because
                    // it opens something instead of being a value: what it
                    // returns turns up as the selected chip beside it, via the
                    // not-a-preset branch above.
                    ActionChip(
                      avatar: const Icon(Icons.event_rounded, size: 14),
                      label: const Text(
                        'Pick…',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      onPressed: () async {
                        final at = await showReminderPicker(
                          context,
                          initial: _remindAt,
                        );
                        if (at != null) setState(() => _remindAt = at);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(fontSize: 12.5)),
          ),
          FilledButton(
            onPressed: _save,
            child: Text(
              widget.existing == null ? 'Add' : 'Save',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 11.5, color: T.muted));
}

/// The high-priority toggle. A flag rather than a slider of levels: the column
/// can carry more, but two states are what a checklist can act on.
class _Flag extends StatelessWidget {
  const _Flag({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? T.danger.withValues(alpha: 0.18) : T.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: on ? T.danger.withValues(alpha: 0.8) : Colors.transparent,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? Icons.flag_rounded : Icons.outlined_flag_rounded,
                size: 15,
                color: on ? T.danger : T.muted,
              ),
              const SizedBox(width: 7),
              Text(
                'High priority',
                style: TextStyle(
                  fontSize: 12,
                  color: on ? T.text : T.muted,
                  fontWeight: on ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
