import 'package:flutter/material.dart';

/// INKBOOK's visual language: a creative's desk at night. Cream paper, washi
/// tape, polaroids and folder tabs laid out on a deep ink-blue surface, so the
/// app reads as a moodboard / sketchbook rather than as technical software.
class InkbookColors {
  const InkbookColors._();

  // Ink and paper.
  static const Color ink = Color(0xFF2B2622);
  static const Color inkSoft = Color(0xFF6B6259);
  static const Color paper = Color(0xFFFBF7F0);
  static const Color paperWarm = Color(0xFFF3EADC);
  static const Color paperToned = Color(0xFFE7D8C3);
  static const Color accent = Color(0xFFB4552D);
  static const Color accentSoft = Color(0xFFE0B49C);
  static const Color sage = Color(0xFF6F8368);
  static const Color cover = Color(0xFF3A3531);

  // The desk everything sits on.
  static const Color desk = Color(0xFF2E3352);
  static const Color deskDeep = Color(0xFF242842);
  static const Color deskLight = Color(0xFF3C4268);

  // Folder tabs (after the lavender / dusty rose / cream index tabs).
  static const Color folderCream = Color(0xFFEDE7DA);
  static const Color folderLavender = Color(0xFF9DA6E6);
  static const Color folderRose = Color(0xFFC0797C);
  static const Color folderSage = Color(0xFFA8B79A);

  // Tool tray and the signature colour of each tool.
  static const Color tray = Color(0xFF262628);
  static const Color toolYellow = Color(0xFFF0B13A);
  static const Color toolOrange = Color(0xFFE2683C);
  static const Color toolTeal = Color(0xFF5E8C94);
  static const Color toolBrown = Color(0xFF9C6D4C);
  static const Color toolPurple = Color(0xFFAA7DB3);

  // Washi tape.
  static const List<Color> tapes = <Color>[
    Color(0xCCE8C9A0),
    Color(0xCCB9C3EE),
    Color(0xCCE4AFAF),
    Color(0xCCBFD1B4),
    Color(0xCCF1DD9B),
  ];

  /// Sketchbook cover colours, Paper-by-FiftyThree style: flat and bold.
  static const List<Color> covers = <Color>[
    Color(0xFFF2B53B),
    Color(0xFF2F5A8A),
    Color(0xFFE2583E),
    Color(0xFF5E8C94),
    Color(0xFFC0797C),
    Color(0xFF9DA6E6),
    Color(0xFF3A3531),
    Color(0xFFA8B79A),
  ];

  /// Default swatches offered in the colour picker.
  static const List<Color> palette = <Color>[
    Color(0xFF2B2622),
    Color(0xFF6B6259),
    Color(0xFF9A8F80),
    Color(0xFFB4552D),
    Color(0xFFD98E3C),
    Color(0xFFE3C567),
    Color(0xFF6F8368),
    Color(0xFF3F6C7A),
    Color(0xFF4C5A93),
    Color(0xFF7A5A88),
    Color(0xFFC96A7B),
    Color(0xFFFFFFFF),
  ];
}

/// Type, bundled under assets/fonts (all SIL Open Font License).
///
/// One workhorse family keeps every screen readable and consistent:
/// - DM Sans for headings ([title], bold and tight, like the reference
///   moodboards), body copy ([body]) and small labels ([eyebrow]).
/// - Playfair Display only for the brand ([wordmark]) and big initials.
/// - Caveat only for short annotations - tape, notes the user scribbles,
///   asides - never for anything people need to read at length.
class InkbookType {
  const InkbookType._();

  static const String display = 'Playfair Display';
  static const List<String> displayFallback = <String>[
    'Didot',
    'Georgia',
    'serif'
  ];

  static const String hand = 'Caveat';
  static const List<String> handFallback = <String>['Bradley Hand', 'cursive'];

  static const String sans = 'DM Sans';
  static const List<String> sansFallback = <String>[
    'Avenir Next',
    'sans-serif'
  ];

