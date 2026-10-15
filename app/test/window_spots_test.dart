import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todo_widget/app_state.dart';
import 'package:todo_widget/layout.dart';
import 'package:todo_widget/sync/local_store.dart';
import 'package:todo_widget/ui/title_bar.dart';
import 'package:todo_widget/window_spots.dart';

void main() {
  // A 1920x1080 screen with a 48px taskbar along the bottom, and a second
  // 1280x1024 one to its right.
  const main = Rect.fromLTWH(0, 0, 1920, 1032);
  const side = Rect.fromLTWH(1920, 0, 1280, 1024);

  const corner = WindowMode(
    name: 'Corner',
    bounds: Rect.fromLTWH(10, 540, 340, 480),
    area: main,
  );

  group('placeIn', () {
    test('on the screen it was saved on, the bounds are used as they are', () {
      expect(corner.placeIn([main, side], main), corner.bounds);
    });

    test('a mode saved on the other screen goes back there', () {
      const there = WindowMode(
        name: 'There',
        bounds: Rect.fromLTWH(2000, 100, 800, 600),
        area: side,
      );
      expect(there.placeIn([main, side], main), there.bounds);
    });

    test('with its screen gone, it lands in proportion on this one', () {
      const there = WindowMode(
        name: 'There',
        bounds: Rect.fromLTWH(2560, 512, 640, 512),
        area: side,
      );
      // Right half, lower half, of the side screen -> of the main one.
      expect(
        there.placeIn([main], main),
        const Rect.fromLTWH(960, 516, 960, 516),
      );
    });

    test('a window hanging off an edge is pulled back on', () {
      const off = WindowMode(
        name: 'Off',
        bounds: Rect.fromLTWH(1800, 900, 340, 480),
        area: main,
      );
      final r = off.placeIn([main], main);
      expect(r.size, const Size(340, 480));
      expect(r.bottomRight, const Offset(1920, 1032));
    });
  });

  test('fitInto shrinks only what cannot fit', () {
    expect(
      fitInto(const Rect.fromLTWH(-50, 10, 3000, 400), main),
      const Rect.fromLTWH(0, 10, 1920, 400),
    );
  });

  test('areaFor picks the screen holding the middle, else the primary', () {
    const w = Rect.fromLTWH(2000, 100, 400, 300);
    expect(areaFor(w, [main, side], main), side);
    expect(
      areaFor(const Rect.fromLTWH(-900, -900, 100, 100), [main, side], main),
      main,
    );
  });

  group('the setting', () {
    test('round-trips', () {
      final modes = [
        corner,
        const WindowMode(
          name: 'Big',
          bounds: Rect.fromLTWH(200, 100, 1500, 850),
          area: main,
        ),
      ];
      expect(decodeWindowModes(encodeWindowModes(modes)), modes);
    });

    test('nothing stored is no modes - there are no presets', () {
      expect(decodeWindowModes(null), isEmpty);
    });

    test('a bad entry drops itself, not the list', () {
      final modes = decodeWindowModes(
        '[{"name":"No area","bounds":[0,0,10,10]},'
        '{"name":"Flat","bounds":[0,0,0,10],"area":[0,0,100,100]},'
        '{"spot":"center","size":"large"},'
        '${encodeWindowModes([corner]).substring(1)}',
      );
      expect(modes, [corner]);
      expect(decodeWindowModes('not json'), isEmpty);
    });
  });

  group('AppState', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    Future<(LocalStore, AppState)> fresh() async {
      final store = await LocalStore.open(
        path: inMemoryDatabasePath,
        singleInstance: false,
      );
      final s = AppState(store);
      await s.load();
      return (store, s);
    }

    test(
      'starts with none, keeps what is saved, and survives a restart',
      () async {
        final (store, s) = await fresh();
        expect(s.windowModes, isEmpty);
        await s.addWindowMode(corner);
        final again = AppState(store);
        await again.load();
        expect(again.windowModes, [corner]);
      },
    );

    test('saving under a taken name replaces that one in its place', () async {
      final (_, s) = await fresh();
      const big = WindowMode(
        name: 'Big',
        bounds: Rect.fromLTWH(200, 100, 1500, 850),
        area: main,
      );
      await s.addWindowMode(corner);
      await s.addWindowMode(big);
      const moved = WindowMode(
        name: 'Corner',
        bounds: Rect.fromLTWH(1570, 540, 340, 480),
        area: main,
      );
      await s.addWindowMode(moved);
      expect(s.windowModes, [moved, big]);
      await s.removeWindowMode(moved);
      expect(s.windowModes, [big]);
    });
  });

  testWidgets('the naming sheet returns the name, and warns of a replace', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: LayoutScope(
          layout: const Layout(Size(340, 600)),
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await askWindowModeName(context, taken: ['Corner']),
              child: const Text('save'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Corner');
    await tester.pump();
    expect(find.text('Replaces the one with this name'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  Big  ');
    await tester.pump();
    expect(find.text('Replaces the one with this name'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(result, 'Big');
  });
}
