// The Markdown dialect the notes surfaces render, checked at the parse layer.
//
// These assert the *tree*, not pixels: what has to hold is which runs of text
// became maths and which stayed prose, and that is a property of the syntaxes
// in markdown_text.dart. Rendering a formula is flutter_math_fork's problem.
//
// The `$…$` cases are the ones that matter. Turning maths on for text people
// have already written means every existing note is re-parsed under the new
// rules, so a dollar sign that used to be a dollar sign has to stay one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:todo_widget/ui/markdown_text.dart';

/// The tags of every maths node in [source], with its LaTeX and whether it is
/// display style.
List<({String tex, bool display})> maths(String source) {
  final doc = md.Document(extensionSet: markdownExtensions, encodeHtml: false);
  final found = <({String tex, bool display})>[];
  void walk(md.Node node) {
    if (node is! md.Element) return;
    if (node.tag == 'math') {
      found.add((
        tex: node.textContent,
        display: node.attributes['display'] == 'block',
      ));
      return;
    }
    for (final child in node.children ?? const <md.Node>[]) {
      walk(child);
    }
  }

  for (final node in doc.parseLines(source.split('\n'))) {
    walk(node);
  }
  return found;
}

void main() {
  group('inline maths', () {
    test(r'$ … $ becomes text-style maths', () {
      expect(maths(r'the area is $\pi r^2$ exactly'), [
        (tex: r'\pi r^2', display: false),
      ]);
    });

    test(r'$$ … $$ inside a line becomes display maths', () {
      expect(maths(r'so $$E = mc^2$$ then'), [
        (tex: 'E = mc^2', display: true),
      ]);
    });

    test('two formulas on one line are two nodes', () {
      expect(maths(r'$a+b$ and $c+d$'), [
        (tex: 'a+b', display: false),
        (tex: 'c+d', display: false),
      ]);
    });

    test('an escaped dollar is not a delimiter', () {
      expect(maths(r'costs \$5 and \$7'), isEmpty);
    });

    // The rule that makes this safe to switch on over notes already written.
    test('money is left alone', () {
      expect(maths(r'it costs $5, or $7 with tax'), isEmpty);
      expect(maths(r'between $5-$7'), isEmpty);
      expect(maths(r'$100 today, $250 next week'), isEmpty);
    });

    test('whitespace against a delimiter is not maths', () {
      expect(maths(r'a $ b $ c'), isEmpty);
    });

    test('an empty pair is not maths', () {
      expect(maths(r'nothing $$ here'), isEmpty);
    });

    test('a formula does not run across a line break', () {
      expect(maths('open \$a\nand \$b'), isEmpty);
    });
  });

  group('block maths', () {
    test(r'a $$ fence on its own lines is display maths', () {
      expect(maths('before\n\n\$\$\n\\sum_{i=0}^n i\n\$\$\n\nafter'), [
        (tex: r'\sum_{i=0}^n i', display: true),
      ]);
    });

    test('a ```math fence is display maths', () {
      expect(maths('```math\n\\frac{a}{b}\n```'), [
        (tex: r'\frac{a}{b}', display: true),
      ]);
    });

    test('a ```math fence is not rendered as a code block', () {
      final doc =
          md.Document(extensionSet: markdownExtensions, encodeHtml: false);
      final html =
          md.HtmlRenderer().render(doc.parseLines('```math\nx^2\n```'.split('\n')));
      expect(html, isNot(contains('<code')));
    });

    test('an unclosed fence still reads as maths', () {
      expect(maths('\$\$\nx^2'), [(tex: 'x^2', display: true)]);
    });

    test('an ordinary code fence is untouched', () {
      expect(maths('```\nlet x = \$5\n```'), isEmpty);
    });
  });

  group('markdownPlainText', () {
    test('strips emphasis and keeps the words', () {
      expect(markdownPlainText('**done** by _five_'), 'done by five');
    });

    test('a link previews as its label', () {
      expect(
        markdownPlainText('book it on [the site](https://example.com/a/b)'),
        'book it on the site',
      );
    });

    test('a list flattens to one line', () {
      expect(markdownPlainText('- passport\n- tickets'), 'passport tickets');
    });

    test('a task list loses its box, not its text', () {
      expect(markdownPlainText('- [ ] call the bank'), 'call the bank');
    });

    test('headings and paragraphs do not run together', () {
      expect(markdownPlainText('# Trip\n\nLeaves at nine'), 'Trip Leaves at nine');
    });

    test('maths previews as its source', () {
      expect(markdownPlainText(r'area $\pi r^2$'), r'area \pi r^2');
    });

    test('empty in, empty out', () {
      expect(markdownPlainText('   \n  '), '');
    });
  });

  // The parse tests above stop at the tree. These are the render path, which is
  // the only place a maths node ever reaches flutter_math - and the only place a
  // bad delimiter, an unknown macro or a stray builder would throw instead of
  // producing a wrong tree.
  group('rendering', () {
    Future<void> render(WidgetTester tester, String source) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: MarkdownText(source))),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a document with inline and block maths builds',
        (tester) async {
      await render(tester, '''
# Trip

The area is \$\\pi r^2\$, near enough.

\$\$
\\sum_{i=0}^{n} i = \\frac{n(n+1)}{2}
\$\$

- [x] passport
- [ ] \$120 in cash

See [the site](https://example.com).
''');
      expect(tester.takeException(), isNull);
      expect(find.text('Trip'), findsOneWidget);
    });

    // Notes are written in passing and half of them are wrong for a minute.
    testWidgets('a formula with a typo shows its source instead of throwing',
        (tester) async {
      await render(tester, r'broken $\frac{1}{$ here');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a single newline is a line break, not a space',
        (tester) async {
      await render(tester, 'first line\nsecond line');
      expect(tester.takeException(), isNull);
      // Folded into one paragraph, they would have been one string.
      expect(find.textContaining('first line second line'), findsNothing);
    });
  });
}
