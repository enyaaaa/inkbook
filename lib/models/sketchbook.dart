import 'sketch_page.dart';

/// Paper styles a sketchbook can use. Purely visual - drawn by the canvas
/// background painter.
enum PaperStyle {
  plain('Plain'),
  dotted('Dot grid'),
  grid('Grid'),
  ruled('Ruled'),
  toned('Toned paper');

  const PaperStyle(this.label);
  final String label;
}

/// The shape of a sketchbook's pages - or, for [whiteboard], no edges at
/// all: one page you can pan and zoom across without limit.
enum PageSize {
  portrait('Portrait', '3 : 4', 3 / 4),
  aSeries('A-series', 'A4 · A5', 1 / 1.41421356),
  square('Square', '1 : 1', 1),
  landscape('Landscape', '4 : 3', 4 / 3),
  wide('Wide', '16 : 9', 16 / 9),
  whiteboard('Whiteboard', 'Unlimited', 4 / 3);

  const PageSize(this.label, this.detail, this.aspect);

  final String label;
  final String detail;

  /// Page width / height. For [whiteboard] this is only the shape of its
  /// cover and preview.
  final double aspect;

  bool get isInfinite => this == PageSize.whiteboard;
}

/// A collection of pages the user flips through, like a physical sketchbook.
class Sketchbook {
  Sketchbook({
    required this.id,
    required this.title,
    required this.createdAt,
    this.paper = PaperStyle.plain,
    this.size = PageSize.portrait,
    int? coverIndex,
    List<SketchPage>? pages,
  })  : coverIndex =
            coverIndex ?? id.codeUnits.fold<int>(0, (a, b) => (a + b) & 0xffff),
        pages = pages ?? <SketchPage>[SketchPage(id: '$id-p1')];

  final String id;
  String title;
  final DateTime createdAt;
  PaperStyle paper;

  /// Page shape. Only changeable while the book is still blank, since
  /// strokes are stored in page coordinates.
  PageSize size;

  bool get isBlank => pages.every((p) => p.strokes.isEmpty);

  /// Which cover colour from the theme's cover palette this book uses.
  /// Stored as an index so the model stays free of UI types.
  int coverIndex;

  final List<SketchPage> pages;

  int get pageCount => pages.length;

  SketchPage pageAt(int index) => pages[index];

  SketchPage addPage({int? at}) {
    final page =
        SketchPage(id: '$id-p${DateTime.now().microsecondsSinceEpoch}');
    if (at == null || at >= pages.length) {
      pages.add(page);
    } else {
      pages.insert(at, page);
    }
    return page;
  }

  bool removePage(int index) {
    if (pages.length <= 1 || index < 0 || index >= pages.length) return false;
    pages.removeAt(index);
    return true;
  }
}
