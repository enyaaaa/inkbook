import 'dart:async';

import 'package:flutter/material.dart';

import '../models/artist.dart';
import '../models/artwork.dart';
import '../models/drawing_guide.dart';
import '../models/mood_board_item.dart';
import '../services/ai_guidance_service.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import 'sketchbook_controller.dart';

/// Community feed, artist profiles and following.
class CommunityController extends ChangeNotifier {
  CommunityController(this._storage);

  final StorageService _storage;

  final List<Artwork> _feed = <Artwork>[];
  final List<Artist> _artists = <Artist>[];
  bool _loading = true;

  List<Artwork> get feed => List<Artwork>.unmodifiable(_feed);
  List<Artist> get artists => List<Artist>.unmodifiable(_artists);
  bool get isLoading => _loading;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    final feed = await _storage.loadFeed();
    final artists = await _storage.loadArtists();
    _feed
      ..clear()
      ..addAll(feed);
    _artists
      ..clear()
      ..addAll(artists);
    _loading = false;
    notifyListeners();
  }

  Artist artistById(String id) => _artists.firstWhere(
        (a) => a.id == id,
        orElse: () => Artist(
          id: id,
          name: 'Unknown artist',
          handle: '@unknown',
          bio: '',
        ),
      );

  Artist get currentUser => _artists.firstWhere(
        (a) => a.isCurrentUser,
        orElse: () => Artist(
          id: 'u-me',
          name: 'You',
          handle: '@you',
          bio: '',
          isCurrentUser: true,
        ),
      );

  List<Artwork> artworksBy(String artistId) =>
      _feed.where((a) => a.artistId == artistId).toList(growable: false);

  void toggleLike(Artwork artwork) {
    artwork.isLiked = !artwork.isLiked;
    artwork.likeCount += artwork.isLiked ? 1 : -1;
    notifyListeners();
    _storage.setLiked(artwork.id, artwork.isLiked);
  }

  void toggleFollow(Artist artist) {
    artist.isFollowing = !artist.isFollowing;
    artist.followerCount += artist.isFollowing ? 1 : -1;
    notifyListeners();
    _storage.setFollowing(artist.id, artist.isFollowing);
  }

  /// Saves the current user's profile. Throws [ProfileFailure] with a
  /// user-facing message (for example when the @handle is taken).
  Future<void> updateProfile({
    required String name,
    required String handle,
    required String bio,
  }) async {
    final updated = await _storage.updateProfile(
      name: name,
      handle: handle,
      bio: bio,
    );
    final me = currentUser;
    me
      ..name = updated.name
      ..handle = updated.handle
      ..bio = updated.bio;
    notifyListeners();
  }

  Future<bool> isHandleAvailable(String handle) =>
      _storage.isHandleAvailable(handle);

  Future<void> publish(Artwork artwork) async {
    _feed.insert(0, artwork);
    notifyListeners();
    await _storage.publishArtwork(artwork);
  }
}

/// The personal mood board: saved artwork and references.
class MoodBoardController extends ChangeNotifier {
  final List<MoodBoardItem> _items = <MoodBoardItem>[];

  List<MoodBoardItem> get items => List<MoodBoardItem>.unmodifiable(_items);

  List<String> get collections {
    final set = <String>{'All'};
    for (final item in _items) {
      set.add(item.collection);
    }
    return set.toList(growable: false);
  }

  List<MoodBoardItem> inCollection(String collection) => collection == 'All'
      ? items
      : _items.where((i) => i.collection == collection).toList(growable: false);

  bool contains(String artworkId) =>
      _items.any((i) => i.artwork.id == artworkId);

  void save(
    Artwork artwork, {
    MoodBoardSource source = MoodBoardSource.savedFromFeed,
    String collection = 'All',
    String note = '',
  }) {
    if (contains(artwork.id)) return;
    _items.insert(
      0,
      MoodBoardItem(
        id: 'mb-${DateTime.now().microsecondsSinceEpoch}',
        artwork: artwork,
        savedAt: DateTime.now(),
        source: source,
        collection: collection,
        note: note,
      ),
    );
    notifyListeners();
  }

