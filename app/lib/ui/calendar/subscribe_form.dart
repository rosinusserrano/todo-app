// Subscribing to a calendar by its address, and managing the subscriptions.
//
// Two panels, both the shared FormSheet. The subscribe form is a
// fetch-then-confirm, like the .ics import: the address is checked before
// anything is written, so a wrong one (a page link rather than the iCal one is
// the usual mistake) is caught while the person is still looking at it rather
// than as a calendar that quietly stays empty.
//
// **Where the events go is a choice, and both answers are first class.** A
// new calendar is the default - it gets the feed's name and its own colour and
// can be hidden on its own - but a feed can just as well be merged into a
// calendar that already exists, a workspace's own included, so "my work
// meetings" can sit on the Work workspace's calendar beside the blocks planned
// there. The events stay marked as the feed's either way (feed_uuid), which is
// what keeps them read-only and what lets unsubscribing take exactly them.

import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../layout.dart';
import '../../sync/feeds.dart';
import '../../sync/ics.dart';
import '../../sync/models.dart';
import '../../theme.dart';
import '../form_sheet.dart';

/// Subscribe to a new calendar, or edit [existing].
Future<void> showSubscribeForm(
  BuildContext context,
  AppState state, {
  CalendarFeed? existing,
}) {
  return showFormSheet<void>(
    context,
    builder: (context, layout) =>
        _SubscribeForm(state: state, existing: existing, layout: layout),
  );
}

/// Every subscription, how its last refresh went, and the way to add one.
Future<void> showSubscriptions(BuildContext context, AppState state) {
  return showFormSheet<void>(
    context,
    builder: (context, layout) =>
        _SubscriptionList(state: state, layout: layout),
  );
}

/// "5 min ago", for the line under a subscription.
String describeAgo(DateTime at, [DateTime? now]) {
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  final days = d.inDays;
  return days == 1 ? 'yesterday' : '$days days ago';
}

/// The one line a subscription's state comes down to.
String describeFeedStatus(FeedStatus status, {bool refreshing = false}) {
  if (refreshing) return 'Refreshing…';
  final error = status.error;
  final fetched = status.fetchedAt;
  if (error != null) {
    return fetched == null
        ? error
        : '$error Showing what was there ${describeAgo(fetched)}.';
  }
  if (fetched == null) return 'Not fetched yet.';
  final n = status.count;
  return 'Updated ${describeAgo(fetched)} · $n event${n == 1 ? '' : 's'}';
}

class _SubscribeForm extends StatefulWidget {
  const _SubscribeForm({
    required this.state,
    required this.layout,
    this.existing,
  });

  final AppState state;
  final Layout layout;
  final CalendarFeed? existing;

  @override
  State<_SubscribeForm> createState() => _SubscribeFormState();
}

/// Where the events go: a calendar made for them, or one already there.
const _newCalendar = '';

class _SubscribeFormState extends State<_SubscribeForm> {
  late final _url = TextEditingController(text: widget.existing?.url ?? '');
  late final _name = TextEditingController(text: widget.existing?.name ?? '');

  /// [_newCalendar] or a calendar's uuid.
  late String _target = widget.existing?.calendarUuid ?? _newCalendar;
  late String _color = T.toHex(T.workspaceColors[2]);
  late bool _alerts = widget.existing?.alerts ?? false;

  /// The last fetch the form made, and what it found. Subscribing hands the
  /// text over so the address is not asked twice.
  String? _text;
  String? _checkedUrl;
  List<FeedInstance> _found = const [];
  String? _error;
  bool _checking = false;

  bool get _editing => widget.existing != null;

  AppState get _s => widget.state;

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final url = _url.text.trim();
    if (url.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final text = await _s.previewFeed(url);
      final window = feedWindow();
      final found = expandFeed(parseIcs(text), window.from, window.to);
      if (!mounted) return;
      setState(() {
        _text = text;
        _checkedUrl = url;
        _found = found;
        if (_name.text.trim().isEmpty) {
          _name.text = icsCalendarName(text) ?? _hostOf(url);
        }
      });
    } on FeedError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not read it: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  static String _hostOf(String url) => feedUri(url)?.host ?? 'Subscribed';

  bool get _checked => _text != null && _checkedUrl == _url.text.trim();

