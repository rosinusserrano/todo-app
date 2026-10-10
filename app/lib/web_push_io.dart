/// Native builds: there is no Web Push here, and nothing asks.
class WebPush {
  static Future<String> state() async => 'unsupported';
  static Future<String?> enable(String publicKey) async => null;
  static Future<String?> current() async => null;
  static Future<String?> disable() async => null;
}
