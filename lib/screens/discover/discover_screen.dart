import 'package:flutter/material.dart';

import '../../controllers/app_state.dart';
import '../../models/artist.dart';
import '../../models/artwork.dart';
import '../../models/sketchbook.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile_form.dart';
import '../../widgets/artwork_thumbnail.dart';
import '../../widgets/scrapbook.dart';
import '../draw/draw_screen.dart';
import '../library/flip_book.dart';

/// The community feed, pinned up as a wall of taped polaroids.
class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        state.community,
        state.moodBoard,
      ]),
      builder: (context, _) {
        final community = state.community;
        if (community.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final feed = community.feed;
        void openArtist(String id) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ArtistProfileScreen(artistId: id),
              ),
            );

        return ListView(
          padding: EdgeInsets.fromLTRB(
            InkbookLayout.gutter(context),
            22,
            InkbookLayout.gutter(context),
            48,
          ),
          children: <Widget>[
            ScrapHeading(
              title: 'Discover',
              subtitle: '${feed.length} pieces from the community',
              icon: Icons.explore_outlined,
              aside: 'what everyone else is drawing today',
            ),
            const SizedBox(height: 22),
            Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(
                  children: <Widget>[
                    for (final artist in community.artists)
                      if (!artist.isCurrentUser)
                        _ArtistStamp(
                          artist: artist,
                          onTap: () => openArtist(artist.id),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            Masonry(
              itemCount: feed.length,
              heightOf: (i, w) => ArtworkCard.heightFor(feed[i], w),
              itemBuilder: (context, index) {
                final artwork = feed[index];
                return ArtworkCard(
                  artwork: artwork,
                  artist: community.artistById(artwork.artistId),
                  saved: state.moodBoard.contains(artwork.id),
                  onLike: () => community.toggleLike(artwork),
                  onSave: () => state.moodBoard.toggle(artwork),
                  onArtistTap: () => openArtist(artwork.artistId),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// An artist avatar drawn like a round rubber stamp / sticker.
class _ArtistStamp extends StatelessWidget {
  const _ArtistStamp({required this.artist, required this.onTap});

  final Artist artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = InkbookColors.covers[
        artist.id.codeUnits.fold<int>(0, (a, b) => a + b) %
            InkbookColors.covers.length];
    return Padding(
      padding: const EdgeInsets.only(right: 18),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: <Widget>[
            Container(
              width: 62,
              height: 62,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: InkbookColors.paper,
                boxShadow: paperShadow(lift: 0.5),
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tint,
                  border: Border.all(
                    color: artist.isFollowing
                        ? InkbookColors.ink
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  artist.name.substring(0, 1),
                  style: InkbookType.wordmark(
                    size: 26,
                    color: tint.computeLuminance() > 0.45
                        ? InkbookColors.ink
                        : InkbookColors.folderCream,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 76,
              child: Text(
                artist.name.split(' ').first.toLowerCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: InkbookType.body(size: 12, weight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A shared piece of artwork as a taped polaroid: the title is written on
/// the frame, the like count sits beside it, the artist's handle underneath.
class ArtworkCard extends StatelessWidget {
  const ArtworkCard({
    super.key,
    required this.artwork,
    required this.artist,
    required this.saved,
    required this.onLike,
    required this.onSave,
    this.onArtistTap,
  });

  final Artwork artwork;
  final Artist artist;
  final bool saved;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final VoidCallback? onArtistTap;

  /// The height a card needs at [width] so the photo keeps its aspect ratio.
  static double heightFor(Artwork artwork, double width) =>
      (width - 18) / artwork.aspectRatio + 9 + 44 + 26;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: scrapTilt(artwork.seed, max: 0.03),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Polaroid(
                  caption: artwork.title,
                  captionTrailing: InkWell(
                    onTap: onLike,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            artwork.isLiked
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 15,
                            color: artwork.isLiked
                                ? InkbookColors.toolOrange
                                : InkbookColors.inkSoft,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${artwork.likeCount}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: InkbookColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      ArtworkThumbnail(artwork: artwork, radius: 0),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: _PinButton(saved: saved, onTap: onSave),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 26,
                child: GestureDetector(
                  onTap: onArtistTap,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, left: 2),
                    child: Text(
                      artist.handle.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: InkbookType.eyebrow(
                        color: InkbookColors.ink.withAlpha(180),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: -10,
            left: 0,
            right: 0,
            child: Center(
              child: WashiTape(
                color: scrapTape(artwork.seed),
                angle: scrapTilt(artwork.seed + 3, max: 0.12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinButton extends StatelessWidget {
  const _PinButton({required this.saved, required this.onTap});

  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: saved ? 'Remove from mood board' : 'Pin to mood board',
      child: Material(
        color: saved ? InkbookColors.tray : Colors.white.withAlpha(225),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(
              saved ? Icons.push_pin : Icons.push_pin_outlined,
              size: 15,
              color: saved ? InkbookColors.toolYellow : InkbookColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// A single artist's profile: bio, follower count and their artwork.
///
/// [embedded] is true when shown inside the home folders; otherwise it is a
/// pushed route and brings its own desk and folder.
class ArtistProfileScreen extends StatelessWidget {
  const ArtistProfileScreen({
    super.key,
    required this.artistId,
    this.embedded = false,
  });

  final String artistId;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    final content = ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        state.community,
        state.moodBoard,
        state.sketchbooks,
      ]),
      builder: (context, _) {
        final community = state.community;
        final artist = community.artistById(artistId);
        final works = community.artworksBy(artistId);
        final wide = MediaQuery.sizeOf(context).width >= 720;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            InkbookLayout.gutter(context),
            22,
            InkbookLayout.gutter(context),
            48,
          ),
          children: <Widget>[
            if (!embedded)
              Align(
                alignment: Alignment.centerLeft,
                child: RingButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Back',
                  color: InkbookColors.ink,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 28,
              runSpacing: 18,
              children: <Widget>[
                _ProfilePhoto(artist: artist),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 460 : 320),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        artist.handle.toUpperCase(),
                        style: InkbookType.eyebrow(
                          color: InkbookColors.ink.withAlpha(170),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        artist.name,
                        style: InkbookType.title(size: wide ? 34 : 26),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        artist.bio,
                        style: InkbookType.body(size: 15),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: <Widget>[
                          _Stat(
                              value: '${artist.followerCount}',
                              label: 'followers'),
                          const SizedBox(width: 22),
                          _Stat(value: '${works.length}', label: 'pieces'),
                          const SizedBox(width: 22),
                          if (!artist.isCurrentUser)
                            artist.isFollowing
                                ? OutlinedButton(
                                    onPressed: () =>
                                        community.toggleFollow(artist),
                                    child: const Text('Following'),
                                  )
                                : FilledButton(
                                    onPressed: () =>
                                        community.toggleFollow(artist),
                                    child: const Text('Follow'),
                                  ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (artist.isCurrentUser && embedded) ...<Widget>[
              const SizedBox(height: 24),
              const _AccountPanel(),
            ],
            if (artist.isCurrentUser) ...<Widget>[
              const SizedBox(height: 36),
              _SectionLabel(
                'Your sketchbooks · ${state.sketchbooks.sketchbooks.length}',
              ),
              const SizedBox(height: 16),
              _MySketchbooks(books: state.sketchbooks.sketchbooks),
              const SizedBox(height: 36),
              _SectionLabel('Shared to Discover · ${works.length}'),
            ],
            const SizedBox(height: 40),
            if (works.isEmpty)
              Center(
                child: Text(
                  artist.isCurrentUser
                      ? 'nothing shared yet - share a page from\nany sketchbook and it will be pinned here'
                      : 'nothing shared yet',
                  textAlign: TextAlign.center,
                  style: InkbookType.body(
                    color: InkbookColors.ink.withAlpha(170),
                  ),
                ),
              )
            else
              Masonry(
                itemCount: works.length,
                maxColumnWidth: 260,
                heightOf: (i, w) => ArtworkCard.heightFor(works[i], w),
                itemBuilder: (context, index) {
                  final artwork = works[index];
                  return ArtworkCard(
                    artwork: artwork,
                    artist: artist,
                    saved: state.moodBoard.contains(artwork.id),
                    onLike: () => community.toggleLike(artwork),
                    onSave: () => state.moodBoard.toggle(artwork),
                  );
                },
              ),
          ],
        );
      },
    );

    if (embedded) return content;

    return Scaffold(
      backgroundColor: InkbookColors.desk,
      body: GrainSurface(
        color: InkbookColors.desk,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
              child: GrainSurface(
                color: InkbookColors.folderSage,
                grain: InkbookColors.ink,
                density: 0.55,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The profile picture as a taped instant photo with the artist's initial.
class _ProfilePhoto extends StatelessWidget {
  const _ProfilePhoto({required this.artist});

  final Artist artist;

  @override
  Widget build(BuildContext context) {
    final tint = InkbookColors.covers[
        artist.id.codeUnits.fold<int>(0, (a, b) => a + b) %
            InkbookColors.covers.length];
    return Transform.rotate(
      angle: -0.05,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          SizedBox(
            width: 140,
            height: 170,
            child: Polaroid(
              caption: artist.name.split(' ').first.toLowerCase(),
              child: ColoredBox(
                color: tint,
                child: Center(
                  child: Text(
                    artist.name.substring(0, 1),
                    style: InkbookType.wordmark(
                      size: 60,
                      color: tint.computeLuminance() > 0.45
                          ? InkbookColors.ink
                          : InkbookColors.folderCream,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            top: -9,
            left: 34,
            child: WashiTape(angle: 0.1, color: Color(0xCCF1DD9B)),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(value, style: InkbookType.title(size: 24)),
        Text(label.toUpperCase(),
            style: InkbookType.eyebrow(
              color: InkbookColors.ink.withAlpha(170),
            )),
      ],
    );
  }
}

/// Account controls on your own profile: email, edit profile, sign out.
class _AccountPanel extends StatelessWidget {
  const _AccountPanel();

  @override
  Widget build(BuildContext context) {
    final account = AppScope.of(context).account;
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) => Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: <Widget>[
          if (account.email != null)
            Text(
              account.email!,
              style: InkbookType.body(
                size: 13,
                color: InkbookColors.ink.withAlpha(170),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => showEditProfile(context),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit profile'),
          ),
          TextButton(
            onPressed: account.isBusy ? null : account.signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          text.toUpperCase(),
          style: InkbookType.eyebrow(color: InkbookColors.ink.withAlpha(180)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Divider(color: InkbookColors.ink.withAlpha(40)),
        ),
      ],
    );
  }
}

/// The signed-in artist's own sketchbooks, as covers. Tap one to draw in it.
class _MySketchbooks extends StatelessWidget {
  const _MySketchbooks({required this.books});

  final List<Sketchbook> books;

  void _open(BuildContext context, Sketchbook book) {
    AppScope.of(context).sketchbooks.open(book);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DrawScreen(sketchbook: book)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return Text(
        'No sketchbooks yet - start one from the Sketchbooks tab.',
        style: InkbookType.body(color: InkbookColors.ink.withAlpha(170)),
      );
    }
    return Wrap(
      spacing: 22,
      runSpacing: 22,
      children: <Widget>[
        for (final book in books)
          SizedBox(
            width: 120,
            child: GestureDetector(
              onTap: () => _open(context, book),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    height: 150,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: FlipBook.aspectOf(book),
                        child: BookCover(book: book),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: InkbookType.body(size: 13, weight: FontWeight.w600),
                  ),
                  Text(
                    book.size.isInfinite
                        ? 'WHITEBOARD'
                        : '${book.pageCount} PAGE${book.pageCount == 1 ? '' : 'S'}',
                    style: InkbookType.eyebrow(
                      color: InkbookColors.ink.withAlpha(160),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
