import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import '../models/stroke.dart';

class DrawingCanvas extends StatelessWidget {
  final List<Stroke> strokes;
  final Stroke? currentStroke;

  const DrawingCanvas({
    super.key,
    required this.strokes,
    this.currentStroke,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StrokePainter(
        strokes: strokes,
        currentStroke: currentStroke,
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  final List<Stroke> strokes;
  final Stroke? currentStroke;

  _StrokePainter({required this.strokes, this.currentStroke});

  @override
  void paint(Canvas canvas, Size size) {
    final all = [...strokes, ?currentStroke];
    for (final stroke in all) {
      _drawStroke(canvas, stroke);
    }
  }

  void _drawStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.isEmpty) return;

    final points = stroke.points
        .map((p) => PointVector(p.dx, p.dy))
        .toList();

    final outlinePoints = getStroke(
      points,
      options: StrokeOptions(
        size: stroke.size,
        thinning: stroke.thinning,
        smoothing: stroke.smoothing,
        streamline: 0.5,
        simulatePressure: true,
      ),
    );

    if (outlinePoints.isEmpty) return;

    final path = Path();
    path.moveTo(outlinePoints[0].dx, outlinePoints[0].dy);
    for (int i = 1; i < outlinePoints.length - 1; i++) {
      final mid = Offset(
        (outlinePoints[i].dx + outlinePoints[i + 1].dx) / 2,
        (outlinePoints[i].dy + outlinePoints[i + 1].dy) / 2,
      );
      path.quadraticBezierTo(
        outlinePoints[i].dx,
        outlinePoints[i].dy,
        mid.dx,
        mid.dy,
      );
    }
    path.close();

    final paint = Paint()
      ..color = stroke.color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_StrokePainter old) =>
      old.strokes.length != strokes.length ||
      old.currentStroke != currentStroke;
}