  void annotate(MoodBoardItem item, {String? note, String? collection}) {
    if (note != null) item.note = note.trim();
    if (collection != null) {
      item.collection = collection.trim().isEmpty ? 'All' : collection.trim();
    }
    notifyListeners();
  }

  void remove(String artworkId) {
    _items.removeWhere((i) => i.artwork.id == artworkId);
    notifyListeners();
  }

  void toggle(Artwork artwork) {
    if (contains(artwork.id)) {
      remove(artwork.id);
    } else {
      save(artwork);
    }
  }
}

/// Drives the AI-assisted drawing panel.
class AiController extends ChangeNotifier {
  AiController(this._service);

  final AiGuidanceService _service;

  List<DrawingPrompt> _prompts = const <DrawingPrompt>[];
  DrawingGuide? _guide;
  String? _critique;
  bool _busy = false;
  int _activeStep = 0;

  List<DrawingPrompt> get prompts => _prompts;
  DrawingGuide? get guide => _guide;
  String? get critique => _critique;
  bool get isBusy => _busy;
  int get activeStep => _activeStep;

  Future<void> refreshPrompts({String? theme}) async {
    _busy = true;
    notifyListeners();
    _prompts = await _service.prompts(theme: theme);
    _busy = false;
    notifyListeners();
  }

  Future<void> requestGuide(String subject) async {
    _busy = true;
    _critique = null;
    notifyListeners();
    _guide = await _service.guideFor(subject);
    _activeStep = 0;
    _busy = false;
    notifyListeners();
  }

  Future<void> requestCritique({
    required String subject,
    required int strokeCount,
  }) async {
    _busy = true;
    notifyListeners();
    _critique = await _service.critique(
      subject: subject,
      strokeCount: strokeCount,
    );
    _busy = false;
    notifyListeners();
  }

  void setActiveStep(int index) {
    final guide = _guide;
    if (guide == null) return;
    _activeStep = index.clamp(0, guide.stepCount - 1);
    notifyListeners();
  }

  void nextStep() => setActiveStep(_activeStep + 1);
  void previousStep() => setActiveStep(_activeStep - 1);

  void clearGuide() {
    _guide = null;
    _critique = null;
    _activeStep = 0;
    notifyListeners();
  }
}

/// Where the signed-in person is in getting into the app.
enum AccountStage {
  /// Waiting to hear whether anyone is signed in.
  starting,

  /// Nobody is signed in: show the welcome / sign-in screen.
  signedOut,

  /// Signed in to a brand-new account with no profile yet: show set-up.
  settingUp,

  /// Loading this person's sketchbooks and feed.
  loading,

  /// Everything loaded: show the app.
  ready,

  /// Loading failed (usually no connection): offer a retry.
  failed,
}

/// Who is signed in, and the sign-in actions the UI can call.
///
/// The flow is: [AccountStage.signedOut] -> sign in or create an account ->
/// [AccountStage.settingUp] (new accounts only: name + unique @username) ->
/// [AccountStage.loading] -> [AccountStage.ready]. Signing out goes back to
/// the start. There are no guest sessions.
class AccountController extends ChangeNotifier {
  AccountController(
    this._auth,
    this._storage, {
    required Future<void> Function() loadEverything,
  }) : _loadEverything = loadEverything;

  final AuthService _auth;
  final StorageService _storage;
  final Future<void> Function() _loadEverything;

  StreamSubscription<AuthUser?>? _subscription;
  AccountStage _stage = AccountStage.starting;
  AuthUser? _user;
  bool _busy = false;
  Object? _error;

  AccountStage get stage => _stage;
  AuthUser? get user => _user;
  String? get email => _user?.email;
  bool get isBusy => _busy;
  Object? get error => _error;

  void start() {
    _subscription ??= _auth.userChanges.listen(_userChanged);
  }

  void _userChanged(AuthUser? user) {
    final previous = _user?.uid;
    _user = user;
    if (user == null) {
      _stage = AccountStage.signedOut;
      notifyListeners();
      return;
    }
    if (user.uid != previous || _stage == AccountStage.starting) {
      _prepare(user.uid);
    }
  }

  void _set(AccountStage stage) {
    _stage = stage;
    notifyListeners();
  }

