import 'package:flutter/material.dart';

enum VeilThemeMode { aim, dark, glass, light }

extension VeilThemeModeLabel on VeilThemeMode {
  String get label => switch (this) {
    VeilThemeMode.aim   => 'AIM Classic',
    VeilThemeMode.dark  => 'Dark',
    VeilThemeMode.glass => 'Glass',
    VeilThemeMode.light => 'Light',
  };

  IconData get icon => switch (this) {
    VeilThemeMode.aim   => Icons.computer,
    VeilThemeMode.dark  => Icons.dark_mode,
    VeilThemeMode.glass => Icons.blur_on,
    VeilThemeMode.light => Icons.light_mode,
  };
}

class VeilThemeColors {
  // Scaffold / list chrome
  final Color scaffold;
  final Color titleStart;
  final Color titleEnd;
  final Color titleOnColor;   // text + icon color on title bars
  final Color nameBg;
  final Color sectionBg;
  final Color sectionText;
  final Color listBg;
  final Color rowBg;
  final bool roundedRows;
  final double rowRadius;

  // Chat screen specific
  final Color chatBg;         // message list area background
  final Color inputBg;        // input field area background
  final Color myNameColor;    // sender name for own messages
  final Color theirNameColor; // sender name for received messages

  // Avatar
  final bool gradientAvatar;
  final Color solidAvatarBg;
  final Color avatarText;

  // Row text
  final Color nameText;
  final Color previewText;
  final Color timestampText;

  // Unread badge
  final Color badgeBg;
  final Color badgeText;

  // Bottom toolbar
  final Color toolbarBg;
  final Color toolbarText;
  final Color toolbarActive;

  // Presence dot / divider
  final Color presenceBorder;
  final Color divider;

  // Glass effect
  final bool useGlass;
  final bool showGlow;
  final Color glowColor;

  const VeilThemeColors({
    required this.scaffold,
    required this.titleStart,
    required this.titleEnd,
    required this.titleOnColor,
    required this.nameBg,
    required this.sectionBg,
    required this.sectionText,
    required this.listBg,
    required this.rowBg,
    required this.roundedRows,
    required this.rowRadius,
    required this.chatBg,
    required this.inputBg,
    required this.myNameColor,
    required this.theirNameColor,
    required this.gradientAvatar,
    required this.solidAvatarBg,
    required this.avatarText,
    required this.nameText,
    required this.previewText,
    required this.timestampText,
    required this.badgeBg,
    required this.badgeText,
    required this.toolbarBg,
    required this.toolbarText,
    required this.toolbarActive,
    required this.presenceBorder,
    required this.divider,
    this.useGlass = false,
    this.showGlow = false,
    this.glowColor = Colors.transparent,
  });

