import 'package:flutter/material.dart';

// Color palette definitions for the six app-wide UI themes (modern/retro/aim/dark/glass/light).
// VeilThemeColors is a plain data class of named colors consumed by nearly every
// screen and widget in the app; VeilUserPrefs (core/veil_user_prefs.dart) owns
// the current VeilThemeMode selection and exposes `.colors` for the active theme.
// This file has no app state of its own — just color constants and lookups.
//
// `modern` (Direction B) is the default theme as of v0.1.36: a contemporary
// bubble-based layout that keeps Veil's AIM soul through the signature blue
// and screen-name-forward headers rather than the literal Win98 chrome.
// `retro` (Direction A, "AIM Remastered") keeps the exact flat AIM-line
// structure of `aim` but with richer gradients, gradient-ring avatars, and
// refined tones — a 2026 remaster rather than a redesign. `aim`/`dark`/
// `glass`/`light` are unchanged from before this pass.

enum VeilThemeMode { modern, retro, aim, dark, glass, light }

extension VeilThemeModeLabel on VeilThemeMode {
  String get label => switch (this) {
    VeilThemeMode.modern => 'Modern',
    VeilThemeMode.retro  => 'AIM Remastered',
    VeilThemeMode.aim    => 'AIM Classic',
    VeilThemeMode.dark   => 'Dark',
    VeilThemeMode.glass  => 'Glass',
    VeilThemeMode.light  => 'Light',
  };

