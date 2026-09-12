import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colours that mean something regardless of which palette is active.
///
/// Danger is always red, Logic Points are always amber, and the role badge
/// colours are a legend the user learns once — so these stay fixed while the
/// surfaces and accent move with [AppPalette].
class AppColors {
  const AppColors._();

  static const points = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const success = Color(0xFF22C55E);

  /// The default palette's accent, kept as a named constant because widgets
  /// across the app refer to it directly.
  static const accent = Color(0xFF22C55E);
  static const accentDim = Color(0xFF15803D);
  static const button = Color(0xFF0C499D);
  static const navSelected = Color(0xFFDE473C);

  static const darkBg = Color(0xFF030712);
  static const darkSurface = Color(0xFF111827);
  static const darkBorder = Color(0xFF1F2937);
  static const darkText = Color(0xFFF9FAFB);
  static const darkMuted = Color(0xFF9CA3AF);

  static const lightBg = Color(0xFFF9FAFB);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFE5E7EB);
  static const lightText = Color(0xFF111827);
  static const lightMuted = Color(0xFF4B5563);
}

/// Role → badge colour, mirroring the palette the web client used.
Color roleColor(String? role) => switch (role) {
      'STUDENT' => const Color(0xFF3B82F6),
      'ALUMNI' => const Color(0xFFA855F7),
      'BUSINESS' => AppColors.accent,
      'ADMIN' => AppColors.danger,
      _ => AppColors.darkMuted,
    };

/// Faculty → accent. The two faculties are separate audiences (migration
/// 0007), so giving each a colour lets a mixed list — a business feed, an
/// admin view, search results — stay readable at a glance.
Color facultyColor(String? faculty) => switch (faculty) {
      'IT' => const Color(0xFF38BDF8),
      'BUSINESS' => const Color(0xFFFBBF24),
      _ => AppColors.darkMuted,
    };

String facultyLabel(String? faculty) => switch (faculty) {
      'IT' => 'IT',
      'BUSINESS' => 'Business',
      _ => 'All faculties',
    };

/// One selectable look.
///
/// A palette only carries what actually differs between themes: the accent,
/// the button colour, the selected-tab colour, and the neutral ramp. Semantic
/// colours come from [AppColors], so a new palette cannot accidentally make
/// "danger" green.
class AppPalette {
  const AppPalette({
    required this.id,
    required this.name,
    required this.description,
    required this.accent,
    required this.button,
    required this.navSelected,
    required this.darkBg,
    required this.darkSurface,
    required this.darkBorder,
    required this.lightBg,
    required this.lightSurface,
    required this.lightBorder,
    this.darkText = const Color(0xFFF9FAFB),
    this.darkMuted = const Color(0xFF9CA3AF),
    this.lightText = const Color(0xFF111827),
    this.lightMuted = const Color(0xFF4B5563),
  });

  final String id;
  final String name;
  final String description;

  final Color accent;
  final Color button;
  final Color navSelected;

  final Color darkBg;
  final Color darkSurface;
  final Color darkBorder;
  final Color darkText;
  final Color darkMuted;

  final Color lightBg;
  final Color lightSurface;
  final Color lightBorder;
  final Color lightText;
  final Color lightMuted;
}

