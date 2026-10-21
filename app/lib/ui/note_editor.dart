// The body field of a note, grown into a small editor (Marco, 2026-10-21:
// "generally richer note editor").
//
// Still one Flutter [TextField] - everything a text field already does
// (selection handles, the IME, a phone's keyboard, undo) keeps working, and
// what is added sits around it rather than replacing it:
//
//   - **Monospaced**, in Space Mono (bundled, [T.fontMono]): what is typed here
//     is Markdown, and its indents and markers line up in a fixed pitch.
//   - **Lists continue and Tab nests them** (markdown_editing.dart).
//   - **Ctrl+F / Ctrl+H find and replace**, in a bar over the field. Matches
//     are drawn by the controller ([NoteController.buildTextSpan]) rather than
//     selected, so the caret can stay in the find field while you step
//     through them; Esc puts the caret on the one you were at.
//   - **The code editor's keys**, when Settings turns them on (code_keys.dart).
//     Ctrl+D's extra selections are the controller's [NoteController.extras]:
//     shaded by the same span builder, given a caret by [_ExtraCarets], and
//     kept in step with every edit by the controller's `value` setter, which
//     is the one place every change to the text passes through.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter/services.dart';

import '../theme.dart';
import 'code_keys.dart';
import 'markdown_editing.dart';

/// The note body's controller: the text, plus the ranges drawn over it.
class NoteController extends TextEditingController {
  NoteController({super.text});

  /// Ctrl+D's other selections. The field's own selection is not in here.
  List<TextRange> extras = const [];

  /// Find's matches, and which one is current (-1 for none).
  List<TextRange> matches = const [];
  int current = -1;

  bool _quiet = false;

  /// Sets the value and the extras together, without the setter reading the
  /// change as an edit to repeat.
  void setWithExtras(TextEditingValue v, List<TextRange> extras) {
    _quiet = true;
    this.extras = extras;
    value = v;
    _quiet = false;
    notifyListeners();
  }

  /// The spans changed, not the text: draw again.
  void redraw() => notifyListeners();

  void clearExtras() {
    if (extras.isEmpty) return;
    extras = const [];
    notifyListeners();
  }

  @override
  set value(TextEditingValue next) {
    if (_quiet || extras.isEmpty) {
      super.value = next;
      return;
    }
    final old = super.value;
    if (next.text != old.text) {
      final multi = applyMulti(old, next, extras);
      if (multi == null) {
        extras = const [];
        super.value = next;
      } else {
        extras = multi.$2;
        super.value = multi.$1;
      }
      return;
    }
    // The caret moved somewhere on its own: the other selections were about
    // where it was.
    if (next.selection != old.selection) extras = const [];
    super.value = next;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final layers = <(TextRange, TextStyle)>[
      for (var i = 0; i < matches.length; i++)
        (
          matches[i],
          TextStyle(
            backgroundColor: i == current
                ? T.accent.withValues(alpha: 0.55)
                : T.accent.withValues(alpha: 0.22),
          ),
        ),
      for (final r in extras)
        if (!r.isCollapsed)
          (r, TextStyle(backgroundColor: T.accent.withValues(alpha: 0.35))),
    ];
    if (layers.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final c = value.composing;
    if (withComposing && c.isValid && !c.isCollapsed) {
      layers.add((
        c,
        const TextStyle(decoration: TextDecoration.underline),
      ));
    }
    return TextSpan(style: style, children: layered(text, layers));
  }
}

/// [text] cut at every edge of [layers], each piece styled by the layers
/// over it (later ones on top).
List<TextSpan> layered(String text, List<(TextRange, TextStyle)> layers) {
  final cuts = <int>{0, text.length};
  for (final (r, _) in layers) {
    if (r.start >= 0 && r.start <= text.length) cuts.add(r.start);
    if (r.end >= 0 && r.end <= text.length) cuts.add(r.end);
  }
  final sorted = cuts.toList()..sort();
  return [
    for (var i = 0; i + 1 < sorted.length; i++)
      if (sorted[i] < sorted[i + 1])
        TextSpan(
          text: text.substring(sorted[i], sorted[i + 1]),
          style: layers
              .where((l) => l.$1.start <= sorted[i] && l.$1.end >= sorted[i + 1])
              .fold<TextStyle?>(
                null,
                (s, l) => s == null ? l.$2 : s.merge(l.$2),
              ),
        ),
  ];
}

class NoteBody extends StatefulWidget {
  const NoteBody({
    super.key,
    required this.controller,
    required this.focusNode,
    this.codeKeys = false,
    this.autofocus = false,
    this.hint,
  });

