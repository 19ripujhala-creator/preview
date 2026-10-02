// lib/tabs/student/modules/student_attendance/widgets/luxury_card_mesh.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Ultra-smooth, GPU-optimized Luxury Mesh Painter (Zero Shader Crashes)
class LuxuryCardWaveMeshPainter extends CustomPainter {
  final Color dotColor;
  LuxuryCardWaveMeshPainter({required this.dotColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dotColor.withOpacity(0.09)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Elegant Luxury Geometric Waves
    final double w = size.width;
    final double h = size.height;

    for (int i = 0; i < 6; i++) {
      final double offset = i * 14.0;
      final path = Path();
      path.moveTo(w * 0.40 + offset, 0);
      path.cubicTo(
        w * 0.70 + offset,
        h * 0.20,
        w * 0.50 + offset,
        h * 0.80,
        w * 0.85 + offset,
        h,
      );
      canvas.drawPath(path, paint);
    }

    // Luxury Accent Ambient Glow
    final glowPaint = Paint()
      ..color = dotColor.withOpacity(0.04)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.88, h * 0.38), 52, glowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Reusable Press Scale Touch Feedback
class ScaleTouch extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const ScaleTouch({super.key, required this.child, required this.onTap});

  @override
  State<ScaleTouch> createState() => _ScaleTouchState();
}

class _ScaleTouchState extends State<ScaleTouch> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}