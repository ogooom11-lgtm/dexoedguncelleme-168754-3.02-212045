// lib/src/services/notification_service.dart
import 'dart:convert';

import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/alarm_page.dart';
import '../ui/alarm_end_page.dart';
import '../utils/app_navigator.dart';
import 'alarm_preferences.dart';

class NotificationService {
  static const String pendingActionsKey = 'pending_actions';
  static String? _lastOpenedAlarmKey;
  static DateTime? _lastOpenedAlarmAt;

  /// ✅ التهيئة
  static Future<void> init() async {
    await AwesomeNotifications().initialize(
      null,
      [
        for (final option in AlarmPreferences.alarmOptions)
          NotificationChannel(
            channelKey: option.channelKey,
            channelName: 'منبهات الدروس - ${option.label}',
            channelDescription: 'منبهات بداية ونهاية الدروس بصوت مخصص',
            soundSource: option.resourcePath,
            defaultColor: Colors.indigo,
            ledColor: Colors.white,
            importance: NotificationImportance.Max,
            playSound: true,
            enableVibration: true,
            criticalAlerts: true,
            defaultRingtoneType: DefaultRingtoneType.Alarm,
          ),
        for (final option in AlarmPreferences.notificationOptions)
          NotificationChannel(
            channelKey: option.channelKey,
            channelName: 'إشعارات الدروس - ${option.label}',
            channelDescription: 'تذكيرات وتنبيهات عادية بصوت مخصص',
            soundSource: option.resourcePath,
            defaultColor: Colors.teal,
            ledColor: Colors.white,
            importance: NotificationImportance.High,
            playSound: true,
            enableVibration: true,
            defaultRingtoneType: DefaultRingtoneType.Notification,
          ),
      ],
    );

    await AwesomeNotifications().requestPermissionToSendNotifications(
      permissions: [
        NotificationPermission.Alert,
        NotificationPermission.Sound,
        NotificationPermission.Vibration,
        NotificationPermission.FullScreenIntent,
        NotificationPermission.CriticalAlert,
      ],
    );

    AwesomeNotifications().setListeners(
      onActionReceivedMethod: NotificationService.onActionReceived,
      onNotificationCreatedMethod: NotificationService.onNotificationCreated,
      onNotificationDisplayedMethod:
          NotificationService.onNotificationDisplayed,
      onDismissActionReceivedMethod: NotificationService.onDismissed,
    );
  }

  // ================== Listeners ==================

