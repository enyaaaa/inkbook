import 'dart:typed_data';

import 'stroke.dart';

/// One page inside a sketchbook: an ordered list of strokes plus a cached
/// thumbnail captured the last time the page was left.
class SketchPage {
  SketchPage({required this.id, List<Stroke>? strokes, this.thumbnail})
      : strokes = strokes ?? <Stroke>[];

  final String id;
  final List<Stroke> strokes;

  /// PNG bytes of the last render of this page, used in the page strip and
  /// on sketchbook covers. Null until the page has been rendered once.
  Uint8List? thumbnail;

  bool get isBlank => strokes.isEmpty;
  int get strokeCount => strokes.length;
}
