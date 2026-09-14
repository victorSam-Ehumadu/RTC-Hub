import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The "terminal" look the project has always aimed at: near-black surfaces,
/// Richfield institutional blue as the primary accent, and a monospace face
/// reserved for code and point totals so technical content reads differently from prose.
class AppColors {
  const AppColors._();

  static const accent = Color(0xFF1565C0);       // Richfield institutional blue
  static const accentDim = Color(0xFF0D47A1);    // Darker variant for hover
  static const success = Color(0xFF22C55E);      // Success signal (old green)
  static const successDim = Color(0xFF15803D);   // Success hover variant
  static const points = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
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

TextTheme _textTheme(TextTheme base) => GoogleFonts.interTextTheme(base);

/// Monospace, for code snippets and Logic Point counters.
TextStyle monoStyle({
  double size = 13,
  FontWeight weight = FontWeight.w500,
  Color? color,
}) =>
    GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: weight, color: color);

ThemeData _build({required bool dark}) {
  final bg = dark ? AppColors.darkBg : AppColors.lightBg;
  final surface = dark ? AppColors.darkSurface : AppColors.lightSurface;
  final border = dark ? AppColors.darkBorder : AppColors.lightBorder;
  final text = dark ? AppColors.darkText : AppColors.lightText;
  final muted = dark ? AppColors.darkMuted : AppColors.lightMuted;

  final scheme = ColorScheme(
    brightness: dark ? Brightness.dark : Brightness.light,
    primary: AppColors.accent,
    onPrimary: Colors.white,
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
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.button,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(50),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.button,
        minimumSize: const Size.fromHeight(50),
        side: BorderSide(color: border),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.button,
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.button,
        selectedForegroundColor: Colors.white,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.button,
      foregroundColor: Colors.white,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.button,
    ),
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
              ? AppColors.navSelected
              : muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? AppColors.navSelected
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

ThemeData buildDarkTheme() => _build(dark: true);
ThemeData buildLightTheme() => _build(dark: false);
