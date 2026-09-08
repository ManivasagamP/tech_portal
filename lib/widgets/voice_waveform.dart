import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:record/record.dart';

/// Live bar-style waveform driven by the recorder's amplitude stream — the
/// same visual language as a voice-message recorder, so a technician can see
/// at a glance that the mic is actually picking up sound rather than reading
/// a static "Recording…" label and wondering if it hung.
class VoiceWaveform extends StatefulWidget {
  const VoiceWaveform({
    super.key,
    required this.amplitudeStream,
    required this.color,
    this.barCount = 32,
    this.height = 28,
  });

  final Stream<Amplitude> amplitudeStream;
  final Color color;
  final int barCount;
  final double height;

  @override
  State<VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<VoiceWaveform> {
  // `List.filled` alone is fixed-length — `removeAt` below would throw on
  // every tick, silently, since it happens inside setState before the
  // rebuild is scheduled. `growable: true` is what makes this a real queue.
  late final List<double> _levels = List.filled(
    widget.barCount,
    0.06,
    growable: true,
  );
  StreamSubscription<Amplitude>? _sub;

  /// A recent-loudness ceiling, not an all-time peak — measured on-device,
  /// ordinary speech swings a good 20-25dB from syllable to syllable and a
  /// short pause can sit 25dB+ below the loudest word said a second earlier
  /// (e.g. -27dB right after a peak of -1dB, confirmed on-device). A peak
  /// that only ever climbed would freeze the scale at that one loud moment
  /// and flatline everything quieter for the rest of the recording — this
  /// decays back down during quiet stretches so the scale keeps re-centering
  /// on how loud things actually are *right now*.
  double _peak = -35;

  @override
  void initState() {
    super.initState();
    _sub = widget.amplitudeStream.listen(_onAmplitude);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onAmplitude(Amplitude amplitude) {
    // Chase a new peak instantly, but only give one back gradually — about
    // 8dB/second, so the ceiling forgets a shout within a couple of seconds
    // instead of pinning the scale there for the rest of the recording.
    _peak = math.max(amplitude.current, _peak - 0.8);
    final floor = _peak - 24;
    final level = ((amplitude.current - floor) / (_peak - floor)).clamp(
      0.0,
      1.0,
    );
    if (!mounted) return;
    setState(() {
      _levels.removeAt(0);
      _levels.add(math.max(level, 0.06));
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final level in _levels)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOut,
                height: (widget.height * level).clamp(3.0, widget.height),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
