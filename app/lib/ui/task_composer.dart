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
// The notes are Markdown (see markdown_text.dart), so the box has two states.
// It opens *read-first* on a task that already has notes and edit-first on one
// that does not - which is the same rule stated twice: show the editor exactly
// when there is nothing to read. That is what keeps the Ctrl+D flow intact,
// since a task being composed has no notes yet and so still lands in a field
// with the caret in it.
//
// A modal *route* rather than a sheet in the shell's Stack, unlike Settings and
// the sublist. The rule in main.dart is about things that live on screen while
// you work around them - a sheet leaves the title bar reachable so the window
// can still be dragged and closed. This is modal by nature (it is one task's
// fields, saved or cancelled) and it is the same shape as the event and
// workspace forms.
//
// It is **not** an AlertDialog, though, and that is the difference between what
// this looks like and what a phone showed. AlertDialog brings Material's own
// surface, insets, title styling and button bar, so on a phone the composer
// arrived as a small grey card floating in the middle of the screen in stock
// purple and blue, cropped by the keyboard, with the Priority row cut off - a
// different application's dialog wearing this app's data. What is here instead
// is [showGeneralDialog] with the surface drawn from the same tokens as
// SettingsSheet, so the composer reads as this app opening a panel.
//
// The shape is one decision made twice, on [Layout.touch]:
//
//   - Touch: full width, anchored to the bottom, rounded at the top only, and
//     rising from the bottom edge. A phone form belongs against the thumb and
//     against the keyboard, and a card inset by 40px on each side is 40px of
//     line length given away on the narrowest screen there is.
//   - Pointer: a centred column at the width the fields were drawn for, fading
//     in with a small rise. A full-width sheet on a 1400px monitor would be a
//     form with a metre of nothing beside it.
//
// Either way the body scrolls and the surface is pushed up by the keyboard
// rather than covered by it (`viewInsets`), which is what makes the reminder
// chips reachable while the notes field has the caret.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../layout.dart';
import '../sync/models.dart';
import '../theme.dart';
import 'markdown_text.dart';
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
    required this.recur,
  });

  final String text;
  final String notes;
  final int priority;

  /// Null is "no reminder", which on an existing task means clear the one it
  /// has - see AppState.saveTaskDetails.
  final DateTime? remindAt;

  /// One of [Recur.rules], or null for a task that happens once. Only
  /// meaningful alongside [remindAt] - there is nothing to repeat from
  /// otherwise, which AppState.saveTaskDetails enforces.
  final String? recur;
}

/// [existing] null composes a new task; otherwise the same form edits that one.
/// [initialText] seeds the title of a new task with whatever was already typed
/// into the add field. [accent] is the workspace colour, so the panel belongs
/// to the list it was opened from rather than being a neutral grey card.
Future<TaskDraft?> showTaskComposer(
  BuildContext context, {
  Task? existing,
  String initialText = '',
  Color accent = T.accent,
}) {
  // Read here, not inside the builder: the route's own context sits above the
  // shell's LayoutScope, so asking there would always get the fallback.
  final layout = Layout.of(context);

  return showGeneralDialog<TaskDraft>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: const Color(0x99000000),
    // Matched to the sheets in the shell, since the two now animate the same
    // way and arriving at different speeds would read as two different kinds
    // of thing.
    transitionDuration: T.sheetDur,
    pageBuilder: (context, _, _) => _ComposerSheet(
      existing: existing,
      initialText: existing?.text ?? initialText,
      accent: accent,
      layout: layout,
    ),
    transitionBuilder: (context, anim, _, child) {
      final t = T.sheetEase.transform(anim.value);
      return FadeTransition(
        opacity: anim,
        child: Transform.translate(
          // Touch rises the full height of a thumb's travel; a pointer gets a
          // token 12px, which reads as "this appeared" without the panel
          // sliding across a desk-sized screen.
          offset: Offset(0, (1 - t) * (layout.touch ? 64 : 12)),
          child: child,
        ),
      );
    },
  );
}

class _ComposerSheet extends StatefulWidget {
  const _ComposerSheet({
    required this.existing,
    required this.initialText,
    required this.accent,
    required this.layout,
  });

  final Task? existing;
  final String initialText;
  final Color accent;

  /// Passed down rather than read from context: this widget is built by a
  /// route, above the shell's LayoutScope.
  final Layout layout;

