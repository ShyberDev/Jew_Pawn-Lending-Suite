import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Local due reminders (#040) — the Android side.
///
/// Kept deliberately small and failure-tolerant: the app must work on a phone
/// where notifications are denied, on a device with no Play services, and in
/// `flutter test` where there is no platform channel at all. Every entry point
/// catches its own errors and reports whether it worked, so a notification
/// problem can never block the ledger.
///
/// One recurring summary is scheduled ("9:00 — who is due"), not one per
/// member: a shop with 30 members should not get 30 pings. The content is the
/// same [DueReminderPlan] the app shows, so the notification and the screen can
/// never disagree.
class DueNotifications {
  const DueNotifications._();

  /// Stable id: rescheduling replaces the previous summary instead of stacking.
  static const summaryId = 7001;
  static const channelId = 'due_reminders';
  static const channelName = 'Due reminders';
  static const defaultHour = 9;

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Initialises the plugin once. Returns false when notifications are simply
  /// not available, which is not an error worth interrupting the shop for.
  static Future<bool> init() async {
    if (_ready) return true;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings: settings);
      _ready = true;
      return true;
    } catch (e) {
      debugPrint('Due notifications unavailable: $e');
      return false;
    }
  }

  /// Asks for POST_NOTIFICATIONS on Android 13+. Older Android versions grant
  /// it at install time, hence the null-safe result.
  static Future<bool> requestPermission() async {
    if (!await init()) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (e) {
      debugPrint('Notification permission failed: $e');
      return false;
    }
  }

  /// Schedules the next 9:00 summary. Called on every app start and after a
  /// write that changes who is due, so the roll-forward is self-healing.
  static Future<bool> scheduleDaily({
    required String title,
    required String body,
    int hour = defaultHour,
  }) async {
    if (!await init()) return false;
    try {
      final now = DateTime.now();
      var next = DateTime(now.year, now.month, now.day, hour);
      if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        id: summaryId,
        title: title,
        body: body,
        // The instant is what matters, so a UTC TZDateTime built from a local
        // wall-clock time fires at the shop's own 9:00 without shipping the
        // timezone database or needing the device zone name.
        scheduledDate: tz.TZDateTime.from(next.toUtc(), tz.UTC),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription:
                'Who has a khatabook collection due or overdue today',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return true;
    } catch (e) {
      debugPrint('Due reminder scheduling failed: $e');
      return false;
    }
  }

  /// Removes the pending summary (toggle off, or nobody is due at all).
  static Future<void> cancel() async {
    if (!await init()) return;
    try {
      await _plugin.cancel(id: summaryId);
    } catch (e) {
      debugPrint('Due reminder cancel failed: $e');
    }
  }
}
