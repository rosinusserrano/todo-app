// The push routes' client: what it sends, and what it says when the server
// cannot help. The server half is tested in server/push.test.js.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:todo_widget/sync/push_client.dart';

void main() {
  test('register passes the browser subscription through, authenticated',
      () async {
    late http.Request seen;
    final client = PushClient(
      baseUrl: 'https://todo.example.com',
      token: 'tok',
      client: MockClient((req) async {
        seen = req;
        return http.Response('', 204);
      }),
    );
    const sub = '{"endpoint":"https://push.example.com/x","keys":{}}';
    await client.register(sub);
    expect(seen.method, 'PUT');
    expect(seen.url.path, '/api/push/subscription');
    expect(seen.headers['Authorization'], 'Bearer tok');
    expect(seen.body, sub);
  });

  test('the key comes back as a string', () async {
    final client = PushClient(
      baseUrl: 'https://todo.example.com',
      token: 'tok',
      client: MockClient(
        (_) async => http.Response(jsonEncode({'publicKey': 'BKey'}), 200),
      ),
    );
    expect(await client.publicKey(), 'BKey');
  });

  test('a server from before push says to update it', () async {
    final client = PushClient(
      baseUrl: 'https://todo.example.com',
      token: 'tok',
      client: MockClient(
        (_) async => http.Response('<pre>Cannot GET /api/push/key</pre>', 404),
      ),
    );
    await expectLater(
      client.publicKey(),
      throwsA(isA<PushException>().having(
        (e) => e.message,
        'message',
        contains('too old'),
      )),
    );
  });

  test('the server\'s own wording is kept', () async {
    final client = PushClient(
      baseUrl: 'https://todo.example.com',
      token: 'tok',
      client: MockClient(
        (_) async => http.Response(jsonEncode({'error': 'not subscribed'}), 404),
      ),
    );
    await expectLater(
      client.test('https://push.example.com/x'),
      throwsA(isA<PushException>()
          .having((e) => e.message, 'message', 'not subscribed')),
    );
  });
}
