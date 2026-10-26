# INKBOOK — FYP prototype

An interactive digital sketchbook for creative expression and exploration.
Flutter, tablet-first, **zero third-party packages** so it builds and runs
straight from the Flutter SDK.

## Run it

```bash
cd inkbook
flutter create . --platforms=android,ios,web,macos,windows,linux   # generates the native runner folders
flutter run                                                        # pick a tablet, or -d chrome
```

`flutter create .` is needed once because this archive contains only the Dart
source (`lib/`) and `pubspec.yaml` — not the generated `android/`, `ios/`,
`web/` folders. It will not overwrite anything in `lib/`.

For the best demo, run on a tablet with a stylus (Android + S Pen, or iPad +
Apple Pencil). On desktop or a trackpad the app falls back to speed-simulated
pressure, and the status bar under the canvas tells you which mode is active.

## What works

**Core drawing (scope §Core Drawing Features)**
- Canvas with pressure-sensitive strokes — width *and* opacity respond to
  pressure, with a different response curve per tool
- Pencil / ink pen / marker / eraser; adjustable size and opacity; 12-colour
  palette; live brush preview showing the pressure ramp
- Eraser removes ink with `BlendMode.clear` rather than painting over it, so
  the paper grid stays visible
- Undo / redo (per page) and clear page
- Palm rejection: once a stylus is seen, touch input stops drawing

**Digital sketchbook (§Digital Sketchbook)**
- Multiple sketchbooks on a shelf, each with its own paper style (plain, dot
  grid, grid, ruled, toned)
- Multi-page books, add/delete pages, 3D page-turn animation
- Pages render to PNG for thumbnails, mood-board saves and sharing

**Creative exploration and AI (§Creative Exploration and AI)**
- Drawing prompts, shuffleable, grouped by category
- Step-by-step guides ("how do I draw a hand / face / tree / cat", plus a
  generic construction guide for anything else) with per-step tips
- "Suggest a next step" — context-aware advice based on what's on the page

**Art community (§Art Community)**
- Discover feed, like, artist profiles, follow/unfollow
- Share a sketchbook page to the feed
- Personal mood board with collections, saving from the feed or from your own
  pages

## Structure

```
lib/
  main.dart                     app entry, splash, AppScope
  controllers/
    app_state.dart              CommunityController, MoodBoardController,
                                AiController, AppState + AppScope
    sketchbook_controller.dart  sketchbooks, pages, brush, strokes, undo/redo
  models/                       brush, stroke, sketch_page, sketchbook,
                                artwork, artist, mood_board_item, drawing_guide
  services/
    storage_service.dart        StorageService interface + in-memory impl
    ai_guidance_service.dart    AiGuidanceService interface + mock impl
    sample_data.dart            placeholder artists / artwork / sketchbooks
  utils/
    pressure.dart               normalises stylus pressure across devices
    stroke_geometry.dart        variable-width stroke outline builder
  screens/                      home_shell, library, draw, discover, moodboard
  widgets/artwork_thumbnail.dart  procedural placeholder art (no image assets)
  widgets/scrapbook.dart        moodboard building blocks: paper grain, washi
                                tape, polaroids, torn paper, masonry layout
  theme/app_theme.dart          palette (desk / folders / tools) + type styles
assets/fonts/                   Playfair Display, Caveat, DM Sans (SIL OFL,
                                licences alongside) - bundled, not fetched
```

State management is plain `ChangeNotifier` + an `InheritedWidget` (`AppScope`),
so there is no package dependency. Swapping in Provider or Riverpod later is a
drop-in change.

## The two technical parts worth writing up in the report

**1. Pressure-sensitive strokes** (`utils/stroke_geometry.dart`)
Flutter's `Paint.strokeWidth` is constant for a whole path, so a
pressure-sensitive brush cannot be drawn as a stroked path. Instead each stroke
builds its own *outline*: walk the centre line, offset every sample along its
normal by a half-width derived from that sample's pressure, walk back along the
other side, close the shape and fill it. Samples are smoothed (Chaikin-style)
and joined with quadratic segments so the result reads as a curve rather than a
polyline.

**2. Cross-device pressure** (`utils/pressure.dart`)
A stylus reports real pressure between `pressureMin` and `pressureMax`; a
finger reports a constant; a mouse reports nothing. The normaliser detects
which case it is in and, when there is no real pressure, *simulates* it from
pointer speed — slow strokes go thick, fast strokes thin, which is how a real
pen behaves. Output is exponentially smoothed so width never jumps between
samples.

## Backend (Firebase)

Project `inkbook-72b71`, Firestore in `asia-southeast1`, free Spark plan.
`main.dart` starts Firebase and falls back to in-memory services if it is not
configured for the platform (e.g. macOS), so the app always runs.

- **Auth** (`services/firebase_auth_service.dart`, `screens/auth/`):
  email/password and Google. Signed-out users see the welcome screen; a new
  account picks a display name and a unique @username once
  (`widgets/profile_form.dart`, checked live as you type), then lands on
  their shelf. `AccountController` in `app_state.dart` drives the flow.
- **Data** (`services/firestore_storage_service.dart`): the full data model
  is documented at the top of the file. Strokes are packed into a compact
  binary blob (`services/stroke_codec.dart`, 12 bytes per point), saves are
  debounced and only rewrite pages that changed, and Firestore's offline
  cache queues writes made without a connection.
- **Images**: page previews and shared artwork are shrunk to 640/720 px and
  stored as Firestore blobs, because Cloud Storage needs the Blaze plan.
  Moving to Storage later only touches the image bits of that one file.
- **Security** (`firestore.rules`): you can only touch your own sketchbooks;
  usernames are unique (enforced in the rules, not just the app); counters
  move by exactly one.
  Deploy after any change with `firebase deploy --only firestore:rules`.

**AI** - implement `AiGuidanceService` (`services/ai_guidance_service.dart`)
behind a Cloud Function so the API key never ships in the app (needs Blaze).

## Known gaps (deliberate, for the next iteration)

- The mood board is still local to the session (not yet in Firestore)
- iOS needs Xcode + CocoaPods before `flutterfire configure` can finish it
- Layers, brush textures and stroke stabilisation are not implemented
- Tilt is captured on every sample but not yet used for brush shape
- No tests yet; the stroke geometry and pressure normaliser are the two units
  most worth testing first
