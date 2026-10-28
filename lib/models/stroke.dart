import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'brush.dart';

/// A single sampled point along a stroke.
///
/// [pressure] is already normalised to 0..1 by [PressureNormaliser] so the
/// renderer never has to care which input device produced the event.
@immutable
class StrokePoint {
  const StrokePoint(this.offset, this.pressure, {this.tilt = 0.0});

  final Offset offset;
  final double pressure;

  /// Stylus tilt in radians (0 = perpendicular). Reserved for future brush
  /// shapes; captured now so the data is there when it is needed.
  final double tilt;

  double get dx => offset.dx;
  double get dy => offset.dy;

  StrokePoint lerpTo(StrokePoint other, double t) => StrokePoint(
        Offset.lerp(offset, other.offset, t)!,
        pressure + (other.pressure - pressure) * t,
        tilt: tilt + (other.tilt - tilt) * t,
      );
}

/// One continuous mark made by the user, from pointer-down to pointer-up.
///
/// Strokes are vectors - centre-line points with pressure and tilt, not
/// pixels - so they can be moved, scaled, rotated and recoloured after the
/// fact without losing quality.
class Stroke {
  Stroke({required this.brush, List<StrokePoint>? points})
      : points = points ?? <StrokePoint>[];

  /// Mutable so a selection can be recoloured or scaled in place.
  BrushSettings brush;
  final List<StrokePoint> points;

  bool get isEraser => brush.type.isEraser;
  bool get isEmpty => points.isEmpty;

  void add(StrokePoint point) => points.add(point);

  /// Bounding box, padded by the widest possible half-width of the stroke.
  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    var minX = points.first.dx;
    var maxX = points.first.dx;
    var minY = points.first.dy;
    var maxY = points.first.dy;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final pad = brush.size;
    return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
  }

  Stroke copy() => Stroke(brush: brush, points: List<StrokePoint>.of(points));

  /// Applies [transform] to every point in place. [sizeScale] scales the
  /// brush with it, so a resized drawing keeps its proportions.
  void transformBy(Offset Function(Offset) transform, {double sizeScale = 1}) {
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      points[i] = StrokePoint(transform(p.offset), p.pressure, tilt: p.tilt);
    }
    if (sizeScale != 1) {
      brush = brush.copyWith(size: (brush.size * sizeScale).clamp(0.3, 400.0));
    }
  }
}
