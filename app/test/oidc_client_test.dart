// The device-grant sign-in.
//
// Everything here runs against a stubbed http client. That covers the parts
// that are actually easy to get wrong - the RFC's polling states, and the
// single-flight refresh - without a Keycloak to point at.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:todo_widget/sync/oidc_client.dart';

const _device = 'https://kc.test/realms/home/protocol/openid-connect/auth/device';
const _tokenUrl = 'https://kc.test/realms/home/protocol/openid-connect/token';

const _config = AuthConfig(
  mode: 'oidc',
  issuer: 'https://kc.test/realms/home',
  clientId: 'todo-widget',
  deviceEndpoint: _device,
  tokenEndpoint: _tokenUrl,
);

http.Response _ok(Map<String, Object?> body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

http.Response _err(int status, Map<String, Object?> body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  group('AuthConfig', () {
    test('an older server with no such route means device tokens', () async {
      final client = MockClient((_) async => http.Response('Not found', 404));
      final config = await AuthConfig.discover('http://box:8787', client: client);
      expect(config.mode, 'token');
      expect(config.isOidc, isFalse);
    });

    test('an unreachable server is not a reason to demand a token', () async {
      final client = MockClient((_) async => throw const SocketishError());
      final config = await AuthConfig.discover('http://box:8787', client: client);
      expect(config.mode, 'token');
    });

    test('SSO is only usable once the provider has answered', () {
      const partial = AuthConfig(mode: 'oidc', error: 'provider down');
      expect(partial.isOidc, isTrue);
      // The distinction that matters: SSO *is* configured, so the UI must not
      // fall back to asking for a token the user is not supposed to have.
      expect(partial.usable, isFalse);
      expect(_config.usable, isTrue);
    });
  });

  group('requesting a code', () {
    test('reads what the user has to be shown', () async {
      final client = MockClient((req) async {
        expect(req.url.toString(), _device);
        expect(req.bodyFields['client_id'], 'todo-widget');
        return _ok({
          'device_code': 'dev-1',
          'user_code': 'WDJB-MJHT',
          'verification_uri': 'https://kc.test/device',
          'verification_uri_complete': 'https://kc.test/device?user_code=WDJB-MJHT',
          'expires_in': 600,
          'interval': 5,
        });
      });

      final code = await OidcClient(config: _config, client: client).requestCode();
      expect(code.userCode, 'WDJB-MJHT');
      expect(code.interval, const Duration(seconds: 5));
      // Prefer the complete URI: on a phone it makes the flow one tap.
      expect(code.bestUri, contains('user_code=WDJB-MJHT'));
      expect(code.expired, isFalse);
    });

    test('the commonest misconfiguration is named outright', () async {
      // "unauthorized_client" on its own sends people to look at their
      // password, when the actual fix is a checkbox on the Keycloak client.
      final client = MockClient(
        (_) async => _err(400, {'error': 'unauthorized_client'}),
      );

      await expectLater(
        OidcClient(config: _config, client: client).requestCode(),
        throwsA(
          isA<OidcAuthException>().having(
            (e) => e.message,
            'message',
            contains('Device Authorization Grant'),
          ),
        ),
      );
    });
  });

  group('polling for approval', () {
    DeviceCode code({Duration interval = Duration.zero}) => DeviceCode(
          deviceCode: 'dev-1',
          userCode: 'WDJB-MJHT',
          verificationUri: 'https://kc.test/device',
          verificationUriComplete: null,
          interval: interval,
          expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );

    test('keeps waiting through authorization_pending, then succeeds', () async {
      var calls = 0;
      var pending = 0;
      final client = MockClient((_) async {
        calls++;
        if (calls < 3) return _err(400, {'error': 'authorization_pending'});
        return _ok({
          'access_token': 'at-1',
          'refresh_token': 'rt-1',
          'expires_in': 300,
        });
      });

      final tokens = await OidcClient(config: _config, client: client)
          .awaitApproval(code(), onPending: () => pending++);

      expect(tokens.accessToken, 'at-1');
      expect(calls, 3);
      expect(pending, 2, reason: 'the UI is told each time it is still waiting');
    });

    test('slow_down backs the interval off instead of giving up', () async {
      // Required by RFC 8628 - a provider that says slow_down and gets the same
      // rate back can legitimately start refusing.
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        if (calls == 1) return _err(400, {'error': 'slow_down'});
        return _ok({'access_token': 'at-1', 'expires_in': 300});
      });

      final started = DateTime.now();
      final tokens = await OidcClient(config: _config, client: client)
          .awaitApproval(code());

      expect(tokens.accessToken, 'at-1');
      // The second pass waited the extra five seconds the RFC asks for.
      expect(
        DateTime.now().difference(started),
        greaterThanOrEqualTo(const Duration(seconds: 5)),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a refusal ends it, and says so', () async {
      final client = MockClient((_) async => _err(400, {'error': 'access_denied'}));
      await expectLater(
        OidcClient(config: _config, client: client).awaitApproval(code()),
        throwsA(isA<OidcAuthException>().having((e) => e.message, 'm', contains('refused'))),
      );
    });

    test('an expired code ends it', () async {
      final client = MockClient((_) async => _err(400, {'error': 'expired_token'}));
      await expectLater(
        OidcClient(config: _config, client: client).awaitApproval(code()),
        throwsA(isA<OidcAuthException>().having((e) => e.message, 'm', contains('expired'))),
      );
    });

    test('cancelling stops the poll', () async {
      final client = MockClient((_) async => _err(400, {'error': 'authorization_pending'}));
      await expectLater(
        OidcClient(config: _config, client: client)
            .awaitApproval(code(), cancelled: () => true),
        throwsA(isA<OidcAuthException>()),
      );
    });
  });

  group('the session', () {
    OidcSession session(
      http.Client client, {
      required Duration validFor,
      String? refresh = 'rt-1',
      List<OidcTokens>? saved,
    }) {
      return OidcSession(
        client: OidcClient(config: _config, client: client),
        tokens: OidcTokens(
          accessToken: 'at-old',
          refreshToken: refresh,
          expiresAt: DateTime.now().add(validFor),
        ),
        save: (t) async => saved?.add(t),
      );
    }

    test('a fresh token is handed back without touching the network', () async {
      final client = MockClient((_) async => throw StateError('must not refresh'));
      final s = session(client, validFor: const Duration(minutes: 10));
      expect(await s.accessToken(), 'at-old');
    });

    test('a stale token is refreshed and persisted', () async {
      final saved = <OidcTokens>[];
      final client = MockClient(
        (_) async => _ok({'access_token': 'at-new', 'refresh_token': 'rt-2', 'expires_in': 300}),
      );
      final s = session(client, validFor: const Duration(seconds: 5), saved: saved);

      expect(await s.accessToken(), 'at-new');
      expect(saved.single.refreshToken, 'rt-2');
    });

    test('two overlapping calls make exactly one refresh', () async {
      // The one that matters. Keycloak rotates refresh tokens, so a second
      // refresh spends a token the first already replaced - the provider
      // rejects it, and a perfectly good device signs itself out. Sync polls on
      // a timer *and* on resume, so overlapping calls are routine.
      var refreshes = 0;
      final client = MockClient((_) async {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return _ok({'access_token': 'at-new', 'refresh_token': 'rt-2', 'expires_in': 300});
      });
      final s = session(client, validFor: const Duration(seconds: 5));

      final results = await Future.wait([s.accessToken(), s.accessToken(), s.accessToken()]);

      expect(refreshes, 1);
      expect(results, everyElement('at-new'));
    });

    test('a provider that does not rotate keeps the refresh token we have', () async {
      final saved = <OidcTokens>[];
      final client = MockClient(
        (_) async => _ok({'access_token': 'at-new', 'expires_in': 300}),
      );
      final s = session(client, validFor: const Duration(seconds: 5), saved: saved);

      await s.accessToken();
      expect(saved.single.refreshToken, 'rt-1', reason: 'dropping it would end the session');
    });

    test('no refresh token at all is an immediate sign-out', () async {
      final client = MockClient((_) async => throw StateError('must not be called'));
      final s = session(client, validFor: const Duration(seconds: 5), refresh: null);
      await expectLater(s.accessToken(), throwsA(isA<OidcAuthException>()));
    });

    test('a rejected refresh surfaces as needing a new sign-in', () async {
      final client = MockClient(
        (_) async => _err(400, {'error': 'invalid_grant', 'error_description': 'Token is not active'}),
      );
      final s = session(client, validFor: const Duration(seconds: 5));
      await expectLater(s.accessToken(), throwsA(isA<OidcAuthException>()));
    });

    test('a failed refresh does not wedge the session for later attempts', () async {
      // The in-flight future has to be cleared on failure too, or one blip
      // means every later call awaits a future that already threw.
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        if (calls == 1) return _err(503, {});
        return _ok({'access_token': 'at-new', 'expires_in': 300});
      });
      final s = session(client, validFor: const Duration(seconds: 5));

      await expectLater(s.accessToken(), throwsA(isA<OidcAuthException>()));
      expect(await s.accessToken(), 'at-new');
    });
  });
}

/// Stands in for a network failure without importing dart:io.
class SocketishError implements Exception {
  const SocketishError();
}
