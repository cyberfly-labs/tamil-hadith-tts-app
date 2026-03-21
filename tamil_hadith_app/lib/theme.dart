import 'package:flutter/material.dart';

/// App theme — Elegant Golden Yellow aesthetic with refined Material 3
class AppTheme {
  // ── Golden Yellow Palette ──
  static const Color emerald = Color(0xFFB8860B);
  static const Color emeraldDark = Color(0xFF8B6508);
  static const Color gold = Color(0xFF3E2723);
  static const Color goldDeep = Color(0xFF2D1A12);
  static const Color goldLight = Color(0xFF6D4C41);
  static const Color cream = Color(0xFFFAF7F2);
  static const Color surface = Color(0xFFFFFDF9);
  static const Color warmBorder = Color(0xFFE8DDD0);
  static const Color darkText = Color(0xFF1A1A1A);
  static const Color subtleText = Color(0xFF6B6B6B);
  static const Color mutedText = Color(0xFF9E9E9E);

  // Backward compat aliases
  static const Color primaryColor = emerald;
  static const Color accentColor = gold;
  static const Color backgroundColor = cream;
  static const Color surfaceColor = surface;
  static const Color cardColor = surface;
  static const Color textPrimary = darkText;
  static const Color textSecondary = subtleText;
  static const Color textOnPrimary = cream;
  static const Color primaryLight = Color(0xFF2D6F5A);
  static const Color primaryDark = emeraldDark;
  static const Color deepGold = goldDeep;
  static const Color goldAccent = gold;
  static const Color creamBg = cream;
  static const Color lightGray = subtleText;

