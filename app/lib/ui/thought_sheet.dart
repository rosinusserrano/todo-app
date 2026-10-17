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
// It can take a glyph, a title and a hint because the *other* thing captured
// blind on a phone wants exactly this pane: the line added to the task you are
// on, from the home-screen quick action. Same shape, same reasoning - a phone
// pulled out mid-conversation to write one line down - so it is the same widget
// with three strings in it rather than a second copy that would drift.
//
// On a desktop it is the capture surface too (it used to be the footer's
// field, expanding in place, everywhere but the full-window calendar - two
// ways of doing one thing depending on what happened to be open). There the
// keys are the point: Enter saves and closes, Ctrl+Enter saves and clears for
// the next one, Shift+Enter is a new line ([enterSaves]). A phone keeps Enter
// as a new line: its keyboard has no Ctrl to chain with, and the buttons are
// under the thumb anyway.
//
// Full height *below the title bar*, that is. It used to start at the top of
// the window and be drawn under the bar, which is above every sheet in the
// shell's Stack - so this pane's ✕ landed exactly under the concentration-sound
// button and pressing it started a rain sample instead of closing the pane.
// Nothing is lost by stopping at [TitleBar.height]: what the pane hides is the
// workspace name and the tasks, and both of those are *below* the bar. The bar
// itself says "Todo" and holds window controls.
//
// **The mic records** (voice_recorder.dart), where there is a recorder and
// the pane was given [ThoughtSheet.canRecord]: tap to start, tap to stop,
// and the recording waits above the buttons to be listened to or thrown
// away until Save stores it with whatever was typed - or with nothing typed,
// which is the point. It used to be dictation, and the browser's
// transcripts were too garbled to keep (Marco, 2026-10-17). Saving while it
// runs stops it and keeps what was said; closing throws it away like the
// text.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../voice_clip.dart';
import '../voice_notes.dart';
import '../voice_recorder.dart';
import 'title_bar.dart';

class ThoughtSheet extends StatefulWidget {
  const ThoughtSheet({
    super.key,
    required this.accent,
    required this.onAdd,
    required this.onClose,
    this.glyph,
    this.title,
    this.hint,
    this.enterSaves = false,
    this.canRecord = false,
  });

  /// Draw the mic, where this build can record. Only the thought pile keeps
  /// a recording; a note on a task is text.
  final bool canRecord;

  /// Enter saves and closes, Ctrl+Enter saves and stays for another, and
  /// Shift+Enter is the new line. Off on touch, where Enter is a new line.
  final bool enterSaves;

  final Color accent;

  /// What this pane is for, in the header. Absent for a side thought, which is
  /// what it was built for and still mostly is: that pane is deliberately
  /// plain - a field and the keyboard, nothing to read first. The quick
  /// action's note-on-a-task use passes them, because it has to say which task.
  final String? glyph;
  final String? title;

  /// The empty field's prompt. Absent means none.
  final String? hint;

  /// Returns once the thought is stored. [clip] is a recording, and comes
  /// only from a pane that [canRecord]. Nothing typed and nothing recorded
  /// is not a submit.
  final Future<void> Function(String text, VoiceClip? clip) onAdd;

  final VoidCallback onClose;

  @override
  State<ThoughtSheet> createState() => _ThoughtSheetState();
}

class _ThoughtSheetState extends State<ThoughtSheet> {
  final _controller = TextEditingController();
  late final _focus = FocusNode(onKeyEvent: _onKey);

