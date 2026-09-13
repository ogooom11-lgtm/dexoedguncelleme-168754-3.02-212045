// lib/src/pages/teacher_weekly_schedule_page.dart
//
// ⚠️ تم استبدال «الجدول الأسبوعي» القديم بـ «الجدول الزمني» الجديد
// (`teacher_timeline_page.dart`) الذي يدعم العرض اليومي والأسبوعي والشهري.
// يُبقي هذا الملف على الاسم القديم للتوافق مع أي استدعاءات سابقة.
import 'package:flutter/material.dart';

import '../services/timeline_preferences.dart';
import 'teacher_timeline_page.dart';

class TeacherWeeklySchedulePage extends StatelessWidget {
  const TeacherWeeklySchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const TeacherTimelinePage(initialView: TimelineView.week);
  }
}
