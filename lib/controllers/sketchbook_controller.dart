import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../models/brush.dart';
import '../models/sketch_page.dart';
import '../models/sketchbook.dart';
import '../models/stroke.dart';
import '../services/storage_service.dart';

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

  final Map<String, List<Stroke>> _redoStacks = <String, List<Stroke>>{};

  // --- loading -------------------------------------------------------------

  Future<void> load() async {
    _loading = true;
    _open = null;
    _pageIndex = 0;
    _liveStroke = null;
    _redoStacks.clear();
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

  void endStroke() {
    final stroke = _liveStroke;
    final page = currentPage;
    _liveStroke = null;
    if (stroke == null || page == null || stroke.isEmpty) {
      notifyListeners();
      return;
    }
    page.strokes.add(stroke);
    _redoStacks.remove(page.id);
    _committedRevision++;
    notifyListeners();
    final book = _open;
    if (book != null) unawaitedSave(book);
  }

  void cancelStroke() {
    _liveStroke = null;
    notifyListeners();
  }

  // --- history -------------------------------------------------------------

  bool get canUndo => (currentPage?.strokes.isNotEmpty ?? false);
  bool get canRedo => (_redoStacks[currentPage?.id ?? '']?.isNotEmpty ?? false);

  void undo() {
    final page = currentPage;
    if (page == null || page.strokes.isEmpty) return;
    final stroke = page.strokes.removeLast();
    (_redoStacks[page.id] ??= <Stroke>[]).add(stroke);
    _committedRevision++;
    notifyListeners();
    _saveOpen();
  }

  void redo() {
    final page = currentPage;
    if (page == null) return;
    final stack = _redoStacks[page.id];
    if (stack == null || stack.isEmpty) return;
    page.strokes.add(stack.removeLast());
    _committedRevision++;
    notifyListeners();
    _saveOpen();
  }

  void clearPage() {
    final page = currentPage;
    if (page == null || page.strokes.isEmpty) return;
    final removed = List<Stroke>.of(page.strokes);
    page.strokes.clear();
    // Clearing is undoable one stroke at a time, which matches how users
    // expect undo to behave after a destructive action.
    (_redoStacks[page.id] ??= <Stroke>[]).addAll(removed);
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
