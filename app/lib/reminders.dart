// Reminders.
//
// Polling, not a timer per task. A scheduled timer is the obvious design and
// the wrong one here: it silently loses every reminder that came due while the
// machine was asleep or the app was closed, which is most of the ones that
// matter. A poll over the database catches those on the next tick, because the
// database - not a timer - is what holds the state.
//
// What firing *does* is the shell's. On Windows it is a toast, like every
// other app there (notifications.dart, `showDue`); on the other desktops the
// always-on-top widget pulls itself back in front of you. Either way the row
// keeps showing as due until it is dealt with.

import 'dart:async';
import 'dart:convert';

import 'sync/local_store.dart';
import 'sync/models.dart';

class ReminderService {
  ReminderService(
    this._store, {
    required this.onDue,
    this.onThoughtsDue,
    this.onReviewsDue,
    this.onTick,
    Duration? interval,
  }) : _interval = interval ?? const Duration(seconds: 20);

  final LocalStore _store;
  final Duration _interval;

  /// Called with the tasks that have just come due. Never called with an empty
  /// list, so the callback can surface the window unconditionally.
  final Future<void> Function(List<Task> due) onDue;

  /// The same for thoughts with a reminder ("keys, in 10 minutes"), which
  /// are in the pile rather than on a list, so the shell shows them there.
  final Future<void> Function(List<SideThought> due)? onThoughtsDue;

  /// Parked shelves whose review has come round
  /// ([ParkedGroup.reviewRemindAt]). Announced once per review **per device,
  /// restarts included** - unlike a task's reminder, which nags again after a
  /// restart. A shelf left unreviewed for a fortnight would otherwise open
  /// Parked on every start of a widget that starts with Windows, and the
  /// dock's dot already says it is waiting. The key carries when the shelf
  /// was last reviewed, so reviewing it starts a new one.
  final Future<void> Function(List<ParkedGroup> due)? onReviewsDue;

  /// Called on every tick, due reminders or not.
  ///
  /// This poll is the only clock in the app, and reminders are not the only
  /// thing that comes true because time passed: a calendar block *starting* is
  /// the other, and nothing is written to the database when it does. A second
  /// timer for that would be a second thing to start, stop, resume and keep in
  /// step with this one, for the same 20-second question.
  final Future<void> Function()? onTick;

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
    await onTick?.call();

    final due = await _store.dueReminders(now);
    final thoughts = onThoughtsDue == null
        ? const <SideThought>[]
        : await _store.dueThoughtReminders(now);
    final reviews = onReviewsDue == null
        ? const <ParkedGroup>[]
        : await _store.dueGroupReviews(now);
    String reviewKey(ParkedGroup g) => '${g.uuid}:${g.lastReviewedAt ?? ''}';
    final announcedReviews =
        onReviewsDue == null ? <String>{} : await _announcedReviews();
    final freshReviews = reviews
        .where((g) => !announcedReviews.contains(reviewKey(g)))
        .toList();
    final keepReviews = reviews.map(reviewKey).toSet();
    if (freshReviews.isNotEmpty ||
        announcedReviews.length != keepReviews.length) {
      // Pruned to what is still due, so the setting stays a handful of keys.
      await _store.setSetting(_kReviewsAnnounced, jsonEncode([...keepReviews]));
    }

    // Forget rows that are no longer due at all - cleared, completed,
    // resolved or pushed into the future - so re-arming one can fire again.
    // Tasks and thoughts share the set: their uuids cannot collide.
    final dueIds = {...due.map((t) => t.uuid), ...thoughts.map((t) => t.uuid)};
    _announced.removeWhere((id) => !dueIds.contains(id));

    final fresh = due.where((t) => !_announced.contains(t.uuid)).toList();
    final freshThoughts = thoughts
        .where((t) => !_announced.contains(t.uuid))
        .toList();
    _announced.addAll(fresh.map((t) => t.uuid));
    _announced.addAll(freshThoughts.map((t) => t.uuid));

    if (fresh.isNotEmpty) await onDue(fresh);
    if (freshThoughts.isNotEmpty) await onThoughtsDue!(freshThoughts);
    if (freshReviews.isNotEmpty) await onReviewsDue!(freshReviews);
  }

  static const _kReviewsAnnounced = 'reminders:reviews-announced';

  Future<Set<String>> _announcedReviews() async {
    try {
      final raw = await _store.setting(_kReviewsAnnounced);
      return raw == null ? {} : {...(jsonDecode(raw) as List).cast<String>()};
    } on FormatException {
      return {};
    }
  }

  void dispose() => stop();
}
