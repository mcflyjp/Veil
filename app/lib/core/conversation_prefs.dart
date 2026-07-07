import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-conversation settings stored in shared_preferences.
/// Key prefix: conv_{roomId}_{setting}
class ConversationPrefs {
  final String roomId;
  final SharedPreferences _prefs;

  ConversationPrefs._(this.roomId, this._prefs);

  static Future<ConversationPrefs> load(String roomId) async {
    final p = await SharedPreferences.getInstance();
    return ConversationPrefs._(roomId, p);
  }

  String _k(String s) => 'conv_${roomId}_$s';

  // ── Font ──────────────────────────────────────────────────────────
  String get fontFamily => _prefs.getString(_k('font_family')) ?? 'Arial';
  double get fontSize   => _prefs.getDouble(_k('font_size'))   ?? 14.0;
  Future<void> setFont(String family, double size) async {
    await _prefs.setString(_k('font_family'), family);
    await _prefs.setDouble(_k('font_size'), size);
  }

  // ── Mute ─────────────────────────────────────────────────────────
  bool get muted => _prefs.getBool(_k('muted')) ?? false;
  Future<void> setMuted(bool v) => _prefs.setBool(_k('muted'), v);

  // ── Hidden ────────────────────────────────────────────────────────
  bool get hidden => _prefs.getBool(_k('hidden')) ?? false;
  Future<void> setHidden(bool v) => _prefs.setBool(_k('hidden'), v);

  // ── Disappearing messages (seconds, 0 = off) ──────────────────────
  int get disappearingSecs => _prefs.getInt(_k('disappearing')) ?? 0;
  Future<void> setDisappearing(int secs) => _prefs.setInt(_k('disappearing'), secs);

  // ── Theme ─────────────────────────────────────────────────────────
  String get themeKey => _prefs.getString(_k('theme')) ?? 'classic';
  Future<void> setTheme(String key) => _prefs.setString(_k('theme'), key);

  static const Map<String, ConvTheme> themes = {
    'classic': ConvTheme(label: 'Classic AIM',  chatBg: Color(0xFFFFFFFF), myName: Color(0xFF0000EE), theirName: Color(0xFFCC0000), darkChatBg: Color(0xFF1A1A1A)),
    'midnight': ConvTheme(label: 'Midnight',     chatBg: Color(0xFF0D0D1A), myName: Color(0xFF88AAFF), theirName: Color(0xFFFF8888), darkChatBg: Color(0xFF0D0D1A)),
    'forest':  ConvTheme(label: 'Forest',        chatBg: Color(0xFFF0FFF0), myName: Color(0xFF006600), theirName: Color(0xFF8B4513), darkChatBg: Color(0xFF0A1A0A)),
    'rose':    ConvTheme(label: 'Rose',          chatBg: Color(0xFFFFF0F4), myName: Color(0xFFCC0055), theirName: Color(0xFF880066), darkChatBg: Color(0xFF1A0A10)),
    'ocean':   ConvTheme(label: 'Ocean',         chatBg: Color(0xFFF0FAFF), myName: Color(0xFF005599), theirName: Color(0xFF007766), darkChatBg: Color(0xFF061A22)),
  };

  ConvTheme get theme => themes[themeKey] ?? themes['classic']!;
}

class ConvTheme {
  final String label;
  final Color chatBg;
  final Color darkChatBg;
  final Color myName;
  final Color theirName;
  const ConvTheme({
    required this.label,
    required this.chatBg,
    required this.darkChatBg,
    required this.myName,
    required this.theirName,
  });
}
