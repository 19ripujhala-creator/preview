import 'package:flutter/material.dart';

class NicDownloadIndicator extends StatelessWidget {
  final double size;
  final double progress; // 0.0 to 1.0 (Clockwise fill)
  final Color color;
  final Color? trackColor;

  const NicDownloadIndicator({
    super.key,
    this.size = 17.0,
    required this.progress,
    this.color = const Color(0xFF007AFF), // Official Apple Blue
    this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: progress.clamp(0.0, 1.0).toDouble()),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _IosProgressRingPainter(
              progress: animatedValue,
              color: color,
              trackColor: trackColor ?? color.withValues(alpha: 0.18),
            ),
          ),
        );
      },
    );
  }
}

class _IosProgressRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _IosProgressRingPainter({required this.progress, required this.color, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = size.width * 0.125;
    final radius = (size.width - strokeWidth) / 2;

    // 1. Faint Outer Full Track Ring
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    // 2. Real Clockwise Progress Arc (Starts exactly at 12 o'clock)
    if (progress > 0.02) {
      final progressPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth;

      const double startAngle = -1.5707963267948966; // -pi / 2 (Top 12 o'clock)
      final double sweepAngle = progress * 6.283185307179586; // progress * 2 * pi

      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, progressPaint);
    }

    // 3. Static Center iOS Downward Download Arrow
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth * 0.95;

    final arrowTop = center.dy - (size.height * 0.20);
    final arrowBottom = center.dy + (size.height * 0.20);
    final wingSpanX = size.width * 0.16;
    final wingSpanY = size.height * 0.14;

    final arrowPath = Path();
    arrowPath.moveTo(center.dx, arrowTop);
    arrowPath.lineTo(center.dx, arrowBottom);

    arrowPath.moveTo(center.dx - wingSpanX, arrowBottom - wingSpanY);
    arrowPath.lineTo(center.dx, arrowBottom);
    arrowPath.lineTo(center.dx + wingSpanX, arrowBottom - wingSpanY);

    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _IosProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color || oldDelegate.trackColor != trackColor;
  }
}

