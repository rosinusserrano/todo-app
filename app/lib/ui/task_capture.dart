// The add card: where a new task is written.
//
// The "Add a task" line at the head of the list is the field folded. Opening
// it - a click on that line, the dock's ＋, N - lifts it out of the list and
// flies it to the middle of the window, growing as it goes, with the list
// dimmed behind. Under the title sit the settings a task most often needs at
// birth: priority, a reminder, which workspace it goes on, and ⤢ for the
// full composer.
//
// The title can also carry those settings itself (task_keywords.dart): a
// `#workspace`, a date, a time. What was recognised is highlighted in the
// field and shows on its button in the bar with a × that hands the word back
// to the title. Choosing a setting by hand does the same for that kind - a
// hand-picked reminder is not overridden by the "9:30" the title happens to
// contain.
//
// A recognised `#workspace` offers **a shortcut** - "#MT" for "#Master
// thesis" - in a small pill under the word, while the mouse is on it or the
// caret is in it (a finger has no hover). The pill is a `TextFieldTapRegion`,
// so a tap on it counts as inside the field and does not take the caret
// away - which would hide the pill under the finger before the tap landed.
//
// Keys, on a keyboard: **Enter adds and closes, Ctrl+Enter adds and stays
// open for the next one, Shift+Enter is a new line** - ThoughtSheet's keys.
// They are taken on the way up from the field (`_onKey`), so a handled Enter
// never reaches the text input as a line break. A phone's return key is
// "Done", which adds and closes.
//
// Things about it that are load-bearing:
//
// - **The card is always in the shell's Stack** and draws nothing while
//   closed. Its State is what holds the draft's priority, reminder and
//   workspace between openings, and an exit animation needs a widget still in
//   the tree to run in (the same reason `SheetTransition` keeps its child).
// - **The flight is laid out, not transformed.** `_FlightLayout` interpolates
//   the box from the folded line's rect to a centred column, and the card's
//   contents lay out at every width along the way - a scale transform would
//   stretch the text, the same reason focus mode lerps a `Rect`.
// - **The origin is read when the flight starts, in both directions.** The
//   list can have moved between opening and closing (a task added above, a
//   resize), and landing on where the line *was* would jump at the end.
// - **The controller belongs to the shell.** Closing keeps what was typed,
//   and the folded line shows it, so nothing half-written is lost to a tap on
//   the dimmed list.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../layout.dart';
import '../sync/models.dart';
import '../task_keywords.dart';
import '../theme.dart';
import 'form_sheet.dart';
import 'reminder_menu.dart';
import 'title_bar.dart';

/// What the card hands back: the title with its keywords taken out, and the
/// settings, hand-picked or read from the text. A null workspace is "here".
class CaptureResult {
  const CaptureResult({
    required this.title,
    this.workspaceUuid,
    this.priority = 0,
    this.remindAt,
    this.project = false,
  });

  final String title;
  final String? workspaceUuid;
  final int priority;
  final DateTime? remindAt;

  /// Add a project of this name rather than a task. Priority and reminder
  /// are not offered then: they belong to the project's tasks.
  final bool project;
}

/// A text controller that draws the recognised keywords highlighted.
///
/// [parser] and [colorOf] are installed by the card, which knows the
/// workspaces and which kinds are switched off; until then this is a plain
/// controller. The parse is cached per text, because a build reads it more
/// than once and the card reads it again for the bar.
class KeywordController extends TextEditingController {
  KeywordController({super.text});

  KeywordParse Function(String text)? parser;
  Color Function(KeywordSpan span)? colorOf;

  String? _parsedText;
  KeywordParse? _parsed;

  KeywordParse get parse {
    final p = parser;
    if (p == null) return KeywordParse(title: text.trim());
    if (_parsedText != text || _parsed == null) {
      _parsed = p(text);
      _parsedText = text;
    }
    return _parsed!;
  }

