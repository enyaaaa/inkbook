import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'controllers/app_state.dart';
import 'firebase_options.dart';
import 'screens/auth/auth_screens.dart';
import 'screens/home_shell.dart';
import 'services/firebase_auth_service.dart';
import 'services/firestore_storage_service.dart';
import 'theme/app_theme.dart';
import 'utils/pencil_texture.dart';
import 'widgets/scrapbook.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The paper grain pencil strokes are textured with (generated, ~5 ms).
  await PencilGrain.load();
  runApp(InkbookApp(state: await _createState()));
}

/// Uses Firebase when it is configured for this platform; otherwise falls
/// back to the in-memory services so the app still runs (e.g. on macOS,
/// which has no Firebase config yet).
Future<AppState> _createState() async {
  // `flutter run --dart-define=INKBOOK_OFFLINE=true` skips Firebase and runs
  // on local sample data - for demos without internet, and for testing
  // without creating accounts.
  if (const bool.fromEnvironment('INKBOOK_OFFLINE')) return AppState();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Keep a local copy of everything so the sketchbook works offline and
    // writes made without a connection sync later.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    final auth = FirebaseAuthService();
    return AppState(
      auth: auth,
      storage: FirestoreStorageService(auth: auth),
    );
  } catch (error) {
    debugPrint('Firebase unavailable, running offline-only: $error');
    return AppState();
  }
}

class InkbookApp extends StatefulWidget {
  const InkbookApp({super.key, required this.state});

  final AppState state;

  @override
  State<InkbookApp> createState() => _InkbookAppState();
}

class _InkbookAppState extends State<InkbookApp> {
  @override
  void initState() {
    super.initState();
    widget.state.start();
  }

  @override
  void dispose() {
    widget.state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.state.account;
    return AppScope(
      state: widget.state,
      child: MaterialApp(
        title: 'INKBOOK',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        // Which screen shows follows the account: signed out -> welcome,
        // new account -> profile set-up, then the app once loaded.
        home: ListenableBuilder(
          listenable: account,
          builder: (context, _) {
            final Widget screen = switch (account.stage) {
              AccountStage.starting ||
              AccountStage.loading =>
                const _SplashScreen(),
              AccountStage.signedOut => const WelcomeScreen(),
              AccountStage.settingUp => const ProfileSetupScreen(),
              AccountStage.failed => const LoadFailedScreen(),
              AccountStage.ready => const HomeShell(),
            };
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: KeyedSubtree(
                key: ValueKey<AccountStage>(account.stage),
                child: screen,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: InkbookColors.desk,
      body: GrainSurface(
        color: InkbookColors.desk,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                'Inkbook',
                style: InkbookType.wordmark(
                  size: 72,
                  color: InkbookColors.folderCream,
                ),
              ),
              Transform.translate(
                offset: const Offset(36, -6),
                child: Text(
                  'an interactive digital sketchbook',
                  style: InkbookType.handwritten(
                    size: 18,
                    color: InkbookColors.folderCream.withAlpha(200),
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
