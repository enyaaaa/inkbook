import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../controllers/sketchbook_controller.dart';
import '../../../models/brush.dart';
import '../../../models/stroke.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/shapes.dart';
import '../../../utils/stroke_geometry.dart';
import 'canvas_painters.dart';

/// The dark tool tray along the bottom of the canvas, after Paper by
/// FiftyThree: colour swatches, the tools drawn as real objects (the
/// selected one slides up), and size / opacity with a live pressure preview.
class ToolTray extends StatelessWidget {
  const ToolTray({super.key, required this.controller});

  final SketchbookController controller;

  static const double height = 118;

  @override
  Widget build(BuildContext context) {
    final brush = controller.brush;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        const SizedBox(width: 20),
        _Palette(selected: brush.color, onSelected: controller.setColor),
        const SizedBox(width: 26),
        for (final type in BrushType.values)
          _Tool(
            label: type.label,
            selected: controller.tool == CanvasTool.draw && brush.type == type,
            painter: _ToolPainter(
              type,
              brush.color,
              controller.tool == CanvasTool.draw && brush.type == type,
            ),
            onTap: () {
              controller.setBrushType(type);
              controller.setTool(CanvasTool.draw);
            },
          ),
        const SizedBox(width: 10),
        _Tool(
          label: 'Shapes (${controller.shape.label.toLowerCase()})',
          selected: controller.tool == CanvasTool.shape,
          painter: _StencilPainter(controller.shape),
          onTap: () => controller.setTool(CanvasTool.shape),
        ),
        _Tool(
          label: 'Select - lasso strokes to move, resize, rotate',
          selected: controller.tool == CanvasTool.select,
          painter: const _LassoPainter(),
          onTap: () => controller.setTool(CanvasTool.select),
        ),
        if (controller.tool == CanvasTool.shape) ...<Widget>[
          const SizedBox(width: 6),
          _ShapeChoices(controller: controller),
        ],
        const SizedBox(width: 26),
        _BrushPreview(brush: brush),
        const SizedBox(width: 14),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _TraySlider(
              label: 'SIZE  ${brush.size.round()}',
              value: brush.size,
              min: 1,
              max: 60,
              onChanged: controller.setSize,
            ),
            _TraySlider(
              label: 'FLOW  ${(brush.opacity * 100).round()}%',
              value: brush.opacity,
              min: 0.05,
              max: 1.0,
              onChanged: controller.setOpacity,
            ),
          ],
        ),
        const SizedBox(width: 20),
      ],
    );

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: InkbookColors.tray,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withAlpha(70),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        child: wide
            ? Center(child: content)
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: content,
              ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({
    required this.label,
    required this.selected,
    required this.painter,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final CustomPainter painter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 70,
          height: ToolTray.height,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: <Widget>[
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                left: 9,
                right: 9,
                top: selected ? 6 : 30,
                height: 140,
                child: CustomPaint(painter: painter),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints each tool as a flat illustration with its signature colour.
class _ToolPainter extends CustomPainter {
  const _ToolPainter(this.type, this.ink, this.selected);

  final BrushType type;
  final Color ink;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final shade = Paint()..color = Colors.black.withAlpha(40);

    switch (type) {
      case BrushType.pencil:
        const body = InkbookColors.toolOrange;
        final top = 34.0;
        canvas.drawRect(
            Rect.fromLTWH(6, top, w - 12, size.height), Paint()..color = body);
        // Facets.
        for (final x in <double>[w * 0.38, w * 0.62]) {
          canvas.drawLine(
            Offset(x, top + 4),
            Offset(x, size.height),
            Paint()
              ..color = Colors.black.withAlpha(45)
              ..strokeWidth = 1.2,
          );
        }
        // Sharpened wood.
        final wood = Path()
          ..moveTo(6, top)
          ..quadraticBezierTo(w * 0.3, top + 4, w * 0.5, 0)
          ..quadraticBezierTo(w * 0.7, top + 4, w - 6, top)
          ..close();
        canvas.drawPath(wood, Paint()..color = const Color(0xFFE9CDA4));
        // Scalloped edge where the paint was shaved off.
        final scallop = Path()..moveTo(6, top);
        for (var i = 0; i < 3; i++) {
          final x0 = 6 + (w - 12) * i / 3;
          final x1 = 6 + (w - 12) * (i + 1) / 3;
          scallop.quadraticBezierTo((x0 + x1) / 2, top - 7, x1, top);
        }
        scallop
          ..lineTo(w - 6, top + 3)
          ..lineTo(6, top + 3)
          ..close();
        canvas.drawPath(scallop, Paint()..color = body);
        final lead = Path()
          ..moveTo(w * 0.4, 12)
          ..lineTo(w * 0.5, 0)
          ..lineTo(w * 0.6, 12)
          ..close();
        canvas.drawPath(lead, Paint()..color = ink);
        canvas.drawRect(Rect.fromLTWH(w - 12, top, 6, size.height), shade);
      case BrushType.ink:
        const body = InkbookColors.toolYellow;
        final grip = 46.0;
        canvas.drawRRect(
          RRect.fromLTRBR(
              6, grip + 14, w - 6, size.height, const Radius.circular(4)),
          Paint()..color = body,
        );
        canvas.drawRect(
          Rect.fromLTWH(8, grip, w - 16, 18),
          Paint()..color = const Color(0xFF3A3632),
        );
        // Nib.
        final nib = Path()
          ..moveTo(w * 0.22, grip + 2)
          ..cubicTo(w * 0.2, grip - 18, w * 0.42, grip - 30, w * 0.5, 0)
          ..cubicTo(w * 0.58, grip - 30, w * 0.8, grip - 18, w * 0.78, grip + 2)
          ..close();
        canvas.drawPath(nib, Paint()..color = const Color(0xFFF4EFE6));
        canvas.drawPath(
          nib,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = InkbookColors.ink,
        );
        canvas.drawCircle(
            Offset(w * 0.5, grip - 18), 3, Paint()..color = InkbookColors.ink);
        canvas.drawLine(
          Offset(w * 0.5, 2),
          Offset(w * 0.5, grip - 18),
          Paint()
            ..color = ink
            ..strokeWidth = 1.6,
        );
        canvas.drawRect(
            Rect.fromLTWH(w - 12, grip + 14, 6, size.height), shade);
      case BrushType.marker:
        const body = InkbookColors.toolTeal;
        final top = 40.0;
        canvas.drawRRect(
          RRect.fromLTRBR(2, top, w - 2, size.height, const Radius.circular(3)),
          Paint()..color = body,
        );
        final cone = Path()
          ..moveTo(4, top)
          ..lineTo(w * 0.24, 14)
          ..lineTo(w * 0.76, 14)
          ..lineTo(w - 4, top)
          ..close();
        canvas.drawPath(cone, Paint()..color = const Color(0xFF2F3436));
        final tip = Path()
          ..moveTo(w * 0.3, 14)
          ..lineTo(w * 0.36, 0)
          ..lineTo(w * 0.7, 6)
          ..lineTo(w * 0.7, 14)
          ..close();
        canvas.drawPath(tip, Paint()..color = ink);
        canvas.drawRect(Rect.fromLTWH(2, top + 30, w - 4, 6),
            Paint()..color = Colors.white.withAlpha(60));
        canvas.drawRect(Rect.fromLTWH(w - 9, top, 7, size.height), shade);
      case BrushType.eraser:
        const body = Color(0xFFE6A9A6);
        final top = 16.0;
        canvas.drawRRect(
          RRect.fromLTRBAndCorners(
            4,
            top,
            w - 4,
            size.height,
            topLeft: const Radius.circular(10),
            topRight: const Radius.circular(10),
          ),
          Paint()..color = body,
        );
        canvas.drawRect(
          Rect.fromLTWH(4, top + 40, w - 8, size.height),
          Paint()..color = InkbookColors.toolPurple,
        );
        canvas.drawRect(
          Rect.fromLTWH(4, top + 40, w - 8, 3),
          Paint()..color = Colors.white.withAlpha(90),
        );
        canvas.drawRect(Rect.fromLTWH(w - 10, top + 6, 6, size.height), shade);
    }

    if (selected) {
      canvas.drawCircle(
        Offset(w / 2, size.height - 52),
        3,
        Paint()..color = Colors.white.withAlpha(200),
      );
    }
  }

  @override
  bool shouldRepaint(_ToolPainter oldDelegate) =>
      oldDelegate.type != type ||
      oldDelegate.ink != ink ||
      oldDelegate.selected != selected;
}

/// The shape tool: a drawing stencil with line, square and circle cut-outs.
class _StencilPainter extends CustomPainter {
  const _StencilPainter(this.shape);

  final ShapeKind shape;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final body =
        RRect.fromLTRBR(2, 4, w - 2, size.height, const Radius.circular(6));
    canvas.drawRRect(body, Paint()..color = InkbookColors.folderLavender);
    canvas.drawRect(
      Rect.fromLTWH(w - 8, 10, 6, size.height),
      Paint()..color = Colors.black.withAlpha(35),
    );
    final hole = Paint()..color = InkbookColors.tray;
    final active = Paint()..color = InkbookColors.folderCream;
    final cx = w / 2;
    // Circle, square and slot cut-outs; the current shape's is lit.
    canvas.drawCircle(
        Offset(cx, 22), 9, shape == ShapeKind.ellipse ? active : hole);
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, 46), width: 16, height: 16),
      shape == ShapeKind.rectangle ? active : hole,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, 68), width: 26, height: 5),
        const Radius.circular(3),
      ),
      shape == ShapeKind.line ? active : hole,
    );
  }

  @override
  bool shouldRepaint(_StencilPainter oldDelegate) => oldDelegate.shape != shape;
}

