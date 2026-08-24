// The whole side-thought control on a phone: a bubble floating over the list.
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
// It is **one door, not a second one**: wherever this is drawn the footer draws
// nothing at all (see `ThoughtFooter.showCaptureButton` / `showPressure`). It
// therefore has to carry the whole of what that bar was saying, which is three
// things and not one:
//
//   write one     tapping it opens the capture pane.
//   how many      the count rides on the bubble, and the bubble takes the
//                 alarm colour and starts to pulse as the pile grows - the
//                 same escalation the bar ran, on the same numbers
//                 (ThoughtPulse), because it is the same signal.
//   read them     a swipe **up** opens the pile. A phone has one obvious
//                 gesture for "there is more above this", and spending a
//                 second tap target on it - or a long press, which is
//                 invisible - would put the pile behind something you have to
//                 be told about.
//
// The bubble lifts with the finger while the swipe is in progress and drops
// back if it was not enough, which is the only way the gesture announces
// itself: nothing else on the phone moves when you push it.

import 'package:flutter/material.dart';

import '../theme.dart';
import 'thought_pressure.dart';

class ThoughtBubble extends StatefulWidget {
  const ThoughtBubble({
    super.key,
    required this.accent,
    required this.count,
    required this.listOpen,
    required this.onTap,
    required this.onToggleList,
  });

  /// The workspace colour, so it belongs to the window it floats over rather
  /// than arriving as a stock Material FAB in somebody else's blue. It is also
  /// what the alarm colour is derived from, so the two can never clash.
  final Color accent;

  /// How many thoughts are waiting. Drives the badge, the tint and the pulse.
  final int count;

  /// Whether the pile currently owns the content area, so a swipe up reads as
  /// the toggle it is and the badge can show itself as pressed.
  final bool listOpen;

  final VoidCallback onTap;
  final VoidCallback onToggleList;

  /// Bigger than `Layout.touchTargetSide` (40): it is lifted off the content with
  /// nothing beside it to be crowded by, and it is the control most often
  /// pressed without looking.
  static const side = 48.0;

  /// What the shell keeps clear of it on the right and below.
  static const margin = 12.0;

  /// How far it can be pushed up, and how far is far enough to mean it.
  static const _lift = 56.0;
  static const _commit = 24.0;

  @override
  State<ThoughtBubble> createState() => _ThoughtBubbleState();
}

class _ThoughtBubbleState extends State<ThoughtBubble>
    with SingleTickerProviderStateMixin {
  late final ThoughtPulse _pulse = ThoughtPulse(this);

  /// How far the finger has pushed the bubble up, in points.
  double _lifted = 0;

  @override
  void initState() {
    super.initState();
    _pulse.sync(widget.count);
  }

  @override
  void didUpdateWidget(ThoughtBubble old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count) _pulse.sync(widget.count);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _dragUpdate(DragUpdateDetails d) {
    setState(() {
      _lifted = (_lifted - d.delta.dy).clamp(0.0, ThoughtBubble._lift);
    });
  }

  void _dragEnd(DragEndDetails d) {
    final flung = (d.primaryVelocity ?? 0) < -400;
    final far = _lifted >= ThoughtBubble._commit;
    setState(() => _lifted = 0);
    // Nothing to review is not a reason to refuse the gesture: the panel says
    // the pile is empty, which is a better answer than a control that ignores
    // being pushed.
    if (flung || far) widget.onToggleList();
  }

  @override
  Widget build(BuildContext context) {
    final alarm = T.complementary(widget.accent);
    final hot = ThoughtPulse.intensityOf(widget.count);

    // The Semantics is the outermost thing this builds, not a layer somewhere
    // in the middle: a screen reader asking what this control is should not
    // have to go looking past an AnimatedBuilder for the answer.
    return Semantics(
      label: widget.count == 0
          ? 'Capture a side thought'
          : 'Capture a side thought, ${widget.count} waiting. '
              'Swipe up to review them.',
      button: true,
      child: AnimatedBuilder(
        animation: _pulse.controller,
        builder: (context, child) {
          final glow = Curves.easeInOut.transform(_pulse.controller.value);
          return Transform.translate(
            offset: Offset(0, -_lifted),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  if (ThoughtPulse.pulsingAt(widget.count))
                    BoxShadow(
                      color: alarm.withValues(alpha: glow * hot * 0.9),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                ],
              ),
              child: child,
            ),
          );
        },
        child: GestureDetector(
          // Vertical only: the content underneath is a scrolling list and a
          // pan recogniser here would eat flicks that started on the circle.
          onVerticalDragUpdate: _dragUpdate,
          onVerticalDragEnd: _dragEnd,
          onVerticalDragCancel: () => setState(() => _lifted = 0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [_circle(alarm, hot), if (widget.count > 0) _badge(alarm)],
          ),
        ),
      ),
    );
  }

  Widget _circle(Color alarm, double hot) {
    return Material(
      // Opaque rather than tinted-translucent: it sits over a scrolling list
      // and text running underneath a semi-transparent circle is unreadable
      // for the half second it takes to pass behind it.
      //
      // The fill walks from the workspace colour towards the alarm as the pile
      // grows, which is the quiet half of the escalation - it is saying
      // something long before it starts to pulse.
      color: Color.lerp(
        Color.lerp(T.bgSolid, widget.accent, 0.34),
        alarm,
        hot * 0.55,
      ),
      shape: const CircleBorder(),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.5),
      child: InkWell(
        onTap: widget.onTap,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: ThoughtBubble.side,
          height: ThoughtBubble.side,
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
    );
  }

  /// The count, sitting on the shoulder of the circle.
  ///
  /// Not a second button - the swipe is what opens the pile, and a 16px target
  /// overlapping a 48px one is a way of pressing the wrong thing. It is only
  /// ever read.
  Widget _badge(Color alarm) {
    return Positioned(
      right: -2,
      top: -2,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: widget.listOpen ? T.bgSolid : alarm,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: T.bgSolid, width: 1.5),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              '${widget.count}',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: widget.listOpen ? alarm : T.bgSolid,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
