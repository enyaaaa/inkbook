import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../controllers/sketchbook_controller.dart';
import '../../../models/sketchbook.dart';
import '../../../models/stroke.dart';
import '../../../utils/pressure.dart';
import '../../../utils/stroke_geometry.dart';
import 'canvas_painters.dart';

/// Where the infinite whiteboard is looking: board-to-screen is
/// `screen = board * zoom + pan`.
class BoardView extends ChangeNotifier {
  Offset _pan = Offset.zero;
  double _zoom = 1;
  bool _hand = false;
  Size _viewport = Size.zero;

  static const double minZoom = 0.1;
  static const double maxZoom = 8;

  Offset get pan => _pan;
  double get zoom => _zoom;

  /// When on, the primary pointer pans instead of drawing.
  bool get hand => _hand;
  set hand(bool value) {
    if (value == _hand) return;
    _hand = value;
    notifyListeners();
  }

  Offset toBoard(Offset screen) => (screen - _pan) / _zoom;

  void panBy(Offset delta) {
    if (delta == Offset.zero) return;
    _pan += delta;
    notifyListeners();
  }

  /// Zooms to [zoom], keeping the board point under [focal] in place.
  void zoomTo(double zoom, {Offset? focal}) {
    final next = zoom.clamp(minZoom, maxZoom);
    final anchor = focal ?? _viewport.center(Offset.zero);
    final board = toBoard(anchor);
    _zoom = next;
    _pan = anchor - board * next;
    notifyListeners();
  }

  void zoomBy(double factor, {Offset? focal}) =>
      zoomTo(_zoom * factor, focal: focal);

  /// Back to 100% with the board origin in the top-left corner.
  void reset() {
    _pan = Offset.zero;
    _zoom = 1;
    notifyListeners();
  }
}

/// The drawing surface.
///
/// Uses a raw [Listener] rather than a [GestureDetector] because gesture
/// recognisers only report position - pressure, tilt and the device kind are
/// available on the pointer events themselves, and all three matter here.
class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({
    super.key,
    required this.controller,
    required this.paper,
    required this.repaintKey,
    this.board,
  });

  final SketchbookController controller;
  final PaperStyle paper;

  /// Set for the infinite whiteboard: the canvas then pans and zooms.
  final BoardView? board;

  /// Wraps the canvas so the page can be exported to PNG.
  final GlobalKey repaintKey;

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

enum _Drag { none, lasso, move, scale, rotate }

class _DrawingCanvasState extends State<DrawingCanvas> {
  final PressureNormaliser _pressure = PressureNormaliser();
  final StrokeCache _cache = StrokeCache();
  int? _activePointer;

  // Whiteboard navigation.
  final Map<int, Offset> _touches = <int, Offset>{};
  int? _panPointer;
  double _lastPinchScale = 1;

  // Hold-to-snap (draw tool): pausing at the end of a stroke tidies it
  // into a perfect line, ellipse or rectangle.
  static const Duration _holdToSnap = Duration(milliseconds: 600);
  Timer? _holdTimer;
  bool _snapped = false;

  // Shape tool.
  Offset? _shapeFrom;

  // Select tool.
  _Drag _drag = _Drag.none;
  List<Offset>? _lasso;
  Offset _last = Offset.zero;
  Offset _anchor = Offset.zero;
  double _lastDistance = 1;
  double _lastAngle = 0;

  static const double _handleRadius = 9;
  static const double _rotateOffset = 30;

  SketchbookController get _controller => widget.controller;
  BoardView? get _board => widget.board;

  Offset _toBoard(Offset local) => _board?.toBoard(local) ?? local;
  Offset _toScreen(Offset board) {
    final b = _board;
    return b == null ? board : board * b.zoom + b.pan;
  }

