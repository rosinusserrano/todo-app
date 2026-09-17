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
  static const bg = Color(0xDB18181D); // rgba(24,24,29,0.86)
  static const bgSolid = Color(0xFF18181D);
  static const surface = Color(0x0DFFFFFF); // rgba(255,255,255,0.05)
  static const surfaceHover = Color(0x17FFFFFF); // rgba(255,255,255,0.09)
  static const text = Color(0xFFEDEDF0);
  static const muted = Color(0xFF90909A);
  static const accent = Color(0xFF6F86CC);

  /// Destructive, and **only** destructive - delete, revoke, a failed sync.
  ///
  /// It used to be all three of destructive, overdue and flagged, which is
  /// most of why the widget read as loud: the same full-strength red said
  /// "this will be gone for ever" and "this was due at nine". Those are not
  /// the same sentence and now do not share a colour. See [warn] and
  /// [flagged].
  static const danger = Color(0xFFCC7A7A);

  /// Attention, not alarm: a reminder that has come due, a sync that failed
  /// and will retry. Warm rather than red because nothing here is lost - the
  /// task is fine, the clock has simply passed it, and the sync will come
  /// round again in a minute.
  ///
  /// One token rather than one per caller, and this is the split that was
  /// missing: [danger] is for the thing you cannot undo.
  static const warn = Color(0xFFCC9A6A);

  /// Something worked - a sync test that reached the server, a setting that
  /// took. The mint from [workspaceColors], named, because it was written out
  /// as a raw `0xFF7EE3A1` in the settings sheet and stayed the *old*,
  /// brighter mint through two palette changes.
  static const ok = Color(0xFF83C0A0);

  /// The flagged task's bar down its leading edge. A muted red: it has to be
  /// legible as urgency at 3px wide against the row's own fill, and it is the
  /// one of the three states that is drawn as a solid shape rather than a
  /// tint, so it can afford less saturation than the tint would need.
  static const flagged = Color(0xFFCC7A7A);

  /// **The** corner radius. One number, everywhere - the window, the sheets,
  /// the rows, the fields, the pills.
  ///
  /// There were six (14, 9, 8, 7, 6, 20) with no rule for which belonged
  /// where, which is the kind of thing nobody can name and everybody reads as
  /// unconsidered. Anything that genuinely wants a different shape wants a
  /// *shape* - a circle for the tick box, a stadium for a chip - and says so
  /// with `BoxShape` or a pill radius rather than by picking a fourth number.
  static const radius = 8.0;

  // ---- The spacing scale ----
  //
  // Every padding, margin and gap in the widget is one of these five numbers.
  // They were picked per widget before (6/7 on a row, 9/5/7/5 on a workspace
  // pill, 8/4 in the title bar, 4/5/5 in a menu), which is why nothing lined
  // up with anything: a 1px difference between two paddings is invisible on
  // its own and, repeated down a column, is exactly what makes a layout feel
  // approximate.
  //
  // Four rather than eight steps, because this is a 340px window - the two
  // large ones exist for the gap *between* regions, not inside them.

  /// Between two things that belong to each other - an icon and its label.
  static const s1 = 4.0;

  /// The default gap inside a row or a control.
  static const s2 = 8.0;

  /// The window gutter, and the padding inside a row.
  static const s3 = 12.0;

  /// Between two regions that are not the same thing.
  static const s4 = 16.0;

  /// Standoff at the top or bottom of a panel.
  static const s5 = 24.0;

  // ---- The type scale ----
  //
  // Four sizes and two weights. There were six sizes between 10.5 and 15,
  // which is too close together to make a hierarchy and too many to be one -
  // 13 and 13.5 sat next to each other in the same window and only one of
  // them could have been deliberate.
  //
  // Weight 600 is gone entirely. What it was doing - saying "this is the
  // label of the thing you are in" - is done by [wMedium] plus the colour it
  // already had, and a 600 at 12px in Segoe UI Variable Text is a smear
  // rather than an emphasis.

  /// The title bar, a task's title, the add field. What you read.
  static const fsBody = 13.0;

  /// The workspace bar and the view bar. What you navigate by.
  static const fsLabel = 12.0;

  /// Notes previews, counts, times, marks. What you glance at.
  ///
  /// Half a point *up* from the 10.5 it replaces: below 11 the fallback faces
  /// on Android stop hinting cleanly, and this is the size the notes preview
  /// under a task title is set in.
  static const fsMeta = 11.0;

  /// Menu and picker items, which are targets before they are text.
  static const fsMenu = 15.0;

  /// Text laid *into* the calendar grid: the hour gutter, a weekday initial, a
  /// day number in a month tile, the label inside a block.
  ///
  /// The one place the scale above cannot reach, and it is geometry that
  /// stops it: every box here is sized by something other than its contents -
  /// a block's height is its *duration*, a day column's width is a seventh of
  /// what is left after the gutter - so the text has to fit what the clock and
  /// the calendar chose. A 15-minute block at the default hour height is 14
  /// pixels tall; [fsMeta] in it is an overflow, which is exactly how this
  /// token came to exist.
  static const fsGrid = 9.5;

  static const wNormal = FontWeight.w400;
  static const wMedium = FontWeight.w500;

  /// **Content** emphasis, never chrome: Markdown's `**bold**` and the
  /// headings inside a note. The rule above is about the widget's own labels
  /// - a heavier weight there was decoration - but a note that says something
  /// is bold has to look bold, and w500 against w400 is not that.
  static const wStrong = FontWeight.w600;

  /// The **most** the whole widget is enlarged by on a phone. Every size in
  /// this app was picked for a 340x480 desktop window; on a phone that layout
  /// is still the right layout, it is just small, and its hit targets are
  /// smaller than a fingertip. See [UiScale] for why this is one number rather
  /// than a second set of paddings and font sizes.
  ///
  /// A *maximum* rather than a fixed factor: zooming by a flat 1.28 on a 375pt
  /// iPhone leaves the layout only 293 points to lay out in, which is narrower
  /// than the window it was designed for, so the controls at the ends of the
  /// bars get squeezed. [UiScale] takes the largest zoom that still leaves
  /// [designWidth] to work with.
  static const mobileScale = 1.28;

  /// The width every size in this app was chosen against - the desktop window.
  static const designWidth = 340.0;

  /// --hero-dur / --hero-ease. Previously duplicated between CSS and
  /// HERO_MS in main.ts.
  static const heroDur = Duration(milliseconds: 380);
  static const heroEase = Cubic(0.2, 0.9, 0.25, 1);

  /// The slide-out on a checked-off task. Was the 320ms timeout in main.ts,
  /// which had to match the `slide-out` keyframe by hand.
  static const slideOutDur = Duration(milliseconds: 320);

  /// How a panel that covers the content area arrives and leaves - Settings,
  /// the sound sheet, the task composer.
  ///
  /// One pair for all of them, because they are the same gesture: something
  /// slides over what you were doing and slides back off it. Two of them
  /// animating at different speeds is the kind of difference nobody can name
  /// and everybody notices.
  ///
  /// Shorter than [heroDur]: the focus flight is a thing *moving*, and the eye
  /// wants to follow it. A sheet is a thing *appearing*, and waiting for it is
  /// waiting.
  static const sheetDur = Duration(milliseconds: 220);

  /// Decelerating, so the panel arrives rather than stops. Same family as
  /// [heroEase] with less overshoot in the tail - a sheet has an edge that
  /// lines up with the window, and an eased-past-and-back edge reads as slop.
  static const sheetEase = Cubic(0.2, 0.85, 0.3, 1);

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

  /// The eight, at roughly 60% of the chroma they carried.
  ///
  /// The hues are unchanged and in the same order, which is the whole point:
  /// a workspace keeps the colour its owner already knows it by, stored as an
  /// index into this list, so nothing migrates and nobody has to re-learn
  /// which one is which. What changes is that the window stops glowing - see
  /// [tintedBackground], which now mixes 6% rather than 16%.
  ///
  /// Lightness is deliberately *not* equalised. These are labels, not a
  /// sequential scale, and an amber and a violet at the same L are harder to
  /// tell apart in the corner of your eye than the pair that keeps its
  /// natural difference.
  static const workspaceColors = [
    Color(0xFF6F86CC), // blue
    Color(0xFF83C0A0), // mint
    Color(0xFFD6BE86), // amber
    Color(0xFFD08585), // red
    Color(0xFFD096C4), // pink
    Color(0xFFA691D6), // violet
    Color(0xFF7FB4CC), // cyan
    Color(0xFFC6C6CA), // neutral
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

  /// The window base tinted with a slice of the active workspace colour.
  ///
  /// **6%, down from 16%.** At 16 the tint was the loudest thing in the
  /// window and it was saying the least: the workspace's name is on the bar,
  /// in its own colour, an inch from the tint that was repeating it. Six is
  /// enough that switching workspaces is visibly a change of room and not
  /// enough to sit under a task list all day. The same reasoning the calendar
  /// chrome already used - see [calendarBackground], which mixes 12% because
  /// grey has no hue to carry the signal.
  static Color tintedBackground(Color ws) => Color.lerp(bg, ws, 0.06)!;

  static Color tintedBorder(Color ws) =>
      Color.lerp(const Color(0x14FFFFFF), ws, 0.30)!;

  /// The calendar's own chrome, in place of the workspace tint.
  ///
  /// Every other view is a view of one workspace, and tinting the window with
  /// that workspace's colour is telling you which one you are in. The calendar
  /// is not: it can show every workspace at once, and each block on it is
  /// already drawn in *its own* calendar's colour - which is the whole point of
  /// the week view, and which a window mixed 16% into one of those colours was
  /// quietly working against. So while it owns the window the tint drops out
  /// and this neutral takes its place.
  ///
  /// Two neutrals, decided together though only one is reachable: [calendarInk]
  /// is what mixes in today, [calendarInkLight] is the eggshell the light theme
  /// will take when it exists (still in FEATURES.md's backlog). Pairing them
  /// here rather than leaving the second to be invented later is the point -
  /// "neutral" means something different against a dark window than a pale one,
  /// and deciding it twice is how the two end up unrelated.
  static const calendarInk = Color(0xFF8A8A96);
  static const calendarInkLight = Color(0xFFF1EBDD);

  /// The same two mixes [tintedBackground] and [tintedBorder] make, with the
  /// neutral in place of the workspace colour. Lighter mixes than those, since
  /// grey has no hue to carry the signal and reads as dirt if it is laid on as
  /// thickly as a colour.
  static final calendarBackground = Color.lerp(bg, calendarInk, 0.12)!;

  static final calendarBorder =
      Color.lerp(const Color(0x14FFFFFF), calendarInk, 0.22)!;

  /// The side-thought pile's colour, wherever it is drawn - the bubble, the
  /// capture pane, the footer's meter and the list.
  ///
  /// Side thoughts are global: one pile, every workspace, no `workspace_uuid`.
  /// They used to be drawn in the current workspace's colour anyway, which
  /// told you something untrue - that this pile belonged to this list, and
  /// that switching would show a different one. The app's own accent belongs
  /// to no workspace, which is exactly the claim to make. The alarm the pile
  /// escalates towards is derived from this, so it no longer changes hue as
  /// you move between workspaces either.
  static const thoughts = accent;

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

/// A global zoom applied to the entire widget.
///
/// The desktop and mobile builds share one set of size tokens. Rather than fork
/// every padding, font size and icon per platform - which would drift the two
/// builds apart one literal at a time - the tree is laid out at 1/[scale] of
/// the real viewport and drawn back up as a whole. Proportions stay identical
/// to the desktop widget by construction, and there is a single number to tune.
///
/// The MediaQuery has to be shrunk alongside the transform, or the subtree
/// lays out for a viewport larger than the one it ends up occupying: the
/// bottom of the list would fall off the screen, and safe-area insets would be
/// over-applied by exactly [scale].
class UiScale extends StatelessWidget {
  const UiScale({super.key, required this.scale, required this.child});

  /// The **maximum** zoom. The zoom actually applied is whatever leaves at
  /// least [T.designWidth] to lay out in - see [effectiveScale].
  final double scale;

  final Widget child;

  /// The largest zoom no greater than [max] that still leaves the layout its
  /// design width.
  ///
  /// Never below 1: shrinking the widget to fit a very narrow screen would
  /// make the text smaller than the desktop build, which is the opposite of
  /// what this is for.
  @visibleForTesting
  static double effectiveScale(double width, double max) {
    if (max <= 1.0 || width <= 0) return 1.0;
    return (width / T.designWidth).clamp(1.0, max);
  }

  @override
  Widget build(BuildContext context) {
    if (scale <= 1.0) return child;

    final mq = MediaQuery.of(context);
    final applied = effectiveScale(mq.size.width, scale);
    if (applied == 1.0) return child;
    final size = mq.size / applied;

    return MediaQuery(
      data: mq.copyWith(
        size: size,
        padding: mq.padding / applied,
        viewPadding: mq.viewPadding / applied,
        viewInsets: mq.viewInsets / applied,
      ),
      child: Transform.scale(
        scale: applied,
        alignment: Alignment.topLeft,
        // OverflowBox, not SizedBox. The incoming constraints from MaterialApp
        // are *tight* at the full viewport, and a SizedBox cannot defy a tight
        // constraint - it was silently ignored, the subtree laid out at the
        // full screen width, and Transform then magnified that by [scale], so
        // ~22% of the width and height fell off the screen with no overflow
        // warning (a Transform does not report one). OverflowBox is the widget
        // that actually hands a child different constraints than it was given.
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: size.width,
          maxWidth: size.width,
          minHeight: size.height,
          maxHeight: size.height,
          child: child,
        ),
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
