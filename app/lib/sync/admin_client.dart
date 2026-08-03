// The server's user management, as seen from the app (see server/index.js).
//
// Separate from SyncClient because it is a different job on the same
// connection: sync runs constantly and must never throw at the UI, while these
// are one-shot actions a human just asked for and whose failure is worth a
// sentence on screen. Hence the different error style - `AdminException` rather
// than a SyncFailed value - and hence the separate file.
//
// Nothing here is reachable without an admin account: the server answers 403,
// and the app does not show the panel at all unless /api/me said admin. Both
// checks exist on purpose; the client one is only to avoid showing a door that
// will not open.

import 'dart:convert';

import 'package:http/http.dart' as http;

class AdminException implements Exception {
  AdminException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A token as the server will describe it: everything except the token itself,
/// which exists in one response, once, and is never stored anywhere.
class ServerToken {
  const ServerToken({
    required this.id,
    required this.label,
    required this.lastSeenAt,
    required this.revoked,
  });

  final String id;
  final String label;
  final DateTime? lastSeenAt;
  final bool revoked;

  static ServerToken fromJson(Map<String, dynamic> j) => ServerToken(
        id: j['id'] as String,
        label: (j['label'] as String?) ?? 'device',
        lastSeenAt: DateTime.tryParse((j['last_seen_at'] as String?) ?? '')?.toLocal(),
        revoked: j['revoked'] == true,
      );

  String describe() {
    if (revoked) return 'revoked';
    final seen = lastSeenAt;
    if (seen == null) return 'never used';
    final ago = DateTime.now().difference(seen);
    if (ago.inMinutes < 2) return 'in use now';
    if (ago.inHours < 1) return 'last used ${ago.inMinutes}m ago';
    if (ago.inDays < 1) return 'last used ${ago.inHours}h ago';
    return 'last used ${ago.inDays}d ago';
  }
}

class ServerUser {
  const ServerUser({
    required this.id,
    required this.label,
    required this.admin,
    required this.tokens,
  });

  final String id;
  final String label;
  final bool admin;
  final List<ServerToken> tokens;

  int get activeTokens => tokens.where((t) => !t.revoked).length;

  static ServerUser fromJson(Map<String, dynamic> j) => ServerUser(
        id: j['id'] as String,
        label: (j['label'] as String?) ?? j['id'] as String,
        admin: j['admin'] == true,
        tokens: ((j['tokens'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ServerToken.fromJson)
            .toList(),
      );
}

/// A freshly minted token, on its way to the one screen that will ever show it.
class IssuedToken {
  const IssuedToken({required this.token, required this.userLabel});
  final String token;
  final String userLabel;
}

class AdminClient {
  AdminClient({required this.baseUrl, required this.token, http.Client? client})
      : _http = client ?? http.Client();

  final String baseUrl;
  final String token;
  final http.Client _http;

  static const _timeout = Duration(seconds: 15);

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Uri _endpoint(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final http.Response res;
    try {
      final uri = _endpoint(path);
      res = await switch (method) {
        'GET' => _http.get(uri, headers: _headers),
        'DELETE' => _http.delete(uri, headers: _headers),
        _ => _http.post(uri, headers: _headers, body: jsonEncode(body ?? const {})),
      }
          .timeout(_timeout);
    } catch (e) {
      throw AdminException('Could not reach the server.');
    }

    if (res.statusCode == 200) {
      try {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        throw AdminException('The server sent a malformed response.');
      }
    }

    // The server's own wording is better than anything inventable here - it is
    // the side that knows *why* ("that is the token you are using right now").
    final message = switch (res.statusCode) {
      401 => 'Token rejected. Check the token in Settings.',
      403 => 'This account cannot manage users on this server.',
      404 => 'That account no longer exists on the server.',
      // An older server has no admin routes at all, and Express answers HTML.
      _ => _errorOf(res.body) ?? 'The server answered ${res.statusCode}.',
    };
    throw AdminException(message);
  }

  Future<List<ServerUser>> users() async {
    final body = await _send('GET', '/api/admin/users');
    return ((body['users'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ServerUser.fromJson)
        .toList();
  }

  /// Creates the account and its first token in one call, because an account
  /// nobody can sign into is not a useful thing to have made.
  Future<IssuedToken> addUser(String label) async {
    final body = await _send('POST', '/api/admin/users', body: {'label': label});
    final token = body['token'];
    if (token is! String) throw AdminException('The server did not return a token.');
    return IssuedToken(token: token, userLabel: label);
  }

  Future<IssuedToken> addToken(ServerUser user, String label) async {
    final body = await _send(
      'POST',
      '/api/admin/users/${Uri.encodeComponent(user.id)}/tokens',
      body: {'label': label},
    );
    final token = body['token'];
    if (token is! String) throw AdminException('The server did not return a token.');
    return IssuedToken(token: token, userLabel: user.label);
  }

  Future<void> revokeToken(ServerToken token) =>
      _send('POST', '/api/admin/tokens/${Uri.encodeComponent(token.id)}/revoke');

  Future<void> deleteUser(ServerUser user) =>
      _send('DELETE', '/api/admin/users/${Uri.encodeComponent(user.id)}');

  void dispose() => _http.close();

  static String? _errorOf(String body) {
    try {
      final message = (jsonDecode(body) as Map)['error'];
      return message is String && message.isNotEmpty ? message : null;
    } catch (_) {
      return null;
    }
  }
}
