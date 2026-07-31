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
// body field, and Cancel / Save. Esc backs out of the editor before the journal.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../theme.dart';
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
  });

  /// A password has been set (encryption is on).
  final bool configured;

  /// Configured but not unlocked this session - show the unlock prompt.
  final bool locked;

  final List<JournalItem> items;

  final Future<void> Function(String password) onSetup;
  final Future<bool> Function(String password) onUnlock;
  final VoidCallback onLock;
  final Future<void> Function() onRemovePassword;

  /// [existing] null means a new entry.
  final Future<void> Function(String title, String body, JournalItem? existing)
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
  final _body = TextEditingController();

  bool _editorOpen = false;
  bool _settingUp = false; // reachable "set a password" screen
  JournalItem? _editing;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
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
  }

  Future<void> _confirmRemove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: T.bgSolid,
        title: const Text('Remove password?', style: TextStyle(fontSize: 15)),
        content: const Text(
          'The notes will be stored unencrypted and readable without a password.',
          style: TextStyle(fontSize: 12.5, color: T.muted, height: 1.4),
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

  void _openNew() {
    _title.clear();
    _body.clear();
    setState(() {
      _editing = null;
      _editorOpen = true;
    });
  }

  void _openExisting(JournalItem item) {
    if (item.locked) return; // cannot be read here, so cannot be opened
    _title.text = item.title;
    _body.text = item.body;
    setState(() {
      _editing = item;
      _editorOpen = true;
    });
  }

  void _closeEditor() => setState(() => _editorOpen = false);

  Future<void> _save() async {
    setState(() => _busy = true);
    await widget.onSave(_title.text, _body.text, _editing);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _editorOpen = false;
    });
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
      _editorOpen = false;
    });
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    // Intercept Esc so it backs out of the editor (or the set-password screen)
    // before the shell uses it to close the whole journal.
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (_editorOpen) {
            _closeEditor();
            return KeyEventResult.handled;
          }
          if (_settingUp) {
            setState(() {
              _settingUp = false;
              _error = null;
            });
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: _content(),
    );
  }

  Widget _content() {
    if (widget.locked) return _gate(setup: false);
    if (_settingUp) return _gate(setup: true);
    if (_editorOpen) return _editor();
    return _list();
  }

  // ------------------------------------------------------------------- gate

  /// The password screen - either "set one" or "enter it". Kept as plain as a
  /// login field so it reads as routine rather than as a vault. The setup
  /// variant is cancelable (it is reached on purpose, not forced).
  Widget _gate({required bool setup}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            setup ? 'Set a password to lock these notes.' : 'Locked.',
            style: const TextStyle(fontSize: 13, color: T.text),
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
            Text(_error!,
                style: const TextStyle(fontSize: 11.5, color: T.danger)),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (setup)
                _textAction('Cancel', _busy
                    ? null
                    : () => setState(() {
                          _settingUp = false;
                          _error = null;
                        })),
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
              style: TextStyle(fontSize: 11, color: T.muted, height: 1.4),
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
                  Icons.lock_open_outlined, 'Set a password',
                  () => setState(() => _settingUp = true))
            else ...[
              _iconButton(
                  Icons.no_encryption_outlined, 'Remove password',
                  _busy ? () {} : _confirmRemove),
              _iconButton(Icons.lock_outline, 'Lock', widget.onLock),
            ],
          ],
        ),
        Expanded(
          child: widget.items.isEmpty
              ? const Center(
                  child: Text(
                    'Empty.',
                    style: TextStyle(color: T.muted, fontSize: 12.5),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: widget.items.length,
                  itemBuilder: (context, i) => _row(widget.items[i]),
                ),
        ),
      ],
    );
  }

  Widget _row(JournalItem item) {
    final untitled = item.title.trim().isEmpty;
    final label = item.locked
        ? 'Locked'
        : (untitled ? 'Untitled' : item.title.trim());
    return InkWell(
      onTap: () => _openExisting(item),
      borderRadius: BorderRadius.circular(7),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(7),
        ),
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
                  fontSize: 12.5,
                  color: (untitled || item.locked) ? T.muted : T.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _stamp(item.createdAtTime),
              style: const TextStyle(fontSize: 10.5, color: T.muted),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- editor

  Widget _editor() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            style: const TextStyle(fontSize: 14, color: T.text),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Title',
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 6),
            ),
          ),
          const Divider(height: 8, thickness: 0.5, color: T.surfaceHover),
          Expanded(
            child: TextField(
              controller: _body,
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontSize: 13, color: T.text, height: 1.4),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 6),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (_editing != null)
                _textAction('Delete', _busy ? null : _deleteEditing,
                    color: T.danger),
              const Spacer(),
              _textAction('Cancel', _busy ? null : _closeEditor),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: T.surfaceHover,
                  foregroundColor: T.text,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ pieces

  /// Only the list state carries this bar, which is what keeps the back arrow
  /// honest: from the editor, Esc backs out to the list first, so a "back to
  /// tasks" control there would skip a step the user did not ask to skip.
  Widget _topBar({required List<Widget> right}) => PanelHeader(
        title: 'Notes',
        onBack: widget.onBack,
        actions: right,
      );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    bool autofocus = false,
    ValueChanged<String>? onSubmitted,
  }) =>
      TextField(
        controller: controller,
        obscureText: obscure,
        autofocus: autofocus,
        style: const TextStyle(fontSize: 13),
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          filled: true,
          fillColor: T.surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide.none,
          ),
        ),
      );

  Widget _iconButton(IconData icon, String tooltip, VoidCallback onTap) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 15, color: T.muted),
          ),
        ),
      );

  Widget _textAction(String label, VoidCallback? onTap, {Color color = T.muted}) =>
      TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12.5)),
      );

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// "Jul 20, 14:32" - a plain, unremarkable timestamp.
  static String _stamp(DateTime? when) {
    if (when == null) return '';
    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    return '${_months[when.month - 1]} ${when.day}, $hh:$mm';
  }
}
