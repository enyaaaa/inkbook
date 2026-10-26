import 'dart:async';

import '../models/artist.dart';
import '../models/artwork.dart';
import '../models/sketchbook.dart';
import 'sample_data.dart';

/// A profile change the backend refused, with a message for the user.
class ProfileFailure implements Exception {
  const ProfileFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Everything the app needs to persist, expressed as an interface.
///
/// [InMemoryStorageService] keeps everything in memory (offline demos and
/// tests); `FirestoreStorageService` is the real backend. `main.dart` picks
/// one - nothing else in the app knows which is in use.
abstract class StorageService {
  /// The signed-in user's profile, or null if they have not set one up yet
  /// (a brand-new account).
  Future<Artist?> loadMyProfile();

  /// First-time profile set-up for a new account. Claims the unique
  /// @username. Throws [ProfileFailure] if it is invalid or taken.
  Future<Artist> createProfile({
    required String name,
    required String handle,
    required String bio,
  });

  /// Updates the signed-in user's name, unique @handle and bio. Throws
  /// [ProfileFailure] if the handle is invalid or already taken.
  Future<Artist> updateProfile({
    required String name,
    required String handle,
    required String bio,
  });

  /// Whether [handle] is free for the current user to take (their own
  /// current username counts as available).
  Future<bool> isHandleAvailable(String handle);

  Future<List<Sketchbook>> loadSketchbooks();
  Future<void> saveSketchbook(Sketchbook sketchbook);
  Future<void> deleteSketchbook(String id);

  Future<List<Artwork>> loadFeed();
  Future<List<Artist>> loadArtists();
  Future<void> publishArtwork(Artwork artwork);
  Future<void> setLiked(String artworkId, bool liked);
  Future<void> setFollowing(String artistId, bool following);
}

/// Local, volatile implementation used by the prototype.
///
/// The small artificial delays are deliberate: they keep the UI honest about
/// the fact that the real implementation will be asynchronous and network
/// bound, so loading and empty states get exercised during user testing.
class InMemoryStorageService implements StorageService {
  InMemoryStorageService({this.latency = const Duration(milliseconds: 220)});

  final Duration latency;

  final List<Sketchbook> _sketchbooks = SampleData.sketchbooks();
  final List<Artwork> _feed = SampleData.artworks();
  final List<Artist> _artists = SampleData.artists();

  Future<T> _delayed<T>(T value) => Future<T>.delayed(latency, () => value);

  @override
  Future<Artist?> loadMyProfile() =>
      _delayed<Artist?>(_artists.firstWhere((a) => a.isCurrentUser));

  @override
  Future<Artist> createProfile({
    required String name,
    required String handle,
    required String bio,
  }) =>
      updateProfile(name: name, handle: handle, bio: bio);

  @override
  Future<Artist> updateProfile({
    required String name,
    required String handle,
    required String bio,
  }) async {
    final me = _artists.firstWhere((a) => a.isCurrentUser);
    final clean = handle.trim().replaceFirst('@', '');
    me
      ..name = name.trim().isEmpty ? me.name : name.trim()
      ..handle = clean.isEmpty ? me.handle : '@$clean'
      ..bio = bio.trim();
    return _delayed(me);
  }

  @override
  Future<bool> isHandleAvailable(String handle) async {
    final clean = '@${handle.trim().toLowerCase().replaceFirst('@', '')}';
    return _delayed(
      !_artists.any((a) => !a.isCurrentUser && a.handle.toLowerCase() == clean),
    );
  }

  @override
  Future<List<Sketchbook>> loadSketchbooks() =>
      _delayed(List<Sketchbook>.of(_sketchbooks));

  @override
  Future<void> saveSketchbook(Sketchbook sketchbook) async {
    final index = _sketchbooks.indexWhere((s) => s.id == sketchbook.id);
    if (index == -1) {
      _sketchbooks.add(sketchbook);
    } else {
      _sketchbooks[index] = sketchbook;
    }
    await _delayed<void>(null);
  }

  @override
  Future<void> deleteSketchbook(String id) async {
    _sketchbooks.removeWhere((s) => s.id == id);
    await _delayed<void>(null);
  }

  @override
  Future<List<Artwork>> loadFeed() => _delayed(List<Artwork>.of(_feed));

  @override
  Future<List<Artist>> loadArtists() => _delayed(List<Artist>.of(_artists));

  @override
  Future<void> publishArtwork(Artwork artwork) async {
    _feed.insert(0, artwork);
    await _delayed<void>(null);
  }

  @override
  Future<void> setLiked(String artworkId, bool liked) async {
    // In the Firebase implementation this would be a transaction on the
    // artwork document plus a write to the user's `likes` subcollection.
    await _delayed<void>(null);
  }

  @override
  Future<void> setFollowing(String artistId, bool following) async {
    await _delayed<void>(null);
  }
}
