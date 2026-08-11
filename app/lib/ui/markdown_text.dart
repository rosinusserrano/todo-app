// Markdown, with maths, for the three places this app keeps long-form text:
// a task's notes, a journal entry's body, and a calendar event's description.
//
// The dialect is **GitHub Flavored Markdown** plus GitHub's maths extension -
// which is what people mean when they say "the GitHub one": headings, emphasis,
// lists (including `- [x]` task lists), links, tables, block quotes, code
// spans and fences, and `$…$` / `$$…$$` / ```` ```math ```` for LaTeX. Picking
// an existing dialect rather than inventing one is the whole point: notes get
// pasted in from somewhere else at least as often as they get typed here.
//
// Two decisions worth keeping:
//
//   - **One renderer, three call sites.** Every surface uses [MarkdownText] and
//     differs only in its base [TextStyle]. A second style sheet would drift
//     from this one a literal at a time, which is the same reason [UiScale]
//     exists rather than a mobile fork of every padding.
//   - **The style sheet is derived from the base style**, not written out per
//     surface. Notes render at 12.5, a journal body at 13 and an event
//     description at 12.5; deriving means a heading is proportionally a heading
//     in all three, and there is one place to change what "a heading" looks
//     like.
//
// Not selectable, deliberately. Selection would fight the tap that opens the
// editor - see the read/edit split in `task_composer.dart` and
// `journal_panel.dart` - and links are tappable, which is what the text is
// mostly wanted for.

import 'dart:convert' show LineSplitter;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// GFM, plus the maths syntaxes below.
///
/// The custom syntaxes go **first** in each list. The block parser and the
/// inline parser both evaluate what a [md.Document] was handed ahead of their
/// own standard set, and both orderings matter here: ```` ```math ```` has to be
/// seen before the ordinary fenced-code syntax claims it, and `$…$` has to be
/// seen before the escape syntax eats the `\$` in an escaped dollar.
final md.ExtensionSet markdownExtensions = md.ExtensionSet(
  <md.BlockSyntax>[
    const _MathBlockSyntax(),
    ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
  ],
  <md.InlineSyntax>[
    _MathInlineSyntax(),
    ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
  ],
);

