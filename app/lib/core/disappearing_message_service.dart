import 'dart:async';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Per-message disappearing-timer engine. A timer is only ever started once a
// message has actually been viewed (chat_screen.dart calls schedule() from
// its "visible in an open chat" scan) — not at send time — matching Telegram-
// style behavior. Timers are kept both in memory (_timers, for instant
// isArmed()/remaining() checks) and in SharedPreferences (so they survive an
// app restart via loadAndReschedule). When a timer fires it redacts the
// Matrix event, which deletes it for everyone in the room.

/// Persists per-message disappear timers and fires Matrix redactions when they expire.
/// Storage key: 'disappear_{eventId}' = '{roomId}|{expireAtMs}'
class DisappearingMessageService {
  DisappearingMessageService._();
  static final instance = DisappearingMessageService._();

  static const _prefix = 'disappear_';
  final Map<String, Timer> _timers = {};

  /// Returns true synchronously if [eventId] has an active in-memory timer.
  bool isArmed(String eventId) => _timers.containsKey(eventId);

  /// Schedule a message to be redacted after [after]. Idempotent — silently
  /// returns if the timer is already armed so double-calls are safe.
  Future<void> schedule({
    required String eventId,
    required String roomId,
    required Duration after,
    required Client client,
  }) async {
    if (_timers.containsKey(eventId)) return;
    final expireAt = DateTime.now().add(after).millisecondsSinceEpoch;
    // Arm the in-memory timer first (sync) so isArmed() returns true immediately.
    _arm(eventId: eventId, roomId: roomId, expireAt: expireAt, client: client);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$eventId', '$roomId|$expireAt');
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
