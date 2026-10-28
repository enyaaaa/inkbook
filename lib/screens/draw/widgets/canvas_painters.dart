import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../models/brush.dart';
import '../../../models/sketchbook.dart';
import '../../../models/stroke.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/pencil_texture.dart';
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

/// Remembers the finished strokes as a recorded [ui.Picture], so drawing a
/// new stroke only has to build that one stroke - not re-tessellate every
/// stroke on the page on every pointer move. Owned by the canvas widget.
class StrokeCache {
  ui.Picture? _picture;
  int _revision = -1;
  List<Stroke>? _strokes;

  ui.Picture picture(List<Stroke> strokes, int revision) {
    final cached = _picture;
    if (cached != null &&
        _revision == revision &&
        identical(_strokes, strokes)) {
      return cached;
    }
    cached?.dispose();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final stroke in strokes) {
      paintStroke(canvas, stroke);
    }
    _revision = revision;
    _strokes = strokes;
    return _picture = recorder.endRecording();
  }

  void dispose() {
    _picture?.dispose();
    _picture = null;
  }
}

/// Paints one stroke. Pencil strokes are graphite (stamped, pressure and
/// tilt shaded, paper grain); ink and marker are smooth filled outlines.
///
/// Eraser strokes use [BlendMode.clear], which removes ink rather than
/// painting paper-coloured strokes over it - so the paper texture and grid
/// stay visible underneath.
void paintStroke(Canvas canvas, Stroke stroke) {
  if (stroke.isEmpty) return;
  if (stroke.brush.type == BrushType.pencil) {
    _paintPencil(canvas, stroke);
    return;
  }

  final outline = StrokeGeometry.buildOutline(stroke);
  final averagePressure =
      stroke.points.map((p) => p.pressure).reduce((a, b) => a + b) /
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

/// Graphite. The stroke is laid down as many small overlapping dabs along
/// the centre line:
///
/// - each dab's size and darkness come from the pressure at that point, so
///   one stroke can go from a whisper to a hard line;
/// - tilting the stylus widens and softens the dab, like shading with the
///   side of the lead;
/// - dabs build up where they overlap, so going back over an area darkens
///   it, as graphite does;
/// - the result is masked by [PencilGrain], so light pressure only catches
///   the paper's raised tooth.
void _paintPencil(Canvas canvas, Stroke stroke) {
  final brush = stroke.brush;
  final points = stroke.points;
  final bounds = stroke.bounds.inflate(brush.size * 2 + 4);

  canvas.saveLayer(bounds, Paint());
  final dab = Paint()..isAntiAlias = true;

  // About this many dabs overlap at any spot on the centre line; each dab's
  // alpha is chosen so that together they reach the target darkness.
  const overlap = 5.0;

  void stamp(StrokePoint p) {
    final tilt = (p.tilt / (math.pi / 2)).clamp(0.0, 1.0);
    final radius = math.max(
      StrokeGeometry.halfWidthAt(brush, p.pressure) * (1 + 2.2 * tilt),
      0.45,
    );
    final target =
        StrokeGeometry.opacityAt(brush, p.pressure) * (1 - 0.5 * tilt);
    final alpha = 1 - math.pow(1 - target.clamp(0.0, 0.999), 1 / overlap);
    dab.color = brush.color.withAlpha((alpha * 255).round().clamp(1, 255));
    canvas.drawCircle(p.offset, radius, dab);
  }

  stamp(points.first);
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    final distance = (b.offset - a.offset).distance;
    final radius =
        math.max(StrokeGeometry.halfWidthAt(brush, b.pressure), 0.45);
    final spacing = math.max(radius * 2 / overlap, 0.5);
    final steps = math.max(1, (distance / spacing).ceil());
    for (var k = 1; k <= steps; k++) {
      stamp(a.lerpTo(b, k / steps));
    }
  }

  final grain = PencilGrain.image;
  if (grain != null) {
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ImageShader(
          grain,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        ),
    );
  }
  canvas.restore();
}

/// Paints the page's strokes plus the one being drawn. Finished strokes
/// come from [cache]; only the live stroke is built each frame.
class StrokePainter extends CustomPainter {
  StrokePainter({
    required this.strokes,
    required this.revision,
    required this.liveVersion,
    required this.cache,
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
  final StrokeCache cache;

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
    canvas.drawPicture(cache.picture(strokes, revision));
    final live = liveStroke;
    if (live != null) paintStroke(canvas, live);
    canvas.restore();
  }

  @override
  bool shouldRepaint(StrokePainter oldDelegate) =>
      oldDelegate.revision != revision ||
      oldDelegate.liveVersion != liveVersion ||
      oldDelegate.pan != pan ||
      oldDelegate.zoom != zoom ||
      !identical(oldDelegate.strokes, strokes) ||
      !identical(oldDelegate.liveStroke, liveStroke);
}
