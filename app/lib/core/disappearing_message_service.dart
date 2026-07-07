import 'dart:async';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists per-message disappear timers and fires Matrix redactions when they expire.
/// Storage key: 'disappear_{eventId}' = '{roomId}|{expireAtMs}'
class DisappearingMessageService {
  DisappearingMessageService._();
  static final instance = DisappearingMessageService._();

  static const _prefix = 'disappear_';
  final Map<String, Timer> _timers = {};

  /// Schedule a message to be redacted after [after].
  Future<void> schedule({
    required String eventId,
    required String roomId,
    required Duration after,
    required Client client,
  }) async {
    final expireAt = DateTime.now().add(after).millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$eventId', '$roomId|$expireAt');
    _arm(eventId: eventId, roomId: roomId, expireAt: expireAt, client: client);
  }

  /// On app start, reload any pending timers from SharedPreferences.
  Future<void> loadAndReschedule(Client client) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final val = prefs.getString(key);
      if (val == null) continue;
      final parts = val.split('|');
      if (parts.length != 2) continue;
      final roomId = parts[0];
      final expireAt = int.tryParse(parts[1]) ?? 0;
      final eventId = key.substring(_prefix.length);
      _arm(eventId: eventId, roomId: roomId, expireAt: expireAt, client: client);
    }
  }

  /// Returns true if [eventId] has an active disappear timer.
  Future<bool> isScheduled(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('$_prefix$eventId');
  }

  /// Returns the remaining Duration, or null if not scheduled.
  Future<Duration?> remaining(String eventId) async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString('$_prefix$eventId');
    if (val == null) return null;
    final expireAt = int.tryParse(val.split('|').last) ?? 0;
    final ms = expireAt - DateTime.now().millisecondsSinceEpoch;
    return ms > 0 ? Duration(milliseconds: ms) : Duration.zero;
  }

  void _arm({
    required String eventId,
    required String roomId,
    required int expireAt,
    required Client client,
  }) {
    _timers[eventId]?.cancel();
    final remaining = expireAt - DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) {
      _redact(eventId: eventId, roomId: roomId, client: client);
      return;
    }
    _timers[eventId] = Timer(Duration(milliseconds: remaining), () {
      _redact(eventId: eventId, roomId: roomId, client: client);
    });
  }

  Future<void> _redact({
    required String eventId,
    required String roomId,
    required Client client,
  }) async {
    try {
      final room = client.getRoomById(roomId);
      if (room != null) {
        await room.redactEvent(eventId, reason: 'Message expired');
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$eventId');
    _timers.remove(eventId);
  }
}
