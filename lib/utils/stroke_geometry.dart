import 'dart:math' as math;
import 'dart:ui';

import '../models/brush.dart';
import '../models/stroke.dart';

/// Turns a list of sampled points into a fillable outline whose width varies
/// with pressure.
///
/// A plain `Path` + `Paint.strokeWidth` cannot change thickness part-way
/// through a stroke, so a pressure-sensitive brush has to build its own
/// outline: walk the centre line, offset each point along the normal by the
/// local half-width, then walk back along the other side and close the shape.
class StrokeGeometry {
  const StrokeGeometry._();

  /// Minimum distance (logical px) between stored samples. Filtering out
  /// near-duplicate points keeps the outline clean and the stroke list small.
  static const double minSampleDistance = 1.2;

  /// Half-width of the stroke at a given pressure, for a given brush.
  static double halfWidthAt(BrushSettings brush, double pressure) {
    final response = brush.type.pressureWidthResponse;
    // At response = 0 the width is constant; at 1 it scales straight with
    // pressure. The 0.15 floor stops the stroke vanishing completely.
    final scale = (1.0 - response) + response * (0.15 + 0.85 * pressure);
    return (brush.size * scale) / 2.0;
  }

  /// Opacity of the stroke at a given pressure, for a given brush.
  static double opacityAt(BrushSettings brush, double pressure) {
    final response = brush.type.pressureOpacityResponse;
    final scale = (1.0 - response) + response * (0.25 + 0.75 * pressure);
    return (brush.opacity * scale).clamp(0.0, 1.0);
  }

  /// Should this sample be kept, given the previously stored one?
  static bool shouldSample(StrokePoint? previous, Offset candidate) {
    if (previous == null) return true;
    return (candidate - previous.offset).distance >= minSampleDistance;
  }

  /// Builds the filled outline for [stroke].
  ///
  /// Returns an empty path for an empty stroke, and a dot for a single tap so
  /// that tapping the canvas still leaves a mark.
  static Path buildOutline(Stroke stroke) {
    final points = stroke.points;
    final path = Path();
    if (points.isEmpty) return path;

    if (points.length == 1) {
      final p = points.first;
      path.addOval(
        Rect.fromCircle(
          center: p.offset,
          radius: math.max(halfWidthAt(stroke.brush, p.pressure), 0.4),
        ),
      );
      return path;
    }

    final smoothed = _smooth(points);
    final left = <Offset>[];
    final right = <Offset>[];

    for (var i = 0; i < smoothed.length; i++) {
      final point = smoothed[i];
      final direction = _directionAt(smoothed, i);
      final normal = Offset(-direction.dy, direction.dx);
      final halfWidth =
          math.max(halfWidthAt(stroke.brush, point.pressure), 0.35);
      left.add(point.offset + normal * halfWidth);
      right.add(point.offset - normal * halfWidth);
    }

    // Forward along the left edge...
    path.moveTo(left.first.dx, left.first.dy);
    _appendSmoothPolyline(path, left);
    // ...round the tip...
    path.lineTo(right.last.dx, right.last.dy);
    // ...and back along the right edge.
    _appendSmoothPolyline(path, right.reversed.toList(growable: false));
    path.close();
    return path;
  }

  /// Unit direction vector of the centre line at index [i].
  static Offset _directionAt(List<StrokePoint> points, int i) {
    final Offset delta;
    if (i == 0) {
      delta = points[1].offset - points[0].offset;
    } else if (i == points.length - 1) {
      delta = points[i].offset - points[i - 1].offset;
    } else {
      delta = points[i + 1].offset - points[i - 1].offset;
    }
    final length = delta.distance;
    if (length < 0.0001) return const Offset(1, 0);
    return delta / length;
  }

  /// Chaikin-style smoothing pass: softens the jitter that raw touch sampling
  /// introduces without noticeably lagging behind the pointer.
  static List<StrokePoint> _smooth(List<StrokePoint> points) {
    if (points.length < 3) return points;
    final out = <StrokePoint>[points.first];
    for (var i = 1; i < points.length - 1; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final next = points[i + 1];
      out.add(
        StrokePoint(
          Offset(
            (previous.dx + current.dx * 2 + next.dx) / 4,
            (previous.dy + current.dy * 2 + next.dy) / 4,
          ),
          (previous.pressure + current.pressure * 2 + next.pressure) / 4,
          tilt: current.tilt,
        ),
      );
    }
    out.add(points.last);
    return out;
  }

  /// Appends [points] to [path] as quadratic segments through the midpoints,
  /// which reads as a continuous curve rather than a chain of line segments.
  static void _appendSmoothPolyline(Path path, List<Offset> points) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      path.lineTo(points.first.dx, points.first.dy);
      return;
    }
    path.lineTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final mid =
          Offset((current.dx + next.dx) / 2, (current.dy + next.dy) / 2);
      path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
  }
}
