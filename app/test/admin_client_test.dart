// The admin API as the app sees it.
//
// Wire-format tests against a stubbed server, which is the half of the contract
// `sync_integration_test.dart` cannot check without a real one running. The
// thing worth pinning here is the *failure* mapping: an admin action is a
// deliberate act by a person who is owed a reason, so a 403 must not surface as
// "something went wrong".

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:todo_widget/sync/admin_client.dart';
import 'package:todo_widget/sync/sync_client.dart';

AdminClient clientThat(
  Future<http.Response> Function(http.Request) handler,
) =>
    AdminClient(
      baseUrl: 'http://server:8787',
      token: 'tok',
      client: MockClient(handler),
    );

void main() {
  test('users() parses accounts, their tokens and the admin flag', () async {
    final client = clientThat((req) async {
      expect(req.url.path, '/api/admin/users');
      expect(req.headers['Authorization'], 'Bearer tok');
      return http.Response(
        jsonEncode({
          'users': [
            {
              'id': 'local',
              'label': 'local',
              'admin': true,
              'tokens': [
                {
                  'id': 'aa11',
                  'label': 'bootstrap secret',
                  'last_seen_at': null,
                  'revoked': false,
                },
              ],
            },
            {
              'id': 'alice-3f9c',
              'label': 'Alice',
              'admin': false,
              'tokens': [
                {'id': 'bb22', 'label': 'phone', 'last_seen_at': null, 'revoked': true},
              ],
            },
          ],
        }),
        200,
      );
    });

    final users = await client.users();
    expect(users.length, 2);
    expect(users.first.admin, isTrue);
    expect(users.last.label, 'Alice');
    expect(users.last.tokens.single.revoked, isTrue);
    // A revoked token is not an active one, which is what drives the "no
    // working token" warning rather than the raw count.
    expect(users.last.activeTokens, 0);
  });

  test('the server never sends the token hash, and nothing here looks for it', () async {
    final client = clientThat((_) async => http.Response(
          jsonEncode({
            'users': [
              {
                'id': 'alice-3f9c',
                'label': 'Alice',
                'admin': false,
                'tokens': [
                  {'id': 'bb22', 'label': 'phone', 'revoked': false},
                ],
              },
            ],
          }),
          200,
        ));

    final token = (await client.users()).single.tokens.single;
    expect(token.id, 'bb22');
    expect(token.lastSeenAt, isNull);
    expect(token.describe(), 'never used');
  });

  test('a 403 says the account is not an admin, not "request failed"', () async {
    final client = clientThat((_) async => http.Response(
          jsonEncode({'error': 'This account is not an admin of this server'}),
          403,
        ));

    await expectLater(
      client.users(),
      throwsA(isA<AdminException>().having(
        (e) => e.message,
        'message',
        contains('cannot manage users'),
      )),
    );
  });

  test('the server\'s own refusal wins over anything invented here', () async {
    // The server is the side that knows *why* - "that is the token you are
    // using right now" is not a sentence the client could have produced.
    final client = clientThat((_) async => http.Response(
          jsonEncode({'error': 'That is the token you are using right now'}),
          400,
        ));

    await expectLater(
      client.revokeToken(const ServerToken(
        id: 'aa11',
        label: 'bootstrap secret',
        lastSeenAt: null,
        revoked: false,
      )),
      throwsA(isA<AdminException>().having(
        (e) => e.message,
        'message',
        'That is the token you are using right now',
      )),
    );
  });

  test('an older server answering HTML does not surface as a crash', () async {
    // A server from before the admin routes has no /api/admin/* at all, and
    // Express answers 404 with an HTML page rather than JSON.
    final client = clientThat(
      (_) async => http.Response('<!DOCTYPE html><body>Cannot GET</body>', 404),
    );

    await expectLater(client.users(), throwsA(isA<AdminException>()));
  });

  test('an unreachable server reports as unreachable', () async {
    final client = clientThat((_) async => throw http.ClientException('boom'));

    await expectLater(
      client.users(),
      throwsA(isA<AdminException>()
          .having((e) => e.message, 'message', contains('reach'))),
    );
  });

  test('creating an account sends the name and returns the token once', () async {
    late Map<String, dynamic> sent;
    final client = clientThat((req) async {
      expect(req.method, 'POST');
      expect(req.url.path, '/api/admin/users');
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'user': {'id': 'alice-3f9c', 'label': 'Alice', 'admin': false},
          'token': 'a-fresh-token',
          'token_id': 'cc33',
        }),
        200,
      );
    });

    final issued = await client.addUser('Alice');
    expect(sent['label'], 'Alice');
    expect(issued.token, 'a-fresh-token');
  });

  test('a user id with a slash cannot escape its own route', () async {
    late Uri asked;
    final client = clientThat((req) async {
      asked = req.url;
      return http.Response(jsonEncode({'ok': true}), 200);
    });

    await client.deleteUser(const ServerUser(
      id: 'a/../local',
      label: 'sneaky',
      admin: false,
      tokens: [],
    ));
    expect(asked.path, '/api/admin/users/a%2F..%2Flocal');
  });

  group('ServerIdentity', () {
    test('reads the account and its admin flag', () {
      final id = ServerIdentity.parse(
        jsonEncode({'user': 'alice-3f9c', 'label': 'Alice', 'admin': true}),
      );
      expect(id!.user, 'alice-3f9c');
      expect(id.label, 'Alice');
      expect(id.admin, isTrue);
    });

    test('a server that says nothing about admin is not one', () {
      // Older server, no admin concept: the panel must stay hidden rather than
      // offer routes that are not there.
      final id = ServerIdentity.parse(jsonEncode({'user': 'local'}));
      expect(id!.admin, isFalse);
      // Falls back to the id, so the UI never shows an empty name.
      expect(id.label, 'local');
    });

    test('nonsense parses to null rather than throwing at the caller', () {
      expect(ServerIdentity.parse('not json'), isNull);
      expect(ServerIdentity.parse(jsonEncode({'label': 'no id'})), isNull);
    });
  });
}
