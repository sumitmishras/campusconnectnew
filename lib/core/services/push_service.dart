import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'supabase_service.dart';

/// Push notifications, V1: a new chat message and an incoming connection
/// request. Nothing else notifies.
///
/// The decisions about *whether* to notify are not here and should not be —
/// they are in Postgres (`fanout_message_notifications`, 0010, and the
/// connection trigger in 0015), where the mute switch, the block list and the
/// notification settings already live. A student who has muted a thread gets
/// no row written, so there is nothing for this class to suppress.
///
/// What is left for the client is the part only the client can know:
///
///   * whether the student is looking at that very conversation right now,
///   * drawing the notification while the app is in the foreground, which FCM
///     does not do on its own,
///   * where a tap should land.
class PushService {
  const PushService._();

  static final _local = FlutterLocalNotificationsPlugin();

  /// Must match `android.notification.channel_id` in the push-notify Edge
  /// Function — a message naming a channel the app never created is silently
  /// dropped by Android.
  static const _channelId = 'campus_connect_default';

  static bool _ready = false;

  /// What the student currently has open, asked of whoever knows. Registered
  /// by the app shell, because the answer lives in `ChatProvider` and a
  /// service should not reach into the widget tree to find it.
  static String? Function()? currentConversation;

  /// A deep link waiting for the app to be in a state that can follow it —
  /// the notification that launched a cold start, most often, which arrives
  /// long before there is a signed-in student or a navigator.
  static final ValueNotifier<String?> pendingLink = ValueNotifier(null);

  /// Wires up Firebase and the notification channel. Safe to call when the
  /// app has no Firebase configuration at all: it gives up quietly and the
  /// rest of the app behaves exactly as it did before push existed.
  static Future<void> initialize() async {
    if (_ready) return;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      // No google-services.json, or an unconfigured platform. Not fatal —
      // notifications simply do not arrive.
      debugPrint('[push] Firebase unavailable, notifications are off: $e');
      return;
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      // Asked for later, together with the FCM permission, so the student
      // sees one prompt rather than two.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      const InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: (response) =>
          _open(response.payload ?? ''),
    );

    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          'Messages and requests',
          description: 'New chat messages and connection requests.',
          importance: Importance.high,
        ));

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _open(_linkOf(message)),
    );

    // The notification that started the app from cold. Held until something
    // is on screen that can act on it.
    final launched = await FirebaseMessaging.instance.getInitialMessage();
    if (launched != null) pendingLink.value = _linkOf(launched);

    _ready = true;
  }

  /// Registers this handset against the signed-in student.
  ///
  /// Called after sign-in and on every resume: an FCM token can be rotated by
  /// the system at any time, and a stale one is a student who quietly stops
  /// receiving anything.
  static Future<void> registerDevice() async {
    if (!_ready || !SupabaseService.isReady) return;

    final messaging = FirebaseMessaging.instance;

    // Android 13+ and iOS both gate notifications behind this. Declined is a
    // real answer: nothing else in the app changes, there are simply no
    // notifications.
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[push] notification permission declined');
      return;
    }

    try {
      final token = await messaging.getToken();
      if (token != null) await _saveToken(token);
    } catch (e) {
      debugPrint('[push] could not obtain a token: $e');
    }

    // Rotations, and the first token on a device that had none at install.
    messaging.onTokenRefresh.listen(_saveToken);
  }

  static Future<void> _saveToken(String token) async {
    try {
      await SupabaseService.client.rpc('register_push_device', params: {
        'p_token': token,
        'p_platform': Platform.isIOS ? 'ios' : 'android',
        'p_locale': Platform.localeName,
      });
      debugPrint('[push] device registered');
    } catch (e) {
      // The student is still signed in and everything else works; they just
      // will not get pushes until the next attempt.
      debugPrint('[push] device registration failed: $e');
    }
  }

  /// Called on sign-out. Deleting the token at the FCM end is what stops the
  /// next person to use this phone from receiving the last person's messages
  /// — the server row is re-pointed by `register_push_device` on their first
  /// sign-in, but that leaves a window in between.
  static Future<void> signOut() async {
    if (!_ready) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // Already gone, or no token was ever issued.
    }
  }

  // ------------------------------------------------------------ foreground

  /// FCM does not draw anything while the app is in the foreground, so this
  /// does — except when the student is already looking at the conversation
  /// the message belongs to, which is the one case where a notification would
  /// be describing something already on screen.
  static void _onForegroundMessage(RemoteMessage message) {
    final link = _linkOf(message);
    if (_isViewing(link)) {
      debugPrint('[push] suppressed, already viewing $link');
      return;
    }

    final notification = message.notification;
    if (notification == null) return;

    _local.show(
      // Same conversation replaces rather than stacks.
      link.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Messages and requests',
          importance: Importance.high,
          priority: Priority.high,
          tag: link,
        ),
        iOS: DarwinNotificationDetails(threadIdentifier: link),
      ),
      payload: link,
    );
  }

  /// True when [link] names the thread that is open right now.
  static bool _isViewing(String link) {
    if (!link.startsWith('/chat/')) return false;
    final open = currentConversation?.call();
    if (open == null || open.isEmpty) return false;
    return link.substring('/chat/'.length) == open;
  }

  static String _linkOf(RemoteMessage message) =>
      (message.data['deep_link'] as String?) ?? '';

  static void _open(String link) {
    if (link.isEmpty) return;
    pendingLink.value = link;
  }
}
