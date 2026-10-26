/// A profile in the INKBOOK community: sample artists from [SampleData]
/// plus real users loaded from Firestore.
class Artist {
  Artist({
    required this.id,
    required this.name,
    required this.handle,
    required this.bio,
    this.followerCount = 0,
    this.isFollowing = false,
    this.isCurrentUser = false,
  });

  final String id;
  String name;
  String handle;
  String bio;
  int followerCount;
  bool isFollowing;
  final bool isCurrentUser;
}
