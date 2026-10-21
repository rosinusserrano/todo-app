// The code editor's keys, for the note editor - an option in Settings
// (*Code editor keys in notes*), because half of them take a key the platform
// already gives a meaning to (Ctrl+D, Alt+↑) and somebody who has never used
// VS Code should not find those changed under them.
//
//   Ctrl+D           select the word, then each next occurrence of it; type and
//                    every one of them changes at once
//   Alt+↑ / Alt+↓    move the line (or the selected lines) up or down
//   Shift+Alt+↑ / ↓  copy the line above or below itself
//   Ctrl+Shift+K     delete the line
//   Ctrl+L           select the line, and the next one on each press
//   Ctrl+Enter       a new line below, whatever the caret is in the middle of
//
// Everything is a pure function of a [TextEditingValue], and the several
// selections Ctrl+D makes are plain [TextRange]s beside it: Flutter's text
// field has one selection and one caret, so the others are drawn by the note
// editor and kept in step by [applyMulti], which repeats an edit made at the
// field's own selection at each of them.

import 'package:flutter/services.dart';

import 'markdown_editing.dart' show lineAt, selectedLines;

final _word = RegExp(r'[\p{L}\p{N}_]', unicode: true);

/// The word around a collapsed caret, selected. Null when the caret is not on
/// or beside one.
TextEditingValue? selectWord(TextEditingValue v) {
  final text = v.text;
  final at = v.selection.baseOffset;
  bool isWord(int i) => i >= 0 && i < text.length && _word.hasMatch(text[i]);
  var start = at;
  var end = at;
  while (isWord(start - 1)) {
    start--;
  }
  while (isWord(end)) {
    end++;
  }
  if (start == end) return null;
  return v.copyWith(
    selection: TextSelection(baseOffset: start, extentOffset: end),
  );
}

/// Ctrl+D with something selected: the next occurrence of the selected text
/// after every selection there is, wrapping round, becomes the field's
/// selection, and the old one joins [extras]. Null when there is no other.
(TextEditingValue, List<TextRange>)? selectNext(
  TextEditingValue v,
  List<TextRange> extras,
) {
  final sel = v.selection;
  if (!sel.isValid || sel.isCollapsed) return null;
  final needle = sel.textInside(v.text);
  final taken = [TextRange(start: sel.start, end: sel.end), ...extras];
  final after = taken.map((r) => r.end).reduce((a, b) => a > b ? a : b);
  bool free(int i) => !taken.any((r) => i < r.end && i + needle.length > r.start);

  int? found;
  for (var i = v.text.indexOf(needle, after); i >= 0;
      i = v.text.indexOf(needle, i + 1)) {
    if (free(i)) {
      found = i;
      break;
    }
  }
  if (found == null) {
    for (var i = v.text.indexOf(needle); i >= 0 && i < after;
        i = v.text.indexOf(needle, i + 1)) {
      if (free(i)) {
        found = i;
        break;
      }
    }
  }
  if (found == null) return null;
  return (
    v.copyWith(
      selection: TextSelection(
        baseOffset: found,
        extentOffset: found + needle.length,
      ),
    ),
    [...extras, TextRange(start: sel.start, end: sel.end)],
  );
}

/// Repeats at every range in [extras] the edit that turned [old] into [next]
/// at the field's own selection. Returns the edited value and where each
/// extra ended up, or null when the edit cannot be read as one made at the
/// selection (a paste over everything, an undo) - the caller then lets the
/// extras go, which is what an editor does with an edit it cannot repeat.
(TextEditingValue, List<TextRange>)? applyMulti(
  TextEditingValue old,
  TextEditingValue next,
  List<TextRange> extras,
) {
  final sel = old.selection;
  if (!sel.isValid || extras.isEmpty) return null;
  final a = old.text;
  final b = next.text;
  final ps = sel.start;
  final pe = sel.end;

  // The changed region: the longest common prefix, kept from reaching past the
  // selection's start, and the longest common suffix, kept from reaching
  // before its end. Without the bounds a letter typed beside the same letter
  // is ambiguous about where it went.
  var p = 0;
  while (p < ps && p < a.length && p < b.length && a[p] == b[p]) {
    p++;
  }
  var q = 0;
  final maxQ = [a.length - pe, a.length - p, b.length - p]
      .reduce((x, y) => x < y ? x : y);
  while (q < maxQ && a[a.length - 1 - q] == b[b.length - 1 - q]) {
    q++;
  }
  final oldEnd = a.length - q;
  final inserted = b.substring(p, b.length - q);
  final dl = p - ps; // <= 0: how far before the selection the edit starts
  final dr = oldEnd - pe; // >= 0: how far after it the edit ends
  if (dl > 0 || dr < 0) return null;

  final nsel = next.selection;
  if (!nsel.isValid) return null;
  final relStart = nsel.start - p;
  final relEnd = nsel.end - p;

  // Every selection, the field's own first, in text order.
  final all = [
    (TextRange(start: ps, end: pe), true),
    for (final r in extras) (r, false),
  ]..sort((x, y) => x.$1.start.compareTo(y.$1.start));

  final out = StringBuffer();
  var at = 0;
  var shift = 0;
  TextSelection? primary;
  final moved = <TextRange>[];
  for (final (r, isPrimary) in all) {
    final from = r.start + dl;
    final to = r.end + dr;
    if (from < at || to > a.length || from > to) return null; // overlap
    out
      ..write(a.substring(at, from))
      ..write(inserted);
    final base = from + shift;
    if (isPrimary) {
      primary = TextSelection(
        baseOffset: base + relStart,
        extentOffset: base + relEnd,
      );
    } else {
      moved.add(TextRange(start: base + relStart, end: base + relEnd));
    }
    shift += inserted.length - (to - from);
    at = to;
  }
  out.write(a.substring(at));
  return (
    TextEditingValue(text: out.toString(), selection: primary!),
    moved,
  );
}

