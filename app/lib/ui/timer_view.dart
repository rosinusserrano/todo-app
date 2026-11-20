// The timer's view: set one, watch it, and be told when it is up (Marco,
// 2026-11-20). The model and the parsing are countdown.dart; the alarm - the
// window coming back and landing here - is the shell's (`_onCountdownUp`).
//
// It owns the content area the way the checklist does: a place of its own on
// the dock's More, global rather than a workspace's, so the window drops the
// workspace tint while it shows.
//
// Three states, drawn from `AppState.countdown`:
//
//   - **None**: one line, "1h for checking mails", read as it is typed
//     (parseCountdown) and echoed under the field, and a row of common
//     lengths that start at once with whatever is typed as the label. One
//     field rather than a duration picker plus a label field, because the
//     sentence is how a timer is said.
//   - **Running** (or paused): what it is for, the time left large enough to
//     read across a room, a bar for how much of it is gone, when it ends.
//   - **Up**: says so, and offers Done (Enter), five more minutes, and the
//     same again.
//
// It ticks itself once a second while it shows, and nothing else does: the
// dock's clock (CountdownBadge) is its own widget with its own ticker, so the
// shell is never rebuilt by a timer.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../countdown.dart';
import '../layout.dart';
import '../theme.dart';
import 'panel_header.dart';

/// The lengths offered under the field.
const kTimerPresets = [
  Duration(minutes: 5),
  Duration(minutes: 15),
  Duration(minutes: 25),
  Duration(minutes: 45),
  Duration(hours: 1),
];

/// "Five more minutes".
const kTimerMore = Duration(minutes: 5);

class TimerView extends StatefulWidget {
  const TimerView({super.key, required this.state, this.now = DateTime.now});

  final AppState state;

  /// Injected so a test can stand at a chosen instant.
  final DateTime Function() now;

  @override
  State<TimerView> createState() => _TimerViewState();
}

class _TimerViewState extends State<TimerView> {
  AppState get s => widget.state;

  final _field = TextEditingController();
  final _fieldFocus = FocusNode(debugLabel: 'timer field');
  final _focus = FocusNode(debugLabel: 'timer view');
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _field.addListener(() => setState(() {}));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && s.countdown != null) setState(() {});
    });
  }

  /// Whether a timer was set at the last build. Focus follows it - the field
  /// when there is none, the view (Space, Enter) when there is - asked for
  /// outright after the frame, as the thought pane does: autofocus gives way
  /// to the shell's key handler, which always has focus. On a change rather
  /// than every build, or a click elsewhere would be pulled back each second.
  bool? _hadTimer;

  void _followFocus() {
    final has = s.countdown != null;
    if (has == _hadTimer) return;
    _hadTimer = has;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (s.countdown == null ? _fieldFocus : _focus).requestFocus();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _field.dispose();
    _fieldFocus.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _start([Duration? preset]) async {
    final parsed = parseCountdown(_field.text);
    final Duration d;
    final String label;
    if (preset != null) {
      // A preset is the length; whatever was typed is what it is for, with
      // any duration in it ignored rather than added.
      d = preset;
      label = parsed?.label ?? _field.text.trim();
    } else if (parsed != null) {
      d = parsed.duration;
      label = parsed.label;
    } else {
      return;
    }
    _field.clear();
    await s.startCountdown(d, label);
  }

  Future<void> _done() => s.clearCountdown();

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final c = s.countdown;
    final now = widget.now();
    _followFocus();

    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent || c == null) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (c.isUp(now) &&
            (key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.numpadEnter)) {
          _done();
          return KeyEventResult.handled;
        }
        if (!c.isUp(now) && key == LogicalKeyboardKey.space) {
          c.paused ? s.resumeCountdown() : s.pauseCountdown();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 0, 0, T.s2),
            child: PanelHeader(title: 'Timer'),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(T.s4, 0, T.s4, T.s4),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (box.maxHeight - T.s4).clamp(0, double.infinity),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: Layout.focusTileMax,
                      ),
                      child: c == null
                          ? _setup(layout)
                          : c.isUp(now)
                          ? _up(c, layout)
                          : _running(c, now, layout),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ setup

  Widget _setup(Layout layout) {
    final parsed = parseCountdown(_field.text);
    final typed = _field.text.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _field,
          focusNode: _fieldFocus,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _start(),
          style: const TextStyle(fontSize: T.fsMenu, color: T.text),
          decoration: InputDecoration(
            hintText: '1h for checking mails',
            hintStyle: const TextStyle(color: T.muted),
            filled: true,
            fillColor: T.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(T.radius),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: T.s3,
              vertical: T.s3,
            ),
          ),
        ),
        const SizedBox(height: T.s2),
        // What Enter will set, so a misread is seen before it starts.
        Text(
          parsed != null
              ? [
                  describeDuration(parsed.duration),
                  if (parsed.label.isNotEmpty) parsed.label,
                ].join(' · ')
              : typed
              ? 'Add a time - "25m", "1h30", "1:15" - or pick one below'
              : 'A time and what it is for',
          style: TextStyle(
            fontSize: T.fsMeta,
            color: parsed != null ? T.accent : T.muted,
          ),
        ),
        const SizedBox(height: T.s4),
        Wrap(
          spacing: T.s2,
          runSpacing: T.s2,
          children: [
            for (final d in kTimerPresets)
              _Button(
                label: describeDuration(d),
                touch: layout.touch,
                onTap: () => _start(d),
              ),
          ],
        ),
        const SizedBox(height: T.s4),
        Align(
          alignment: Alignment.centerRight,
          child: _Button(
            label: 'Start',
            icon: Icons.play_arrow_rounded,
            filled: true,
            touch: layout.touch,
            onTap: parsed == null ? null : _start,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- running

  Widget _running(Countdown c, DateTime now, Layout layout) {
    final ends = c.endsAt;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (c.label.isNotEmpty) ...[
          _Label(c.label),
          const SizedBox(height: T.s2),
        ],
        Text(
          formatClock(c.remaining(now)),
          style: TextStyle(
            fontFamily: T.fontDisplay,
            fontSize: T.fsReadout,
            fontWeight: T.wMedium,
            color: c.paused ? T.muted : T.text,
            fontFeatures: const [FontFeature.tabularFigures()],
            height: 1.1,
          ),
        ),
        const SizedBox(height: T.s3),
        _Bar(value: c.progress(now), color: c.paused ? T.muted : T.accent),
        const SizedBox(height: T.s2),
        Text(
          c.paused ? 'Paused' : 'Ends at ${_hhmm(ends!)}',
          style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
        ),
        const SizedBox(height: T.s5),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: T.s2,
          runSpacing: T.s2,
          children: [
            _Button(
              label: c.paused ? 'Resume' : 'Pause',
              hint: layout.touch ? null : 'Space',
              icon: c.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              filled: true,
              touch: layout.touch,
              onTap: c.paused ? s.resumeCountdown : s.pauseCountdown,
            ),
            _Button(
              label: '+${describeDuration(kTimerMore)}',
              touch: layout.touch,
              onTap: () => s.extendCountdown(kTimerMore),
            ),
            _Button(
              label: 'Stop',
              icon: Icons.stop_rounded,
              color: T.danger,
              touch: layout.touch,
              onTap: _done,
            ),
          ],
        ),
      ],
    );
  }

  // --------------------------------------------------------------------- up

  Widget _up(Countdown c, Layout layout) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.alarm_rounded, size: 32, color: T.warn),
        const SizedBox(height: T.s2),
        const Text(
          "Time's up",
          style: TextStyle(
            fontFamily: T.fontDisplay,
            fontSize: T.fsTitle,
            fontWeight: T.wMedium,
            color: T.warn,
          ),
        ),
        if (c.label.isNotEmpty) ...[
          const SizedBox(height: T.s2),
          _Label(c.label),
        ],
        const SizedBox(height: T.s2),
        Text(
          '${describeDuration(c.total)} · ended ${_hhmm(c.endsAt!)}',
          style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
        ),
        const SizedBox(height: T.s5),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: T.s2,
          runSpacing: T.s2,
          children: [
            _Button(
              label: 'Done',
              hint: layout.touch ? null : 'Enter',
              icon: Icons.check_rounded,
              filled: true,
              touch: layout.touch,
              onTap: _done,
            ),
            _Button(
              label: '+${describeDuration(kTimerMore)}',
              touch: layout.touch,
              onTap: () => s.extendCountdown(kTimerMore),
            ),
            _Button(
              label: 'Again',
              icon: Icons.replay_rounded,
              touch: layout.touch,
              onTap: s.restartCountdown,
            ),
          ],
        ),
      ],
    );
  }

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: T.fsMenu, color: T.text, height: 1.3),
  );
}

