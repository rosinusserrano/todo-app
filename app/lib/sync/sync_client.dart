// Talks to a self-hosted sync server (see server/index.js).
//
// The server address and token are entered by the user, so every failure here
// is a *likely* one: wrong IP, server not running, laptop asleep, phone off the
// VPN. Errors are therefore modelled explicitly and carry a message worth
// showing in the UI, rather than thrown as raw exceptions.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'local_store.dart';

sealed class SyncResult {
  const SyncResult();
}

class SyncOk extends SyncResult {
  final int cursor;
  final int applied;
  final int pushed;
  const SyncOk(this.cursor, this.applied, this.pushed);
}

class SyncFailed extends SyncResult {
  final String message;

  /// True when retrying later might succeed on its own (server down, no
  /// network). False for problems the user has to fix, like a bad token.
  final bool transient;
  const SyncFailed(this.message, {this.transient = true});
}

class SyncClient {
  SyncClient({required this.baseUrl, required this.token, http.Client? client})
      : _http = client ?? http.Client();

  final String baseUrl;
  final String token;
  final http.Client _http;

  static const _timeout = Duration(seconds: 15);

  /// Normalizes what a user actually types: "192.168.2.184:8787",
  /// "http://nas.local:8787/", trailing slashes, missing scheme.
  static Uri? parseBase(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    s = s.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return null;
    return uri;
  }

  Uri _endpoint(String path) => Uri.parse('$baseUrl$path');

  /// Unauthenticated reachability check, so the UI can tell "wrong address"
  /// apart from "wrong token" instead of showing one vague failure for both.
  Future<SyncResult> checkReachable() async {
    try {
      final res = await _http.get(_endpoint('/api/health')).timeout(_timeout);
      if (res.statusCode != 200) {
        return SyncFailed('Server answered ${res.statusCode}');
      }
      final body = jsonDecode(res.body);
      if (body is! Map || body['service'] != 'todo-widget-sync') {
        return const SyncFailed(
          'That address is reachable but is not a todo sync server',
          transient: false,
        );
      }
      return const SyncOk(0, 0, 0);
    } catch (e) {
      return SyncFailed('Cannot reach server: ${_short(e)}');
    }
  }

  /// One full reconcile: push local changes, apply what comes back.
  Future<SyncResult> syncOnce(LocalStore store) async {
    final since = await store.cursor();
    final outgoing = await store.dirtyRows();

    final http.Response res;
    try {
      res = await _http
          .post(
            _endpoint('/api/sync'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'since': since, 'changes': outgoing}),
          )
          .timeout(_timeout);
    } catch (e) {
      return SyncFailed('Sync failed: ${_short(e)}');
    }

    if (res.statusCode == 401) {
      return const SyncFailed('Token rejected. Check the token from the server console.',
          transient: false);
    }
    if (res.statusCode == 400) {
      return SyncFailed('Server rejected the data: ${_errorOf(res.body)}',
          transient: false);
    }
    if (res.statusCode != 200) {
      return SyncFailed('Server answered ${res.statusCode}');
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return const SyncFailed('Server sent a malformed response');
    }

    final changes = <String, List<Map<String, Object?>>>{};
    final raw = body['changes'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        changes[entry.key as String] = (entry.value as List)
            .cast<Map<String, dynamic>>()
            .map((m) => Map<String, Object?>.from(m))
            .toList();
      }
    }

    // Order matters. Apply the server's rows first, then clear dirty flags
    // scoped to exactly what was pushed - so an edit made during the request
    // survives instead of being marked clean without ever being sent.
    await store.applyRemote(changes);
    await store.clearDirty(outgoing);

    final cursor = (body['cursor'] as num?)?.toInt() ?? since;
    await store.setCursor(cursor);

    final applied = changes.values.fold<int>(0, (n, l) => n + l.length);
    final pushed = outgoing.values.fold<int>(0, (n, l) => n + l.length);
    return SyncOk(cursor, applied, pushed);
  }

  void dispose() => _http.close();

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}...' : s;
  }

  static String _errorOf(String body) {
    try {
      return (jsonDecode(body) as Map)['error']?.toString() ?? body;
    } catch (_) {
      return body;
    }
  }
}
