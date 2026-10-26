import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/artwork.dart';
import '../theme/app_theme.dart';

/// Renders an artwork.
///
/// If the artwork came from a real sketchbook page it has PNG bytes and is
/// drawn as an image. Sample artworks have no bytes, so they are drawn as
/// procedural pencil studies chosen from their tags - deterministic from the
/// artwork's seed, so the same piece always looks the same, and no image
/// assets need to ship with the prototype.
class ArtworkThumbnail extends StatelessWidget {
  const ArtworkThumbnail({super.key, required this.artwork, this.radius = 14});

  final Artwork artwork;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bytes = artwork.imageBytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: bytes != null
          ? Image.memory(bytes, fit: BoxFit.cover)
          : RepaintBoundary(
              child: CustomPaint(
                painter: _SketchPainter(artwork.seed, artwork.tags),
                child: const SizedBox.expand(),
              ),
            ),
    );
  }
}

/// What a sample piece depicts, picked from its tags.
enum _Subject { object, bus, hand, creature, leaf, figures, umbrella, facade }

_Subject _subjectFor(List<String> tags, int seed) {
  bool has(String tag) => tags.contains(tag);
  if (has('anatomy')) return _Subject.hand;
  if (has('creature')) return _Subject.creature;
  if (has('botanical')) return _Subject.leaf;
  if (has('figure') || has('practice')) return _Subject.figures;
  if (has('people')) return _Subject.bus;
  if (has('mood') || has('wash')) return _Subject.umbrella;
  if (has('architecture')) return _Subject.facade;
  return _Subject.object;
}

/// A page of pencil studies: one main subject, a small secondary study,
/// faint construction lines and hatched shading, like the loose concept
/// sketches people post from their sketchbooks.
class _SketchPainter extends CustomPainter {
  _SketchPainter(this.seed, this.tags);

