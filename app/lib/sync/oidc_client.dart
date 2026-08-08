// Signing in to the sync server with single sign-on.
//
// The **device authorization grant** (RFC 8628), not the authorization-code
// flow, and that is the whole design decision here. A code flow needs a
// redirect back into the app: a custom URL scheme and an intent filter on
// Android, an associated domain or scheme on iOS, a loopback HTTP listener on
// desktop - three platform integrations, each of which fails differently and
// none of which can be tested without the device in your hand. The device grant
// needs none of it. The app asks for a code, shows it, and polls; the browser
// half happens anywhere, even on a different machine. One code path for
// Windows, iOS and Android.
//
// The server never sees any of this. It only ever receives the resulting access
// token as a bearer, exactly where a device token would go - see server/oidc.js.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// How the server wants clients to authenticate.
class AuthConfig {
  const AuthConfig({
    required this.mode,
    this.issuer,
    this.clientId,
    this.deviceEndpoint,
    this.tokenEndpoint,
    this.error,
  });

  /// `'token'` for a pasted device token, `'oidc'` for single sign-on.
  final String mode;

  final String? issuer;
  final String? clientId;
  final String? deviceEndpoint;
  final String? tokenEndpoint;

  /// Set when the server has SSO configured but could not reach the provider.
  /// Distinct from `mode: 'token'`: the answer is "try again later", not "paste
  /// a token instead", and telling the user the latter would have them go
  /// looking for a credential they are not supposed to need.
  final String? error;

  bool get isOidc => mode == 'oidc';
  bool get usable => isOidc && deviceEndpoint != null && tokenEndpoint != null;

  static AuthConfig fromJson(Map<String, Object?> m) => AuthConfig(
    mode: (m['mode'] as String?) ?? 'token',
    issuer: m['issuer'] as String?,
    clientId: m['client_id'] as String?,
    deviceEndpoint: m['device_authorization_endpoint'] as String?,
    tokenEndpoint: m['token_endpoint'] as String?,
    error: m['error'] as String?,
  );

  /// Ask a server how to log in. Never throws: an older server has no such
  /// route and a 404 simply means "device tokens", which is the correct answer.
  static Future<AuthConfig> discover(
    String baseUrl, {
    http.Client? client,
  }) async {
    final own = client == null;
    final c = client ?? http.Client();
    try {
      final res = await c
          .get(Uri.parse('$baseUrl/api/auth/config'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 404) return const AuthConfig(mode: 'token');
      final body = jsonDecode(res.body) as Map<String, Object?>;
      return AuthConfig.fromJson(body);
    } catch (_) {
      return const AuthConfig(mode: 'token');
    } finally {
      if (own) c.close();
    }
  }
}

/// What to show the user while they approve the sign-in.
class DeviceCode {
  const DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.interval,
    required this.expiresAt,
  });

  final String deviceCode;

  /// The short code the user types, e.g. `WDJB-MJHT`.
  final String userCode;

  final String verificationUri;

  /// The URL with the code already in it. Worth preferring when it exists:
  /// on a phone this turns the whole flow into one tap.
  final String? verificationUriComplete;

  final Duration interval;
  final DateTime expiresAt;

  bool get expired => DateTime.now().isAfter(expiresAt);

  /// The best link to send someone to.
  String get bestUri => verificationUriComplete ?? verificationUri;
}

/// A sign-in that failed in a way the user has to act on.
class OidcAuthException implements Exception {
  OidcAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The tokens a completed sign-in produced.
class OidcTokens {
  const OidcTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;

  /// Treated as expired a little early: a token that is valid for two more
  /// seconds is not worth starting a request with, and the clock here and the
  /// provider's are not the same clock.
  static const skew = Duration(seconds: 60);

  bool get isFresh => DateTime.now().add(skew).isBefore(expiresAt);

  static OidcTokens fromJson(Map<String, Object?> m, {DateTime? now}) {
    final seconds = (m['expires_in'] as num?)?.toInt() ?? 300;
    return OidcTokens(
      accessToken: m['access_token'] as String? ?? '',
      refreshToken: m['refresh_token'] as String?,
      expiresAt: (now ?? DateTime.now()).add(Duration(seconds: seconds)),
    );
  }
}

/// Runs the device grant against one provider.
class OidcClient {
  OidcClient({required this.config, http.Client? client})
    : _http = client ?? http.Client();

  final AuthConfig config;
  final http.Client _http;

  static const _grant = 'urn:ietf:params:oauth:grant-type:device_code';

  /// Step one: ask the provider for a code to show the user.
  Future<DeviceCode> requestCode() async {
    final res = await _http.post(
      Uri.parse(config.deviceEndpoint!),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': config.clientId ?? '',
        'scope': 'openid profile email',
      },
    );

    final body = _json(res);
    if (res.statusCode >= 400) {
      throw OidcAuthException(_describe(body, res.statusCode));
    }

