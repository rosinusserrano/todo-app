// Capturing a side thought without showing anybody your tasks.
//
// On a desktop the footer field expands in place, and that is right: the window
// is yours, it is 340px wide in the corner of your own screen, and expanding
// keeps the list visible so you can see you are *not* adding a task.
//
// A phone is held in front of people. The moment this is most used is exactly
// the moment that matters - somebody recommends a book, you pull the phone out
// and write it down - and the inline field left the whole workspace on screen
// behind the keyboard: every task in it, the workspace's name, whatever you are
// behind on. A capture box that exposes your todo list to the person who prompted
// it is one you learn not to open.
//
// So on touch this takes the screen instead. Nothing but the thought being
// written. It is not a privacy feature in the security sense - anyone can close
// it - it is about what is *incidentally* on display while you type in company.
//
// Deliberately not the composer's shape (a panel with the list dimmed behind
// it): a barrier you can see through still shows the list. This is opaque and
// full height.
//
// Full height *below the title bar*, that is. It used to start at the top of
// the window and be drawn under the bar, which is above every sheet in the
// shell's Stack - so this pane's ✕ landed exactly under the concentration-sound
// button and pressing it started a rain sample instead of closing the pane.
// Nothing is lost by stopping at [TitleBar.height]: what the pane hides is the
// workspace name and the tasks, and both of those are *below* the bar. The bar
// itself says "Todo" and holds window controls.

import 'package:flutter/material.dart';

import '../theme.dart';
import 'title_bar.dart';

class ThoughtSheet extends StatefulWidget {
  const ThoughtSheet({
    super.key,
    required this.accent,
    required this.onAdd,
    required this.onClose,
  });

  final Color accent;

  /// Returns once the thought is stored. The sheet stays open on an empty
  /// submit rather than closing on nothing.
  final Future<void> Function(String text) onAdd;

  final VoidCallback onClose;

  @override
  State<ThoughtSheet> createState() => _ThoughtSheetState();
}

class _ThoughtSheetState extends State<ThoughtSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// How many went in this sitting. Shown rather than the pile's total: the
  /// total is the footer's job, and while this is open the point is that the
  /// last one landed - a field that empties itself is otherwise
  /// indistinguishable from one that dropped what you typed.
  int _added = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit({bool andClose = true}) async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      if (andClose) widget.onClose();
      return;
    }
    _controller.clear();
    setState(() => _added++);
    await widget.onAdd(text);
    if (!mounted) return;
    if (andClose) {
      widget.onClose();
    } else {
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return Positioned(
      top: TitleBar.height,
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        // Opaque: the workspace bar is directly under this, and a capture pane
        // that hid the tasks but not which list they were in would be missing
        // half the point.
        color: T.bgSolid,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
                  child: Row(
                    children: [
                      const Text('💭', style: TextStyle(fontSize: 17)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Side thought',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: T.text,
                          ),
                        ),
                      ),
                      if (_added > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            _added == 1 ? '1 saved' : '$_added saved',
                            style: TextStyle(
                              fontSize: 11,
                              color: widget.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      Semantics(
                        label: 'Close',
                        button: true,
                        child: InkWell(
                          onTap: widget.onClose,
                          borderRadius: BorderRadius.circular(8),
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: T.muted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: true,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(fontSize: 15, height: 1.35),
                      decoration: const InputDecoration(
                        hintText: 'What just came to mind…',
                        border: InputBorder.none,
                      ),
                      // Enter makes a new line here, unlike the footer's one-
                      // line field: this is a box you were given the whole
                      // screen for, so it would be odd if it took one line.
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                  child: Row(
                    children: [
                      // Chaining, for the case this exists for: somebody lists
                      // three books at you and closing between each is three
                      // taps you do not have time for.
                      TextButton(
                        onPressed: () => _submit(andClose: false),
                        style: TextButton.styleFrom(
                          foregroundColor: T.muted,
                          minimumSize: const Size(0, 44),
                        ),
                        child: const Text(
                          'Save & another',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.accent,
                          foregroundColor: T.bgSolid,
                          minimumSize: const Size(96, 44),
                        ),
                        child: const Text(
                          'Save',
                          style: TextStyle(
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
        ),
      ),
    );
  }
}
