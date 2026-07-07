import 'package:flutter/material.dart';

// AIM color palette — blues, grays, classic IM feel
class AimColors {
  static const aimBlue = Color(0xFF2050A0);
  static const aimLightBlue = Color(0xFF4A7FC1);
  static const aimTitleBar = Color(0xFF003580);
  static const aimTitleBarEnd = Color(0xFF6699CC);
  static const aimBackground = Color(0xFFECECEC);
  static const aimWindowBg = Color(0xFFFFFFFF);
  static const aimBorder = Color(0xFF808080);
  static const aimBubbleOut = Color(0xFFDCEAF7);
  static const aimBubbleIn = Color(0xFFFFFFFF);
  static const aimOnline = Color(0xFF00A000);
  static const aimAway = Color(0xFFF0A000);
  static const aimOffline = Color(0xFF808080);

  static const darkBackground = Color(0xFF1A1A2E);
  static const darkSurface = Color(0xFF16213E);
  static const darkSurface2 = Color(0xFF0F3460);
  static const darkBubbleOut = Color(0xFF1E3A5F);
  static const darkBubbleIn = Color(0xFF243447);
}

class AimTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: AimColors.aimBlue,
          secondary: AimColors.aimLightBlue,
          surface: AimColors.aimWindowBg,
          onPrimary: Colors.white,
          onSurface: Color(0xFF111111),
        ),
        scaffoldBackgroundColor: AimColors.aimBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: AimColors.aimTitleBar,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontFamily: 'Arial',
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          color: AimColors.aimWindowBg,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(2),
            side: const BorderSide(color: AimColors.aimBorder, width: 1),
          ),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: const BorderSide(color: AimColors.aimBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: const BorderSide(color: AimColors.aimBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: const BorderSide(color: AimColors.aimBlue, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          isDense: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AimColors.aimBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            textStyle: const TextStyle(fontFamily: 'Arial', fontSize: 12, fontWeight: FontWeight.bold),
            elevation: 2,
          ),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontFamily: 'Arial', fontSize: 13),
          bodySmall: TextStyle(fontFamily: 'Arial', fontSize: 11),
          labelMedium: TextStyle(fontFamily: 'Arial', fontSize: 12),
          titleMedium: TextStyle(fontFamily: 'Arial', fontSize: 13, fontWeight: FontWeight.bold),
        ),
        dividerColor: AimColors.aimBorder,
        listTileTheme: const ListTileThemeData(dense: true, minLeadingWidth: 0),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: AimColors.aimLightBlue,
          secondary: AimColors.aimLightBlue,
          surface: AimColors.darkSurface,
          onPrimary: Colors.white,
          onSurface: Color(0xFFE0E0E0),
        ),
        scaffoldBackgroundColor: AimColors.darkBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: AimColors.darkSurface2,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontFamily: 'Arial',
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          color: AimColors.darkSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(2),
            side: const BorderSide(color: Color(0xFF334466), width: 1),
          ),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AimColors.darkSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: const BorderSide(color: Color(0xFF334466)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: const BorderSide(color: Color(0xFF334466)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(2),
            borderSide: const BorderSide(color: AimColors.aimLightBlue, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          isDense: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AimColors.darkSurface2,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            textStyle: const TextStyle(fontFamily: 'Arial', fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontFamily: 'Arial', fontSize: 13, color: Color(0xFFE0E0E0)),
          bodySmall: TextStyle(fontFamily: 'Arial', fontSize: 11, color: Color(0xFFB0B0B0)),
          labelMedium: TextStyle(fontFamily: 'Arial', fontSize: 12, color: Color(0xFFE0E0E0)),
          titleMedium: TextStyle(fontFamily: 'Arial', fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFE0E0E0)),
        ),
        dividerColor: const Color(0xFF334466),
        listTileTheme: const ListTileThemeData(dense: true, minLeadingWidth: 0),
      );
}
