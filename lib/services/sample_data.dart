import '../models/artist.dart';
import '../models/artwork.dart';
import '../models/sketchbook.dart';

/// Placeholder content so the prototype can be demonstrated and user-tested
/// with a populated feed. Replace with real Firestore queries later.
class SampleData {
  const SampleData._();

  static final DateTime _now = DateTime(2026, 9, 17);

  static List<Artist> artists() => <Artist>[
        Artist(
          id: 'u-me',
          name: 'You',
          handle: '@you',
          bio: 'Sketching most days. Mostly ink, occasionally watercolour.',
          followerCount: 42,
          isCurrentUser: true,
        ),
        Artist(
          id: 'u-mira',
          name: 'Mira Tan',
          handle: '@mirasketches',
          bio: 'Urban sketcher. Coffee shops, void decks, five-foot ways.',
          followerCount: 12400,
          isFollowing: true,
        ),
        Artist(
          id: 'u-kai',
          name: 'Kai Rahman',
          handle: '@kai.inks',
          bio: 'Ink and brush pen. Creatures that should not exist.',
          followerCount: 8300,
        ),
        Artist(
          id: 'u-noor',
          name: 'Noor Aziz',
          handle: '@noordraws',
          bio: 'Studying anatomy one hand at a time.',
          followerCount: 3100,
          isFollowing: true,
        ),
        Artist(
          id: 'u-wen',
          name: 'Wen Li',
          handle: '@wenli.studio',
          bio: 'Botanical studies and quiet interiors.',
          followerCount: 21800,
        ),
      ];

  static List<Artwork> artworks() => <Artwork>[
        Artwork(
          id: 'a-01',
          title: 'Morning at the hawker centre',
          artistId: 'u-mira',
          createdAt: _now.subtract(const Duration(hours: 5)),
          tags: <String>['urban', 'ink', 'observation'],
          likeCount: 842,
          aspectRatio: 0.78,
        ),
        Artwork(
          id: 'a-02',
          title: 'Study of a resting hand',
          artistId: 'u-noor',
          createdAt: _now.subtract(const Duration(hours: 9)),
          tags: <String>['anatomy', 'pencil'],
          likeCount: 311,
          isLiked: true,
          aspectRatio: 1.0,
        ),
        Artwork(
          id: 'a-03',
          title: 'Something in the reservoir',
          artistId: 'u-kai',
          createdAt: _now.subtract(const Duration(days: 1)),
          tags: <String>['creature', 'ink'],
          likeCount: 1290,
          aspectRatio: 0.7,
        ),
        Artwork(
          id: 'a-04',
          title: 'Monstera, third attempt',
          artistId: 'u-wen',
          createdAt: _now.subtract(const Duration(days: 1, hours: 8)),
          tags: <String>['botanical', 'graphite'],
          likeCount: 654,
          aspectRatio: 0.82,
        ),
        Artwork(
          id: 'a-05',
          title: 'Bus 174, upper deck',
          artistId: 'u-mira',
          createdAt: _now.subtract(const Duration(days: 2)),
          tags: <String>['urban', 'people'],
          likeCount: 487,
          aspectRatio: 1.35,
        ),
        Artwork(
          id: 'a-06',
          title: 'Thirty-second gestures',
          artistId: 'u-noor',
          createdAt: _now.subtract(const Duration(days: 2, hours: 4)),
          tags: <String>['practice', 'figure'],
          likeCount: 205,
          aspectRatio: 0.92,
        ),
        Artwork(
          id: 'a-07',
          title: 'Rain on the way home',
          artistId: 'u-wen',
          createdAt: _now.subtract(const Duration(days: 3)),
          tags: <String>['mood', 'wash'],
          likeCount: 1502,
          isLiked: true,
          aspectRatio: 0.66,
        ),
        Artwork(
          id: 'a-08',
          title: 'Shophouse facade',
          artistId: 'u-kai',
          createdAt: _now.subtract(const Duration(days: 4)),
          tags: <String>['architecture', 'ink'],
          likeCount: 733,
          aspectRatio: 1.1,
        ),
      ];

  static List<Sketchbook> sketchbooks() => <Sketchbook>[
        Sketchbook(
          id: 'sb-daily',
          title: 'Daily sketches',
          createdAt: _now.subtract(const Duration(days: 26)),
          paper: PaperStyle.plain,
          coverIndex: 0,
        ),
        Sketchbook(
          id: 'sb-anatomy',
          title: 'Anatomy practice',
          createdAt: _now.subtract(const Duration(days: 12)),
          paper: PaperStyle.dotted,
          coverIndex: 1,
        ),
        Sketchbook(
          id: 'sb-ideas',
          title: 'Ideas & thumbnails',
          createdAt: _now.subtract(const Duration(days: 3)),
          paper: PaperStyle.toned,
          coverIndex: 2,
        ),
      ];
}