  final int seed;
  final List<String> tags;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed);
    final rect = Offset.zero & size;

    // Paper, with a little tooth.
    canvas.drawRect(rect, Paint()..color = const Color(0xFFF8F6F1));
    final tooth = Paint();
    for (var i = 0; i < size.width * size.height / 260; i++) {
      tooth.color = Colors.black.withAlpha(3 + r.nextInt(6));
      canvas.drawCircle(
        Offset(r.nextDouble() * size.width, r.nextDouble() * size.height),
        0.4 + r.nextDouble() * 0.5,
        tooth,
      );
    }

    final subject = _subjectFor(tags, seed);
    final pencil = _Pencil(canvas, r, size.shortestSide / 160);

    // A watercolour wash behind some pieces.
    if (subject == _Subject.umbrella ||
        subject == _Subject.leaf ||
        r.nextInt(4) == 0) {
      final wash = <Color>[
        InkbookColors.toolYellow,
        InkbookColors.toolTeal,
        InkbookColors.folderRose,
        InkbookColors.sage,
        InkbookColors.folderLavender,
      ][subject == _Subject.leaf ? 3 : r.nextInt(5)];
      canvas.drawCircle(
        Offset(size.width * (0.35 + r.nextDouble() * 0.3),
            size.height * (0.4 + r.nextDouble() * 0.2)),
        size.shortestSide * 0.3,
        Paint()
          ..color = wash.withAlpha(60)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );
    }

    // Faint construction lines across the page.
    for (var i = 0; i < 3; i++) {
      final y = size.height * (0.2 + r.nextDouble() * 0.6);
      pencil.line(
        Offset(-10, y + r.nextDouble() * 30 - 15),
        Offset(size.width + 10, y + r.nextDouble() * 30 - 15),
        width: 0.6,
        alpha: 0.12,
        passes: 1,
      );
    }

    final main = Rect.fromCenter(
      center: Offset(size.width * 0.5, size.height * 0.47),
      width: size.width * 0.9,
      height: size.height * 0.76,
    );

    switch (subject) {
      case _Subject.object:
        _roundedObject(pencil, main, r);
      case _Subject.bus:
        _bus(pencil, main, r);
      case _Subject.hand:
        _hand(pencil, main, r);
      case _Subject.creature:
        _creature(pencil, main, r);
      case _Subject.leaf:
        _leaf(pencil, main, r);
      case _Subject.figures:
        _figures(pencil, main, r);
      case _Subject.umbrella:
        _umbrella(pencil, main, r, size);
      case _Subject.facade:
        _facade(pencil, main, r);
    }

    // A small secondary study tucked in a corner.
    final small = size.shortestSide * 0.13;
    final corner = Offset(
      r.nextBool() ? size.width * 0.17 : size.width * 0.83,
      size.height * 0.86,
    );
    if (r.nextBool()) {
      _sphere(pencil, Rect.fromCircle(center: corner, radius: small * 0.6), r);
    } else {
      _roundedObject(
        pencil,
        Rect.fromCenter(center: corner, width: small * 1.4, height: small),
        r,
        detail: false,
      );
    }
  }

  // --- subjects --------------------------------------------------------------

  /// A soft-cornered box in perspective with an arched opening - the
  /// toaster / tiny-house shape from the reference studies.
  void _roundedObject(_Pencil p, Rect area, math.Random r,
      {bool detail = true}) {
    final w = area.width * 0.66;
    final h = area.height * 0.56;
    final front = Rect.fromLTWH(
        area.left + area.width * 0.08, area.center.dy - h * 0.25, w, h);
    final depth = Offset(area.width * 0.22, -area.height * 0.16);
    final radius = math.min(w, h) * 0.28;

    final top = Path()
      ..moveTo(front.left + radius * 0.6, front.top)
      ..lineTo(front.left + radius * 0.6 + depth.dx, front.top + depth.dy)
      ..lineTo(front.right - radius * 0.3 + depth.dx, front.top + depth.dy)
      ..lineTo(front.right - radius * 0.3, front.top)
      ..close();
    final side = Path()
      ..moveTo(front.right, front.top + radius * 0.6)
      ..lineTo(front.right + depth.dx, front.top + radius * 0.6 + depth.dy)
      ..lineTo(front.right + depth.dx, front.bottom - radius * 0.4 + depth.dy)
      ..lineTo(front.right, front.bottom - radius * 0.4)
      ..close();

    // Cast shadow on the ground.
    final ground = Rect.fromCenter(
      center: Offset(front.center.dx + depth.dx * 0.7, front.bottom + h * 0.08),
      width: w * 1.25,
      height: h * 0.22,
    );
    p.hatch(Path()..addOval(ground), angle: -0.9, spacing: 3.2, alpha: 0.35);
    p.ellipse(ground, alpha: 0.25, width: 0.8);

    p.hatch(side, angle: 0.95, spacing: 2.6, alpha: 0.55);
    p.hatch(top, angle: -0.2, spacing: 5, alpha: 0.18);
    p.roundRect(front, radius, width: 1.8);
    p.line(Offset(front.left + radius * 0.6, front.top),
        Offset(front.left + radius * 0.6 + depth.dx, front.top + depth.dy));
    p.line(Offset(front.right - radius * 0.3, front.top),
        Offset(front.right - radius * 0.3 + depth.dx, front.top + depth.dy));
    p.line(Offset(front.left + radius * 0.6 + depth.dx, front.top + depth.dy),
        Offset(front.right - radius * 0.3 + depth.dx, front.top + depth.dy));
    p.line(Offset(front.right + depth.dx, front.top + radius * 0.6 + depth.dy),
        Offset(front.right + depth.dx, front.bottom - radius * 0.4 + depth.dy));
    p.line(Offset(front.right, front.bottom - radius * 0.4),
        Offset(front.right + depth.dx, front.bottom - radius * 0.4 + depth.dy));

    if (!detail) return;
    // Arched door with a shaded inside.
    final door = Rect.fromLTWH(
        front.left + w * 0.38, front.top + h * 0.3, w * 0.26, h * 0.62);
    final doorPath = Path()
      ..moveTo(door.left, door.bottom)
      ..lineTo(door.left, door.top + door.width / 2)
      ..arcTo(Rect.fromLTWH(door.left, door.top, door.width, door.width),
          math.pi, math.pi, false)
      ..lineTo(door.right, door.bottom);
    p.hatch(Path.from(doorPath)..close(), angle: 0.8, spacing: 2.2, alpha: 0.7);
    p.path(doorPath, width: 1.5);
    // Little window and a handle on top.
    p.ellipse(Rect.fromLTWH(
        front.left + w * 0.1, front.top + h * 0.22, w * 0.18, h * 0.24));
    p.ellipse(
      Rect.fromCenter(
        center: Offset(front.center.dx + depth.dx * 0.5,
            front.top + depth.dy * 0.5 - h * 0.06),
        width: w * 0.3,
        height: h * 0.16,
      ),
      width: 1.3,
    );
    _speedMarks(p, Offset(front.right + depth.dx + 6, front.top + depth.dy), r);
  }

  void _bus(_Pencil p, Rect area, math.Random r) {
    final body = Rect.fromLTWH(area.left, area.center.dy - area.height * 0.28,
        area.width * 0.95, area.height * 0.5);
    final radius = body.height * 0.22;
    p.hatch(
      Path()
        ..addOval(Rect.fromCenter(
            center: Offset(body.center.dx, body.bottom + 6),
            width: body.width * 1.05,
            height: body.height * 0.18)),
      angle: -0.8,
      spacing: 3,
      alpha: 0.3,
    );
    p.roundRect(body, radius, width: 1.9);
    // Two decks of windows.
    for (var deck = 0; deck < 2; deck++) {
      final y = body.top + body.height * (0.12 + deck * 0.38);
      for (var i = 0; i < 5; i++) {
        final win = Rect.fromLTWH(body.left + body.width * (0.07 + i * 0.17), y,
            body.width * 0.13, body.height * 0.24);
        p.roundRect(win, 4, width: 1.1);
        if ((i + deck) % 2 == 0) {
          p.hatch(Path()..addRect(win), angle: 0.9, spacing: 2.4, alpha: 0.5);
        }
      }
    }
    p.line(Offset(body.left + 4, body.top + body.height * 0.48),
        Offset(body.right - 4, body.top + body.height * 0.48),
        width: 0.9);
    for (final x in <double>[0.22, 0.78]) {
      final c = Offset(body.left + body.width * x, body.bottom);
      p.ellipse(Rect.fromCircle(center: c, radius: body.height * 0.15),
          width: 1.8);
      p.hatch(
          Path()
            ..addOval(Rect.fromCircle(center: c, radius: body.height * 0.15)),
          angle: 0.4,
          spacing: 2,
          alpha: 0.75);
    }
    _speedMarks(p, Offset(body.left - 4, body.center.dy), r, flip: true);
  }

  /// A construction study of a hand: palm block plus a chain of ovals per
  /// finger, the way anatomy is taught.
  void _hand(_Pencil p, Rect area, math.Random r) {
    final palm = Rect.fromCenter(
      center: Offset(area.center.dx, area.center.dy + area.height * 0.16),
      width: area.width * 0.5,
      height: area.height * 0.4,
    );
    p.roundRect(palm, palm.width * 0.2, width: 1.6);
    p.hatch(
      Path()
        ..addRect(Rect.fromLTWH(
            palm.left, palm.center.dy, palm.width, palm.height / 2)),
      angle: 0.9,
      spacing: 3,
      alpha: 0.35,
    );
    // Wrist.
    p.line(Offset(palm.left + palm.width * 0.15, palm.bottom),
        Offset(palm.left + palm.width * 0.1, area.bottom));
    p.line(Offset(palm.right - palm.width * 0.1, palm.bottom),
        Offset(palm.right - palm.width * 0.05, area.bottom));
    // Fingers.
    final lengths = <double>[0.78, 0.92, 0.86, 0.68];
    for (var f = 0; f < 4; f++) {
      final base = Offset(palm.left + palm.width * (0.14 + f * 0.24), palm.top);
      final lean = (f - 1.5) * 0.12;
      var at = base;
      final segment = palm.height * 0.36 * lengths[f];
      for (var k = 0; k < 3; k++) {
        final next =
            at + Offset(math.sin(lean) * segment, -math.cos(lean) * segment);
        p.ellipse(
          Rect.fromCenter(
            center: Offset.lerp(at, next, 0.5)!,
            width: palm.width * 0.18,
            height: segment * 1.08,
          ),
          width: k == 0 ? 1.4 : 1.1,
        );
        at = next;
      }
    }
    // Thumb.
    var at = Offset(palm.left, palm.center.dy);
    for (var k = 0; k < 2; k++) {
      final next = at + Offset(-palm.width * 0.2, -palm.height * 0.22);
      p.ellipse(
        Rect.fromCenter(
            center: Offset.lerp(at, next, 0.5)!,
            width: palm.width * 0.26,
            height: palm.width * 0.2),
        width: 1.3,
      );
      at = next;
    }
    // Gesture line through the middle finger.
    p.line(Offset(palm.center.dx, area.bottom),
        Offset(palm.center.dx + 6, area.top),
        width: 0.6, alpha: 0.25);
  }

  void _creature(_Pencil p, Rect area, math.Random r) {
    final body = Rect.fromCenter(
      center: area.center + Offset(0, area.height * 0.06),
      width: area.width * 0.78,
      height: area.height * 0.7,
    );
    final bodyPath = Path()..addOval(body);
    // Shading on the lower right.
    p.canvas.save();
    p.canvas.clipPath(bodyPath);
    p.hatch(
      Path()..addOval(body.shift(Offset(body.width * 0.3, body.height * 0.25))),
      angle: 0.85,
      spacing: 2.4,
      alpha: 0.6,
    );
    p.canvas.restore();
    p.hatch(
      Path()
        ..addOval(Rect.fromCenter(
            center: Offset(body.center.dx + 10, body.bottom + 4),
            width: body.width * 0.9,
            height: body.height * 0.16)),
      angle: -0.8,
      spacing: 3,
      alpha: 0.35,
    );
    p.ellipse(body, width: 2, passes: 3);
    // Ears / antennae.
    for (final side in <double>[-1, 1]) {
      final ear = Rect.fromCenter(
        center: Offset(body.center.dx + side * body.width * 0.3,
            body.top + body.height * 0.02),
        width: body.width * 0.22,
        height: body.height * 0.3,
      );
      p.ellipse(ear, width: 1.5);
    }
    // Eyes with highlights.
    for (final side in <double>[-1, 1]) {
      final c = Offset(body.center.dx + side * body.width * 0.16,
          body.center.dy - body.height * 0.06);
      final eye = Rect.fromCircle(center: c, radius: body.width * 0.07);
      p.hatch(Path()..addOval(eye), angle: 0.3, spacing: 1.4, alpha: 0.95);
      p.ellipse(eye, width: 1.4);
      p.canvas.drawCircle(c + Offset(-eye.width * 0.18, -eye.height * 0.2),
          eye.width * 0.14, Paint()..color = const Color(0xFFF8F6F1));
    }
    // A wobbly smile and little feet.
    p.stroke(<Offset>[
      Offset(body.center.dx - body.width * 0.08,
          body.center.dy + body.height * 0.12),
      Offset(body.center.dx, body.center.dy + body.height * 0.17),
      Offset(body.center.dx + body.width * 0.08,
          body.center.dy + body.height * 0.12),
    ], width: 1.3);
    for (final side in <double>[-1, 1]) {
      p.ellipse(
        Rect.fromCenter(
          center:
              Offset(body.center.dx + side * body.width * 0.2, body.bottom - 2),
          width: body.width * 0.2,
          height: body.height * 0.1,
        ),
        width: 1.4,
      );
    }
    // Ripples - it lives in a reservoir.
    for (var i = 0; i < 3; i++) {
      final y = body.bottom + body.height * (0.12 + i * 0.07);
      p.line(Offset(area.left + i * 14, y),
          Offset(area.left + area.width * 0.35 + i * 6, y + 2),
          width: 0.8, alpha: 0.4);
      p.line(Offset(area.right - area.width * 0.35, y + 3),
          Offset(area.right - i * 10, y),
          width: 0.8, alpha: 0.4);
    }
    _speedMarks(p, Offset(body.right, body.top), r);
  }

  /// A monstera leaf with its slits and veins, half hatched.
  void _leaf(_Pencil p, Rect area, math.Random r) {
    final c = area.center;
    final rx = area.width * 0.42;
    final ry = area.height * 0.4;
    final outline = <Offset>[];
    for (var i = 0; i <= 40; i++) {
      final a = -math.pi / 2 + i / 40 * math.pi * 2;
      final heart =
          1 - 0.18 * math.pow(math.cos((a + math.pi / 2) / 2), 40).toDouble();
      outline
          .add(c + Offset(math.cos(a) * rx * heart, math.sin(a) * ry * heart));
    }
    final leafPath = Path()..addPolygon(outline, true);
    p.canvas.save();
    p.canvas.clipPath(leafPath);
    p.hatch(
        Path()..addRect(Rect.fromLTRB(c.dx, area.top, area.right, area.bottom)),
        angle: 0.7,
        spacing: 2.6,
        alpha: 0.4);
    p.canvas.restore();
    p.stroke(outline, width: 1.8, passes: 2);
    // Midrib and stem.
    p.stroke(<Offset>[
      Offset(c.dx, c.dy - ry * 0.9),
      Offset(c.dx + 4, c.dy),
      Offset(c.dx + 2, c.dy + ry * 0.9),
      Offset(c.dx + 18, area.bottom + 20),
    ], width: 1.6);
    // Veins and slits.
    for (var i = 0; i < 5; i++) {
      final t = -0.7 + i * 0.35;
      final start = Offset(c.dx + 3, c.dy + t * ry);
      for (final side in <double>[-1, 1]) {
        final end =
            Offset(c.dx + side * rx * 0.95, c.dy + (t - 0.25) * ry * 0.9);
        p.stroke(<Offset>[
          start,
          Offset.lerp(start, end, 0.5)! + const Offset(0, -6),
          end
        ], width: 0.9, alpha: 0.7);
        if (i % 2 == 1) {
          final slit = Offset.lerp(start, end, 0.82)!;
          p.ellipse(Rect.fromCenter(center: slit, width: rx * 0.22, height: 5),
              width: 1, alpha: 0.8);
        }
      }
    }
  }

  /// Thirty-second gesture drawings: line of action, head, limbs.
  void _figures(_Pencil p, Rect area, math.Random r) {
    for (var f = 0; f < 3; f++) {
      final x = area.left + area.width * (0.18 + f * 0.32);
      final top = area.top + area.height * (0.08 + r.nextDouble() * 0.1);
      final h = area.height * 0.8;
      final lean = (r.nextDouble() - 0.5) * 0.5;
      final head = Offset(x + lean * 20, top + h * 0.08);
      final hip = Offset(x - lean * 18, top + h * 0.5);
      p.ellipse(Rect.fromCircle(center: head, radius: h * 0.07), width: 1.4);
      // Line of action.
      p.stroke(<Offset>[
        head + Offset(0, h * 0.07),
        Offset.lerp(head, hip, 0.5)! + Offset(lean * 30, 0),
        hip
      ], width: 2);
      final shoulder = Offset.lerp(head, hip, 0.28)!;
      for (final side in <double>[-1, 1]) {
        final elbow = shoulder +
            Offset(side * h * 0.14, h * (0.1 + r.nextDouble() * 0.1));
        p.stroke(<Offset>[
          shoulder,
          elbow,
          elbow + Offset(side * h * 0.06, h * (r.nextDouble() * 0.2 - 0.12))
        ], width: 1.2);
        final knee = hip + Offset(side * h * 0.1, h * 0.22);
        p.stroke(<Offset>[
          hip,
          knee,
          knee + Offset(side * h * 0.02 - lean * 10, h * 0.24)
        ], width: 1.4);
      }
      p.ellipse(Rect.fromCenter(center: hip, width: h * 0.16, height: h * 0.08),
          width: 1, alpha: 0.6);
    }
  }

  void _umbrella(_Pencil p, Rect area, math.Random r, Size size) {
    // Rain first, so the umbrella sits over it.
    for (var i = 0; i < 26; i++) {
      final s = Offset(
          r.nextDouble() * size.width, r.nextDouble() * size.height * 0.8);
      p.line(s, s + const Offset(-7, 18), width: 0.7, alpha: 0.35, passes: 1);
    }
    final canopy = Rect.fromCenter(
      center: Offset(area.center.dx, area.top + area.height * 0.38),
      width: area.width * 0.8,
      height: area.height * 0.5,
    );
    final dome = Path()
      ..moveTo(canopy.left, canopy.center.dy)
      ..arcTo(canopy, math.pi, math.pi, false);
    // Scalloped hem.
    final hem = <Offset>[];
    for (var i = 0; i <= 4; i++) {
      final x0 = canopy.left + canopy.width * i / 4;
      hem.add(Offset(x0, canopy.center.dy));
      if (i < 4)
        hem.add(Offset(
            x0 + canopy.width / 8, canopy.center.dy - canopy.height * 0.08));
    }
    p.canvas.save();
    p.canvas.clipPath(Path.from(dome)..close());
    p.hatch(
        Path()
          ..addRect(Rect.fromLTRB(
              canopy.center.dx, canopy.top, canopy.right, canopy.center.dy)),
        angle: 0.9,
        spacing: 2.4,
        alpha: 0.55);
    p.canvas.restore();
    p.path(dome, width: 1.9);
    p.stroke(hem, width: 1.4);
    for (var i = 1; i < 4; i++) {
      p.stroke(<Offset>[
        Offset(canopy.center.dx, canopy.top),
        Offset(canopy.left + canopy.width * i / 4, canopy.center.dy),
      ], width: 0.9, alpha: 0.7);
    }
    // Shaft and hook.
    final bottom = Offset(canopy.center.dx, area.bottom - area.height * 0.05);
    p.line(Offset(canopy.center.dx, canopy.top - 8), bottom, width: 1.6);
    p.path(
      Path()
        ..moveTo(bottom.dx, bottom.dy)
        ..arcToPoint(bottom + const Offset(-16, 0),
            radius: const Radius.circular(8)),
      width: 1.6,
    );
    // Puddle.
    p.ellipse(
      Rect.fromCenter(
          center: Offset(area.center.dx, area.bottom + 6),
          width: area.width * 0.7,
          height: 12),
      width: 0.9,
      alpha: 0.5,
    );
  }

  /// A shophouse front: pitched roof line, arched windows, five-foot way.
  void _facade(_Pencil p, Rect area, math.Random r) {
    final front = Rect.fromLTWH(area.left + area.width * 0.12,
        area.top + area.height * 0.08, area.width * 0.76, area.height * 0.9);
    p.roundRect(front, 3, width: 1.8);
    p.stroke(<Offset>[
      front.topLeft + const Offset(-8, 4),
      Offset(front.center.dx, front.top - front.height * 0.12),
      front.topRight + const Offset(8, 4),
    ], width: 1.6);
    final floor = front.top + front.height * 0.55;
    p.line(Offset(front.left, floor), Offset(front.right, floor), width: 1.4);
    for (var i = 0; i < 3; i++) {
      final win = Rect.fromLTWH(
          front.left + front.width * (0.08 + i * 0.31),
          front.top + front.height * 0.12,
          front.width * 0.22,
          front.height * 0.32);
      final arch = Path()
        ..moveTo(win.left, win.bottom)
        ..lineTo(win.left, win.top + win.width / 2)
        ..arcTo(Rect.fromLTWH(win.left, win.top, win.width, win.width), math.pi,
            math.pi, false)
        ..lineTo(win.right, win.bottom)
        ..close();
      p.hatch(arch, angle: 0.85, spacing: 2.2, alpha: 0.55);
      p.path(arch, width: 1.3);
      p.line(
          Offset(win.center.dx, win.top + 4), Offset(win.center.dx, win.bottom),
          width: 0.8);
    }
    // Five-foot way arches at street level.
    for (var i = 0; i < 2; i++) {
      final bay = Rect.fromLTWH(front.left + front.width * (0.08 + i * 0.46),
          floor + 8, front.width * 0.38, front.bottom - floor - 8);
      final arch = Path()
        ..moveTo(bay.left, bay.bottom)
        ..lineTo(bay.left, bay.top + bay.width / 2)
        ..arcTo(Rect.fromLTWH(bay.left, bay.top, bay.width, bay.width), math.pi,
            math.pi, false)
        ..lineTo(bay.right, bay.bottom);
      p.hatch(Path.from(arch)..close(), angle: -0.9, spacing: 3, alpha: 0.35);
      p.path(arch, width: 1.4);
    }
  }

  void _sphere(_Pencil p, Rect box, math.Random r) {
    final path = Path()..addOval(box);
    p.canvas.save();
    p.canvas.clipPath(path);
    p.hatch(
        Path()..addOval(box.shift(Offset(box.width * 0.35, box.height * 0.3))),
        angle: 0.9,
        spacing: 2.2,
        alpha: 0.6);
    p.canvas.restore();
    p.hatch(
      Path()
        ..addOval(Rect.fromCenter(
            center: Offset(box.center.dx + box.width * 0.3, box.bottom),
            width: box.width,
            height: box.height * 0.25)),
      angle: -0.8,
      spacing: 2.6,
      alpha: 0.35,
    );
    p.ellipse(box, width: 1.5, passes: 2);
    p.ellipse(
        Rect.fromCenter(
            center: box.center, width: box.width, height: box.height * 0.3),
        width: 0.7,
        alpha: 0.3);
  }

  /// Little motion ticks next to an object, as in loose concept sketches.
  void _speedMarks(_Pencil p, Offset at, math.Random r, {bool flip = false}) {
    for (var i = 0; i < 3; i++) {
      final s = at + Offset((flip ? -1 : 1) * (4 + i * 6.0), -4 - i * 5.0);
      p.line(s, s + Offset((flip ? -1 : 1) * 6, -8),
          width: 1.1, alpha: 0.7, passes: 1);
    }
  }

  @override
  bool shouldRepaint(_SketchPainter oldDelegate) => oldDelegate.seed != seed;
}

