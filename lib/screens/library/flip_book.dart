import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/sketchbook.dart';
import '../../theme/app_theme.dart';
import '../../widgets/scrapbook.dart';
import '../draw/widgets/canvas_painters.dart';

/// A sketchbook you can flip through.
///
/// Closed, it is a hardback cover. Tapped, the cover swings open on its
/// spine and the book slides to the centre to show a two-page spread; from
/// there pages are turned by dragging (the page follows the finger) or with
/// [next] / [previous]. Tapping a page asks the parent to open it for
/// drawing.
///
/// Spread 0 is the inside of the front cover on the left and page 1 on the
/// right; every later spread shows two pages, like a real book.
class FlipBook extends StatefulWidget {
  const FlipBook({
    super.key,
    required this.book,
    required this.pageWidth,
    this.closedScale = 1,
    this.interactive = true,
    this.onOpenPage,
    this.onChanged,
    this.onTapClosed,
  });

  /// Page width / height for [book] - its chosen size, so previews match
  /// the drawing canvas exactly.
  static double aspectOf(Sketchbook book) => book.size.aspect;

  final Sketchbook book;

  /// Width of one page once the book is open.
  final double pageWidth;

  /// How much bigger the closed cover is drawn than an open page.
  final double closedScale;

  /// False for books that are not in focus: they stay shut and just report
  /// taps through [onTapClosed].
  final bool interactive;
  final ValueChanged<int>? onOpenPage;
  final VoidCallback? onChanged;
  final VoidCallback? onTapClosed;

  @override
  State<FlipBook> createState() => FlipBookState();
}