  final NoteController controller;

  /// The field's node. This widget sets its `onKeyEvent`: a key handled there
  /// is handled before the field or the app's shortcuts see it.
  final FocusNode focusNode;

  /// The code editor's keys (code_keys.dart), from Settings.
  final bool codeKeys;
  final bool autofocus;
  final String? hint;

  static const style = TextStyle(
    fontFamily: T.fontMono,
    fontFamilyFallback: T.fontMonoFallback,
    fontSize: T.fsBody - 0.5,
    color: T.text,
    height: 1.45,
  );

  @override
  State<NoteBody> createState() => _NoteBodyState();
}

class _NoteBodyState extends State<NoteBody> {
  final _scroll = ScrollController();
  final _fieldKey = GlobalKey();
  final _stackKey = GlobalKey();

  bool _finding = false;
  final _find = TextEditingController();
  final _replace = TextEditingController();
  final _findFocus = FocusNode();

  NoteController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    widget.focusNode.onKeyEvent = _onFieldKey;
    _c.addListener(_onText);
  }

  @override
  void didUpdateWidget(NoteBody old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.onKeyEvent = null;
      widget.focusNode.onKeyEvent = _onFieldKey;
    }
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.focusNode.onKeyEvent = null;
    _c.removeListener(_onText);
    _c.matches = const [];
    _c.extras = const [];
    _scroll.dispose();
    _find.dispose();
    _replace.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  String _lastText = '';

  /// The text changed under an open find: the matches move with it.
  void _onText() {
    if (!_finding || _c.text == _lastText) return;
    _lastText = _c.text;
    _search(keepPlace: true);
  }

  // ------------------------------------------------------------------- keys

  bool get _ctrl =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  KeyEventResult _onFieldKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = e.logicalKey;
    final keys = HardwareKeyboard.instance;
    final shift = keys.isShiftPressed;
    final alt = keys.isAltPressed;

    if (_ctrl && !alt && (key == LogicalKeyboardKey.keyF ||
        key == LogicalKeyboardKey.keyH)) {
      _openFind();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && _c.extras.isNotEmpty) {
      _c.clearExtras();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab && !_ctrl && !alt) {
      final next = indentList(
        _c.value,
        outdent: shift,
        anyLine: widget.codeKeys,
      );
      if (next == null) return KeyEventResult.ignored;
      _c.value = next;
      return KeyEventResult.handled;
    }
    if (!widget.codeKeys) return KeyEventResult.ignored;

