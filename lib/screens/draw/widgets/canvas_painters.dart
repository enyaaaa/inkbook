import 'package:flutter/material.dart';

import '../../../models/sketchbook.dart';
import '../../../models/stroke.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/stroke_geometry.dart';

/// Paints the paper itself: colour, grid or rule lines, and a subtle inner
/// shadow at the spine so the page reads as part of a bound sketchbook.
class PaperPainter extends CustomPainter {
  const PaperPainter(this.paper);

  final PaperStyle paper;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final background = paper == PaperStyle.toned
        ? InkbookColors.paperToned
        : const Color(0xFFFFFDF8);
    canvas.drawRect(rect, Paint()..color = background);

    final guide = Paint()
      ..color =
          InkbookColors.inkSoft.withAlpha(paper == PaperStyle.toned ? 40 : 30)
      ..strokeWidth = 1;

    switch (paper) {
      case PaperStyle.plain:
      case PaperStyle.toned:
        break;
      case PaperStyle.ruled:
        for (var y = 48.0; y < size.height; y += 32) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), guide);
        }
      case PaperStyle.grid:
        for (var x = 32.0; x < size.width; x += 32) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), guide);
        }
        for (var y = 32.0; y < size.height; y += 32) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), guide);
        }
      case PaperStyle.dotted:
        final dot = Paint()..color = InkbookColors.inkSoft.withAlpha(55);
        for (var x = 28.0; x < size.width; x += 28) {
          for (var y = 28.0; y < size.height; y += 28) {
            canvas.drawCircle(Offset(x, y), 1.1, dot);
          }
        }
    }

    // Spine shading on the left edge.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 26, size.height),
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            InkbookColors.ink.withAlpha(30),
            InkbookColors.ink.withAlpha(0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, 26, size.height)),
    );
  }

  @override
  bool shouldRepaint(PaperPainter oldDelegate) => oldDelegate.paper != paper;
}

/// The infinite whiteboard's paper: the same patterns as [PaperPainter],
/// but tiled forever and moving with the board as it is panned and zoomed.
class BoardPaperPainter extends CustomPainter {
  const BoardPaperPainter(this.paper, {required this.pan, required this.zoom});

  final PaperStyle paper;
  final Offset pan;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..color = paper == PaperStyle.toned
            ? InkbookColors.paperToned
            : const Color(0xFFFFFDF8),
    );

    final alpha = paper == PaperStyle.toned ? 40 : 30;
    final line = Paint()
      ..color = InkbookColors.inkSoft.withAlpha(alpha)
      ..strokeWidth = 1;

    // Pattern spacing in board units, doubled while zoomed far out so the
    // pattern never turns into a grey smear.
    double spacing(double base) {
      var s = base * zoom;
      while (s < 12) {
        s *= 2;
      }
      return s;
    }

    double start(double offset, double step) => offset % step - step;

    switch (paper) {
      case PaperStyle.plain:
      case PaperStyle.toned:
        // A very faint grid so movement is visible on a blank board.
        final step = spacing(160);
        line.color = InkbookColors.inkSoft.withAlpha(12);
        for (var x = start(pan.dx, step); x < size.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        }
        for (var y = start(pan.dy, step); y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
      case PaperStyle.ruled:
        final step = spacing(32);
        for (var y = start(pan.dy, step); y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
      case PaperStyle.grid:
        final step = spacing(32);
        for (var x = start(pan.dx, step); x < size.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        }
        for (var y = start(pan.dy, step); y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        }
      case PaperStyle.dotted:
        final step = spacing(28);
        final dot = Paint()..color = InkbookColors.inkSoft.withAlpha(55);
        final radius = (1.1 * zoom).clamp(0.7, 2.2);
        for (var x = start(pan.dx, step); x < size.width; x += step) {
          for (var y = start(pan.dy, step); y < size.height; y += step) {
            canvas.drawCircle(Offset(x, y), radius, dot);
          }
        }
    }
  }

  @override
  bool shouldRepaint(BoardPaperPainter oldDelegate) =>
      oldDelegate.paper != paper ||
      oldDelegate.pan != pan ||
      oldDelegate.zoom != zoom;
}

/// Paints a list of strokes with pressure-driven width and opacity.
///
/// Eraser strokes are drawn with [BlendMode.clear] inside a `saveLayer`, which
/// removes ink rather than painting paper-coloured strokes over it - so the
/// paper texture and grid stay visible underneath.
class StrokePainter extends CustomPainter {
  const StrokePainter({
    required this.strokes,
    required this.revision,
    required this.liveVersion,
    this.liveStroke,
    this.pan = Offset.zero,
    this.zoom = 1,
  });

  /// Board-to-screen transform for the infinite whiteboard (identity for
  /// ordinary pages).
  final Offset pan;
  final double zoom;

  final List<Stroke> strokes;
  final Stroke? liveStroke;

  /// Changes whenever [strokes] is mutated, so the painter knows to repaint.
  final int revision;

  /// Number of points in [liveStroke] at the time this painter was built.
  ///
  /// The live stroke is mutated in place while the user draws, so comparing
  /// the object itself in [shouldRepaint] would always report "unchanged".
  /// Capturing the length at build time is what makes the stroke appear as it
  /// is drawn.
  final int liveVersion;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(zoom);
    // Skip strokes entirely off screen - matters on a big whiteboard.
    final visible = Rect.fromLTWH(
      -pan.dx / zoom,
      -pan.dy / zoom,
      size.width / zoom,
      size.height / zoom,
    );
    for (final stroke in strokes) {
      if (zoom != 1 || pan != Offset.zero) {
        if (!stroke.bounds.overlaps(visible)) continue;
      }
      _paintStroke(canvas, stroke);
    }
    final live = liveStroke;
    if (live != null) _paintStroke(canvas, live);
    canvas.restore();
  }

  void _paintStroke(Canvas canvas, Stroke stroke) {
    if (stroke.isEmpty) return;
    final outline = StrokeGeometry.buildOutline(stroke);
    final averagePressure = stroke.points.isEmpty
        ? 0.5
        : stroke.points.map((p) => p.pressure).reduce((a, b) => a + b) /
            stroke.points.length;

    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;

    if (stroke.isEraser) {
      paint
        ..blendMode = BlendMode.clear
        ..color = const Color(0xFF000000);
    } else {
      final opacity = StrokeGeometry.opacityAt(stroke.brush, averagePressure);
      paint.color = stroke.brush.color.withAlpha((opacity * 255).round());
    }

    canvas.drawPath(outline, paint);
  }

  @override
  bool shouldRepaint(StrokePainter oldDelegate) =>
      oldDelegate.revision != revision ||
      oldDelegate.liveVersion != liveVersion ||
      oldDelegate.pan != pan ||
      oldDelegate.zoom != zoom ||
      !identical(oldDelegate.liveStroke, liveStroke);
}