  // ── Per-letter gradient palette ────────────────────────────────────────
  static const List<List<Color>> _avatarGradients = [
    [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    [Color(0xFFEC4899), Color(0xFFF43F5E)],
    [Color(0xFF10B981), Color(0xFF06B6D4)],
    [Color(0xFFF59E0B), Color(0xFFEF4444)],
    [Color(0xFF3B82F6), Color(0xFF6366F1)],
    [Color(0xFF8B5CF6), Color(0xFFEC4899)],
  ];

  static List<Color> avatarGradientFor(String letter) {
    final i = letter.isEmpty ? 0 : letter.toUpperCase().codeUnitAt(0) % _avatarGradients.length;
    return _avatarGradients[i];
  }

  // ── Theme definitions ──────────────────────────────────────────────────

  static const VeilThemeColors aim = VeilThemeColors(
    scaffold:        Color(0xFFD4D0C8),
    titleStart:      Color(0xFF17369C),
    titleEnd:        Color(0xFF5B8FD4),
    titleOnColor:    Colors.white,
    nameBg:          Color(0xFF17369C),
    sectionBg:       Color(0xFF7B9FD4),
    sectionText:     Colors.white,
    listBg:          Color(0xFFD4D0C8),
    rowBg:           Colors.white,
    roundedRows:     false,
    rowRadius:       0,
    chatBg:          Color(0xFFFFF8F0),
    inputBg:         Colors.white,
    myNameColor:     Color(0xFF1B0AB9),
    theirNameColor:  Color(0xFF8B0000),
    gradientAvatar:  false,
    solidAvatarBg:   Color(0xFF17369C),
    avatarText:      Colors.white,
    nameText:        Colors.black,
    previewText:     Color(0xFF777777),
    timestampText:   Color(0xFF999999),
    badgeBg:         Color(0xFF17369C),
    badgeText:       Colors.white,
    toolbarBg:       Color(0xFFD4D0C8),
    toolbarText:     Colors.black87,
    toolbarActive:   Color(0xFF17369C),
    presenceBorder:  Colors.white,
    divider:         Color(0xFFCCCCCC),
  );

  static const VeilThemeColors dark = VeilThemeColors(
    scaffold:        Color(0xFF0F0F1E),
    titleStart:      Color(0xFF3730A3),
    titleEnd:        Color(0xFF6D28D9),
    titleOnColor:    Colors.white,
    nameBg:          Color(0xFF1A1A30),
    sectionBg:       Color(0xFF1A1A30),
    sectionText:     Color(0xFF9CA3AF),
    listBg:          Color(0xFF0F0F1E),
    rowBg:           Color(0xFF1E1E3A),
    roundedRows:     true,
    rowRadius:       14,
    chatBg:          Color(0xFF0F0F1E),
    inputBg:         Color(0xFF1A1A30),
    myNameColor:     Color(0xFF818CF8),
    theirNameColor:  Color(0xFF34D399),
    gradientAvatar:  true,
    solidAvatarBg:   Color(0xFF3730A3),
    avatarText:      Colors.white,
    nameText:        Colors.white,
    previewText:     Color(0xFF9CA3AF),
    timestampText:   Color(0xFF6B7280),
    badgeBg:         Color(0xFF7C3AED),
    badgeText:       Colors.white,
    toolbarBg:       Color(0xFF0A0A1A),
    toolbarText:     Color(0xFF9CA3AF),
    toolbarActive:   Color(0xFF8B5CF6),
    presenceBorder:  Color(0xFF1E1E3A),
    divider:         Colors.transparent,
  );

  static const VeilThemeColors glass = VeilThemeColors(
    scaffold:        Color(0xFF07071A),
    titleStart:      Color(0x14FFFFFF),
    titleEnd:        Color(0x0AFFFFFF),
    titleOnColor:    Colors.white,
    nameBg:          Color(0x0FFFFFFF),
    sectionBg:       Colors.transparent,
    sectionText:     Color(0xFF9CA3AF),
    listBg:          Colors.transparent,
    rowBg:           Color(0x0FFFFFFF),
    roundedRows:     true,
    rowRadius:       16,
    chatBg:          Color(0xFF07071A),
    inputBg:         Color(0x14FFFFFF),
    myNameColor:     Color(0xFF818CF8),
    theirNameColor:  Color(0xFF34D399),
    gradientAvatar:  true,
    solidAvatarBg:   Color(0xFF6D28D9),
    avatarText:      Colors.white,
    nameText:        Colors.white,
    previewText:     Color(0xFF9CA3AF),
    timestampText:   Color(0xFF6B7280),
    badgeBg:         Color(0xFF7C3AED),
    badgeText:       Colors.white,
    toolbarBg:       Color(0x0AFFFFFF),
    toolbarText:     Color(0xFF9CA3AF),
    toolbarActive:   Color(0xFF8B5CF6),
    presenceBorder:  Color(0x1AFFFFFF),
    divider:         Colors.transparent,
    useGlass:        true,
    showGlow:        true,
    glowColor:       Color(0xFF4C1D95),
  );

  static const VeilThemeColors light = VeilThemeColors(
    scaffold:        Color(0xFFF2F2F7),
    titleStart:      Color(0xFF007AFF),
    titleEnd:        Color(0xFF34AADC),
    titleOnColor:    Colors.white,
    nameBg:          Color(0xFFF2F2F7),
    sectionBg:       Color(0xFFF2F2F7),
    sectionText:     Color(0xFF6C6C70),
    listBg:          Color(0xFFF2F2F7),
    rowBg:           Colors.white,
    roundedRows:     true,
    rowRadius:       14,
    chatBg:          Color(0xFFF2F2F7),
    inputBg:         Colors.white,
    myNameColor:     Color(0xFF1558D6),
    theirNameColor:  Color(0xFF2D9B44),
    gradientAvatar:  false,
    solidAvatarBg:   Color(0xFF007AFF),
    avatarText:      Colors.white,
    nameText:        Color(0xFF1C1C1E),
    previewText:     Color(0xFF6C6C70),
    timestampText:   Color(0xFF8E8E93),
    badgeBg:         Color(0xFF007AFF),
    badgeText:       Colors.white,
    toolbarBg:       Colors.white,
    toolbarText:     Color(0xFF8E8E93),
    toolbarActive:   Color(0xFF007AFF),
    presenceBorder:  Color(0xFFF2F2F7),
    divider:         Color(0xFFE5E5EA),
  );

  static VeilThemeColors forMode(VeilThemeMode mode) => switch (mode) {
    VeilThemeMode.aim   => VeilThemeColors.aim,
    VeilThemeMode.dark  => VeilThemeColors.dark,
    VeilThemeMode.glass => VeilThemeColors.glass,
    VeilThemeMode.light => VeilThemeColors.light,
  };
}
