import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The moodboard building blocks used across every screen: paper grain,
/// washi tape, polaroid frames, torn paper and round action buttons.
///
/// Everything is painted procedurally so the prototype still ships with no
/// image assets.

/// Fills its area with [color] plus a fine speckled grain, like the dust and
/// fibres on a scanned sheet of paper.
class GrainSurface extends StatelessWidget {
  const GrainSurface({
    super.key,
    required this.color,
    this.grain = const Color(0xFFFFFFFF),
    this.density = 1.0,
    this.child,
  });

  final Color color;
  final Color grain;
  final double density;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _GrainPainter(color, grain, density),
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter(this.color, this.grain, this.density);

  final Color color;
  final Color grain;
  final double density;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = color);

    // Soft vignette so flat colour feels like a lit surface.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.4),
          radius: 1.2,
          colors: <Color>[
            Colors.white.withAlpha(14),
            Colors.black.withAlpha(30)
          ],
        ).createShader(rect),
    );

    final random = math.Random(11);
    final count = (size.width * size.height / 900 * density).clamp(0, 9000);
    final speck = Paint();
    for (var i = 0; i < count; i++) {
      final light = random.nextBool();
      speck.color = (light ? grain : Colors.black)
          .withAlpha(6 + random.nextInt(light ? 22 : 16));
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        0.3 + random.nextDouble() * 0.9,
        speck,
      );
    }

    // A few longer fibres / scratches.
    final fibre = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count / 140; i++) {
      final start = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final angle = random.nextDouble() * math.pi * 2;
      final length = 4 + random.nextDouble() * 14;
      fibre.color = grain.withAlpha(18 + random.nextInt(20));
      canvas.drawLine(
        start,
        start + Offset(math.cos(angle), math.sin(angle)) * length,
        fibre,
      );
    }
  }

  @override
  bool shouldRepaint(_GrainPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.grain != grain ||
      oldDelegate.density != density;
}

/// A strip of washi tape with torn, zig-zag ends.
class WashiTape extends StatelessWidget {
  const WashiTape({
    super.key,
    this.color = const Color(0xCCE8C9A0),
    this.width = 74,
    this.height = 22,
    this.angle = 0,
    this.label,
  });

  final Color color;
  final double width;
  final double height;
  final double angle;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: CustomPaint(
        painter: _TapePainter(color),
        child: SizedBox(
          width: width,
          height: height,
          child: label == null
              ? null
              : Center(
                  child: Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: InkbookType.handwritten(size: 13),
                  ),
                ),
        ),
      ),
    );
  }
}

class _TapePainter extends CustomPainter {
  const _TapePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const tooth = 3.0;
    final path = Path()..moveTo(tooth, 0);
    path.lineTo(size.width - tooth, 0);
    var y = 0.0;
    var out = true;
    while (y < size.height) {
      y = math.min(y + tooth, size.height);
      path.lineTo(out ? size.width : size.width - tooth, y);
      out = !out;
    }
    path.lineTo(tooth, size.height);
    y = size.height;
    out = true;
    while (y > 0) {
      y = math.max(y - tooth, 0);
      path.lineTo(out ? 0 : tooth, y);
      out = !out;
    }
    path.close();

    canvas.drawShadow(path, Colors.black.withAlpha(60), 1.5, false);
    canvas.drawPath(path, Paint()..color = color);
    // Faint stripes printed on the tape.
    canvas.save();
    canvas.clipPath(path);
    final stripe = Paint()..color = Colors.white.withAlpha(36);
    for (var x = -size.height; x < size.width; x += 9) {
      canvas.drawPath(
        Path()
          ..moveTo(x, size.height)
          ..lineTo(x + size.height, 0)
          ..lineTo(x + size.height + 3, 0)
          ..lineTo(x + 3, size.height)
          ..close(),
        stripe,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TapePainter oldDelegate) => oldDelegate.color != color;
}

/// A white instant-photo frame with a thicker bottom edge for a caption.
class Polaroid extends StatelessWidget {
  const Polaroid({
    super.key,
    required this.child,
    this.caption,
    this.captionTrailing,
    this.padding = 9,
  });

