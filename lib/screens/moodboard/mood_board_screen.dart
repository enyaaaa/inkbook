import 'package:flutter/material.dart';

import '../../controllers/app_state.dart';
import '../../models/mood_board_item.dart';
import '../../theme/app_theme.dart';
import '../../widgets/artwork_thumbnail.dart';
import '../../widgets/scrapbook.dart';

/// The user's personal collection of inspiration - their own pages plus
/// artwork pinned from the feed - laid out as a taped-up collage with
/// handwritten notes.
class MoodBoardScreen extends StatefulWidget {
  const MoodBoardScreen({super.key});

  @override
  State<MoodBoardScreen> createState() => _MoodBoardScreenState();
}

class _MoodBoardScreenState extends State<MoodBoardScreen> {
  String _collection = 'All';

  static const double _noteHeight = 74;

  String _stamp(MoodBoardSource source) {
    switch (source) {
      case MoodBoardSource.ownWork:
        return 'MINE';
      case MoodBoardSource.savedFromFeed:
        return 'PINNED';
      case MoodBoardSource.reference:
        return 'REF';
    }
  }

  Future<void> _annotate(MoodBoardItem item) async {
    final board = AppScope.of(context).moodBoard;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => _NoteDialog(item: item),
    );
    if (result != null) {
      board.annotate(item, note: result.$1, collection: result.$2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return ListenableBuilder(
      listenable: state.moodBoard,
      builder: (context, _) {
        final board = state.moodBoard;
        if (!board.collections.contains(_collection)) _collection = 'All';
        final items = board.inCollection(_collection);

        return ListView(
          padding: EdgeInsets.fromLTRB(
            InkbookLayout.gutter(context),
            22,
            InkbookLayout.gutter(context),
            56,
          ),
          children: <Widget>[
            ScrapHeading(
              title: 'Mood board',
              subtitle: '${board.items.length} things that caught your eye',
              icon: Icons.push_pin_outlined,
              aside: 'collect what moves you, draw what it teaches you',
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                for (final collection in board.collections)
                  _CollectionLabel(
                    label: collection == 'All' ? 'everything' : collection,
                    selected: _collection == collection,
                    seed: collection.hashCode,
                    onTap: () => setState(() => _collection = collection),
                  ),
              ],
            ),
            const SizedBox(height: 34),
            if (board.items.isEmpty)
              const _EmptyBoard()
            else
              Masonry(
                itemCount: items.length,
                maxColumnWidth: 250,
                spacing: 30,
                runSpacing: 30,
                heightOf: (i, w) =>
                    (w - 18) / items[i].artwork.aspectRatio +
                    9 +
                    44 +
                    (items[i].note.isEmpty ? 0 : _noteHeight - 14),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _Scrap(
                    item: item,
                    stamp: _stamp(item.source),
                    noteHeight: _noteHeight,
                    onRemove: () => board.remove(item.artwork.id),
                    onAnnotate: () => _annotate(item),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

/// Edits a pin's note and collection. Owns its text controllers so they
/// outlive the dialog's closing animation.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.item});

  final MoodBoardItem item;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _note =
      TextEditingController(text: widget.item.note);
  late final TextEditingController _collection = TextEditingController(
    text: widget.item.collection == 'All' ? '' : widget.item.collection,
  );

  @override
  void dispose() {
    _note.dispose();
    _collection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scribble a note'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _note,
              autofocus: true,
              maxLines: 3,
              style: InkbookType.handwritten(size: 19),
              decoration: const InputDecoration(
                labelText: 'NOTE',
                hintText: 'what do you love about it?',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _collection,
              style: InkbookType.body(size: 16),
              decoration: const InputDecoration(
                labelText: 'COLLECTION',
                hintText: 'e.g. colour, studies, mood',
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (_note.text, _collection.text)),
          child: const Text('Stick it on'),
        ),
      ],
    );
  }
}

/// One pinned piece: a polaroid, a strip of tape, a source stamp and - if
/// the user wrote one - a torn scrap of paper with their note, tucked under
/// the bottom edge.
class _Scrap extends StatelessWidget {
  const _Scrap({
    required this.item,
    required this.stamp,
    required this.noteHeight,
    required this.onRemove,
    required this.onAnnotate,
  });

  final MoodBoardItem item;
  final String stamp;
  final double noteHeight;
  final VoidCallback onRemove;
  final VoidCallback onAnnotate;

  @override
  Widget build(BuildContext context) {
    final seed = item.artwork.seed;
    final hasNote = item.note.isNotEmpty;

    return GestureDetector(
      onTap: onAnnotate,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            bottom: hasNote ? noteHeight - 14 : 0,
            child: Transform.rotate(
              angle: scrapTilt(seed, max: 0.05),
              child: Polaroid(
                caption: item.artwork.title,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ArtworkThumbnail(artwork: item.artwork, radius: 0),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Transform.rotate(
                        angle: -0.08,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: InkbookColors.toolOrange.withAlpha(200),
                              width: 1.4,
                            ),
                            borderRadius: BorderRadius.circular(3),
                            color: Colors.white.withAlpha(150),
                          ),
                          child: Text(
                            stamp,
                            style: InkbookType.eyebrow(
                              color: InkbookColors.toolOrange,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Material(
                        color: Colors.white.withAlpha(210),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onRemove,
                          child: const Tooltip(
                            message: 'Unpin',
                            child: Padding(
                              padding: EdgeInsets.all(5),
                              child: Icon(Icons.close, size: 14),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (hasNote)
            Positioned(
              left: 14,
              right: 2,
              bottom: 0,
              height: noteHeight,
              child: Transform.rotate(
                angle: scrapTilt(seed + 7, max: 0.06),
                child: TornPaper(
                  seed: seed,
                  tornTop: true,
                  color: const Color(0xFFF6F0DF),
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item.note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: InkbookType.handwritten(size: 17),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: -11,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment(scrapTilt(seed + 1, max: 0.6) * 1.2, 0),
              child: WashiTape(
                color: scrapTape(seed + 2),
                angle: scrapTilt(seed + 5, max: 0.18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A collection filter as a little paper label with tape across the top.
class _CollectionLabel extends StatelessWidget {
  const _CollectionLabel({
    required this.label,
    required this.selected,
    required this.seed,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final int seed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Transform.rotate(
        angle: scrapTilt(seed, max: 0.04),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? InkbookColors.tray : InkbookColors.paper,
            borderRadius: BorderRadius.circular(2),
            boxShadow: paperShadow(lift: selected ? 0.7 : 0.35),
          ),
          child: Text(
            label,
            style: InkbookType.body(
              size: 13,
              weight: FontWeight.w600,
              color: selected ? InkbookColors.folderCream : InkbookColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 360,
        child: Transform.rotate(
          angle: -0.02,
          child: TornPaper(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 30),
            child: Text(
              'nothing pinned yet.\n\ntap the pin on anything in Discover, '
              'or save a page while you draw, and it will end up here.',
              textAlign: TextAlign.center,
              style: InkbookType.handwritten(size: 19),
            ),
          ),
        ),
      ),
    );
  }
}
