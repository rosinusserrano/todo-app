// How a task repeats, in one panel.
//
// The composer's chip row covers the four repeats anybody sets in a hurry -
// day, week, month, year. This is the rest of it, and it exists because two
// perfectly ordinary requests could not be said at all:
//
//   - **"The last day of every month."** Not expressible as a due date plus a
//     period: "monthly" means the same day-of-month as the reminder, and from
//     the 31st that clamps to 28 February and then walks on from *there*, so
//     one short month quietly rewrites the rule for ever.
//   - **"Every two weeks after I last did it."** The interval that matters for
//     a chore is between doings, not between due dates. Cleaning the kitchen on
//     the 8th when it was due on the 1st means the next one is the 22nd; a
//     schedule says the 15th and hands you a backlog for being late.
//
// So the panel is two questions, and the second one changes with the answer to
// the first:
//
//   **What it is measured from** - the schedule, or the last completion.
//   **When the next one appears** - which only a scheduled repeat gets to
//   answer, because a completion-anchored one cannot appear before the
//   completion it is counted from.
//
// That second question is the one that decides whether a repeat can pile up.
// "When the last one is done" is the old behaviour and is incapable of it -
// there is at most one open occurrence, because making the next needs finishing
// this one. "When it is due", and the lead times, are the rule-based half: the
// monthly report appears on the last day of the month whether or not last
// month's was ever sent, and an unanswered month is a row that stays on the
// list saying so. Both are wanted, and which one you want is not something the
// app can guess - so it is asked, in those words.

import 'package:flutter/material.dart';

import '../layout.dart';
import '../sync/models.dart';
import '../task_variables.dart';
import '../theme.dart';
import 'form_sheet.dart';

/// Everything a repeat is, as the composer holds it.
class RepeatSpec {
  const RepeatSpec({this.recur, this.from = RecurFrom.schedule, this.lead});

  /// Null is "once".
  final String? recur;
  final String from;

  /// Minutes before the due time at which the next occurrence is created, or
  /// null for "as soon as the last one is ticked". See [Task.recurLead].
  final int? lead;

  static const once = RepeatSpec();

  bool get repeats => recur != null;

  /// One line for the chip that stands for this in the composer.
  String get label {
    final rule = recur;
    if (rule == null) return 'Once';
    final base = Recur.label(rule);
    if (from == RecurFrom.completion) return '$base, after it is done';
    return base;
  }

  /// The second line, under the panel's controls: what will actually happen,
  /// spelled out. A setting whose consequence has to be worked out from two
  /// other settings is a setting people get wrong.
  String get explanation {
    if (recur == null) return 'This task happens once.';

    if (from == RecurFrom.completion) {
      return 'The next one is created ${_intervalWords()} after you tick this '
          'one off - so being late moves the whole series, instead of leaving '
          'you behind it.';
    }
    if (lead == null) {
      return 'The next one is created as soon as this one is ticked off. There '
          'is never more than one waiting.';
    }
    if (lead == 0) {
      return 'The next one is created when it falls due, ticked or not - so a '
          'missed one stays on the list beside the new one.';
    }
    return 'The next one is created ${_leadWords(lead!)} before it is due, '
        'ticked or not, with the due date still the rule’s.';
  }

  String _intervalWords() {
    final rule = recur;
    if (rule == null) return '';
    // "Every 2 weeks" -> "2 weeks"; the plain rules read fine as they are.
    final label = Recur.label(rule).toLowerCase();
    return label.startsWith('every ') ? label.substring(6) : label;
  }

  static String _leadWords(int minutes) {
    if (minutes % (24 * 60) == 0) {
      final days = minutes ~/ (24 * 60);
      if (days % 7 == 0) {
        final weeks = days ~/ 7;
        return weeks == 1 ? 'a week' : '$weeks weeks';
      }
      return days == 1 ? 'a day' : '$days days';
    }
    final hours = minutes ~/ 60;
    return hours == 1 ? 'an hour' : '$hours hours';
  }
}