    TextEditingValue? next;
    if (_ctrl && !alt && !shift && key == LogicalKeyboardKey.keyD) {
      _selectNext();
      return KeyEventResult.handled;
    } else if (alt && !_ctrl && key == LogicalKeyboardKey.arrowUp) {
      next = shift
          ? duplicateLines(_c.value, up: true)
          : moveLines(_c.value, up: true);
    } else if (alt && !_ctrl && key == LogicalKeyboardKey.arrowDown) {
      next = shift
          ? duplicateLines(_c.value, up: false)
          : moveLines(_c.value, up: false);
    } else if (_ctrl && shift && key == LogicalKeyboardKey.keyK) {
      next = deleteLines(_c.value);
    } else if (_ctrl && !shift && !alt && key == LogicalKeyboardKey.keyL) {
      next = selectLine(_c.value);
    } else if (_ctrl && !shift && !alt &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      next = lineBelow(_c.value);
    } else {
      return KeyEventResult.ignored;
    }
    // At the top or bottom a move has nowhere to go, and the key is still
    // spent: passing it on would move the caret instead.
    if (next != null) _c.setWithExtras(next, const []);
    return KeyEventResult.handled;
  }

  void _selectNext() {
    final v = _c.value;
    if (v.selection.isCollapsed) {
      final word = selectWord(v);
      if (word != null) _c.setWithExtras(word, _c.extras);
      return;
    }
    final next = selectNext(v, _c.extras);
    if (next == null) return;
    _c.setWithExtras(next.$1, next.$2);
    _reveal(next.$1.selection.start);
  }

  // ------------------------------------------------------------------- find

  void _openFind() {
    final sel = _c.selection;
    // A selection on one line is what you were about to look for.
    if (sel.isValid && !sel.isCollapsed) {
      final picked = sel.textInside(_c.text);
      if (!picked.contains('\n')) _find.text = picked;
    }
    _find.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _find.text.length,
    );
    setState(() => _finding = true);
    _lastText = _c.text;
    _search();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _findFocus.requestFocus();
    });
  }

  /// Back to the text, the caret on the match you were at.
  void _closeFind() {
    final at = _c.current >= 0 && _c.current < _c.matches.length
        ? _c.matches[_c.current]
        : null;
    _c.matches = const [];
    _c.current = -1;
    setState(() => _finding = false);
    if (at != null) {
      _c.selection = TextSelection(baseOffset: at.start, extentOffset: at.end);
    }
    widget.focusNode.requestFocus();
  }

  /// [keepPlace]: the text changed, so stay at the match nearest where the
  /// current one was rather than jumping back to the first after the caret.
  void _search({bool keepPlace = false}) {
    final found = findAll(_c.text, _find.text);
    var current = -1;
    if (found.isNotEmpty) {
      final from = keepPlace && _c.current >= 0 && _c.current < _c.matches.length
          ? _c.matches[_c.current].start
          : (_c.selection.isValid ? _c.selection.start : 0);
      current = found.indexWhere((r) => r.start >= from);
      if (current < 0) current = 0;
    }
    _c.matches = found;
    _c.current = current;
    // The spans are the controller's to draw; tell the field.
    _c.redraw();
    setState(() {});
    if (current >= 0) _reveal(found[current].start);
  }

  void _step(int by) {
    final n = _c.matches.length;
    if (n == 0) return;
    _c.current = ((_c.current < 0 ? 0 : _c.current) + by) % n;
    if (_c.current < 0) _c.current += n;
    _c.redraw();
    setState(() {});
    _reveal(_c.matches[_c.current].start);
  }

  void _replaceOne() {
    final i = _c.current;
    if (i < 0 || i >= _c.matches.length) return;
    final r = _c.matches[i];
    final text = _c.text.replaceRange(r.start, r.end, _replace.text);
    _c.setWithExtras(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(
          offset: r.start + _replace.text.length,
        ),
      ),
      const [],
    );
    _lastText = _c.text;
    _search();
  }

  void _replaceAll() {
    if (_c.matches.isEmpty) return;
    final text = replaceRanges(_c.text, _c.matches, _replace.text);
    _c.setWithExtras(
      TextEditingValue(text: text, selection: const TextSelection.collapsed(offset: 0)),
      const [],
    );
    _lastText = _c.text;
    _search();
  }

  /// Scroll the field so [offset] is on screen - a third of the way down, so
  /// what comes after a match is visible too.
  void _reveal(int offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final editable = _editable();
      if (editable == null || !_scroll.hasClients) return;
      final rect = editable.getLocalRectForCaret(TextPosition(offset: offset));
      final height = editable.size.height;
      if (rect.top >= 0 && rect.bottom <= height) return;
      final target = (_scroll.offset + rect.top - height / 3).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.jumpTo(target);
    });
  }

  RenderEditable? _editable() {
    RenderEditable? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is EditableTextState) {
        found = (e.state as EditableTextState).renderEditable;
        return;
      }
      e.visitChildElements(visit);
    }

    final root = _fieldKey.currentContext;
    if (root is Element) root.visitChildElements(visit);
    return found;
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Focus(
      // Esc and Enter in the find bar. Above the bar's fields, so a key they
      // do not use comes here on its way up.
      onKeyEvent: (node, e) {
        if (!_finding || e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.escape) {
          _closeFind();
          return KeyEventResult.handled;
        }
        if (_ctrl && e.logicalKey == LogicalKeyboardKey.keyF) {
          _findFocus.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_finding) _findBar(),
          Expanded(
            child: Stack(
              key: _stackKey,
              children: [
                TextField(
                  key: _fieldKey,
                  controller: _c,
                  focusNode: widget.focusNode,
                  scrollController: _scroll,
                  autofocus: widget.autofocus,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  style: NoteBody.style,
                  inputFormatters: [ListContinuation()],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.hint,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: T.s2),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ExtraCarets(
                        controller: _c,
                        scroll: _scroll,
                        editable: _editable,
                        stack: () =>
                            _stackKey.currentContext?.findRenderObject()
                                as RenderBox?,
                      ),
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

  Widget _findBar() {
    final n = _c.matches.length;
    final count = _find.text.isEmpty
        ? ''
        : n == 0
        ? 'No results'
        : '${_c.current + 1} of $n';
    InputDecoration deco(String hint) => InputDecoration(
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
    );
    Widget icon(IconData i, String tip, VoidCallback? onTap) => Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.radius),
        child: Padding(
          padding: const EdgeInsets.all(T.s1),
          child: Icon(i, size: 16, color: onTap == null ? T.surfaceHover : T.muted),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: T.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Focus(
                  // Enter steps forward, Shift+Enter back; the field keeps
                  // the caret, so stepping is as many presses as you like.
                  onKeyEvent: (node, e) {
                    if (e is! KeyDownEvent ||
                        (e.logicalKey != LogicalKeyboardKey.enter &&
                            e.logicalKey != LogicalKeyboardKey.numpadEnter)) {
                      return KeyEventResult.ignored;
                    }
                    _step(HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
                    return KeyEventResult.handled;
                  },
                  child: TextField(
                    controller: _find,
                    focusNode: _findFocus,
                    style: const TextStyle(fontSize: T.fsLabel),
                    decoration: deco('Find'),
                    onChanged: (_) => _search(),
                  ),
                ),
              ),
              const SizedBox(width: T.s2),
              SizedBox(
                width: 70,
                child: Text(
                  count,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
                ),
              ),
              icon(Icons.keyboard_arrow_up_rounded, 'Previous (Shift+Enter)',
                  n == 0 ? null : () => _step(-1)),
              icon(Icons.keyboard_arrow_down_rounded, 'Next (Enter)',
                  n == 0 ? null : () => _step(1)),
              icon(Icons.close_rounded, 'Close (Esc)', _closeFind),
            ],
          ),
          const SizedBox(height: T.s1),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _replace,
                  style: const TextStyle(fontSize: T.fsLabel),
                  decoration: deco('Replace with'),
                  onSubmitted: (_) => _replaceOne(),
                ),
              ),
              const SizedBox(width: T.s2),
              TextButton(
                onPressed: n == 0 ? null : _replaceOne,
                style: TextButton.styleFrom(foregroundColor: T.muted),
                child: const Text('Replace', style: TextStyle(fontSize: T.fsLabel)),
              ),
              TextButton(
                onPressed: n == 0 ? null : _replaceAll,
                style: TextButton.styleFrom(foregroundColor: T.muted),
                child: const Text('All', style: TextStyle(fontSize: T.fsLabel)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A caret at the end of each of Ctrl+D's other selections. The field draws
/// its own selection's caret; these it knows nothing about.
class _ExtraCarets extends CustomPainter {
  _ExtraCarets({
    required this.controller,
    required this.scroll,
    required this.editable,
    required this.stack,
  }) : super(repaint: Listenable.merge([controller, scroll]));

  final NoteController controller;
  final ScrollController scroll;
  final RenderEditable? Function() editable;
  final RenderBox? Function() stack;

  @override
  void paint(Canvas canvas, Size size) {
    if (controller.extras.isEmpty) return;
    final re = editable();
    final box = stack();
    if (re == null || box == null || !re.attached || !box.attached) return;
    final paint = Paint()..color = T.text;
    for (final r in controller.extras) {
      if (r.end > controller.text.length) continue;
      final rect = re.getLocalRectForCaret(TextPosition(offset: r.end));
      if (rect.bottom < 0 || rect.top > re.size.height) continue;
      final topLeft = box.globalToLocal(re.localToGlobal(rect.topLeft));
      canvas.drawRect(
        Rect.fromLTWH(topLeft.dx, topLeft.dy, 1.5, rect.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ExtraCarets old) => true;
}