  IconData get icon => switch (this) {
    VeilThemeMode.modern => Icons.auto_awesome,
    VeilThemeMode.retro  => Icons.computer,
    VeilThemeMode.aim    => Icons.window,
    VeilThemeMode.dark   => Icons.dark_mode,
    VeilThemeMode.glass  => Icons.blur_on,
    VeilThemeMode.light  => Icons.light_mode,
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
  final Color myNameColor;    // sender name for own messages (flat-line layout)
  final Color theirNameColor; // sender name for received messages (flat-line layout)

  // Avatar
  final bool gradientAvatar;
  final Color solidAvatarBg;
  final Color avatarText;
  final bool avatarRing;      // gradient ring + stronger presence glow (modern/retro)

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
  final bool floatingToolbar; // rounded floating pill toolbar instead of a flat bar (modern)

  // Presence dot / divider
  final Color presenceBorder;
  final Color divider;

  // Glass / frosted-chrome effect — also drives Modern's light frosted title
  // bar and floating toolbar (same BackdropFilter code path, light tokens).
  final bool useGlass;
  final bool showGlow;
  final Color glowColor;
  final Color titleBarBorderColor; // hairline under a useGlass title bar

  // Chat message layout: bubble-based (glass/modern) vs flat AIM-line (the rest).
  final bool bubbleLayout;
  final bool pillComposer; // scrollable Aa/B/I/U/timer pill row instead of icon toolbar (modern)
  final bool bubbleShowSenderBothSides; // screen name above own bubbles too, not just received (modern)
  final List<Color> sentBubbleGradient;
  final List<Color> receivedBubbleGradient;
  final Color receivedBubbleTextColor;
  final Color? receivedBubbleBorder;
  final Color bubbleSenderLabelColor;
  final Color bubbleTimestampColor;

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
    this.avatarRing = false,
    this.floatingToolbar = false,
    this.titleBarBorderColor = const Color(0x33FFFFFF),
    this.bubbleLayout = false,
    this.pillComposer = false,
    this.bubbleShowSenderBothSides = false,
    this.sentBubbleGradient = const [Color(0xFF3B5FE0), Color(0xFF1D3FAE)],
    this.receivedBubbleGradient = const [Color(0x22FFFFFF), Color(0x14FFFFFF)],
    this.receivedBubbleTextColor = Colors.white,
    this.receivedBubbleBorder,
    this.bubbleSenderLabelColor = Colors.white54,
    this.bubbleTimestampColor = Colors.white38,
  });

  // ── Per-letter gradient palette ────────────────────────────────────────
  // Also used as the avatar ring's conic-gradient colors when avatarRing is on.
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

  static const VeilThemeColors modern = VeilThemeColors(
    scaffold:        Color(0xFFF3F4F8),
    titleStart:      Color(0xFFFCFCFE),
    titleEnd:        Color(0xFFFCFCFE),
    titleOnColor:    Color(0xFF14161F),
    nameBg:          Color(0xFFF3F4F8),
    sectionBg:       Color(0xFFF3F4F8),
    sectionText:     Color(0xFF6C6C70),
    listBg:          Color(0xFFF3F4F8),
    rowBg:           Colors.white,
    roundedRows:     true,
    rowRadius:       18,
    chatBg:          Color(0xFFF3F4F8),
    inputBg:         Colors.white,
    myNameColor:     Color(0xFF3B5FE0),
    theirNameColor:  Color(0xFFD0654F),
    gradientAvatar:  true,
    solidAvatarBg:   Color(0xFF3B5FE0),
    avatarText:      Colors.white,
    avatarRing:      true,
    nameText:        Color(0xFF14161F),
    previewText:     Color(0xFF7A7F8C),
    timestampText:   Color(0xFF9AA0AC),
    badgeBg:         Color(0xFF3B5FE0),
    badgeText:       Colors.white,
    toolbarBg:       Colors.white,
    toolbarText:     Color(0xFF8A8F9C),
    toolbarActive:   Color(0xFF3B5FE0),
    floatingToolbar: true,
    presenceBorder:  Colors.white,
    divider:         Color(0xFFE4E7EF),
    useGlass:        true,
    showGlow:        false,
    titleBarBorderColor: Color(0x12000000),
    bubbleLayout:    true,
    pillComposer:    true,
    bubbleShowSenderBothSides: true,
    sentBubbleGradient:     [Color(0xFF3B5FE0), Color(0xFF1D3FAE)],
    receivedBubbleGradient: [Colors.white, Colors.white],
    receivedBubbleTextColor: Color(0xFF14161F),
    receivedBubbleBorder:    null,
    bubbleSenderLabelColor:  Color(0xFF9AA0AC),
    bubbleTimestampColor:    Color(0xFF9AA0AC),
  );

  static const VeilThemeColors retro = VeilThemeColors(
    scaffold:        Color(0xFFF5F6FA),
    titleStart:      Color(0xFF142D82),
    titleEnd:        Color(0xFF5B8FD4),
    titleOnColor:    Colors.white,
    nameBg:          Color(0xFF142D82),
    sectionBg:       Color(0xFF5B8FD4),
    sectionText:     Colors.white,
    listBg:          Color(0xFFF5F6FA),
    rowBg:           Colors.white,
    roundedRows:     true,
    rowRadius:       12,
    chatBg:          Color(0xFFFBFAF7),
    inputBg:         Colors.white,
    myNameColor:     Color(0xFF3B5FE0),
    theirNameColor:  Color(0xFFD0654F),
    gradientAvatar:  true,
    solidAvatarBg:   Color(0xFF3B5FE0),
    avatarText:      Colors.white,
    avatarRing:      true,
    nameText:        Color(0xFF181A22),
    previewText:     Color(0xFF6B7080),
    timestampText:   Color(0xFF9AA0AC),
    badgeBg:         Color(0xFF3B5FE0),
    badgeText:       Colors.white,
    toolbarBg:       Colors.white,
    toolbarText:     Color(0xFF5C6270),
    toolbarActive:   Color(0xFF3B5FE0),
    presenceBorder:  Colors.white,
    divider:         Color(0xFFEAEDF3),
  );

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
    titleBarBorderColor: Color(0x33FFFFFF),
    bubbleLayout:    true,
    sentBubbleGradient:     [Color(0xFF6D28D9), Color(0xFF4C1D95)],
    receivedBubbleGradient: [Color(0x22FFFFFF), Color(0x14FFFFFF)],
    receivedBubbleTextColor: Colors.white,
    receivedBubbleBorder:    Color(0x1EFFFFFF),
    bubbleSenderLabelColor:  Colors.white54,
    bubbleTimestampColor:    Colors.white38,
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
    VeilThemeMode.modern => VeilThemeColors.modern,
    VeilThemeMode.retro  => VeilThemeColors.retro,
    VeilThemeMode.aim    => VeilThemeColors.aim,
    VeilThemeMode.dark   => VeilThemeColors.dark,
    VeilThemeMode.glass  => VeilThemeColors.glass,
    VeilThemeMode.light  => VeilThemeColors.light,
  };
}