/// The lead times offered. Minutes, because that is the column's unit; the
/// labels are the only thing anybody reads.
const _leadOptions = <int?, String>{
  null: 'When the last one is done',
  0: 'When it is due',
  24 * 60: 'A day before',
  3 * 24 * 60: 'Three days before',
  7 * 24 * 60: 'A week before',
};

Future<RepeatSpec?> showRepeatEditor(
  BuildContext context, {
  required RepeatSpec initial,
  required bool hasReminder,
  Color accent = T.accent,
}) {
  return showFormSheet<RepeatSpec>(
    context,
    builder: (context, layout) => _RepeatSheet(
      initial: initial,
      hasReminder: hasReminder,
      accent: accent,
      layout: layout,
    ),
  );
}

class _RepeatSheet extends StatefulWidget {
  const _RepeatSheet({
    required this.initial,
    required this.hasReminder,
    required this.accent,
    required this.layout,
  });

  final RepeatSpec initial;

  /// A scheduled repeat is measured from the reminder, so without one it would
  /// never produce a second occurrence. Said in the panel rather than enforced
  /// silently on save.
  final bool hasReminder;

  final Color accent;
  final Layout layout;

  @override
  State<_RepeatSheet> createState() => _RepeatSheetState();
}

/// The shapes a schedule can take, as the panel offers them. Three of them are
/// a single rule and two open a second row of controls.
enum _Shape { simple, monthLast, nthWeekday, interval }

class _RepeatSheetState extends State<_RepeatSheet> {
  late bool _repeats = widget.initial.repeats;
  late String _from = widget.initial.from;
  late int? _lead = widget.initial.lead;

  // The simple rule, kept even while another shape is selected, so switching
  // back and forth does not lose what was chosen.
  late String _simple = _initialSimple();
  late _Shape _shape = _initialShape();
  late int _ordinal = _initialOrdinal();
  late int _weekday = _initialWeekday();
  late int _count = _initialCount();
  late String _unit = _initialUnit();

  String _initialSimple() {
    final rule = widget.initial.recur;
    return rule != null && Recur.rules.contains(rule) ? rule : Recur.weekly;
  }

  _Shape _initialShape() {
    final rule = widget.initial.recur;
    if (rule == null) return _Shape.simple;
    if (rule == Recur.monthLast) return _Shape.monthLast;
    if (Recur.rules.contains(rule)) return _Shape.simple;
    if (rule.startsWith('every-')) return _Shape.interval;
    if (rule.startsWith('month-')) return _Shape.nthWeekday;
    return _Shape.simple;
  }

  int _initialOrdinal() {
    final parts = (widget.initial.recur ?? '').split('-');
    if (parts.length != 3 || parts[0] != 'month') return 1;
    return parts[1] == 'last' ? Recur.ordLast : (int.tryParse(parts[1]) ?? 1);
  }

  int _initialWeekday() {
    final parts = (widget.initial.recur ?? '').split('-');
    if (parts.length != 3 || parts[0] != 'month') return DateTime.monday;
    const names = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    final index = names.indexOf(parts[2]);
    return index < 0 ? DateTime.monday : index + 1;
  }

  int _initialCount() {
    final parts = (widget.initial.recur ?? '').split('-');
    if (parts.length != 3 || parts[0] != 'every') return 2;
    return int.tryParse(parts[1]) ?? 2;
  }

  String _initialUnit() {
    final parts = (widget.initial.recur ?? '').split('-');
    if (parts.length != 3 || parts[0] != 'every') return Recur.unitWeek;
    return Recur.units.contains(parts[2]) ? parts[2] : Recur.unitWeek;
  }

