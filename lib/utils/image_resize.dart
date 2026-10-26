import 'dart:typed_data';
import 'dart:ui' as ui;

/// Scales a PNG down so it is at most [maxWidth] pixels wide, re-encoding
/// it as PNG. Images already small enough are returned untouched.
///
/// Used before images are written to the database: page captures are made
/// at 2x for crisp thumbnails on screen, which is far more than a feed card
/// or a page preview needs, and Firestore documents are capped at 1 MB.
///
/// Decodes with [ui.instantiateImageCodec] and redraws onto a smaller
/// canvas, both of which work on every platform including web
/// (`ImageDescriptor` does not).
Future<Uint8List> shrinkPng(Uint8List bytes, {int maxWidth = 640}) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final source = frame.image;
  codec.dispose();
  try {
    if (source.width <= maxWidth) return bytes;
    final scale = maxWidth / source.width;
    final height = (source.height * scale).round();

    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, maxWidth.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final scaled = await picture.toImage(maxWidth, height);
    picture.dispose();
    final data = await scaled.toByteData(format: ui.ImageByteFormat.png);
    scaled.dispose();
    return data?.buffer.asUint8List() ?? bytes;
  } finally {
    source.dispose();
  }
}