/// The select tool: a loop of rope (a lasso) on a handle.
class _LassoPainter extends CustomPainter {
  const _LassoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    canvas.drawRRect(
      RRect.fromLTRBR(
          w * 0.38, 40, w * 0.62, size.height, const Radius.circular(3)),
      Paint()..color = InkbookColors.toolBrown,
    );
    final rope = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = InkbookColors.toolYellow;
    canvas.drawOval(Rect.fromLTWH(4, 2, w - 8, 30), rope);
    canvas.drawLine(Offset(w * 0.5, 32), Offset(w * 0.5, 42), rope);
  }

  @override
  bool shouldRepaint(_LassoPainter oldDelegate) => false;
}

/// Line / rectangle / ellipse buttons, shown while the shape tool is on.
class _ShapeChoices extends StatelessWidget {
  const _ShapeChoices({required this.controller});

  final SketchbookController controller;

  @override
  Widget build(BuildContext context) {
    Widget choice(ShapeKind kind, IconData icon) {
      final on = controller.shape == kind;
      return Tooltip(
        message: kind.label,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => controller.setShape(kind),
          child: Container(
            width: 34,
            height: 30,
            margin: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color:
                  on ? InkbookColors.folderCream : Colors.white.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: on ? InkbookColors.ink : InkbookColors.folderCream,
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        choice(ShapeKind.line, Icons.horizontal_rule),
        choice(ShapeKind.rectangle, Icons.crop_square),
        choice(ShapeKind.ellipse, Icons.circle_outlined),
      ],
    );
  }
}

/// Shows how the current brush responds to pressure, from light on the left
/// to full pressure on the right.
class _BrushPreview extends StatelessWidget {
  const _BrushPreview({required this.brush});

