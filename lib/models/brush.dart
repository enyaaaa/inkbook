import 'package:flutter/material.dart';

/// The drawing tools available on the INKBOOK canvas.
enum BrushType {
  pencil('Pencil', Icons.edit_outlined),
  ink('Ink Pen', Icons.create_outlined),
  marker('Marker', Icons.brush_outlined),
  eraser('Eraser', Icons.cleaning_services_outlined);

  const BrushType(this.label, this.icon);

  final String label;
  final IconData icon;

  bool get isEraser => this == BrushType.eraser;

  /// How strongly stylus pressure changes the stroke width for this tool.
  /// 0.0 = constant width, 1.0 = width is fully driven by pressure.
  double get pressureWidthResponse {
    switch (this) {
      case BrushType.pencil:
        return 0.75;
      case BrushType.ink:
        return 0.55;
      case BrushType.marker:
        return 0.25;
      case BrushType.eraser:
        return 0.10;
    }
  }

  /// How strongly stylus pressure changes the stroke opacity for this tool.
  double get pressureOpacityResponse {
    switch (this) {
      case BrushType.pencil:
        return 0.55;
      case BrushType.ink:
        return 0.15;
      case BrushType.marker:
        return 0.35;
      case BrushType.eraser:
        return 0.0;
    }
  }
}

/// An immutable snapshot of the brush settings used for a single stroke.
@immutable
class BrushSettings {
  const BrushSettings({
    this.type = BrushType.pencil,
    this.color = const Color(0xFF2B2622),
    this.size = 8.0,
    this.opacity = 1.0,
  });

  final BrushType type;
  final Color color;

  /// Maximum stroke width in logical pixels (reached at full pressure).
  final double size;
  final double opacity;

  BrushSettings copyWith({
    BrushType? type,
    Color? color,
    double? size,
    double? opacity,
  }) {
    return BrushSettings(
      type: type ?? this.type,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BrushSettings &&
      other.type == type &&
      other.color == color &&
      other.size == size &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(type, color, size, opacity);
}