  @override
  State<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends State<_ComposerSheet> {
  late final _title = TextEditingController(text: widget.initialText);
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');

  late int _priority = widget.existing?.priority ?? 0;
  late DateTime? _remindAt = widget.existing?.remindAtTime;
  late String? _recur = widget.existing?.recur;

  /// Read-first exactly when there is something to read. See the header.
  late bool _editingNotes = (widget.existing?.notes ?? '').trim().isEmpty;

  /// The presets are relative to *now*, and "now" has to be the same instant
  /// for the whole life of the dialog or the chip labels drift under the
  /// selection they made.
  final _openedAt = DateTime.now();

  final _notesFocus = FocusNode();

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  /// Into the raw text, with the caret in it. The field does not exist until
  /// this setState has been built, so the focus cannot be requested until
  /// after the frame.
  void _editNotes() {
    if (_editingNotes) return;
    setState(() => _editingNotes = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notesFocus.requestFocus();
    });
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
        recur: _recur,
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
    final touch = widget.layout.touch;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
      },
      child: _Surface(
        accent: widget.accent,
        touch: touch,
        title: widget.existing == null ? 'New task' : 'Task',
        onCancel: () => Navigator.pop(context),
        onSave: _save,
        saveLabel: widget.existing == null ? 'Add' : 'Save',
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
                _notesBox(),
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
                // Only offered once there is a reminder to repeat from. A rule
                // with nothing to count from produces no second occurrence, so
                // showing it would be offering a setting that does nothing.
                if (_remindAt != null) ...[
                  const SizedBox(height: 14),
                  const _Label('Repeats'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text(
                          'Once',
                          style: TextStyle(fontSize: 11.5),
                        ),
                        selected: _recur == null,
                        onSelected: (_) => setState(() => _recur = null),
                      ),
                      for (final r in Recur.rules)
                        ChoiceChip(
                          label: Text(
                            Recur.label(r),
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          selected: _recur == r,
                          onSelected: (_) => setState(() => _recur = r),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ),
    );
  }

  /// The notes field and its rendered form, with one control between them.
  ///
  /// The toggle sits *under* the box rather than over its corner: notes start
  /// at the top-left of that box, and a control floating there would land on
  /// the first word of every note that has one.
  Widget _notesBox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_editingNotes)
          // Autofocus lands here, which is the whole point of Ctrl+D: the title
          // is either already typed or is the thing the one-line field would
          // have captured on its own. A task opened for re-reading starts in
          // the other state, so this only fires where the caret is wanted.
          TextField(
            controller: _notes,
            focusNode: _notesFocus,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            style: const TextStyle(fontSize: 12.5, height: 1.35),
            decoration: const InputDecoration(
              hintText: 'Notes — Markdown, links, what "done" means…',
            ),
          )
        else
          InkWell(
            onTap: _editNotes,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: T.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: MarkdownText(
                _notes.text,
                style: const TextStyle(
                    fontSize: 12.5, height: 1.35, color: T.text),
                // The body is as good a handle as the toggle. Links inside it
                // still open rather than switching to the editor - MarkdownBody
                // hands a tap on a link to onTapLink instead of this.
                onTapText: _editNotes,
              ),
            ),
          ),
        // Only offered once there is something to render. A "Preview" on an
        // empty note is a control that does nothing.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _notes,
          builder: (context, value, _) {
            if (value.text.trim().isEmpty) return const SizedBox(height: 4);
            return Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _editingNotes
                    ? setState(() => _editingNotes = false)
                    : _editNotes(),
                icon: Icon(
                  _editingNotes
                      ? Icons.visibility_outlined
                      : Icons.edit_outlined,
                  size: 14,
                ),
                label: Text(
                  _editingNotes ? 'Preview' : 'Edit',
                  style: const TextStyle(fontSize: 11.5),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: T.muted,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// The panel the composer is drawn on: full-width and bottom-anchored under a
/// fingertip, a centred column under a pointer.
///
/// It owns the chrome an AlertDialog used to bring - surface, title, and the
/// cancel/save pair - so that all of it comes from [T] and none of it from
/// Material's defaults. The colours are SettingsSheet's, deliberately: these
/// are the two big panels in the app and they should look like siblings.
class _Surface extends StatelessWidget {
  const _Surface({
    required this.accent,
    required this.touch,
    required this.title,
    required this.onCancel,
    required this.onSave,
    required this.saveLabel,
    required this.child,
  });

  final Color accent;
  final bool touch;
  final String title;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final String saveLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    // What the keyboard is covering. Padding the panel by it lifts the whole
    // form clear rather than letting the caret sit behind the keys - which is
    // what the AlertDialog did, and why the priority row was unreachable on a
    // phone with the notes field focused.
    final keyboard = media.viewInsets.bottom;

    // AlertDialog used to bring this along, and dropping it is what broke the
    // fields: an InkWell needs a Material to paint its splash onto and a
    // TextField needs one for its decoration, so without it the whole form
    // asserts. Transparent, because the surface below is drawn by the
    // Container and a second opaque layer would flatten it.
    final panel = Material(
      type: MaterialType.transparency,
      child: Container(
      decoration: BoxDecoration(
        color: Color.lerp(T.bgSolid, accent, 0.14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        borderRadius: touch
            // Square at the bottom on touch: the panel is against the edge of
            // the screen, and a rounded corner there shows a sliver of the
            // list behind it that reads as a rendering fault.
            ? const BorderRadius.vertical(top: Radius.circular(16))
            : BorderRadius.circular(T.radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x8C000000),
            blurRadius: 34,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: T.text,
                    ),
                  ),
                ),
                // A real close control, not just the barrier. On a phone the
                // barrier is a thin strip above a full-width panel and is
                // nobody's first guess at how to get out.
                Semantics(
                  label: 'Close without saving',
                  button: true,
                  child: InkWell(
                    onTap: onCancel,
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: touch ? 40 : 28,
                      height: touch ? 40 : 28,
                      child: Icon(
                        Icons.close_rounded,
                        size: touch ? 20 : 16,
                        color: T.muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: child,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, touch ? 18 : 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: T.muted,
                    minimumSize: Size(0, touch ? 44 : 32),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontSize: 12.5)),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onSave,
                  style: FilledButton.styleFrom(
                    // The workspace colour, not Material's seed purple - this
                    // panel belongs to the list it was opened from.
                    backgroundColor: accent,
                    foregroundColor: T.bgSolid,
                    minimumSize: Size(touch ? 96 : 64, touch ? 44 : 32),
                  ),
                  child: Text(
                    saveLabel,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
        ),
    );

    if (touch) {
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Never taller than most of the screen, so there is always a strip
            // of barrier left to tap and the panel never reads as a new page.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: media.size.height * 0.88 - keyboard,
              ),
              child: panel,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 380,
            maxHeight: media.size.height * 0.86 - keyboard,
          ),
          child: panel,
        ),
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
