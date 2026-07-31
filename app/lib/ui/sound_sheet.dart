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
            top: Radius.circular(12),
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
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 2),
      child: Row(
        children: [
          const Text(
            'Sound',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: T.muted,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: widget.onClose,
            borderRadius: BorderRadius.circular(7),
            child: const Padding(
              padding: EdgeInsets.all(6),
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
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: active ? Color.lerp(T.surface, ws, 0.30) : T.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: active ? T.text : T.muted,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
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
      padding: const EdgeInsets.symmetric(horizontal: 10),
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
      padding: const EdgeInsets.symmetric(horizontal: 10),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            'Public-domain field recordings from the Internet Archive. '
            'Tap again for a different one.',
            style: TextStyle(fontSize: 10.5, color: T.muted, height: 1.35),
          ),
        ),
        for (final preset in AmbiencePreset.all)
          _Row(
            title: preset.label,
            active: _isActive(SoundTier.ambience, preset.id),
            accent: ws,
            onTap: () => s.playAmbience(preset),
          ),
      ],
    );
  }

  Widget _radioList(Color ws) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final g in RadioGenre.all)
                GestureDetector(
                  onTap: () => _selectGenre(g),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _genre == g
                          ? Color.lerp(T.surface, ws, 0.34)
                          : T.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      g.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
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
        child: Text('Pick a genre.', style: TextStyle(fontSize: 11.5, color: T.muted)),
      );
    }
    if (_stationError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _stationError!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, color: T.muted),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 10),
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
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 10),
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
              style: const TextStyle(fontSize: 11, color: T.muted),
            ),
          ),
          if (s.isPlaying)
            Tooltip(
              message: 'Stop',
              child: InkWell(
                onTap: s.stop,
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(4),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.20) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
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
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: T.text,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  subtitle!,
                  style: const TextStyle(fontSize: 10.5, color: T.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
