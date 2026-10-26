import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../controllers/app_state.dart';
import '../../models/sketchbook.dart';
import '../../theme/app_theme.dart';
import '../../widgets/scrapbook.dart';
import '../draw/draw_screen.dart';
import '../draw/widgets/canvas_painters.dart';
import 'flip_book.dart';

/// The shelf: every sketchbook the user owns as bold covers in a 3D
/// carousel (or laid flat in a grid). Tapping the book in front opens it
/// into a flip-through spread; tapping a page opens it for drawing.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  PageController? _pages;
  double _viewport = 0;
  int _focused = 0;
  bool _grid = false;
  final Map<String, GlobalKey<FlipBookState>> _keys =
      <String, GlobalKey<FlipBookState>>{};

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  GlobalKey<FlipBookState> _keyFor(Sketchbook book) =>
      _keys.putIfAbsent(book.id, () => GlobalKey<FlipBookState>());

  FlipBookState? _flipOf(Sketchbook? book) =>
      book == null ? null : _keys[book.id]?.currentState;

  PageController _controllerFor(double viewport) {
    if (_pages == null || _viewport != viewport) {
      _pages?.dispose();
      _viewport = viewport;
      _pages =
          PageController(viewportFraction: viewport, initialPage: _focused);
    }
    return _pages!;
  }

  void _showGrid(bool grid) {
    if (grid == _grid) return;
    // The carousel is rebuilt from scratch so it starts on [_focused].
    _pages?.dispose();
    _pages = null;
    setState(() => _grid = grid);
  }

  Future<void> _editSketchbook(BuildContext context, {Sketchbook? book}) async {
    final result = await showDialog<_BookDraft>(
      context: context,
      builder: (context) => _BookDialog(book: book),
    );
    if (result == null || !context.mounted) return;
    final controller = AppScope.of(context).sketchbooks;
    if (book != null) {
      controller.updateSketchbook(
        book,
        title: result.title,
        paper: result.paper,
        size: result.size,
        coverIndex: result.coverIndex,
      );
      return;
    }
    controller.createSketchbook(
      title: result.title,
      paper: result.paper,
      size: result.size,
      coverIndex: result.coverIndex,
    );
    _focusAndOpen(0);
  }

  /// Brings book [index] to the front of the shelf and opens it.
  void _focusAndOpen(int index) {
    _pages?.dispose();
    _pages = null;
    setState(() {
      _grid = false;
      _focused = index;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final books = AppScope.of(context).sketchbooks.sketchbooks;
      if (index < books.length) _flipOf(books[index])?.open();
    });
  }

  Future<void> _delete(BuildContext context, Sketchbook book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this sketchbook?'),
        content: Text(
          '"${book.title}" and its ${book.pageCount} '
          'page${book.pageCount == 1 ? '' : 's'} will be gone for good.',
          style: InkbookType.body(),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: InkbookColors.toolOrange,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await AppScope.of(context).sketchbooks.deleteSketchbook(book);
    if (mounted) setState(() => _focused = math.max(0, _focused - 1));
  }

  Future<void> _draw(BuildContext context, Sketchbook book, int page) async {
    final controller = AppScope.of(context).sketchbooks;
    controller.open(book, page: page);
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 480),
        reverseTransitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, __, ___) => DrawScreen(sketchbook: book),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.86, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    // Come back to the spread the user was last drawing on.
    if (mounted) _flipOf(book)?.showPage(controller.pageIndex);
  }

  String _spreadLabel(FlipBookState flip, Sketchbook book) {
    final left = flip.leftPage(flip.spread);
    final right = flip.rightPage(flip.spread);
    final total = book.pageCount;
    if (left != null && right != null) {
      return 'pages ${left + 1}-${right + 1} of $total';
    }
    return 'page ${(left ?? right ?? 0) + 1} of $total';
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).sketchbooks;
    final gutter = InkbookLayout.gutter(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final books = controller.sketchbooks;
        if (books.isNotEmpty && _focused >= books.length) {
          _focused = books.length - 1;
        }
        final focused = books.isEmpty ? null : books[_focused];
        final flip = _grid ? null : _flipOf(focused);
        final engaged = flip?.engaged ?? false;
        final open = flip?.isOpen ?? false;

        final String title;
        final String subtitle;
        final String? aside;
        if (_grid || focused == null) {
          title = 'Your shelf';
          subtitle =
              '${books.length} sketchbook${books.length == 1 ? '' : 's'}';
          aside = books.isEmpty ? null : 'tap a book to open it';
        } else if (open) {
          title = focused.title;
          subtitle = _spreadLabel(flip!, focused);
          aside = 'drag the pages to flip - tap one to draw';
        } else if (focused.size.isInfinite) {
          title = focused.title;
          subtitle = 'Infinite whiteboard  ·  ${focused.paper.label}';
          aside = 'tap the board to start drawing';
        } else {
          title = focused.title;
          subtitle =
              '${focused.pageCount} page${focused.pageCount == 1 ? '' : 's'}'
              '  ·  ${focused.size.label}  ·  ${focused.paper.label}';
          aside = 'tap the cover to flip through';
        }

        return Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 18, gutter, 0),
              child: ScrapHeading(
                title: title,
                subtitle: subtitle,
                icon: Icons.layers_outlined,
                aside: aside,
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    RingButton(
                      icon: Icons.auto_stories_outlined,
                      tooltip: 'Shelf view',
                      color: InkbookColors.ink,
                      selected: !_grid,
                      onTap: () => _showGrid(false),
                    ),
                    const SizedBox(width: 8),
                    RingButton(
                      icon: Icons.grid_view,
                      tooltip: 'Grid view',
                      color: InkbookColors.ink,
                      selected: _grid,
                      onTap: engaged ? null : () => _showGrid(true),
                    ),
                  ],
                ),
                trailing: RingButton(
                  icon: Icons.add,
                  tooltip: 'New sketchbook',
                  color: InkbookColors.ink,
                  onTap: () => _editSketchbook(context),
                ),
              ),
            ),
            Expanded(
              child: books.isEmpty
                  ? _EmptyShelf(onCreate: () => _editSketchbook(context))
                  : _grid
                      ? _gridView(context, books)
                      : _shelfView(context, books, engaged),
            ),
            if (!_grid && focused != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 22, top: 6),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: open
                      ? Row(
                          key: const ValueKey<String>('open'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            RoundAction(
                              icon: Icons.close,
                              tooltip: 'Close the book',
                              dark: true,
                              onTap: flip!.close,
                            ),
                            const SizedBox(width: 14),
                            RoundAction(
                              icon: Icons.chevron_left,
                              tooltip: 'Previous pages',
                              dark: true,
                              onTap: flip.canPrevious ? flip.previous : null,
                            ),
                            const SizedBox(width: 14),
                            RoundAction(
                              icon: Icons.edit_outlined,
                              tooltip: 'Draw on this page',
                              active: true,
                              size: 56,
                              onTap: () =>
                                  _draw(context, focused, flip.focusPage),
                            ),
                            const SizedBox(width: 14),
                            RoundAction(
                              icon: Icons.chevron_right,
                              tooltip: 'Next pages',
                              dark: true,
                              onTap: flip.canNext ? flip.next : null,
                            ),
                          ],
                        )
                      : Row(
                          key: const ValueKey<String>('closed'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            RoundAction(
                              icon: Icons.more_horiz,
                              tooltip: 'Edit sketchbook',
                              dark: true,
                              onTap: engaged
                                  ? null
                                  : () =>
                                      _editSketchbook(context, book: focused),
                            ),
                            const SizedBox(width: 14),
                            RoundAction(
                              icon: Icons.menu_book_outlined,
                              tooltip: 'Open the book',
                              active: true,
                              size: 56,
                              onTap: () => _flipOf(focused)?.open(),
                            ),
                            const SizedBox(width: 14),
                            RoundAction(
                              icon: Icons.delete_outline,
                              tooltip: 'Delete',
                              dark: true,
                              onTap: engaged
                                  ? null
                                  : () => _delete(context, focused),
                            ),
                            const SizedBox(width: 14),
                            RoundAction(
                              icon: Icons.add,
                              tooltip: 'New sketchbook',
                              dark: true,
                              onTap: () => _editSketchbook(context),
                            ),
                          ],
                        ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _shelfView(
    BuildContext context,
    List<Sketchbook> books,
    bool engaged,
  ) {
    final wide = InkbookLayout.isWide(context);
    final gutter = InkbookLayout.gutter(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final fraction = wide ? 0.34 : 0.7;
        final pages = _controllerFor(fraction);

        // Size each book's page so its open spread fits the screen, then
        // let the closed cover be drawn bigger so the shelf does not look
        // empty. Every book can have a different page shape.
        final room = math.max(120.0, height - 44);
        Size pageOf(Sketchbook book) {
          final aspect = FlipBook.aspectOf(book);
          final pw = math.min(room * aspect, (width - gutter * 2 - 12) / 2);
          return Size(pw, pw / aspect);
        }

        double closedScaleOf(Size page) => math
            .min(
              math.min(1.45, (width * fraction - 28) / page.width),
              room / page.height,
            )
            .clamp(0.6, 1.45);

        Widget flipBook(int index) {
          final book = books[index];
          final page = pageOf(book);
          final pw = page.width;
          final closedScale = closedScaleOf(page);
          return FlipBook(
            key: _keyFor(book),
            book: book,
            pageWidth: pw,
            closedScale: closedScale,
            interactive: index == _focused,
            onChanged: () {
              if (mounted) setState(() {});
            },
            onTapClosed: () => pages.animateToPage(
              index,
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
            ),
            onOpenPage: (page) => _draw(context, book, page),
          );
        }

        // An open spread is wider than a carousel slot, and taps outside a
        // slot would go to its neighbour. So while the focused book is open
        // it is lifted out of the carousel into a full-width layer; the
        // GlobalKey carries its animation state across the move.
        final lifted = engaged && _focused < books.length;

        final carousel = PageView.builder(
          controller: pages,
          clipBehavior: Clip.none,
          physics: engaged ? const NeverScrollableScrollPhysics() : null,
          itemCount: books.length,
          onPageChanged: (i) => setState(() => _focused = i),
          itemBuilder: (context, index) {
            return AnimatedBuilder(
              animation: pages,
              builder: (context, child) {
                var delta = (index - _focused).toDouble();
                if (pages.hasClients && pages.position.haveDimensions) {
                  delta = index - (pages.page ?? _focused.toDouble());
                }
                final d = delta.clamp(-1.5, 1.5);
                final scale = 1 - d.abs() * 0.16;
                return AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: engaged && index != _focused
                      ? 0
                      : (1 - d.abs() * 0.35).clamp(0.0, 1.0),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0011)
                      ..translate(-d * 26)
                      ..rotateY(d * 0.55)
                      ..scale(scale, scale),
                    child: child,
                  ),
                );
              },
              child: Center(
                child: lifted && index == _focused
                    ? SizedBox.fromSize(size: pageOf(books[index]))
                    : flipBook(index),
              ),
            );
          },
        );

        return Stack(
          children: <Widget>[
            Positioned.fill(child: carousel),
            if (lifted) Center(child: flipBook(_focused)),
          ],
        );
      },
    );
  }

  Widget _gridView(BuildContext context, List<Sketchbook> books) {
    final gutter = InkbookLayout.gutter(context);
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(gutter + 8, 28, gutter + 24, 40),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.6,
        crossAxisSpacing: 32,
        mainAxisSpacing: 28,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        return Column(
          children: <Widget>[
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => Center(
                  child: FlipBook(
                    book: book,
                    interactive: false,
                    pageWidth: math.min(
                      c.maxWidth,
                      c.maxHeight * FlipBook.aspectOf(book),
                    ),
                    onTapClosed: () => _focusAndOpen(index),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: InkbookType.body(size: 14, weight: FontWeight.w600),
            ),
            Text(
              '${book.pageCount} page${book.pageCount == 1 ? '' : 's'}',
              style: InkbookType.eyebrow(),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'an empty shelf is just\npotential, really.',
            textAlign: TextAlign.center,
            style:
                InkbookType.handwritten(size: 22, color: InkbookColors.inkSoft),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Start a sketchbook'),
          ),
        ],
      ),
    );
  }
}

