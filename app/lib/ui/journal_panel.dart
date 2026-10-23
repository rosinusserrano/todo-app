// The journal - a quiet, optionally password-locked writing surface, per
// workspace.
//
// Two deliberate design choices drive everything here:
//
//   - It is *quiet*. No "Journal" wordmark, no diary iconography, no warm
//     colours or emoji - just a plain list and a plain title/body editor in the
//     same muted greys as the rest of the widget. Someone glancing at the
//     screen sees a notes pane in a todo app, not something personal.
//   - The lock is *optional*. By default the journal is plaintext and opens
//     straight to the list. Set a password and it turns on encryption (the
//     entries become unreadable in the database) and starts asking to be
//     unlocked; remove the password and it goes back to plaintext.
//
// The editor takes over the whole pane (an in-app editor, not a separate OS
// window): pick or create an entry and the list is replaced by a title field, a
// body field, and Cancel / Save.
//
// Entries are Markdown (see markdown_text.dart), which puts a third state
// between the list and the editor: **reading**. Picking an existing entry
// renders it; the pencil turns it back into the two fields. A new entry skips
// straight to the fields, because there is nothing to read yet. So Esc walks
// back down a ladder rather than out of one door - editor to reader, reader to
// list, list to the tasks - and each rung is where you just came from.
//
// The editor's own shortcuts, all of them about not reaching for the mouse
// mid-sentence:
//
//   Tab           title to body (Enter and Ctrl+Enter too). In the body Tab
//                 nests a list item instead (note_editor.dart).
//   Ctrl+S        save and read what you wrote - the same thing Save does.
//   Ctrl+Alt+S    save and go back to the list, for when the entry is finished
//                 rather than being re-read.
//   Ctrl+F        find and replace in the body.
//
// And one from the reader: Ctrl+E edits the note being read, caret in the
// body - the pencil's key. The calendar's Ctrl+E is the shell's and cannot
// collide: the calendar replaces the pane.
//
// The body is a [NoteBody] (note_editor.dart): monospaced, lists that continue,
// and the code editor's keys when Settings has them on. Beside it, when
// [JournalView.preview] is on, the note as it will read - side by side where
// there is room, one above the other where there is not.

import 'dart:async' show Timer;

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../theme.dart';
import 'list_rule.dart';
import 'markdown_text.dart';
import 'note_editor.dart';
import 'panel_header.dart';

class JournalView extends StatefulWidget {
  const JournalView({
    super.key,
    required this.configured,
    required this.locked,
    required this.items,
    required this.onSetup,
    required this.onUnlock,
    required this.onLock,
    required this.onRemovePassword,
    required this.onSave,
    required this.onDelete,
    required this.onBack,
    this.onFocusChanged,
    this.onEditingChanged,
    this.startNew = false,
    this.codeKeys = false,
    this.preview = false,
    this.onPreview,
  });

  /// The code editor's keys in the body (code_keys.dart), from Settings.
  final bool codeKeys;

  /// The rendered note beside the one being written, and how to turn it on
  /// and off - a standing choice, so the shell keeps it (device-local).
  final bool preview;
  final ValueChanged<bool>? onPreview;

  /// Open on a blank entry rather than the list - the dock's *Add a note*.
  /// Read once, when the State is made: the shell hands a fresh key with it.
  /// A locked journal still asks for the password first, and the blank entry
  /// is what unlocking lands on.
  final bool startNew;

  /// Called when the editor opens and when it closes - the shell hides a
  /// bottom dock while a note is written, and keeps it while one is read.
  final ValueChanged<bool>? onEditingChanged;

  /// Called when an open note goes into focus - nothing on screen but its
  /// title and its text - and again when it comes out, or the note closes.
  ///
  /// The shell hides everything of its own for it: the dock, the footer, and
  /// on a phone the title bar. It is a callback rather than something the
  /// shell can work out for itself because which rung of the ladder this
  /// panel is on is genuinely this panel's own state - `showJournal` only
  /// says the pane is open.
  final ValueChanged<bool>? onFocusChanged;

