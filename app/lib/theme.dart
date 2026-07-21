// Design tokens ported from src/styles.css.
//
// Values are copied deliberately rather than re-picked by eye, so the Flutter
// build reads as the same app. The two duration constants here are the ones the
// old code warned about keeping in sync with CSS; now there is only one copy of
// each, which removes that hazard entirely.

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

class T {
  // --bg, --surface, --text, --muted, --accent, --danger
  static const bg = Color(0xDB1C1C22); // rgba(28,28,34,0.86)
  static const bgSolid = Color(0xFF1C1C22);
  static const surface = Color(0x0FFFFFFF); // rgba(255,255,255,0.06)
  static const surfaceHover = Color(0x1FFFFFFF); // rgba(255,255,255,0.12)
  static const text = Color(0xFFF2F2F5);
  static const muted = Color(0xFF9A9AA6);
  static const accent = Color(0xFF6C8CFF);
  static const danger = Color(0xFFFF6C6C);

  static const radius = 14.0;

  /// --hero-dur / --hero-ease. Previously duplicated between CSS and
  /// HERO_MS in main.ts.
  static const heroDur = Duration(milliseconds: 380);
  static const heroEase = Cubic(0.2, 0.9, 0.25, 1);

  /// The slide-out on a checked-off task. Was the 320ms timeout in main.ts,
  /// which had to match the `slide-out` keyframe by hand.
  static const slideOutDur = Duration(milliseconds: 320);

  static const nudgeBobDur = Duration(milliseconds: 1150);
  static const nudgeBobDistance = 9.0;

  /// Segoe UI Variable ships on Windows 11 with real optical sizes. The
  /// fallbacks matter more now than they did in the Tauri build, since this
  /// also runs on iOS and Android.
  static const fontFamily = 'Segoe UI Variable Text';
  static const fontFallback = [
    'Segoe UI Variable',
    'Segoe UI',
    '.SF UI Text',
    'Roboto',
    'system-ui',
  ];

  static const workspaceColors = [
    Color(0xFF6C8CFF), // accent blue
    Color(0xFF7EE3A1), // mint
    Color(0xFFFFCF6C), // amber
    Color(0xFFFF6C6C), // red
    Color(0xFFFF8CD9), // pink
    Color(0xFFB28CFF), // violet
    Color(0xFF6CD9FF), // cyan
    Color(0xFFE0E0E0), // neutral
  ];

  static Color parseHex(String hex) {
    final s = hex.replaceAll('#', '');
    if (s.length != 6) return accent;
    return Color(int.parse('FF$s', radix: 16));
  }

  static String toHex(Color c) {
    int ch(double v) => (v * 255).round() & 0xff;
    return '#${ch(c.r).toRadixString(16).padLeft(2, '0')}'
        '${ch(c.g).toRadixString(16).padLeft(2, '0')}'
        '${ch(c.b).toRadixString(16).padLeft(2, '0')}';
  }

  /// The window base tinted with a slice of the active workspace colour -
  /// `color-mix(in srgb, var(--ws-color) 16%, var(--bg))`.
  static Color tintedBackground(Color ws) => Color.lerp(bg, ws, 0.16)!;

  static Color tintedBorder(Color ws) =>
      Color.lerp(const Color(0x14FFFFFF), ws, 0.30)!;

  /// Hue-rotate 180 degrees from the workspace colour, but force high
  /// saturation and mid lightness. A pale or desaturated workspace colour would
  /// otherwise produce a complement too washed out to read as an alarm, which
  /// is the entire job of the side-thought bar.
  static Color complementary(Color c) {
    final hsl = HSLColor.fromColor(c);
    return HSLColor.fromAHSL(1, (hsl.hue + 180) % 360, 0.85, 0.58).toColor();
  }

  static ThemeData themeData() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: base.textTheme.apply(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFallback,
        bodyColor: text,
        displayColor: text,
      ),
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        error: danger,
        surface: bgSolid,
      ),
    );
  }
}

/// Bobbing wrapper for the focus tile. Runs only while [active], so the
/// animation is not burning frames whenever the nudge is switched off.
class NudgeBob extends StatefulWidget {
  const NudgeBob({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<NudgeBob> createState() => _NudgeBobState();
}

class _NudgeBobState extends State<NudgeBob>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: T.nudgeBobDur,
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(NudgeBob oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return Transform.translate(
          offset: Offset(0, -lerpDouble(0, T.nudgeBobDistance, t)!),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
