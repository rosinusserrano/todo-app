// Who has been using the sync server and how hard - the admin's overview,
// a page of the settings sheet beside *People on this server*.
//
// Counters only (server/traffic.js): requests, syncs, rows each way, bytes,
// per account per day. Nothing here says what anyone wrote.
//
// The chart is one series, requests per day, in the accent: one hue, thin
// bars with a surface gap, rounded only at the data end, a recessive
// baseline. Pointing at (or tapping) a day puts that day's figures in the
// readout above the chart rather than in a tooltip, which is the same on a
// phone as under a mouse; with nothing picked the readout is the whole
// window. The per-account list underneath is the table view of the same
// numbers.

import 'package:flutter/material.dart';

import '../sync/admin_client.dart';
import '../sync/sync_service.dart';
import '../theme.dart';

/// The windows offered, in days.
const kTrafficWindows = [7, 30, 90];

class ServerTrafficView extends StatefulWidget {
  const ServerTrafficView({
    super.key,
    required this.sync,
    required this.onBack,
    this.load,
  });

  final SyncService sync;
  final VoidCallback onBack;

  /// Replaces the request, for tests.
  final Future<TrafficOverview> Function(int days)? load;

  @override
  State<ServerTrafficView> createState() => _ServerTrafficViewState();
}

class _ServerTrafficViewState extends State<ServerTrafficView> {
  int _days = 30;
  TrafficOverview? _data;
  String? _error;
  bool _busy = true;