  /// A password has been set (encryption is on).
  final bool configured;

  /// Configured but not unlocked this session - show the unlock prompt.
  final bool locked;

  final List<JournalItem> items;

  final Future<void> Function(String password) onSetup;
  final Future<bool> Function(String password) onUnlock;
  final VoidCallback onLock;
  final Future<void> Function() onRemovePassword;

  /// [existing] null means a new entry. Returns the entry as saved - the panel
  /// needs the uuid a *new* one was given, or the second Ctrl+S in a sitting
  /// would write a second row instead of rewriting the first. Null means
  /// nothing was saved (an empty entry, or one cleared to nothing, which
  /// deletes).
  final Future<JournalItem?> Function(
    String title,
    String body,
    JournalItem? existing,
  )
  onSave;
  final Future<void> Function(JournalItem) onDelete;

  /// Back to the task list, from the list state's header.
  final VoidCallback onBack;

  @override
  State<JournalView> createState() => _JournalViewState();
}

class _JournalViewState extends State<JournalView> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _title = TextEditingController();
  final _body = NoteController();

  /// Tab from the title goes to the body, not to the next button along: the
  /// body is the only place anyone tabbing out of a title is going.
  late final _titleFocus = FocusNode(
    onKeyEvent: (node, e) {
      if (e is! KeyDownEvent ||
          e.logicalKey != LogicalKeyboardKey.tab ||
          HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      _bodyFocus.requestFocus();
      return KeyEventResult.handled;
    },
  );
  final _bodyFocus = FocusNode();

  /// The pane's own node, so the reader can hold focus.
  ///
  /// The editor never needed one: a text field inside it takes primary focus
  /// and every key event bubbles up through here on its way out. The reader has
  /// no field, so without this the pane is not on the focus path at all and Esc
  /// falls through to the shell - which closes the whole journal, skipping the
  /// list rung the ladder exists for.
  final _paneFocus = FocusNode(debugLabel: 'journal pane');

  late bool _editorOpen = widget.startNew;
  bool _reading = false;

  /// The ⛶ in the reader or the editor: everything but the note's title and
  /// text goes. It carries across reading and editing the one note, and every
  /// note opened from the list starts out of it (Marco, 2026-10-18).
  bool _focused = false;

  bool get _inFocus => _focused && (_editorOpen || _reading);

  void _setFocus(bool on) => setState(() => _focused = on);

  /// Live for [kDoubleTapTimeout] after a click on the list opened the reader:
  /// a second click inside that window, which lands on the reader since the
  /// reader has replaced the list, opens the editor instead. Hand-rolled for
  /// the reason task_row.dart's `_clickText` is: `onDoubleTap` beside the tap
  /// would hold every single click back by the double-tap window, and opening
  /// a note to read it is the commoner of the two.
  Timer? _secondClick;
  bool _settingUp = false; // reachable "set a password" screen
  JournalItem? _editing;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _secondClick?.cancel();
    _saveDraftOnTheWayOut();
    _password.dispose();
    _confirm.dispose();
    _title.dispose();
    _body.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    _paneFocus.dispose();
    super.dispose();
  }

  /// The panel is going away with the editor open: keep what was typed.
  ///
  /// Nothing the user did asked for the words to be thrown away. Switching
  /// workspace closes every view, the calendar does too, and a window resized
  /// past a breakpoint used to rebuild this panel from scratch - each of them
  /// discarded a half-written note without a word, which from the outside is
  /// the note being deleted. Cancel is the one way to discard, and it closes
  /// the editor first, so it never reaches here.
  ///
  /// Fire and forget, because `dispose` cannot wait. Two things keep it safe:
  /// an unchanged entry writes nothing (so merely reading one and leaving costs
  /// no `updated_at` and no sync), and an entry cleared to nothing is left
  /// alone rather than saved - saving empty fields *deletes*, and deleting is
  /// not something to do on somebody's behalf while they are looking elsewhere.
  /// `onSave` is the closure from the last build, which the shell binds to the
  /// workspace the note was written in rather than the one just switched to.
  void _saveDraftOnTheWayOut() {
    if (!_editorOpen || _busy) return;
    final title = _title.text;
    final body = _body.text;
    if (title.trim().isEmpty && body.trim().isEmpty) return;
    final existing = _editing;
    if (existing != null &&
        existing.title.trim() == title.trim() &&
        existing.body.trim() == body.trim()) {
      return;
    }
    widget.onSave(title, body, existing);
  }

  @override
  void initState() {
    super.initState();
    if (widget.startNew && !widget.locked) _focusTitle();
  }

  /// The caret into a new entry's title. Asked for outright, after the frame
  /// that builds the field: the field's `autofocus` gives way to the shell's
  /// key handler, which always holds focus (ThoughtSheet's reason).
  void _focusTitle() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _titleFocus.requestFocus();
    });
  }

  /// Put the keyboard on the pane itself. The state it is being asked for is
  /// built by the setState that calls this, so the request waits for the frame.
  void _focusPane() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _paneFocus.requestFocus();
    });
  }

  // --------------------------------------------------------------- lock flow

  Future<void> _setup() async {
    final pw = _password.text;
    if (pw.isEmpty) {
      setState(() => _error = 'Choose a password.');
      return;
    }
    if (pw != _confirm.text) {
      setState(() => _error = 'The two entries do not match.');
      return;
    }
    setState(() => _busy = true);
    await widget.onSetup(pw);
    _password.clear();
    _confirm.clear();
    if (mounted) {
      setState(() {
        _busy = false;
        _settingUp = false;
        _error = null;
      });
    }
  }

  Future<void> _unlock() async {
    final pw = _password.text;
    if (pw.isEmpty) return;
    setState(() => _busy = true);
    final ok = await widget.onUnlock(pw);
    _password.clear();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = ok ? null : 'Wrong password.';
    });
    if (ok && _editorOpen && _editing == null) _focusTitle();
  }

  Future<void> _confirmRemove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: T.bgSolid,
        title: const Text(
          'Remove password?',
          style: TextStyle(fontSize: T.fsMenu),
        ),
        content: const Text(
          'The notes will be stored unencrypted and readable without a password.',
          style: TextStyle(fontSize: T.fsLabel, color: T.muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => _busy = true);
    await widget.onRemovePassword();
    if (mounted) setState(() => _busy = false);
  }

  // ------------------------------------------------------------- editor flow

  /// A blank entry has nothing to read, so it opens in the fields.
  void _openNew() {
    _title.clear();
    _body.clear();
    setState(() {
      _focused = false;
      _editing = null;
      _editorOpen = true;
      _reading = false;
    });
    _focusTitle();
  }

  /// Picking one from the list *reads* it.
  /// A click on the list: read the entry at once, and arm the double-click.
  void _clickRow(JournalItem item) {
    _openExisting(item);
    if (!_reading) return;
    _secondClick?.cancel();
    _secondClick = Timer(kDoubleTapTimeout, () => _secondClick = null);
  }

  /// A pointer went down on the reader. Inside the double-click window it is
  /// the second click of one gesture, so it edits.
  void _readerPointerDown(PointerDownEvent _) {
    final armed = _secondClick;
    if (armed == null || !armed.isActive) return;
    armed.cancel();
    _secondClick = null;
    _edit();
  }

  void _openExisting(JournalItem item) {
    if (item.locked) return; // cannot be read here, so cannot be opened
    _title.text = item.title;
    _body.text = item.body;
    setState(() {
      _focused = false;
      _editing = item;
      _editorOpen = false;
      _reading = true;
    });
    _focusPane();
  }

  /// The pencil on a list row: straight into the fields, caret in the body.
  void _editFromList(JournalItem item) {
    _title.text = item.title;
    _body.text = item.body;
    setState(() {
      _focused = false;
      _editing = item;
      _editorOpen = true;
      _reading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bodyFocus.requestFocus();
    });
  }

  /// The pencil, from the reader, and Ctrl+E. The caret goes in the body,
  /// as from a list row's pencil: editing a note you were reading is
  /// changing what it says, not its name.
  void _edit() {
    setState(() {
      _editorOpen = true;
      _reading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bodyFocus.requestFocus();
    });
  }

  /// Back one rung: out of the editor to whatever it was opened from. A new
  /// entry was opened from the list and has nothing to fall back to.
  void _closeEditor() {
    setState(() {
      _editorOpen = false;
      _reading = _editing != null;
    });
    if (_reading) _focusPane();
  }

  void _closeReader() => setState(() {
    _reading = false;
    _editing = null;
  });

  /// [toList] is Ctrl+Alt+S; otherwise this is Ctrl+S and the Save button, and
  /// lands on the rendered entry.
  ///
  /// The saved item is adopted as [_editing] whatever it was before, which is
  /// what makes a new entry editable again without leaving the pane: after this
  /// there is a row behind the text on screen. A null back means nothing was
  /// written (an entry cleared to nothing deletes), so there is nothing to read
  /// and the list is the only honest place to be.
  Future<void> _save({bool toList = false}) async {
    setState(() => _busy = true);
    final saved = await widget.onSave(_title.text, _body.text, _editing);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _editing = saved;
      _editorOpen = false;
      _reading = saved != null && !toList;
    });
    if (_reading) _focusPane();
  }

  Future<void> _deleteEditing() async {
    final item = _editing;
    if (item == null) {
      _closeEditor();
      return;
    }
    setState(() => _busy = true);
    await widget.onDelete(item);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _editing = null;
      _editorOpen = false;
      _reading = false;
    });
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    // Intercept Esc so it backs down one rung - out of the editor, then out of
    // the reader - before the shell uses it to close the whole journal.
    //
    // The editor's three shortcuts live here rather than on the fields: Ctrl+S
    // has to work with the caret in either field, and a CallbackShortcuts
    // around one of them only ever sees that one (the same thing the composer's
    // Ctrl+Enter comment in task_composer.dart is about).
    return Focus(
      focusNode: _paneFocus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (key == LogicalKeyboardKey.escape) {
          // Out of focus first: it is the outermost thing on screen.
          if (_inFocus) {
            _setFocus(false);
            return KeyEventResult.handled;
          }
          if (_editorOpen) {
            _closeEditor();
            return KeyEventResult.handled;
          }
          if (_reading) {
            _closeReader();
            return KeyEventResult.handled;
          }
          if (_settingUp) {
            setState(() {
              _settingUp = false;
              _error = null;
            });
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        final ctrl = HardwareKeyboard.instance.isControlPressed;
        if (_reading &&
            !_editorOpen &&
            ctrl &&
            key == LogicalKeyboardKey.keyE &&
            !HardwareKeyboard.instance.isShiftPressed &&
            !HardwareKeyboard.instance.isAltPressed) {
          _edit();
          return KeyEventResult.handled;
        }

        if (!_editorOpen || _busy) return KeyEventResult.ignored;
        if (!ctrl) return KeyEventResult.ignored;

        if (key == LogicalKeyboardKey.enter) {
          _bodyFocus.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyS) {
          _save(toList: HardwareKeyboard.instance.isAltPressed);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: _content(),
    );
  }

  /// Whether a note is in focus, told to the shell when it changes.
  ///
  /// Reported from `build` and deferred to after the frame: the shell reacts by
  /// calling setState, and doing that from inside another widget's build is the
  /// "setState called during build" crash.
  bool? _reportedFocus;
  bool? _reportedEditing;

  void _reportFocus() {
    final focus = _inFocus && !widget.locked;
    final editing = _editorOpen && !widget.locked;
    if (focus != _reportedFocus) {
      _reportedFocus = focus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFocusChanged?.call(focus);
      });
    }
    if (editing != _reportedEditing) {
      _reportedEditing = editing;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onEditingChanged?.call(editing);
      });
    }
  }

  Widget _content() {
    _reportFocus();
    if (widget.locked) return _gate(setup: false);
    if (_settingUp) return _gate(setup: true);
    if (_editorOpen) return _editor();
    // A Listener rather than a recogniser: it never enters the arena, so the
    // reader's own taps and scrolling are untouched.
    if (_reading) {
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _readerPointerDown,
        child: _reader(),
      );
    }
    return _list();
  }

  // ------------------------------------------------------------------- gate

  /// The password screen - either "set one" or "enter it". Kept as plain as a
  /// login field so it reads as routine rather than as a vault. The setup
  /// variant is cancelable (it is reached on purpose, not forced).
  Widget _gate({required bool setup}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: T.s5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            setup ? 'Set a password to lock these notes.' : 'Locked.',
            style: const TextStyle(fontSize: T.fsBody, color: T.text),
          ),
          const SizedBox(height: 12),
          _field(
            controller: _password,
            hint: 'Password',
            obscure: true,
            autofocus: true,
            onSubmitted: (_) => setup ? _setup() : _unlock(),
          ),
          if (setup) ...[
            const SizedBox(height: 8),
            _field(
              controller: _confirm,
              hint: 'Confirm password',
              obscure: true,
              onSubmitted: (_) => _setup(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(fontSize: T.fsMeta, color: T.danger),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (setup)
                _textAction(
                  'Cancel',
                  _busy
                      ? null
                      : () => setState(() {
                          _settingUp = false;
                          _error = null;
                        }),
                ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: _busy ? null : (setup ? _setup : _unlock),
                style: FilledButton.styleFrom(
                  backgroundColor: T.surfaceHover,
                  foregroundColor: T.text,
                ),
                child: Text(setup ? 'Set' : 'Unlock'),
              ),
            ],
          ),
          if (setup) ...[
            const SizedBox(height: 12),
            const Text(
              'If you forget it, these notes cannot be recovered.',
              style: TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- list

  Widget _list() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _topBar(
          right: [
            _iconButton(Icons.add, 'New', _openNew),
            if (!widget.configured)
              _iconButton(
                Icons.lock_open_outlined,
                'Set a password',
                () => setState(() => _settingUp = true),
              )
            else ...[
              _iconButton(
                Icons.no_encryption_outlined,
                'Remove password',
                _busy ? () {} : _confirmRemove,
              ),
              _iconButton(Icons.lock_outline, 'Lock', widget.onLock),
            ],
          ],
        ),
        Expanded(
          child: widget.items.isEmpty
              ? const Center(
                  child: Text(
                    'Empty.',
                    style: TextStyle(color: T.muted, fontSize: T.fsLabel),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: T.s2),
                  itemCount: widget.items.length,
                  itemBuilder: (context, i) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i > 0) const ListRule(),
                      _row(widget.items[i]),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _row(JournalItem item) => _NoteRow(
    item: item,
    onRead: () => _clickRow(item),
    onEdit: item.locked ? null : () => _editFromList(item),
  );

  // ----------------------------------------------------------------- reader

  /// An entry as it reads. The text comes from the same controllers the editor
  /// writes into rather than from [_editing], so what is on screen after a save
  /// is exactly what was saved - no second lookup that could disagree with it,
  /// and nothing to re-resolve when the list is rebuilt underneath.
  Widget _reader() {
    final untitled = _title.text.trim().isEmpty;
    final focus = _inFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (focus)
          const SizedBox(height: T.s3)
        else
          PanelHeader(
            title: 'Notes',
            onBack: _closeReader,
            backTooltip: 'Back to the list (Esc)',
            actions: [
              _focusButton(),
              _iconButton(Icons.edit_outlined, 'Edit (Ctrl+E)', _edit),
              if (_editing != null)
                _iconButton(
                  Icons.delete_outline,
                  'Delete',
                  _busy ? () {} : _deleteEditing,
                ),
            ],
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(T.s3, 0, T.s3, T.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        untitled ? 'Untitled' : _title.text.trim(),
                        style: TextStyle(
                          fontSize: T.fsBody,
                          fontWeight: T.wMedium,
                          color: untitled ? T.muted : T.text,
                        ),
                      ),
                    ),
                    if (focus) ...[
                      _iconButton(Icons.edit_outlined, 'Edit (Ctrl+E)', _edit, size: 20),
                      _focusButton(),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                // The body is a handle too, the same way a task's rendered
                // notes are: the obvious thing to do to something you are
                // reading and want to change is to touch it.
                MarkdownText(
                  _body.text,
                  style: const TextStyle(
                    fontSize: T.fsBody,
                    color: T.text,
                    height: 1.4,
                  ),
                  onTapText: _edit,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- editor

  Widget _editor() {
    final focus = _inFocus;
    return Padding(
      padding: EdgeInsets.fromLTRB(T.s3, focus ? T.s3 : 2, T.s3, T.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _title,
                  focusNode: _titleFocus,
                  // The caret starts in the title on a new entry and in the body on
                  // one being revised: the title of an existing entry is the part
                  // that is already right.
                  autofocus: _editing == null,
                  style: const TextStyle(fontSize: T.fsBody, color: T.text),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Title',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: T.s2),
                  ),
                  // Enter in a one-line field does nothing, so it may as well do the
                  // obvious thing. Ctrl+Enter does it too, from either field.
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _bodyFocus.requestFocus(),
                ),
              ),
              if (widget.onPreview != null)
                _iconButton(
                  widget.preview
                      ? Icons.vertical_split_rounded
                      : Icons.vertical_split_outlined,
                  widget.preview ? 'Hide the preview' : 'Preview beside it',
                  () => widget.onPreview!(!widget.preview),
                  size: 17,
                  lit: widget.preview,
                ),
              _focusButton(),
            ],
          ),
          const Divider(height: 8, thickness: 0.5, color: T.surfaceHover),
          Expanded(child: _bodyWithPreview()),
          if (!focus) const SizedBox(height: 6),
          if (!focus)
            Row(
              children: [
                if (_editing != null)
                  _textAction(
                    'Delete',
                    _busy ? null : _deleteEditing,
                    color: T.danger,
                  ),
                const Spacer(),
                _textAction('Cancel', _busy ? null : _closeEditor),
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Save (Ctrl+S) · Save and close (Ctrl+Alt+S)',
                  child: FilledButton(
                    onPressed: _busy ? null : () => _save(),
                    style: FilledButton.styleFrom(
                      backgroundColor: T.surfaceHover,
                      foregroundColor: T.text,
                      padding: const EdgeInsets.symmetric(
                        horizontal: T.s3,
                        vertical: T.s2,
                      ),
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _bodyWithPreview() {
    final body = NoteBody(
      controller: _body,
      focusNode: _bodyFocus,
      codeKeys: widget.codeKeys,
      autofocus: _editing != null,
      hint: 'Markdown, if you want it.',
    );
    if (!widget.preview) return body;
    final preview = ListenableBuilder(
      listenable: _body,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: T.s2),
        child: MarkdownText(
          _body.text,
          style: const TextStyle(fontSize: T.fsBody, color: T.text, height: 1.4),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        // Side by side once each half is still a column of text; below
        // that, the preview under the field.
        final beside = box.maxWidth >= 2 * 260;
        const rule = T.surfaceHover;
        return beside
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: body),
                  const VerticalDivider(width: T.s4, thickness: 0.5, color: rule),
                  Expanded(child: preview),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: body),
                  const Divider(height: T.s3, thickness: 0.5, color: rule),
                  Expanded(child: preview),
                ],
              );
      },
    );
  }

  // ------------------------------------------------------------------ pieces

  /// Into focus, or back out of it. The one control a note in focus keeps:
  /// a phone has no Esc.
  Widget _focusButton() => _inFocus
      ? _iconButton(
          Icons.fullscreen_exit_rounded,
          'Leave focus (Esc)',
          () => _setFocus(false),
          size: 20,
        )
      : _iconButton(
          Icons.fullscreen_rounded,
          'Focus: only the note on screen',
          () => _setFocus(true),
        );

  /// Only the list state carries this bar, which is what keeps the back arrow
  /// honest: from the editor, Esc backs out to the list first, so a "back to
  /// tasks" control there would skip a step the user did not ask to skip.
  Widget _topBar({required List<Widget> right}) => PanelHeader(
    title: 'Notes',
    onBack: widget.onBack,
    count: widget.items.isEmpty ? null : widget.items.length,
    actions: right,
  );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    bool autofocus = false,
    ValueChanged<String>? onSubmitted,
  }) => TextField(
    controller: controller,
    obscureText: obscure,
    autofocus: autofocus,
    style: const TextStyle(fontSize: T.fsBody),
    onSubmitted: onSubmitted,
    decoration: InputDecoration(
      isDense: true,
      hintText: hint,
      filled: true,
      fillColor: T.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: T.s2,
        vertical: T.s2,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(T.radius),
        borderSide: BorderSide.none,
      ),
    ),
  );

  Widget _iconButton(
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    double size = 15,
    bool lit = false,
  }) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(T.radius),
      child: Padding(
        padding: const EdgeInsets.all(T.s1),
        child: Icon(icon, size: size, color: lit ? T.accent : T.muted),
      ),
    ),
  );

  Widget _textAction(
    String label,
    VoidCallback? onTap, {
    Color color = T.muted,
  }) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: T.s2, vertical: T.s2),
    ),
    child: Text(label, style: const TextStyle(fontSize: T.fsLabel)),
  );

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

  /// "Jul 20, 14:32" - a plain, unremarkable timestamp.
  static String _stamp(DateTime? when) {
    if (when == null) return '';
    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    return '${_months[when.month - 1]} ${when.day}, $hh:$mm';
  }
}

