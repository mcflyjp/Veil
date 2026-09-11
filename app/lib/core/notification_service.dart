import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Local (on-device) push notification wrapper around flutter_local_notifications.
// Singleton so ClientManager's onEvent listener and the UI (chat screen open/close,
// notification tap routing in main.dart) can all reach the same instance.
// Android only for now — every method no-ops on web.

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  /// Set by ChatScreen on open, cleared on dispose.
  /// Suppresses notifications for the room currently on screen.
  String? activeRoomId;

  /// Called when the user taps a notification. Receives the roomId payload.
  void Function(String roomId)? onTap;

  /// Set during init() if the app process itself was started by tapping a
  /// notification (as opposed to a normal launch, or a tap while already
  /// running — those go through `onTap` above via onDidReceiveNotification
  /// Response instead). `init()` runs before `onTap` is assigned in
  /// main.dart, so this can't just call `onTap` directly at that point —
  /// callers should check this once, right after setting `onTap`, and
  /// clear it so it's only consumed once per cold launch.
  String? pendingLaunchRoomId;

  Future<void> init() async {
    if (kIsWeb) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (response) {
        final roomId = response.payload;
        if (roomId != null) onTap?.call(roomId);
      },
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      pendingLaunchRoomId = launchDetails?.notificationResponse?.payload;
    }

    // Create high-importance channel for Android 8+
    const channel = AndroidNotificationChannel(
      'veil_messages',
      'Messages',
      description: 'New Veil message notifications',
      importance: Importance.high,
      playSound: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Request POST_NOTIFICATIONS permission (Android 13+)
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> showMessage({
    required String roomId,
    required String senderName,
    required String body,
  }) async {
    if (kIsWeb) return;
    if (activeRoomId == roomId) return; // already looking at this room

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'veil_messages',
        'Messages',
        channelDescription: 'New Veil message notifications',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    );

    await _plugin.show(
      id: roomId.hashCode.abs(),
      title: senderName,
      body: body,
      notificationDetails: details,
      payload: roomId,
    );
  }
}
