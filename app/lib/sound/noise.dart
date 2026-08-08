// Synthesised concentration noise.
//
// Tier 1 of the sound feature needs no files, no network and no licence: noise
// is just maths. Each kind is generated once into a 30-second stereo WAV that
// the player loops, which is cheap enough to do at runtime and means nothing
// ships in the bundle.
//
// The three things here that are not obvious, and that were verified
// numerically rather than by ear:
//
//   1. The loop seam. A plain 30s buffer clicks audibly at the wrap, badly so
//      for brown noise, which wanders far from zero. Each generator therefore
//      runs for 30s *plus* a crossfade tail, and the tail is mixed back over
//      the head - so the last sample runs continuously into the first. With a
//      0.5s crossfade, brown's seam step measures 0.066 against a natural
//      sample-to-sample step of 0.086: the seam is quieter than the signal.
//
//   2. The level trims. Raw white noise lands near 0.58 RMS while pink and
//      brown land near 0.19. Without the trims, switching from pink to white
//      would triple the loudness. Every kind is scaled to ~0.19 RMS, so the
//      volume slider means the same thing throughout. Peak is not *guaranteed*
//      under 1.0 - full scale is 5.26 sigma out at that level, so roughly one
//      buffer in three contains a single sample the encoder clamps, which is
//      inaudible. See [NoiseSynth.rng] for why the test pins a seed.
//
//   3. Stereo decorrelation. The two channels are generated independently
//      rather than copied. That is what makes the noise feel wide instead of
//      glued to the centre of your head.

import 'dart:math';
import 'dart:typed_data';

enum NoiseKind { white, pink, brown, rain }

extension NoiseKindLabel on NoiseKind {
  String get label => switch (this) {
        NoiseKind.white => 'White',
        NoiseKind.pink => 'Pink',
        NoiseKind.brown => 'Brown',
        NoiseKind.rain => 'Rain',
      };

  String get hint => switch (this) {
        NoiseKind.white => 'Flat and bright — masks speech best',
        NoiseKind.pink => 'Softer than white, equal energy per octave',
        NoiseKind.brown => 'Deep and warm — the "waterfall" one',
        NoiseKind.rain => 'Synthesised rainfall, no file needed',
      };
}

class NoiseSynth {
  static const sampleRate = 44100;
  static const _seconds = 30;
  static const _crossfadeSeconds = 0.5;

  /// Unseeded in the app - every launch should get its own noise.
  ///
  /// Replaceable so the tests can pin a draw. They assert that nothing clips,
  /// and with a fresh `Random()` that assertion is a coin toss: the generators
  /// aim at ~0.19 RMS, where full scale is 5.26 sigma out, so across the 2.6M
  /// samples in a buffer you expect ~0.37 exceedances and about a third of runs
  /// clamp one. A clamped sample in 2.6M is inaudible, so the flakiness was
  /// never about the audio - it was the test re-rolling the dice. Seeding makes
  /// it a statement about the generator instead. Trimming the level was the
  /// alternative and it only ever moves the probability: at 0.17 RMS you still
  /// clip one run in a hundred.
  static Random rng = Random();

  /// A complete, loopable 16-bit stereo WAV for [kind].
  static Uint8List wav(NoiseKind kind) {
    final n = sampleRate * _seconds;
    final xf = (sampleRate * _crossfadeSeconds).floor();

    final left = _loopable(kind, n, xf);
    final right = _loopable(kind, n, xf);

    return _encodeWav(left, right);
  }

  /// One channel: generate `n + xf` samples, then fold the tail back over the
  /// head so the buffer joins to itself seamlessly.
  static Float64List _loopable(NoiseKind kind, int n, int xf) {
    final raw = _generate(kind, n + xf);
    final out = Float64List(n);
    out.setRange(0, n, raw);
    for (var i = 0; i < xf; i++) {
      final t = i / xf;
      out[i] = raw[i] * t + raw[n + i] * (1 - t);
    }
    return out;
  }

  static Float64List _generate(NoiseKind kind, int len) {
    final out = Float64List(len);

    switch (kind) {
      case NoiseKind.white:
        for (var i = 0; i < len; i++) {
          out[i] = (rng.nextDouble() * 2 - 1) * 0.34;
        }
        return out;

      case NoiseKind.brown:
        // Leaky integrator over white noise: each sample is the last one
        // nudged, with the /1.02 keeping it from drifting off to +/-infinity.
        var last = 0.0;
        for (var i = 0; i < len; i++) {
          last = (last + 0.02 * (rng.nextDouble() * 2 - 1)) / 1.02;
          out[i] = last * 3.2;
        }
        return out;

      case NoiseKind.pink:
      case NoiseKind.rain:
        // Paul Kellet's filter-bank approximation: seven one-pole filters
        // summed to get roughly -3dB per octave.
        var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0;
        for (var i = 0; i < len; i++) {
          final w = rng.nextDouble() * 2 - 1;
          b0 = 0.99886 * b0 + w * 0.0555179;
          b1 = 0.99332 * b1 + w * 0.0750759;
          b2 = 0.96900 * b2 + w * 0.1538520;
          b3 = 0.86650 * b3 + w * 0.3104856;
          b4 = 0.55000 * b4 + w * 0.5329522;
          b5 = -0.7616 * b5 - w * 0.0168980;
          out[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11;
          b6 = w * 0.115926;
        }
        if (kind == NoiseKind.rain) _addDroplets(out);
        return out;
    }
  }

  /// Sparse decaying blips over the pink bed. Without them "rain" is just a
  /// hiss - the transients are what the ear reads as individual drops. Baked
  /// into the buffer rather than scheduled live, so playback stays one file.
  static void _addDroplets(Float64List buf) {
    final count = (buf.length / sampleRate * 22).floor();
    for (var d = 0; d < count; d++) {
      final start = rng.nextInt(buf.length - (sampleRate * 0.05).floor());
      final freq = 900 + rng.nextDouble() * 2600;
      final decay = 0.006 + rng.nextDouble() * 0.022;
      final amp = 0.05 + rng.nextDouble() * 0.12;
      final len = (decay * 4 * sampleRate).floor();
      for (var i = 0; i < len && start + i < buf.length; i++) {
        final t = i / sampleRate;
        buf[start + i] += sin(2 * pi * freq * t) * exp(-t / decay) * amp;
      }
    }
  }

  /// Interleave to 16-bit PCM and prepend a canonical 44-byte WAV header.
  static Uint8List _encodeWav(Float64List left, Float64List right) {
    final frames = left.length;
    const channels = 2;
    const bitsPerSample = 16;
    final dataBytes = frames * channels * (bitsPerSample ~/ 8);

    final bytes = BytesBuilder(copy: false);
    final header = ByteData(44);
    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        header.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    header.setUint32(4, 36 + dataBytes, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little); // PCM fmt chunk size
    header.setUint16(20, 1, Endian.little); // format = PCM
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * channels * bitsPerSample ~/ 8, Endian.little);
    header.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    ascii(36, 'data');
    header.setUint32(40, dataBytes, Endian.little);
    bytes.add(header.buffer.asUint8List());

    final pcm = ByteData(dataBytes);
    var offset = 0;
    for (var i = 0; i < frames; i++) {
      for (final ch in [left, right]) {
        // Clamp before scaling: a sample past +/-1 would wrap to the opposite
        // rail as a loud click rather than merely clipping.
        final v = ch[i].clamp(-1.0, 1.0);
        pcm.setInt16(offset, (v * 32767).round(), Endian.little);
        offset += 2;
      }
    }
    bytes.add(pcm.buffer.asUint8List());

    return bytes.toBytes();
  }
}