/// One note in the list. A click reads it; under a mouse, hovering swaps the
/// date for *Read* and *Edit* (Marco, 2026-10-21), so editing is one click
/// rather than read-then-pencil. In place of the date rather than beside it:
/// what appears on hover must not move the title.
class _NoteRow extends StatefulWidget {
  const _NoteRow({required this.item, required this.onRead, this.onEdit});

  final JournalItem item;
  final VoidCallback onRead;
  final VoidCallback? onEdit;

  @override
  State<_NoteRow> createState() => _NoteRowState();
}

class _NoteRowState extends State<_NoteRow> {
  bool _hovered = false;

  Widget _button(IconData icon, String tip, VoidCallback onTap) => Tooltip(
    message: tip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(T.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.s1),
        child: Icon(icon, size: 16, color: T.muted),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final untitled = item.title.trim().isEmpty;
    final label = item.locked
        ? 'Locked'
        : (untitled ? 'Untitled' : item.title.trim());
    final actions = widget.onEdit != null && _hovered;
    // No tile: the entry is its text on the pane's colour, and a ListRule
    // between two says where one ends.
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onRead,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: T.s2, vertical: T.s3),
          child: Row(
            children: [
              if (item.locked) ...[
                const Icon(Icons.lock_outline, size: 12, color: T.muted),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: T.fsLabel,
                    color: (untitled || item.locked) ? T.muted : T.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Stack(
                alignment: Alignment.centerRight,
                children: [
                  Visibility(
                    visible: !actions,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: Text(
                      _JournalViewState._stamp(item.createdAtTime),
                      style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
                    ),
                  ),
                  if (actions)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _button(Icons.visibility_outlined, 'Read', widget.onRead),
                        _button(Icons.edit_outlined, 'Edit', widget.onEdit!),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