  /// Throw the cached parse away - the rules changed under the same text.
  /// Deliberately does not notify: it is called from the card's build path,
  /// and the card rebuilding is what redraws the field.
  void invalidate() => _parsed = null;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final spans = parse.spans;
    final colorOf = this.colorOf;
    // Mid-composition (an IME, a phone's suggestion strip) the composing
    // underline matters more than the colours, and drawing both is a fight.
    if (spans.isEmpty ||
        colorOf == null ||
        (withComposing && value.isComposingRangeValid)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final children = <TextSpan>[];
    var at = 0;
    for (final s in spans) {
      // "tonight" is two spans over one range; draw it once.
      if (s.start < at || s.end > text.length) continue;
      if (s.start > at) {
        children.add(TextSpan(text: text.substring(at, s.start)));
      }
      final c = colorOf(s);
      children.add(
        TextSpan(
          text: text.substring(s.start, s.end),
          style: TextStyle(
            color: c,
            background: Paint()..color = c.withValues(alpha: 0.18),
          ),
        ),
      );
      at = s.end;
    }
    if (at < text.length) children.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: children);
  }
}

class TaskCapture extends StatefulWidget {
  const TaskCapture({
    super.key,
    required this.open,
    required this.controller,
    required this.focusNode,
    required this.workspaces,
    required this.hereUuid,
    required this.layout,
    required this.originOf,
    required this.onSubmit,
    required this.onExpand,
    required this.onClose,
    required this.onClosed,
    required this.onAddShortcut,
  });

  final bool open;
  final KeywordController controller;
  final FocusNode focusNode;
  final List<Workspace> workspaces;

  /// The workspace on screen: what "no workspace chosen" means.
  final String? hereUuid;
  final Layout layout;

  /// Where the folded line is, in this widget's coordinates, or null when it
  /// is not on screen (another view is up) - the card then rises from the
  /// bottom edge, where the dock's ＋ is.
  final Rect? Function() originOf;

  final Future<void> Function(CaptureResult result) onSubmit;

  /// The full composer. Resolves true when it wrote the task, and the card
  /// then empties and closes.
  final Future<bool> Function(CaptureResult result) onExpand;

  /// Asked to close: the scrim, Enter on nothing.
  final VoidCallback onClose;

  /// The flight home has landed - the folded line can be drawn again.
  final VoidCallback onClosed;

  /// Store [shortcut] (already checked, without its `#`) on a workspace.
  final Future<void> Function(String workspaceUuid, String shortcut)
  onAddShortcut;

  @override
  State<TaskCapture> createState() => _TaskCaptureState();
}