  /// Ahead of the field: a key the focused node handles never reaches the
  /// text input, so Enter here saves rather than also breaking the line.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!widget.enterSaves || e is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (e.logicalKey != LogicalKeyboardKey.enter &&
        e.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    // Mid-composition (an IME's candidate list) Enter picks the candidate.
    if (_controller.value.composing.isValid) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed) return KeyEventResult.ignored;
    _submit(andClose: !(keys.isControlPressed || keys.isMetaPressed));
    return KeyEventResult.handled;
  }

  /// How many went in this sitting. Shown rather than the pile's total: the
  /// total is the footer's job, and while this is open the point is that the
  /// last one landed - a field that empties itself is otherwise
  /// indistinguishable from one that dropped what you typed.
  int _added = 0;

  @override
  void initState() {
    super.initState();
    // Asked for outright, after the first frame. The field's `autofocus`
    // only takes focus when nothing else in the scope has it, and the shell's
    // own key handler always does - so the pane opened with the caret
    // nowhere and the first thing typed went to the list behind it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _recorder?.cancel();
    _player?.stop();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Recording, since when, and what the last recording made.
  VoiceRecorder? _recorder;
  DateTime? _recordingSince;
  VoiceClip? _clip;
  String? _recordError;

  /// Ticks the elapsed time while recording.
  Stream<int>? _ticker;

  /// The app's player, held so a draft playing when the pane goes is
  /// stopped with it.
  VoiceNotes? _player;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _player = VoiceNotesScope.maybeOf(context);
  }

  Future<void> _toggleRecording() async {
    if (_recorder != null) {
      await _stopRecording();
      _focus.requestFocus();
      return;
    }
    final rec = VoiceRecorder();
    setState(() {
      _recorder = rec;
      _recordError = null;
    });
    try {
      await rec.start();
    } catch (reason) {
      if (!mounted || _recorder != rec) return;
      setState(() {
        _recorder = null;
        _recordError = reason == 'not-allowed'
            ? 'The microphone is not allowed for this page'
            : 'Could not record ($reason)';
      });
      return;
    }
    if (!mounted || _recorder != rec) {
      rec.cancel();
      return;
    }
    // A new recording replaces one not saved yet - it was listened to and
    // found wanting, or forgotten.
    await _player?.stop();
    setState(() {
      _clip = null;
      _recordingSince = DateTime.now();
      _ticker = Stream.periodic(const Duration(seconds: 1), (i) => i);
    });
  }

  /// Stop, and keep what was said as the draft's recording.
  Future<void> _stopRecording() async {
    final rec = _recorder;
    if (rec == null) return;
    setState(() {
      _recorder = null;
      _recordingSince = null;
      _ticker = null;
    });
    final clip = await rec.stop();
    if (!mounted) return;
    if (clip != null && clip.bytes.isNotEmpty) setState(() => _clip = clip);
  }

  void _discardClip() {
    _player?.stop();
    setState(() => _clip = null);
  }

  Future<void> _submit({bool andClose = true}) async {
    // Saving ends a recording and keeps it: Save is the obvious way to say
    // "done" mid-sentence.
    if (_recorder != null) await _stopRecording();
    if (!mounted) return;
    final text = _controller.text.trim();
    final clip = _clip;
    if (text.isEmpty && clip == null) {
      if (andClose) widget.onClose();
      return;
    }
    await _player?.stop();
    _controller.clear();
    setState(() {
      _added++;
      _clip = null;
    });
    await widget.onAdd(text, clip);
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
                  padding: const EdgeInsets.fromLTRB(T.s3, T.s2, T.s2, T.s1),
                  child: Row(
                    children: [
                      if (widget.glyph != null) ...[
                        Text(
                          widget.glyph!,
                          style: const TextStyle(fontSize: 17),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: widget.title == null
                            ? const SizedBox.shrink()
                            : Text(
                                widget.title!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: T.fsMenu,
                                  fontWeight: T.wMedium,
                                  color: T.text,
                                ),
                              ),
                      ),
                      if (_added > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: T.s2),
                          child: Text(
                            _added == 1 ? '1 saved' : '$_added saved',
                            style: TextStyle(
                              fontSize: T.fsMeta,
                              color: widget.accent,
                              fontWeight: T.wMedium,
                            ),
                          ),
                        ),
                      Semantics(
                        label: 'Close',
                        button: true,
                        child: InkWell(
                          onTap: widget.onClose,
                          borderRadius: BorderRadius.circular(T.radius),
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
                    padding: const EdgeInsets.fromLTRB(T.s3, T.s1, T.s3, T.s1),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: true,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(fontSize: T.fsMenu, height: 1.35),
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        border: InputBorder.none,
                      ),
                      // Several lines are welcome: this is a box you were
                      // given the whole screen for. On a phone Enter is the
                      // new line; with a keyboard it is Shift+Enter, and
                      // Enter saves (see _onKey).
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                ),
                if (_recordError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: T.s3),
                    child: Text(
                      _recordError!,
                      style: const TextStyle(fontSize: T.fsMeta, color: T.warn),
                    ),
                  ),
                if (_clip != null || _recordingSince != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(T.s3, T.s1, T.s3, 0),
                    child: Row(
                      children: [
                        if (_recordingSince != null)
                          _Recording(
                            since: _recordingSince!,
                            ticker: _ticker,
                            color: widget.accent,
                          )
                        else ...[
                          VoiceNoteButton(clip: _clip, accent: widget.accent),
                          const SizedBox(width: T.s1),
                          Tooltip(
                            message: 'Throw the recording away',
                            child: InkWell(
                              onTap: _discardClip,
                              borderRadius: BorderRadius.circular(T.radius),
                              child: const SizedBox(
                                width: 32,
                                height: 32,
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: T.muted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(T.s3, T.s1, T.s3, T.s3),
                  child: Row(
                    children: [
                      if (widget.canRecord && VoiceRecorder.supported) ...[
                        Tooltip(
                          message: _recorder == null
                              ? 'Record a voice note'
                              : 'Stop recording',
                          child: Material(
                            color: _recorder == null
                                ? Colors.transparent
                                : widget.accent,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _toggleRecording,
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: Icon(
                                  _recorder == null
                                      ? Icons.mic_none_rounded
                                      : Icons.stop_rounded,
                                  size: 22,
                                  color: _recorder == null
                                      ? T.muted
                                      : T.inkOn(widget.accent),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: T.s1),
                      ],
                      // Chaining, for the case this exists for: somebody lists
                      // three books at you and closing between each is three
                      // taps you do not have time for.
                      Tooltip(
                        message: widget.enterSaves ? 'Ctrl+Enter' : '',
                        child: TextButton(
                          onPressed: () => _submit(andClose: false),
                          style: TextButton.styleFrom(
                            foregroundColor: T.muted,
                            minimumSize: const Size(0, 44),
                          ),
                          child: const Text(
                            'Save & another',
                            style: TextStyle(fontSize: T.fsLabel),
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (widget.enterSaves)
                        const Padding(
                          padding: EdgeInsets.only(right: T.s2),
                          child: Text(
                            'Shift+Enter: new line',
                            style: TextStyle(
                              fontSize: T.fsMeta,
                              color: T.muted,
                            ),
                          ),
                        ),
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
                            fontSize: T.fsLabel,
                            fontWeight: T.wMedium,
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

/// ● 0:12 - the recording running, counted from [since].
class _Recording extends StatelessWidget {
  const _Recording({
    required this.since,
    required this.ticker,
    required this.color,
  });

  final DateTime since;
  final Stream<int>? ticker;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: ticker,
      builder: (context, _) {
        final secs = DateTime.now().difference(since).inSeconds;
        final time = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: T.s2),
            Text(
              'Recording $time',
              style: const TextStyle(
                fontSize: T.fsLabel,
                color: T.text,
                fontWeight: T.wMedium,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      },
    );
  }
}