    final seconds = (body['expires_in'] as num?)?.toInt() ?? 600;
    return DeviceCode(
      deviceCode: body['device_code'] as String,
      userCode: body['user_code'] as String,
      verificationUri: body['verification_uri'] as String? ?? '',
      verificationUriComplete: body['verification_uri_complete'] as String?,
      // The provider tells us how often to poll and we obey it; polling faster
      // earns a `slow_down`, which is handled below but is better avoided.
      interval: Duration(seconds: (body['interval'] as num?)?.toInt() ?? 5),
      expiresAt: DateTime.now().add(Duration(seconds: seconds)),
    );
  }

  /// Step two: poll until the user approves, refuses, or the code expires.
  ///
  /// [onPending] fires on each unsuccessful pass so a UI can show that it is
  /// still waiting rather than looking hung.
  Future<OidcTokens> awaitApproval(
    DeviceCode code, {
    void Function()? onPending,
    bool Function()? cancelled,
  }) async {
    var interval = code.interval;

    while (true) {
      if (cancelled?.call() ?? false) {
        throw OidcAuthException('Sign-in cancelled');
      }
      if (code.expired) {
        throw OidcAuthException('The code expired. Start again.');
      }

      await Future<void>.delayed(interval);

      final res = await _http.post(
        Uri.parse(config.tokenEndpoint!),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': _grant,
          'device_code': code.deviceCode,
          'client_id': config.clientId ?? '',
        },
      );
      final body = _json(res);

      if (res.statusCode == 200) return OidcTokens.fromJson(body);

      switch (body['error']) {
        case 'authorization_pending':
          onPending?.call();
          continue;
        case 'slow_down':
          // Required by the RFC: back off by five seconds and keep going.
          interval += const Duration(seconds: 5);
          onPending?.call();
          continue;
        case 'expired_token':
          throw OidcAuthException('The code expired. Start again.');
        case 'access_denied':
          throw OidcAuthException('Sign-in was refused.');
        default:
          throw OidcAuthException(_describe(body, res.statusCode));
      }
    }
  }

  /// Exchange a refresh token for a new access token.
  ///
  /// Throws [OidcAuthException] when the provider says the grant is no longer
  /// valid, which means the session is over and the user has to sign in again.
  Future<OidcTokens> refresh(String refreshToken) async {
    final res = await _http.post(
      Uri.parse(config.tokenEndpoint!),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': config.clientId ?? '',
      },
    );
    final body = _json(res);
    if (res.statusCode != 200) {
      throw OidcAuthException(_describe(body, res.statusCode));
    }
    return OidcTokens.fromJson(body);
  }

  void dispose() => _http.close();

  Map<String, Object?> _json(http.Response res) {
    try {
      return jsonDecode(res.body) as Map<String, Object?>;
    } catch (_) {
      return const {};
    }
  }

  String _describe(Map<String, Object?> body, int status) {
    final code = body['error'] as String?;
    final detail = body['error_description'] as String?;
    if (code == null) return 'The provider returned HTTP $status.';
    // Worth naming outright: it is the single most common setup mistake, and
    // "unauthorized_client" on its own sends people looking at their password.
    if (code == 'unauthorized_client') {
      return 'This client is not allowed to use the device flow. Enable '
          '"OAuth 2.0 Device Authorization Grant" on the Keycloak client.';
    }
    return detail == null || detail.isEmpty ? code : '$code: $detail';
  }
}

/// Holds the tokens for a signed-in session and keeps the access token fresh.
///
/// [load] and [save] are how it persists; the service owns the storage so this
/// class stays testable without a database.
class OidcSession {
  OidcSession({
    required this.client,
    required OidcTokens tokens,
    required Future<void> Function(OidcTokens) save,
    // Named parameters cannot be private, so an initialising formal is not
    // available for either of these - the lint's suggestion does not compile.
    // ignore: prefer_initializing_formals
  }) : _tokens = tokens,
       // ignore: prefer_initializing_formals
       _save = save;

  final OidcClient client;
  final Future<void> Function(OidcTokens) _save;

  OidcTokens _tokens;
  OidcTokens get tokens => _tokens;

  /// The in-flight refresh, if there is one.
  ///
  /// Single-flight, and it has to be: **Keycloak rotates refresh tokens by
  /// default**, so a second refresh started while the first is in the air
  /// spends a token the first one has already replaced, and the provider
  /// rejects it - which looks exactly like "your session ended" and signs a
  /// perfectly good device out. Sync polls on a timer and on resume, so two
  /// overlapping calls is a normal Tuesday, not a rare race.
  Future<String>? _refreshing;

  /// A usable access token, refreshing first if the current one is stale.
  Future<String> accessToken() async {
    if (_tokens.isFresh) return _tokens.accessToken;
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<String> _doRefresh() async {
    final refresh = _tokens.refreshToken;
    if (refresh == null || refresh.isEmpty) {
      throw OidcAuthException('Signed out — sign in again.');
    }

    final next = await client.refresh(refresh);
    // A provider that does not rotate returns no new refresh token; keep the
    // one we have rather than dropping the session on the next call.
    _tokens = OidcTokens(
      accessToken: next.accessToken,
      refreshToken: next.refreshToken ?? refresh,
      expiresAt: next.expiresAt,
    );
    await _save(_tokens);
    return _tokens.accessToken;
  }
}
