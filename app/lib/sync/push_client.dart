// The four push routes on the sync server (server/push.js, server/index.js).
// Separate from SyncClient because nothing here is part of a sync: these are
// one-off calls from the settings sheet, and none of them touches the store.

import 'dart:convert';

import 'package:http/http.dart' as http;

class PushException implements Exception {
  PushException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PushClient {
  PushClient({required this.baseUrl, required this.token, http.Client? client})
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

  /// The server's public key, which a browser subscribes against.
  Future<String> publicKey() async {
    final res = await _call(() => _http.get(_endpoint('/api/push/key'), headers: _headers));
    final key = (jsonDecode(res.body) as Map)['publicKey'];
    if (key is! String) throw PushException('The server sent no push key.');
    return key;
  }

  /// [subscription] is the browser's subscription JSON, passed through as is.
  Future<void> register(String subscription) => _call(() => _http.put(
        _endpoint('/api/push/subscription'),
        headers: _headers,
        body: subscription,
      ));

  Future<void> unregister(String endpoint) => _call(() => _http.delete(
        _endpoint('/api/push/subscription'),
        headers: _headers,
        body: jsonEncode({'endpoint': endpoint}),
      ));

  Future<void> test(String endpoint) => _call(() => _http.post(
        _endpoint('/api/push/test'),
        headers: _headers,
        body: jsonEncode({'endpoint': endpoint}),
      ));

  Future<http.Response> _call(Future<http.Response> Function() send) async {
    final http.Response res;
    try {
      res = await send().timeout(_timeout);
    } catch (_) {
      throw PushException('Could not reach the server.');
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return res;
    throw PushException(switch (res.statusCode) {
      401 => 'Token rejected. Check the token in Settings.',
      // A server from before push answers its HTML page or a plain 404.
      404 when !res.body.contains('"error"') =>
        'This server is too old for notifications. Update it first.',
      _ => _errorOf(res.body) ?? 'The server answered ${res.statusCode}.',
    });
  }

  static String? _errorOf(String body) {
    try {
      final e = (jsonDecode(body) as Map)['error'];
      return e is String ? e : null;
    } catch (_) {
      return null;
    }
  }

  void dispose() => _http.close();
}
