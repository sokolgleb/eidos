import 'package:flutter/material.dart';

class Stroke {
  final List<Offset> points;
  final Color color;
  final double size;
  final double thinning;
  final double smoothing;

  const Stroke({
    required this.points,
    required this.color,
    required this.size,
    required this.thinning,
    required this.smoothing,
  });

  Stroke copyWith({List<Offset>? points}) {
    return Stroke(
      points: points ?? this.points,
      color: color,
      size: size,
      thinning: thinning,
      smoothing: smoothing,
    );
  }
}
