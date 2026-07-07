import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

const kHomeserver = 'https://matrix.veilmsg.com';

class ClientManager extends ChangeNotifier {
  late Client _client;
  Client get client => _client;

  bool _isReady = false;
  bool get isReady => _isReady;

  bool get isLoggedIn => _client.isLogged();

  Future<void> init() async {
    final db = await MatrixSdkDatabase.init('veil_db');
    _client = Client('Veil', database: db);

    await _client.init(
      waitForFirstSync: false,
      waitUntilLoadCompletedLoaded: false,
    );

    _client.onLoginStateChanged.stream.listen((_) => notifyListeners());
    _client.onSync.stream.listen((_) => notifyListeners());

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

  Future<void> register(String username, String password, String? displayName) async {
    await _client.checkHomeserver(Uri.parse(kHomeserver));
    await _client.register(
      username: username,
      password: password,
      initialDeviceDisplayName: 'Veil',
    );
    if (displayName != null && displayName.isNotEmpty) {
      await _client.setProfileField(_client.userID!, 'displayname', {'displayname': displayName});
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await _client.logout();
    notifyListeners();
  }

  List<Room> get rooms => _client.rooms;

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
