import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Rect;

import 'package:flutter/foundation.dart';

import '../models/brush.dart';
import '../models/sketch_page.dart';
import '../models/sketchbook.dart';
import '../models/stroke.dart';
import '../services/storage_service.dart';
import '../utils/shapes.dart';

/// Owns the user's sketchbooks and all editing of the page currently open.
///
/// Undo/redo is per page and is deliberately *not* a global history: in a
/// physical sketchbook, undoing on one page should never disturb another.
class SketchbookController extends ChangeNotifier {
  SketchbookController(this._storage);

  final StorageService _storage;

  final List<Sketchbook> _sketchbooks = <Sketchbook>[];
  List<Sketchbook> get sketchbooks =>
      List<Sketchbook>.unmodifiable(_sketchbooks);

  bool _loading = true;
  bool get isLoading => _loading;

  Sketchbook? _open;
  Sketchbook? get openSketchbook => _open;

  int _pageIndex = 0;
  int get pageIndex => _pageIndex;

  BrushSettings _brush = const BrushSettings();
  BrushSettings get brush => _brush;

  /// Remembers the last drawing brush so toggling the eraser on and off
  /// returns the user to the tool they were actually using.
  BrushSettings _lastDrawingBrush = const BrushSettings();

  Stroke? _liveStroke;
  Stroke? get liveStroke => _liveStroke;

  /// Bumped whenever the committed stroke list changes, so the painter that
  /// draws finished strokes can repaint only when it needs to.
  int _committedRevision = 0;
  int get committedRevision => _committedRevision;

  bool _stylusDetected = false;
  bool get stylusDetected => _stylusDetected;

  // Undo / redo, per page (a sketchbook's pages have separate histories).
  final Map<String, List<_Edit>> _undo = <String, List<_Edit>>{};
  final Map<String, List<_Edit>> _redo = <String, List<_Edit>>{};

  // --- tools ---------------------------------------------------------------

  CanvasTool _tool = CanvasTool.draw;
  CanvasTool get tool => _tool;

  ShapeKind _shape = ShapeKind.ellipse;
  ShapeKind get shape => _shape;

  /// Strokes picked with the lasso, by identity.
  final Set<Stroke> _selection = <Stroke>{};
  Set<Stroke> get selection => Set<Stroke>.unmodifiable(_selection);
  bool get hasSelection => _selection.isNotEmpty;

  /// Set briefly after hold-to-snap so the UI can say what it became.
  ShapeKind? _lastSnap;
  ShapeKind? get lastSnap => _lastSnap;

  /// What the input device reported last - shown in the drawing screen so
  /// it is obvious whether real pen pressure is coming through.
  String _inputLabel = '';
  String get inputLabel => _inputLabel;

  // --- loading -------------------------------------------------------------

