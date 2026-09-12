// lib/src/services/notification_orchestrator.dart
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'alarm_preferences.dart';
import 'notification_service.dart';

class NotificationOrchestrator {
  /// ⚠️ لا تُستدعى أثناء تسجيل الدخول (حتى يبقى الدخول سريعاً).
  /// إعادة تحليل الدروس وجدولة تنبيهاتها — تُستدعى يدوياً فقط.
  static Future<void> rescheduleAll({required String teacherCode}) async {
    try {
      // أمان إضافي
      if (teacherCode.isEmpty) return;

      // امسح أي إشعارات قديمة متبقية قبل إعادة الجدولة
      await NotificationService.clearAllScheduled();
      await NotificationService.scheduleDailyMorningReminder();

      final ref = FirebaseDatabase.instance.ref('users/$teacherCode/schedule');
      final snap = await ref.get();
      if (!snap.exists) {
        final prefsStore = await SharedPreferences.getInstance();
        await prefsStore.setString(
            'notifications_bootstrap_last_code', teacherCode);
        return;
      }

      final now = DateTime.now();
      final data = Map<String, dynamic>.from(snap.value as Map);
      final alarmPrefs = await AlarmPreferences.load();

      for (final entry in data.entries) {
        final lessonId = entry.key.toString();
        final v = Map<String, dynamic>.from(entry.value as Map? ?? {});
        final status =
            (v['status'] ?? '').toString(); // planned|started|ended|canceled
        final studentName =
            (v['studentName'] ?? v['student'] ?? 'طالب').toString();

        final startStr = v['startTime']?.toString();
        final startTime = startStr == null ? null : DateTime.tryParse(startStr);

        // المدة بالثواني (كما هو مستخدم في المشروع)
        final durationSec = int.tryParse('${v['duration'] ?? 0}') ?? 0;
        final endTime = (startTime != null && durationSec > 0)
            ? startTime.add(Duration(seconds: durationSec))
            : null;

        // نظافة: ألغِ كل إشعارات هذا الدرس أولاً
        await NotificationService.cancelLessonNotification(lessonId);

        final isSchedulable =
            status == 'scheduled' || status == 'pending' || status.isEmpty;

        // 1) دروس قادمة
        if (isSchedulable && startTime != null && startTime.isAfter(now)) {
          // تذكير قبل 5 دقائق (إن بقي وقت كافٍ)
          final reminder = startTime.subtract(alarmPrefs.reminderLeadDuration);
          if (reminder.isAfter(now)) {
            await NotificationService.scheduleReminderNotification(
              lessonId: lessonId,
              student: studentName,
              reminderTime: reminder,
              teacherCode: teacherCode,
            );
          }
          // إشعار بداية الدرس (FullScreen/Alarm)
          await NotificationService.scheduleLessonStartNotification(
            lessonId: lessonId,
            student: studentName,
            startTime: startTime,
            teacherCode: teacherCode,
          );
          continue;
        }

        // 2) دروس جارية: إمّا مبدوءة status=started أو وقتها الحالي بين start..end
        final inProgress = (status == 'started') ||
            (startTime != null &&
                endTime != null &&
                now.isAfter(startTime) &&
                now.isBefore(endTime));

        if (inProgress && endTime != null && endTime.isAfter(now)) {
          // تذكير النهاية قبل 5 دقائق إن أمكن
          final endReminder = endTime.subtract(alarmPrefs.reminderLeadDuration);
          if (endReminder.isAfter(now)) {
            await NotificationService.scheduleLessonEndReminderNotification(
              lessonId: lessonId,
              student: studentName,
              reminderTime: endReminder,
              teacherCode: teacherCode,
            );
          }
          // إشعار نهاية الدرس (FullScreen/Alarm)
          await NotificationService.scheduleLessonEndedNotification(
            lessonId: lessonId,
            student: studentName,
            endTime: endTime,
            teacherCode: teacherCode,
          );
          continue;
        }

        // 3) دروس منتهية/ملغاة أو لا تصلح للجدولة: فقط تأكد من الإلغاء
        await NotificationService.cancelLessonNotification(lessonId);
      }

      // علامة بسيطة تفيد أننا أعددنا الإشعارات بعد آخر دخول
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('notifications_bootstrap_last_code', teacherCode);
    } catch (e) {
      debugPrint('❌ NotificationOrchestrator.rescheduleAll: $e');
    }
  }

  /// يستدعى عند تسجيل الخروج لمسح كل الإشعارات + المعلّقات
  static Future<void> onLogoutClearAll() async {
    await NotificationService.clearAllScheduled();
  }
}