class _TaskCaptureState extends State<TaskCapture>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flight;
  Rect? _origin;

  int _priority = 0;

  /// The folder on the bar: what is added is a project, not a task. Forgotten
  /// after each add, like the priority - a project is the exception.
  bool _project = false;

  /// Chosen by hand. Either one switches its kind of keyword off.
  DateTime? _remindAt;
  String? _workspace;

  /// A recognised word was handed back to the title with its ×.
  bool _ignoreWorkspaceWord = false;
  bool _ignoreDateWords = false;

  String? _addedTo;
  Timer? _addedToTimer;

  /// A menu is open from the bar. It is a route, so the field loses focus
  /// to it; this is what puts the caret back afterwards.
  bool _menuOpen = false;

  final _reminderKey = GlobalKey();
  final _workspaceKey = GlobalKey();

  /// Around the field, to find its `RenderEditable` for where a word is.
  final _fieldKey = GlobalKey();

  /// The box the shortcut pill is placed in.
  final _stackKey = GlobalKey();

  /// The `#workspace` under the mouse, and whether the mouse is on the pill.
  /// Leaving the word waits a moment before the pill goes, so the mouse can
  /// cross the gap to it (the dock's hover menus do the same).
  KeywordSpan? _hoverSpan;
  bool _overPill = false;
  Timer? _hoverTimer;

  /// Where the pill goes, in [_stackKey]'s space: under the word's start.
  Offset? _pillAt;

  @override
  void initState() {
    super.initState();
    // In initState, not a late final: see SheetTransition - a card never
    // opened would first touch it from dispose.
    _flight = AnimationController(vsync: this, duration: T.heroDur)
      ..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) widget.onClosed();
      });
    _install();
    widget.controller.addListener(_onText);
    if (widget.open) _fly(true);
  }

  @override
  void didUpdateWidget(TaskCapture old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
    _install();
    if (old.open != widget.open) _fly(widget.open);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _addedToTimer?.cancel();
    _hoverTimer?.cancel();
    _flight.dispose();
    super.dispose();
  }

  void _install() {
    final c = widget.controller
      ..parser = _parse
      ..colorOf = _colorOf;
    // The workspaces or the rules may have changed under the same text.
    c.invalidate();
  }

  KeywordParse _parse(String text) => parseTaskKeywords(
    text,
    now: DateTime.now(),
    workspaces: widget.workspaces,
    matchWorkspaces: _workspace == null && !_ignoreWorkspaceWord,
    matchDates: _remindAt == null && !_ignoreDateWords,
  );

  Color _colorOf(KeywordSpan span) {
    if (span.kind == KeywordKind.workspace) {
      final w = _workspaceById(span.workspaceUuid);
      if (w != null) return T.parseHex(w.color);
    }
    return T.accent;
  }

  Workspace? _workspaceById(String? uuid) {
    if (uuid == null) return null;
    for (final w in widget.workspaces) {
      if (w.uuid == uuid) return w;
    }
    return null;
  }

  /// An emptied field forgets the words it handed back: the next title is a
  /// new sentence.
  void _onText() {
    if (widget.controller.text.isEmpty &&
        (_ignoreWorkspaceWord || _ignoreDateWords)) {
      _ignoreWorkspaceWord = false;
      _ignoreDateWords = false;
      widget.controller.invalidate();
    }
    if (mounted) setState(() {});
  }

  void _fly(bool open) {
    _origin = widget.originOf();
    if (open) {
      _flight.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.open) widget.focusNode.requestFocus();
      });
    } else {
      widget.focusNode.unfocus();
      _flight.reverse();
    }
  }

  CaptureResult get _result {
    final p = widget.controller.parse;
    var ws = _workspace ?? p.workspaceUuid;
    if (ws == widget.hereUuid || _workspaceById(ws) == null) ws = null;
    return CaptureResult(
      title: p.title,
      workspaceUuid: ws,
      priority: _project ? 0 : _priority,
      remindAt: _project ? null : _remindAt ?? p.remindAt,
      project: _project,
    );
  }

  /// Ready for the next task. The workspace stays when the card does: several
  /// tasks in a row are usually for the same place.
  void _resetForNext() {
    _priority = 0;
    _project = false;
    _remindAt = null;
    _ignoreWorkspaceWord = false;
    _ignoreDateWords = false;
    widget.controller
      ..invalidate()
      ..clear();
  }

  /// Adds the task. [stay] keeps the card open for the next one (Ctrl+Enter);
  /// otherwise it closes, and a hand-picked workspace goes with it - the
  /// next time the card opens is a new sitting.
  Future<void> _submit({bool stay = false}) async {
    final r = _result;
    if (r.title.trim().isEmpty) {
      widget.onClose();
      return;
    }
    if (!stay) _workspace = null;
    _resetForNext();
    if (!stay) widget.onClose();
    await widget.onSubmit(r);
    if (!mounted || !stay) return;
    final w = _workspaceById(r.workspaceUuid);
    if (w != null) _sayAddedTo(w.name);
    widget.focusNode.requestFocus();
  }

  /// On the way up from the field: see the header for the three Enters.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey != LogicalKeyboardKey.enter &&
        e.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    // Mid-composition (an IME's candidate list) Enter picks the candidate.
    if (widget.controller.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed) return KeyEventResult.ignored;
    _submit(stay: keys.isControlPressed || keys.isMetaPressed);
    return KeyEventResult.handled;
  }

  // ------------------------------------------------------------- shortcuts

  RenderEditable? _editable() {
    RenderEditable? found;
    void visit(RenderObject o) {
      if (found != null) return;
      if (o is RenderEditable) {
        found = o;
        return;
      }
      o.visitChildren(visit);
    }

    final root = _fieldKey.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  /// The word's boxes in the editable's own space.
  List<Rect> _boxesOf(RenderEditable editable, KeywordSpan span) => [
    for (final b in editable.getBoxesForSelection(
      TextSelection(baseOffset: span.start, extentOffset: span.end),
    ))
      b.toRect(),
  ];

  void _onHover(PointerHoverEvent e) {
    final editable = _editable();
    if (editable == null) return;
    final local = editable.globalToLocal(e.position);
    KeywordSpan? hit;
    for (final span in widget.controller.parse.spans) {
      if (span.kind != KeywordKind.workspace) continue;
      if (_boxesOf(editable, span).any((r) => r.inflate(2).contains(local))) {
        hit = span;
      }
    }
    if (hit != null) {
      _hoverTimer?.cancel();
      if (_hoverSpan?.start != hit.start || _hoverSpan?.end != hit.end) {
        setState(() => _hoverSpan = hit);
      }
    } else if (_hoverSpan != null) {
      _leaveSoon();
    }
  }

  void _leaveSoon() {
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && !_overPill) setState(() => _hoverSpan = null);
    });
  }

  /// The `#workspace` the caret is in or at the end of, while typing.
  KeywordSpan? _caretSpan() {
    if (!widget.focusNode.hasFocus) return null;
    final sel = widget.controller.selection;
    if (!sel.isValid || !sel.isCollapsed) return null;
    for (final span in widget.controller.parse.spans) {
      if (span.kind != KeywordKind.workspace) continue;
      if (sel.baseOffset >= span.start && sel.baseOffset <= span.end) {
        return span;
      }
    }
    return null;
  }

  KeywordSpan? get _pillSpan {
    final hovered = _hoverSpan;
    // The text can change under a hover; only a word still recognised counts.
    if (hovered != null &&
        widget.controller.parse.spans.any(
          (s) =>
              s.kind == KeywordKind.workspace &&
              s.start == hovered.start &&
              s.end == hovered.end,
        )) {
      return hovered;
    }
    return _caretSpan();
  }

  /// Where the pill goes is a question about the last layout, so it is
  /// answered after the frame and set if it moved.
  void _placePill() {
    if (!mounted) return;
    final span = _pillSpan;
    final editable = _editable();
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    Offset? at;
    if (span != null && editable != null && stack != null) {
      final boxes = _boxesOf(editable, span);
      if (boxes.isNotEmpty) {
        at = stack.globalToLocal(
          editable.localToGlobal(boxes.first.bottomLeft),
        );
      }
    }
    if (at != _pillAt) setState(() => _pillAt = at);
  }

  Future<void> _addShortcut(KeywordSpan span) async {
    final w = _workspaceById(span.workspaceUuid);
    if (w == null) return;
    _menuOpen = true;
    final shortcut = await showFormSheet<String>(
      context,
      builder: (context, layout) => _ShortcutSheet(
        layout: layout,
        workspace: w,
        workspaces: widget.workspaces,
      ),
    );
    _menuOpen = false;
    if (!mounted) return;
    setState(() {
      _hoverSpan = null;
      _overPill = false;
    });
    if (shortcut != null) await widget.onAddShortcut(w.uuid, shortcut);
    if (mounted && widget.open) widget.focusNode.requestFocus();
  }

  Widget _pill(KeywordSpan span, Offset at) {
    final w = _workspaceById(span.workspaceUuid);
    final color = w == null ? T.accent : T.parseHex(w.color);
    return Positioned(
      left: math.max(0, at.dx),
      top: at.dy + 2,
      child: TextFieldTapRegion(
        child: MouseRegion(
          onEnter: (_) {
            _overPill = true;
            _hoverTimer?.cancel();
          },
          onExit: (_) {
            _overPill = false;
            _leaveSoon();
          },
          child: Material(
            color: T.bgSolid,
            elevation: 2,
            borderRadius: BorderRadius.circular(T.radius),
            child: InkWell(
              onTap: () => _addShortcut(span),
              borderRadius: BorderRadius.circular(T.radius),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: T.s2,
                  vertical: widget.layout.touch ? T.s2 : T.s1,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 14, color: color),
                    const SizedBox(width: T.s1),
                    Text(
                      w == null || w.shortcuts.isEmpty
                          ? 'Shortcut'
                          : 'Shortcut (${w.shortcuts.map((x) => '#$x').join(' ')})',
                      style: const TextStyle(fontSize: T.fsMeta, color: T.text),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _expand() async {
    if (_project) return;
    final done = await widget.onExpand(_result);
    if (!mounted) return;
    if (done) {
      _workspace = null;
      _resetForNext();
    } else if (widget.open) {
      widget.focusNode.requestFocus();
    }
  }

  void _sayAddedTo(String name) {
    _addedToTimer?.cancel();
    setState(() => _addedTo = name);
    _addedToTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _addedTo = null);
    });
  }

  void _setRules(VoidCallback change) {
    widget.controller.invalidate();
    setState(change);
  }

  /// A menu's anchor, in the overlay's space rather than the screen's:
  /// UiScale sits above the Navigator (see taskActionAnchor).
  RelativeRect? _anchor(GlobalKey key) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (overlay == null || box == null) return null;
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    return RelativeRect.fromRect(
      Rect.fromLTWH(rect.left, rect.bottom, rect.width, 0),
      Offset.zero & overlay.size,
    );
  }

  Future<void> _pickReminder() async {
    final at = _anchor(_reminderKey);
    if (at == null) return;
    _menuOpen = true;
    await showReminderMenu(
      context: context,
      position: at,
      armed: _remindAt ?? widget.controller.parse.remindAt,
      onChosen: (chosen) async {
        // Chosen by hand, a reminder and its absence both outrank the text.
        _setRules(() {
          _remindAt = chosen;
          _ignoreDateWords = chosen == null;
        });
      },
    );
    _menuOpen = false;
    if (mounted && widget.open) widget.focusNode.requestFocus();
  }

  Future<void> _pickWorkspace() async {
    final at = _anchor(_workspaceKey);
    if (at == null) return;
    final current = _result.workspaceUuid ?? widget.hereUuid;
    _menuOpen = true;
    final picked = await showMenu<String>(
      context: context,
      color: T.bgSolid,
      position: at,
      items: [
        for (final w in widget.workspaces)
          PopupMenuItem<String>(
            value: w.uuid,
            height: 38,
            child: Row(
              children: [
                // A project sits under its workspace, one step in.
                if (w.isProject) const SizedBox(width: T.s4),
                _Dot(T.parseHex(w.color)),
                const SizedBox(width: T.s2),
                Expanded(
                  child: Text(
                    w.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: T.fsLabel,
                      color: w.uuid == current ? T.text : T.muted,
                      fontWeight: w.uuid == current ? T.wMedium : T.wNormal,
                    ),
                  ),
                ),
                if (w.uuid == widget.hereUuid)
                  const Text(
                    'this one',
                    style: TextStyle(fontSize: T.fsMeta, color: T.muted),
                  ),
              ],
            ),
          ),
      ],
    );
    _menuOpen = false;
    if (!mounted) return;
    if (picked != null) _setRules(() => _workspace = picked);
    if (widget.open) widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flight,
      builder: (context, _) {
        final v = _flight.value;
        if (v == 0 && !widget.open) return const SizedBox.shrink();
        final t = T.heroEase.transform(v);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _menuOpen ? null : widget.onClose,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.45 * t),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomSingleChildLayout(
                delegate: _FlightLayout(
                  t: t,
                  origin: _origin,
                  topInset: TitleBar.height,
                ),
                child: _card(t),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _card(double t) {
    final here = _workspaceById(widget.hereUuid);
    final hereColor = here == null ? T.accent : T.parseHex(here.color);
    final fill = Color.lerp(
      T.surface,
      Color.lerp(T.bgSolid, hereColor, 0.12)!,
      t,
    )!;
    // The bar arrives in the second half of the flight, growing out of the
    // card's foot, so the first half reads as the line lifting off.
    final barT = ((t - 0.35) / 0.65).clamp(0.0, 1.0);

    return Material(
      color: fill,
      elevation: 8 * t,
      shadowColor: Colors.black,
      borderRadius: BorderRadius.circular(T.radius),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.lerp(
          const EdgeInsets.all(T.s2),
          const EdgeInsets.fromLTRB(T.s4, T.s4, T.s3, T.s3),
          t,
        )!,
        child: Stack(
          key: _stackKey,
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(t, hereColor),
                ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: barT,
                    child: Opacity(opacity: barT, child: _below(hereColor)),
                  ),
                ),
              ],
            ),
            if (t == 1 && _pillSpan != null && _pillAt != null)
              _pill(_pillSpan!, _pillAt!),
          ],
        ),
      ),
    );
  }

  Widget _field(double t, Color hereColor) {
    if (t == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _placePill());
    }
    final touch = widget.layout.touch;
    final field = TextField(
      key: _fieldKey,
      controller: widget.controller,
      focusNode: widget.focusNode,
      // A finger's return key is Done; a keyboard's Shift+Enter is a line.
      maxLines: null,
      keyboardType: touch ? TextInputType.text : TextInputType.multiline,
      textInputAction: touch ? TextInputAction.done : TextInputAction.newline,
      textCapitalization: TextCapitalization.sentences,
      // The display face: on the card the title is the thing being named,
      // and it is set the way a view's name is. Grows with the flight.
      style: TextStyle(
        fontFamily: T.fontDisplay,
        fontSize: lerpDouble(T.fsBody, T.fsTitle, t),
        color: T.text,
      ),
      decoration: const InputDecoration(
        isDense: true,
        hintText: 'Add a task',
        hintStyle: TextStyle(color: T.muted),
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
      onSubmitted: (_) => _submit(),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): _expand,
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          onHover: _onHover,
          onExit: (_) {
            if (_hoverSpan != null) _leaveSoon();
          },
          child: _fieldRow(t, hereColor, field),
        ),
      ),
    );
  }

  Widget _fieldRow(double t, Color hereColor, Widget field) {
    return Row(
      children: [
        // The folded line's ＋, giving way as the card opens, so the text
        // does not jump sideways at either end of the flight.
        SizedBox(
          width: (16 + T.s2) * (1 - t),
          child: Opacity(
            opacity: 1 - t,
            child: Icon(Icons.add_rounded, size: 16, color: hereColor),
          ),
        ),
        Expanded(child: field),
      ],
    );
  }

  /// Under the title: a line of help or "Added to", then the bar.
  Widget _below(Color hereColor) {
    final p = widget.controller.parse;
    final empty = widget.controller.text.trim().isEmpty;
    final note = _addedTo != null
        ? 'Added to $_addedTo'
        : empty
        ? 'A #workspace, a day or a time in the title sets it'
        : null;

    return Padding(
      padding: const EdgeInsets.only(top: T.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 16,
            child: note == null
                ? null
                : Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
                  ),
          ),
          const SizedBox(height: T.s2),
          _bar(p, empty, hereColor),
        ],
      ),
    );
  }

  Widget _bar(KeywordParse p, bool empty, Color hereColor) {
    final remindAt = _remindAt ?? p.remindAt;
    final remindFromWord = _remindAt == null && p.remindAt != null;
    final wsUuid = _workspace ?? p.workspaceUuid;
    final target = _workspaceById(wsUuid) ?? _workspaceById(widget.hereUuid);
    final wsFromWord = _workspace == null && p.workspaceUuid != null;
    final wsColor = target == null ? hereColor : T.parseHex(target.color);
    final size = widget.layout.touch ? 36.0 : 30.0;

    // The settings wrap rather than squeeze: "tomorrow 09:30" ellipsed to
    // "tomor…" says nothing, and at 340px the workspace's name and the
    // reminder do not both fit beside the two actions. A second line is
    // cheap on a card in the middle of the screen.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Wrap(
            spacing: T.s1,
            runSpacing: T.s1,
            children: [
              if (!_project)
                _BarButton(
                  tooltip: _priority > 0
                      ? 'High priority'
                      : 'Mark high priority',
                  height: size,
                  lit: _priority > 0,
                  color: T.flagged,
                  icon: _priority > 0
                      ? Icons.flag_rounded
                      : Icons.outlined_flag_rounded,
                  onTap: () =>
                      setState(() => _priority = _priority > 0 ? 0 : 1),
                ),
              if (!_project)
                _BarButton(
                  key: _reminderKey,
                  tooltip: 'Reminder',
                  height: size,
                  lit: remindAt != null,
                  color: T.accent,
                  icon: remindAt == null
                      ? Icons.notifications_none_rounded
                      : Icons.notifications_active_rounded,
                  label: remindAt == null ? null : describeReminder(remindAt),
                  onTap: _pickReminder,
                  onDismiss: remindFromWord
                      ? () => _setRules(() => _ignoreDateWords = true)
                      : null,
                ),
              _BarButton(
                key: _workspaceKey,
                tooltip: 'Workspace',
                height: size,
                lit: wsUuid != null && wsUuid != widget.hereUuid,
                color: wsColor,
                leading: _Dot(wsColor),
                label: target?.name ?? 'Tasks',
                onTap: _pickWorkspace,
                onDismiss: wsFromWord
                    ? () => _setRules(() => _ignoreWorkspaceWord = true)
                    : null,
              ),
              // Last, so the priority and the reminder keep their places.
              _BarButton(
                tooltip: _project ? 'Adds a project' : 'Add as a project',
                height: size,
                lit: _project,
                color: wsColor,
                icon: Icons.folder_outlined,
                label: _project ? 'Project' : null,
                onTap: () => setState(() => _project = !_project),
              ),
            ],
          ),
        ),
        // The composer writes a task; a project has nothing for it to set.
        if (!_project) ...[
          const SizedBox(width: T.s1),
          _BarButton(
            tooltip: 'Notes, repeat and more (Ctrl+D)',
            height: size,
            lit: false,
            color: T.muted,
            icon: Icons.open_in_full_rounded,
            onTap: _expand,
          ),
        ],
        const SizedBox(width: T.s1),
        // The one filled block on the card: it is the thing the card is for.
        Tooltip(
          message: widget.layout.touch
              ? 'Add'
              : 'Add (Enter) · Ctrl+Enter adds and stays open',
          child: Material(
            color: empty ? T.surface : hereColor,
            borderRadius: BorderRadius.circular(T.radius),
            child: InkWell(
              onTap: empty ? null : _submit,
              borderRadius: BorderRadius.circular(T.radius),
              child: SizedBox(
                width: size + T.s2,
                height: size,
                child: Icon(
                  Icons.arrow_upward_rounded,
                  size: 18,
                  color: empty ? T.muted : T.inkOn(hereColor),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Places the card: from the folded line's box ([origin]) at t = 0 to a
/// centred column at t = 1, a little above the middle - optically centred,
/// and further from a phone keyboard's edge.
class _FlightLayout extends SingleChildLayoutDelegate {
  _FlightLayout({
    required this.t,
    required this.origin,
    required this.topInset,
  });

  final double t;
  final Rect? origin;
  final double topInset;

  static const maxWidth = 440.0;

  double _width(Size box) =>
      math.max(0, math.min(box.width - 2 * T.s3, maxWidth));

  /// Without a folded line on screen the card rises from the bottom edge,
  /// narrow, where the dock's ＋ is.
  Rect _from(Size box) =>
      origin ??
      Rect.fromCenter(
        center: Offset(box.width / 2, box.height - 28),
        width: math.min(160, box.width),
        height: 40,
      );

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final box = constraints.biggest;
    final w = lerpDouble(_from(box).width, _width(box), t)!;
    return BoxConstraints(
      minWidth: w,
      maxWidth: w,
      maxHeight: math.max(0, box.height - topInset - T.s3),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final from = _from(size);
    final x = (size.width - _width(size)) / 2;
    final room = size.height - topInset;
    final y = topInset + math.max(T.s3, (room - childSize.height) * 0.42);
    return Offset(lerpDouble(from.left, x, t)!, lerpDouble(from.top, y, t)!);
  }

  @override
  bool shouldRelayout(_FlightLayout old) =>
      old.t != t || old.origin != origin || old.topInset != topInset;
}

/// A button on the card's bar: flat, filled faintly in its colour while it
/// holds a setting. [onDismiss] adds a × - the setting came from a word in
/// the title, and this hands the word back.
class _BarButton extends StatelessWidget {
  const _BarButton({
    super.key,
    required this.tooltip,
    required this.height,
    required this.lit,
    required this.color,
    required this.onTap,
    this.icon,
    this.leading,
    this.label,
    this.onDismiss,
  });

  final String tooltip;
  final double height;
  final bool lit;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? leading;
  final String? label;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final ink = lit ? color : T.muted;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: lit ? color.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(T.radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(T.radius),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: height, minHeight: height),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: label == null ? 0 : T.s2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) Icon(icon, size: 16, color: ink),
                  ?leading,
                  if (label != null) ...[
                    const SizedBox(width: T.s1),
                    Flexible(
                      child: Text(
                        label!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: T.fsLabel,
                          color: lit ? T.text : T.muted,
                          fontWeight: lit ? T.wMedium : T.wNormal,
                        ),
                      ),
                    ),
                  ],
                  if (onDismiss != null)
                    Tooltip(
                      message: 'Keep the word in the title',
                      child: InkWell(
                        onTap: onDismiss,
                        customBorder: const CircleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.only(left: T.s1),
                          child: Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: ink,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Asks for a workspace's new shortcut. Pops with it, checked and without
/// its `#`, or with nothing.
class _ShortcutSheet extends StatefulWidget {
  const _ShortcutSheet({
    required this.layout,
    required this.workspace,
    required this.workspaces,
  });

  final Layout layout;
  final Workspace workspace;
  final List<Workspace> workspaces;

  @override
  State<_ShortcutSheet> createState() => _ShortcutSheetState();
}

class _ShortcutSheetState extends State<_ShortcutSheet> {
  final _text = TextEditingController(text: '#');
  bool _tried = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? get _problem =>
      shortcutProblem(_text.text, widget.workspace, widget.workspaces);

  void _save() {
    if (_problem != null) {
      setState(() => _tried = true);
      return;
    }
    Navigator.of(context).pop(normalizeShortcut(_text.text));
  }

  @override
  Widget build(BuildContext context) {
    final touch = widget.layout.touch;
    final accent = T.parseHex(widget.workspace.color);
    final problem = _problem;
    // Said once something has been typed, or Save was pressed on nothing:
    // "Type a shortcut" under an empty field the moment it opens is a scold.
    final shown = _tried || normalizeShortcut(_text.text).isNotEmpty
        ? problem
        : null;
    return FormSheet(
      accent: accent,
      layout: widget.layout,
      title: 'Shortcut for ${widget.workspace.name}',
      maxWidth: 360,
      onClose: () => Navigator.of(context).pop(),
      actions: [
        FormSheet.cancelButton(
          touch: touch,
          onTap: () => Navigator.of(context).pop(),
        ),
        FormSheet.saveButton(touch: touch, accent: accent, onTap: _save),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Typed into a task\'s title, it puts the task on '
            '${widget.workspace.name}, like #${widget.workspace.name} does.',
            style: const TextStyle(fontSize: T.fsLabel, color: T.muted),
          ),
          const SizedBox(height: T.s3),
          TextField(
            controller: _text,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
            style: const TextStyle(fontSize: T.fsBody, color: T.text),
            decoration: InputDecoration(
              hintText: '#MT',
              isDense: true,
              errorText: shown,
            ),
          ),
        ],
      ),
    );
  }
}
