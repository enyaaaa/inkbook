import 'dart:typed_data';

/// A piece of artwork shared to the community feed.
///
/// [imageBytes] is set when the artwork was exported from a real sketchbook
/// page. Sample artworks leave it null and are drawn procedurally by
/// [ArtworkThumbnail] so the prototype needs no bundled image assets.
class Artwork {
  Artwork({
    required this.id,
    required this.title,
    required this.artistId,
    required this.createdAt,
    this.tags = const <String>[],
    this.likeCount = 0,
    this.isLiked = false,
    this.imageBytes,
    this.aspectRatio = 0.75,
  });

  final String id;
  final String title;
  final String artistId;
  final DateTime createdAt;
  final List<String> tags;
  int likeCount;
  bool isLiked;
  final Uint8List? imageBytes;

  /// width / height - used to lay the feed out as a staggered grid.
  final double aspectRatio;

  /// Stable seed for the procedural placeholder painter.
  int get seed =>
      id.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7fffffff);
}
