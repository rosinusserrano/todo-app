// Reminders.
//
// Polling, not a timer per task. A scheduled timer is the obvious design and
// the wrong one here: it silently loses every reminder that came due while the
// machine was asleep or the app was closed, which is most of the ones that
// matter. A poll over the database catches those on the next tick, because the
// database - not a timer - is what holds the state.
//
// Firing is deliberately not a toast. This app is an always-on-top widget that
// can hide itself in the tray; the strongest thing it can do is *be there* -
// so a due reminder pulls the window back in front of you and the row keeps
// showing as due until it is dealt with. That also means no notification
// dependency and nothing to configure per platform.

import 'dart:async';

import 'sync/local_store.dart';
import 'sync/models.dart';

class ReminderService {
  ReminderService(this._store, {required this.onDue, Duration? interval})
      : _interval = interval ?? const Duration(seconds: 20);

  final LocalStore _store;
  final Duration _interval;

  /// Called with the tasks that have just come due. Never called with an empty
  /// list, so the callback can surface the window unconditionally.
  final Future<void> Function(List<Task> due) onDue;

  Timer? _timer;

  /// Reminders already announced, so a task that stays due does not re-surface
  /// the window every tick. Memory only, and that is the intent: an unfinished
  /// task whose reminder passed is still worth a nudge after a restart, and
  /// syncing this would let the first device to fire silence all the others.
  final _announced = <String>{};

  void start() {
    _timer ??= Timer.periodic(_interval, (_) => tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Exposed for tests and for calling once at startup, so a reminder that came
  /// due while the app was closed lands immediately rather than up to one
  /// interval later.
  Future<void> tick([DateTime? now]) async {
    final due = await _store.dueReminders(now);

    // Forget tasks that are no longer due at all - cleared, completed or
    // pushed into the future - so re-arming an old task can fire again.
    final dueIds = due.map((t) => t.uuid).toSet();
    _announced.removeWhere((id) => !dueIds.contains(id));

    final fresh = due.where((t) => !_announced.contains(t.uuid)).toList();
    if (fresh.isEmpty) return;

    _announced.addAll(fresh.map((t) => t.uuid));
    await onDue(fresh);
  }

  void dispose() => stop();
}
