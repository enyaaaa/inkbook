import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/artist.dart';
import '../models/artwork.dart';
import '../models/sketch_page.dart';
import '../models/sketchbook.dart';
import '../utils/image_resize.dart';
import 'auth_service.dart';
import 'sample_data.dart';
import 'storage_service.dart';
import 'stroke_codec.dart';

/// [StorageService] backed by Cloud Firestore.
///
/// Data model (all documents are small; binary data is stored as `Blob`):
///
///     users/{uid}                        name, handle, bio, followerCount
///       sketchbooks/{bookId}             title, paper, coverIndex, pageIds
///         pages/{pageId}                 strokes (binary, see StrokeCodec)
///       thumbs/{pageId}                  png (page preview, <= 640px wide)
///       following/{artistId}             (presence = following)
///       likes/{artworkId}                (presence = liked)
///     handles/{handle}                   uid  - makes @handles unique
///     artworks/{id}                      title, artistId, tags, likeCount,
///                                        aspectRatio, image (png), createdAt
///
/// Images live in Firestore rather than Cloud Storage because the project is
/// on the free Spark plan. Moving them to Storage later only changes
/// [_putThumbnail], [publishArtwork] and the loaders below.
///
/// Writes are debounced per sketchbook and only pages whose strokes or
/// preview actually changed are rewritten, so drawing never waits on the
/// network; Firestore's offline cache queues anything written while offline.
class FirestoreStorageService implements StorageService {
  FirestoreStorageService({required this.auth, FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final AuthService auth;
  final FirebaseFirestore _db;

  /// The placeholder feed stays visible next to real posts so the demo is
  /// never empty. Their ids are recognised so likes/follows on them only
  /// touch the user's own documents.
  static final Set<String> _sampleArtworks =
      SampleData.artworks().map((a) => a.id).toSet();
  static final Set<String> _sampleArtists =
      SampleData.artists().map((a) => a.id).toSet();

  static const Duration _debounce = Duration(milliseconds: 700);

  String get _uid {
    final user = auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.uid;
  }

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection('users').doc(uid);
  DocumentReference<Map<String, dynamic>> get _me => _user(_uid);
  CollectionReference<Map<String, dynamic>> get _books =>
      _me.collection('sketchbooks');
  CollectionReference<Map<String, dynamic>> get _thumbs =>
      _me.collection('thumbs');

  // What has already been written, so saves only send what changed.
  final Map<String, String> _pageSignature = <String, String>{};
  final Map<String, Uint8List> _thumbWritten = <String, Uint8List>{};
  final Map<String, Set<String>> _bookPages = <String, Set<String>>{};
  final Map<String, Timer> _timers = <String, Timer>{};
  final Map<String, Sketchbook> _pending = <String, Sketchbook>{};

  // Filled by loadFeed, used by loadArtists.
  final Set<String> _feedAuthors = <String>{};

  // --- profile ---------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> get _handles =>
      _db.collection('handles');

  /// Handles nobody may claim: the sample artists shown in the feed, plus a
  /// few that would be confusing.
  static final Set<String> _reservedHandles = <String>{
    for (final artist in SampleData.artists()) normaliseHandle(artist.handle),
    'you',
    'guest',
    'admin',
    'inkbook',
  };

  static final RegExp _handlePattern = RegExp(r'^[a-z0-9._]{3,20}$');

  /// `@Mira.Sketches ` -> `mira.sketches`.
  static String normaliseHandle(String raw) =>
      raw.trim().toLowerCase().replaceFirst(RegExp('^@'), '');

  static Artist _artist(
    String id,
    Map<String, dynamic> data, {
    bool me = false,
    bool following = false,
  }) {
    return Artist(
      id: id,
      name: (data['name'] as String?) ?? '',
      handle: '@${(data['handle'] as String?) ?? ''}',
      bio: (data['bio'] as String?) ?? '',
      followerCount: (data['followerCount'] as num?)?.toInt() ?? 0,
      isFollowing: following,
      isCurrentUser: me,
    );
  }

  /// A profile counts as set up once it has a username.
  @override
  Future<Artist?> loadMyProfile() async {
    final data = (await _me.get()).data();
    if (data == null || ((data['handle'] as String?) ?? '').isEmpty) {
      return null;
    }
    return _artist(_uid, data, me: true);
  }

  Future<Artist> _requireMe() async {
    final me = await loadMyProfile();
    if (me == null) throw StateError('Profile not set up yet');
    return me;
  }

  void _validate(String name, String clean) {
    if (name.trim().isEmpty) {
      throw const ProfileFailure('Add a display name.');
    }
    if (!_handlePattern.hasMatch(clean)) {
      throw const ProfileFailure(
        'Usernames are 3-20 characters: letters, numbers, dots and '
        'underscores.',
      );
    }
    if (_reservedHandles.contains(clean)) {
      throw const ProfileFailure('That username is taken - try another.');
    }
  }

  @override
  Future<bool> isHandleAvailable(String handle) async {
    final clean = normaliseHandle(handle);
    if (!_handlePattern.hasMatch(clean) || _reservedHandles.contains(clean)) {
      return false;
    }
    final claim = await _handles.doc(clean).get();
    return !claim.exists || claim.data()?['uid'] == _uid;
  }

  @override
  Future<Artist> createProfile({
    required String name,
    required String handle,
    required String bio,
  }) =>
      _saveProfile(name: name, handle: handle, bio: bio, creating: true);

  @override
  Future<Artist> updateProfile({
    required String name,
    required String handle,
    required String bio,
  }) =>
      _saveProfile(name: name, handle: handle, bio: bio, creating: false);

  /// Claiming the new username, releasing the old one and writing the
  /// profile happen in one transaction, so two people can never end up with
  /// the same username even if they press save at the same moment.
  Future<Artist> _saveProfile({
    required String name,
    required String handle,
    required String bio,
    required bool creating,
  }) async {
    final clean = normaliseHandle(handle);
    _validate(name, clean);
    final uid = _uid;
    await _db.runTransaction((tx) async {
      final mine = await tx.get(_me);
      final previous = (mine.data()?['handle'] as String?) ?? '';
      if (clean != previous) {
        final claim = _handles.doc(clean);
        final existing = await tx.get(claim);
        if (existing.exists && existing.data()?['uid'] != uid) {
          throw const ProfileFailure('That username is taken - try another.');
        }
        if (!existing.exists) {
          tx.set(claim, <String, dynamic>{'uid': uid});
        }
        if (previous.isNotEmpty) tx.delete(_handles.doc(previous));
      }
      final fields = <String, dynamic>{
        'name': name.trim(),
        'handle': clean,
        'bio': bio.trim(),
      };
      if (!mine.exists) {
        tx.set(_me, <String, dynamic>{
          ...fields,
          'followerCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        tx.update(_me, fields);
      }
    });
    return _requireMe();
  }

  // --- sketchbooks -----------------------------------------------------------

  @override
  Future<List<Sketchbook>> loadSketchbooks() async {
    _pageSignature.clear();
    _thumbWritten.clear();
    _bookPages.clear();

    final books = await _books.orderBy('createdAt', descending: true).get();
    if (books.docs.isEmpty) {
      // Everyone starts with one empty book on their shelf.
      final first = Sketchbook(
        id: 'sb-${DateTime.now().millisecondsSinceEpoch}',
        title: 'My first sketchbook',
        createdAt: DateTime.now(),
        coverIndex: 0,
      );
      await saveSketchbook(first);
      return <Sketchbook>[first];
    }

    final thumbSnap = await _thumbs.get();
    final thumbs = <String, Uint8List>{
      for (final doc in thumbSnap.docs)
        if (doc.data()['png'] is Blob)
          doc.id: (doc.data()['png'] as Blob).bytes,
    };

    final result = <Sketchbook>[];
    for (final doc in books.docs) {
      final data = doc.data();
      final pageSnap = await doc.reference.collection('pages').get();
      final strokesById = <String, Uint8List>{
        for (final page in pageSnap.docs)
          if (page.data()['strokes'] is Blob)
            page.id: (page.data()['strokes'] as Blob).bytes,
      };
      final order = List<String>.from(data['pageIds'] as List? ?? <String>[]);
      final pages = <SketchPage>[
        for (final id in order)
          SketchPage(
            id: id,
            strokes: strokesById[id] == null
                ? null
                : StrokeCodec.decode(strokesById[id]!),
            thumbnail: thumbs[id],
          ),
      ];
      final book = Sketchbook(
        id: doc.id,
        title: (data['title'] as String?) ?? 'Untitled sketchbook',
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        paper: PaperStyle.values.firstWhere(
          (p) => p.name == data['paper'],
          orElse: () => PaperStyle.plain,
        ),
        size: PageSize.values.firstWhere(
          (s) => s.name == data['size'],
          orElse: () => PageSize.portrait,
        ),
        coverIndex: (data['coverIndex'] as num?)?.toInt(),
        pages: pages.isEmpty ? null : pages,
      );
      // Remember what is already stored so the first save is a no-op.
      _bookPages[book.id] = book.pages.map((p) => p.id).toSet();
      for (final page in book.pages) {
        _pageSignature[page.id] = _signature(page);
        if (page.thumbnail != null) _thumbWritten[page.id] = page.thumbnail!;
      }
      result.add(book);
    }
    return result;
  }

  /// Cheap fingerprint of a page's strokes: count, identity and length of
  /// the newest stroke. Changes on draw, undo, redo and clear.
  static String _signature(SketchPage page) {
    final strokes = page.strokes;
    if (strokes.isEmpty) return '0';
    final last = strokes.last;
    return '${strokes.length}:${identityHashCode(last)}:${last.points.length}';
  }

  @override
  Future<void> saveSketchbook(Sketchbook sketchbook) {
    _pending[sketchbook.id] = sketchbook;
    _timers[sketchbook.id]?.cancel();
    final done = Completer<void>();
    _timers[sketchbook.id] = Timer(_debounce, () {
      _flush(sketchbook.id).then(done.complete, onError: (Object e) {
        debugPrint('Saving ${sketchbook.id} failed: $e');
        done.complete();
      });
    });
    return done.future;
  }

  Future<void> _flush(String bookId) async {
    final book = _pending.remove(bookId);
    _timers.remove(bookId);
    if (book == null) return;

    final ref = _books.doc(book.id);
    final batch = _db.batch();
    batch.set(ref, <String, dynamic>{
      'title': book.title,
      'paper': book.paper.name,
      'size': book.size.name,
      'coverIndex': book.coverIndex,
      'pageIds': book.pages.map((p) => p.id).toList(),
      'createdAt': Timestamp.fromDate(book.createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final current = <String>{};
    for (final page in book.pages) {
      current.add(page.id);
      final signature = _signature(page);
      if (_pageSignature[page.id] != signature) {
        batch.set(ref.collection('pages').doc(page.id), <String, dynamic>{
          'strokes': Blob(StrokeCodec.encode(page.strokes)),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _pageSignature[page.id] = signature;
      }
      final thumb = page.thumbnail;
      if (thumb != null && !identical(_thumbWritten[page.id], thumb)) {
        // A preview that fails to shrink is skipped (and retried on the
        // next save) rather than losing the strokes in the same batch.
        try {
          final small = await shrinkPng(thumb);
          batch.set(_thumbs.doc(page.id), <String, dynamic>{
            'png': Blob(small),
          });
          _thumbWritten[page.id] = thumb;
        } catch (e) {
          debugPrint('Skipping preview for ${page.id}: $e');
        }
      }
    }

    // Pages deleted since the last save.
    for (final gone
        in (_bookPages[book.id] ?? <String>{}).difference(current)) {
      batch.delete(ref.collection('pages').doc(gone));
      batch.delete(_thumbs.doc(gone));
      _pageSignature.remove(gone);
      _thumbWritten.remove(gone);
    }
    _bookPages[book.id] = current;

    await batch.commit();
  }

  @override
  Future<void> deleteSketchbook(String id) async {
    _timers.remove(id)?.cancel();
    _pending.remove(id);
    final ref = _books.doc(id);
    final pages = await ref.collection('pages').get();
    final batch = _db.batch();
    for (final page in pages.docs) {
      batch.delete(page.reference);
      batch.delete(_thumbs.doc(page.id));
    }
    for (final pageId in _bookPages.remove(id) ?? <String>{}) {
      batch.delete(_thumbs.doc(pageId));
    }
    batch.delete(ref);
    await batch.commit();
  }

  // --- community -------------------------------------------------------------

  @override
  Future<List<Artwork>> loadFeed() async {
    final liked =
        (await _me.collection('likes').get()).docs.map((d) => d.id).toSet();
    final snap = await _db
        .collection('artworks')
        .orderBy('createdAt', descending: true)
        .limit(60)
        .get();

    _feedAuthors.clear();
    final real = <Artwork>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final artistId = data['artistId'] as String? ?? '';
      _feedAuthors.add(artistId);
      real.add(Artwork(
        id: doc.id,
        title: (data['title'] as String?) ?? 'Untitled',
        artistId: artistId,
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        tags: List<String>.from(data['tags'] as List? ?? <String>[]),
        likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
        isLiked: liked.contains(doc.id),
        imageBytes: (data['image'] as Blob?)?.bytes,
        aspectRatio: (data['aspectRatio'] as num?)?.toDouble() ?? 0.75,
      ));
    }

    final samples = SampleData.artworks();
    for (final sample in samples) {
      if (liked.contains(sample.id) && !sample.isLiked) {
        sample
          ..isLiked = true
          ..likeCount += 1;
      }
    }
    return <Artwork>[...real, ...samples]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<List<Artist>> loadArtists() async {
    final following =
        (await _me.collection('following').get()).docs.map((d) => d.id).toSet();
    final me = await _requireMe();

    final others =
        _feedAuthors.where((id) => id != me.id && id.isNotEmpty).toList();
    final real = <Artist>[];
    for (var i = 0; i < others.length; i += 10) {
      final chunk = others.sublist(i, (i + 10).clamp(0, others.length));
      final snap = await _db
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        real.add(
            _artist(doc.id, doc.data(), following: following.contains(doc.id)));
      }
    }

    final samples = SampleData.artists().where((a) => !a.isCurrentUser);
    for (final sample in samples) {
      final wasFollowing = sample.isFollowing;
      sample.isFollowing = wasFollowing || following.contains(sample.id);
      if (!wasFollowing && sample.isFollowing) sample.followerCount += 1;
    }
    return <Artist>[me, ...real, ...samples];
  }

  @override
  Future<void> publishArtwork(Artwork artwork) async {
    final bytes = artwork.imageBytes;
    await _db.collection('artworks').doc(artwork.id).set(<String, dynamic>{
      'title': artwork.title,
      'artistId': _uid,
      'tags': artwork.tags,
      'likeCount': 0,
      'aspectRatio': artwork.aspectRatio,
      if (bytes != null) 'image': Blob(await shrinkPng(bytes, maxWidth: 720)),
      'createdAt': Timestamp.fromDate(artwork.createdAt),
    });
  }

  @override
  Future<void> setLiked(String artworkId, bool liked) async {
    final batch = _db.batch();
    final mark = _me.collection('likes').doc(artworkId);
    if (liked) {
      batch.set(mark, <String, dynamic>{'at': FieldValue.serverTimestamp()});
    } else {
      batch.delete(mark);
    }
    if (!_sampleArtworks.contains(artworkId)) {
      batch.update(_db.collection('artworks').doc(artworkId), <String, dynamic>{
        'likeCount': FieldValue.increment(liked ? 1 : -1),
      });
    }
    await batch.commit();
  }

  @override
  Future<void> setFollowing(String artistId, bool following) async {
    final batch = _db.batch();
    final mark = _me.collection('following').doc(artistId);
    if (following) {
      batch.set(mark, <String, dynamic>{'at': FieldValue.serverTimestamp()});
    } else {
      batch.delete(mark);
    }
    if (!_sampleArtists.contains(artistId)) {
      batch.update(_user(artistId), <String, dynamic>{
        'followerCount': FieldValue.increment(following ? 1 : -1),
      });
    }
    await batch.commit();
  }
}
