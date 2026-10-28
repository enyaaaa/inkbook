import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../controllers/app_state.dart';
import '../../controllers/sketchbook_controller.dart';
import '../../models/artwork.dart';
import '../../models/mood_board_item.dart';
import '../../models/sketchbook.dart';
import '../../theme/app_theme.dart';
import '../../widgets/scrapbook.dart';
import 'widgets/ai_guidance_panel.dart';
import 'widgets/brush_toolbar.dart';
import 'widgets/drawing_canvas.dart';

/// The sketchbook itself: the page lying on the desk with the rest of the
/// book stacked behind it, page controls underneath, the tool tray along the
/// bottom and the AI assistant on the right.
class DrawScreen extends StatefulWidget {
  const DrawScreen({super.key, required this.sketchbook});

  final Sketchbook sketchbook;

  @override
  State<DrawScreen> createState() => _DrawScreenState();
}

class _DrawScreenState extends State<DrawScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey _canvasKey = GlobalKey();
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _showAi = false;
  int _flipDirection = 1;

  /// Pan and zoom for the infinite whiteboard (unused for paged books).
  final BoardView _board = BoardView();

  bool get _isBoard => widget.sketchbook.size.isInfinite;

  @override
  void dispose() {
    _flip.dispose();
    _board.dispose();
    super.dispose();
  }

  /// The whiteboard: no page edges, the canvas fills the whole area.
  Widget _boardArea(SketchbookController controller) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: paperShadow(lift: 1.2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: DrawingCanvas(
            controller: controller,
            paper: widget.sketchbook.paper,
            repaintKey: _canvasKey,
            board: _board,
          ),
        ),
      ),
    );
  }

  Future<void> _turnPage(int direction) async {
    final controller = AppScope.of(context).sketchbooks;
    if (direction > 0 && !controller.hasNextPage) return;
    if (direction < 0 && !controller.hasPreviousPage) return;
    setState(() => _flipDirection = direction);
    await _capturePage();
    await _flip.forward(from: 0);
    if (!mounted) return;
    direction > 0 ? controller.nextPage() : controller.previousPage();
    await _flip.reverse(from: 1);
  }

  /// Renders the current page to PNG bytes via the canvas [RepaintBoundary].
  /// Used for page thumbnails, for saving to the mood board and for sharing.
  Future<Uint8List?> _capturePage() async {
    final boundary = _canvasKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    try {
      final image = await boundary.toImage(pixelRatio: 2.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return null;
      final bytes = data.buffer.asUint8List();
      if (mounted) AppScope.of(context).sketchbooks.setThumbnail(bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToMoodBoard() async {
    final state = AppScope.of(context);
    final bytes = await _capturePage();
    if (!mounted) return;
    final artwork = Artwork(
      id: 'own-${DateTime.now().microsecondsSinceEpoch}',
      title: '${widget.sketchbook.title} - page '
          '${state.sketchbooks.pageIndex + 1}',
      artistId: state.community.currentUser.id,
      createdAt: DateTime.now(),
      imageBytes: bytes,
    );
    state.moodBoard.save(artwork, source: MoodBoardSource.ownWork);
    _toast('Saved to your mood board');
  }

  Future<void> _share() async {
    final state = AppScope.of(context);
    final bytes = await _capturePage();
    if (!mounted) return;
    final title = await showDialog<String>(
      context: context,
      builder: (context) => _ShareDialog(
        initialTitle: '${widget.sketchbook.title} - page '
            '${state.sketchbooks.pageIndex + 1}',
      ),
    );
    if (title == null || !mounted) return;
    await state.community.publish(
      Artwork(
        id: 'pub-${DateTime.now().microsecondsSinceEpoch}',
        title: title.trim().isEmpty ? 'Untitled' : title.trim(),
        artistId: state.community.currentUser.id,
        createdAt: DateTime.now(),
        imageBytes: bytes,
      ),
    );
    if (mounted) _toast('Shared to Discover');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final controller = state.sketchbooks;
    final cream = InkbookColors.folderCream;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final page = controller.currentPage;
        final wide = MediaQuery.sizeOf(context).width >= 720;
        return Scaffold(
          backgroundColor: InkbookColors.desk,
          body: GrainSurface(
            color: InkbookColors.desk,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                    child: Row(
                      children: <Widget>[
                        RingButton(
                          icon: Icons.close,
                          tooltip: 'Close sketchbook',
                          onTap: () async {
                            await _capturePage();
                            if (!mounted) return;
                            controller.close();
                            if (mounted) Navigator.of(context).pop();
                          },
                        ),
                        const SizedBox(width: 8),
                        RingButton(
                          icon: Icons.undo,
                          tooltip: 'Undo',
                          onTap: controller.canUndo ? controller.undo : null,
                        ),
                        const SizedBox(width: 8),
                        RingButton(
                          icon: Icons.redo,
                          tooltip: 'Redo',
                          onTap: controller.canRedo ? controller.redo : null,
                        ),
                        Expanded(
                          child: Column(
                            children: <Widget>[
                              Text(
                                widget.sketchbook.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: InkbookType.title(
                                  size: wide ? 30 : 22,
                                  color: cream,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isBoard
                                    ? 'INFINITE WHITEBOARD'
                                    : 'PAGE ${controller.pageIndex + 1} OF '
                                        '${widget.sketchbook.pageCount}',
                                style: InkbookType.eyebrow(
                                  color: cream.withAlpha(170),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (wide) ...<Widget>[
                          PopupMenuButton<PaperStyle>(
                            tooltip: 'Paper',
                            onSelected: controller.setPaper,
                            itemBuilder: (context) =>
                                <PopupMenuEntry<PaperStyle>>[
                              for (final style in PaperStyle.values)
                                PopupMenuItem<PaperStyle>(
                                  value: style,
                                  child: Text(style.label),
                                ),
                            ],
                            child: const IgnorePointer(
                              child: RingButton(
                                icon: Icons.texture,
                                tooltip: 'Paper',
                                onTap: _noop,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          RingButton(
                            icon: Icons.layers_clear_outlined,
                            tooltip: 'Clear page',
                            onTap: controller.hasStrokes
                                ? controller.clearPage
                                : null,
                          ),
                          const SizedBox(width: 8),
                          RingButton(
                            icon: Icons.push_pin_outlined,
                            tooltip: 'Pin to mood board',
                            onTap: _saveToMoodBoard,
                          ),
                          const SizedBox(width: 8),
                          RingButton(
                            icon: Icons.ios_share,
                            tooltip: 'Share',
                            onTap: _share,
                          ),
                          const SizedBox(width: 8),
                        ] else ...<Widget>[
                          PopupMenuButton<VoidCallback>(
                            tooltip: 'More',
                            onSelected: (action) => action(),
                            itemBuilder: (context) =>
                                <PopupMenuEntry<VoidCallback>>[
                              PopupMenuItem<VoidCallback>(
                                value: _saveToMoodBoard,
                                child: const Text('Pin to mood board'),
                              ),
                              PopupMenuItem<VoidCallback>(
                                value: _share,
                                child: const Text('Share'),
                              ),
                              if (controller.hasStrokes)
                                PopupMenuItem<VoidCallback>(
                                  value: controller.clearPage,
                                  child: const Text('Clear page'),
                                ),
                            ],
                            child: const IgnorePointer(
                              child: RingButton(
                                icon: Icons.more_horiz,
                                tooltip: 'More',
                                onTap: _noop,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        RingButton(
                          icon: Icons.auto_awesome,
                          tooltip: 'Drawing assistant',
                          selected: _showAi,
                          color: _showAi ? InkbookColors.toolYellow : cream,
                          onTap: () => setState(() => _showAi = !_showAi),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            children: <Widget>[
                              Expanded(
                                child: Stack(
                                  children: <Widget>[
                                    Positioned.fill(
                                      child: _isBoard
                                          ? _boardArea(controller)
                                          : Padding(
                                              // The whole page, as large as the
                                              // screen allows - room for the stack of
                                              // pages peeking out on the right.
                                              padding: EdgeInsets.fromLTRB(
                                                wide ? 20 : 8,
                                                4,
                                                wide ? 34 : 18,
                                                6,
                                              ),
                                              child: Center(
                                                child: AspectRatio(
                                                  aspectRatio: widget
                                                      .sketchbook.size.aspect,
                                                  child: _PageStack(
                                                    extraPages: (widget
                                                                .sketchbook
                                                                .pageCount -
                                                            controller
                                                                .pageIndex -
                                                            1)
                                                        .clamp(0, 3),
                                                    child: AnimatedBuilder(
                                                      animation: _flip,
                                                      builder:
                                                          (context, child) {
                                                        // Lifts toward the viewer, hinged
                                                        // on the side it turns from.
                                                        final angle =
                                                            _flip.value *
                                                                1.3 *
                                                                _flipDirection;
                                                        return Transform(
                                                          alignment:
                                                              _flipDirection > 0
                                                                  ? Alignment
                                                                      .centerLeft
                                                                  : Alignment
                                                                      .centerRight,
                                                          transform: Matrix4
                                                              .identity()
                                                            ..setEntry(
                                                                3, 2, 0.0012)
                                                            ..rotateY(angle),
                                                          child: child,
                                                        );
                                                      },
                                                      child: DecoratedBox(
                                                        decoration:
                                                            BoxDecoration(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(4),
                                                          boxShadow:
                                                              paperShadow(
                                                                  lift: 1.4),
                                                        ),
                                                        child: ClipRRect(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(4),
                                                          child: DrawingCanvas(
                                                            controller:
                                                                controller,
                                                            paper: widget
                                                                .sketchbook
                                                                .paper,
                                                            repaintKey:
                                                                _canvasKey,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                    ),
                                    // Floats over the canvas so the page
                                    // never resizes when it appears.
                                    if (controller.tool == CanvasTool.select &&
                                        controller.hasSelection)
                                      Positioned(
                                        left: 0,
                                        right: 0,
                                        bottom: 10,
                                        child: _SelectionBar(
                                          controller: controller,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (_isBoard)
                                _BoardBar(
                                  board: _board,
                                  strokeCount: page?.strokeCount ?? 0,
                                  stylusDetected: controller.stylusDetected,
                                )
                              else
                                _PageBar(
                                  pageIndex: controller.pageIndex,
                                  pageCount: widget.sketchbook.pageCount,
                                  strokeCount: page?.strokeCount ?? 0,
                                  stylusDetected: controller.stylusDetected,
                                  inputLabel: controller.inputLabel,
                                  onPrevious: () => _turnPage(-1),
                                  onNext: () => _turnPage(1),
                                  onAdd: () async {
                                    // Snapshot the page being left so it
                                    // shows on the left of the spread.
                                    await _capturePage();
                                    controller.addPage();
                                  },
                                  onDelete: widget.sketchbook.pageCount > 1
                                      ? controller.deleteCurrentPage
                                      : null,
                                ),
                            ],
                          ),
                        ),
                        if (_showAi)
                          AiGuidancePanel(
                            ai: state.aiGuidance,
                            strokeCount: page?.strokeCount ?? 0,
                            onClose: () => setState(() => _showAi = false),
                          ),
                      ],
                    ),
                  ),
                  ToolTray(controller: controller),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

void _noop() {}

/// Asks for a title before sharing. Owns its controller so it outlives the
/// dialog's closing animation.
class _ShareDialog extends StatefulWidget {
  const _ShareDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.initialTitle);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Share to the community'),
      content: TextField(
        controller: _title,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'TITLE'),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _title.text),
          child: const Text('Share'),
        ),
      ],
    );
  }
}

/// The pages still to come, peeking out behind the current one like the
/// fore-edge of a real sketchbook.
class _PageStack extends StatelessWidget {
  const _PageStack({required this.extraPages, required this.child});

  final int extraPages;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        for (var i = extraPages; i >= 1; i--)
          Positioned.fill(
            left: 10.0 * i,
            right: -9.0 * i,
            top: 5.0 * i,
            bottom: 5.0 * i,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(
                    InkbookColors.paper, InkbookColors.paperToned, i * 0.25),
                borderRadius: BorderRadius.circular(4),
                boxShadow: paperShadow(lift: 0.6),
              ),
            ),
          ),
        Positioned.fill(child: child),
      ],
    );
  }
}

/// Actions for the lasso selection: duplicate, recolour, delete, done.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.controller});

  final SketchbookController controller;

  @override
  Widget build(BuildContext context) {
    final count = controller.selection.length;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: InkbookColors.tray,
          borderRadius: BorderRadius.circular(30),
          boxShadow: paperShadow(lift: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '$count STROKE${count == 1 ? '' : 'S'}',
                style: InkbookType.eyebrow(
                  color: InkbookColors.folderCream.withAlpha(180),
                ),
              ),
            ),
            RoundAction(
              icon: Icons.copy_all_outlined,
              tooltip: 'Duplicate',
              size: 36,
              dark: true,
              onTap: controller.duplicateSelection,
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Recolour with the current colour',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: controller.recolourSelection,
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: controller.brush.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: InkbookColors.folderCream,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            RoundAction(
              icon: Icons.delete_outline,
              tooltip: 'Delete',
              size: 36,
              dark: true,
              onTap: controller.deleteSelection,
            ),
            const SizedBox(width: 6),
            RoundAction(
              icon: Icons.check,
              tooltip: 'Done',
              size: 36,
              active: true,
              onTap: controller.clearSelection,
            ),
          ],
        ),
      ),
    );
  }
}

/// Under the whiteboard: hand tool, zoom out / level / in, reset view.
class _BoardBar extends StatelessWidget {
  const _BoardBar({
    required this.board,
    required this.strokeCount,
    required this.stylusDetected,
  });

  final BoardView board;
  final int strokeCount;
  final bool stylusDetected;

  @override
  Widget build(BuildContext context) {
    final cream = InkbookColors.folderCream;
    final meta = InkbookType.eyebrow(color: cream.withAlpha(150));
    return ListenableBuilder(
      listenable: board,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                stylusDetected
                    ? 'ONE FINGER TO PAN · PINCH TO ZOOM'
                    : 'SCROLL TO PAN · CTRL/⌘ + SCROLL TO ZOOM',
                overflow: TextOverflow.ellipsis,
                style: meta,
              ),
            ),
            RoundAction(
              icon: Icons.pan_tool_outlined,
              tooltip:
                  board.hand ? 'Back to drawing' : 'Hand tool (drag to pan)',
              size: 38,
              active: board.hand,
              onTap: () => board.hand = !board.hand,
            ),
            const SizedBox(width: 8),
            RoundAction(
              icon: Icons.remove,
              tooltip: 'Zoom out',
              size: 38,
              onTap: board.zoom > BoardView.minZoom
                  ? () => board.zoomBy(1 / 1.25)
                  : null,
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Reset view',
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: board.reset,
                child: Container(
                  width: 64,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDFBF6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${(board.zoom * 100).round()}%',
                    style: InkbookType.body(size: 13, weight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            RoundAction(
              icon: Icons.add,
              tooltip: 'Zoom in',
              size: 38,
              onTap: board.zoom < BoardView.maxZoom
                  ? () => board.zoomBy(1.25)
                  : null,
            ),
            Expanded(
              child: Text(
                '$strokeCount STROKES',
                textAlign: TextAlign.right,
                style: meta,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small floating pill under the page: pressure mode, page turning and
/// page management.
class _PageBar extends StatelessWidget {
  const _PageBar({
    required this.pageIndex,
    required this.pageCount,
    required this.strokeCount,
    required this.stylusDetected,
    required this.inputLabel,
    required this.onPrevious,
    required this.onNext,
    required this.onAdd,
    required this.onDelete,
  });

  final int pageIndex;
  final int pageCount;
  final int strokeCount;
  final bool stylusDetected;

  /// What the last pointer reported, e.g. "PEN · PRESSURE 0.42".
  final String inputLabel;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onAdd;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final cream = InkbookColors.folderCream;
    final meta = InkbookType.eyebrow(color: cream.withAlpha(150));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Tooltip(
              message: 'What your pen or mouse is sending. With no real '
                  'pressure, line weight is simulated from drawing speed.',
              child: Row(
                children: <Widget>[
                  Icon(
                    inputLabel.contains('PRESSURE ') || stylusDetected
                        ? Icons.draw
                        : Icons.touch_app_outlined,
                    size: 14,
                    color: inputLabel.contains('PRESSURE ')
                        ? InkbookColors.toolYellow
                        : cream.withAlpha(150),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      inputLabel.isNotEmpty
                          ? inputLabel
                          : (stylusDetected
                              ? 'STYLUS PRESSURE'
                              : 'DRAW TO CHECK PRESSURE'),
                      overflow: TextOverflow.ellipsis,
                      style: meta,
                    ),
                  ),
                ],
              ),
            ),
          ),
          RoundAction(
            icon: Icons.chevron_left,
            tooltip: 'Previous page',
            size: 38,
            onTap: pageIndex > 0 ? onPrevious : null,
          ),
          const SizedBox(width: 8),
          RoundAction(
            icon: Icons.delete_outline,
            tooltip: 'Delete page',
            size: 38,
            onTap: onDelete,
          ),
          const SizedBox(width: 8),
          RoundAction(
            icon: Icons.add,
            tooltip: 'Add page',
            size: 38,
            active: true,
            onTap: onAdd,
          ),
          const SizedBox(width: 8),
          RoundAction(
            icon: Icons.chevron_right,
            tooltip: 'Next page',
            size: 38,
            onTap: pageIndex < pageCount - 1 ? onNext : null,
          ),
          Expanded(
            child: Text(
              '$strokeCount STROKES',
              textAlign: TextAlign.right,
              style: meta,
            ),
          ),
        ],
      ),
    );
  }
}
