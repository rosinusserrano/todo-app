// The way into the capture pane on a phone: a bubble floating over the list.
//
// On a desktop the way in is the 💭 on the left of the footer, and that is
// right there - the pointer reaches a 26px target in the corner of a 340px
// window as easily as anything else on screen.
//
// A thumb does not, and the footer is the worst row on the phone to put it in:
// it is the strip *below* the view bar, so the one control used in a hurry -
// somebody is talking, you have four seconds - is the furthest thing from the
// hand and the smallest thing on screen. This is the shape every chat widget on
// the web settled on for the same reason: a circle, lifted off the content,
// sitting just above the bottom bar where the thumb already rests.
//
// It is **one door, not a second one**: the footer drops its own 💭 wherever
// this is on screen (see `ThoughtFooter.showCaptureButton`). Two controls for
// one field is how you end up with a phone build whose capture button is in a
// different place depending on which view you are in.
//
// The count stays on the footer. This says *write one*; the badge below says
// how many are waiting, and it is also the way into the panel that shows them -
// a bubble that carried the number would be saying the pile's job as well as
// its own, from a control that does not open it.

import 'package:flutter/material.dart';

import '../theme.dart';

class ThoughtBubble extends StatelessWidget {
  const ThoughtBubble({super.key, required this.accent, required this.onTap});

  /// The workspace colour, so it belongs to the window it floats over rather
  /// than arriving as a stock Material FAB in somebody else's blue.
  final Color accent;

  final VoidCallback onTap;

  /// Bigger than `Layout.touchTargetSide` (40): it is lifted off the content with
  /// nothing beside it to be crowded by, and it is the control most often
  /// pressed without looking.
  static const side = 48.0;

  /// What the shell keeps clear of it on the right and below.
  static const margin = 12.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Capture a side thought',
      button: true,
      child: Material(
        // Opaque rather than tinted-translucent: it sits over a scrolling list
        // and text running underneath a semi-transparent circle is unreadable
        // for the half second it takes to pass behind it.
        color: Color.lerp(T.bgSolid, accent, 0.34),
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: const SizedBox(
            width: side,
            height: side,
            // The glyph is excluded from semantics: the label above already
            // says what this is, and a screen reader announcing "thought
            // balloon" after it is reading the picture out twice.
            child: Center(
              child: ExcludeSemantics(
                child: Text('💭', style: TextStyle(fontSize: 20)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
