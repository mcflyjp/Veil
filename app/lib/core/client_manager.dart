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
      // Guard: userID may be null if sync fires before login fully completes.
      final myId = _client.userID;
      if (myId == null) { notifyListeners(); return; }

      // Detect new incoming invites and fire a local notification for each.
      for (final room in _client.rooms) {
        if (room.membership == Membership.invite) {
          if (!_knownInvites.contains(room.id)) {
            _knownInvites.add(room.id);
            final inviterEvent = room.getState(EventTypes.RoomMember, myId);
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
    // Timers for new messages are scheduled by ChatScreen when the user opens
    // and views the conversation (view-triggered, not send-triggered).

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

  // ── Timeline cache ─────────────────────────────────────────────────────
  // Keyed by room ID. Keeps Timeline alive across ChatScreen dispose/recreate
  // so we never call room.getTimeline() twice on the same room, which can
  // deadlock if a prior requestHistory() is still in flight.
  final _timelineCache = <String, Timeline>{};

  Timeline? getTimeline(String roomId) => _timelineCache[roomId];

  Future<Timeline> getOrCreateTimeline(String roomId) async {
    final cached = _timelineCache[roomId];
    if (cached != null) return cached;
    final room = roomById(roomId);
    if (room == null) throw Exception('Room $roomId not found');
    final tl = await room.getTimeline(onUpdate: notifyListeners);
    _timelineCache[roomId] = tl;
    // Fire-and-forget: return the timeline immediately so ChatScreen can render
    // with whatever events are already in the local DB. New history streams in
    // via onUpdate as the network fetch completes. Awaiting requestHistory here
    // was the source of the "gray freeze" — it could block for 300ms–2s on a
    // real network before the first frame of ChatScreen was ever painted.
    tl.requestHistory(historyCount: 50).catchError((_) {});
    return tl;
  }

  Future<void> logout() async {
    for (final tl in _timelineCache.values) {
      tl.cancelSubscriptions();
    }
    _timelineCache.clear();
    await _client.logout();
    notifyListeners();
  }

  List<Room> get rooms {
    final joined = _client.rooms
        .where((r) => r.membership == Membership.join)
        .toList();
    // Sort by most-recent message so the buddy list is stable after restart
    joined.sort((a, b) {
      final ta = a.lastEvent?.originServerTs ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.lastEvent?.originServerTs ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return joined;
  }

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

  // ── Device management ──────────────────────────────────────────────

  /// Returns all devices registered to the current account.
  Future<List<Device>> getDevices() async {
    final resp = await _client.getDevices();
    return resp ?? [];
  }

  /// Revokes a device using UIA password authentication (server-side session invalidation).
  /// Uses two-step raw HTTP: first request gets the UIA session, second authenticates.
  Future<void> deleteDevice(String deviceId, String password) async {
    final accessToken = _client.accessToken;
    final userId = _client.userID;
    if (accessToken == null || userId == null) throw Exception('Not logged in');

    final uri = Uri.parse('$kHomeserver/_matrix/client/v3/devices/$deviceId');
    final headers = {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    };

    // Step 1: initiate UIA — server responds 401 with session ID
    final r1 = await http.delete(uri, headers: headers, body: jsonEncode({}));
    if (r1.statusCode == 200) return;
    if (r1.statusCode != 401) {
      final e = jsonDecode(r1.body) as Map<String, Object?>;
      throw Exception('${e['errcode'] ?? 'ERROR'}: ${e['error'] ?? r1.body}');
    }
    final body1 = jsonDecode(r1.body) as Map<String, Object?>;
    final session = body1['session'] as String?;

    // Step 2: respond with password credential
    final r2 = await http.delete(uri, headers: headers, body: jsonEncode({
      'auth': {
        'type': 'm.login.password',
        'identifier': {'type': 'm.id.user', 'user': userId},
        'password': password,
        if (session != null) 'session': session,
      },
    }));
    if (r2.statusCode != 200) {
      final e = jsonDecode(r2.body) as Map<String, Object?>;
      throw Exception('${e['errcode'] ?? 'ERROR'}: ${e['error'] ?? r2.body}');
    }
  }

  /// Generates a short-lived single-use login token for QR-code device linking.
  /// Token is valid for ~2 minutes (Matrix spec 1.7 login token flow).
  Future<String> requestLoginToken() async {
    final accessToken = _client.accessToken;
    if (accessToken == null) throw Exception('Not logged in');
    final uri = Uri.parse('$kHomeserver/_matrix/client/v1/login/get_token');
    final resp = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({}),
    );
    if (resp.statusCode != 200) {
      final e = jsonDecode(resp.body) as Map<String, Object?>;
      throw Exception('${e['errcode'] ?? 'ERROR'}: ${e['error'] ?? resp.body}');
    }
    final body = jsonDecode(resp.body) as Map<String, Object?>;
    final token = body['login_token'] as String?;
    if (token == null) throw Exception('Homeserver did not return a login token');
    return token;
  }

  /// Signs in with a QR-code login token (m.login.token).
  Future<void> loginWithToken(String loginToken) async {
    await _client.checkHomeserver(Uri.parse(kHomeserver));
    await _client.login(
      LoginType.mLoginToken,
      token: loginToken,
      initialDeviceDisplayName: 'Veil',
    );
    notifyListeners();
  }

  /// Forces a buddy list rebuild — call after external hidden-state changes.
  void forceRefresh() => notifyListeners();
}
