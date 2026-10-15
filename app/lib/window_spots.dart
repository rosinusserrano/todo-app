// Saved window arrangements for the desktop window.
//
// The widget lives in a corner of the screen at its own small size most of
// the time, and every so often wants to be big for a while - the week, a long
// note - and then go back. Dragging an edge and a title bar to get there and
// back is two fiddly gestures each way. So the person arranges the window by
// hand once, saves it under a name, and from then on it is one click in the
// title bar (`_WindowModes` in title_bar.dart).
//
// There are no presets. Where the widget should sit is a fact about this
// person's screen and habits, and any guess would be a row to delete; the
// one arrangement that means the same on every screen, full screen, is the
// title bar's own row and not one of these.
//
// A mode is the window's exact bounds plus the *work area* of the screen it
// was saved on (the screen minus the taskbar). The area is what lets a mode
// survive the screens changing: on the same screen the bounds are used as
// they are; when no screen holds them any more (a monitor unplugged, a
// laptop off its dock) they are carried over in proportion to the screen the
// window is on now. It also lets the menu draw where the window goes.
//
// Pure maths, so it is tested without a window; main.dart does the asking
// (`window_manager`, `screen_retriever`).

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

class WindowMode {
  const WindowMode({
    required this.name,
    required this.bounds,
    required this.area,
  });

  final String name;

  /// Where the window was and how big, in screen pixels.
  final Rect bounds;

  /// The work area of the screen it was on when it was saved.
  final Rect area;

  /// Where this mode puts the window, given the work areas of the screens
  /// there are now and [current], the one the window is on.
  Rect placeIn(List<Rect> areas, Rect current) {
    for (final a in areas) {
      if (a.contains(bounds.center)) return fitInto(bounds, a);
    }
    // Its screen has gone: the same place in proportion on this one.
    final sx = current.width / area.width;
    final sy = current.height / area.height;
    return fitInto(
      Rect.fromLTWH(
        current.left + (bounds.left - area.left) * sx,
        current.top + (bounds.top - area.top) * sy,
        bounds.width * sx,
        bounds.height * sy,
      ),
      current,
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'bounds': _rect(bounds),
    'area': _rect(area),
  };

  /// Null for anything unreadable, so one bad entry drops itself rather than
  /// the list.
  static WindowMode? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final bounds = _readRect(json['bounds']);
    final area = _readRect(json['area']);
    if (name is! String || bounds == null || area == null) return null;
    return WindowMode(name: name, bounds: bounds, area: area);
  }

  @override
  bool operator ==(Object other) =>
      other is WindowMode &&
      other.name == name &&
      other.bounds == bounds &&
      other.area == area;

  @override
  int get hashCode => Object.hash(name, bounds, area);
}

List<double> _rect(Rect r) => [r.left, r.top, r.width, r.height];

Rect? _readRect(Object? json) {
  if (json is! List || json.length != 4 || json.any((v) => v is! num)) {
    return null;
  }
  final [l, t, w, h] = [for (final v in json) (v as num).toDouble()];
  if (w <= 0 || h <= 0) return null;
  return Rect.fromLTWH(l, t, w, h);
}

/// [r] moved, and shrunk only if it has to be, so all of it is inside [area].
Rect fitInto(Rect r, Rect area) {
  final w = math.min(r.width, area.width);
  final h = math.min(r.height, area.height);
  final left = r.left.clamp(area.left, area.right - w).toDouble();
  final top = r.top.clamp(area.top, area.bottom - h).toDouble();
  return Rect.fromLTWH(left, top, w, h);
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

String encodeWindowModes(List<WindowMode> modes) =>
    jsonEncode([for (final m in modes) m.toJson()]);

/// The stored list; nothing stored, or nothing readable, is no modes.
List<WindowMode> decodeWindowModes(String? stored) {
  if (stored == null) return const [];
  try {
    final list = jsonDecode(stored);
    if (list is! List) return const [];
    return [for (final e in list) ?WindowMode.fromJson(e)];
  } on FormatException {
    return const [];
  }
}