  Future<void> _save() async {
    final existing = widget.existing;
    if (existing != null) {
      await _s.updateFeed(
        existing,
        name: _name.text,
        calendarUuid: _target == _newCalendar ? null : _target,
        alerts: _alerts,
      );
    } else {
      if (!_checked) return;
      await _s.subscribe(
        url: _url.text,
        name: _name.text,
        calendarUuid: _target == _newCalendar ? null : _target,
        color: _color,
        alerts: _alerts,
        text: _text,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _unsubscribe() async {
    final existing = widget.existing;
    if (existing == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: T.bgSolid,
        title: Text('Unsubscribe from ${existing.name}?',
            style: const TextStyle(fontSize: T.fsMenu)),
        content: const Text(
          'Its events are removed from every device. Anything you added to '
          'that calendar yourself stays.',
          style: TextStyle(fontSize: T.fsLabel, color: T.muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unsubscribe'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _s.unsubscribe(existing);
    if (mounted) Navigator.pop(context);
  }

  Color get _accent {
    if (_target == _newCalendar) return T.parseHex(_color);
    final c = _s.calendarsByUuid[_target];
    return c == null ? T.accent : _s.calendarColor(c);
  }

  @override
  Widget build(BuildContext context) {
    final touch = widget.layout.touch;
    final accent = _accent;
    final canSave = _editing || _checked;

    return FormSheet(
      accent: accent,
      layout: widget.layout,
      title: _editing ? 'Subscription' : 'Subscribe to a calendar',
      onClose: () => Navigator.pop(context),
      actions: [
        if (_editing)
          FormSheet.dangerButton(
            touch: touch,
            label: 'Unsubscribe',
            onTap: _unsubscribe,
          ),
        FormSheet.cancelButton(
          touch: touch,
          onTap: () => Navigator.pop(context),
        ),
        Opacity(
          opacity: canSave ? 1 : 0.4,
          child: FormSheet.saveButton(
            touch: touch,
            accent: accent,
            label: _editing ? 'Save' : 'Subscribe',
            onTap: canSave ? _save : () => _check(),
          ),
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_editing)
              _Label(widget.existing!.url, selectable: true)
            else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _url,
                      autofocus: !touch,
                      keyboardType: TextInputType.url,
                      style: const TextStyle(fontSize: T.fsBody),
                      decoration: const InputDecoration(
                        hintText: 'webcal://… or https://….ics',
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _check(),
                    ),
                  ),
                  const SizedBox(width: T.s2),
                  FormSheet.plainButton(
                    touch: touch,
                    label: _checking ? 'Checking…' : 'Check',
                    onTap: _check,
                  ),
                ],
              ),
              const SizedBox(height: T.s2),
              const _Label(
                'In Google Calendar: Settings → the calendar → '
                '"Secret address in iCal format". Outlook, iCloud and '
                'Fastmail all publish one too.',
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: T.s2),
              Text(_error!,
                  style: const TextStyle(fontSize: T.fsMeta, color: T.warn)),
            ],
            if (_checked) ...[
              const SizedBox(height: T.s3),
              _Found(found: _found),
            ],
            if (_editing || _checked) ...[
              const SizedBox(height: T.s3),
              TextField(
                controller: _name,
                maxLength: 40,
                style: const TextStyle(fontSize: T.fsBody),
                decoration: const InputDecoration(
                  labelText: 'Name',
                  counterText: '',
                ),
              ),
              const SizedBox(height: T.s3),
              const _Heading('Put the events in'),
              const SizedBox(height: T.s2),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  // Retargeting an existing subscription onto a brand new
                  // calendar is two steps (make it, then pick it); offering it
                  // here would be a second place calendars get made.
                  if (!_editing)
                    ChoiceChip(
                      avatar: const Icon(Icons.add, size: 14),
                      label: const Text('A new calendar',
                          style: TextStyle(fontSize: T.fsMeta)),
                      selected: _target == _newCalendar,
                      onSelected: (_) =>
                          setState(() => _target = _newCalendar),
                    ),
                  for (final c in _s.calendars)
                    ChoiceChip(
                      avatar: Icon(Icons.circle,
                          size: 9, color: _s.calendarColor(c)),
                      label: Text(_s.calendarName(c),
                          style: const TextStyle(fontSize: T.fsMeta)),
                      selected: _target == c.uuid,
                      onSelected: (_) => setState(() => _target = c.uuid),
                    ),
                ],
              ),
              if (_target == _newCalendar) ...[
                const SizedBox(height: T.s3),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in T.workspaceColors)
                      _Swatch(
                        color: c,
                        selected:
                            T.toHex(c).toLowerCase() == _color.toLowerCase(),
                        onTap: () => setState(() => _color = T.toHex(c)),
                      ),
                  ],
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.only(top: T.s2),
                  child: _Label(
                    'Merged in beside what is already there. They stay '
                    "the subscription's: read-only, and removed again if "
                    'you unsubscribe.',
                  ),
                ),
              const SizedBox(height: T.s2),
              // A Row and a Switch, as the event editor does, not a
              // SwitchListTile: a ListTile paints its ink on the nearest
              // Material, which is behind the panel's own coloured surface.
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Notify for these events',
                            style: TextStyle(
                                fontSize: T.fsLabel, color: T.text)),
                        _Label("Off by default - the calendar's own app "
                            'probably already does.'),
                      ],
                    ),
                  ),
                  Switch(
                    value: _alerts,
                    activeThumbColor: accent,
                    onChanged: (v) => setState(() => _alerts = v),
                  ),
                ],
              ),
            ],
            if (_editing) ...[
              const SizedBox(height: T.s1),
              ListenableBuilder(
                listenable: _s,
                builder: (context, _) {
                  final f = widget.existing!;
                  return Row(
                    children: [
                      Expanded(
                        child: _Label(describeFeedStatus(
                          _s.feedStatus[f.uuid] ?? const FeedStatus(),
                          refreshing: _s.isRefreshingFeed(f.uuid),
                        )),
                      ),
                      FormSheet.plainButton(
                        touch: touch,
                        icon: Icons.refresh_rounded,
                        label: 'Refresh',
                        onTap: () => _s.refreshFeed(f),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the check found: how many, and the next few, so a wrong address
/// (somebody else's calendar, an empty one) is obvious before subscribing.
class _Found extends StatelessWidget {
  const _Found({required this.found});

  final List<FeedInstance> found;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _when(FeedInstance i) {
    final s = i.start;
    final date = '${s.day} ${_months[s.month - 1]}';
    if (i.event.allDay) return date;
    return '$date ${s.hour.toString().padLeft(2, '0')}:'
        '${s.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final next = found.where((i) => i.end.isAfter(now)).take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          found.isEmpty
              ? 'A calendar, but with nothing in it from three months ago to '
                  'a year ahead.'
              : '${found.length} event${found.length == 1 ? '' : 's'} from '
                  'three months ago to a year ahead.',
          style: const TextStyle(fontSize: T.fsLabel, color: T.text),
        ),
        for (final i in next)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '${_when(i)}  ${i.event.summary}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
            ),
          ),
      ],
    );
  }
}

class _SubscriptionList extends StatelessWidget {
  const _SubscriptionList({required this.state, required this.layout});

  final AppState state;
  final Layout layout;

  @override
  Widget build(BuildContext context) {
    final touch = layout.touch;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => FormSheet(
        accent: T.accent,
        layout: layout,
        title: 'Subscriptions',
        onClose: () => Navigator.pop(context),
        actions: [
          FormSheet.plainButton(
            touch: touch,
            icon: Icons.refresh_rounded,
            label: 'Refresh all',
            onTap: () => state.refreshFeeds(force: true),
          ),
          FormSheet.saveButton(
            touch: touch,
            accent: T.accent,
            label: 'Subscribe…',
            onTap: () => showSubscribeForm(context, state),
          ),
        ],
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.feeds.isEmpty)
                const _Label('Nothing subscribed yet.'),
              for (final f in state.feeds) _FeedTile(state: state, feed: f),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedTile extends StatelessWidget {
  const _FeedTile({required this.state, required this.feed});

  final AppState state;
  final CalendarFeed feed;

  @override
  Widget build(BuildContext context) {
    final calendar = state.calendarsByUuid[feed.calendarUuid];
    final status = state.feedStatus[feed.uuid] ?? const FeedStatus();
    final line = describeFeedStatus(
      status,
      refreshing: state.isRefreshingFeed(feed.uuid),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(T.radius),
      onTap: () => showSubscribeForm(context, state, existing: feed),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: T.s2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(Icons.circle,
                  size: 9,
                  color: calendar == null
                      ? T.muted
                      : state.calendarColor(calendar)),
            ),
            const SizedBox(width: T.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(feed.name,
                      style: const TextStyle(
                          fontSize: T.fsLabel, color: T.text)),
                  if (calendar != null &&
                      state.calendarName(calendar) != feed.name)
                    Text('into ${state.calendarName(calendar)}',
                        style: const TextStyle(
                            fontSize: T.fsMeta, color: T.muted)),
                  Text(
                    line,
                    style: TextStyle(
                      fontSize: T.fsMeta,
                      color: status.error == null ? T.muted : T.warn,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 16, color: T.muted),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: T.fsMeta,
          color: T.muted,
          fontWeight: T.wMedium,
          letterSpacing: 0.4,
        ),
      );
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.selectable = false});
  final String text;
  final bool selectable;

  static const _style =
      TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.35);

  @override
  Widget build(BuildContext context) => selectable
      ? SelectableText(text, style: _style)
      : Text(text, style: _style);
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? T.text : Colors.transparent,
              width: 2,
            ),
          ),
        ),
      );
}
