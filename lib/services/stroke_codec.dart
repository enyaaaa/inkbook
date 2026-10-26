import 'dart:typed_data';
import 'dart:ui';

import '../models/brush.dart';
import '../models/stroke.dart';

/// Packs a page's strokes into a compact binary blob for storage, and back.
///
/// JSON would spend ~30 bytes per point on digits and punctuation; this
/// spends 12 (three float32s), so a busy page stays well under Firestore's
/// 1 MB document limit. Layout, little-endian:
///
///   u16 version, u32 strokeCount, then per stroke:
///     u8 brushType, u32 colour (ARGB), f32 size, f32 opacity,
///     u32 pointCount, then pointCount x (f32 x, f32 y, f32 pressure)
class StrokeCodec {
  const StrokeCodec._();

  static const int _version = 1;

  static Uint8List encode(List<Stroke> strokes) {
    var length = 2 + 4;
    for (final stroke in strokes) {
      length += 1 + 4 + 4 + 4 + 4 + stroke.points.length * 12;
    }
    final data = ByteData(length);
    var o = 0;
    data.setUint16(o, _version, Endian.little);
    o += 2;
    data.setUint32(o, strokes.length, Endian.little);
    o += 4;
    for (final stroke in strokes) {
      final brush = stroke.brush;
      data.setUint8(o, brush.type.index);
      o += 1;
      data.setUint32(o, brush.color.toARGB32(), Endian.little);
      o += 4;
      data.setFloat32(o, brush.size, Endian.little);
      o += 4;
      data.setFloat32(o, brush.opacity, Endian.little);
      o += 4;
      data.setUint32(o, stroke.points.length, Endian.little);
      o += 4;
      for (final p in stroke.points) {
        data.setFloat32(o, p.dx, Endian.little);
        data.setFloat32(o + 4, p.dy, Endian.little);
        data.setFloat32(o + 8, p.pressure, Endian.little);
        o += 12;
      }
    }
    return data.buffer.asUint8List();
  }

  static List<Stroke> decode(Uint8List bytes) {
    if (bytes.length < 6) return <Stroke>[];
    final data = ByteData.sublistView(bytes);
    var o = 0;
    final version = data.getUint16(o, Endian.little);
    o += 2;
    if (version != _version) return <Stroke>[];
    final count = data.getUint32(o, Endian.little);
    o += 4;
    final strokes = <Stroke>[];
    for (var s = 0; s < count; s++) {
      final typeIndex = data.getUint8(o);
      o += 1;
      final color = Color(data.getUint32(o, Endian.little));
      o += 4;
      final size = data.getFloat32(o, Endian.little);
      o += 4;
      final opacity = data.getFloat32(o, Endian.little);
      o += 4;
      final pointCount = data.getUint32(o, Endian.little);
      o += 4;
      final points = <StrokePoint>[];
      for (var i = 0; i < pointCount; i++) {
        points.add(StrokePoint(
          Offset(
            data.getFloat32(o, Endian.little),
            data.getFloat32(o + 4, Endian.little),
          ),
          data.getFloat32(o + 8, Endian.little),
        ));
        o += 12;
      }
      strokes.add(Stroke(
        brush: BrushSettings(
          type:
              BrushType.values[typeIndex.clamp(0, BrushType.values.length - 1)],
          color: color,
          size: size,
          opacity: opacity,
        ),
        points: points,
      ));
    }
    return strokes;
  }
}
