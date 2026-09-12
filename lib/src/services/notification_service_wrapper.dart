import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'notification_service.dart';

class NotificationServiceWrapper {
  static bool get _canNotify => !kIsWeb && Platform.isAndroid;

  static Future<void> init() async {
    if (_canNotify) {
      await NotificationService.init();
    }
  }

  static Future<void> scheduleReminderNotification({
    required String lessonId,
    required String student,
    required DateTime reminderTime,
    String? teacherCode,
  }) async {
    if (_canNotify) {
      await NotificationService.scheduleReminderNotification(
        lessonId: lessonId,
        student: student,
        reminderTime: reminderTime,
        teacherCode: teacherCode,
      );
    }
  }

  static Future<void> scheduleLessonStartNotification({
    required String lessonId,
    required String student,
    required DateTime startTime,
    String? teacherCode,
  }) async {
    if (_canNotify) {
      await NotificationService.scheduleLessonStartNotification(
        lessonId: lessonId,
        student: student,
        startTime: startTime,
        teacherCode: teacherCode,
      );
    }
  }

  static Future<void> scheduleLessonEndReminderNotification({
    required String lessonId,
    required String student,
    required DateTime reminderTime,
    String? teacherCode,
  }) async {
    if (_canNotify) {
      await NotificationService.scheduleLessonEndReminderNotification(
        lessonId: lessonId,
        student: student,
        reminderTime: reminderTime,
        teacherCode: teacherCode,
      );
    }
  }

  static Future<void> scheduleLessonEndedNotification({
    required String lessonId,
    required String student,
    required DateTime endTime,
    String? teacherCode,
  }) async {
    if (_canNotify) {
      await NotificationService.scheduleLessonEndedNotification(
        lessonId: lessonId,
        student: student,
        endTime: endTime,
        teacherCode: teacherCode,
      );
    }
  }

  static Future<void> cancelLessonNotification(String lessonId) async {
    if (_canNotify) {
      await NotificationService.cancelLessonNotification(lessonId);
    }
  }
}
