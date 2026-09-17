// The sound subapp's panel.
//
// A bottom sheet rather than a view in the column, because it has to be usable
// *from focus mode* — you pick a task, then pick something to listen to while
// you do it. It therefore sits above the focus overlay in the stack but stops
// below the title bar, which stays on top so the window remains draggable and
// closable with the sheet open.

import 'package:flutter/material.dart';

import '../sound/noise.dart';
import '../sound/radio_library.dart';
import '../sound/sound_service.dart';
import '../sound/sources.dart';
import '../theme.dart';
import 'title_bar.dart';

class SoundSheet extends StatefulWidget {
  const SoundSheet({
    super.key,
    required this.sound,
    required this.accent,
    required this.onClose,
  });

  final SoundService sound;
  final Color accent;
  final VoidCallback onClose;

  @override
  State<SoundSheet> createState() => _SoundSheetState();
}

class _SoundSheetState extends State<SoundSheet> {
  SoundTier _tab = SoundTier.noise;

  /// Radio needs a second level: something to browse - the saved stations, a
  /// genre, or a search - and then a station from it. Held here rather than in
  /// the service: it is where the user has browsed to, not what is playing.
  ///
  /// Saved is where the tab opens when anything is saved. Somebody who has
  /// starred three stations came back for one of those three, and making them
  /// pick a genre to find it again is what starring was meant to spare them.
  late _Browse _browse =
      s.radio.saved.isEmpty ? const _Browse.none() : const _Browse.saved();
  List<Station>? _stations;
  bool _loadingStations = false;
  String? _stationError;

  final _searchController = TextEditingController();

  SoundService get s => widget.sound;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _selectGenre(RadioGenre g) =>
      _load(_Browse.genre(g), () => RadioBrowser.byGenre(g.tag),
          'No stations online for that genre.');

  Future<void> _search(String query) {
    final q = query.trim();
    if (q.isEmpty) return Future.value();
    return _load(_Browse.search(q), () => RadioBrowser.search(q),
        'Nothing in the directory called "$q".');
  }

  void _showSaved() => setState(() {
        _browse = const _Browse.saved();
        _loadingStations = false;
        _stationError = null;
        _stations = null;
      });

  Future<void> _load(
    _Browse browse,
    Future<List<Station>> Function() fetch,
    String emptyMessage,
  ) async {
    setState(() {
      _browse = browse;
      _stations = null;
      _stationError = null;
      _loadingStations = true;
    });

    final found = await fetch();
    if (!mounted || _browse != browse) return; // the user moved on while loading

    setState(() {
      _loadingStations = false;
      _stations = found;
      _stationError = found.isEmpty ? emptyMessage : null;
    });
  }

