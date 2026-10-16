// A link in a task's title is shown as the page's title.
//
// "read https://www.nature.com/articles/s41586-024-07421-0" says nothing on a
// list; "read Accurate structure prediction of biomolecular interactions with
// AlphaFold 3" does. The task's text is not touched - the URL is what is
// stored, synced and edited, and the title is only how a row *draws* it - so
// nothing about this is in the schema, and a page that renames itself is
// simply drawn differently next week.
//
// The rules that are not obvious:
//
// - **Asked once per URL per device, and remembered** in a device-local
//   setting (`link-titles`), including "this page has no title", so a list
//   full of links is not a request per row per launch. Capped at
//   [LinkTitles.maxRemembered], oldest first out.
// - **A failure is not remembered across launches.** Offline, or a site that
//   was down, is asked again next time; only an answer is kept.
// - **The web build asks the sync server** (`/api/link-title`, server/
//   links.js): another site sends a browser no CORS headers, exactly the
//   calendar feeds' problem. Native asks the page itself
//   ([fetchLinkTitleDirect]). The two read a title the same way - og:title,
//   else `<title>` - and **a change to one is a change to the other**.
// - Drawn by [LinkedText], which owns the tap recognisers it hands to the
//   spans; a recogniser in a StatelessWidget would never be disposed.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

/// Every http(s) URL in [text], as (start, end) - without the punctuation a
/// sentence puts after one ("see https://x.com/a.").
List<(int, int)> findLinks(String text) {
  final out = <(int, int)>[];
  for (final m in _url.allMatches(text)) {
    var end = m.end;
    while (end > m.start && '.,;:!?\'"'.contains(text[end - 1])) {
      end--;
    }
    // A closing bracket belongs to the URL only if it opened one inside it
    // (Wikipedia's "Foo_(bar)"); otherwise it closes the sentence's.
    if (text[end - 1] == ')' &&
        !text.substring(m.start, end - 1).contains('(')) {
      end--;
    }
    out.add((m.start, end));
  }
  return out;
}

final _url = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

/// What a page calls itself: og:title, else `<title>`. Null for neither.
/// The mirror of `titleFromHtml` in server/links.js.
String? titleFromHtml(String html) {
  final og =
      RegExp(
        r'''<meta[^>]+property=["']og:title["'][^>]*content=["']([^"']*)["']''',
        caseSensitive: false,
      ).firstMatch(html) ??
      RegExp(
        r'''<meta[^>]+content=["']([^"']*)["'][^>]*property=["']og:title["']''',
        caseSensitive: false,
      ).firstMatch(html);
  final raw =
      og?.group(1) ??
      RegExp(
        r'<title[^>]*>([\s\S]*?)</title>',
        caseSensitive: false,
      ).firstMatch(html)?.group(1);
  if (raw == null) return null;
  final title = _decodeEntities(raw).replaceAll(RegExp(r'\s+'), ' ').trim();
  if (title.isEmpty) return null;
  return title.length > 300 ? '${title.substring(0, 299)}…' : title;
}

const _named = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
};

String _decodeEntities(String s) => s.replaceAllMapped(
  RegExp(r'&(#x[0-9a-f]+|#\d+|[a-z]+);', caseSensitive: false),
  (m) {
    final e = m[1]!;
    if (e.startsWith('#')) {
      final code = e[1] == 'x' || e[1] == 'X'
          ? int.tryParse(e.substring(2), radix: 16)
          : int.tryParse(e.substring(1));
      if (code == null || code > 0x10FFFF) return m[0]!;
      return String.fromCharCode(code);
    }
    return _named[e.toLowerCase()] ?? m[0]!;
  },
);

/// Asks the page itself - the native builds. Reads the head only.
Future<String?> fetchLinkTitleDirect(Uri url, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final req = http.Request('GET', url)
      ..headers['accept'] = 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.5'
      ..headers['user-agent'] =
          'Mozilla/5.0 (compatible; TodoWidget link titles)';
    final res = await c.send(req).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final type = res.headers['content-type'] ?? '';
    if (type.isNotEmpty && !type.toLowerCase().contains('html')) return null;
    final bytes = <int>[];
    await for (final chunk in res.stream.timeout(const Duration(seconds: 8))) {
      bytes.addAll(chunk);
      if (bytes.length > 256 * 1024) break;
      if (latin1
          .decode(bytes, allowInvalid: true)
          .toLowerCase()
          .contains('</head>')) {
        break;
      }
    }
    return titleFromHtml(utf8.decode(bytes, allowMalformed: true));
  } finally {
    if (client == null) c.close();
  }
}

