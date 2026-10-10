// The zoom row in settings: − 130% +, a tap on the number for 100%, and the
// ends disabled rather than silently doing nothing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/sync/sync_service.dart';
import 'package:todo_widget/theme.dart';
import 'package:todo_widget/ui/settings_sheet.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<List<double>> pumpSheet(WidgetTester tester, double zoom) async {
    // Real I/O, so outside the test's fake clock or it never completes.
    final store = (await tester.runAsync(() => LocalStore.open(
          path: inMemoryDatabasePath,
          singleInstance: false,
        )))!;
    final sync = SyncService(store);
    addTearDown(() async {
      sync.dispose();
      await tester.runAsync(store.close);
    });
    final asked = <double>[];
    tester.view.physicalSize = const Size(340, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          SettingsSheet(
            sync: sync,
            accent: T.accent,
            onClose: () {},
            zoom: zoom,
            onZoom: asked.add,
          ),
        ]),
      ),
    ));
    await tester.pump();
    return asked;
  }

  testWidgets('the buttons step, the number resets', (tester) async {
    final asked = await pumpSheet(tester, 1.3);
    expect(find.text('130%'), findsOneWidget);

    await tester.tap(find.byTooltip('Larger'));
    await tester.tap(find.byTooltip('Smaller'));
    await tester.tap(find.text('130%'));
    expect(asked, [1.4, 1.2, 1.0]);
  });

  testWidgets('the largest step disables Larger', (tester) async {
    final asked = await pumpSheet(tester, T.zoomSteps.last);
    await tester.tap(find.byTooltip('Larger'));
    expect(asked, isEmpty);
  });
}
