// How loud the pile of side thoughts is allowed to get.
//
// One pile, one escalation, drawn wherever the current layout put the control:
// the footer's bar under a pointer, [ThoughtBubble] under a thumb. Both read
// the numbers from here rather than each keeping their own, because two copies
// of "when does this start pulsing" drift apart one literal at a time and the
// symptom - a phone that nags at a different pile size than a desktop - is not
// something anybody would think to look for.
//
//   1  thought   the control starts tinting at all
//   4            it begins to pulse
//   12           full intensity, fastest pulse
//
// These were roughly twice as slack before the workspace-switch block was
// removed. Nothing stops you working with thoughts pending any more, so the
// control is the only thing saying anything and it has to say it sooner.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The escalation, and the repeating pulse it drives.
///
/// Owns its [AnimationController]: the two things it decides - whether to run
/// at all, and how fast - are the same decision, and splitting them left both
/// call sites re-deriving the second one from the count.
class ThoughtPulse {
  ThoughtPulse(TickerProvider vsync)
      : controller = AnimationController(vsync: vsync, duration: _slowest);

  final AnimationController controller;

  /// Where the escalation tops out, and where it starts to move.
  static const peak = 12;
  static const pulseFrom = 4;

  static const _slowest = Duration(milliseconds: 1800);
  static const _fastest = Duration(milliseconds: 500);

  /// 0 at empty, 1 at [peak] pending thoughts.
  static double intensityOf(int count) => math.min(count / peak, 1);

  static bool pulsingAt(int count) => count >= pulseFrom;

  /// Start, speed up or stop, for a pile of [count] thoughts.
  void sync(int count) {
    if (!pulsingAt(count)) {
      if (controller.isAnimating) {
        controller.stop();
        controller.value = 0;
      }
      return;
    }

    final span = (peak - pulseFrom).toDouble();
    final t = math.min((count - pulseFrom) / span, 1);
    final next = Duration(
      milliseconds: (_slowest.inMilliseconds -
              (_slowest.inMilliseconds - _fastest.inMilliseconds) * t)
          .round(),
    );
    if (controller.duration != next) {
      controller.duration = next;
      if (controller.isAnimating) controller.repeat(reverse: true);
    }
    if (!controller.isAnimating) controller.repeat(reverse: true);
  }

  void dispose() => controller.dispose();
}
