import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class ReminderNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static Future<void> initialize() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      tzdata.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Reminder notification init error: $e');
    }
  }

  static Future<void> schedule({
    required int taskId,
    required String title,
    required DateTime firstAt,
    required DateTime until,
    required int everyMinutes,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await cancel(taskId);
      final start = firstAt.isAfter(DateTime.now())
          ? firstAt
          : DateTime.now().add(Duration(minutes: everyMinutes));
      final available = await _plugin.pendingNotificationRequests();
      final count = ((until.difference(start).inMinutes ~/ everyMinutes) + 1)
          .clamp(0, (450 - available.length).clamp(0, 450));
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'task_reminders',
          'Nhắc công việc',
          channelDescription: 'Nhắc bạn hoàn thành công việc đúng hạn',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );
      for (var i = 0; i < count; i++) {
        final at = start.add(Duration(minutes: everyMinutes * i));
        await _plugin.zonedSchedule(
          taskId * 1000 + i,
          'Đến hạn công việc',
          title,
          tz.TZDateTime.from(at, tz.local),
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'task:$taskId',
        );
      }
    } catch (e) {
      debugPrint('Schedule notification error: $e');
    }
  }

  static Future<void> cancel(int taskId) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final item in pending.where((item) => item.id ~/ 1000 == taskId)) {
        await _plugin.cancel(item.id);
      }
    } catch (e) {
      debugPrint('Cancel notification error: $e');
    }
  }

  static Future<void> showNotice(int id, String title, String body) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _plugin.show(
        id + 100000,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'task_notices',
            'Thông báo nhóm',
            channelDescription: 'Thông báo liên quan đến công việc nhóm',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Show notice error: $e');
    }
  }
}

