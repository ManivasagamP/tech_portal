import 'dart:math' as math;

import 'package:flutter/material.dart';

// Deliberately not read from FeMotion via `context.motion`: this ring builds
// its AnimationController inside initState(), and Theme.of(context) — which
// that accessor wraps — throws if it's reached before the widget has
// finished mounting. FeMotion.progressFill/spring are fixed, app-wide
// constants that never actually vary by theme, so a literal copy here costs
// nothing and sidesteps the whole class of bug.
const _fillDuration = Duration(milliseconds: 1000);
const _springCurve = Cubic(0.16, 1, 0.3, 1);

/// The dashboard/overview completion ring — a gradient donut that sweeps
/// from zero to [value] on first build, matching the reference screens'
/// "goal ring" pattern more directly than a linear percentage bar does.
///
/// [value] is 0-1. A `null` value paints an indeterminate grey ring (data
/// not loaded yet) instead of a misleading full or empty one.
class ProgressRing extends StatefulWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.colors,
    this.size = 96,
    this.strokeWidth = 12,
    this.child,
  });

  final double? value;
  final List<Color> colors;
  final double size;
  final double strokeWidth;
  final Widget? child;

  @override
  State<ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<ProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _sweep;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _fillDuration);
    _sweep = _tween(0);
    _controller.forward();
  }

  Animation<double> _tween(double from) => Tween(
    begin: from,
    end: (widget.value ?? 0).clamp(0.0, 1.0),
  ).animate(CurvedAnimation(parent: _controller, curve: _springCurve));

  @override
  void didUpdateWidget(covariant ProgressRing old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _sweep = _tween(_sweep.value);
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final indeterminate = widget.value == null;
    return AnimatedBuilder(
      animation: _sweep,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _RingPainter(
          fraction: indeterminate ? 0 : _sweep.value,
          colors: indeterminate
              ? const [Color(0xFFE5E7EB), Color(0xFFE5E7EB)]
              : widget.colors,
          strokeWidth: widget.strokeWidth,
          trackColor: const Color(0xFFF3F4F6),
        ),
        child: widget.child == null
            ? null
            : Center(
                child: SizedBox(
                  width: widget.size - widget.strokeWidth * 2.5,
                  height: widget.size - widget.strokeWidth * 2.5,
                  child: Center(child: widget.child),
                ),
              ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.colors,
    required this.strokeWidth,
    required this.trackColor,
  });

  final double fraction;
  final List<Color> colors;
  final double strokeWidth;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);

    if (fraction <= 0) return;

    final sweep = 2 * math.pi * fraction;
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      // The gradient's own angle-0 is 3 o'clock, but the arc starts drawing
      // at 12 o'clock (-90°) below, so the shader is rotated to match —
      // otherwise the colour stop that should sit at the arc's start paints
      // at its side instead.
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: sweep == 0 ? 0.001 : sweep,
        colors: colors,
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, progress);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fraction != fraction || old.colors != colors;
}
