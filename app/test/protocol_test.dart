// The version handshake between this app and a server.
//
// What is being defended is mostly the *absent* case. The check has to be
// invisible against every server already deployed - none of which sends these
// fields - or turning it on would have been a flag day where nothing synced
// until every machine was updated at once, which is exactly the kind of upgrade
// the number exists to avoid.
//
// The rest is that a mismatch is reported in the right direction. One message
// for both ends sends the user to the wrong machine half the time: there is
// nothing to be done on a phone about a server that needs deploying.

import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/sync/protocol.dart';
import 'package:todo_widget/sync/sync_client.dart';

void main() {
  group('what a server said', () {
    test('a server that has never heard of this is protocol 1', () {
      // Not an error and not a refusal: 1 is what the wire was on the day the
      // number was invented, so silence means 1 by definition.
      final old = ServerProtocol.fromJson({
        'ok': true,
        'service': 'todo-widget-sync',
        'version': 1,
      });
      expect(old.speaks, 1);
      expect(old.minClient, 1);
      expect(old.compatibility, Compatibility.ok);
    });

    test('a body that is not a map at all falls back rather than throwing', () {
      expect(ServerProtocol.fromJson(null).speaks, 1);
      expect(ServerProtocol.fromJson('nonsense').speaks, 1);
    });

    test('numbers arriving as strings or doubles still count', () {
      // A hand-rolled proxy or a JSON encoder with opinions should not read as
      // an incompatible server.
      expect(ServerProtocol.fromJson({'protocol': '4'}).speaks, 4);
      expect(ServerProtocol.fromJson({'protocol': 4.0}).speaks, 4);
      expect(ServerProtocol.fromJson({'minClient': '2'}).minClient, 2);
    });

    test('a field that is meaningless leaves that field at its default', () {
      final p = ServerProtocol.fromJson({'protocol': 'soon', 'minClient': 1});
      expect(p.speaks, 1);
      expect(p.minClient, 1);
    });
  });

  group('who has to update', () {
    test('an equal pair is compatible', () {
      const p = ServerProtocol(speaks: kSyncProtocol, minClient: kSyncProtocol);
      expect(p.compatibility.isOk, isTrue);
    });

    test('a server ahead of us, but still accepting us, is fine', () {
      // The normal case for a server deployed before the phones are updated:
      // it speaks something newer and still accepts the older wire. Refusing
      // here would make every deploy a lockout.
      const p = ServerProtocol(speaks: kSyncProtocol + 5, minClient: 1);
      expect(p.compatibility.isOk, isTrue);
    });

    test('a server that will not accept this app says update the app', () {
      const p = ServerProtocol(
        speaks: kSyncProtocol + 1,
        minClient: kSyncProtocol + 1,
      );
      expect(p.compatibility, Compatibility.appTooOld);
      expect(p.compatibility.title, 'Update the app');
      expect(p.compatibility.summary(p), contains('too old for this server'));
    });

    test('a server older than this app will talk to says update the server',
        () {
      // Only reachable once kMinServerProtocol has been raised; pinned now so
      // the day it is raised, the sentence is already the right way round.
      final p = ServerProtocol(
        speaks: kMinServerProtocol - 1,
        minClient: 1,
      );
      expect(p.compatibility, Compatibility.serverTooOld);
      expect(p.compatibility.title, 'Update the server');
      expect(p.compatibility.summary(p), contains('too old for this app'));
    });

    test('the two sentences name different machines', () {
      const app = ServerProtocol(
        speaks: kSyncProtocol + 1,
        minClient: kSyncProtocol + 1,
      );
      final server = ServerProtocol(speaks: kMinServerProtocol - 1, minClient: 1);
      expect(app.compatibility.summary(app),
          isNot(equals(server.compatibility.summary(server))));
    });
  });

  group('the identity call carries it too', () {
    test('/api/me is read for the same pair', () {
      // So the sync loop learns the wire on a request it was already making,
      // rather than paying for a second one every cycle.
      final id = ServerIdentity.parse(
        '{"user":"local","label":"Marco","admin":true,'
        '"protocol":3,"minClient":2}',
      );
      expect(id, isNotNull);
      expect(id!.protocol.speaks, 3);
      expect(id.protocol.minClient, 2);
    });

    test('an older server answering /api/me is still legacy, not broken', () {
      final id = ServerIdentity.parse('{"user":"local","label":"Marco"}');
      expect(id, isNotNull);
      expect(id!.protocol.speaks, 1);
      expect(id.admin, isFalse);
    });
  });
}
