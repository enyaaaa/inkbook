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

class _DrawingCanvasState extends State<DrawingCanvas> {
  final PressureNormaliser _pressure = PressureNormaliser();
  int? _activePointer;

  // Whiteboard navigation.
  final Map<int, Offset> _touches = <int, Offset>{};
  int? _panPointer;
  double _lastPinchScale = 1;

  BoardView? get _board => widget.board;

  Offset _toBoard(Offset local) => _board?.toBoard(local) ?? local;

  bool _isTouch(PointerEvent e) => e.kind == PointerDeviceKind.touch;

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
            widget.controller.cancelStroke();
          }
          _panPointer = null;
          return;
        }
        // With a stylus in play, one finger pans the board.
        if (widget.controller.stylusDetected) {
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
    if (_isTouch(event) && widget.controller.stylusDetected) {
      // Once a stylus has been seen, treat touch as palm rejection.
      return;
    }
    _activePointer = event.pointer;
    _pressure.begin(event);
    widget.controller.beginStroke(
      StrokePoint(
        _toBoard(event.localPosition),
        _pressure.current,
        tilt: event.tilt,
      ),
      fromStylus: event.kind == PointerDeviceKind.stylus,
      sizeScale: board == null ? 1 : 1 / board.zoom,
    );
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
    final live = widget.controller.liveStroke;
    if (live == null) return;
    final pressure = _pressure.update(event);
    final last = live.points.isEmpty ? null : live.points.last;
    // Sample spacing is judged on screen, so zooming in still gives smooth
    // strokes.
    final lastOnScreen = last == null || board == null
        ? last
        : StrokePoint(last.offset * board.zoom + board.pan, last.pressure);
    if (!StrokeGeometry.shouldSample(lastOnScreen, event.localPosition)) {
      return;
    }
    widget.controller.extendStroke(
      StrokePoint(_toBoard(event.localPosition), pressure, tilt: event.tilt),
    );
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

  void _onPointerUp(PointerEvent event) {
    _touches.remove(event.pointer);
    if (event.pointer == _panPointer) _panPointer = null;
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    _pressure.end();
    widget.controller.endStroke();
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
      child: RepaintBoundary(
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
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
