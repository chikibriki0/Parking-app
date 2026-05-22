import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// AppTheme — палитра и темы оформления в духе iOS / Apple.
///
/// Цвета подобраны близко к Apple Human Interface Guidelines:
/// systemBlue, systemGreen, systemRed, systemOrange.
/// Шрифт — Inter (близкий к SF Pro), поставляется через google_fonts.
class AppTheme {
  // === Brand / Action ===
  static const Color primary = Color(0xFF0A84FF);      // iOS systemBlue (dark variant — насыщеннее)
  static const Color primaryDark = Color(0xFF0040DD);
  static const Color success = Color(0xFF34C759);      // iOS systemGreen
  static const Color danger = Color(0xFFFF3B30);       // iOS systemRed
  static const Color warning = Color(0xFFFF9F0A);      // iOS systemOrange
  static const Color mySpot = Color(0xFF0A84FF);

  // === Light surfaces ===
  static const Color background = Color(0xFFF2F2F7);   // iOS systemGroupedBackground
  static const Color surface = Colors.white;
  static const Color separator = Color(0xFFE5E5EA);

  // === Text ===
  static const Color textPrimary = Color(0xFF1C1C1E);
  static const Color textSecondary = Color(0xFF8E8E93); // iOS systemGray

  // === Dark surfaces (для тёмной темы) ===
  static const Color backgroundDark = Color(0xFF000000);
  static const Color surfaceDark = Color(0xFF1C1C1E);
  static const Color separatorDark = Color(0xFF38383A);
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryDark = Color(0xFF98989F);

  static TextTheme _textTheme(Color base, Color muted) {
    return GoogleFonts.interTextTheme().apply(
      bodyColor: base,
      displayColor: base,
    ).copyWith(
      displayLarge: GoogleFonts.inter(
          fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: base),
      displayMedium: GoogleFonts.inter(
          fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: base),
      headlineMedium: GoogleFonts.inter(
          fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: base),
      titleLarge: GoogleFonts.inter(
          fontSize: 17, fontWeight: FontWeight.w600, color: base),
      titleMedium: GoogleFonts.inter(
          fontSize: 15, fontWeight: FontWeight.w600, color: base),
      bodyLarge: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, color: base),
      bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: base),
      bodySmall: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: muted),
      labelLarge: GoogleFonts.inter(
          fontSize: 15, fontWeight: FontWeight.w600, color: base),
    );
  }

  /// Светлая тема — повседневное использование.
  static ThemeData get light => _build(
        brightness: Brightness.light,
        bg: background,
        surface: surface,
        textBase: textPrimary,
        textMuted: textSecondary,
        separator: separator,
        inputFill: const Color(0xFFEFEFF4),
      );

  /// Тёмная тема — для тех, кто привык к iOS Dark Mode.
  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        bg: backgroundDark,
        surface: surfaceDark,
        textBase: textPrimaryDark,
        textMuted: textSecondaryDark,
        separator: separatorDark,
        inputFill: const Color(0xFF2C2C2E),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color textBase,
    required Color textMuted,
    required Color separator,
    required Color inputFill,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      secondary: primary,
      surface: surface,
      onSurface: textBase,
      error: danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      brightness: brightness,
      textTheme: _textTheme(textBase, textMuted),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textBase,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          color: textBase,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: textBase),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        hintStyle: GoogleFonts.inter(color: textMuted, fontWeight: FontWeight.w400),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dividerTheme: DividerThemeData(color: separator, thickness: 0.5, space: 0),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.inter(
          color: textBase,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: GoogleFonts.inter(
          color: textMuted,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// Сохраняем старое поле `theme` для обратной совместимости со старыми
  /// экранами — пусть оно ссылается на светлую тему.
  static ThemeData get theme => light;
}