typedef LinkTitleFetcher = Future<String?> Function(Uri url);

/// Page titles by URL: what has been learnt, and asking for what has not.
class LinkTitles extends ChangeNotifier {
  LinkTitles({this.fetch, this.read, this.write});

  /// Null asks nothing (a test, or a web build with no sync server).
  LinkTitleFetcher? fetch;

  /// Where the answers are kept between launches; null keeps them in memory.
  final Future<String?> Function()? read;
  final Future<void> Function(String json)? write;

  static const maxRemembered = 500;

  /// URL → title, or '' for "asked, and the page has none".
  final Map<String, String> _known = {};
  final Set<String> _asking = {};

  /// Failed this run - asked again next launch, not every rebuild.
  final Set<String> _failed = {};

  Future<void> load() async {
    final raw = await read?.call();
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw);
      if (map is Map) {
        for (final e in map.entries) {
          if (e.key is String && e.value is String) {
            _known[e.key as String] = e.value as String;
          }
        }
      }
    } on FormatException {
      // A damaged cache is an empty one.
    }
  }

  /// The page's title, or null while it is unknown (being asked, failed, or
  /// the page has none). Asking starts here, the first time a URL is drawn.
  String? titleOf(String url) {
    final known = _known[url];
    if (known != null) return known.isEmpty ? null : known;
    _ask(url);
    return null;
  }

  Future<void> _ask(String url) async {
    final f = fetch;
    if (f == null || _asking.contains(url) || _failed.contains(url)) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    _asking.add(url);
    try {
      final title = await f(uri);
      _known.remove(url);
      _known[url] = title ?? '';
      while (_known.length > maxRemembered) {
        _known.remove(_known.keys.first);
      }
      await write?.call(jsonEncode(_known));
      if (title != null) notifyListeners();
    } catch (_) {
      _failed.add(url);
    } finally {
      _asking.remove(url);
    }
  }
}

/// Puts [LinkTitles] where every [LinkedText] can find it, and rebuilds them
/// when a title arrives.
class LinkTitlesScope extends InheritedNotifier<LinkTitles> {
  const LinkTitlesScope({
    super.key,
    required LinkTitles titles,
    required super.child,
  }) : super(notifier: titles);

  static LinkTitles? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LinkTitlesScope>()?.notifier;
}

/// [text] with each URL drawn as its page's title (the URL itself until the
/// title is known), in [linkColor], opening the page when tapped.
class LinkedText extends StatefulWidget {
  const LinkedText(
    this.text, {
    super.key,
    required this.style,
    this.linkColor = T.accent,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle style;
  final Color linkColor;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  State<LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState extends State<LinkedText> {
  final _recognizers = <TapGestureRecognizer>[];

  void _dropRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _dropRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final links = findLinks(text);
    if (links.isEmpty) {
      return Text(
        text,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }
    final titles = LinkTitlesScope.maybeOf(context);
    _dropRecognizers();
    final spans = <InlineSpan>[];
    var at = 0;
    for (final (start, end) in links) {
      if (start > at) spans.add(TextSpan(text: text.substring(at, start)));
      final url = text.substring(start, end);
      final recognizer = TapGestureRecognizer()
        ..onTap = () =>
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: titles?.titleOf(url) ?? _shortUrl(url),
          recognizer: recognizer,
          mouseCursor: SystemMouseCursors.click,
          style: TextStyle(
            color: widget.linkColor,
            decoration: TextDecoration.underline,
            decorationColor: widget.linkColor.withValues(alpha: 0.4),
          ),
        ),
      );
      at = end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}

/// A URL with no title yet: without the scheme and `www.`, and a long path
/// cut down, since the whole of it is in the task when it is edited.
String _shortUrl(String url) {
  var s = url.replaceFirst(
    RegExp(r'^https?://(www\.)?', caseSensitive: false),
    '',
  );
  if (s.endsWith('/')) s = s.substring(0, s.length - 1);
  return s.length > 48 ? '${s.substring(0, 47)}…' : s;
}