  /// Checks for a profile, then loads everything for [uid]. Bails out if a
  /// different user signs in meanwhile.
  Future<void> _prepare(String uid) async {
    _error = null;
    _set(AccountStage.loading);
    try {
      final me = await _storage.loadMyProfile();
      if (_user?.uid != uid) return;
      if (me == null) {
        _set(AccountStage.settingUp);
        return;
      }
      await _loadEverything();
      if (_user?.uid != uid) return;
      _set(AccountStage.ready);
    } catch (e) {
      if (_user?.uid != uid) return;
      debugPrint('Loading account failed: $e');
      _error = e;
      _set(AccountStage.failed);
    }
  }

  Future<void> retry() async {
    final uid = _user?.uid;
    if (uid != null) await _prepare(uid);
  }

  Future<void> _run(Future<void> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> signInWithGoogle() => _run(_auth.signInWithGoogle);

  Future<void> createAccount(String email, String password) =>
      _run(() => _auth.createAccount(email: email, password: password));

  Future<void> signIn(String email, String password) =>
      _run(() => _auth.signIn(email: email, password: password));

  Future<void> sendPasswordReset(String email) =>
      _run(() => _auth.sendPasswordReset(email));

  Future<void> signOut() => _run(_auth.signOut);

  /// Saves a new account's profile, then opens the app. Throws
  /// [ProfileFailure] (e.g. username taken) for the form to show.
  Future<void> createProfile({
    required String name,
    required String handle,
    required String bio,
  }) async {
    final uid = _user?.uid;
    if (uid == null) return;
    await _run(() => _storage.createProfile(
          name: name,
          handle: handle,
          bio: bio,
        ));
    await _prepare(uid);
  }

  Future<bool> isHandleAvailable(String handle) =>
      _storage.isHandleAvailable(handle);

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// Bundles every controller and makes them reachable from any widget with
/// `AppScope.of(context)`.
class AppState {
  AppState({StorageService? storage, AiGuidanceService? ai, AuthService? auth})
      : storage = storage ?? InMemoryStorageService(),
        ai = ai ?? MockAiGuidanceService(),
        auth = auth ?? LocalAuthService() {
    sketchbooks = SketchbookController(this.storage);
    community = CommunityController(this.storage);
    moodBoard = MoodBoardController();
    aiGuidance = AiController(this.ai);
    account = AccountController(
      this.auth,
      this.storage,
      loadEverything: _loadEverything,
    );
  }

  final StorageService storage;
  final AiGuidanceService ai;
  final AuthService auth;

  late final AccountController account;
  late final SketchbookController sketchbooks;
  late final CommunityController community;
  late final MoodBoardController moodBoard;
  late final AiController aiGuidance;

  /// Starts listening for sign-in; the UI follows [AccountController.stage].
  void start() => account.start();

  /// Everything a signed-in person sees: their shelf, the feed, prompts.
  Future<void> _loadEverything() async {
    await Future.wait<void>(<Future<void>>[
      sketchbooks.load(),
      community.load(),
      aiGuidance.refreshPrompts(),
    ]);
    _pinStarterInspiration();
  }

  /// Starts the mood board with a few pins so a first-time user sees a board
  /// rather than an empty form. Remove once boards persist per user.
  void _pinStarterInspiration() {
    const pins = <String, List<String>>{
      'a-07': <String>['Mood', 'the colour of wet pavement'],
      'a-01': <String>['Urban', 'loose lines, lots of people'],
      'a-04': <String>['Studies', 'try this leaf shape'],
      'a-08': <String>['Urban', ''],
      'a-02': <String>['Studies', 'knuckles = boxes'],
    };
    for (final entry in pins.entries.toList().reversed) {
      final matches = community.feed.where((a) => a.id == entry.key);
      if (matches.isEmpty) continue;
      moodBoard.save(
        matches.first,
        collection: entry.value[0],
        note: entry.value[1],
      );
    }
  }

  void dispose() {
    account.dispose();
    sketchbooks.dispose();
    community.dispose();
    moodBoard.dispose();
    aiGuidance.dispose();
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.state, required super.child});

  final AppState state;

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!.state;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.state != state;
}
