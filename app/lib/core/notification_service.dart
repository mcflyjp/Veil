import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();

  /// Set by ChatScreen on open, cleared on dispose.
  /// Suppresses notifications for the room currently on screen.
  String? activeRoomId;

  /// Called when the user taps a notification. Receives the roomId payload.
  void Function(String roomId)? onTap;

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
