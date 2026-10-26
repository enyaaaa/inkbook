import 'package:flutter/material.dart';

import '../controllers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/scrapbook.dart';
import 'discover/discover_screen.dart';
import 'library/library_screen.dart';
import 'moodboard/mood_board_screen.dart';

/// Top-level navigation, styled as a stack of index folders on a desk.
///
/// Each destination is a folder with its own coloured tab; the selected one
/// slides to the front and its paper becomes the page. The same layout works
/// on tablet and phone - the tabs just get narrower.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const List<FolderDestination> destinations = <FolderDestination>[
    FolderDestination('sketchbooks', InkbookColors.folderCream),
    FolderDestination('discover', InkbookColors.folderLavender),
    FolderDestination('mood board', InkbookColors.folderRose),
    FolderDestination('profile', InkbookColors.folderSage),
  ];

  Widget _screen(int index) {
    switch (index) {
      case 0:
        return const LibraryScreen();
      case 1:
        return const DiscoverScreen();
      case 2:
        return const MoodBoardScreen();
      default:
        return ArtistProfileScreen(
          artistId: AppScope.of(context).community.currentUser.id,
          embedded: true,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 720;
    final folder = destinations[_index].color;

    return Scaffold(
      backgroundColor: InkbookColors.desk,
      body: GrainSurface(
        color: InkbookColors.desk,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Masthead(wide: wide),
              FolderTabs(
                destinations: destinations,
                selected: _index,
                onSelected: (i) => setState(() => _index = i),
              ),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  color: folder,
                  child: GrainSurface(
                    color: folder,
                    grain: InkbookColors.ink,
                    density: 0.55,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: KeyedSubtree(
                        key: ValueKey<int>(_index),
                        child: _screen(_index),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The big serif wordmark across the top of the desk, with the tiny
/// staggered corner note and a handwritten byline.
class _Masthead extends StatelessWidget {
  const _Masthead({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final cream = InkbookColors.folderCream;
    return SizedBox(
      height: wide ? 84 : 58,
      child: Stack(
        children: <Widget>[
          if (wide)
            Positioned(
              left: 22,
              top: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('AN  INTERACTIVE',
                      style: InkbookType.eyebrow(color: cream)),
                  Padding(
                    padding: const EdgeInsets.only(left: 30),
                    child: Text('DIGITAL',
                        style: InkbookType.eyebrow(color: cream)),
                  ),
                  Text('SKETCHBOOK', style: InkbookType.eyebrow(color: cream)),
                ],
              ),
            ),
          Align(
            alignment: wide ? const Alignment(0, 0.1) : const Alignment(0, 0.4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  wide ? CrossAxisAlignment.end : CrossAxisAlignment.center,
              children: <Widget>[
                Text(
                  'Inkbook',
                  style: InkbookType.wordmark(
                    size: wide ? 46 : 30,
                    color: cream,
                  ),
                ),
                Transform.translate(
                  offset: Offset(wide ? 30 : 0, wide ? -4 : -1),
                  child: Text(
                    'by you, one page at a time',
                    style: InkbookType.handwritten(
                      size: wide ? 15 : 12,
                      color: cream.withAlpha(210),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FolderDestination {
  const FolderDestination(this.label, this.color);

  final String label;
  final Color color;
}

/// The overlapping folder tabs. Every folder is a full-width band with one
/// tab bump; back folders sit a little higher so their colour shows as a
/// stripe, and the selected folder is drawn last, in front.
class FolderTabs extends StatelessWidget {
  const FolderTabs({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelected,
  });

  final List<FolderDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelected;

  static const double tabHeight = 34;
  static const double stripe = 9;

  @override
  Widget build(BuildContext context) {
    final backCount = destinations.length - 1;
    final height = tabHeight + stripe * backCount + 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= 720;
        final margin = wide ? 40.0 : 10.0;
        final slot = (width - margin * 2) / destinations.length;
        final tabWidth = (slot * 0.94).clamp(80.0, 210.0);

        double tabLeft(int i) => margin + slot * i + (slot - tabWidth) / 2;
        // Back folders step down in index order; the front one sits lowest.
        double layerTop(int i) {
          if (i == selected) return stripe * backCount;
          return stripe * (i < selected ? i : i - 1);
        }

        return SizedBox(
          height: height,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(
                  painter: _FolderPainter(
                    layers: <_FolderLayer>[
                      for (var i = 0; i < destinations.length; i++)
                        if (i != selected)
                          _FolderLayer(
                            destinations[i].color,
                            layerTop(i),
                            tabLeft(i),
                            tabWidth,
                            front: false,
                          ),
                      _FolderLayer(
                        destinations[selected].color,
                        layerTop(selected),
                        tabLeft(selected),
                        tabWidth,
                        front: true,
                      ),
                    ],
                    tabHeight: tabHeight,
                  ),
                ),
              ),
              for (var i = 0; i < destinations.length; i++)
                Positioned(
                  left: tabLeft(i),
                  top: layerTop(i),
                  width: tabWidth,
                  height: tabHeight,
                  child: Semantics(
                    button: true,
                    selected: i == selected,
                    label: destinations[i].label,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelected(i),
                      child: Center(
                        child: Text(
                          wide
                              ? '( ${destinations[i].label} )'
                              : destinations[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(
                            fontFamily: InkbookType.sans,
                            fontFamilyFallback: InkbookType.sansFallback,
                            fontSize: wide ? 13 : 11,
                            letterSpacing: 0.3,
                            fontWeight: i == selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: InkbookColors.ink
                                .withAlpha(i == selected ? 255 : 190),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FolderLayer {
  const _FolderLayer(
    this.color,
    this.top,
    this.tabLeft,
    this.tabWidth, {
    required this.front,
  });

  final Color color;
  final double top;
  final double tabLeft;
  final double tabWidth;
  final bool front;
}

class _FolderPainter extends CustomPainter {
  const _FolderPainter({required this.layers, required this.tabHeight});

  final List<_FolderLayer> layers;
  final double tabHeight;

  Path _shape(Size size, _FolderLayer layer) {
    final bandTop = layer.top + tabHeight;
    final l = layer.tabLeft;
    final r = layer.tabLeft + layer.tabWidth;
    const slope = 20.0;
    const round = 10.0;
    return Path()
      ..moveTo(0, bandTop)
      ..lineTo(l - 4, bandTop)
      ..cubicTo(l + slope * 0.45, bandTop, l + slope * 0.2, layer.top,
          l + slope + round * 0.4, layer.top)
      ..lineTo(r - slope - round * 0.4, layer.top)
      ..cubicTo(
          r - slope * 0.2, layer.top, r - slope * 0.45, bandTop, r + 4, bandTop)
      ..lineTo(size.width, bandTop)
      ..lineTo(size.width, size.height + 2)
      ..lineTo(0, size.height + 2)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final layer in layers) {
      final path = _shape(size, layer);
      canvas.drawShadow(path, Colors.black, layer.front ? 6 : 3, false);
      canvas.drawPath(path, Paint()..color = layer.color);
    }
  }

  @override
  bool shouldRepaint(_FolderPainter oldDelegate) => true;
}