/// The palettes a user can pick from. `terminal` is first because it is the
/// look the project has always had, and changing the default under existing
/// users would be its own kind of bug.
const kPalettes = <AppPalette>[
  AppPalette(
    id: 'terminal',
    name: 'Terminal',
    description: 'Near-black with a signal-green accent. The original.',
    accent: Color(0xFF22C55E),
    button: Color(0xFF0C499D),
    navSelected: Color(0xFFDE473C),
    darkBg: Color(0xFF030712),
    darkSurface: Color(0xFF111827),
    darkBorder: Color(0xFF1F2937),
    lightBg: Color(0xFFF9FAFB),
    lightSurface: Color(0xFFFFFFFF),
    lightBorder: Color(0xFFE5E7EB),
  ),
  AppPalette(
    id: 'richfield',
    name: 'Richfield',
    description: 'The college red, for screenshots and the demo.',
    accent: Color(0xFFDE473C),
    button: Color(0xFFC0392B),
    navSelected: Color(0xFFDE473C),
    darkBg: Color(0xFF120708),
    darkSurface: Color(0xFF1F1214),
    darkBorder: Color(0xFF32201F),
    lightBg: Color(0xFFFDF8F7),
    lightSurface: Color(0xFFFFFFFF),
    lightBorder: Color(0xFFEEDDDA),
  ),
  AppPalette(
    id: 'midnight',
    name: 'Midnight',
    description: 'Cool slate and indigo. Easier on the eyes at night.',
    accent: Color(0xFF6366F1),
    button: Color(0xFF4F46E5),
    navSelected: Color(0xFF818CF8),
    darkBg: Color(0xFF0B1020),
    darkSurface: Color(0xFF151B31),
    darkBorder: Color(0xFF242C49),
    lightBg: Color(0xFFF5F6FC),
    lightSurface: Color(0xFFFFFFFF),
    lightBorder: Color(0xFFE0E3F2),
  ),
  AppPalette(
    id: 'paper',
    name: 'Paper',
    description: 'Warm, low-contrast, built for reading long posts.',
    accent: Color(0xFF0F766E),
    button: Color(0xFF115E59),
    navSelected: Color(0xFF0F766E),
    darkBg: Color(0xFF14110E),
    darkSurface: Color(0xFF201C17),
    darkBorder: Color(0xFF332C24),
    lightBg: Color(0xFFFAF7F0),
    lightSurface: Color(0xFFFFFDF8),
    lightBorder: Color(0xFFE7DFD0),
    lightText: Color(0xFF1C1917),
    lightMuted: Color(0xFF57534E),
  ),
  AppPalette(
    id: 'contrast',
    name: 'High contrast',
    description: 'Maximum legibility. Pure black or white, heavy borders.',
    accent: Color(0xFFFFD400),
    button: Color(0xFF0047AB),
    navSelected: Color(0xFFFFD400),
    darkBg: Color(0xFF000000),
    darkSurface: Color(0xFF0D0D0D),
    darkBorder: Color(0xFF4D4D4D),
    darkText: Color(0xFFFFFFFF),
    darkMuted: Color(0xFFCCCCCC),
    lightBg: Color(0xFFFFFFFF),
    lightSurface: Color(0xFFFFFFFF),
    lightBorder: Color(0xFF1A1A1A),
    lightText: Color(0xFF000000),
    lightMuted: Color(0xFF262626),
  ),
];

AppPalette paletteById(String? id) =>
    kPalettes.firstWhere((p) => p.id == id, orElse: () => kPalettes.first);

TextTheme _textTheme(TextTheme base) => GoogleFonts.interTextTheme(base);

/// Monospace, for code snippets, spreadsheet cells and Logic Point counters.
TextStyle monoStyle({
  double size = 13,
  FontWeight weight = FontWeight.w500,
  Color? color,
}) =>
    GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: weight, color: color);

ThemeData buildTheme({required AppPalette palette, required bool dark}) {
  final bg = dark ? palette.darkBg : palette.lightBg;
  final surface = dark ? palette.darkSurface : palette.lightSurface;
  final border = dark ? palette.darkBorder : palette.lightBorder;
  final text = dark ? palette.darkText : palette.lightText;
  final muted = dark ? palette.darkMuted : palette.lightMuted;
  final accent = palette.accent;
  final button = palette.button;

  // Buttons are filled with `button`, so the label on top has to be legible
  // against it whichever palette is active rather than always white.
  final onButton =
      ThemeData.estimateBrightnessForColor(button) == Brightness.dark
          ? Colors.white
          : Colors.black;
  final onAccent =
      ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
          ? Colors.white
          : Colors.black;

  final scheme = ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: accent,
    onPrimary: onAccent,
    secondary: AppColors.points,
    onSecondary: const Color(0xFF1A1204),
    error: AppColors.danger,
    onError: Colors.white,
    surface: surface,
    onSurface: text,
    outline: border,
  );

  final base = dark ? ThemeData.dark() : ThemeData.light();

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    textTheme: _textTheme(base.textTheme).apply(
      bodyColor: text,
      displayColor: text,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: text,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border),
      ),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      hintStyle: TextStyle(color: muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: button,
        foregroundColor: onButton,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: button,
        minimumSize: const Size.fromHeight(50),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: button,
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: button,
        selectedForegroundColor: onButton,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: button,
      foregroundColor: onButton,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: button),
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      side: BorderSide(color: border),
      labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      // Flutter's own default for the selected icon/label is
      // ColorScheme.onSecondaryContainer, which our scheme never sets — it
      // was falling back to near-black and vanishing against the dark
      // theme. Spell both states out explicitly instead.
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? palette.navSelected
              : muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? palette.navSelected
              : muted,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: surface,
      contentTextStyle: TextStyle(color: text),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
    ),
  );
}

/// Kept so call sites that only ever wanted "the dark one" — the setup
/// screen, tests — do not need a palette to hand.
ThemeData buildDarkTheme([AppPalette? palette]) =>
    buildTheme(palette: palette ?? kPalettes.first, dark: true);

ThemeData buildLightTheme([AppPalette? palette]) =>
    buildTheme(palette: palette ?? kPalettes.first, dark: false);
