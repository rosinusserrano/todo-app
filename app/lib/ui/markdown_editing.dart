// What typing Markdown into a plain text field needs to feel like an editor.
//
// Everything here is a pure function of a [TextEditingValue], so it works the
// same from a hardware key, a phone's return key and a test, and it never
// needs to know which widget the text is in:
//
//   - **Lists continue.** Enter at the end of "- milk" starts "- " on the next
//     line, "3. " after "2. ", "- [ ] " after a ticked or unticked box, at the
//     same indent. Enter on a list line with nothing after its marker ends
//     the list instead - the marker goes and the line is empty - which is how
//     every editor that does this lets you out. It is a [TextInputFormatter]
//     rather than a key handler because a phone's return key is not a key
//     event: it arrives as text, and the formatter is the one place both
//     kinds of Enter pass through.
//   - **Tab indents a list line** (Shift+Tab outdents), so nesting is one
//     key. Off a list line Tab is left alone and moves focus as it always has.
//   - **Find** is [findAll]: case-insensitive, plain text, never a regex -
//     people search their notes for words.
//
// The code-editor keys (Ctrl+D and friends) are in code_keys.dart.

import 'package:flutter/services.dart';

/// "  - [ ] ", "3. ", "* " at the start of a line: indent, marker, an
/// optional task box, and the space after.
final _listLine = RegExp(r'^(\s*)([-*+]|(\d+)([.)]))(\s+)(\[[ xX]\]\s+)?');

/// The start and end of the line [offset] is on.
(int, int) lineAt(String text, int offset) {
  final start = offset <= 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;
  var end = text.indexOf('\n', offset);
  if (end < 0) end = text.length;
  return (start, end);
}

/// The marker the line after [line] should start with, or null when [line]
/// is not a list item.
String? nextMarker(String line) {
  final m = _listLine.firstMatch(line);
  if (m == null) return null;
  final indent = m.group(1)!;
  final number = m.group(3);
  final marker = number == null
      ? m.group(2)!
      : '${int.parse(number) + 1}${m.group(4)}';
  final box = m.group(6) == null ? '' : '[ ] ';
  return '$indent$marker${m.group(5)}$box';
}

/// Whether [line] is a list marker and nothing else.
bool isBareItem(String line) {
  final m = _listLine.firstMatch(line);
  return m != null && line.substring(m.end).trim().isEmpty;
}

/// Continues a list when Enter is pressed at a list line - see the file
/// header. Anything other than a single newline typed at a collapsed caret
/// passes through untouched.
class ListContinuation extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final caret = newValue.selection;
    if (!caret.isCollapsed || !oldValue.selection.isValid) return newValue;
    if (newValue.text.length != oldValue.text.length + 1 -
            (oldValue.selection.end - oldValue.selection.start)) {
      return newValue;
    }
    final at = caret.baseOffset - 1;
    if (at < 0 || newValue.text[at] != '\n') return newValue;
    if (oldValue.selection.start != at) return newValue;
    // Mid-composition the newline is the IME's to place.
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }

    final text = newValue.text;
    final (start, _) = lineAt(text, at);
    final line = text.substring(start, at);

    if (isBareItem(line)) {
      // Enter on an empty item: out of the list. The marker goes, and so does
      // the newline just typed - the caret stays on the now empty line.
      final out = text.replaceRange(start, at + 1, '');
      return TextEditingValue(
        text: out,
        selection: TextSelection.collapsed(offset: start),
      );
    }
    final marker = nextMarker(line);
    if (marker == null) return newValue;
    final out = text.replaceRange(at + 1, at + 1, marker);
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: at + 1 + marker.length),
    );
  }
}

/// The lines the selection touches, as [start, end) with no trailing newline.
/// A selection ending just after a newline does not take the line after it.
(int, int) selectedLines(TextEditingValue v) {
  final sel = v.selection;
  final (start, _) = lineAt(v.text, sel.start);
  final endAt = sel.end > sel.start && v.text[sel.end - 1] == '\n'
      ? sel.end - 1
      : sel.end;
  final (_, end) = lineAt(v.text, endAt);
  return (start, end);
}

/// Indents (or with [outdent], outdents) the list lines under the selection by
/// [unit]. Null when no line in it is a list item: the caller then lets Tab
/// do what Tab does.
TextEditingValue? indentList(
  TextEditingValue v, {
  bool outdent = false,
  String unit = '  ',
  bool anyLine = false,
}) {
  if (!v.selection.isValid) return null;
  final (start, end) = selectedLines(v);
  final lines = v.text.substring(start, end).split('\n');
  if (!anyLine && !lines.any((l) => _listLine.hasMatch(l))) return null;

  var shift = 0; // how far the caret's line moved
  var total = 0;
  final caretLine = v.selection.baseOffset;
  var pos = start;
  final out = <String>[];
  for (final line in lines) {
    String next = line;
    if (anyLine || _listLine.hasMatch(line)) {
      if (outdent) {
        final cut = line.startsWith(unit)
            ? unit.length
            : line.startsWith('\t') || line.startsWith(' ')
            ? 1
            : 0;
        next = line.substring(cut);
      } else {
        next = '$unit$line';
      }
    }
    final delta = next.length - line.length;
    if (caretLine >= pos && caretLine <= pos + line.length) shift = delta;
    total += delta;
    pos += line.length + 1;
    out.add(next);
  }
  final text = v.text.replaceRange(start, end, out.join('\n'));
  final sel = v.selection;
  final selection = sel.isCollapsed
      ? TextSelection.collapsed(
          offset: (sel.baseOffset + shift).clamp(start, text.length),
        )
      : TextSelection(
          baseOffset: start,
          extentOffset: (end + total).clamp(start, text.length),
        );
  return TextEditingValue(text: text, selection: selection);
}

/// Where [query] occurs in [text], ignoring case. Empty for an empty query.
List<TextRange> findAll(String text, String query) {
  if (query.isEmpty) return const [];
  final hay = text.toLowerCase();
  final needle = query.toLowerCase();
  final found = <TextRange>[];
  var from = 0;
  while (true) {
    final i = hay.indexOf(needle, from);
    if (i < 0) break;
    found.add(TextRange(start: i, end: i + needle.length));
    from = i + needle.length;
  }
  return found;
}

/// [text] with every range in [ranges] replaced by [by]. The ranges must not
/// overlap, as [findAll]'s never do.
String replaceRanges(String text, List<TextRange> ranges, String by) {
  final out = StringBuffer();
  var at = 0;
  for (final r in ranges) {
    out
      ..write(text.substring(at, r.start))
      ..write(by);
    at = r.end;
  }
  out.write(text.substring(at));
  return out.toString();
}