  final Widget child;
  final String? caption;
  final Widget? captionTrailing;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(padding, padding, padding, 0),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFBF6),
        borderRadius: BorderRadius.circular(2),
        boxShadow: paperShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: ClipRect(child: child)),
          SizedBox(
            height: caption == null ? padding * 3 : 44,
            child: caption == null
                ? null
                : Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          caption!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: InkbookType.body(
                            size: 13,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (captionTrailing != null) captionTrailing!,
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// The soft, slightly offset shadow of paper lying on a desk.
List<BoxShadow> paperShadow({double lift = 1}) => <BoxShadow>[
      BoxShadow(
        color: Colors.black.withAlpha((40 * lift).round().clamp(0, 255)),
        blurRadius: 3 * lift,
        offset: Offset(0, 1.5 * lift),
      ),
      BoxShadow(
        color: Colors.black.withAlpha((34 * lift).round().clamp(0, 255)),
        blurRadius: 18 * lift,
        offset: Offset(2 * lift, 10 * lift),
      ),
    ];

/// Clips its child to a sheet with a ragged, hand-torn bottom (and
/// optionally top) edge.
class TornPaper extends StatelessWidget {
  const TornPaper({
    super.key,
    required this.child,
    this.color = InkbookColors.paper,
    this.seed = 1,
    this.tornTop = false,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 22),
  });

  final Widget child;
  final Color color;
  final int seed;
  final bool tornTop;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final clipper = _TornClipper(seed, tornTop);
    return CustomPaint(
      painter: _TornShadowPainter(clipper),
      child: ClipPath(
        clipper: clipper,
        child: GrainSurface(
          color: color,
          grain: InkbookColors.inkSoft,
          density: 0.5,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _TornClipper extends CustomClipper<Path> {
  const _TornClipper(this.seed, this.tornTop);

  final int seed;
  final bool tornTop;

  Path _edge(Path path, Size size, double baseY, bool forward, math.Random r) {
    const step = 7.0;
    if (forward) {
      for (var x = 0.0; x <= size.width; x += step) {
        path.lineTo(x, baseY + (r.nextDouble() - 0.5) * 5);
      }
      path.lineTo(size.width, baseY);
    } else {
      for (var x = size.width; x >= 0; x -= step) {
        path.lineTo(x, baseY + (r.nextDouble() - 0.5) * 5);
      }
      path.lineTo(0, baseY);
    }
    return path;
  }

  @override
  Path getClip(Size size) {
    final r = math.Random(seed);
    final path = Path();
    if (tornTop) {
      path.moveTo(0, 4);
      _edge(path, size, 4, true, r);
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0);
    }
    path.lineTo(size.width, size.height - 4);
    _edge(path, size, size.height - 4, false, r);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_TornClipper oldClipper) =>
      oldClipper.seed != seed || oldClipper.tornTop != tornTop;
}

class _TornShadowPainter extends CustomPainter {
  const _TornShadowPainter(this.clipper);

  final _TornClipper clipper;

  @override
  void paint(Canvas canvas, Size size) {
    final path = clipper.getClip(size);
    canvas.drawShadow(
        path.shift(const Offset(1, 2)), Colors.black.withAlpha(120), 6, false);
  }

  @override
  bool shouldRepaint(_TornShadowPainter oldDelegate) => false;
}

/// The circular action buttons that sit under the sketchbook shelf.
class RoundAction extends StatelessWidget {
  const RoundAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.dark = false,
    this.size = 46,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool dark;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final background = active
        ? InkbookColors.toolYellow
        : dark
            ? InkbookColors.tray
            : const Color(0xFFFDFBF6);
    final foreground = active
        ? InkbookColors.ink
        : dark
            ? InkbookColors.folderCream
            : InkbookColors.ink;
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          elevation: dark ? 0 : 3,
          shadowColor: Colors.black54,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: size * 0.43, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small outlined circle button for the top corners of a screen - the
/// thin-ringed icons in the reference moodboards.
class RingButton extends StatelessWidget {
  const RingButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = InkbookColors.folderCream,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? color.withAlpha(36) : Colors.transparent,
            border: Border.all(
              color:
                  color.withAlpha(onTap == null ? 40 : (selected ? 220 : 90)),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: color.withAlpha(onTap == null ? 70 : 255),
          ),
        ),
      ),
    );
  }
}

/// A deterministic small tilt for scattered scraps, in radians.
double scrapTilt(int seed, {double max = 0.045}) {
  final r = math.Random(seed);
  return (r.nextDouble() * 2 - 1) * max;
}

/// A deterministic tape colour for a scrap.
Color scrapTape(int seed) =>
    InkbookColors.tapes[seed.abs() % InkbookColors.tapes.length];

/// A simple masonry layout: items are dropped into whichever column is
/// currently shortest, so pieces of different shapes pack like a pinboard.
///
/// [heightOf] returns an item's height for a given column width. Builds all
/// children eagerly, which is fine for feed- and board-sized lists.
class Masonry extends StatelessWidget {
  const Masonry({
    super.key,
    required this.itemCount,
    required this.heightOf,
    required this.itemBuilder,
    this.maxColumnWidth = 280,
    this.spacing = 28,
    this.runSpacing = 34,
  });

  final int itemCount;
  final double Function(int index, double columnWidth) heightOf;
  final IndexedWidgetBuilder itemBuilder;
  final double maxColumnWidth;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = math.max(
            1, ((width + spacing) / (maxColumnWidth + spacing)).ceil());
        final columnWidth = (width - spacing * (columns - 1)) / columns;
        final heights = List<double>.filled(columns, 0);
        final buckets = List<List<Widget>>.generate(columns, (_) => <Widget>[]);

        for (var i = 0; i < itemCount; i++) {
          var target = 0;
          for (var c = 1; c < columns; c++) {
            if (heights[c] < heights[target] - 1) target = c;
          }
          final h = heightOf(i, columnWidth);
          if (buckets[target].isNotEmpty) {
            buckets[target].add(SizedBox(height: runSpacing));
          }
          buckets[target].add(
            SizedBox(
                width: columnWidth, height: h, child: itemBuilder(context, i)),
          );
          heights[target] += h + runSpacing;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var c = 0; c < columns; c++) ...<Widget>[
              if (c > 0) SizedBox(width: spacing),
              SizedBox(
                width: columnWidth,
                child: Column(children: buckets[c]),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The heading every screen opens with, after the reference boards: a bold
/// centred title, a small icon + caps subtitle under it, an optional
/// handwritten aside, and ring buttons in the top corners.
class ScrapHeading extends StatelessWidget {
  const ScrapHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    this.aside,
    this.leading,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData? icon;
  final String? aside;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final wide = InkbookLayout.isWide(context);
    final muted = InkbookColors.ink.withAlpha(170);

    final heading = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: InkbookType.title(size: wide ? 34 : 26),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 14, color: muted),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                subtitle.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: InkbookType.eyebrow(color: muted),
              ),
            ),
          ],
        ),
        if (aside != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              aside!,
              textAlign: TextAlign.center,
              style: InkbookType.handwritten(size: 16, color: muted),
            ),
          ),
      ],
    );

    final corners = Row(
      children: <Widget>[
        leading ?? const SizedBox.shrink(),
        const Spacer(),
        trailing ?? const SizedBox.shrink(),
      ],
    );

    if (leading == null && trailing == null) return Center(child: heading);
    if (!wide) {
      return Column(
        children: <Widget>[corners, const SizedBox(height: 4), heading],
      );
    }
    return Stack(
      alignment: Alignment.topCenter,
      children: <Widget>[
        const SizedBox(width: double.infinity),
        Positioned.fill(
            child: Align(alignment: Alignment.topCenter, child: corners)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 110),
          child: heading,
        ),
      ],
    );
  }
}