  static TextStyle _sans(double size, FontWeight weight, Color color,
          {double height = 1.4, double letterSpacing = 0}) =>
      TextStyle(
        fontFamily: sans,
        fontFamilyFallback: sansFallback,
        fontSize: size,
        fontWeight: weight,
        fontVariations: <FontVariation>[
          FontVariation('wght', weight.value.toDouble()),
        ],
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  /// Screen and section headings.
  static TextStyle title({
    double size = 32,
    Color color = InkbookColors.ink,
    FontWeight weight = FontWeight.w700,
  }) =>
      _sans(size, weight, color, height: 1.1, letterSpacing: -size * 0.025);

  /// Running text: bios, prompts, instructions, captions.
  static TextStyle body({
    double size = 15,
    Color color = InkbookColors.ink,
    FontWeight weight = FontWeight.w400,
  }) =>
      _sans(size, weight, color, height: 1.45);

  /// The elegant serif, kept for the brand name and decorative initials.
  static TextStyle wordmark({
    double size = 40,
    Color color = InkbookColors.ink,
  }) =>
      TextStyle(
        fontFamily: display,
        fontFamilyFallback: displayFallback,
        fontSize: size,
        color: color,
        height: 1.05,
        letterSpacing: -0.3,
      );

  /// Handwritten - captions, labels on tape and polaroids.
  static TextStyle handwritten({
    double size = 16,
    Color color = InkbookColors.ink,
  }) =>
      TextStyle(
        fontFamily: hand,
        fontFamilyFallback: handFallback,
        // Caveat runs small next to other faces at the same point size.
        fontSize: size * 1.15,
        fontWeight: FontWeight.w500,
        fontVariations: const <FontVariation>[FontVariation('wght', 500)],
        color: color,
        height: 1.15,
      );

  /// Tiny spaced-out caps, like the corner notes on a printed moodboard.
  static TextStyle eyebrow({Color color = InkbookColors.inkSoft}) =>
      _sans(10.5, FontWeight.w600, color, height: 1.3, letterSpacing: 1.8);
}

/// Shared spacing so every screen lines up the same way.
class InkbookLayout {
  const InkbookLayout._();

  static const double tablet = 720;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tablet;

  /// Side margin for screen content.
  static double gutter(BuildContext context) => isWide(context) ? 36 : 16;
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: InkbookType.sans,
      fontFamilyFallback: InkbookType.sansFallback,
      colorScheme: ColorScheme.fromSeed(
        seedColor: InkbookColors.accent,
        surface: InkbookColors.paper,
        primary: InkbookColors.ink,
      ),
      scaffoldBackgroundColor: InkbookColors.paper,
    );

    final pill =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(40));

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: InkbookColors.ink,
        displayColor: InkbookColors.ink,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: InkbookColors.ink,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: InkbookType.title(size: 22),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0x14000000),
        space: 1,
        thickness: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: InkbookColors.folderCream,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        titleTextStyle: InkbookType.title(size: 24),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: InkbookColors.folderCream,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: InkbookColors.tray,
        contentTextStyle: InkbookType.body(
          size: 14,
          color: InkbookColors.folderCream,
        ),
        shape: pill,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withAlpha(160),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
        labelStyle: InkbookType.eyebrow(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: InkbookColors.tray,
          foregroundColor: InkbookColors.folderCream,
          shape: pill,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: InkbookColors.ink,
          side: const BorderSide(color: InkbookColors.ink, width: 1),
          shape: pill,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: InkbookColors.ink),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: InkbookColors.paperWarm,
        side: BorderSide.none,
        labelStyle: const TextStyle(
          color: InkbookColors.inkSoft,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: InkbookColors.folderCream,
        inactiveTrackColor: Colors.white.withAlpha(40),
        thumbColor: InkbookColors.folderCream,
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: InkbookColors.ink,
      ),
    );
  }
}
