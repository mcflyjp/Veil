import 'package:flutter/material.dart';

class AimColors {
  // Title bar gradient — classic AIM deep blue
  static const titleBarStart = Color(0xFF17369C);
  static const titleBarEnd   = Color(0xFF5B8FD4);

  // Buddy list chrome
  static const buddyListBg      = Color(0xFFD4D0C8); // Win98 gray
  static const sectionHeaderBg  = Color(0xFF7B9FD4); // medium blue
  static const sectionHeaderFg  = Color(0xFFFFFFFF);
  static const buddyRowBg       = Color(0xFFFFFFFF);
  static const buddyRowAlt      = Color(0xFFF5F5F5);

  // Chat window
  static const chatBg           = Color(0xFFFFFFFF);
  static const inputBg          = Color(0xFFFFFFFF);
  static const inputBorder      = Color(0xFF808080);
  static const toolbarBg        = Color(0xFFD4D0C8);

  // Message text colors (classic AIM defaults)
  static const myNameColor      = Color(0xFF0000FF);  // blue — "me"
  static const theirNameColor   = Color(0xFFCC0000);  // red  — "them"
  static const msgTextColor     = Color(0xFF000000);

  // Presence
  static const online  = Color(0xFF00AA00);
  static const away    = Color(0xFFDD8800);
  static const offline = Color(0xFF999999);

  // Borders
  static const winBorder    = Color(0xFF808080);
  static const winBorderDark = Color(0xFF404040);

  // Legacy aliases — used by login/settings/widget files
  static const aimBlue       = titleBarStart;
  static const aimLightBlue  = titleBarEnd;
  static const aimTitleBar   = titleBarStart;
  static const aimTitleBarEnd = titleBarEnd;
  static const aimOnline     = online;
  static const darkBackground = Color(0xFF1A1A1A);
  static const darkSurface   = Color(0xFF1E1E1E);
  static const darkSurface2  = darkSectionBg;

  // Dark mode
  static const darkTitleBar  = Color(0xFF0F2244);
  static const darkChatBg    = Color(0xFF1A1A1A);
  static const darkInputBg   = Color(0xFF222222);
  static const darkBuddyBg   = Color(0xFF1E1E1E);
  static const darkSectionBg = Color(0xFF2A3A5C);
  static const darkText      = Color(0xFFE0E0E0);
  static const darkBorder    = Color(0xFF444444);
  static const darkMyName    = Color(0xFF6699FF);
  static const darkTheirName = Color(0xFFFF7777);
}

class AimTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: false,
    fontFamily: 'Arial',
    scaffoldBackgroundColor: AimColors.buddyListBg,
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF17369C),
      secondary: Color(0xFF5B8FD4),
      surface: AimColors.buddyRowBg,
      onPrimary: Colors.white,
      onSurface: Colors.black,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AimColors.titleBarStart,
      foregroundColor: Colors.white,
      elevation: 1,
      titleTextStyle: TextStyle(fontFamily: 'Arial', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
    ),
    cardTheme: const CardThemeData(
      color: AimColors.buddyRowBg,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: AimColors.winBorder, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AimColors.inputBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(0),
        borderSide: const BorderSide(color: AimColors.inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(0),
        borderSide: const BorderSide(color: AimColors.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(0),
        borderSide: const BorderSide(color: Color(0xFF17369C), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      isDense: true,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AimColors.buddyListBg,
        foregroundColor: Colors.black,
        elevation: 2,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        textStyle: const TextStyle(fontFamily: 'Arial', fontSize: 11, fontWeight: FontWeight.normal),
        side: const BorderSide(color: AimColors.winBorder),
      ),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontFamily: 'Arial', fontSize: 12, color: Colors.black),
      bodySmall:  TextStyle(fontFamily: 'Arial', fontSize: 11, color: Colors.black),
    ),
    dividerColor: AimColors.winBorder,
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: false,
    fontFamily: 'Arial',
    scaffoldBackgroundColor: AimColors.darkBuddyBg,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF5B8FD4),
      secondary: Color(0xFF5B8FD4),
      surface: AimColors.darkChatBg,
      onPrimary: Colors.white,
      onSurface: AimColors.darkText,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AimColors.darkTitleBar,
      foregroundColor: Colors.white,
      elevation: 1,
      titleTextStyle: TextStyle(fontFamily: 'Arial', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
    ),
    cardTheme: const CardThemeData(
      color: AimColors.darkChatBg,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AimColors.darkInputBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(0),
        borderSide: const BorderSide(color: AimColors.darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(0),
        borderSide: const BorderSide(color: AimColors.darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(0),
        borderSide: const BorderSide(color: Color(0xFF5B8FD4), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      isDense: true,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2A2A2A),
        foregroundColor: AimColors.darkText,
        elevation: 1,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        textStyle: const TextStyle(fontFamily: 'Arial', fontSize: 11),
        side: const BorderSide(color: AimColors.darkBorder),
      ),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontFamily: 'Arial', fontSize: 12, color: AimColors.darkText),
      bodySmall:  TextStyle(fontFamily: 'Arial', fontSize: 11, color: AimColors.darkText),
    ),
    dividerColor: AimColors.darkBorder,
  );
}
