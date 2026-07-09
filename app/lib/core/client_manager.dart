import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'disappearing_message_service.dart';
import 'notification_service.dart';

const kHomeserver = 'https://matrix.veilmsg.com';

class ClientManager extends ChangeNotifier {
  late Client _client;
  Client get client => _client;

  bool _isReady = false;
  bool get isReady => _isReady;

  bool get isLoggedIn => _client.isLogged();

  /// Room IDs we've already fired an invite notification for.
  final _knownInvites = <String>{};

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
      // Detect new incoming invites and fire a local notification for each.
      for (final room in _client.rooms) {
        if (room.membership == Membership.invite) {
          if (!_knownInvites.contains(room.id)) {
            _knownInvites.add(room.id);
            final inviterEvent = room.getState(EventTypes.RoomMember, _client.userID!);
            final inviterId = inviterEvent?.senderId ?? '';
            final inviterName = inviterId.isNotEmpty
                ? inviterId.split(':').first.replaceFirst('@', '')
                : room.getLocalizedDisplayname();
            await NotificationService.instance.showMessage(
              roomId: room.id,
              senderName: inviterName,
              body: '$inviterName wants to message you',
            );
          }
        } else {
          _knownInvites.remove(room.id);
        }
      }
      notifyListeners();
    });

    // Fire a local notification for every incoming message not from ourselves.
    _client.onEvent.stream.listen((update) async {
      if (update.type != EventUpdateType.timeline) return;
      final raw = update.content;
      if (raw['type'] != 'm.room.message') return;
      if (raw['sender'] == _client.userID) return;

      final sender = (raw['sender'] as String?)
              ?.split(':').first.replaceFirst('@', '') ??
          'Unknown';
      final body = (raw['content'] as Map?)?['body'] as String? ?? 'New message';

      await NotificationService.instance.showMessage(
        roomId: update.roomID,
        senderName: sender,
        body: body,
      );
    });

    // Reload any persisted per-message disappear timers.
    await DisappearingMessageService.instance.loadAndReschedule(_client);

    // Auto-schedule disappearing for incoming messages that carry veil_expire_at.
    _client.onEvent.stream.listen((update) async {
      if (update.type != EventUpdateType.timeline) return;
      final raw = update.content;
      if (raw['type'] != 'm.room.message') return;
      final expireAt = (raw['content'] as Map?)?['veil_expire_at'] as int?;
      if (expireAt == null) return;
      final remaining = expireAt - DateTime.now().millisecondsSinceEpoch;
      if (remaining <= 0) return;
      final eventId = raw['event_id'] as String?;
      if (eventId == null) return;
      await DisappearingMessageService.instance.schedule(
        eventId: eventId,
        roomId: update.roomID,
        after: Duration(milliseconds: remaining),
        client: _client,
      );
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

  List<Room> get inviteRooms => _client.rooms
      .where((r) => r.membership == Membership.invite)
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

  Future<void> setDisplayName(String name) async {
    final userId = _client.userID;
    if (userId == null) return;
    await _client.setProfileField(userId, 'displayname', {'displayname': name});
    notifyListeners();
  }
}
