import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// The paper "tooth" that pencil strokes are textured with.
///
/// A real pencil only deposits graphite on the raised fibres of the paper,
/// so a light stroke is broken and grainy while a heavy one fills in. This
/// generates a small tileable alpha texture once at start-up; the stroke
/// painter masks pencil strokes with it (fixed to the page, not the stroke,
/// so overlapping strokes share the same grain like on real paper).
class PencilGrain {
  const PencilGrain._();

  static const int _size = 128;
  static ui.Image? _image;
  static Future<void>? _loading;

  /// Null until [load] has finished; strokes draw untextured until then.
  static ui.Image? get image => _image;

  static Future<void> load() => _loading ??= _generate();

  static Future<void> _generate() async {
    final random = math.Random(7);
    // Value noise: random cells, blurred a little so the grain reads as
    // paper fibres rather than per-pixel static.
    final raw =
        List<double>.generate(_size * _size, (_) => random.nextDouble());
    double at(int x, int y) => raw[(y % _size) * _size + (x % _size)];

    final pixels = Uint8List(_size * _size * 4);
    for (var y = 0; y < _size; y++) {
      for (var x = 0; x < _size; x++) {
        // Slightly stretched horizontally, like laid paper.
        final v = (at(x, y) * 2 +
                at(x + 1, y) +
                at(x - 1, y) +
                at(x, y + 1) * 0.5 +
                at(x, y - 1) * 0.5) /
            5;
        // Map to alpha 90..255: never fully transparent, so strokes stay
        // continuous, but light enough in the gaps to look like graphite.
        final alpha = (90 + 165 * math.pow(v, 0.8)).round().clamp(0, 255);
        final i = (y * _size + x) * 4;
        pixels[i] = 255;
        pixels[i + 1] = 255;
        pixels[i + 2] = 255;
        pixels[i + 3] = alpha;
      }
    }

    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      _size,
      _size,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    _image = await done.future;
  }
}
