// The sound subapp's panel.
//
// A bottom sheet rather than a view in the column, because it has to be usable
// *from focus mode* — you pick a task, then pick something to listen to while
// you do it. It therefore sits above the focus overlay in the stack but stops
// below the title bar, which stays on top so the window remains draggable and
// closable with the sheet open.

import 'package:flutter/material.dart';

import '../sound/noise.dart';
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

  /// Radio needs a second level: pick a genre, then a station from the
  /// directory. Held here rather than in the service — it is where the user has
  /// browsed to, not what is playing.
  RadioGenre? _genre;
  List<Station>? _stations;
  bool _loadingStations = false;
  String? _stationError;

  SoundService get s => widget.sound;

  Future<void> _selectGenre(RadioGenre g) async {
    setState(() {
      _genre = g;
      _stations = null;
      _stationError = null;
      _loadingStations = true;
    });

    final found = await RadioBrowser.byGenre(g.tag);
    if (!mounted || _genre != g) return; // the user moved on while loading

    setState(() {
      _loadingStations = false;
      _stations = found;
      _stationError = found.isEmpty ? 'No stations online for that genre.' : null;
    });
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(T.s3, 0, T.s3, T.s2),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final g in RadioGenre.all)
                GestureDetector(
                  onTap: () => _selectGenre(g),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: T.s2, vertical: T.s1),
                    decoration: BoxDecoration(
                      color: _genre == g
                          ? Color.lerp(T.surface, ws, 0.34)
                          : T.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      g.label,
                      style: TextStyle(
                        fontSize: T.fsMeta,
                        fontWeight: T.wMedium,
                        color: _genre == g ? T.text : T.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _stationList(ws)),
      ],
    );
  }

  Widget _stationList(Color ws) {
    if (_loadingStations) {
      return const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: T.muted),
        ),
      );
    }
    if (_genre == null || _stations == null) {
      return const Center(
        child: Text('Pick a genre.', style: TextStyle(fontSize: T.fsMeta, color: T.muted)),
      );
    }
    if (_stationError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: T.s4),
          child: Text(
            _stationError!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: T.s2),
      children: [
        for (final station in _stations!)
          _Row(
            title: station.name,
            subtitle: station.subtitle,
            active: _isActive(SoundTier.radio, station.uuid),
            accent: ws,
            onTap: () => s.playStation(station),
          ),
      ],
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
  });

  final String title;
  final String? subtitle;
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
                  style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
