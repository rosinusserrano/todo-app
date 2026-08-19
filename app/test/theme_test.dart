// The window's two chromes.
//
// Every view but one is a view of a single workspace, and the window says which
// by mixing that workspace's colour into its background. The calendar is the
// exception - it can show every workspace at once, and each block on it is
// drawn in its own calendar's colour - so it gets a neutral instead.
//
// "Neutral" is the whole claim and it is the thing a later tweak can break
// silently: a grey nudged a few points towards blue is still called neutral by
// whoever nudged it, and is a second accent to everybody else.
//
// It is measured as *hue*, not as chroma. The window base is not a pure grey to
// begin with - it is #1C1C22, a blue-violet dark - and lifting it towards a
// lighter grey of the same hue raises chroma slightly while being exactly the
// neutral wanted. What must be true is that the calendar's chrome stays on the
// window's own hue at no more saturation, while a workspace tint pulls it off.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_widget/theme.dart';

void main() {
  HSLColor hsl(Color c) => HSLColor.fromColor(c);

  /// Degrees apart on the wheel, the short way round.
  double hueGap(Color a, Color b) {
    final d = (hsl(a).hue - hsl(b).hue).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  test('the calendar chrome is the window base lifted, not tinted', () {
    expect(hueGap(T.calendarBackground, T.bg), lessThan(1));
    expect(
      hsl(T.calendarBackground).saturation,
      lessThanOrEqualTo(hsl(T.bg).saturation),
    );
    // Lifted: it has to be distinguishable from the base or the calendar would
    // simply look like the window with the tint switched off.
    expect(
      hsl(T.calendarBackground).lightness,
      greaterThan(hsl(T.bg).lightness + 0.03),
    );
    expect(hueGap(T.calendarInk, T.bg), lessThan(1));
  });

  test('a workspace tint pulls the window off that hue, and the calendar '
      'chrome does not', () {
    for (final ws in T.workspaceColors) {
      final tint = T.tintedBackground(ws);
      // The one grey in the palette has no hue to pull with, so it is judged on
      // the same axis it acts on: it desaturates the window instead.
      if (hsl(ws).saturation < 0.2) {
        expect(hsl(tint).saturation, lessThan(hsl(T.bg).saturation));
        continue;
      }
      expect(
        hueGap(tint, T.bg),
        greaterThan(5),
        reason: '${T.toHex(ws)} should be visible in the window',
      );
      expect(
        hueGap(T.calendarBackground, T.bg),
        lessThan(hueGap(tint, T.bg)),
        reason: 'the calendar should be nearer the base than ${T.toHex(ws)}',
      );
    }
  });

  test('the light theme neutral is decided, though nothing reads it yet', () {
    // Defined with its dark twin rather than left to be invented when the light
    // theme lands - see the note on T.calendarInk. Eggshell: barely coloured,
    // and pale enough to be a background rather than a mix into one.
    // Measured as channel spread rather than HSL saturation: at this lightness
    // saturation exaggerates - #F1EBDD reads as 0.42 saturated and is a cream
    // three points off white.
    final c = T.calendarInkLight;
    expect([c.r, c.g, c.b].reduce(math.max) - [c.r, c.g, c.b].reduce(math.min),
        lessThan(0.12));
    expect(T.calendarInkLight.computeLuminance(), greaterThan(0.8));
    expect(T.calendarInk.computeLuminance(), lessThan(0.5));
  });
}
