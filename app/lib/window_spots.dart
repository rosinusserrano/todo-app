// Preset sizes and places for the desktop window.
//
// The widget lives in a corner of the screen at its own small size most of
// the time, and every so often wants to be big for a while - the week, a long
// note - and then go back. Dragging an edge and a title bar to get there and
// back is two fiddly gestures each way, so the title bar offers both answers
// as presets: a size, and a spot.
//
// The two are independent. Picking a size keeps the window where it is -
// anchored on the corner it is nearest, so a widget in the bottom-right
// grows up and to the left instead of off the screen. Picking a spot keeps
// its size. Both are measured against the *work area* of the screen the
// window is on (the screen minus the taskbar), never the whole screen.
//
// Pure maths, so it is tested without a window; main.dart does the asking
// (`window_manager`, `screen_retriever`).

import 'dart:math' as math;
import 'dart:ui';

/// The gap kept between the window and the edge of the work area.
const kWindowMargin = 8.0;

enum WindowSize {
  /// The widget: the size it was designed at.
  small('Small'),

  /// A column the height of the screen: room for a long list or a day.
  tall('Tall'),

  /// Most of the screen: the week beside the list.
  large('Large');

  const WindowSize(this.label);
  final String label;

  /// What this size is on a work area [area], never more than fits.
  Size within(Rect area) {
    final room = Size(
      area.width - 2 * kWindowMargin,
      area.height - 2 * kWindowMargin,
    );
    final want = switch (this) {
      WindowSize.small => const Size(340, 480),
      WindowSize.tall => Size(420, room.height),
      WindowSize.large => Size(
        math.min(1280, area.width * 0.8),
        math.min(860, area.height * 0.85),
      ),
    };
    return Size(
      math.min(want.width, room.width),
      math.min(want.height, room.height),
    );
  }
}

enum WindowSpot {
  topLeft('Top left'),
  topRight('Top right'),
  center('Centre'),
  bottomLeft('Bottom left'),
  bottomRight('Bottom right');

  const WindowSpot(this.label);
  final String label;
}

/// The spot a window at [window] is already in: a corner by which quarter of
/// [area] its middle is in, or the centre when its middle is in the middle
/// third both ways.
WindowSpot spotOf(Rect window, Rect area) {
  final c = window.center;
  final third = Size(area.width / 3, area.height / 3);
  final middle = Rect.fromLTWH(
    area.left + third.width,
    area.top + third.height,
    third.width,
    third.height,
  );
  if (middle.contains(c)) return WindowSpot.center;
  final left = c.dx < area.center.dx;
  final top = c.dy < area.center.dy;
  return top
      ? (left ? WindowSpot.topLeft : WindowSpot.topRight)
      : (left ? WindowSpot.bottomLeft : WindowSpot.bottomRight);
}

/// Where a window of [size] goes at [spot] in [area].
Rect placeWindow({
  required Rect area,
  required Size size,
  required WindowSpot spot,
}) {
  final w = math.min(size.width, area.width - 2 * kWindowMargin);
  final h = math.min(size.height, area.height - 2 * kWindowMargin);
  final left = area.left + kWindowMargin;
  final right = area.right - kWindowMargin - w;
  final top = area.top + kWindowMargin;
  final bottom = area.bottom - kWindowMargin - h;
  final at = switch (spot) {
    WindowSpot.topLeft => Offset(left, top),
    WindowSpot.topRight => Offset(right, top),
    WindowSpot.bottomLeft => Offset(left, bottom),
    WindowSpot.bottomRight => Offset(right, bottom),
    WindowSpot.center => Offset(area.center.dx - w / 2, area.center.dy - h / 2),
  };
  return at & Size(w, h);
}

/// The work area of whichever of [areas] holds the middle of [window], or
/// [fallback] (the primary screen's) when none does - a window dragged half
/// off every screen still has to land somewhere.
Rect areaFor(Rect window, List<Rect> areas, Rect fallback) {
  for (final a in areas) {
    if (a.contains(window.center)) return a;
  }
  return fallback;
}