class _BookDraft {
  const _BookDraft(this.title, this.paper, this.size, this.coverIndex);

  final String title;
  final PaperStyle paper;
  final PageSize size;
  final int coverIndex;
}

/// Create / edit a sketchbook: title, cover, page size and paper, with a
/// live preview of exactly what the pages will look like.
class _BookDialog extends StatefulWidget {
  const _BookDialog({this.book});

  final Sketchbook? book;

  @override
  State<_BookDialog> createState() => _BookDialogState();
}

class _BookDialogState extends State<_BookDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.book?.title ?? 'New sketchbook');
  late PaperStyle _paper = widget.book?.paper ?? PaperStyle.plain;
  late PageSize _size = widget.book?.size ?? PageSize.portrait;
  late int _cover =
      (widget.book?.coverIndex ?? DateTime.now().millisecondsSinceEpoch) %
          InkbookColors.covers.length;

  /// Strokes are stored in page coordinates, so the shape is fixed once
  /// anything has been drawn.
  bool get _sizeLocked => widget.book != null && !widget.book!.isBlank;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Widget _section(String label, Widget child, {String? note}) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: InkbookType.eyebrow()),
          const SizedBox(height: 10),
          child,
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                note,
                style: InkbookType.body(size: 12, color: InkbookColors.inkSoft),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final cover = InkbookColors.covers[_cover];

    final form = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: _title,
          autofocus: true,
          style: InkbookType.body(size: 16),
          decoration: const InputDecoration(labelText: 'TITLE'),
        ),
        _section(
          'COVER',
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (var i = 0; i < InkbookColors.covers.length; i++)
                GestureDetector(
                  onTap: () => setState(() => _cover = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 26,
                    height: 34,
                    transform:
                        Matrix4.translationValues(0, i == _cover ? -4 : 0, 0),
                    decoration: BoxDecoration(
                      color: InkbookColors.covers[i],
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(2),
                        right: Radius.circular(6),
                      ),
                      border: i == _cover
                          ? Border.all(color: InkbookColors.ink, width: 2)
                          : null,
                      boxShadow: paperShadow(lift: i == _cover ? 0.8 : 0.3),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _section(
          'PAGE SIZE',
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final size in PageSize.values)
                _SizeOption(
                  size: size,
                  selected: _size == size,
                  onTap:
                      _sizeLocked ? null : () => setState(() => _size = size),
                ),
            ],
          ),
          note: _sizeLocked
              ? 'The page size is fixed once you have drawn in a book.'
              : null,
        ),
        _section(
          'PAPER',
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final style in PaperStyle.values)
                ChoiceChip(
                  label: Text(style.label),
                  selected: _paper == style,
                  showCheckmark: false,
                  selectedColor: InkbookColors.tray,
                  labelStyle: TextStyle(
                    color: _paper == style
                        ? InkbookColors.folderCream
                        : InkbookColors.ink,
                  ),
                  backgroundColor: Colors.white.withAlpha(140),
                  shape: const StadiumBorder(),
                  onSelected: (_) => setState(() => _paper = style),
                ),
            ],
          ),
        ),
      ],
    );

    final preview = _PaperPreview(paper: _paper, size: _size, cover: cover);

    return AlertDialog(
      title: Text(widget.book == null ? 'A new sketchbook' : 'Edit sketchbook'),
      content: SizedBox(
        width: wide ? 700 : 380,
        child: SingleChildScrollView(
          // Room for the text field's floating label.
          padding: const EdgeInsets.only(top: 8),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(width: 250, height: 340, child: preview),
                    const SizedBox(width: 28),
                    Expanded(child: form),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(height: 190, child: preview),
                    const SizedBox(height: 12),
                    form,
                  ],
                ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _BookDraft(_title.text, _paper, _size, _cover),
          ),
          child: Text(widget.book == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

/// A page-size choice: a little outline drawn at the real proportions.
class _SizeOption extends StatelessWidget {
  const _SizeOption({
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final PageSize size;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? InkbookColors.folderCream : InkbookColors.ink;
    const box = 26.0;
    final w = size.aspect >= 1 ? box : box * size.aspect;
    final h = size.aspect >= 1 ? box / size.aspect : box;

    return Opacity(
      opacity: onTap == null && !selected ? 0.4 : 1,
      child: Material(
        color: selected ? InkbookColors.tray : Colors.white.withAlpha(140),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            width: 84,
            height: 82,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: box,
                  height: box,
                  child: Center(
                    child: size.isInfinite
                        ? Icon(Icons.all_inclusive, size: 22, color: fg)
                        : Container(
                            width: w,
                            height: h,
                            decoration: BoxDecoration(
                              border: Border.all(color: fg, width: 1.5),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  size.label,
                  style: InkbookType.body(
                    size: 12,
                    weight: FontWeight.w600,
                    color: fg,
                  ),
                ),
                Text(
                  size.detail,
                  style: InkbookType.body(size: 10.5, color: fg.withAlpha(170)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the pages will look like: the real paper pattern at the real page
/// proportions, sitting on the chosen cover - or, for a whiteboard, a patch
/// of endless board fading out at the edges.
class _PaperPreview extends StatelessWidget {
  const _PaperPreview({
    required this.paper,
    required this.size,
    required this.cover,
  });

  final PaperStyle paper;
  final PageSize size;
  final Color cover;

  /// Patterns are drawn at the size a real page is drawn on screen, then
  /// scaled down, so dot and line spacing look true to life.
  static const double _pageHeight = 620;

  @override
  Widget build(BuildContext context) {
    final Widget sheet;
    if (size.isInfinite) {
      sheet = AspectRatio(
        aspectRatio: size.aspect,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const RadialGradient(
              radius: 0.75,
              colors: <Color>[Colors.black, Colors.black, Colors.transparent],
              stops: <double>[0, 0.6, 1],
            ).createShader(rect),
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _pageHeight * size.aspect,
                height: _pageHeight,
                child: CustomPaint(
                  painter: BoardPaperPainter(
                    paper,
                    pan: const Offset(17, 11),
                    zoom: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      sheet = AspectRatio(
        aspectRatio: size.aspect,
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 6, 5, 6),
          decoration: BoxDecoration(
            color: cover,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(3),
              right: Radius.circular(8),
            ),
            boxShadow: paperShadow(lift: 0.8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(
                width: _pageHeight * size.aspect,
                height: _pageHeight,
                child: CustomPaint(painter: PaperPainter(paper)),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey<String>('${size.name}-${paper.name}-$cover'),
                child: sheet,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          size.isInfinite
              ? 'Infinite whiteboard · ${paper.label}'
              : '${size.label} ${size.detail} · ${paper.label}',
          textAlign: TextAlign.center,
          style: InkbookType.eyebrow(),
        ),
        if (size.isInfinite)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'pan and zoom as far as you like',
              style: InkbookType.handwritten(size: 15),
            ),
          ),
      ],
    );
  }
}
