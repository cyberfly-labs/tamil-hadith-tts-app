import 'package:flutter/material.dart';

/// App theme — Islamic/Elegant aesthetic with refined Material 3
class AppTheme {
  // ── Islamic Palette ──
  static const Color emerald = Color(0xFF1B4D3E);
  static const Color emeraldDark = Color(0xFF0D3020);
  static const Color gold = Color(0xFFD4A04A);
  static const Color goldDeep = Color(0xFFB8860B);
  static const Color goldLight = Color(0xFFE8C882);
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
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: cream,

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

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: emerald,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Colors.white12),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