/// Renders [data] as Markdown.
///
/// [style] is the body text; everything else is derived from it. Null takes the
/// surrounding [DefaultTextStyle], which is how the font family and its
/// fallbacks reach the spans - [MarkdownBody] builds its own `RichText`, so a
/// style sheet that named no family would silently lose Segoe UI Variable.
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.data, {super.key, this.style, this.onTapText});

  final String data;
  final TextStyle? style;

  /// Tapping anywhere that is not a link. The read views use it as the way in
  /// to the editor, so the body is as good a handle as the pencil.
  final VoidCallback? onTapText;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    return MarkdownBody(
      data: data,
      extensionSet: markdownExtensions,
      styleSheet: _styleSheet(base),
      builders: {'math': _MathBuilder(base)},
      onTapText: onTapText,
      onTapLink: (text, href, title) => _open(href),
      // Markdown folds a single newline into a space, and that is correct for
      // prose - but these are notes, where a list of bare lines is written
      // without blank lines between them far more often than a paragraph is
      // wrapped by hand.
      softLineBreak: true,
    );
  }

  /// Never throws: a link that will not open is a dead link, not an error worth
  /// interrupting someone's notes for. Same reasoning as the SSO launcher.
  static Future<void> _open(String? href) async {
    if (href == null || href.isEmpty) return;
    try {
      await launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
    } catch (_) {
      // Nothing sensible to do here, and nowhere to say it.
    }
  }

  static MarkdownStyleSheet _styleSheet(TextStyle base) {
    final size = base.fontSize ?? 12.5;
    // Monospace for code, by family list rather than by name: the three
    // platforms this runs on do not agree on one, and naming a font that is not
    // there gets the proportional default back, which is the one thing a code
    // span must not be.
    final code = base.copyWith(
      fontSize: size - 0.5,
      fontFamily: 'Cascadia Mono',
      fontFamilyFallback: const ['Consolas', 'Menlo', 'monospace'],
      color: T.text,
    );
    TextStyle heading(double scale) => base.copyWith(
          fontSize: size * scale,
          fontWeight: FontWeight.w600,
          height: 1.25,
          color: T.text,
        );

    return MarkdownStyleSheet(
      p: base,
      pPadding: EdgeInsets.zero,
      a: base.copyWith(color: T.accent, decoration: TextDecoration.underline),
      em: base.copyWith(fontStyle: FontStyle.italic),
      strong: base.copyWith(fontWeight: FontWeight.w700),
      del: base.copyWith(decoration: TextDecoration.lineThrough, color: T.muted),
      code: code,
      // Headings step down gently. This is a 340px window; an h1 at the usual
      // 2x would be a banner across a note that is four lines long.
      h1: heading(1.35),
      h2: heading(1.2),
      h3: heading(1.1),
      h4: heading(1.0),
      h5: heading(1.0),
      h6: heading(1.0).copyWith(color: T.muted),
      h1Padding: EdgeInsets.zero,
      h2Padding: EdgeInsets.zero,
      h3Padding: EdgeInsets.zero,
      h4Padding: EdgeInsets.zero,
      h5Padding: EdgeInsets.zero,
      h6Padding: EdgeInsets.zero,
      blockquote: base.copyWith(color: T.muted),
      blockquotePadding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
      blockquoteDecoration: const BoxDecoration(
        border: Border(left: BorderSide(color: T.surfaceHover, width: 2)),
      ),
      codeblockPadding: const EdgeInsets.all(8),
      codeblockDecoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(top: BorderSide(color: T.surfaceHover, width: 1)),
      ),
      listBullet: base.copyWith(color: T.muted),
      listBulletPadding: const EdgeInsets.only(right: 4),
      listIndent: 16,
      checkbox: base.copyWith(color: T.accent),
      blockSpacing: 6,
      tableHead: base.copyWith(fontWeight: FontWeight.w600),
      tableBody: base,
      tableBorder: TableBorder.all(color: T.surfaceHover, width: 0.5),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      tableHeadAlign: TextAlign.left,
      img: base,
      textAlign: WrapAlignment.start,
    );
  }
}

/// Previews already worked out, keyed by their source.
///
/// This is called from `build`, once per task row carrying notes and once per
/// agenda line carrying a description - and those rebuild on hover and on every
/// frame of a row's slide-out, where the string has not changed. Parsing a
/// document per row per frame to arrive at the same answer is the kind of cost
/// that does not show up until the list is long.
///
/// Cleared wholesale rather than evicted one at a time: the keys are note
/// bodies, the bound is generous, and an LRU here would be more machinery than
/// the thing it manages.
final _previews = <String, String>{};
const _previewCacheMax = 256;

/// The same source rendered down to one readable line, for the places that show
/// a *preview* rather than the text: the notes line under a task title, and an
/// event's description in the agenda.
///
/// Walking the parsed tree rather than stripping punctuation with a regex is
/// what keeps this honest - `**done** by 5` previews as "done by 5" and a link
/// previews as its label, without a pile of patterns that each get one case
/// right. Maths previews as its LaTeX, which is the only plain-text form it
/// has.
String markdownPlainText(String source) {
  if (source.trim().isEmpty) return '';
  final cached = _previews[source];
  if (cached != null) return cached;

  final doc = md.Document(extensionSet: markdownExtensions, encodeHtml: false);
  final buf = StringBuffer();

  void walk(md.Node node) {
    if (node is md.Text) {
      buf.write(node.text);
      return;
    }
    if (node is md.Element) {
      // An image has no text of its own; its alt text is what it was for.
      if (node.tag == 'img') {
        buf.write(node.attributes['alt'] ?? '');
        return;
      }
      // A checkbox is a marker, not a word. Dropping it keeps "- [ ] call the
      // bank" previewing as the thing to do.
      if (node.tag == 'input') return;
      for (final child in node.children ?? const <md.Node>[]) {
        walk(child);
      }
      // Blocks that ran together would read as one word ("firstsecond").
      buf.write(' ');
    }
  }

  for (final node in doc.parseLines(const LineSplitter().convert(source))) {
    walk(node);
  }
  final preview = buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();

  if (_previews.length >= _previewCacheMax) _previews.clear();
  return _previews[source] = preview;
}

