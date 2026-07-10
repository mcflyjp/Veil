import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'veil_theme.dart';

const _kAccountDataType = 'im.veil.user_settings';

/// Holds the user's theme choice and font formatting prefs.
/// Persists locally via SharedPreferences and syncs to Matrix account data
/// so settings follow the user across every device they sign in on.
class VeilUserPrefs extends ChangeNotifier {
  VeilThemeMode _theme    = VeilThemeMode.aim;
  String  _fontFamily     = 'Arial';
  double  _fontSize       = 16.0;
  bool    _bold           = false;
  bool    _italic         = false;
  bool    _underline      = false;

  VeilThemeMode  get theme      => _theme;
  VeilThemeColors get colors    => VeilThemeColors.forMode(_theme);
  String  get fontFamily        => _fontFamily;
  double  get fontSize          => _fontSize;
  bool    get bold              => _bold;
  bool    get italic            => _italic;
  bool    get underline         => _underline;

  Client? _client;
  StreamSubscription<SyncUpdate>? _syncSub;
  String? _lastAccountDataContent; // guards against redundant sync pulls

  VeilUserPrefs() { _loadLocal(); }

  // ── Client attachment ──────────────────────────────────────────────────

  void attachClient(Client client) {
    if (_client == client) return;
    _syncSub?.cancel();
    _client = client;
    // Pull remote settings immediately, then refresh on every sync
    // so changes made on another device are picked up automatically.
    _pullFromMatrix();
    _syncSub = client.onSync.stream.listen((_) => _pullFromMatrix());
  }

  void detachClient() {
    _syncSub?.cancel();
    _syncSub = null;
    _client = null;
  }

  // ── Public setters ─────────────────────────────────────────────────────

  Future<void> setTheme(VeilThemeMode mode) async {
    if (_theme == mode) return;
    _theme = mode;
    notifyListeners();
    await _persist();
  }

  void cycleTheme() => setTheme(
    VeilThemeMode.values[(_theme.index + 1) % VeilThemeMode.values.length]);

  Future<void> setFont({
    String? family,
    double? size,
    bool? bold,
    bool? italic,
    bool? underline,
  }) async {
    var changed = false;
    if (family    != null && family    != _fontFamily) { _fontFamily = family;    changed = true; }
    if (size      != null && size      != _fontSize)   { _fontSize   = size;      changed = true; }
    if (bold      != null && bold      != _bold)       { _bold       = bold;      changed = true; }
    if (italic    != null && italic    != _italic)     { _italic     = italic;    changed = true; }
    if (underline != null && underline != _underline)  { _underline  = underline; changed = true; }
    if (!changed) return;
    notifyListeners();
    await _persist();
  }

  // ── Persistence ────────────────────────────────────────────────────────

  Future<void> _loadLocal() async {
    final p = await SharedPreferences.getInstance();
    _theme = VeilThemeMode.values.firstWhere(
      (e) => e.name == (p.getString('veil_app_theme') ?? 'aim'),
      orElse: () => VeilThemeMode.aim,
    );
    _fontFamily = p.getString('user_font_family')   ?? 'Arial';
    _fontSize   = p.getDouble('user_font_size')     ?? 16.0;
    _bold       = p.getBool('user_font_bold')       ?? false;
    _italic     = p.getBool('user_font_italic')     ?? false;
    _underline  = p.getBool('user_font_underline')  ?? false;
    notifyListeners();
  }

  Future<void> _saveLocal() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('veil_app_theme',     _theme.name);
    await p.setString('user_font_family',   _fontFamily);
    await p.setDouble('user_font_size',     _fontSize);
    await p.setBool('user_font_bold',       _bold);
    await p.setBool('user_font_italic',     _italic);
    await p.setBool('user_font_underline',  _underline);
  }

  Future<void> _pushToMatrix() async {
    final client = _client;
    if (client == null || !client.isLogged()) return;
    try {
      await client.setAccountData(
        client.userID!,
        _kAccountDataType,
        {
          'theme':          _theme.name,
          'font_family':    _fontFamily,
          'font_size':      _fontSize,
          'font_bold':      _bold,
          'font_italic':    _italic,
          'font_underline': _underline,
        },
      );
    } catch (_) {
      // Non-fatal — settings are still saved locally.
    }
  }

  Future<void> _persist() async {
    await _saveLocal();
    await _pushToMatrix();
  }

  /// Read account data pushed by another device (or an earlier session).
  Future<void> _pullFromMatrix() async {
    final client = _client;
    if (client == null || !client.isLogged()) return;

    final event = client.accountData[_kAccountDataType];
    if (event == null) return;

    // Skip entirely if the raw content hasn't changed since last pull
    final snapshot = event.content.toString();
    if (snapshot == _lastAccountDataContent) return;
    _lastAccountDataContent = snapshot;

    final c = event.content;

    var changed = false;

    final themeName = c['theme'] as String?;
    if (themeName != null) {
      final mode = VeilThemeMode.values.firstWhere(
        (e) => e.name == themeName, orElse: () => VeilThemeMode.aim);
      if (mode != _theme) { _theme = mode; changed = true; }
    }

    final fam = c['font_family'] as String?;
    if (fam != null && fam != _fontFamily) { _fontFamily = fam; changed = true; }

    final size = (c['font_size'] as num?)?.toDouble();
    if (size != null && size != _fontSize) { _fontSize = size; changed = true; }

    final bold = c['font_bold'] as bool?;
    if (bold != null && bold != _bold) { _bold = bold; changed = true; }

    final italic = c['font_italic'] as bool?;
    if (italic != null && italic != _italic) { _italic = italic; changed = true; }

    final underline = c['font_underline'] as bool?;
    if (underline != null && underline != _underline) { _underline = underline; changed = true; }

    if (changed) {
      await _saveLocal();
      notifyListeners();
    }
  }
}