class FlipBookState extends State<FlipBook> with TickerProviderStateMixin {
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
  );
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );

  int _spread = 0;
  int? _target;
  double _grabX = 0;
  bool _hover = false;

  @override
  void dispose() {
    _open.dispose();
    _turn.dispose();
    super.dispose();
  }

  // --- state the parent reads ---------------------------------------------

  bool get isOpen => _open.value > 0.5;

  /// True from the moment the cover starts to lift until it is shut again.
  bool get engaged => _open.value > 0 || _open.isAnimating;
  int get spread => _spread;
  int get spreadCount => widget.book.pageCount ~/ 2 + 1;
  bool get canNext => isOpen && _target == null && _spread < spreadCount - 1;
  bool get canPrevious => isOpen && _target == null && _spread > 0;

  /// Page index shown on the left of [spread], or null for the cover.
  int? leftPage(int spread) {
    final index = spread * 2 - 1;
    return spread == 0 || index >= widget.book.pageCount ? null : index;
  }

  /// Page index shown on the right of [spread], or null past the last page.
  int? rightPage(int spread) {
    final index = spread * 2;
    return index >= widget.book.pageCount ? null : index;
  }

  /// The page to draw on when the user just says "draw": the right-hand
  /// page, or the left one on the final spread.
  int get focusPage => rightPage(_spread) ?? leftPage(_spread) ?? 0;

  // --- commands ------------------------------------------------------------

  Future<void> open() async {
    // A whiteboard has no pages to flip: go straight to drawing.
    if (widget.book.size.isInfinite) {
      widget.onOpenPage?.call(0);
      return;
    }
    final opening = _open.animateTo(1, curve: Curves.easeInOutCubic);
    _notify();
    await opening;
    _notify();
  }

  Future<void> close() async {
    if (_target != null) return;
    final closing = _open.animateBack(0, curve: Curves.easeInOutCubic);
    _notify();
    await closing;
    if (!mounted) return;
    setState(() => _spread = 0);
    _notify();
  }

  Future<void> next() => _turnTo(_spread + 1);
  Future<void> previous() => _turnTo(_spread - 1);

  /// Shows the spread containing [page] without animating.
  void showPage(int page) {
    setState(() => _spread = ((page + 1) ~/ 2).clamp(0, spreadCount - 1));
    _notify();
  }

  Future<void> _turnTo(int target) async {
    if (_target != null || target < 0 || target >= spreadCount) return;
    setState(() => _target = target);
    _turn.value = 0;
    await _turn.animateTo(1, curve: Curves.easeInOutSine);
    _commit();
  }

  void _commit() {
    if (!mounted) return;
    setState(() {
      _spread = _target ?? _spread;
      _target = null;
    });
    _turn.value = 0;
    _notify();
  }

  void _notify() => widget.onChanged?.call();

  // --- dragging pages ------------------------------------------------------

  void _dragStart(DragStartDetails details) {
    _grabX = details.localPosition.dx;
  }

  void _dragUpdate(DragUpdateDetails details) {
    if (!isOpen || _turn.isAnimating) return;
    final pw = widget.pageWidth;
    final moved = details.localPosition.dx - _grabX;
    if (_target == null) {
      if (moved < -6 && _spread < spreadCount - 1) {
        setState(() => _target = _spread + 1);
      } else if (moved > 6 && _spread > 0) {
        setState(() => _target = _spread - 1);
      } else {
        return;
      }
    }
    final forward = _target! > _spread;

    // Keep the page's free edge under the finger. Grabbing right at the
    // edge moves it 1:1; grabbing nearer the spine moves it proportionally
    // faster, so dragging to the mirror-image point always turns the page
    // fully. The page angle is then whatever puts its edge there.
    final grab = (_grabX - pw).abs().clamp(pw / 3, pw);
    final edge = (forward ? pw : -pw) + moved * (pw / grab);
    final angle = math.acos((edge / pw).clamp(-1.0, 1.0));
    _turn.value = forward ? angle / math.pi : 1 - angle / math.pi;
  }

  Future<void> _dragEnd(DragEndDetails details) async {
    final target = _target;
    if (target == null || _turn.isAnimating) return;
    final forward = target > _spread;
    final velocity = details.primaryVelocity ?? 0;
    final flungOn = forward ? velocity < -350 : velocity > 350;
    final flungBack = forward ? velocity > 350 : velocity < -350;
    final v = _turn.value;
    if (!flungBack && (v > 0.5 || flungOn)) {
      await _turn.animateTo(
        1,
        duration: Duration(milliseconds: (480 * (1 - v)).round() + 140),
        curve: Curves.easeOutQuad,
      );
      _commit();
    } else {
      await _turn.animateBack(
        0,
        duration: Duration(milliseconds: (480 * v).round() + 140),
        curve: Curves.easeOutQuad,
      );
      if (mounted) setState(() => _target = null);
    }
  }

  // --- painting ------------------------------------------------------------

  @override
  void didUpdateWidget(FlipBook oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_spread >= spreadCount) _spread = spreadCount - 1;
    if (!widget.interactive && _open.value > 0) {
      _open.value = 0;
      _spread = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pw = widget.pageWidth;
    final ph = pw / FlipBook.aspectOf(widget.book);

    // Laid out as wide as the open spread (or as wide as the parent
    // allows) so taps anywhere on either page land on this widget.
    return SizedBox(
      width: pw * 2,
      height: ph,
      child: OverflowBox(
        minWidth: pw * 2,
        maxWidth: pw * 2,
        minHeight: ph,
        maxHeight: ph,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: isOpen
                ? null
                : (widget.interactive ? open : widget.onTapClosed),
            onHorizontalDragStart: isOpen ? _dragStart : null,
            onHorizontalDragUpdate: isOpen ? _dragUpdate : null,
            onHorizontalDragEnd: isOpen ? _dragEnd : null,
            child: AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[_open, _turn]),
              builder: (context, _) => _buildBook(pw, ph),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBook(double pw, double ph) {
    final t = _open.value;
    final lift = !isOpen && _hover && widget.interactive ? 1.025 : 1.0;
    final scale = (widget.closedScale + (1 - widget.closedScale) * t) * lift;
    final cover = InkbookColors
        .covers[widget.book.coverIndex % InkbookColors.covers.length];

    final turning = _target != null;
    final lower = turning ? math.min(_spread, _target!) : _spread;
    final upper = turning ? math.max(_spread, _target!) : _spread;
    final forward = turning && _target! > _spread;
    final theta = forward ? math.pi * _turn.value : math.pi * (1 - _turn.value);
    final settled = !turning && t == 1;

    final leftStack = math.min(3, lower);
    final rightStack = math.min(3, spreadCount - 1 - upper);
    final coverOnTop = t < 1;

    Widget page(int? index, {required bool left}) {
      return PageFace(
        book: widget.book,
        index: index,
        left: left,
        onTap: index == null || widget.onOpenPage == null || !settled
            ? null
            : () => widget.onOpenPage!(index),
      );
    }

    final coverLeaf = Positioned(
      left: pw,
      top: -5,
      width: pw + 5,
      height: ph + 10,
      child: Transform(
        alignment: Alignment.centerLeft,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0005)
          ..rotateY(math.pi * t),
        child: t > 0.5
            ? Transform.flip(
                flipX: true,
                child: Endpaper(book: widget.book, color: cover),
              )
            : BookCover(book: widget.book),
      ),
    );

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..translate(-(1 - t) * pw / 2)
        ..scale(scale, scale),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          // Long flat shadow under the closed book, fading as it opens.
          if (t < 1)
            Positioned(
              left: pw,
              top: 0,
              width: pw,
              height: ph,
              child: Opacity(
                opacity: 1 - t,
                child: CustomPaint(painter: LongShadowPainter()),
              ),
            ),
          // Shadow of the open book on the desk.
          // It only spreads left once the cover has come down on that side.
          Positioned(
            left: pw - pw * math.max(0, 2 * t - 1),
            top: 0,
            width: pw + pw * math.max(0, 2 * t - 1),
            height: ph,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: paperShadow(lift: 1.6),
              ),
            ),
          ),
          // Back board.
          Positioned(
            left: pw,
            top: -5,
            width: pw + 5,
            height: ph + 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(cover, Colors.black, 0.12),
                borderRadius:
                    const BorderRadius.horizontal(right: Radius.circular(10)),
              ),
            ),
          ),
          if (!coverOnTop) coverLeaf,
          // Pages already read, stacked under the left page.
          for (var k = leftStack; k >= 1; k--)
            Positioned(
              left: -2.5 * k,
              top: 0,
              width: pw,
              height: ph,
              child: Opacity(opacity: t, child: _sheetEdge(k)),
            ),
          // Pages still to come, stacked under the right page.
          for (var k = rightStack; k >= 1; k--)
            Positioned(
              left: pw + 2.5 * k,
              top: 0,
              width: pw,
              height: ph,
              child: _sheetEdge(k),
            ),
          if (leftPage(lower) != null)
            Positioned(
              left: 0,
              top: 0,
              width: pw,
              height: ph,
              child: Opacity(
                opacity: t,
                child: page(leftPage(lower), left: true),
              ),
            ),
          Positioned(
            left: pw,
            top: 0,
            width: pw,
            height: ph,
            child: page(rightPage(upper), left: false),
          ),
          // The board's shadow sweeping over page one as the cover lifts.
          if (t > 0 && t < 1)
            ..._castShadow(
                pw, ph, math.cos(math.pi * t) * pw, math.sin(math.pi * t)),
          // The page being turned, and the shadow it throws.
          if (turning) ...<Widget>[
            ..._castShadow(
                pw, ph, _edgeOf(theta, forward) * pw, math.sin(theta)),
            Positioned(
              left: pw,
              top: 0,
              width: pw,
              height: ph,
              child: _Leaf(
                theta: theta,
                forward: forward,
                front: page(rightPage(lower), left: false),
                back: page(leftPage(upper), left: true),
              ),
            ),
          ],
          // Gutter shadow down the spine.
          if (t > 0)
            Positioned(
              left: pw - 14,
              top: 0,
              width: 28,
              height: ph,
              child: IgnorePointer(
                child: Opacity(
                  opacity: t,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          Color(0x00000000),
                          Color(0x2E000000),
                          Color(0x00000000),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (coverOnTop) coverLeaf,
        ],
      ),
    );
  }

  /// Where the free edge of a turning page lands, in page widths from the
  /// spine (1 = right edge, -1 = left edge), allowing for its curl.
  double _edgeOf(double theta, bool forward) {
    final curled = theta + _Leaf.bendFor(theta, forward);
    return (math.cos(theta) + math.cos(curled)) / 2;
  }

  /// A soft shadow on the page underneath, just beyond a lifted leaf whose
  /// edge is [edge] pixels from the spine. [strength] is 0 flat, 1 upright.
  List<Widget> _castShadow(double pw, double ph, double edge, double strength) {
    final width = 18 + 60 * strength;
    final alpha = (70 * strength).round();
    if (alpha <= 0) return const <Widget>[];
    final onRight = edge >= 0;
    final left = onRight ? pw + edge : pw + edge - width;
    final clippedLeft = left.clamp(onRight ? pw : 0.0, onRight ? pw * 2 : pw);
    final clippedRight =
        (left + width).clamp(onRight ? pw : 0.0, onRight ? pw * 2 : pw);
    if (clippedRight - clippedLeft < 1) return const <Widget>[];
    final dark = Colors.black.withAlpha(alpha);
    const clear = Color(0x00000000);
    return <Widget>[
      Positioned(
        left: clippedLeft,
        top: 0,
        width: clippedRight - clippedLeft,
        height: ph,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: onRight ? <Color>[dark, clear] : <Color>[clear, dark],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _sheetEdge(int depth) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.lerp(
            InkbookColors.paper, InkbookColors.paperToned, depth * 0.3),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.black.withAlpha(20), width: 0.6),
      ),
    );
  }
}