TextSelection _shifted(TextSelection s, int by) => TextSelection(
  baseOffset: s.baseOffset + by,
  extentOffset: s.extentOffset + by,
);

/// Alt+↑ / Alt+↓. Null at the top or bottom, where there is nowhere to go.
TextEditingValue? moveLines(TextEditingValue v, {required bool up}) {
  final text = v.text;
  final (start, end) = selectedLines(v);
  final block = text.substring(start, end);
  if (up) {
    if (start == 0) return null;
    final (prevStart, _) = lineAt(text, start - 1);
    final prev = text.substring(prevStart, start - 1);
    return TextEditingValue(
      text: text.replaceRange(prevStart, end, '$block\n$prev'),
      selection: _shifted(v.selection, -(prev.length + 1)),
    );
  }
  if (end >= text.length) return null;
  final (_, nextEnd) = lineAt(text, end + 1);
  final nextLine = text.substring(end + 1, nextEnd);
  return TextEditingValue(
    text: text.replaceRange(start, nextEnd, '$nextLine\n$block'),
    selection: _shifted(v.selection, nextLine.length + 1),
  );
}

/// Shift+Alt+↑ / ↓: the lines again, the selection on the copy below (↓) or
/// staying on the upper one (↑) - VS Code's way round.
TextEditingValue duplicateLines(TextEditingValue v, {required bool up}) {
  final (start, end) = selectedLines(v);
  final block = v.text.substring(start, end);
  return TextEditingValue(
    text: v.text.replaceRange(end, end, '\n$block'),
    selection: up ? v.selection : _shifted(v.selection, block.length + 1),
  );
}

/// Ctrl+Shift+K. The caret lands where the line was, or at the start of the
/// line above when it was the last.
TextEditingValue deleteLines(TextEditingValue v) {
  final text = v.text;
  final (start, end) = selectedLines(v);
  if (end < text.length) {
    return TextEditingValue(
      text: text.replaceRange(start, end + 1, ''),
      selection: TextSelection.collapsed(offset: start),
    );
  }
  final from = start > 0 ? start - 1 : 0;
  final out = text.replaceRange(from, end, '');
  final (above, _) = lineAt(out, from);
  return TextEditingValue(
    text: out,
    selection: TextSelection.collapsed(offset: above),
  );
}

/// Ctrl+L: the whole line, newline included; pressed again, the next too.
TextEditingValue selectLine(TextEditingValue v) {
  final text = v.text;
  final (start, end) = selectedLines(v);
  final alreadyWhole = v.selection.start == start &&
      v.selection.end == (end < text.length ? end + 1 : end) &&
      !v.selection.isCollapsed;
  var to = end < text.length ? end + 1 : end;
  if (alreadyWhole && to < text.length) {
    final (_, nextEnd) = lineAt(text, to);
    to = nextEnd < text.length ? nextEnd + 1 : nextEnd;
  }
  return v.copyWith(
    selection: TextSelection(baseOffset: start, extentOffset: to),
  );
}

/// Ctrl+Enter: a fresh line under this one, caret on it.
TextEditingValue lineBelow(TextEditingValue v) {
  final (_, end) = lineAt(v.text, v.selection.end);
  return TextEditingValue(
    text: v.text.replaceRange(end, end, '\n'),
    selection: TextSelection.collapsed(offset: end + 1),
  );
}