  /// The day the pointer is on, by index into [TrafficOverview.days].
  int? _picked;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final days = _days;
    try {
      final TrafficOverview data;
      if (widget.load != null) {
        data = await widget.load!(days);
      } else {
        final client = AdminClient(
          baseUrl: widget.sync.baseUrl!,
          token: widget.sync.token!,
        );
        try {
          data = await client.traffic(days: days);
        } finally {
          client.dispose();
        }
      }
      if (!mounted || days != _days) return;
      setState(() {
        _data = data;
        _picked = null;
      });
    } on AdminException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setDays(int days) {
    if (days == _days) return;
    setState(() => _days = days);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(T.s3, T.s2, T.s3, T.s2),
            children: [
              _windowPicker(),
              if (_error != null) ...[
                const SizedBox(height: T.s2),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: T.fsMeta, color: T.danger),
                ),
              ],
              if (data != null) ...[
                const SizedBox(height: T.s3),
                _readout(data),
                const SizedBox(height: T.s2),
                _TrafficChart(
                  days: data.days,
                  picked: _picked,
                  onPick: (i) => setState(() => _picked = i),
                ),
                const SizedBox(height: T.s4),
                const Text(
                  'PEOPLE',
                  style: TextStyle(
                    fontFamily: T.fontDisplay,
                    fontSize: T.fsMeta,
                    letterSpacing: 1.2,
                    color: T.muted,
                  ),
                ),
                const SizedBox(height: T.s1),
                for (final a in data.accounts) _account(a),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(T.s2, 0, T.s2, T.s2),
          child: Row(
            children: [
              TextButton(onPressed: widget.onBack, child: const Text('Back')),
              const Spacer(),
              TextButton(
                onPressed: _busy ? null : _load,
                child: const Text('Refresh'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The window, as three words: the picked one lit, the others muted.
  /// Not chips - three bordered pills are wider than a phone's settings
  /// sheet, and the app has no pills anywhere else.
  Widget _windowPicker() {
    return Wrap(
      spacing: T.s1,
      children: [
        for (final d in kTrafficWindows)
          InkWell(
            onTap: () => _setDays(d),
            borderRadius: BorderRadius.circular(T.radius),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: T.s2,
                vertical: T.s1,
              ),
              decoration: BoxDecoration(
                color: d == _days ? T.text.withValues(alpha: 0.08) : null,
                borderRadius: BorderRadius.circular(T.radius),
              ),
              child: Text(
                '$d days',
                style: TextStyle(
                  fontSize: T.fsLabel,
                  fontWeight: d == _days ? T.wMedium : null,
                  color: d == _days ? T.text : T.muted,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The figures for the picked day, or for the whole window.
  Widget _readout(TrafficOverview data) {
    final i = _picked;
    final day = i == null || i >= data.days.length ? null : data.days[i];
    final c = day?.counts ?? data.totals;
    final title = day == null ? 'Last $_days days' : describeDay(day.day);
    final people =
        day?.activeUsers ??
        data.accounts.where((a) => a.counts.requests > 0).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
        ),
        const SizedBox(height: T.s1),
        Wrap(
          spacing: T.s4,
          runSpacing: T.s2,
          children: [
            _Stat(value: _count(c.requests), label: 'requests'),
            _Stat(value: _count(c.syncs), label: 'syncs'),
            _Stat(value: _count(c.rowsIn + c.rowsOut), label: 'rows moved'),
            _Stat(value: formatBytes(c.bytes), label: 'transferred'),
            _Stat(
              value: '$people',
              label: people == 1 ? 'person active' : 'people active',
            ),
            if (day == null)
              _Stat(value: '${data.devicesOnline}', label: 'connected now'),
          ],
        ),
      ],
    );
  }

  Widget _account(TrafficAccount a) {
    final me = widget.sync.identity?.user == a.id;
    final seen = describeSeen(a.lastSeenAt);
    final c = a.counts;
    return Padding(
      padding: const EdgeInsets.only(bottom: T.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, color: Color(0x14FFFFFF)),
          const SizedBox(height: T.s2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: a.label,
                        style: const TextStyle(
                          fontSize: T.fsBody,
                          color: T.text,
                        ),
                      ),
                      if (me)
                        const TextSpan(
                          text: '  you',
                          style: TextStyle(fontSize: T.fsMeta, color: T.muted),
                        ),
                      if (a.admin)
                        const TextSpan(
                          text: '  admin',
                          style: TextStyle(fontSize: T.fsMeta, color: T.muted),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _count(c.requests),
                style: const TextStyle(
                  fontFamily: T.fontDisplay,
                  fontSize: T.fsBody,
                  color: T.text,
                ),
              ),
              const Text(
                ' req',
                style: TextStyle(fontSize: T.fsMeta, color: T.muted),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              seen,
              if (a.devicesOnline > 0) '${a.devicesOnline} connected now',
              'active ${a.activeDays} of $_days days',
            ].join(' · '),
            style: const TextStyle(
              fontSize: T.fsMeta,
              color: T.muted,
              height: 1.4,
            ),
          ),
          Text(
            [
              '${_count(c.syncs)} syncs',
              '${_count(c.rowsIn)} rows up, ${_count(c.rowsOut)} down',
              formatBytes(c.bytes),
            ].join(' · '),
            style: const TextStyle(
              fontSize: T.fsMeta,
              color: T.muted,
              height: 1.4,
            ),
          ),
          Text(
            [
              'keeps ${_count(a.rowsStored)} rows',
              if (a.blobBytes > 0) '${formatBytes(a.blobBytes)} of recordings',
            ].join(' · '),
            style: const TextStyle(
              fontSize: T.fsMeta,
              color: T.muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontFamily: T.fontDisplay,
            fontSize: T.fsTitle,
            fontWeight: T.wMedium,
            color: T.text,
            height: 1.1,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
        ),
      ],
    );
  }
}

/// Requests per day, oldest at the left.
class _TrafficChart extends StatelessWidget {
  const _TrafficChart({
    required this.days,
    required this.picked,
    required this.onPick,
  });

  final List<TrafficDay> days;
  final int? picked;
  final ValueChanged<int?> onPick;

  static const _height = 96.0;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final top = days.fold<int>(
      0,
      (m, d) => d.counts.requests > m ? d.counts.requests : m,
    );
    // Thin bars with a surface gap: 2px between them, less only when a
    // 90-day window would leave the bars thinner than the gap.
    return LayoutBuilder(
      builder: (context, box) {
        final gap = box.maxWidth / days.length > 6 ? 2.0 : 1.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              top == 0
                  ? 'No requests yet'
                  : '${_count(top)} requests on the busiest day',
              style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
            ),
            const SizedBox(height: T.s1),
            SizedBox(
              height: _height,
              child: MouseRegion(
                onExit: (_) => onPick(null),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < days.length; i++)
                      Expanded(
                        child: _Bar(
                          fraction: top == 0
                              ? 0
                              : days[i].counts.requests / top,
                          gap: gap,
                          picked: picked == i,
                          dimmed: picked != null && picked != i,
                          semantics:
                              '${describeDay(days[i].day)}: ${days[i].counts.requests} requests',
                          onEnter: () => onPick(i),
                          onTap: () => onPick(picked == i ? null : i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Container(height: 1, color: T.muted.withValues(alpha: 0.35)),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  describeDay(days.first.day, short: true),
                  style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
                ),
                const Spacer(),
                Text(
                  describeDay(days.last.day, short: true),
                  style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.gap,
    required this.picked,
    required this.dimmed,
    required this.semantics,
    required this.onEnter,
    required this.onTap,
  });

  final double fraction;
  final double gap;
  final bool picked;
  final bool dimmed;
  final String semantics;
  final VoidCallback onEnter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The whole column is the target, not the bar: a quiet day's bar is a
    // pixel tall and still has to be pointable.
    return Semantics(
      label: semantics,
      button: true,
      child: MouseRegion(
        onEnter: (_) => onEnter(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: gap / 2),
            child: Stack(
              children: [
                if (picked)
                  Positioned.fill(
                    child: ColoredBox(color: T.text.withValues(alpha: 0.05)),
                  ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: fraction == 0 ? 0 : fraction.clamp(0.02, 1.0),
                    widthFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: T.accent.withValues(alpha: dimmed ? 0.45 : 1),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _count(int n) {
  if (n < 10000) return '$n';
  if (n < 1000000) return '${(n / 1000).toStringAsFixed(n < 100000 ? 1 : 0)}k';
  return '${(n / 1000000).toStringAsFixed(1)}M';
}

/// Bytes the way a person reads them: 0 B, 812 B, 4.2 KB, 31 MB.
String formatBytes(int b) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = b.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  final digits = u == 0 || v >= 10 ? 0 : 1;
  return '${v.toStringAsFixed(digits)} ${units[u]}';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// `2026-11-09` as "Mon 9 Nov", or "9 Nov" when [short].
String describeDay(String day, {bool short = false}) {
  final d = DateTime.tryParse(day);
  if (d == null) return day;
  final date = '${d.day} ${_months[d.month - 1]}';
  return short ? date : '${_weekdays[d.weekday - 1]} $date';
}

/// When an account last used any token.
String describeSeen(DateTime? seen, {DateTime? now}) {
  if (seen == null) return 'never seen';
  final ago = (now ?? DateTime.now()).difference(seen);
  if (ago.inMinutes < 2) return 'seen just now';
  if (ago.inHours < 1) return 'seen ${ago.inMinutes}m ago';
  if (ago.inDays < 1) return 'seen ${ago.inHours}h ago';
  return 'seen ${ago.inDays}d ago';
}
