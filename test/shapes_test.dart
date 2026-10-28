import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:inkbook/models/brush.dart';
import 'package:inkbook/models/stroke.dart';
import 'package:inkbook/utils/shapes.dart';

Stroke _stroke(List<Offset> points) => Stroke(
      brush: const BrushSettings(),
      points: <StrokePoint>[for (final p in points) StrokePoint(p, 0.6)],
    );

void main() {
  test('a wobbly hand-drawn circle snaps to an ellipse', () {
    final points = <Offset>[
      for (var i = 0; i <= 60; i++)
        () {
          final a = i / 60 * math.pi * 2;
          final r = 75 + math.sin(i * 1.7) * 7;
          return Offset(630 + math.cos(a) * r * 1.25, 500 + math.sin(a) * r);
        }(),
    ];
    expect(Shapes.recognise(_stroke(points))?.$1, ShapeKind.ellipse);
  });

  test('a slightly shaky straight stroke snaps to a line', () {
    final points = <Offset>[
      for (var i = 0; i <= 40; i++)
        Offset(100 + i * 8.0, 200 + math.sin(i.toDouble()) * 3),
    ];
    expect(Shapes.recognise(_stroke(points))?.$1, ShapeKind.line);
  });

  test('a rough box snaps to a rectangle', () {
    final corners = <Offset>[
      const Offset(0, 0),
      const Offset(200, 3),
      const Offset(198, 120),
      const Offset(2, 118),
      const Offset(1, 2),
    ];
    final points = <Offset>[];
    for (var c = 0; c < corners.length - 1; c++) {
      for (var k = 0; k < 15; k++) {
        points.add(Offset.lerp(corners[c], corners[c + 1], k / 15)!);
      }
    }
    points.add(corners.last);
    expect(Shapes.recognise(_stroke(points))?.$1, ShapeKind.rectangle);
  });

  test('a scribble is left alone', () {
    final random = math.Random(3);
    final points = <Offset>[
      for (var i = 0; i < 50; i++)
        Offset(random.nextDouble() * 300, random.nextDouble() * 300),
    ];
    expect(Shapes.recognise(_stroke(points)), isNull);
  });
}