/// A page mid-turn. It is hinged at the spine (its left edge) and drawn as
/// two halves so it can curl: the half by the spine rotates by [theta] and
/// the outer half bends a little further back, the way paper lags behind
/// the hand turning it. Each half shows the front or back of the sheet
/// depending on which way it currently faces.
class _Leaf extends StatelessWidget {
  const _Leaf({
    required this.theta,
    required this.forward,
    required this.front,
    required this.back,
  });

  /// 0 = lying flat on the right, pi = lying flat on the left.
  final double theta;
  final bool forward;
  final Widget front;
  final Widget back;

  /// Extra rotation of the outer half: zero when flat, most when upright,
  /// always trailing the direction of the turn.
  static double bendFor(double theta, bool forward) =>
      math.sin(theta) * 0.5 * (forward ? -1 : 1);

  @override
  Widget build(BuildContext context) {
    final bend = bendFor(theta, forward);
    return LayoutBuilder(
      builder: (context, box) {
        final pw = box.maxWidth;
        final ph = box.maxHeight;

        Widget half({required bool outer, required double angle}) {
          final facingBack = angle > math.pi / 2 || angle < -math.pi / 2;
          final face =
              facingBack ? Transform.flip(flipX: true, child: back) : front;
          // Turned away from the light = darker; the curl catches a
          // highlight where it bends.
          final shade = (math.sin(angle).abs() * 55).round();
          return ClipRect(
            child: OverflowBox(
              alignment: outer ? Alignment.centerRight : Alignment.centerLeft,
              minWidth: pw,
              maxWidth: pw,
              minHeight: ph,
              maxHeight: ph,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  face,
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            Colors.black.withAlpha(outer ? shade ~/ 2 : shade),
                            Colors.black.withAlpha(outer ? shade : shade ~/ 3),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (outer)
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.center,
                            end: Alignment.centerRight,
                            colors: <Color>[
                              Colors.white.withAlpha(
                                (math.sin(bend).abs() * 70).round(),
                              ),
                              const Color(0x00FFFFFF),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        return Transform(
          alignment: Alignment.centerLeft,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0006)
            ..rotateY(theta),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                left: 0,
                top: 0,
                width: pw / 2 + 0.5,
                height: ph,
                child: half(outer: false, angle: theta),
              ),
              Positioned(
                left: pw / 2,
                top: 0,
                width: pw / 2,
                height: ph,
                child: Transform(
                  alignment: Alignment.centerLeft,
                  transform: Matrix4.rotationY(bend),
                  child: half(outer: true, angle: theta + bend),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One sketchbook page as it appears in the flip book (and to the left of
/// the canvas while drawing): its last render if it has one, otherwise
/// blank paper in the book's style.
class PageFace extends StatelessWidget {
  const PageFace({
    super.key,
    required this.book,
    required this.index,
    required this.left,
    this.onTap,
  });

  final Sketchbook book;
  final int? index;
  final bool left;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final i = index;
    final radius = left
        ? const BorderRadius.horizontal(left: Radius.circular(4))
        : const BorderRadius.horizontal(right: Radius.circular(4));

    if (i == null) {
      return ClipRRect(
        borderRadius: radius,
        child: ColoredBox(
          color: InkbookColors.paper,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'the end - for now',
                textAlign: TextAlign.center,
                style: InkbookType.handwritten(
                  size: 16,
                  color: InkbookColors.inkSoft,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final thumbnail = book.pages[i].thumbnail;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (thumbnail != null)
              Image.memory(thumbnail, fit: BoxFit.cover, gaplessPlayback: true)
            else
              CustomPaint(painter: PaperPainter(book.paper)),
            if (left)
              const Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 26,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[Color(0x00000000), Color(0x1E2B2622)],
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 8,
              left: left ? 12 : null,
              right: left ? null : 12,
              child: Text('${i + 1}', style: InkbookType.eyebrow()),
            ),
          ],
        ),
      ),
    );
  }
}

/// The inside of the front cover: a cloth-coloured board with a patterned
/// endpaper and a bookplate.
class Endpaper extends StatelessWidget {
  const Endpaper({super.key, required this.book, required this.color});

  final Sketchbook book;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 5, 0, 5),
      decoration: BoxDecoration(
        color: Color.lerp(color, Colors.black, 0.12),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(4)),
        child: CustomPaint(
          painter: _EndpaperPainter(color),
          child: Center(
            child: FractionallySizedBox(
              widthFactor: 0.66,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                decoration: BoxDecoration(
                  color: InkbookColors.paper,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: color, width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('THIS BOOK BELONGS TO', style: InkbookType.eyebrow()),
                    const SizedBox(height: 6),
                    Text(
                      book.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: InkbookType.handwritten(size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EndpaperPainter extends CustomPainter {
  const _EndpaperPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Color.lerp(InkbookColors.paper, color, 0.18)!,
    );
    final dot = Paint()..color = color.withAlpha(70);
    for (var y = 10.0; y < size.height; y += 16) {
      final shift = (y ~/ 16).isEven ? 0.0 : 8.0;
      for (var x = 8.0 + shift; x < size.width; x += 16) {
        canvas.drawCircle(Offset(x, y), 1.6, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_EndpaperPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The front of a hardback cover: flat bold colour, darker spine, an
/// elastic band, a paper title label and - once the first page has ink -
/// that page taped on as a polaroid.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book});

  final Sketchbook book;

  static const BorderRadius _radius = BorderRadius.only(
    topLeft: Radius.circular(4),
    bottomLeft: Radius.circular(4),
    topRight: Radius.circular(12),
    bottomRight: Radius.circular(12),
  );

  @override
  Widget build(BuildContext context) {
    final color =
        InkbookColors.covers[book.coverIndex % InkbookColors.covers.length];
    final spine = Color.lerp(color, Colors.black, 0.18)!;
    final onCover = color.computeLuminance() > 0.45
        ? InkbookColors.ink
        : InkbookColors.folderCream;
    final thumbnail = book.pages.first.thumbnail;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: _radius,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withAlpha(50),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: _radius,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                    child: GrainSurface(color: color, density: 0.4)),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: w * 0.09,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          spine,
                          spine,
                          Color.lerp(spine, Colors.white, 0.12)!,
                        ],
                        stops: const <double>[0, 0.8, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: w * 0.1,
                  top: 0,
                  bottom: 0,
                  width: 5,
                  child: ColoredBox(color: Colors.black.withAlpha(60)),
                ),
                if (thumbnail != null)
                  Positioned(
                    left: w * 0.22,
                    right: w * 0.24,
                    top: w * 0.18,
                    height: w * 0.66,
                    child: Transform.rotate(
                      angle: scrapTilt(book.id.hashCode, max: 0.06),
                      child: Polaroid(
                        padding: 5,
                        child: Image.memory(thumbnail, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                if (thumbnail != null)
                  Positioned(
                    left: w * 0.36,
                    top: w * 0.14,
                    child: WashiTape(
                      color: scrapTape(book.id.hashCode),
                      width: w * 0.3,
                      height: 16,
                      angle: -0.08,
                    ),
                  ),
                Positioned(
                  left: w * 0.2,
                  right: w * 0.2,
                  bottom: w * 0.2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: InkbookColors.paper,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withAlpha(40),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(
                      book.title,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: InkbookType.body(
                        size: (w * 0.06).clamp(11.0, 16.0),
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: w * 0.15,
                  top: w * 0.07,
                  child: Text(
                    book.size.isInfinite
                        ? 'WHITEBOARD  ∞'
                        : 'NO. ${(book.coverIndex % 90) + 1}',
                    style: InkbookType.eyebrow(color: onCover.withAlpha(170)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The long, flat 45-degree shadow from the Paper app.
class LongShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final reach = size.height * 0.4;
    final path = Path()
      ..moveTo(size.width - 6, 8)
      ..lineTo(size.width + reach, 8 + reach)
      ..lineTo(size.width + reach, size.height + reach)
      ..lineTo(reach + 4, size.height + reach)
      ..lineTo(4, size.height)
      ..lineTo(size.width - 6, size.height)
      ..close();
    final rect = Rect.fromLTWH(0, 0, size.width + reach, size.height + reach);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.black.withAlpha(40),
            Colors.black.withAlpha(0)
          ],
          stops: const <double>[0.5, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(LongShadowPainter oldDelegate) => false;
}