  bool _isTouch(PointerEvent e) => e.kind == PointerDeviceKind.touch;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _cache.dispose();
    super.dispose();
  }

  void _reportInput(PointerEvent event) {
    final kind = switch (event.kind) {
      PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => 'PEN',
      PointerDeviceKind.touch => 'TOUCH',
      PointerDeviceKind.mouse => 'MOUSE',
      PointerDeviceKind.trackpad => 'TRACKPAD',
      _ => 'POINTER',
    };
    _controller.reportInput(
      _pressure.deviceSupportsPressure
          ? '$kind · PRESSURE ${_pressure.rawPressure.toStringAsFixed(2)}'
          : '$kind · NO PRESSURE (SIMULATED)',
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    final board = _board;
    if (board != null) {
      if (_isTouch(event)) {
        _touches[event.pointer] = event.localPosition;
        // A second finger means "navigate": drop the stroke it started.
        if (_touches.length >= 2) {
          if (_activePointer != null) {
            _activePointer = null;
            _pressure.end();
            _holdTimer?.cancel();
            _controller.cancelStroke();
          }
          _panPointer = null;
          return;
        }
        // With a stylus in play, one finger pans the board.
        if (_controller.stylusDetected) {
          _panPointer = event.pointer;
          return;
        }
      }
      if (board.hand ||
          event.buttons == kMiddleMouseButton ||
          event.buttons == kSecondaryMouseButton) {
        _panPointer = event.pointer;
        return;
      }
    }

    // Ignore a second finger mid-stroke: it is almost always the hand resting
    // on the tablet, not a deliberate second mark.
    if (_activePointer != null) return;
    if (_isTouch(event) && _controller.stylusDetected) {
      // Once a stylus has been seen, treat touch as palm rejection.
      return;
    }
    _activePointer = event.pointer;
    final at = _toBoard(event.localPosition);

    switch (_controller.tool) {
      case CanvasTool.select:
        _selectDown(event.localPosition, at);
      case CanvasTool.shape:
        _pressure.begin(event);
        _reportInput(event);
        _shapeFrom = at;
        _controller.beginStroke(
          StrokePoint(at, 0.6),
          fromStylus: event.kind == PointerDeviceKind.stylus,
          sizeScale: board == null ? 1 : 1 / board.zoom,
        );
      case CanvasTool.draw:
        _pressure.begin(event);
        _reportInput(event);
        _snapped = false;
        _controller.beginStroke(
          StrokePoint(at, _pressure.current, tilt: event.tilt),
          fromStylus: event.kind == PointerDeviceKind.stylus,
          sizeScale: board == null ? 1 : 1 / board.zoom,
        );
        _armSnap();
    }
  }

  void _armSnap() {
    _holdTimer?.cancel();
    final pointer = _activePointer;
    _holdTimer = Timer(_holdToSnap, () {
      if (_activePointer != pointer || _snapped) return;
      if (_controller.snapLiveStroke()) setState(() => _snapped = true);
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    final board = _board;
    if (board != null) {
      if (_touches.containsKey(event.pointer) && _touches.length >= 2) {
        _pinch(event);
        return;
      }
      if (_touches.containsKey(event.pointer)) {
        _touches[event.pointer] = event.localPosition;
      }
      if (event.pointer == _panPointer) {
        board.panBy(event.delta);
        return;
      }
    }

    if (event.pointer != _activePointer) return;
    final at = _toBoard(event.localPosition);

    switch (_controller.tool) {
      case CanvasTool.select:
        _selectMove(at);
        return;
      case CanvasTool.shape:
        final from = _shapeFrom;
        if (from != null) _controller.shapeTo(from, at);
        return;
      case CanvasTool.draw:
        if (_snapped) return; // the snapped shape stays put
        final live = _controller.liveStroke;
        if (live == null) return;
        final pressure = _pressure.update(event);
        _reportInput(event);
        final last = live.points.isEmpty ? null : live.points.last;
        // Sample spacing is judged on screen, so zooming in still gives
        // smooth strokes.
        final lastOnScreen = last == null || board == null
            ? last
            : StrokePoint(last.offset * board.zoom + board.pan, last.pressure);
        if (!StrokeGeometry.shouldSample(lastOnScreen, event.localPosition)) {
          return; // holding still: let the snap timer run
        }
        _controller.extendStroke(
          StrokePoint(at, pressure, tilt: event.tilt),
        );
        _armSnap();
    }
  }

  void _onPointerUp(PointerEvent event) {
    _touches.remove(event.pointer);
    if (event.pointer == _panPointer) _panPointer = null;
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _holdTimer?.cancel();

    switch (_controller.tool) {
      case CanvasTool.select:
        _selectUp();
      case CanvasTool.shape:
        _shapeFrom = null;
        _pressure.end();
        _controller.endStroke();
      case CanvasTool.draw:
        _pressure.end();
        _controller.endStroke();
        if (_snapped) {
          // Leave the "snapped" hint up for a moment.
          Future<void>.delayed(const Duration(milliseconds: 900), () {
            if (mounted) setState(() => _snapped = false);
          });
        }
    }
  }

  // --- select tool ---------------------------------------------------------

  /// The selection's box on screen, a little padded.
  Rect? get _selectionOnScreen {
    final bounds = _controller.selectionBounds;
    if (bounds == null) return null;
    return Rect.fromPoints(
            _toScreen(bounds.topLeft), _toScreen(bounds.bottomRight))
        .inflate(6);
  }

  void _selectDown(Offset local, Offset at) {
    final box = _selectionOnScreen;
    final bounds = _controller.selectionBounds;
    if (box != null && bounds != null) {
      final rotateHandle = box.topCenter - const Offset(0, _rotateOffset);
      if ((local - rotateHandle).distance < _handleRadius * 2) {
        _drag = _Drag.rotate;
        _anchor = bounds.center;
        _lastAngle = (at - _anchor).direction;
        _controller.beginTransform();
        return;
      }
      final corners = <(Offset, Offset)>[
        (box.topLeft, bounds.bottomRight),
        (box.topRight, bounds.bottomLeft),
        (box.bottomLeft, bounds.topRight),
        (box.bottomRight, bounds.topLeft),
      ];
      for (final (corner, opposite) in corners) {
        if ((local - corner).distance < _handleRadius * 2) {
          _drag = _Drag.scale;
          _anchor = opposite;
          _lastDistance = math.max((at - _anchor).distance, 1);
          _controller.beginTransform();
          return;
        }
      }
      if (box.contains(local)) {
        _drag = _Drag.move;
        _last = at;
        _controller.beginTransform();
        return;
      }
    }
    _controller.clearSelection();
    _drag = _Drag.lasso;
    setState(() => _lasso = <Offset>[at]);
  }

  void _selectMove(Offset at) {
    switch (_drag) {
      case _Drag.lasso:
        setState(() => _lasso?.add(at));
      case _Drag.move:
        _controller.moveSelection(at - _last);
        _last = at;
      case _Drag.scale:
        final distance = math.max((at - _anchor).distance, 1.0);
        final factor = distance / _lastDistance;
        if (factor.isFinite && factor > 0) {
          _controller.scaleSelection(factor, _anchor);
          _lastDistance = distance;
        }
      case _Drag.rotate:
        final angle = (at - _anchor).direction;
        _controller.rotateSelection(angle - _lastAngle, _anchor);
        _lastAngle = angle;
      case _Drag.none:
        break;
    }
  }

  void _selectUp() {
    switch (_drag) {
      case _Drag.lasso:
        final lasso = _lasso;
        if (lasso != null) _controller.selectWithin(lasso);
        setState(() => _lasso = null);
      case _Drag.move:
      case _Drag.scale:
      case _Drag.rotate:
        _controller.endTransform();
      case _Drag.none:
        break;
    }
    _drag = _Drag.none;
  }

  /// Two-finger pan and pinch-zoom on a touch screen.
  void _pinch(PointerMoveEvent event) {
    final board = _board!;
    final before = _touches.values.take(2).toList();
    _touches[event.pointer] = event.localPosition;
    final after = _touches.values.take(2).toList();
    final centreBefore = (before[0] + before[1]) / 2;
    final centreAfter = (after[0] + after[1]) / 2;
    final spreadBefore = (before[0] - before[1]).distance;
    final spreadAfter = (after[0] - after[1]).distance;
    board.panBy(centreAfter - centreBefore);
    if (spreadBefore > 10) {
      board.zoomBy(spreadAfter / spreadBefore, focal: centreAfter);
    }
  }

  /// Mouse wheel and trackpad scroll: pan, or zoom with Ctrl / Cmd held.
  void _onPointerSignal(PointerSignalEvent event) {
    final board = _board;
    if (board == null || event is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed) {
      board.zoomBy(math.pow(0.998, event.scrollDelta.dy).toDouble(),
          focal: event.localPosition);
    } else {
      board.panBy(-event.scrollDelta);
    }
  }

  // Trackpad gestures (two-finger pan, pinch) arrive as pan-zoom events.
  void _onPanZoomStart(PointerPanZoomStartEvent event) => _lastPinchScale = 1;

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final board = _board;
    if (board == null) return;
    board.panBy(event.panDelta);
    if (event.scale != _lastPinchScale) {
      board.zoomBy(event.scale / _lastPinchScale, focal: event.localPosition);
      _lastPinchScale = event.scale;
    }
  }

  @override
  Widget build(BuildContext context) {
    final board = _board;
    if (board == null) return _surface(context, null);
    return LayoutBuilder(
      builder: (context, box) {
        board._viewport = box.biggest;
        return ListenableBuilder(
          listenable: board,
          builder: (context, _) => MouseRegion(
            cursor: board.hand ? SystemMouseCursors.grab : MouseCursor.defer,
            child: _surface(context, board),
          ),
        );
      },
    );
  }

  Widget _surface(BuildContext context, BoardView? board) {
    final controller = widget.controller;
    final page = controller.currentPage;

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      onPointerSignal: board == null ? null : _onPointerSignal,
      onPointerPanZoomStart: board == null ? null : _onPanZoomStart,
      onPointerPanZoomUpdate: board == null ? null : _onPanZoomUpdate,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          RepaintBoundary(
            key: widget.repaintKey,
            child: CustomPaint(
              painter: board == null
                  ? PaperPainter(widget.paper)
                  : BoardPaperPainter(widget.paper,
                      pan: board.pan, zoom: board.zoom),
              foregroundPainter: StrokePainter(
                strokes: page?.strokes ?? const <Stroke>[],
                liveStroke: controller.liveStroke,
                liveVersion: controller.liveStroke?.points.length ?? 0,
                revision: controller.committedRevision,
                pan: board?.pan ?? Offset.zero,
                zoom: board?.zoom ?? 1,
                cache: _cache,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          // Selection box, handles and lasso sit above the page, outside
          // the RepaintBoundary, so they never end up in page previews.
          IgnorePointer(
            child: CustomPaint(
              painter: _SelectionPainter(
                box: _controller.tool == CanvasTool.select
                    ? _selectionOnScreen
                    : null,
                lasso: _lasso?.map(_toScreen).toList(),
                handleRadius: _handleRadius,
                rotateOffset: _rotateOffset,
              ),
            ),
          ),
          if (_snapped && _controller.lastSnap != null)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xE6262628),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Snapped to ${_controller.lastSnap!.label.toLowerCase()}',
                      style: const TextStyle(
                        color: Color(0xFFEDE7DA),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Draws the lasso while it is being drawn, and the selection's dashed box
/// with corner (scale) and top (rotate) handles.
class _SelectionPainter extends CustomPainter {
  const _SelectionPainter({
    required this.box,
    required this.lasso,
    required this.handleRadius,
    required this.rotateOffset,
  });

  final Rect? box;
  final List<Offset>? lasso;
  final double handleRadius;
  final double rotateOffset;

  static const Color _accent = Color(0xFF4C5A93);

  void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 10;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = _accent;

    final lasso = this.lasso;
    if (lasso != null && lasso.length > 1) {
      final path = Path()..addPolygon(lasso, false);
      canvas.drawPath(
        Path()..addPolygon(lasso, true),
        Paint()..color = _accent.withAlpha(25),
      );
      _dashed(canvas, path, line);
    }

    final box = this.box;
    if (box == null) return;
    _dashed(canvas, Path()..addRect(box), line);
    final rotate = box.topCenter - Offset(0, rotateOffset);
    canvas.drawLine(box.topCenter, rotate, line);
    final fill = Paint()..color = const Color(0xFFFFFFFF);
    for (final c in <Offset>[
      box.topLeft,
      box.topRight,
      box.bottomLeft,
      box.bottomRight,
      rotate,
    ]) {
      canvas.drawCircle(c, handleRadius, fill);
      canvas.drawCircle(c, handleRadius, line);
    }
    // A little arrow in the rotate handle.
    canvas.drawArc(
      Rect.fromCircle(center: rotate, radius: handleRadius * 0.5),
      -math.pi * 0.9,
      math.pi * 1.4,
      false,
      line,
    );
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) => true;
}
