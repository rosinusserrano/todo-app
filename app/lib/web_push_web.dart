import 'dart:js_interop';

@JS('todoPush.state')
external JSPromise<JSString> _state();

@JS('todoPush.enable')
external JSPromise<JSString?> _enable(JSString publicKey);

@JS('todoPush.current')
external JSPromise<JSString?> _current();

@JS('todoPush.disable')
external JSPromise<JSString?> _disable();

/// See web_push.dart. Every call fails soft: a page missing its helper (an
/// index.html from before this existed) reads as "unsupported", not a crash.
class WebPush {
  /// 'unsupported', 'install' (iOS outside the home-screen app), 'denied',
  /// 'off' or 'on'.
  static Future<String> state() async {
    try {
      return (await _state().toDart).toDart;
    } catch (_) {
      return 'unsupported';
    }
  }

  /// Asks for permission and subscribes. The subscription as JSON, or null
  /// when permission was not given. Must be called straight from a tap, with
  /// nothing awaited first - the browser shows the prompt only then.
  static Future<String?> enable(String publicKey) async =>
      (await _enable(publicKey.toJS).toDart)?.toDart;

  /// This browser's subscription as JSON, or null.
  static Future<String?> current() async {
    try {
      return (await _current().toDart)?.toDart;
    } catch (_) {
      return null;
    }
  }

  /// Unsubscribes; returns the endpoint that was given up, or null.
  static Future<String?> disable() async =>
      (await _disable().toDart)?.toDart;
}
