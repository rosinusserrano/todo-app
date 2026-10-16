import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_widget/link_titles.dart';

void main() {
  group('findLinks', () {
    List<String> links(String text) => [
      for (final (a, b) in findLinks(text)) text.substring(a, b),
    ];

    test('leaves the sentence its punctuation', () {
      expect(links('see https://example.com/a.'), ['https://example.com/a']);
      expect(links('(https://example.com/a)'), ['https://example.com/a']);
      expect(links('https://en.wikipedia.org/wiki/Foo_(bar) ok'), [
        'https://en.wikipedia.org/wiki/Foo_(bar)',
      ]);
    });

    test('only http and https', () {
      expect(links('ftp://x.org and mailto:a@b.c'), isEmpty);
      expect(links('a http://x.org b https://y.org'), [
        'http://x.org',
        'https://y.org',
      ]);
    });
  });

  test('titleFromHtml: og:title, then <title>, entities decoded', () {
    expect(
      titleFromHtml(
        '<head><title>Site</title>'
        '<meta property="og:title" content="A &amp; B"></head>',
      ),
      'A & B',
    );
    expect(
      titleFromHtml('<title>\n Hello &#8211; world </title>'),
      'Hello – world',
    );
    expect(titleFromHtml('<p>none</p>'), isNull);
  });

  test('asks once, remembers the answer, and says when it changed', () async {
    final asked = <Uri>[];
    String? stored;
    final titles = LinkTitles(
      fetch: (u) async {
        asked.add(u);
        return 'The Page';
      },
      write: (json) async => stored = json,
    );
    var notified = 0;
    titles.addListener(() => notified++);

    expect(titles.titleOf('https://x.org/a'), isNull);
    expect(titles.titleOf('https://x.org/a'), isNull, reason: 'in flight');
    await Future<void>.delayed(Duration.zero);
    expect(titles.titleOf('https://x.org/a'), 'The Page');
    expect(asked, hasLength(1));
    expect(notified, 1);
    expect(stored, contains('The Page'));

    // A new launch reads it back without asking.
    final again = LinkTitles(
      fetch: (u) async => throw StateError('should not ask'),
      read: () async => stored,
    );
    await again.load();
    expect(again.titleOf('https://x.org/a'), 'The Page');
  });

  test('a failure is not asked again this run', () async {
    var asked = 0;
    final titles = LinkTitles(
      fetch: (u) async {
        asked++;
        throw Exception('offline');
      },
    );
    titles.titleOf('https://x.org/a');
    await Future<void>.delayed(Duration.zero);
    titles.titleOf('https://x.org/a');
    await Future<void>.delayed(Duration.zero);
    expect(asked, 1);
  });

  testWidgets('a URL is drawn as its title once known', (tester) async {
    final titles = LinkTitles(fetch: (u) async => 'Example Domain');
    await tester.pumpWidget(
      MaterialApp(
        home: LinkTitlesScope(
          titles: titles,
          child: const Scaffold(
            body: LinkedText(
              'read https://www.example.com/ today',
              style: TextStyle(),
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('read example.com today', findRichText: true),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('read Example Domain today', findRichText: true),
      findsOneWidget,
    );
  });
}