/// Draws with a soft graphite pencil: every mark is a few slightly
/// different, tapered passes that overshoot their ends, so lines read as
/// hand-drawn rather than vector-perfect.
class _Pencil {
  _Pencil(this.canvas, this.r, this.scale);

  final Canvas canvas;
  final math.Random r;
  final double scale;

  static const Color _graphite = Color(0xFF2A2A2E);

  double _j(double amount) => (r.nextDouble() - 0.5) * 2 * amount * scale;

  /// A smooth tapered stroke through [points].
  void stroke(
    List<Offset> points, {
    double width = 1.4,
    double alpha = 0.85,
    int passes = 2,
    double jitter = 1.2,
  }) {
    if (points.length < 2) return;
    final smooth = _resample(points);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var pass = 0; pass < passes; pass++) {
      final shift = Offset(_j(jitter), _j(jitter));
      final over = 0.04 + r.nextDouble() * 0.06; // overshoot at the ends
      final a = alpha * (pass == 0 ? 1 : 0.45 + r.nextDouble() * 0.3);
      for (var i = 0; i < smooth.length - 1; i++) {
        final t = i / (smooth.length - 1);
        final taper = 0.3 + 0.7 * math.sin(math.pi * t.clamp(0.0, 1.0));
        paint
          ..strokeWidth = width * scale * taper * (pass == 0 ? 1 : 0.7)
          ..color = _graphite.withAlpha(
              (255 * a * (0.75 + 0.25 * taper)).round().clamp(0, 255));
        var p0 = smooth[i] + shift;
        var p1 = smooth[i + 1] + shift;
        if (i == 0) p0 = p0 + (p0 - p1) * over * 8;
        if (i == smooth.length - 2) p1 = p1 + (p1 - p0) * over * 8;
        canvas.drawLine(p0, p1, paint);
      }
    }
  }

  void line(Offset a, Offset b,
      {double width = 1.4, double alpha = 0.85, int passes = 2}) {
    final bow = Offset(-(b - a).dy, (b - a).dx) * (_j(0.02) / scale);
    stroke(<Offset>[a, Offset.lerp(a, b, 0.5)! + bow, b],
        width: width, alpha: alpha, passes: passes);
  }

  /// A loose ellipse that does not quite close, drawn a little over once.
  void ellipse(Rect box,
      {double width = 1.4, double alpha = 0.85, int passes = 2}) {
    final start = r.nextDouble() * math.pi * 2;
    final sweep = math.pi * 2 * (1.05 + r.nextDouble() * 0.12);
    final points = <Offset>[];
    for (var i = 0; i <= 28; i++) {
      final a = start + sweep * i / 28;
      final wobble = 1 + _j(0.012) / scale;
      points.add(box.center +
          Offset(math.cos(a) * box.width / 2 * wobble,
              math.sin(a) * box.height / 2 * wobble));
    }
    stroke(points, width: width, alpha: alpha, passes: passes, jitter: 0.8);
  }

  void roundRect(Rect box, double radius,
      {double width = 1.4, double alpha = 0.85}) {
    path(
        Path()..addRRect(RRect.fromRectAndRadius(box, Radius.circular(radius))),
        width: width,
        alpha: alpha);
  }

  /// Traces any path as pencil strokes.
  void path(Path path, {double width = 1.4, double alpha = 0.85}) {
    for (final metric in path.computeMetrics()) {
      final points = <Offset>[];
      final steps = math.max(6, (metric.length / (6 * scale)).round());
      for (var i = 0; i <= steps; i++) {
        final tangent = metric.getTangentForOffset(metric.length * i / steps);
        if (tangent != null) points.add(tangent.position);
      }
      stroke(points, width: width, alpha: alpha);
    }
  }

  /// Parallel shading strokes at [angle] (radians), clipped to [area].
  void hatch(Path area,
      {double angle = 0.8, double spacing = 3, double alpha = 0.5}) {
    final bounds = area.getBounds();
    if (bounds.isEmpty) return;
    canvas.save();
    canvas.clipPath(area);
    final dir = Offset(math.cos(angle), math.sin(angle));
    final normal = Offset(-dir.dy, dir.dx);
    final reach = bounds.longestSide;
    final paint = Paint()..strokeCap = StrokeCap.round;
    final gap = spacing * scale;
    for (var d = -reach; d <= reach; d += gap * (0.8 + r.nextDouble() * 0.4)) {
      final mid = bounds.center + normal * d;
      final len = reach * (0.7 + r.nextDouble() * 0.5);
      paint
        ..strokeWidth = (0.6 + r.nextDouble() * 0.5) * scale
        ..color = _graphite
            .withAlpha((255 * alpha * (0.6 + r.nextDouble() * 0.4)).round());
      canvas.drawLine(
          mid - dir * len + Offset(_j(1), _j(1)), mid + dir * len, paint);
    }
    canvas.restore();
  }

  /// Catmull-Rom resample so a few control points give a smooth curve.
  List<Offset> _resample(List<Offset> pts) {
    if (pts.length == 2) {
      return List<Offset>.generate(
          12, (i) => Offset.lerp(pts[0], pts[1], i / 11)!);
    }
    final out = <Offset>[];
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[math.max(0, i - 1)];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[math.min(pts.length - 1, i + 2)];
      const steps = 8;
      for (var s = 0; s < steps; s++) {
        final t = s / steps;
        final t2 = t * t;
        final t3 = t2 * t;
        out.add((p1 * 2 +
                (p2 - p0) * t +
                (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 +
                (-p0 + p1 * 3 - p2 * 3 + p3) * t3) *
            0.5);
      }
    }
    out.add(pts.last);
    return out;
  }
}