// --------------------------------------------------------------------- maths

/// `$$…$$` or ```` ```math ```` on lines of their own.
///
/// The node it produces is a *paragraph containing* the maths rather than a
/// bare `math` block, so [MarkdownBuilder] handles it on the path it already
/// has for an inline widget in a block. A block-level custom tag would need
/// [MarkdownElementBuilder.isBlockElement] to be true, and that is a property
/// of the builder, not of the element - it would have made every inline `$x$`
/// a block too.
class _MathBlockSyntax extends md.BlockSyntax {
  const _MathBlockSyntax();

  @override
  RegExp get pattern => RegExp(r'^ {0,3}(\$\$|```[ \t]*math[ \t]*)$');

  @override
  md.Node? parse(md.BlockParser parser) {
    final opened = pattern.firstMatch(parser.current.content)!.group(1)!;
    final fence = opened.startsWith(r'$$') ? r'\$\$' : '```';
    final closer = RegExp('^ {0,3}$fence[ \\t]*\$');
    parser.advance();

    final lines = <String>[];
    while (!parser.isDone) {
      if (closer.hasMatch(parser.current.content)) {
        parser.advance();
        break;
      }
      lines.add(parser.current.content);
      parser.advance();
    }
    // An unclosed fence runs to the end of the text rather than being handed
    // back as prose: what was typed is a formula either way, and a half-written
    // one should look like a formula being written.
    return md.Element('p', [_mathNode(lines.join('\n'), display: true)]);
  }
}

/// `$$…$$` and `$…$` inside a line.
///
/// The `$…$` half follows pandoc's rule, and it is the rule that makes this
/// safe to switch on for everyone's existing notes: the delimiters may not sit
/// against whitespace, and a closing `$` may not be followed by a digit. That
/// is what keeps "it costs $5, or $7 with tax" out of the maths renderer, which
/// is the failure mode that would otherwise make this feature a bug report.
class _MathInlineSyntax extends md.InlineSyntax {
  _MathInlineSyntax()
      : super(r'\$\$([^$]+?)\$\$|\$(?!\s)([^$\n]+?)(?<!\s)\$(?![0-9])');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final display = match[1] != null;
    final tex = (match[1] ?? match[2] ?? '').trim();
    if (tex.isEmpty) return false;
    parser.addNode(_mathNode(tex, display: display));
    return true;
  }
}

md.Element _mathNode(String tex, {required bool display}) =>
    md.Element('math', [md.Text(tex.trim())])
      ..attributes['display'] = display ? 'block' : 'inline';

/// Draws one formula.
///
/// [MathStyle.display] versus [MathStyle.text] is the same distinction TeX
/// makes and is why the two delimiters are kept apart all the way down here:
/// a sum's limits belong over and under the sigma on a line of its own, and
/// beside it in the middle of a sentence.
class _MathBuilder extends MarkdownElementBuilder {
  _MathBuilder(this.base);

  final TextStyle base;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final tex = element.textContent;
    final display = element.attributes['display'] == 'block';
    final style = base.merge(parentStyle);
    return Math.tex(
      tex,
      textStyle: style,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      // A formula with a typo in it shows the source, not an exception and not
      // a blank. Notes are written in passing and half of them are wrong for a
      // minute; the useful thing to show is what was typed.
      onErrorFallback: (_) => Text(
        display ? '\$\$$tex\$\$' : '\$$tex\$',
        style: style.copyWith(color: T.danger),
      ),
    );
  }
}