  Future<void> load() async {
    _loading = true;
    _open = null;
    _pageIndex = 0;
    _liveStroke = null;
    _undo.clear();
    _redo.clear();
    _selection.clear();
    notifyListeners();
    try {
      final books = await _storage.loadSketchbooks();
      _sketchbooks
        ..clear()
        ..addAll(books);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // --- sketchbook management ----------------------------------------------

  Sketchbook createSketchbook({
    required String title,
    PaperStyle paper = PaperStyle.plain,
    PageSize size = PageSize.portrait,
    int? coverIndex,
  }) {
    final book = Sketchbook(
      id: 'sb-${DateTime.now().millisecondsSinceEpoch}',
      title: title.trim().isEmpty ? 'Untitled sketchbook' : title.trim(),
      createdAt: DateTime.now(),
      paper: paper,
      size: size,
      coverIndex: coverIndex,
    );
    _sketchbooks.insert(0, book);
    unawaitedSave(book);
    notifyListeners();
    return book;
  }

  void renameSketchbook(Sketchbook book, String title) {
    if (title.trim().isEmpty) return;
    book.title = title.trim();
    unawaitedSave(book);
    notifyListeners();
  }

  void updateSketchbook(
    Sketchbook book, {
    String? title,
    PaperStyle? paper,
    PageSize? size,
    int? coverIndex,
  }) {
    if (title != null && title.trim().isNotEmpty) book.title = title.trim();
    if (paper != null) book.paper = paper;
    if (size != null && book.isBlank) book.size = size;
    if (coverIndex != null) book.coverIndex = coverIndex;
    unawaitedSave(book);
    notifyListeners();
  }

  Future<void> deleteSketchbook(Sketchbook book) async {
    _sketchbooks.removeWhere((s) => s.id == book.id);
    if (_open?.id == book.id) {
      _open = null;
      _pageIndex = 0;
    }
    notifyListeners();
    await _storage.deleteSketchbook(book.id);
  }

  void open(Sketchbook book, {int page = 0}) {
    _open = book;
    _pageIndex = page.clamp(0, book.pageCount - 1);
    _liveStroke = null;
    _committedRevision++;
    notifyListeners();
  }

  void close() {
    final book = _open;
    _open = null;
    _liveStroke = null;
    notifyListeners();
    if (book != null) unawaitedSave(book);
  }

  // --- pages ---------------------------------------------------------------

  SketchPage? get currentPage {
    final book = _open;
    if (book == null) return null;
    return book.pageAt(_pageIndex);
  }

  void goToPage(int index) {
    final book = _open;
    if (book == null) return;
    final clamped = index.clamp(0, book.pageCount - 1);
    if (clamped == _pageIndex) return;
    _pageIndex = clamped;
    _liveStroke = null;
    _selection.clear();
    _committedRevision++;
    notifyListeners();
  }

  void nextPage() => goToPage(_pageIndex + 1);
  void previousPage() => goToPage(_pageIndex - 1);

  bool get hasNextPage => _open != null && _pageIndex < _open!.pageCount - 1;
  bool get hasPreviousPage => _pageIndex > 0;

  void addPage() {
    final book = _open;
    if (book == null) return;
    book.addPage(at: _pageIndex + 1);
    _pageIndex += 1;
    _committedRevision++;
    notifyListeners();
    unawaitedSave(book);
  }

  void deleteCurrentPage() {
    final book = _open;
    if (book == null) return;
    if (!book.removePage(_pageIndex)) return;
    _pageIndex = _pageIndex.clamp(0, book.pageCount - 1);
    _committedRevision++;
    notifyListeners();
    unawaitedSave(book);
  }

  void setPaper(PaperStyle paper) {
    final book = _open;
    if (book == null) return;
    book.paper = paper;
    notifyListeners();
    unawaitedSave(book);
  }

  void setThumbnail(Uint8List bytes) {
    currentPage?.thumbnail = bytes;
    notifyListeners();
    _saveOpen();
  }

  // --- brush ---------------------------------------------------------------

  void setBrush(BrushSettings settings) {
    _brush = settings;
    if (!settings.type.isEraser) _lastDrawingBrush = settings;
    notifyListeners();
  }

  void setBrushType(BrushType type) {
    if (type.isEraser) {
      _lastDrawingBrush = _brush.type.isEraser ? _lastDrawingBrush : _brush;
      setBrush(_brush.copyWith(type: type, size: 28.0));
    } else {
      setBrush(_brush.copyWith(type: type, size: _lastDrawingBrush.size));
    }
  }

  void toggleEraser() {
    if (_brush.type.isEraser) {
      setBrush(_lastDrawingBrush);
    } else {
      setBrushType(BrushType.eraser);
    }
  }

  void setColor(Color color) => setBrush(_brush.copyWith(color: color));

  void setSize(double size) => setBrush(_brush.copyWith(size: size));
  void setOpacity(double opacity) =>
      setBrush(_brush.copyWith(opacity: opacity));

  // --- tools -----------------------------------------------------------------

  void setTool(CanvasTool tool) {
    if (tool == _tool) return;
    _tool = tool;
    if (tool != CanvasTool.select) _selection.clear();
    notifyListeners();
  }

  void setShape(ShapeKind shape) {
    _shape = shape;
    _tool = CanvasTool.shape;
    _selection.clear();
    notifyListeners();
  }

  void reportInput(String label) {
    // Updated alongside stroke points, which already notify listeners.
    _inputLabel = label;
  }

  // --- drawing -------------------------------------------------------------

  /// [sizeScale] lets the infinite whiteboard keep the brush the same size
  /// on screen at any zoom (its strokes are stored in board coordinates).
  void beginStroke(
    StrokePoint point, {
    bool fromStylus = false,
    double sizeScale = 1,
  }) {
    if (currentPage == null) return;
    if (fromStylus && !_stylusDetected) _stylusDetected = true;
    _lastSnap = null;
    _liveStroke = Stroke(
      brush: sizeScale == 1
          ? _brush
          : _brush.copyWith(size: _brush.size * sizeScale),
      points: <StrokePoint>[point],
    );
    notifyListeners();
  }

  void extendStroke(StrokePoint point) {
    final stroke = _liveStroke;
    if (stroke == null) return;
    stroke.add(point);
    notifyListeners();
  }

  /// Shape tool: replaces the live stroke with a clean [shape] dragged from
  /// [from] to [to].
  void shapeTo(Offset from, Offset to) {
    final stroke = _liveStroke;
    if (stroke == null) return;
    stroke.points
      ..clear()
      ..addAll(Shapes.build(_shape, from, to));
    notifyListeners();
  }

  /// Hold-to-snap: if the live freehand stroke looks like a line, ellipse or
  /// rectangle, make it a perfect one. Returns true if it snapped.
  bool snapLiveStroke() {
    final stroke = _liveStroke;
    if (stroke == null || stroke.isEraser) return false;
    final result = Shapes.recognise(stroke);
    if (result == null) return false;
    final (kind, points) = result;
    stroke.points
      ..clear()
      ..addAll(points);
    _lastSnap = kind;
    notifyListeners();
    return true;
  }

  void endStroke() {
    final stroke = _liveStroke;
    final page = currentPage;
    _liveStroke = null;
    if (stroke == null || page == null || stroke.isEmpty) {
      notifyListeners();
      return;
    }
    page.strokes.add(stroke);
    _record(page, _AddStroke(stroke));
    _committedRevision++;
    notifyListeners();
    _saveOpen();
  }

  void cancelStroke() {
    _liveStroke = null;
    notifyListeners();
  }

  // --- selection (lasso) ---------------------------------------------------

  /// Selects every stroke with most of its points inside [lasso] (a closed
  /// polygon in page coordinates).
  void selectWithin(List<Offset> lasso) {
    final page = currentPage;
    _selection.clear();
    if (page == null || lasso.length < 3) {
      notifyListeners();
      return;
    }
    for (final stroke in page.strokes) {
      if (stroke.isEraser || stroke.isEmpty) continue;
      var inside = 0;
      for (final p in stroke.points) {
        if (_pointInPolygon(p.offset, lasso)) inside++;
      }
      if (inside >= stroke.points.length * 0.6) _selection.add(stroke);
    }
    notifyListeners();
  }

  void clearSelection() {
    if (_selection.isEmpty) return;
    _selection.clear();
    notifyListeners();
  }

  /// Bounding box of the selection in page coordinates.
  Rect? get selectionBounds {
    if (_selection.isEmpty) return null;
    Rect? box;
    for (final stroke in _selection) {
      box = box == null ? stroke.bounds : box.expandToInclude(stroke.bounds);
    }
    return box;
  }

  /// Call once before a move / scale / rotate gesture so it can be undone.
  void beginTransform() {
    final page = currentPage;
    if (page == null || _selection.isEmpty) return;
    _record(page, _Snapshot.of(page.strokes));
  }

  void moveSelection(Offset delta) => _transformSelection((p) => p + delta);

  /// Scales the selection by [factor] around [anchor].
  void scaleSelection(double factor, Offset anchor) => _transformSelection(
        (p) => anchor + (p - anchor) * factor,
        sizeScale: factor,
      );

  /// Rotates the selection by [radians] around [centre].
  void rotateSelection(double radians, Offset centre) {
    final c = math.cos(radians);
    final s = math.sin(radians);
    _transformSelection((p) {
      final v = p - centre;
      return centre + Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
    });
  }

  void _transformSelection(
    Offset Function(Offset) transform, {
    double sizeScale = 1,
  }) {
    if (_selection.isEmpty) return;
    for (final stroke in _selection) {
      stroke.transformBy(transform, sizeScale: sizeScale);
    }
    _committedRevision++;
    notifyListeners();
  }

  /// Ends a move / scale / rotate gesture and saves.
  void endTransform() => _saveOpen();

  void deleteSelection() {
    final page = currentPage;
    if (page == null || _selection.isEmpty) return;
    _record(page, _Snapshot.of(page.strokes));
    page.strokes.removeWhere(_selection.contains);
    _selection.clear();
    _committedRevision++;
    notifyListeners();
    _saveOpen();
  }

  /// Copies the selection, offset slightly, and selects the copies.
  void duplicateSelection() {
    final page = currentPage;
    if (page == null || _selection.isEmpty) return;
    _record(page, _Snapshot.of(page.strokes));
    final copies = <Stroke>[
      for (final stroke in page.strokes)
        if (_selection.contains(stroke))
          stroke.copy()..transformBy((p) => p + const Offset(24, 24)),
    ];
    page.strokes.addAll(copies);
    _selection
      ..clear()
      ..addAll(copies);
    _committedRevision++;
    notifyListeners();
    _saveOpen();
  }

  /// Gives the selection the current brush colour.
  void recolourSelection() {
    final page = currentPage;
    if (page == null || _selection.isEmpty) return;
    _record(page, _Snapshot.of(page.strokes));
    for (final stroke in _selection) {
      stroke.brush = stroke.brush.copyWith(color: _brush.color);
    }
    _committedRevision++;
    notifyListeners();
    _saveOpen();
  }

  static bool _pointInPolygon(Offset p, List<Offset> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  // --- history -------------------------------------------------------------
  //
  // One undo stack per page. Most edits are "added a stroke", which is cheap
  // to undo; anything that changes existing strokes (clear, delete, move,
  // scale, rotate, recolour, duplicate) stores a snapshot of the page first.

  void _record(SketchPage page, _Edit edit) {
    (_undo[page.id] ??= <_Edit>[]).add(edit);
    _redo.remove(page.id);
  }

  bool get canUndo {
    final page = currentPage;
    if (page == null) return false;
    // Strokes loaded from storage have no history but can still be undone
    // one at a time, newest first.
    return (_undo[page.id]?.isNotEmpty ?? false) || page.strokes.isNotEmpty;
  }

  bool get canRedo => _redo[currentPage?.id ?? '']?.isNotEmpty ?? false;

  bool get hasStrokes => currentPage?.strokes.isNotEmpty ?? false;

  void undo() {
    final page = currentPage;
    if (page == null) return;
    final stack = _undo[page.id];
    final edit = (stack == null || stack.isEmpty)
        ? (page.strokes.isEmpty ? null : _AddStroke(page.strokes.last))
        : stack.removeLast();
    if (edit == null) return;
    (_redo[page.id] ??= <_Edit>[]).add(edit.undo(page));
    _afterHistory();
  }

  void redo() {
    final page = currentPage;
    if (page == null) return;
    final stack = _redo[page.id];
    if (stack == null || stack.isEmpty) return;
    (_undo[page.id] ??= <_Edit>[]).add(stack.removeLast().undo(page));
    _afterHistory();
  }

  void clearPage() {
    final page = currentPage;
    if (page == null || page.strokes.isEmpty) return;
    _record(page, _Snapshot.of(page.strokes));
    page.strokes.clear();
    _selection.clear();
    _committedRevision++;
    notifyListeners();
    _saveOpen();
  }

  void _afterHistory() {
    _selection.removeWhere((s) => !(currentPage?.strokes.contains(s) ?? false));
    _committedRevision++;
    notifyListeners();
    _saveOpen();
  }

  // --- persistence ---------------------------------------------------------

  void unawaitedSave(Sketchbook book) {
    // Fire and forget: drawing never waits on the network. The Firestore
    // service debounces these and its offline cache queues writes.
    _storage.saveSketchbook(book);
  }

  void _saveOpen() {
    final book = _open;
    if (book != null) unawaitedSave(book);
  }
}

/// What the canvas does with a pointer.
enum CanvasTool {
  /// Freehand with the current brush (hold still at the end to snap).
  draw,

  /// Drag out a clean line, rectangle or ellipse.
  shape,

  /// Lasso strokes, then move / scale / rotate / recolour / delete them.
  select,
}

/// One undoable change. [undo] reverts it on [page] and returns the edit
/// that would re-apply it, so the same type serves undo and redo.
abstract class _Edit {
  _Edit undo(SketchPage page);
}

/// A stroke was added (undo removes it; redo adds it back).
class _AddStroke extends _Edit {
  _AddStroke(this.stroke);

  final Stroke stroke;

  @override
  _Edit undo(SketchPage page) {
    page.strokes.remove(stroke);
    return _RemoveStroke(stroke);
  }
}

class _RemoveStroke extends _Edit {
  _RemoveStroke(this.stroke);

  final Stroke stroke;

  @override
  _Edit undo(SketchPage page) {
    page.strokes.add(stroke);
    return _AddStroke(stroke);
  }
}

/// The whole page as it was before an edit. Strokes are deep-copied because
/// transforms change them in place.
class _Snapshot extends _Edit {
  _Snapshot(this.strokes);

  _Snapshot.of(List<Stroke> current)
      : strokes = <Stroke>[for (final s in current) s.copy()];

  final List<Stroke> strokes;

  @override
  _Edit undo(SketchPage page) {
    final now = _Snapshot.of(page.strokes);
    page.strokes
      ..clear()
      ..addAll(strokes.map((s) => s.copy()));
    return now;
  }
}
