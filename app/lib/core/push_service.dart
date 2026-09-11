// Push notification wiring (Phase 3 of the calls/notifications work) —
// registers this device's FCM token as a Matrix "pusher" so Dendrite can
// wake the app via our self-hosted Sygnal gateway (see CLAUDE.md's "Push
// notifications" section) when it's backgrounded or fully closed, and shows
// a local notification from the background isolate FCM hands the message to.
//
// Deliberately does NOT attempt to decrypt message content in the
// background — Veil's rooms are always E2E encrypted, so the push payload's
// `content` field is Megolm ciphertext the homeserver (and therefore Sygnal
// and FCM) never had plaintext for in the first place. What Dendrite DOES
// send unencrypted is room/sender metadata (room names and member display
// names aren't secret in Matrix, only message bodies are) — `sender_display_
// name` and `room_name` — which is enough for a genuinely informative
// "so-and-so sent a message in X" notification without decrypting anything.
// Real content shows once the user opens the app and it syncs normally.
//
// Same reasoning applies to calls: an encrypted room's m.call.invite is
// itself inside an m.room.encrypted push, indistinguishable from a regular
// message in the push payload's `type` field (it'll just say
// "m.room.encrypted" either way) — so this can't show a distinct
// "incoming call" notification in the background. It shows the same
// generic new-activity notification; CallService's normal to-device/
// timeline listening (already verified working) picks up the real
// invite and shows the actual incoming-call screen once the app opens.

import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';

/// Must match the `app_id` key under Sygnal's `apps:` config on the server
/// (see /etc/sygnal/sygnal.yaml on the VM) — Sygnal routes each pusher's
/// notifications to the pushkin registered under this exact app_id.
const _kPusherAppId = 'com.veil.veil';
const _kPushGatewayUrl = 'https://veilmsg.com/_matrix/push/v1/notify';

/// Same notification channel NotificationService uses — these are the same
/// kind of notification (new activity in a room) shown from a different
/// code path (background isolate vs. foreground sync), so they should look
/// identical to the user and share dedup behavior (see below).
const _kChannelId = 'veil_messages';

class PushService {
  PushService._();
  static final instance = PushService._();

  String? _registeredToken;

  /// Android/iOS only, same as NotificationService — no FCM on web.
  Future<void> init() async {
    if (kIsWeb) return;
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
    await FirebaseMessaging.instance.requestPermission();

    // Foreground pushes are intentionally ignored: the app's own live
    // Matrix sync (ClientManager's onEvent listener -> NotificationService)
    // already shows a real, decrypted notification for anything that
    // happens while the app is actually running and connected. Handling
    // this too would just double the notification.
  }

  // ── Lifecycle: attach/detach the logged-in Matrix client ───────────────
  // Same pattern as VeilUserPrefs/CallService in main.dart's login listener.

  Future<void> attachClient(Client client) async {
    if (kIsWeb) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _registerPusher(client, token);
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _registerPusher(client, newToken);
    });
  }

  void detachClient() {
    // Deliberately not deleting the pusher here: by the time this fires
    // (after ClientManager.logout() has already cleared the session), the
    // access token needed to authenticate a pushers/set delete call is
    // already gone. The pusher just goes stale on the server rather than
    // being cleanly removed -- harmless (no content in these pushes to
    // leak), just not tidy. Revisit if that ever becomes a real problem.
    _registeredToken = null;
  }

  Future<void> _registerPusher(Client client, String fcmToken) async {
    if (_registeredToken == fcmToken) return; // already registered this one
    try {
      await client.request(
        RequestType.POST,
        '/client/v3/pushers/set',
        data: {
          'app_id': _kPusherAppId,
          'pushkey': fcmToken,
          'app_display_name': 'Veil',
          'device_display_name': 'Veil (${Platform.operatingSystem})',
          'kind': 'http',
          'lang': 'en',
          'data': {'url': _kPushGatewayUrl},
        },
      );
      _registeredToken = fcmToken;
    } catch (e) {
      Logs().w('[PushService] Failed to register pusher', e);
    }
  }
}

/// Runs in a separate, minimal Flutter engine/isolate spun up just for this
/// call -- no access to the running app's ClientManager, CallService, or
/// any other app state. Must be a top-level (or static) function annotated
/// exactly like this for the plugin to find it after app restarts.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final data = message.data;
  final roomId = data['room_id'] as String?;
  if (roomId == null) return; // badge-only push, nothing to show

  final sender = data['sender_display_name'] as String?;
  final roomName = data['room_name'] as String?;
  final title = roomName ?? sender ?? 'Veil';
  final body = (roomName != null && sender != null)
      ? '$sender sent a message'
      : 'New message';

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  const channel = AndroidNotificationChannel(
    _kChannelId,
    'Messages',
    description: 'New Veil message notifications',
    importance: Importance.high,
    playSound: true,
  );
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // Same id derivation as NotificationService.showMessage (roomId.hashCode)
  // so a background push and a later live-sync notification for the same
  // room replace each other instead of stacking as two separate alerts.
  await plugin.show(
    id: roomId.hashCode.abs(),
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _kChannelId,
        'Messages',
        channelDescription: 'New Veil message notifications',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
    payload: roomId,
  );
}