  /// What the controls currently add up to. Everything on screen reads this,
  /// so the explanation and what Save writes cannot disagree.
  RepeatSpec get _spec {
    if (!_repeats) return RepeatSpec.once;

    // Counting from the completion only makes sense as an interval: the
    // question it answers is "how long after I last did it", and "every month
    // on the 3rd, after it is done" is two rules arguing.
    if (_from == RecurFrom.completion) {
      return RepeatSpec(
        recur: Recur.every(_count, _unit),
        from: RecurFrom.completion,
        lead: 0,
      );
    }

    final rule = switch (_shape) {
      _Shape.simple => _simple,
      _Shape.monthLast => Recur.monthLast,
      _Shape.nthWeekday => Recur.nthWeekday(_ordinal, _weekday),
      _Shape.interval => Recur.every(_count, _unit),
    };
    return RepeatSpec(recur: rule, from: RecurFrom.schedule, lead: _lead);
  }

  @override
  Widget build(BuildContext context) {
    final touch = widget.layout.touch;
    final spec = _spec;

    return FormSheet(
      accent: widget.accent,
      layout: widget.layout,
      title: 'How it repeats',
      onClose: () => Navigator.pop(context),
      actions: [
        FormSheet.cancelButton(
          touch: touch,
          onTap: () => Navigator.pop(context),
        ),
        FormSheet.saveButton(
          touch: touch,
          accent: widget.accent,
          onTap: () => Navigator.pop(context, spec),
          label: 'Done',
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _chips([
              _choice('Once', !_repeats, () => setState(() => _repeats = false)),
              _choice('Repeats', _repeats, () => setState(() => _repeats = true)),
            ]),
            if (_repeats) ...[
              const SizedBox(height: T.s4),
              const _Label('Measured from'),
              const SizedBox(height: 6),
              _chips([
                for (final f in RecurFrom.all)
                  _choice(
                    RecurFrom.labels[f]!,
                    _from == f,
                    () => setState(() => _from = f),
                  ),
              ]),
              const SizedBox(height: T.s4),
              if (_from == RecurFrom.completion)
                ..._completionControls()
              else
                ..._scheduleControls(),
              const SizedBox(height: T.s4),
              Text(
                spec.explanation,
                style: const TextStyle(
                  fontSize: T.fsMeta,
                  color: T.muted,
                  height: 1.45,
                ),
              ),
              if (_from == RecurFrom.schedule && !widget.hasReminder) ...[
                const SizedBox(height: T.s2),
                const Text(
                  'A scheduled repeat is measured from the reminder, so this '
                  'needs one. Set a time and the repeat will stick; without '
                  'one it is dropped on save.',
                  style: TextStyle(
                    fontSize: T.fsMeta,
                    color: T.warn,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: T.s4),
              _variablesHelp(),
            ],
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- schedule

  List<Widget> _scheduleControls() => [
        const _Label('How often'),
        const SizedBox(height: 6),
        _chips([
          for (final r in Recur.rules)
            _choice(
              Recur.label(r),
              _shape == _Shape.simple && _simple == r,
              () => setState(() {
                _shape = _Shape.simple;
                _simple = r;
              }),
            ),
          _choice(
            'Last day of the month',
            _shape == _Shape.monthLast,
            () => setState(() => _shape = _Shape.monthLast),
          ),
          _choice(
            'Nth weekday',
            _shape == _Shape.nthWeekday,
            () => setState(() => _shape = _Shape.nthWeekday),
          ),
          _choice(
            'Every few…',
            _shape == _Shape.interval,
            () => setState(() => _shape = _Shape.interval),
          ),
        ]),
        if (_shape == _Shape.nthWeekday) ...[
          const SizedBox(height: T.s3),
          _chips([
            for (final ord in Recur.ordinals)
              _choice(
                _ordinalLabel(ord),
                _ordinal == ord,
                () => setState(() => _ordinal = ord),
              ),
          ]),
          const SizedBox(height: 6),
          _chips([
            for (var wd = DateTime.monday; wd <= DateTime.sunday; wd++)
              _choice(
                _weekdayLabel(wd),
                _weekday == wd,
                () => setState(() => _weekday = wd),
              ),
          ]),
        ],
        if (_shape == _Shape.interval) ...[
          const SizedBox(height: T.s3),
          _intervalRow(),
        ],
        const SizedBox(height: T.s4),
        const _Label('The next one appears'),
        const SizedBox(height: 6),
        _chips([
          for (final entry in _leadOptions.entries)
            _choice(
              entry.value,
              _lead == entry.key,
              () => setState(() => _lead = entry.key),
            ),
        ]),
      ];

  // ------------------------------------------------------------ completion

  List<Widget> _completionControls() => [
        const _Label('Comes back after'),
        const SizedBox(height: 6),
        _intervalRow(),
      ];

  Widget _intervalRow() => Row(
        children: [
          _Stepper(
            value: _count,
            accent: widget.accent,
            touch: widget.layout.touch,
            onChanged: (n) => setState(() => _count = n),
          ),
          const SizedBox(width: T.s2),
          Expanded(
            child: _chips([
              for (final unit in Recur.units)
                _choice(
                  _unitLabel(unit, _count),
                  _unit == unit,
                  () => setState(() => _unit = unit),
                ),
            ]),
          ),
        ],
      );

  // ----------------------------------------------------------------- parts

  Widget _variablesHelp() {
    return Container(
      padding: const EdgeInsets.all(T.s2),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The title and notes can name the date this one is for:',
            style: TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.4),
          ),
          const SizedBox(height: 4),
          Text(
            taskVariables.map((v) => '\$(${v.name})').join('  '),
            style: const TextStyle(fontSize: T.fsMeta, color: T.text),
          ),
          const SizedBox(height: 4),
          const Text(
            'e.g. "Send working hours for \$(month)". Offsets work too: '
            '\$(month-1) is the month before. Each occurrence is written out '
            'once, against its own due date, so what is in History stays what '
            'it said.',
            style: TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _chips(List<Widget> children) =>
      Wrap(spacing: 6, runSpacing: 6, children: children);

  Widget _choice(String label, bool selected, VoidCallback onTap) => ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: T.fsMeta)),
        selected: selected,
        onSelected: (_) => onTap(),
      );

  static String _ordinalLabel(int ord) => switch (ord) {
        1 => 'First',
        2 => 'Second',
        3 => 'Third',
        4 => 'Fourth',
        _ => 'Last',
      };

  static String _weekdayLabel(int weekday) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];

  static String _unitLabel(String unit, int count) {
    final words = switch (unit) {
      Recur.unitDay => ['day', 'days'],
      Recur.unitWeek => ['week', 'weeks'],
      Recur.unitMonth => ['month', 'months'],
      _ => ['year', 'years'],
    };
    return count == 1 ? words[0] : words[1];
  }
}

/// A number with a - and a + either side. A stepper rather than a field: the
/// numbers that matter here are 2 and 3, and a keyboard on a phone for that is
/// a keyboard for nothing.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.accent,
    required this.touch,
    required this.onChanged,
  });

  final int value;
  final Color accent;
  final bool touch;
  final ValueChanged<int> onChanged;

  static const max = 30;

  @override
  Widget build(BuildContext context) {
    final size = touch ? 30.0 : 22.0;

    Widget button(IconData icon, VoidCallback? onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(T.radius),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: touch ? 18 : 14,
              color: onTap == null ? T.muted.withValues(alpha: 0.4) : accent,
            ),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            Icons.remove_rounded,
            value <= 1 ? null : () => onChanged(value - 1),
          ),
          SizedBox(
            width: 24,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: T.fsBody,
                color: T.text,
                fontWeight: T.wMedium,
              ),
            ),
          ),
          button(
            Icons.add_rounded,
            value >= max ? null : () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
      );
}
