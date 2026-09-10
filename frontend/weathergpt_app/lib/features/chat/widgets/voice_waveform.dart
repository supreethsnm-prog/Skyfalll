import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A live audio meter driven by the microphone's real amplitude — not a
/// decorative animation. Each of [_barCount] bars tracks one point in a
/// rolling window of recent loudness, newest sample entering from the
/// right and everything else shifting left, so the whole shape visibly
/// flows as the user speaks rather than just twitching in place.
///
/// Two things make this read as continuous motion instead of a value
/// jumping every sample:
/// - the rolling shift-and-append buffer (a scrolling window, not N
///   independent trackers each snapping to their own latest sample)
/// - a per-frame [Ticker] that exponentially smooths every bar toward its
///   current target rather than redrawing only on the ~80ms sample tick
///   (`voiceAmplitudeInterval`) — sampling that infrequently would
///   otherwise look like a strobe, not a waveform.
class VoiceWaveform extends StatefulWidget {
  const VoiceWaveform({
    super.key,
    required this.amplitude,
    this.color = const Color(0xFF3A83F6),
    this.height = 32,
  });

  final Stream<double> amplitude;
  final Color color;
  final double height;

  @override
  State<VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<VoiceWaveform>
    with SingleTickerProviderStateMixin {
  static const _barCount = 28;

  /// Bars never fully flatten to zero — a dead-flat line while actively
  /// recording reads as "the mic broke", not "it's quiet".
  static const _restingLevel = 0.06;

  late final List<double> _levels;
  late final List<double> _targets;
  late final Ticker _ticker;
  StreamSubscription<double>? _subscription;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _levels = List.filled(_barCount, _restingLevel);
    _targets = List.filled(_barCount, _restingLevel);
    _subscription = widget.amplitude.listen(_onAmplitude);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(VoiceWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.amplitude != widget.amplitude) {
      _subscription?.cancel();
      _subscription = widget.amplitude.listen(_onAmplitude);
    }
  }

  void _onAmplitude(double dBFS) {
    final normalized = _normalize(dBFS);
    // Shift the window left, push the new sample in on the right — this
    // is the "scrolling" part of the motion.
    for (var i = 0; i < _targets.length - 1; i++) {
      _targets[i] = _targets[i + 1];
    }
    _targets[_targets.length - 1] = normalized;
  }

  /// BHASHINI/`record` report dBFS, which on mobile mics is effectively
  /// silence below about -50 and full-scale at 0. Speech at a normal
  /// conversational distance sits well inside that band, so this range
  /// (not a wider "textbook" dBFS range) is what actually produces
  /// visible bar movement for a real voice rather than a flat line.
  static double _normalize(double dBFS) {
    const floor = -50.0;
    const ceiling = 0.0;
    final t = ((dBFS - floor) / (ceiling - floor)).clamp(0.0, 1.0);
    return _restingLevel + t * (1.0 - _restingLevel);
  }

  void _onTick(Duration elapsed) {
    final dtSeconds =
        _lastTick == Duration.zero ? 0.0 : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dtSeconds <= 0) return;

    // Exponential smoothing toward each bar's current target. Higher =
    // the bar catches up to a loud/quiet moment faster; tuned so a full
    // swing takes a few frames rather than either snapping instantly
    // (looks jittery) or lagging noticeably behind the actual sound.
    const smoothingRate = 14.0;
    final factor = 1 - math.exp(-smoothingRate * dtSeconds);

    var anyChanged = false;
    for (var i = 0; i < _levels.length; i++) {
      final diff = _targets[i] - _levels[i];
      if (diff.abs() > 0.002) {
        _levels[i] += diff * factor;
        anyChanged = true;
      }
    }
    if (anyChanged && mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: CustomPaint(
        painter: _WaveformPainter(levels: List.of(_levels), color: widget.color),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.levels, required this.color});

  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty || size.width <= 0) return;

    final slot = size.width / levels.length;
    // Bars at 60% of their slot width, leaving visible gaps — a soft bar
    // shape reads as a waveform; touching bars read as a solid block.
    final barWidth = slot * 0.6;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    final centerY = size.height / 2;
    for (var i = 0; i < levels.length; i++) {
      final x = slot * i + slot / 2;
      final barHeight = levels[i].clamp(0.0, 1.0) * size.height;
      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  // A fresh, independent list is passed in on every build (see build()
  // above), so identity comparison alone would always say "changed" —
  // which is exactly right here: this painter only exists while actively
  // ticking, so repainting on every delivered frame is the correct
  // behaviour, not a missed optimization.
  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => true;
}
