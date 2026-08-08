// Picking an exact date and time to be reminded.
//
// The presets in reminder_menu.dart answer "not now, but don't let me forget"
// and are still the right answer most of the time. This is the other case: the
// thing that has to happen on the 14th at 09:30, which no horizon-from-now can
// express.
//
// This used to be impossible on the grounds that Material's date picker wants
// roughly the whole 340px window on its own. The calendar killed that
// objection: [MonthGrid] is a month that already fits, and the year view draws
// one to three of them side by side in this same window. So the picker is a
// grid we already own rather than a reason to grow the widget.
//
// A dialog, not a sheet. The rule in main.dart is about things that stay on
// screen while you work around them - a sheet leaves the title bar reachable so
// the window can still be dragged and closed. This is modal by nature and gone
// in seconds, like the composer and the event editor, and it also has to open
// from *inside* the composer, which is itself a dialog: a sheet in the shell's
// Stack would be drawn behind that dialog's barrier.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'month_grid.dart';

/// Returns the chosen instant, or null if it was dismissed.
///
/// [initial] seeds the grid and the clock - an armed reminder opens on its own
/// day rather than on today, so nudging one by an hour does not mean finding it
/// again first.
Future<DateTime?> showReminderPicker(
  BuildContext context, {
  DateTime? initial,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (context) => _PickerDialog(initial: initial),
  );
}

class _PickerDialog extends StatefulWidget {
  const _PickerDialog({required this.initial});

  final DateTime? initial;

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  late DateTime _day;
  late int _hour;
  late int _minute;

  /// Fixed for the life of the dialog, so "today" cannot move under the
  /// selection while it is open.
  final _now = DateTime.now();

  /// The month on screen, which is not the same thing as the selected day: you
  /// page forward looking for a date and have not chosen one yet.
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    // Defaults to the next round hour rather than to this instant - a reminder
    // at 14:37 is nobody's intention, and it saves the common case a trip to
    // the minute field.
    final seed = widget.initial ?? _nextHour(_now);
    _day = DateTime(seed.year, seed.month, seed.day);
    _hour = seed.hour;
    _minute = seed.minute;
    _month = DateTime(seed.year, seed.month);
  }

  static DateTime _nextHour(DateTime from) => DateTime(
    from.year,
    from.month,
    from.day,
    from.hour,
  ).add(const Duration(hours: 1));

  DateTime get _chosen =>
      DateTime(_day.year, _day.month, _day.day, _hour, _minute);

  /// A reminder in the past fires the moment it is saved, which reads as a bug
  /// rather than as a choice, so Save is refused for one.
  bool get _isPast => !_chosen.isAfter(_now);

  void _stepMonth(int by) =>
      setState(() => _month = DateTime(_month.year, _month.month + by));

  void _save() {
    if (_isPast) return;
    Navigator.pop(context, _chosen);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
      },
      child: AlertDialog(
        backgroundColor: T.bgSolid,
        title: const Text('Remind me', style: TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 300,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MonthHeader(
                  label: '${kMonthNames[_month.month - 1]} ${_month.year}',
                  onPrev: () => _stepMonth(-1),
                  onNext: () => _stepMonth(1),
                ),
                const SizedBox(height: 6),
                MonthGrid(
                  year: _month.year,
                  month: _month.month,
                  weekdayFontSize: 10,
                  childAspectRatio: 1.05,
                  dayBuilder: (day) => _PickCell(
                    day: day,
                    selected: isSameDay(day, _day),
                    isToday: isSameDay(day, _now),
                    onTap: () => setState(() => _day = day),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Time',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: T.muted,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 6),
                _TimeField(
                  hour: _hour,
                  minute: _minute,
                  onChanged: (h, m) => setState(() {
                    _hour = h;
                    _minute = m;
                  }),
                ),
                const SizedBox(height: 10),
                // The times a reminder is actually set for, one tap each. The
                // field above is still there for 09:47.
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in const [
                      [9, 0],
                      [12, 0],
                      [14, 0],
                      [18, 0],
                      [21, 0],
                    ])
                      ActionChip(
                        label: Text(
                          _hhmm(t[0], t[1]),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        onPressed: () => setState(() {
                          _hour = t[0];
                          _minute = t[1];
                        }),
                      ),
                  ],
                ),
                if (_isPast) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'That is in the past — it would fire straight away.',
                    style: TextStyle(fontSize: 11, color: T.danger),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(fontSize: 12.5)),
          ),
          FilledButton(
            onPressed: _isPast ? null : _save,
            child: const Text('Set', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

String _hhmm(int h, int m) =>
    '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: T.text,
            ),
          ),
        ),
        _Step(icon: Icons.chevron_left_rounded, onTap: onPrev),
        const SizedBox(width: 2),
        _Step(icon: Icons.chevron_right_rounded, onTap: onNext),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 18, color: T.muted),
      ),
    );
  }
}

class _PickCell extends StatelessWidget {
  const _PickCell({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Today is a ring, the selection is a fill: the two have to be legible at
    // once, because the day you are picking is very often today.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Center(
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? T.accent : null,
            shape: BoxShape.circle,
            border: isToday && !selected
                ? Border.all(color: T.accent, width: 1)
                : null,
          ),
          child: Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 12,
              color: selected ? T.bgSolid : T.text,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// Two-digit hour and minute, side by side.
///
/// Typed rather than dialled: a Material time picker is another full-width
/// dialog, and the whole point of this file is that this window does not have
/// the room to stack one modal on another.
class _TimeField extends StatefulWidget {
  const _TimeField({
    required this.hour,
    required this.minute,
    required this.onChanged,
  });

  final int hour;
  final int minute;
  final void Function(int hour, int minute) onChanged;

  @override
  State<_TimeField> createState() => _TimeFieldState();
}

class _TimeFieldState extends State<_TimeField> {
  late final _h = TextEditingController(text: _two(widget.hour));
  late final _m = TextEditingController(text: _two(widget.minute));

  static String _two(int v) => v.toString().padLeft(2, '0');

  @override
  void didUpdateWidget(_TimeField old) {
    super.didUpdateWidget(old);
    // The chips write through this widget, so the fields have to follow them -
    // but only when the value actually differs, or every keystroke would fight
    // the caret.
    if (widget.hour != int.tryParse(_h.text)) _h.text = _two(widget.hour);
    if (widget.minute != int.tryParse(_m.text)) _m.text = _two(widget.minute);
  }

  @override
  void dispose() {
    _h.dispose();
    _m.dispose();
    super.dispose();
  }

  /// Clamps rather than rejects. A half-typed "7" in the minute box is a
  /// perfectly good 07, and refusing it mid-keystroke makes the field feel
  /// broken; only the out-of-range cases are pulled back.
  void _emit() {
    final h = (int.tryParse(_h.text) ?? widget.hour).clamp(0, 23);
    final m = (int.tryParse(_m.text) ?? widget.minute).clamp(0, 59);
    widget.onChanged(h, m);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _box(_h, 'HH'),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text(':', style: TextStyle(fontSize: 15, color: T.muted)),
        ),
        _box(_m, 'MM'),
      ],
    );
  }

  Widget _box(TextEditingController c, String hint) => SizedBox(
    width: 46,
    child: TextField(
      controller: c,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: 2,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => _emit(),
    ),
  );
}
