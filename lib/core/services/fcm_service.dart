import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class FcmService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'fcm_reminders',
    'Ulos Reminders',
    description: 'Reminder notification dari Firebase FCM',
    importance: Importance.max,
  );

  static Future<void> initialize() async {
    // Ensure Firebase is ready (safe to call multiple times)
    await Firebase.initializeApp();

    await _initLocalNotifications();

    // iOS permission
    // (On Android 13+, request permission is also needed depending on behavior.)
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      sound: true,
    );

    debugPrint('[FCM] Permission granted: ${settings.authorizationStatus}');

    // Register foreground listeners
    // NOTE: For FCM payloads that use `notification` field, Firebase may also
    // display a native notification depending on app state.
    // We only show a local notification when the message is data-only.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      // If `notification` is present, treat it as handled by FCM/native layer.
      // Show local notification only for data-only payloads.
      if (message.notification != null) return;
      await _showLocalNotificationFromMessage(message);
    });

    // When user taps notification and opens the app
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM] onMessageOpenedApp: ${message.messageId}');
      // For now we only show logs; navigation can be added later.
    });

    // Background handler must be a top-level/entry-point function.
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Fetch token (useful to send to backend if needed)
    final token = await _messaging.getToken();
    debugPrint('[FCM] device token: $token');
  }

  static Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const iosInit = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) async {
        // No-op for now; can be used for routing.
        debugPrint('[LocalNotif] response payload=${response.payload}');
      },
    );

    // Android channel registration
    final androidPlugin = _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_channel);
  }

  static Future<void> _showLocalNotificationFromMessage(
    RemoteMessage message,
  ) async {
    final notification = message.notification;
    final title = notification?.title ?? 'ULOS Reminder';
    final body = notification?.body ?? '';

    final androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.max,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    await _localNotificationsPlugin.show(
      // Use a stable id if possible
      message.hashCode,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: null,
    );
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background isolate must initialize Firebase and local notifications.
  await Firebase.initializeApp();

  // Initialize local notifications minimal (idempotent)
  final plugin = FlutterLocalNotificationsPlugin();

  // iOS/Android init settings must be done before show().
  const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
  const iosInit = DarwinInitializationSettings();
  const initSettings = InitializationSettings(
    android: androidInit,
    iOS: iosInit,
  );

  await plugin.initialize(initSettings);

  final notification = message.notification;
  final title = notification?.title ?? 'ULOS Reminder';
  final body = notification?.body ?? '';

  const androidChannelId = 'fcm_reminders';
  const androidChannelName = 'Ulos Reminders';
  const androidChannelDescription = 'Reminder notification dari Firebase FCM';

  // If payload contains `notification`, Firebase may already display the native
  // notification in background. To avoid duplicates, only show local
  // notifications for data-only payloads.
  if (message.notification != null) {
    return;
  }

  const androidDetails = AndroidNotificationDetails(
    androidChannelId,
    androidChannelName,
    channelDescription: androidChannelDescription,
    importance: Importance.max,
    priority: Priority.high,
  );

  const iosDetails = DarwinNotificationDetails();

  await plugin.show(
    message.hashCode,
    title,
    body,
    const NotificationDetails(android: androidDetails, iOS: iosDetails),
  );
}