  static Future<void> scheduleDailyMorningReminder() async {
    final prefs = await AlarmPreferences.load();
    final sound =
        AlarmPreferences.notificationOption(prefs.notificationSoundId);

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: 100, // ID ثابت لإشعار الصباح
        channelKey: sound.channelKey,
        title: 'صباح الخير ☀️',
        body: 'أكد مواعيدك اليوم لضمان تنبيهك في الوقت المناسب.',
        customSound: sound.resourcePath,
        notificationLayout: NotificationLayout.Default,
        category: NotificationCategory.Reminder,
        payload: {
          'action': 'open_today_page'
        }, //Payload لمعرفة الأكشن عند الضغط
      ),
      schedule: NotificationCalendar(
        hour: 9,
        minute: 0,
        second: 0,
        millisecond: 0,
        repeats: true, // يتكرر يومياً
        allowWhileIdle: true,
        preciseAlarm: true,
      ),
    );
  }

  @pragma("vm:entry-point")
  static Future<void> onActionReceived(ReceivedAction action) async {
    final payload = action.payload ?? {};
    final type = payload['type'] ?? '';
    final lessonId = payload['lessonId'];
    final student = payload['student'] ?? "طالب";
    final teacherCode = payload['teacherCode'];

    if (payload['action'] == 'open_today_page') {
      await AwesomeNotifications().cancel(101);
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/today_recurring',
        (route) => route.isFirst,
      );
      return;
    }

    // ✅ إذا تم الضغط على الإشعار نفسه (أو فتح Full Screen) بدون ضغط زر معيّن
    if (action.buttonKeyPressed.isEmpty && lessonId != null) {
      if (type == 'start') {
        _openLessonAlarm(
          type: 'start',
          lessonId: lessonId,
          student: student,
          teacherCode: teacherCode,
        );
        return;
      } else if (type == 'end') {
        _openLessonAlarm(
          type: 'end',
          lessonId: lessonId,
          student: student,
          teacherCode: teacherCode,
        );
        return;
      }
    }

    switch (action.buttonKeyPressed) {
      case 'SHOW_END_ALARM':
        {
          if (lessonId != null) {
            _openLessonAlarm(
              type: 'end',
              lessonId: lessonId,
              student: student,
              teacherCode: teacherCode,
            );
          }
          break;
        }

      case 'SHOW_START_ALARM':
        {
          if (lessonId != null) {
            _openLessonAlarm(
              type: 'start',
              lessonId: lessonId,
              student: student,
              teacherCode: teacherCode,
            );
          }
          break;
        }

      case 'SNOOZE_5_START':
        {
          if (lessonId != null && student.isNotEmpty) {
            final prefs = await AlarmPreferences.load();
            final when = DateTime.now().add(prefs.snoozeDuration);
            await NotificationService.cancelLessonNotification(lessonId);
            await NotificationService.scheduleLessonStartNotification(
              lessonId: lessonId,
              student: student,
              startTime: when,
              teacherCode: teacherCode,
            );
          }
          break;
        }

      case 'START_LESSON':
        debugPrint("✅ المستخدم بدأ الدرس $lessonId مع $student");
        break;

      case 'END_LESSON':
        debugPrint("✅ المستخدم أنهى الدرس $lessonId");
        navigatorKey.currentState?.pushNamed(
          '/teacher_end',
          arguments: {
            'lessonId': lessonId,
            'student': student,
            'teacherCode': teacherCode,
          },
        );
        break;

      case 'SNOOZE_5_END':
        if (lessonId != null && student.isNotEmpty) {
          final prefs = await AlarmPreferences.load();
          final when = DateTime.now().add(prefs.snoozeDuration);
          await NotificationService.cancelLessonNotification(lessonId);
          await NotificationService.scheduleLessonEndedNotification(
            lessonId: lessonId,
            student: student,
            endTime: when,
            teacherCode: teacherCode,
          );
        }
        break;
    }
  }

  @pragma("vm:entry-point")
  static Future<void> onNotificationCreated(
      ReceivedNotification notification) async {
    debugPrint("📢 Notification created: ${notification.id}");
  }

  @pragma("vm:entry-point")
  static Future<void> onNotificationDisplayed(
      ReceivedNotification notification) async {
    final payload = notification.payload ?? {};
    final type = payload['type'] ?? '';
    final lessonId = payload['lessonId'];
    final student = payload['student'] ?? "طالب";
    final teacherCode = payload['teacherCode'];

    debugPrint("👀 Notification displayed: ${notification.id}  TYPE=$type");

    if (notification.id == 100 || notification.id == 101) {
      await scheduleFollowUpReminder();
      return;
    }

    // ✅ إذا كان الإشعار FULL SCREEN مثل المنبّه
    if (lessonId != null) {
      if (type == 'start') {
        _openLessonAlarm(
          type: 'start',
          lessonId: lessonId,
          student: student,
          teacherCode: teacherCode,
        );
      } else if (type == 'end') {
        _openLessonAlarm(
          type: 'end',
          lessonId: lessonId,
          student: student,
          teacherCode: teacherCode,
        );
      }
    }
  }

  @pragma("vm:entry-point")
  static Future<void> onDismissed(ReceivedAction action) async {
    debugPrint("❌ Notification dismissed: ${action.id}");
  }

  static void _openLessonAlarm({
    required String type,
    required String lessonId,
    required String student,
    String? teacherCode,
  }) {
    if (navigatorKey.currentState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openLessonAlarm(
          type: type,
          lessonId: lessonId,
          student: student,
          teacherCode: teacherCode,
        );
      });
      return;
    }

    final key = '$type:$lessonId';
    final now = DateTime.now();
    if (_lastOpenedAlarmKey == key &&
        _lastOpenedAlarmAt != null &&
        now.difference(_lastOpenedAlarmAt!).inSeconds < 3) {
      return;
    }
    _lastOpenedAlarmKey = key;
    _lastOpenedAlarmAt = now;

    final route = MaterialPageRoute(
      builder: (_) => type == 'end'
          ? AlarmEndPage(
              lessonId: lessonId,
              student: student,
              teacherCode: teacherCode,
            )
          : AlarmPage(
              lessonId: lessonId,
              student: student,
              teacherCode: teacherCode,
            ),
    );
    navigatorKey.currentState!.push(route);
  }

  // ================== جدولة الإشعارات ==================

  static Future<void> scheduleReminderNotification({
    required String lessonId,
    required String student,
    required DateTime reminderTime,
    String? teacherCode,
  }) async {
    final prefs = await AlarmPreferences.load();
    final sound =
        AlarmPreferences.notificationOption(prefs.notificationSoundId);

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: _uniqueId(lessonId, 'reminder'),
        channelKey: sound.channelKey,
        title: '⏰ تذكير بالدرس',
        body: 'لديك درس مع $student بعد قليل',
        customSound: sound.resourcePath,
        notificationLayout: NotificationLayout.Default,
        payload: {
          'lessonId': lessonId,
          'student': student,
          'type': 'reminder',
          if (teacherCode != null) 'teacherCode': teacherCode,
        },
      ),
      schedule: NotificationCalendar.fromDate(
        date: reminderTime,
        allowWhileIdle: true,
        preciseAlarm: true,
      ),
    );
  }

  static Future<void> scheduleLessonStartNotification({
    required String lessonId,
    required String student,
    required DateTime startTime,
    String? teacherCode,
  }) async {
    final prefs = await AlarmPreferences.load();
    final sound = AlarmPreferences.alarmOption(prefs.alarmSoundId);

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: _uniqueId(lessonId, 'start'),
        channelKey: sound.channelKey,
        title: '📚 حان وقت الدرس!',
        body: 'ابدأ الدرس مع $student الآن 🚀',
        customSound: sound.resourcePath,
        payload: {
          'lessonId': lessonId,
          'student': student,
          'type': 'start',
          if (teacherCode != null) 'teacherCode': teacherCode,
        },
        wakeUpScreen: true,
        fullScreenIntent: true,
        criticalAlert: true,
        displayOnBackground: true,
        displayOnForeground: true,
        autoDismissible: false,
        locked: true,
        category: NotificationCategory.Alarm,
      ),
      actionButtons: [
        NotificationActionButton(
          key: 'SHOW_START_ALARM',
          label: 'عرض المنبّه',
          autoDismissible: true,
        ),
        NotificationActionButton(
          key: 'SNOOZE_5_START',
          label: 'ذكّرني بعد 5 دقائق',
          autoDismissible: true,
        ),
      ],
      schedule: NotificationCalendar.fromDate(
        date: startTime,
        allowWhileIdle: true,
        preciseAlarm: true,
      ),
    );
  }

  static Future<void> scheduleLessonEndReminderNotification({
    required String lessonId,
    required String student,
    required DateTime reminderTime,
    String? teacherCode,
  }) async {
    final prefs = await AlarmPreferences.load();
    final sound =
        AlarmPreferences.notificationOption(prefs.notificationSoundId);

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: _uniqueId(lessonId, 'end_reminder'),
        channelKey: sound.channelKey,
        title: '⏳ الدرس سينتهي قريباً',
        body:
            'باقي ${prefs.reminderLeadMinutes} دقائق على انتهاء الدرس مع $student',
        customSound: sound.resourcePath,
        notificationLayout: NotificationLayout.Default,
        payload: {
          'lessonId': lessonId,
          'student': student,
          'type': 'end_reminder',
          if (teacherCode != null) 'teacherCode': teacherCode,
        },
      ),
      schedule: NotificationCalendar.fromDate(
        date: reminderTime,
        allowWhileIdle: true,
        preciseAlarm: true,
      ),
    );
  }

  static Future<void> scheduleLessonEndedNotification({
    required String lessonId,
    required String student,
    required DateTime endTime,
    String? teacherCode,
  }) async {
    final prefs = await AlarmPreferences.load();
    final sound = AlarmPreferences.alarmOption(prefs.alarmSoundId);

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: _uniqueId(lessonId, 'end'),
        channelKey: sound.channelKey,
        title: '✅ انتهى الدرس',
        body: 'انتهى الدرس مع $student',
        customSound: sound.resourcePath,
        notificationLayout: NotificationLayout.Default,
        payload: {
          'lessonId': lessonId,
          'student': student,
          'type': 'end',
          if (teacherCode != null) 'teacherCode': teacherCode,
        },
        wakeUpScreen: true,
        fullScreenIntent: true,
        criticalAlert: true,
        displayOnBackground: true,
        displayOnForeground: true,
        autoDismissible: false,
        locked: true,
        category: NotificationCategory.Alarm,
      ),
      actionButtons: [
        NotificationActionButton(
          key: 'SHOW_END_ALARM',
          label: 'عرض منبّه النهاية',
          autoDismissible: true,
        ),
        NotificationActionButton(
            key: 'SNOOZE_5_END',
            label: 'ذكّرني بعد 5 دقائق',
            autoDismissible: true),
      ],
      schedule: NotificationCalendar.fromDate(
        date: endTime,
        allowWhileIdle: true,
        preciseAlarm: true,
      ),
    );
  }

  /// ✅ استدعاء هذه الدالة عند ظهور أي إشعار لجدولة التذكير التالي بعد ساعة
  static Future<void> scheduleFollowUpReminder() async {
    final prefs = await AlarmPreferences.load();
    final sound =
        AlarmPreferences.notificationOption(prefs.notificationSoundId);

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: 101,
        channelKey: sound.channelKey,
        title: 'تذكير: تأكيد المواعيد',
        body: 'لم تقم بتأكيد مواعيد اليوم بعد، اضغط هنا للقيام بذلك.',
        customSound: sound.resourcePath,
        category: NotificationCategory.Reminder,
        payload: {'action': 'open_today_page'},
      ),
      schedule: NotificationInterval(
        // ✅ الحل الصحيح للخطأ الذي ظهر لك
        interval: const Duration(hours: 1),
        repeats: false,
        preciseAlarm: true,
        allowWhileIdle: true,
      ),
    );
  }

  @pragma("vm:entry-point")
  static Future<void> onActionReceivedMethod(
      ReceivedAction receivedAction) async {
    if (receivedAction.payload?['action'] == 'open_today_page') {
      // إلغاء التذكيرات الحالية (الأساسي وتذكير الساعة)
      await AwesomeNotifications().cancel(100);
      await AwesomeNotifications().cancel(101);

      // ✅ استخدام navigatorKey الذي تم ربطه في MaterialApp
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/today_recurring',
        (route) => route.isFirst,
      );
    }
  }

  /// ✅ مستمع لظهور الإشعار (وليس ضغطه) لجدولة التذكير التالي
  @pragma("vm:entry-point")
  static Future<void> onNotificationDisplayedMethod(
      ReceivedNotification receivedNotification) async {
    // إذا كان الإشعار الظاهر هو إشعار الصباح أو التذكير
    if (receivedNotification.id == 100 || receivedNotification.id == 101) {
      // نجدول تذكير آخر بعد ساعة في حال لم يضغط المستخدم
      await scheduleFollowUpReminder();
    }
  }

  static Future<void> cancelLessonNotification(String lessonId) async {
    final int alarmId = _uniqueId(lessonId, 'start');
    await AwesomeNotifications().cancel(_uniqueId(lessonId, 'reminder'));
    await AwesomeNotifications().cancel(_uniqueId(lessonId, 'start'));
    await AwesomeNotifications().cancel(_uniqueId(lessonId, 'end_reminder'));
    await AwesomeNotifications().cancel(_uniqueId(lessonId, 'end'));

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('alarm_params_$alarmId');
  }

  static Future<List<Map<String, dynamic>>> getPendingActions() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(pendingActionsKey) ?? [];
    return list.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  static Future<void> clearPendingActions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(pendingActionsKey);
  }

  static int _uniqueId(String lessonId, String type) {
    return lessonId.hashCode ^ type.hashCode;
  }

  static Future<void> clearAllScheduled() async {
    try {
      await AwesomeNotifications().cancelAll();
    } catch (_) {}
    try {
      await clearPendingActions();
    } catch (_) {}
  }
}