/// How much of it is gone: a flat rule, filled from the left.
class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: SizedBox(
      height: 4,
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: T.surface)),
          FractionallySizedBox(
            widthFactor: value,
            heightFactor: 1,
            child: ColoredBox(color: color),
          ),
        ],
      ),
    ),
  );
}

/// The parked review's button shape: a flat block, a hint for the key.
class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.touch,
    required this.onTap,
    this.icon,
    this.hint,
    this.color = T.accent,
    this.filled = false,
  });

  final String label;
  final IconData? icon;
  final String? hint;
  final Color color;
  final bool touch;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.radius),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: T.s3,
            vertical: touch ? T.s3 : T.s2,
          ),
          decoration: BoxDecoration(
            color: filled ? color.withValues(alpha: 0.16) : T.surface,
            borderRadius: BorderRadius.circular(T.radius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: touch ? 17 : 14, color: color),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: T.fsLabel,
                  color: T.text,
                  fontWeight: T.wMedium,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(width: 6),
                Text(
                  hint!,
                  style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The dock's little clock beside More while a timer runs and its view is
/// not on screen: time left, or that it is up. Ticks itself, so the dock
/// is not rebuilt every second.
class CountdownBadge extends StatefulWidget {
  const CountdownBadge({super.key, required this.countdown, required this.ink});

  final Countdown countdown;
  final Color ink;

  @override
  State<CountdownBadge> createState() => _CountdownBadgeState();
}

class _CountdownBadgeState extends State<CountdownBadge> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.countdown;
    final now = DateTime.now();
    final up = c.isUp(now);
    final color = up ? T.warn : widget.ink.withValues(alpha: 0.85);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          up
              ? Icons.alarm_rounded
              : c.paused
              ? Icons.pause_circle_outline_rounded
              : Icons.timer_outlined,
          size: 12,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          up ? 'up' : formatShort(c.remaining(now)),
          style: TextStyle(
            fontSize: T.fsMeta,
            fontFamily: T.fontDisplay,
            fontWeight: T.wMedium,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
