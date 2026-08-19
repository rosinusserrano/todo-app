// The version of what this app and a server say to each other.
//
// The mirror of `server/protocol.js`, and the rule for moving these numbers is
// written out there. In short: this is not the app's version and not the
// server's - both of those move on every release, and almost every release
// leaves the wire exactly as it was. A new optional column does not move it; a
// required field, a changed meaning or an endpoint the client cannot work
// without does.
//
// Why a number rather than a table of "app 0.24.x works with server 1.2-1.4":
// the table is a second thing to edit on every release, it goes stale in
// silence, and its failure mode is claiming a pair works when it does not.
//
// **An absent number is 1.** A server that predates the handshake sends
// neither field, and that is not an error - protocol 1 is what the wire was on
// the day the number was invented. Without that rule this would have been a
// flag day for every server already running, which is precisely the kind of
// upgrade this feature exists to avoid.

/// The wire this build speaks.
const kSyncProtocol = 1;

/// The oldest server wire this build can still talk to correctly.
///
/// Separate from [kSyncProtocol] and raised far more rarely: raising it stops
/// this app talking to servers that are merely behind, so it is for the case
/// where carrying on would write something wrong.
const kMinServerProtocol = 1;

/// What a server said about itself.
class ServerProtocol {
  const ServerProtocol({required this.speaks, required this.minClient});

  /// The wire the server speaks.
  final int speaks;

  /// The oldest client wire it will accept.
  final int minClient;

  /// What a server that has never heard of the handshake is, by definition.
  static const legacy = ServerProtocol(speaks: 1, minClient: 1);

  /// Reads the pair out of any JSON body that might carry it (`/api/health`
  /// and `/api/me` both do). Anything missing or malformed falls back to
  /// [legacy]'s value for that field rather than failing: a server is allowed
  /// not to know about this, and a client that treated silence as a refusal
  /// would refuse every server deployed before today.
  factory ServerProtocol.fromJson(Object? body) {
    if (body is! Map) return legacy;
    return ServerProtocol(
      speaks: _int(body['protocol']) ?? legacy.speaks,
      minClient: _int(body['minClient']) ?? legacy.minClient,
    );
  }

  static int? _int(Object? v) => switch (v) {
    final int i => i,
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };

  Compatibility get compatibility {
    // The app's side is checked first only because it is the one the user can
    // act on themselves; both are reported honestly either way.
    if (kSyncProtocol < minClient) return Compatibility.appTooOld;
    if (speaks < kMinServerProtocol) return Compatibility.serverTooOld;
    return Compatibility.ok;
  }

  @override
  String toString() => 'ServerProtocol(speaks: $speaks, minClient: $minClient)';
}

/// Which end is behind, because they are different sentences.
///
/// One message for both would send the user to the wrong machine half the time:
/// there is nothing to be done on a phone about a server that needs deploying,
/// and nothing to be done on the server about an app that needs updating.
enum Compatibility {
  ok,

  /// This app is older than the server will accept.
  appTooOld,

  /// The server is older than this app will talk to.
  serverTooOld;

  bool get isOk => this == Compatibility.ok;

  /// The headline for the alert, in the user's terms rather than the wire's.
  String get title => switch (this) {
    Compatibility.ok => 'Up to date',
    Compatibility.appTooOld => 'Update the app',
    Compatibility.serverTooOld => 'Update the server',
  };

  /// One line for the sync status, which has room for a sentence and no more.
  String summary(ServerProtocol server) => switch (this) {
    Compatibility.ok => 'Compatible.',
    Compatibility.appTooOld =>
      'This app is too old for this server. Syncing is off until you update '
          'it (this app speaks sync $kSyncProtocol, the server needs at least '
          '${server.minClient}).',
    Compatibility.serverTooOld =>
      'This server is too old for this app. Syncing is off until it is '
          'updated (the server speaks sync ${server.speaks}, this app needs at '
          'least $kMinServerProtocol).',
  };
}
