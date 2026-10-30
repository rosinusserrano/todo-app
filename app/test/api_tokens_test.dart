// The API-token calls on AdminClient (server/index.js, *your tokens*).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo_widget/sync/admin_client.dart';

void main() {
  AdminClient client(Future<http.Response> Function(http.Request) handler) =>
      AdminClient(
        baseUrl: 'https://todo.example.com',
        token: 'full',
        client: MockClient(handler),
      );

  test('lists, mints and revokes against /api/tokens', () async {
    final seen = <String>[];
    final c = client((req) async {
      seen.add('${req.method} ${req.url.path}');
      expect(req.headers['Authorization'], 'Bearer full');
      return switch ((req.method, req.url.path)) {
        ('GET', '/api/tokens') => http.Response(
            jsonEncode({
              'tokens': [
                {'id': 'a1', 'label': 'backup', 'scope': 'inbox', 'last_seen_at': null},
                {'id': 'b2', 'label': 'beszel', 'scope': 'notify'},
              ],
            }),
            200,
          ),
        ('POST', '/api/tokens') => http.Response(
            jsonEncode({'token': 'secret-${jsonDecode(req.body)['label']}'}),
            200,
          ),
        _ => http.Response(jsonEncode({'ok': true}), 200),
      };
    });

    final tokens = await c.apiTokens();
    expect([for (final t in tokens) '${t.label}:${t.scope}'], ['backup:inbox', 'beszel:notify']);
    expect(tokens.first.describe(), 'never used');
    expect(await c.addApiToken('ci'), 'secret-ci');
    await c.revokeApiToken(tokens.first);
    expect(seen, ['GET /api/tokens', 'POST /api/tokens', 'POST /api/tokens/a1/revoke']);
  });

  test('an older server says to update it, not that an account is gone', () async {
    final c = client((_) async => http.Response('<!DOCTYPE html>Cannot GET', 404));
    await expectLater(
      c.apiTokens(),
      throwsA(isA<AdminException>().having((e) => e.message, 'message', contains('Update it'))),
    );
  });

  test("the server's own reason is shown, except for a rejected token", () async {
    final c = client((req) async => req.url.path.endsWith('revoke')
        ? http.Response(jsonEncode({'error': 'No such token'}), 404)
        : http.Response(jsonEncode({'error': 'Invalid token'}), 401));
    await expectLater(
      c.revokeApiToken(const ServerToken(id: 'x', label: 'x', lastSeenAt: null, revoked: false)),
      throwsA(isA<AdminException>().having((e) => e.message, 'message', 'No such token')),
    );
    await expectLater(
      c.apiTokens(),
      throwsA(isA<AdminException>().having((e) => e.message, 'message', contains('Settings'))),
    );
  });
}