  static ThemeData get theme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: Brightness.light,
      surface: surface,
    );
    final textTheme = ThemeData.light().textTheme.copyWith(
      headlineSmall: const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: darkText,
        letterSpacing: 0.1,
      ),
      titleLarge: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: darkText,
      ),
      titleMedium: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: darkText,
      ),
      bodyLarge: const TextStyle(
        fontSize: 16,
        height: 1.65,
        color: darkText,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        height: 1.6,
        color: darkText,
      ),
      bodySmall: const TextStyle(
        fontSize: 12,
        height: 1.5,
        color: subtleText,
      ),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: cream,
      textTheme: textTheme,
      iconTheme: const IconThemeData(color: emerald),
      splashColor: emerald.withValues(alpha: 0.06),
      highlightColor: emerald.withValues(alpha: 0.04),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: emerald,
        selectionColor: gold.withValues(alpha: 0.22),
        selectionHandleColor: emerald,
      ),

      // ── AppBar ──
      appBarTheme: const AppBarTheme(
        backgroundColor: emerald,
        foregroundColor: cream,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: cream,
          letterSpacing: 0.3,
        ),
      ),

      // ── Cards — subtle warm border ──
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: warmBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── Chips ──
      chipTheme: ChipThemeData(
        backgroundColor: cream,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: warmBorder, width: 1),
        ),
        side: BorderSide.none,
        labelStyle: const TextStyle(color: darkText, fontWeight: FontWeight.w600, fontSize: 12),
      ),

      // ── Buttons ──
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: emerald,
          foregroundColor: cream,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.2),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: warmBorder, width: 1),
          foregroundColor: emerald,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: emerald,
        foregroundColor: cream,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),

      // ── Inputs / Search ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: mutedText, fontSize: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: warmBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: warmBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: gold, width: 1.4),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(surface),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: warmBorder),
          ),
        ),
        hintStyle: const WidgetStatePropertyAll(
          TextStyle(color: mutedText, fontSize: 15),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(color: darkText, fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      searchViewTheme: const SearchViewThemeData(
        backgroundColor: cream,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: emeraldDark,
        contentTextStyle: const TextStyle(
          color: cream,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Navigation Bar ──
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
        height: 68,
        indicatorColor: emerald.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: emerald,
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: subtleText,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: emerald, size: 24);
          }
          return const IconThemeData(color: subtleText, size: 24);
        }),
      ),

      // ── Divider ──
      dividerTheme: const DividerThemeData(color: warmBorder, thickness: 1, space: 0),

      // ── ListTile ──
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        titleTextStyle: const TextStyle(color: darkText, fontSize: 15, fontWeight: FontWeight.w600),
        subtitleTextStyle: const TextStyle(color: subtleText, fontSize: 13, fontWeight: FontWeight.w500),
      ),

      // ── Page transitions ──
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  // ── Dark Theme Palette ──
  static const Color darkSurface = Color(0xFF121212);
  static const Color darkCard = Color(0xFF1E1E1E);
  static const Color darkBorder = Color(0xFF2E2E2E);
  static const Color darkSubtle = Color(0xFF9E9E9E);
  static const Color darkEmerald = Color(0xFF7A5D08);
  static const Color darkGold = Color(0xFFFFD54F);

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: Brightness.dark,
      surface: darkSurface,
    );
    final textTheme = ThemeData.dark().textTheme.copyWith(
      headlineSmall: const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: Color(0xFFF5F0E8),
      ),
      titleLarge: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Color(0xFFF5F0E8),
      ),
      titleMedium: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Color(0xFFF5F0E8),
      ),
      bodyLarge: const TextStyle(
        fontSize: 16,
        height: 1.65,
        color: Color(0xFFF5F0E8),
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        height: 1.6,
        color: Color(0xFFF5F0E8),
      ),
      bodySmall: const TextStyle(
        fontSize: 12,
        height: 1.5,
        color: darkSubtle,
      ),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: darkSurface,
      textTheme: textTheme,
      iconTheme: const IconThemeData(color: darkGold),
      splashColor: darkGold.withValues(alpha: 0.06),
      highlightColor: darkGold.withValues(alpha: 0.04),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: darkGold,
        selectionColor: darkGold.withValues(alpha: 0.2),
        selectionHandleColor: darkGold,
      ),

      // ── AppBar ──
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF5A4500),
        foregroundColor: const Color(0xFFF5F0E8),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: Color(0xFFF5F0E8),
          letterSpacing: 0.3,
        ),
      ),

      // ── Cards ──
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── Chips ──
      chipTheme: ChipThemeData(
        backgroundColor: darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
        side: BorderSide.none,
        labelStyle: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 12),
      ),

      // ── Buttons ──
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: darkEmerald,
          foregroundColor: const Color(0xFFF5F0E8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.2),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: darkBorder, width: 1),
          foregroundColor: darkEmerald,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: darkEmerald,
        foregroundColor: Color(0xFFF5F0E8),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
      ),

      // ── Inputs / Search ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: darkSubtle, fontSize: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkGold, width: 1.4),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: const WidgetStatePropertyAll(darkCard),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: darkBorder),
          ),
        ),
        hintStyle: const WidgetStatePropertyAll(
          TextStyle(color: darkSubtle, fontSize: 15),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(color: Color(0xFFF5F0E8), fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      searchViewTheme: const SearchViewThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkCard,
        contentTextStyle: const TextStyle(
          color: Color(0xFFF5F0E8),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Navigation Bar ──
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkCard,
        elevation: 0,
        height: 68,
        indicatorColor: darkEmerald.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: darkGold);
          }
          return const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: darkSubtle);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: darkGold, size: 24);
          }
          return const IconThemeData(color: darkSubtle, size: 24);
        }),
      ),

      // ── Divider ──
      dividerTheme: const DividerThemeData(color: darkBorder, thickness: 1, space: 0),

      // ── ListTile ──
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        titleTextStyle: TextStyle(color: colorScheme.onSurface, fontSize: 15, fontWeight: FontWeight.w600),
        subtitleTextStyle: const TextStyle(color: darkSubtle, fontSize: 13, fontWeight: FontWeight.w500),
      ),

      // ── Page transitions ──
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
