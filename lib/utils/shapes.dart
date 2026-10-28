import 'dart:math' as math;
import 'dart:ui';

import '../models/stroke.dart';

/// The clean shapes the shape tool draws and hold-to-snap recognises.
enum ShapeKind {
  line('Line'),
  rectangle('Rectangle'),
  ellipse('Ellipse');

  const ShapeKind(this.label);
  final String label;
}

/// Shapes are stored as ordinary strokes - densely sampled points with
/// pressure - so they render with any brush, erase, save and transform
/// exactly like freehand marks.
class Shapes {
  const Shapes._();

  /// Points for [kind] spanning [from] -> [to] (the drag of the shape tool).
  static List<StrokePoint> build(
    ShapeKind kind,
    Offset from,
    Offset to, {
    double pressure = 0.6,
  }) {
    switch (kind) {
      case ShapeKind.line:
        return _polyline(<Offset>[from, to], pressure, closed: false);
      case ShapeKind.rectangle:
        final r = Rect.fromPoints(from, to);
        return _polyline(
          <Offset>[r.topLeft, r.topRight, r.bottomRight, r.bottomLeft],
          pressure,
          closed: true,
        );
      case ShapeKind.ellipse:
        return ellipse(Rect.fromPoints(from, to), pressure);
    }
  }

  static List<StrokePoint> ellipse(Rect box, double pressure,
      {double rotation = 0}) {
    final steps = math.max(
      24,
      (math.pi * (box.width + box.height) / 2 / 4).round(),
    );
    final c = box.center;
    final cosR = math.cos(rotation);
    final sinR = math.sin(rotation);
    return <StrokePoint>[
      for (var i = 0; i <= steps; i++)
        () {
          final a = i / steps * math.pi * 2;
          final x = math.cos(a) * box.width / 2;
          final y = math.sin(a) * box.height / 2;
          return StrokePoint(
            c + Offset(x * cosR - y * sinR, x * sinR + y * cosR),
            pressure,
          );
        }(),
    ];
  }

  /// Samples straight segments every few pixels so the outline builder (and
  /// the pencil's dabs) see evenly spaced points.
  static List<StrokePoint> _polyline(
    List<Offset> corners,
    double pressure, {
    required bool closed,
  }) {
    final path = <Offset>[...corners, if (closed) corners.first];
    final out = <StrokePoint>[];
    for (var i = 0; i < path.length - 1; i++) {
      final a = path[i];
      final b = path[i + 1];
      final steps = math.max(1, ((b - a).distance / 3).ceil());
      for (var k = 0; k < steps; k++) {
        out.add(StrokePoint(Offset.lerp(a, b, k / steps)!, pressure));
      }
    }
    out.add(StrokePoint(path.last, pressure));
    return out;
  }

  /// Hold-to-snap: if a freehand [stroke] is close to a line, ellipse or
  /// rectangle, returns that shape's points (keeping the stroke's average
  /// pressure); otherwise null.
  static (ShapeKind, List<StrokePoint>)? recognise(Stroke stroke) {
    final pts = stroke.points.map((p) => p.offset).toList();
    if (pts.length < 6) return null;
    final pressure =
        stroke.points.map((p) => p.pressure).reduce((a, b) => a + b) /
            stroke.points.length;

    final first = pts.first;
    final last = pts.last;
    var minX = first.dx, maxX = first.dx, minY = first.dy, maxY = first.dy;
    var length = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
      if (i > 0) length += (p - pts[i - 1]).distance;
    }
    final box = Rect.fromLTRB(minX, minY, maxX, maxY);
    final diagonal = math.max(1.0, (box.bottomRight - box.topLeft).distance);
    if (diagonal < 16) return null;

    // Line: every point close to the chord from start to end.
    final chord = last - first;
    if (chord.distance > diagonal * 0.8) {
      final unit = chord / chord.distance;
      var worst = 0.0;
      for (final p in pts) {
        final v = p - first;
        worst = math.max(worst, (v.dx * unit.dy - v.dy * unit.dx).abs());
      }
      if (worst < chord.distance * 0.06 + 2) {
        return (
          ShapeKind.line,
          build(ShapeKind.line, first, last, pressure: pressure)
        );
      }
    }

    // Closed shapes: the end comes back near the start.
    final closed =
        (last - first).distance < diagonal * 0.25 && length > diagonal * 1.6;
    if (!closed) return null;

    // Average distance from the ellipse that fills the bounding box,
    // measured as how far each point's normalised radius is from 1.
    final c = box.center;
    final rx = math.max(box.width / 2, 1.0);
    final ry = math.max(box.height / 2, 1.0);
    var ellipseError = 0.0;
    for (final p in pts) {
      final nx = (p.dx - c.dx) / rx;
      final ny = (p.dy - c.dy) / ry;
      ellipseError += (math.sqrt(nx * nx + ny * ny) - 1).abs();
    }
    ellipseError /= pts.length;

    // Average distance from the bounding rectangle's edges, normalised.
    var rectError = 0.0;
    for (final p in pts) {
      final d = <double>[
        (p.dx - box.left).abs() / rx,
        (p.dx - box.right).abs() / rx,
        (p.dy - box.top).abs() / ry,
        (p.dy - box.bottom).abs() / ry,
      ].reduce(math.min);
      rectError += d;
    }
    rectError /= pts.length;

    if (ellipseError < 0.16 && ellipseError <= rectError) {
      return (ShapeKind.ellipse, ellipse(box, pressure));
    }
    if (rectError < 0.12) {
      return (
        ShapeKind.rectangle,
        build(ShapeKind.rectangle, box.topLeft, box.bottomRight,
            pressure: pressure),
      );
    }
    return null;
  }
}
