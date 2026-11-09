// The server's user management, as seen from the app (see server/index.js).
//
// Separate from SyncClient because it is a different job on the same
// connection: sync runs constantly and must never throw at the UI, while these
// are one-shot actions a human just asked for and whose failure is worth a
// sentence on screen. Hence the different error style - `AdminException` rather
// than a SyncFailed value - and hence the separate file.
//
// The user routes are not reachable without an admin account: the server
// answers 403, and the app does not show the panel at all unless /api/me said
// admin. Both checks exist on purpose; the client one is only to avoid showing
// a door that will not open. The API-token calls at the end are every
// account's own.

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
    this.scope,
  });

  final String id;
  final String label;
  final DateTime? lastSeenAt;
  final bool revoked;

  /// Null for a device token; `inbox` for an API token, `notify` for a
  /// notify-only one (server/users.js).
  final String? scope;

  static ServerToken fromJson(Map<String, dynamic> j) => ServerToken(
        id: j['id'] as String,
        label: (j['label'] as String?) ?? 'device',
        lastSeenAt: DateTime.tryParse((j['last_seen_at'] as String?) ?? '')?.toLocal(),
        revoked: j['revoked'] == true,
        scope: j['scope'] as String?,
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

/// One day's or one account's counters (server/traffic.js).
class TrafficCounts {
  const TrafficCounts({
    this.requests = 0,
    this.syncs = 0,
    this.rowsIn = 0,
    this.rowsOut = 0,
    this.bytesIn = 0,
    this.bytesOut = 0,
  });

  final int requests;
  final int syncs;
  final int rowsIn;
  final int rowsOut;
  final int bytesIn;
  final int bytesOut;

  int get bytes => bytesIn + bytesOut;

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  static TrafficCounts fromJson(Map<String, dynamic> j) => TrafficCounts(
    requests: _int(j['requests']),
    syncs: _int(j['syncs']),
    rowsIn: _int(j['rows_in']),
    rowsOut: _int(j['rows_out']),
    bytesIn: _int(j['bytes_in']),
    bytesOut: _int(j['bytes_out']),
  );
}

class TrafficDay {
  const TrafficDay({
    required this.day,
    required this.counts,
    required this.activeUsers,
  });

  /// `YYYY-MM-DD`, the server's local date.
  final String day;
  final TrafficCounts counts;
  final int activeUsers;

  static TrafficDay fromJson(Map<String, dynamic> j) => TrafficDay(
    day: j['day'] as String,
    counts: TrafficCounts.fromJson(j),
    activeUsers: TrafficCounts._int(j['active_users']),
  );
}

class TrafficAccount {
  const TrafficAccount({
    required this.id,
    required this.label,
    required this.admin,
    required this.counts,
    required this.activeDays,
    required this.lastSeenAt,
    required this.devicesOnline,
    required this.rowsStored,
    required this.blobBytes,
  });

  final String id;
  final String label;
  final bool admin;
  final TrafficCounts counts;
  final int activeDays;

  /// The most recent use of any of the account's tokens.
  final DateTime? lastSeenAt;

  /// Open instant-sync streams: running apps, roughly.
  final int devicesOnline;

  /// Live rows across every synced table.
  final int rowsStored;
  final int blobBytes;

  static TrafficAccount fromJson(Map<String, dynamic> j) => TrafficAccount(
    id: j['id'] as String,
    label: (j['label'] as String?) ?? j['id'] as String,
    admin: j['admin'] == true,
    counts: TrafficCounts.fromJson(j),
    activeDays: TrafficCounts._int(j['active_days']),
    lastSeenAt: DateTime.tryParse(
      (j['last_seen_at'] as String?) ?? '',
    )?.toLocal(),
    devicesOnline: TrafficCounts._int(j['devices_online']),
    rowsStored: TrafficCounts._int(j['rows_stored']),
    blobBytes: TrafficCounts._int(j['blob_bytes']),
  );
}

/// What `GET /api/admin/traffic` answers: every day of the window, oldest
/// first, and every account with its totals over it.
class TrafficOverview {
  const TrafficOverview({
    required this.days,
    required this.accounts,
    required this.totals,
    required this.devicesOnline,
  });

  final List<TrafficDay> days;
  final List<TrafficAccount> accounts;
  final TrafficCounts totals;
  final int devicesOnline;

  static TrafficOverview fromJson(Map<String, dynamic> j) => TrafficOverview(
    days: ((j['daily'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TrafficDay.fromJson)
        .toList(),
    accounts: ((j['users'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TrafficAccount.fromJson)
        .toList(),
    totals: TrafficCounts.fromJson(
      (j['totals'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    devicesOnline: TrafficCounts._int(j['devices_online']),
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
    // A 401 is the exception: "Invalid token" says less than where to fix it.
    final message = res.statusCode == 401
        ? 'Token rejected. Check the token in Settings.'
        : _errorOf(res.body) ??
            switch (res.statusCode) {
              403 => 'This account cannot do that on this server.',
              // An older server lacks the route, and Express answers HTML.
              404 => 'The server does not have this yet. Update it.',
              _ => 'The server answered ${res.statusCode}.',
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

  /// Who has been using the server, per day and per account, over the last
  /// [days] days.
  Future<TrafficOverview> traffic({int days = 30}) async {
    final body = await _send('GET', '/api/admin/traffic?days=$days');
    return TrafficOverview.fromJson(body);
  }

  // ------------------------------------------------------------ API tokens
  //
  // Not admin routes: any account manages its own (server/index.js, *your
  // tokens*). Here because they are the same kind of call - one-shot, a
  // person waiting on the answer - on the same connection.

  /// This account's narrowed tokens, revoked ones left out.
  Future<List<ServerToken>> apiTokens() async {
    final body = await _send('GET', '/api/tokens');
    return ((body['tokens'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ServerToken.fromJson)
        .toList();
  }

  Future<String> addApiToken(String label) async {
    final body = await _send('POST', '/api/tokens', body: {'label': label});
    final token = body['token'];
    if (token is! String) throw AdminException('The server did not return a token.');
    return token;
  }

  Future<void> revokeApiToken(ServerToken token) =>
      _send('POST', '/api/tokens/${Uri.encodeComponent(token.id)}/revoke');

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
