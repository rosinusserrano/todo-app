import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo_widget/window_spots.dart';

void main() {
  // A 1920x1080 screen with a 48px taskbar along the bottom.
  const area = Rect.fromLTWH(0, 0, 1920, 1032);
  const m = kWindowMargin;

  test('each spot sits against its corners, inside the margin', () {
    const size = Size(340, 480);
    Rect at(WindowSpot s) => placeWindow(area: area, size: size, spot: s);
    expect(at(WindowSpot.topLeft).topLeft, const Offset(m, m));
    expect(at(WindowSpot.topRight).topRight, const Offset(1920 - m, m));
    expect(at(WindowSpot.bottomLeft).bottomLeft, const Offset(m, 1032 - m));
    expect(
      at(WindowSpot.bottomRight).bottomRight,
      const Offset(1920 - m, 1032 - m),
    );
    expect(at(WindowSpot.center).center, area.center);
  });

  test('tall is the height of the work area, not of the screen', () {
    final size = WindowSize.tall.within(area);
    expect(size.height, 1032 - 2 * m);
    final r = placeWindow(area: area, size: size, spot: WindowSpot.topRight);
    expect(r.bottom, 1032 - m, reason: 'clear of the taskbar');
  });

  test('a size never exceeds a small screen', () {
    const small = Rect.fromLTWH(0, 0, 800, 500);
    final size = WindowSize.large.within(small);
    expect(size.width, lessThanOrEqualTo(800 - 2 * m));
    expect(size.height, lessThanOrEqualTo(500 - 2 * m));
  });

  test('the spot a window is in is read off where its middle is', () {
    expect(
      spotOf(const Rect.fromLTWH(1500, 500, 340, 480), area),
      WindowSpot.bottomRight,
    );
    expect(
      spotOf(const Rect.fromLTWH(20, 20, 340, 480), area),
      WindowSpot.topLeft,
    );
    expect(
      spotOf(const Rect.fromLTWH(800, 300, 340, 480), area),
      WindowSpot.center,
    );
  });

  test('growing keeps the corner it is in', () {
    // The widget parked bottom-right gets Large: it grows up and left.
    const parked = Rect.fromLTWH(1572, 544, 340, 480);
    final spot = spotOf(parked, area);
    final r = placeWindow(
      area: area,
      size: WindowSize.large.within(area),
      spot: spot,
    );
    expect(r.bottomRight, parked.bottomRight);
  });

  test('the work area is the screen the window is on', () {
    const right = Rect.fromLTWH(1920, 0, 2560, 1400);
    expect(
      areaFor(const Rect.fromLTWH(2500, 100, 340, 480), [area, right], area),
      right,
    );
    expect(
      areaFor(const Rect.fromLTWH(-900, 100, 340, 480), [area, right], area),
      area,
      reason: 'off every screen: the primary one',
    );
  });

  group('WindowMode', () {
    test(
      'the defaults are small in the bottom left and large in the middle',
      () {
        final small = kDefaultWindowModes[0].placeIn(area);
        expect(small.size, const Size(340, 480));
        expect(small.bottomLeft, const Offset(m, 1032 - m));
        final large = kDefaultWindowModes[1].placeIn(area);
        expect(large.center, area.center);
        expect(large.width, greaterThan(1000));
      },
    );

    test('a saved size is kept, and shrunk only to fit', () {
      const mode = WindowMode(
        spot: WindowSpot.topRight,
        width: 600,
        height: 2000,
      );
      final r = mode.placeIn(area);
      expect(r.width, 600);
      expect(r.height, 1032 - 2 * m);
      expect(r.topRight, const Offset(1920 - m, m));
    });

    test('labels say what and where', () {
      expect(kDefaultWindowModes[0].label, 'Small · bottom left');
      expect(
        const WindowMode(
          spot: WindowSpot.center,
          width: 900,
          height: 700,
        ).label,
        '900 × 700 · centre',
      );
    });

    test('round-trips through the setting', () {
      final modes = [
        ...kDefaultWindowModes,
        const WindowMode(spot: WindowSpot.topLeft, width: 500, height: 400),
      ];
      expect(decodeWindowModes(encodeWindowModes(modes)), modes);
    });

    test('nothing stored is the defaults; an emptied list stays empty', () {
      expect(decodeWindowModes(null), kDefaultWindowModes);
      expect(decodeWindowModes('[]'), isEmpty);
    });

    test('a bad entry drops itself, not the list', () {
      final modes = decodeWindowModes(
        '[{"spot":"nowhere","size":"small"},'
        '{"spot":"center","width":-1,"height":5},'
        '{"spot":"center","size":"large"}]',
      );
      expect(modes, [
        const WindowMode(spot: WindowSpot.center, size: WindowSize.large),
      ]);
      expect(decodeWindowModes('not json'), kDefaultWindowModes);
    });
  });
}
