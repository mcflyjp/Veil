import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

const kHomeserver = 'https://matrix.veilmsg.com';

class ClientManager extends ChangeNotifier {
  late Client _client;
  Client get client => _client;

  bool _isReady = false;
  bool get isReady => _isReady;

  bool get isLoggedIn => _client.isLogged();

  Future<void> init() async {
    late MatrixSdkDatabase db;
    if (kIsWeb) {
      db = await MatrixSdkDatabase.init('veil_db');
    } else {
      final dbPath = await sqflite.getDatabasesPath();
      final sqfliteDb = await sqflite.openDatabase(
        p.join(dbPath, 'veil_db.sqlite'),
      );
      db = await MatrixSdkDatabase.init('veil_db', database: sqfliteDb);
    }
    _client = Client('Veil', database: db);

    await _client.init(
      waitForFirstSync: false,
      waitUntilLoadCompletedLoaded: false,
    );

    _client.onLoginStateChanged.stream.listen((_) => notifyListeners());
    _client.onSync.stream.listen((_) async {
      // Auto-accept all pending invites so DMs appear instantly on both sides.
      for (final room in _client.rooms) {
        if (room.membership == Membership.invite) {
          try { await room.join(); } catch (_) {}
        }
      }
      notifyListeners();
    });

    _isReady = true;
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    await _client.checkHomeserver(Uri.parse(kHomeserver));
    await _client.login(
      LoginType.mLoginPassword,
      identifier: AuthenticationUserIdentifier(user: username),
      password: password,
      initialDeviceDisplayName: 'Veil',
    );
    notifyListeners();
  }

  /// Two-step Matrix UIA registration via raw HTTP, then SDK login.
  Future<void> register(String username, String password, String? displayName) async {
    await _client.checkHomeserver(Uri.parse(kHomeserver));

    final uri = Uri.parse('$kHomeserver/_matrix/client/v3/register');

    final resp1 = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    final body1 = jsonDecode(resp1.body) as Map<String, Object?>;

    if (resp1.statusCode == 200) {
      await _doLogin(username, password, displayName);
      return;
    }

    final session = body1['session'] as String?;
    if (session == null) {
      throw Exception(
        '${body1['errcode'] ?? 'ERROR'}: ${body1['error'] ?? resp1.body}',
      );
    }

    final resp2 = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'initial_device_display_name': 'Veil',
        'auth': {'type': 'm.login.dummy', 'session': session},
      }),
    );

    if (resp2.statusCode != 200) {
      final err = jsonDecode(resp2.body) as Map<String, Object?>;
      throw Exception(
        '${err['errcode'] ?? 'ERROR'}: ${err['error'] ?? resp2.body}',
      );
    }

    await _doLogin(username, password, displayName);
  }

  Future<void> _doLogin(String username, String password, String? displayName) async {
    await _client.login(
      LoginType.mLoginPassword,
      identifier: AuthenticationUserIdentifier(user: username),
      password: password,
      initialDeviceDisplayName: 'Veil',
    );
    if (displayName != null && displayName.isNotEmpty) {
      await _client.setProfileField(
        _client.userID!,
        'displayname',
        {'displayname': displayName},
      );
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await _client.logout();
    notifyListeners();
  }

  List<Room> get rooms => _client.rooms
      .where((r) => r.membership == Membership.join)
      .toList();

  Room? roomById(String id) {
    try {
      return _client.rooms.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  String get myScreenName {
    return _client.userID?.split(':').first.replaceFirst('@', '') ?? 'unknown';
  }

  Future<String?> fetchDisplayName() async {
    try {
      final userId = _client.userID;
      if (userId == null) return null;
      final profile = await _client.getUserProfile(userId);
      return profile.displayname;
    } catch (_) {
      return null;
    }
  }
}
