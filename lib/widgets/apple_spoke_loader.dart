import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Fixed radial spokes with a travelling fade, shared by login and Sync Now.
class AppleSpokeLoader extends StatefulWidget {
  final double size;
  final Color color;
  const AppleSpokeLoader({super.key, this.size = 24, this.color = const Color(0xFF737373)});

  @override
  State<AppleSpokeLoader> createState() => _AppleSpokeLoaderState();
}

class _AppleSpokeLoaderState extends State<AppleSpokeLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1000),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    child: SizedBox.square(dimension: widget.size,
      child: RepaintBoundary(child: CustomPaint(
        painter: _SpokePainter(_controller, widget.color),
      )),
    ),
  );
}

class _SpokePainter extends CustomPainter {
  final Animation<double> phase;
  final Color color;
  _SpokePainter(this.phase, this.color) : super(repaint: phase);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final paint = Paint()..strokeWidth = radius * 0.15..strokeCap = StrokeCap.round;
    for (var index = 0; index < 12; index++) {
      final angle = index * math.pi / 6 - math.pi / 2;
      // A periodic cosine fade avoids a brightness jump at the repeat boundary.
      final wave = (1 + math.cos((index / 12 - phase.value) * math.pi * 2)) / 2;
      final opacity = 0.18 + 0.82 * math.pow(wave, 3).toDouble();
      paint.color = color.withValues(alpha: color.a * opacity);
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(center + direction * (radius * 0.48),
        center + direction * (radius * 0.88), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpokePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.phase != phase;
}