  /// A stream the directory does not have - a local station's own URL, an
  /// internal Icecast. Name optional: the host stands in for one.
  Future<void> _addCustom() async {
    final name = TextEditingController();
    final url = TextEditingController();
    String? error;
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) {
          Future<void> submit() async {
            final station = await s.radio.addCustom(name.text, url.text);
            if (!context.mounted) return;
            if (station == null) {
              setDialog(() => error = 'That does not look like a stream URL.');
              return;
            }
            Navigator.pop(context, true);
          }

          return AlertDialog(
            backgroundColor: T.bgSolid,
            title: const Text('Add a stream',
                style: TextStyle(fontSize: T.fsMenu)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: url,
                  autofocus: true,
                  style: const TextStyle(fontSize: T.fsLabel),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'https://…/stream.mp3',
                    labelText: 'Stream URL',
                  ),
                  onSubmitted: (_) => submit(),
                ),
                const SizedBox(height: T.s2),
                TextField(
                  controller: name,
                  style: const TextStyle(fontSize: T.fsLabel),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Name (optional)',
                  ),
                  onSubmitted: (_) => submit(),
                ),
                if (error != null) ...[
                  const SizedBox(height: T.s2),
                  Text(error!,
                      style:
                          const TextStyle(fontSize: T.fsMeta, color: T.danger)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: submit, child: const Text('Add')),
            ],
          );
        },
      ),
    );
    name.dispose();
    url.dispose();
    if (added == true && mounted) _showSaved();
  }

  @override
  Widget build(BuildContext context) {
    final ws = widget.accent;

    return Positioned(
      top: TitleBar.height,
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Color.lerp(T.bgSolid, ws, 0.14),
          border: Border(top: BorderSide(color: ws.withValues(alpha: 0.35))),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(T.radius),
            bottom: Radius.circular(T.radius),
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x73000000), blurRadius: 30, offset: Offset(0, -10)),
          ],
        ),
        child: Column(
          children: [
            _head(),
            _tabs(ws),
            Expanded(child: _body(ws)),
            _transport(ws),
          ],
        ),
      ),
    );
  }

  Widget _head() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s3, T.s2, T.s2, 2),
      child: Row(
        children: [
          const Text(
            'Sound',
            style: TextStyle(
              fontSize: T.fsLabel,
              fontWeight: T.wMedium,
              color: T.muted,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: widget.onClose,
            borderRadius: BorderRadius.circular(T.radius),
            child: const Padding(
              padding: EdgeInsets.all(T.s2),
              child: Icon(Icons.close, size: 15, color: T.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabs(Color ws) {
    Widget tab(SoundTier tier, String label) {
      final active = _tab == tier;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = tier),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(vertical: T.s2),
            decoration: BoxDecoration(
              color: active ? Color.lerp(T.surface, ws, 0.30) : T.surface,
              borderRadius: BorderRadius.circular(T.radius),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: T.fsMeta,
                fontWeight: T.wMedium,
                color: active ? T.text : T.muted,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s2, 2, T.s2, T.s2),
      child: Row(
        children: [
          tab(SoundTier.noise, 'Noise'),
          tab(SoundTier.ambience, 'Ambience'),
          tab(SoundTier.radio, 'Radio'),
        ],
      ),
    );
  }

  Widget _body(Color ws) {
    return switch (_tab) {
      SoundTier.noise => _noiseList(ws),
      SoundTier.ambience => _ambienceList(ws),
      SoundTier.radio => _radioList(ws),
    };
  }

  bool _isActive(SoundTier tier, String id) =>
      s.now?.tier == tier && s.now?.id == id;

  Widget _noiseList(Color ws) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: T.s2),
      children: [
        for (final kind in NoiseKind.values)
          _Row(
            title: kind.label,
            subtitle: kind.hint,
            active: _isActive(SoundTier.noise, kind.name),
            accent: ws,
            onTap: () => s.playNoise(kind),
          ),
      ],
    );
  }

  Widget _ambienceList(Color ws) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: T.s2),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(T.s1, 0, T.s1, T.s2),
          child: Text(
            'Public-domain field recordings from the Internet Archive. '
            'Tap again for a different one.',
            style: TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.35),
          ),
        ),
        for (final preset in AmbiencePreset.all)
          _Row(
            title: preset.label,
            subtitle: _cachedHint(preset),
            active: _isActive(SoundTier.ambience, preset.id),
            accent: ws,
            onTap: () => s.playAmbience(preset),
          ),
        _keptOnDevice(ws),
      ],
    );
  }

  /// "on this device" under a preset that has a bout stored, and nothing under
  /// one that does not. A count would be noise: what matters to whoever is
  /// choosing is whether this one starts instantly.
  String? _cachedHint(AmbiencePreset preset) {
    if (!s.keepAmbience) return null;
    final cache = s.ambience;
    if (cache == null || cache.countFor(preset.id) == 0) return null;
    return 'on this device';
  }

  /// What the cache is costing, and the two ways out of it. Below the presets
  /// rather than above them: it is about the tier, not a way into it.
  Widget _keptOnDevice(Color ws) {
    final cache = s.ambience;
    final mb = ((cache?.bytes ?? 0) / (1024 * 1024)).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s1, T.s3, T.s1, T.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Keep 30 minutes on this device',
                  style: TextStyle(
                    fontSize: T.fsLabel,
                    color: cache == null ? T.muted : T.text,
                  ),
                ),
              ),
              Switch(
                value: s.keepAmbience && cache != null,
                onChanged:
                    cache == null ? null : (on) => s.setKeepAmbience(on),
                activeThumbColor: ws,
              ),
            ],
          ),
          Text(
            cache == null
                ? 'Not available on this device.'
                : 'The first play of a preset streams and is stored behind '
                    'itself; after that it starts instantly and needs no '
                    'network.',
            style: const TextStyle(
              fontSize: T.fsMeta,
              color: T.muted,
              height: 1.35,
            ),
          ),
          if (cache != null && cache.bouts.isNotEmpty) ...[
            const SizedBox(height: T.s1),
            Row(
              children: [
                Text(
                  '${cache.bouts.length} stored, about $mb MB',
                  style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
                ),
                const SizedBox(width: T.s2),
                TextButton(
                  onPressed: _confirmClear,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: T.s1),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Clear',
                    style: TextStyle(fontSize: T.fsMeta, color: T.danger),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Asked first: this is minutes of downloading and there is no undo. A
  /// dialog rather than a sheet - modal by nature and gone in seconds, which is
  /// the case the sheet rule in main.dart carves out.
  Future<void> _confirmClear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: T.bgSolid,
        title: const Text(
          'Clear stored sound?',
          style: TextStyle(fontSize: T.fsMenu),
        ),
        content: const Text(
          'The recordings will be downloaded again the next time you play '
          'them.',
          style: TextStyle(fontSize: T.fsLabel, color: T.muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (yes == true) await s.clearAmbience();
  }

  Widget _radioList(Color ws) {
    Widget chip(String label, bool active, VoidCallback onTap) =>
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: T.s2, vertical: T.s1),
            decoration: BoxDecoration(
              color: active ? Color.lerp(T.surface, ws, 0.34) : T.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: T.fsMeta,
                fontWeight: T.wMedium,
                color: active ? T.text : T.muted,
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(T.s3, 0, T.s3, T.s2),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(fontSize: T.fsLabel),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search stations by name…',
              filled: true,
              fillColor: T.surface,
              prefixIcon:
                  const Icon(Icons.search_rounded, size: 15, color: T.muted),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 30, minHeight: 28),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: T.s2, vertical: T.s2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(T.radius),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: _search,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(T.s3, 0, T.s3, T.s2),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              chip('★ Saved', _browse.kind == _BrowseKind.saved, _showSaved),
              for (final g in RadioGenre.all)
                chip(g.label, _browse.genre == g, () => _selectGenre(g)),
            ],
          ),
        ),
        Expanded(child: _stationList(ws)),
      ],
    );
  }

  Widget _stationList(Color ws) {
    Widget message(String text) => Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: T.s4),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
            ),
          ),
        );

    if (_browse.kind == _BrowseKind.saved) return _savedList(ws);

    if (_loadingStations) {
      return const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: T.muted),
        ),
      );
    }
    if (_browse.kind == _BrowseKind.none || _stations == null) {
      return message('Pick a genre, or search.');
    }
    if (_stationError != null) return message(_stationError!);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: T.s2),
      children: [
        for (final station in _stations!) _stationRow(station, ws),
      ],
    );
  }

  Widget _savedList(Color ws) {
    final saved = s.radio.saved;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: T.s2),
      children: [
        if (saved.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(T.s1, T.s2, T.s1, T.s2),
            child: Text(
              'Nothing saved yet. Star a station from a genre or a search, '
              'or add a stream the directory does not have.',
              style: TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.35),
            ),
          ),
        for (final station in saved) _stationRow(station, ws),
        _Row(
          title: '+ Add a stream URL',
          active: false,
          accent: ws,
          onTap: _addCustom,
        ),
      ],
    );
  }

  /// A station, with the way to keep it - or, for one added by hand, the way
  /// to get rid of it. A custom stream has no star: it is only in the list
  /// because it was saved, so unstarring it and deleting it are the same act.
  Widget _stationRow(Station station, Color ws) {
    final custom = s.radio.isCustom(station);
    final starred = !custom && s.radio.isFavourite(station);
    return _Row(
      title: station.name,
      subtitle: custom ? station.url : station.subtitle,
      active: _isActive(SoundTier.radio, RadioLibrary.keyOf(station)),
      accent: ws,
      onTap: () => s.playStation(station),
      trailing: Tooltip(
        message: custom
            ? 'Remove this stream'
            : starred
                ? 'Remove from saved'
                : 'Save this station',
        child: InkWell(
          onTap: () => custom
              ? s.radio.removeCustom(station)
              : s.radio.toggleFavourite(station),
          borderRadius: BorderRadius.circular(T.radius),
          child: Padding(
            padding: const EdgeInsets.all(T.s1),
            child: Icon(
              custom
                  ? Icons.close_rounded
                  : starred
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
              size: 16,
              color: starred ? ws : T.muted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _transport(Color ws) {
    return Container(
      padding: const EdgeInsets.fromLTRB(T.s3, T.s2, T.s2, T.s2),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              s.transportLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
            ),
          ),
          if (s.isPlaying)
            Tooltip(
              message: 'Stop',
              child: InkWell(
                onTap: s.stop,
                borderRadius: BorderRadius.circular(T.radius),
                child: const Padding(
                  padding: EdgeInsets.all(T.s1),
                  child: Icon(Icons.stop_rounded, size: 16, color: T.text),
                ),
              ),
            ),
          SizedBox(
            width: 92,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                activeTrackColor: ws,
                inactiveTrackColor: T.surfaceHover,
                thumbColor: ws,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: s.volume,
                onChanged: s.setVolume,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.active,
    required this.accent,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: T.s2, vertical: T.s2),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.20) : Colors.transparent,
          borderRadius: BorderRadius.circular(T.radius),
          border: Border(
            left: BorderSide(
              color: active ? accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: T.fsLabel,
                      fontWeight: T.wMedium,
                      color: T.text,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: T.fsMeta, color: T.muted),
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

enum _BrowseKind { none, saved, genre, search }

/// What the radio tab is showing. A value, so a slow lookup can check it is
/// still the one being waited for before it lands.
@immutable
class _Browse {
  const _Browse.none()
      : kind = _BrowseKind.none,
        genre = null,
        query = null;
  const _Browse.saved()
      : kind = _BrowseKind.saved,
        genre = null,
        query = null;
  const _Browse.genre(RadioGenre this.genre)
      : kind = _BrowseKind.genre,
        query = null;
  const _Browse.search(String this.query)
      : kind = _BrowseKind.search,
        genre = null;

  final _BrowseKind kind;
  final RadioGenre? genre;
  final String? query;

  @override
  bool operator ==(Object other) =>
      other is _Browse &&
      other.kind == kind &&
      other.genre == genre &&
      other.query == query;

  @override
  int get hashCode => Object.hash(kind, genre, query);
}
