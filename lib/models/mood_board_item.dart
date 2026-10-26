import 'artwork.dart';

/// Why an item ended up on the mood board - shown as a small chip so the user
/// can tell their own work apart from saved references.
enum MoodBoardSource { ownWork, savedFromFeed, reference }

class MoodBoardItem {
  MoodBoardItem({
    required this.id,
    required this.artwork,
    required this.savedAt,
    required this.source,
    this.note = '',
    this.collection = 'All',
  });

  final String id;
  final Artwork artwork;
  final DateTime savedAt;
  final MoodBoardSource source;
  String note;
  String collection;
}