  final BrushSettings brush;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 60,
      child: CustomPaint(painter: _PreviewPainter(brush)),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  const _PreviewPainter(this.brush);

  final BrushSettings brush;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      Paint()..color = InkbookColors.paper,
    );

    // A real sample stroke, light to heavy pressure, drawn by the same
    // engine as the canvas - so pencil grain and tilt shading show here too.
    const steps = 40;
    final points = <StrokePoint>[
      for (var i = 0; i <= steps; i++)
        StrokePoint(
          Offset(
            10 + (size.width - 20) * (i / steps),
            size.height / 2 + math.sin(i / steps * math.pi * 2) * 6,
          ),
          i / steps,
        ),
    ];
    if (brush.type.isEraser) {
      canvas.drawPath(
        StrokeGeometry.buildOutline(Stroke(brush: brush, points: points)),
        Paint()..color = InkbookColors.inkSoft.withAlpha(90),
      );
    } else {
      paintStroke(
        canvas,
        Stroke(
          brush: brush.copyWith(size: brush.size.clamp(1.0, 22.0)),
          points: points,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter oldDelegate) => oldDelegate.brush != brush;
}

class _TraySlider extends StatelessWidget {
  const _TraySlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 44,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              label,
              style: InkbookType.eyebrow(
                color: InkbookColors.folderCream.withAlpha(170),
              ),
            ),
          ),
          SizedBox(
            height: 28,
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _Palette extends StatelessWidget {
  const _Palette({required this.selected, required this.onSelected});

  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 6 * 30,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final color in InkbookColors.palette)
            GestureDetector(
              onTap: () => onSelected(color),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color == selected
                        ? InkbookColors.folderCream
                        : Colors.white.withAlpha(30),
                    width: color == selected ? 2.5 : 1,
                  ),
                  boxShadow: color == selected
                      ? <BoxShadow>[
                          BoxShadow(
                            color: color.withAlpha(150),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
