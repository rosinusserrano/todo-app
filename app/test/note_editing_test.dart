// The note editor's text operations: lists that continue, Tab that nests,
// find and replace, and the code editor's keys. All pure functions of a
// TextEditingValue, so they are pinned here without a widget; the keys that
// reach them are in journal_panel_test.dart.

import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_widget/ui/code_keys.dart';
import 'package:todo_widget/ui/markdown_editing.dart';
import 'package:todo_widget/ui/note_editor.dart' show layered;

TextEditingValue at(String text, [int? caret]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: caret ?? text.length),
);

TextEditingValue sel(String text, int start, int end) => TextEditingValue(
  text: text,
  selection: TextSelection(baseOffset: start, extentOffset: end),
);

/// Enter typed at the caret, through the formatter.
TextEditingValue enter(TextEditingValue v) {
  final c = v.selection.start;
  final typed = TextEditingValue(
    text: v.text.replaceRange(c, v.selection.end, '\n'),
    selection: TextSelection.collapsed(offset: c + 1),
  );
  return ListContinuation().formatEditUpdate(v, typed);
}

void main() {
  group('lists continue', () {
    test('a bullet, a number, a box, at their indent', () {
      expect(enter(at('- milk')).text, '- milk\n- ');
      expect(enter(at('  * eggs')).text, '  * eggs\n  * ');
      expect(enter(at('9. nine')).text, '9. nine\n10. ');
      expect(enter(at('1) one')).text, '1) one\n2) ');
      expect(enter(at('- [x] done')).text, '- [x] done\n- [ ] ');
      final v = enter(at('- milk'));
      expect(v.selection.baseOffset, v.text.length, reason: 'caret after it');
    });

    test('Enter on an empty item ends the list', () {
      final v = enter(at('- milk\n- '));
      expect(v.text, '- milk\n');
      expect(v.selection.baseOffset, 7);
    });

    test('a plain line, or Enter mid-line before the marker, is left alone',
        () {
      expect(enter(at('plain')).text, 'plain\n');
      expect(enter(at('- milk', 0)).text, '\n- milk');
    });

    test('a paste with a newline in it is not an Enter', () {
      final old = at('- a');
      final pasted = at('- a\nb\nc');
      expect(ListContinuation().formatEditUpdate(old, pasted), pasted);
    });
  });

  group('Tab', () {
    test('nests a list item and Shift+Tab takes it back out', () {
      final v = indentList(at('- a\n- b', 7))!;
      expect(v.text, '- a\n  - b');
      expect(v.selection.baseOffset, 9);
      expect(indentList(v, outdent: true)!.text, '- a\n- b');
    });

    test('is left to focus off a list line', () {
      expect(indentList(at('plain')), isNull);
      expect(indentList(at('plain'), anyLine: true)!.text, '  plain');
    });

    test('every selected line moves', () {
      final v = indentList(sel('- a\n- b\nc', 0, 7))!;
      expect(v.text, '  - a\n  - b\nc');
    });
  });

  group('find', () {
    test('ignores case, and replaces every match', () {
      final found = findAll('Milk, milk, MILK', 'milk');
      expect(found.length, 3);
      expect(replaceRanges('Milk, milk, MILK', found, 'oat'), 'oat, oat, oat');
      expect(findAll('x', ''), isEmpty);
    });

    test('spans are cut at every edge and keep the text whole', () {
      const style = TextStyle(fontSize: 1);
      final spans = layered('abcdef', [
        (const TextRange(start: 1, end: 3), style),
        (const TextRange(start: 2, end: 5), style),
      ]);
      expect(spans.map((s) => s.text).join(), 'abcdef');
      expect(spans.map((s) => s.text), ['a', 'b', 'c', 'de', 'f']);
      expect(spans.first.style, isNull);
    });
  });

  group('the code editor keys', () {
    test('Ctrl+D selects the word, then the next occurrence', () {
      final word = selectWord(at('cat cat dog', 1))!;
      expect(word.selection, const TextSelection(baseOffset: 0, extentOffset: 3));
      final (next, extras) = selectNext(word, const [])!;
      expect(next.selection.start, 4);
      expect(extras.single, const TextRange(start: 0, end: 3));
      expect(selectNext(next, extras), isNull, reason: 'no third');
    });

    test('an edit at the selection is made at every other one', () {
      final old = sel('cat cat dog', 4, 7);
      const extras = [TextRange(start: 0, end: 3)];
      // Typing "x" over the selection.
      final (v, moved) = applyMulti(old, at('cat x dog', 5), extras)!;
      expect(v.text, 'x x dog');
      expect(v.selection, const TextSelection.collapsed(offset: 3));
      expect(moved.single, const TextRange(start: 1, end: 1));
      // Then a backspace at both.
      final (v2, moved2) = applyMulti(v, at('x  dog', 2), moved)!;
      expect(v2.text, '  dog');
      expect(v2.selection.baseOffset, 1);
      expect(moved2.single.start, 0);
    });

    test('an edit away from the selection lets the others go', () {
      final old = sel('cat cat dog', 4, 7);
      expect(
        applyMulti(old, at('cat cat dogs'), const [TextRange(start: 0, end: 3)]),
        isNull,
      );
    });

    test('lines move, copy, go, and are selected', () {
      expect(moveLines(at('a\nb\nc', 2), up: true)!.text, 'b\na\nc');
      expect(moveLines(at('a\nb\nc', 2), up: false)!.text, 'a\nc\nb');
      expect(moveLines(at('a\nb', 0), up: true), isNull);
      final down = moveLines(at('a\nb\nc', 2), up: false)!;
      expect(down.selection.baseOffset, 4, reason: 'the caret goes with it');

      expect(duplicateLines(at('a\nb', 0), up: false).text, 'a\na\nb');
      expect(duplicateLines(at('a\nb', 0), up: false).selection.baseOffset, 2);

      expect(deleteLines(at('a\nb\nc', 2)).text, 'a\nc');
      expect(deleteLines(at('a\nb\nc', 4)).text, 'a\nb');

      final line = selectLine(at('a\nbb\nc', 3));
      expect(line.selection, const TextSelection(baseOffset: 2, extentOffset: 5));
      expect(selectLine(line).selection.end, 6, reason: 'and the next');

      final below = lineBelow(at('abc', 1));
      expect(below.text, 'abc\n');
      expect(below.selection.baseOffset, 4);
    });
  });
}
