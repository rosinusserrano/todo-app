// Variables in a repeating task's title and notes.
//
// "Send working hours for $(month) to management", made on the last day of
// every month, has to say *September* on the one made in September and
// *October* on the one made in October - and it has to go on saying September
// after October's exists, because the September row is in History and History
// is a record of what was done, not a template that keeps re-rendering.
//
// So expansion happens **once, when the row is written**, against that
// occurrence's own due date. The unexpanded form lives on in `recur_text` /
// `recur_notes`, which is the only reason those columns exist: the first
// expansion would otherwise eat the variable and the series would repeat one
// month's wording for ever.
//
// Deliberately small, and deliberately not a date-format string. `$(month)` is
// something a person types into a title field on a phone once and never thinks
// about again; `%B` and friends are a syntax to look up. The offset form -
// `$(month-1)` - is the one generalisation worth having, because "last month's
// hours, on the first of the month" is as common as "this month's, on the
// last".
//
// An unknown name is left exactly as it was written. A title is prose, `$(` is
// not a sequence anybody writes by accident, and mangling something because it
// looked like a variable is worse than printing a variable that was misspelled.

/// One name the expander knows, and what it prints.
class TaskVariable {
  const TaskVariable(this.name, this.hint, this.unit, this.render);

  final String name;

  /// What it looks like, for the help line in the repeat editor.
  final String hint;

  /// Which unit an offset moves. `$(month-1)` shifts by a month; `$(day+1)` by
  /// a day.
  final TaskVariableUnit unit;

  final String Function(DateTime at) render;
}

/// Which field an offset moves.
enum TaskVariableUnit { day, week, month, year }

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// The ISO-8601 week number: weeks start on Monday, and week 1 is the one
/// holding the first Thursday of the year.
int isoWeek(DateTime at) {
  final day = DateTime(at.year, at.month, at.day);
  final thursday = day.add(Duration(days: 4 - day.weekday));
  final firstDay = DateTime(thursday.year, 1, 1);
  return 1 + (thursday.difference(firstDay).inDays / 7).floor();
}

/// Everything `$(...)` can name. Order is the order the help line prints them.
const taskVariables = <TaskVariable>[
  TaskVariable('month', 'September', TaskVariableUnit.month, _renderMonth),
  TaskVariable('mon', 'Sep', TaskVariableUnit.month, _renderMon),
  TaskVariable('mm', '09', TaskVariableUnit.month, _renderMm),
  TaskVariable('year', '2026', TaskVariableUnit.year, _renderYear),
  TaskVariable('yy', '26', TaskVariableUnit.year, _renderYy),
  TaskVariable('day', '9', TaskVariableUnit.day, _renderDay),
  TaskVariable('dd', '09', TaskVariableUnit.day, _renderDd),
  TaskVariable('weekday', 'Wednesday', TaskVariableUnit.day, _renderWeekday),
  TaskVariable('wd', 'Wed', TaskVariableUnit.day, _renderWd),
  TaskVariable('date', '9 Sep 2026', TaskVariableUnit.day, _renderDate),
  TaskVariable('week', '37', TaskVariableUnit.week, _renderWeek),
  TaskVariable('quarter', 'Q3', TaskVariableUnit.month, _renderQuarter),
];

String _renderMonth(DateTime at) => _monthNames[at.month - 1];
String _renderMon(DateTime at) => _monthNames[at.month - 1].substring(0, 3);
String _renderMm(DateTime at) => _two(at.month);
String _renderYear(DateTime at) => '${at.year}';
String _renderYy(DateTime at) => _two(at.year % 100);
String _renderDay(DateTime at) => '${at.day}';
String _renderDd(DateTime at) => _two(at.day);
String _renderWeekday(DateTime at) => _weekdayNames[at.weekday - 1];
String _renderWd(DateTime at) => _weekdayNames[at.weekday - 1].substring(0, 3);
String _renderDate(DateTime at) =>
    '${at.day} ${_monthNames[at.month - 1].substring(0, 3)} ${at.year}';
String _renderWeek(DateTime at) => '${isoWeek(at)}';
String _renderQuarter(DateTime at) => 'Q${((at.month - 1) ~/ 3) + 1}';

final _pattern = RegExp(r'\$\(\s*([A-Za-z]+)\s*([+-]\s*\d+)?\s*\)');

/// Whether [source] has anything in it worth expanding. Used to decide whether
/// a task needs a template stored at all.
bool hasTaskVariables(String source) => _pattern.hasMatch(source);

/// Replace every `$(...)` in [source] with what it says about [at].
///
/// [at] is the occurrence's **due date**, not today: a task created three days
/// early for the last day of the month must still say the month it is for.
String expandTaskVariables(String source, DateTime at) {
  if (source.isEmpty) return source;
  return source.replaceAllMapped(_pattern, (match) {
    final name = match.group(1)!.toLowerCase();
    final variable = _lookup(name);
    if (variable == null) return match.group(0)!;

    final offset = int.tryParse((match.group(2) ?? '0').replaceAll(' ', ''));
    if (offset == null) return match.group(0)!;

    return variable.render(_shift(at, variable.unit, offset));
  });
}

TaskVariable? _lookup(String name) {
  for (final v in taskVariables) {
    if (v.name == name) return v;
  }
  return null;
}

/// Calendar arithmetic, the same way [Recur] does it and for the same reason:
/// `$(month-1)` on 31 March means February, and adding `Duration(days: -31)`
/// to an instant is not how you say that. Day-of-month overflow does not
/// matter here - every variable prints one field - but clamping it anyway keeps
/// `$(date-1)`-style offsets honest.
DateTime _shift(DateTime at, TaskVariableUnit unit, int by) {
  if (by == 0) return at;
  switch (unit) {
    case TaskVariableUnit.day:
      return DateTime(at.year, at.month, at.day + by, at.hour, at.minute);
    case TaskVariableUnit.week:
      return DateTime(at.year, at.month, at.day + 7 * by, at.hour, at.minute);
    case TaskVariableUnit.month:
      // DateTime normalises month 0 and month 13 in both directions, which is
      // the whole of the year arithmetic.
      final anchor = DateTime(at.year, at.month + by);
      return _clampedTo(anchor, at);
    case TaskVariableUnit.year:
      return _clampedTo(DateTime(at.year + by, at.month), at);
  }
}

/// [anchor]'s year and month with [at]'s day and time, pulled back to the last
/// day of the month when that month is short.
DateTime _clampedTo(DateTime anchor, DateTime at) {
  final last = DateTime(anchor.year, anchor.month + 1, 0).day;
  return DateTime(anchor.year, anchor.month, at.day > last ? last : at.day,
      at.hour, at.minute);
}
