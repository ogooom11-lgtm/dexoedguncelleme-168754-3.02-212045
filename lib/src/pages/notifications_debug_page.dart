// lib/src/pages/notifications_debug_page.dart
import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/notification_service_wrapper.dart';

class NotificationsDebugPage extends StatefulWidget {
  const NotificationsDebugPage({super.key});

  @override
  State<NotificationsDebugPage> createState() => _NotificationsDebugPageState();
}

class _NotificationsDebugPageState extends State<NotificationsDebugPage> {
  final _studentController = TextEditingController(text: 'طالب تجريبي');
  final _lessonIdController = TextEditingController(text: 'L-123');
  String _selectedType = 'start'; // start | reminder | end_reminder | ended
  DateTime? _scheduledTime;
  bool _sending = false;

  List<NotificationModel> _scheduled = [];

  @override
  void initState() {
    super.initState();
    _loadScheduled();
  }

  Future<void> _loadScheduled() async {
    final scheduled = await AwesomeNotifications().listScheduledNotifications();
    setState(() => _scheduled = scheduled);
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledTime ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledTime ?? now.add(const Duration(minutes: 2))),
    );
    if (time == null) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => _scheduledTime = dt);
  }

  Future<void> _schedule() async {
    final lessonId = _lessonIdController.text.trim();
    final student = _studentController.text.trim();
    DateTime? when = _scheduledTime;

    if (lessonId.isEmpty || student.isEmpty) {
      _snack('أدخل lessonId واسم الطالب.');
      return;
    }
    if (when == null) {
      when = DateTime.now().add(const Duration(minutes: 2));
    }

    setState(() => _sending = true);
    try {
      switch (_selectedType) {
        case 'reminder':
        // تذكير قبل البداية (مثلاً -5 دقائق إن أردت). هنا سنستخدم الوقت كما هو.
          await NotificationServiceWrapper.scheduleReminderNotification(
            lessonId: lessonId,
            student: student,
            reminderTime: when,
          );
          break;

        case 'start':
          await NotificationServiceWrapper.scheduleLessonStartNotification(
            lessonId: lessonId,
            student: student,
            startTime: when,
          );
          break;

        case 'end_reminder':
          await NotificationServiceWrapper.scheduleLessonEndReminderNotification(
            lessonId: lessonId,
            student: student,
            reminderTime: when,
          );
          break;

        case 'ended':
          await NotificationServiceWrapper.scheduleLessonEndedNotification(
            lessonId: lessonId,
            student: student,
            endTime: when,
          );
          break;
      }

      _snack('✅ تم الجدولة بنجاح');
      await _loadScheduled();
    } catch (e) {
      _snack('❌ خطأ في الجدولة: $e');
    } finally {
      setState(() => _sending = false);
    }
  }

  Future<void> _cancelByLesson() async {
    final lessonId = _lessonIdController.text.trim();
    if (lessonId.isEmpty) {
      _snack('أدخل lessonId لإلغاء إشعاراته.');
      return;
    }
    setState(() => _sending = true);
    try {
      await NotificationServiceWrapper.cancelLessonNotification(lessonId);
      _snack('🗑️ تم إلغاء إشعارات الدرس: $lessonId');
      await _loadScheduled();
    } catch (e) {
      _snack('❌ فشل الإلغاء: $e');
    } finally {
      setState(() => _sending = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _studentController.dispose();
    _lessonIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dtLabel = _scheduledTime == null
        ? 'اختر وقت الإشعار'
        : '${_scheduledTime!.year}-${_scheduledTime!.month.toString().padLeft(2, '0')}-${_scheduledTime!.day.toString().padLeft(2, '0')} '
        '${_scheduledTime!.hour.toString().padLeft(2, '0')}:${_scheduledTime!.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications Debug'),
        actions: [
          IconButton(
            tooltip: 'تحديث القائمة',
            onPressed: _loadScheduled,
            icon: const Icon(Icons.refresh),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('إعدادات الاختبار', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _lessonIdController,
            decoration: const InputDecoration(
              labelText: 'Lesson ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _studentController,
            decoration: const InputDecoration(
              labelText: 'اسم الطالب',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedType,
            decoration: const InputDecoration(
              labelText: 'نوع الإشعار',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'start', child: Text('Start (ابدأ الدرس الآن)')),
              DropdownMenuItem(value: 'reminder', child: Text('Reminder قبل البداية')),
              DropdownMenuItem(value: 'end_reminder', child: Text('End Reminder قبل النهاية')),
              DropdownMenuItem(value: 'ended', child: Text('Ended (انتهاء الدرس)')),
            ],
            onChanged: (v) => setState(() => _selectedType = v ?? 'start'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickDateTime,
            icon: const Icon(Icons.access_time),
            label: Text(dtLabel),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _sending ? null : _schedule,
            icon: const Icon(Icons.schedule),
            label: Text(_sending ? 'جارٍ...' : 'جدولة الإشعار'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _sending ? null : _cancelByLesson,
            icon: const Icon(Icons.delete_forever),
            label: const Text('إلغاء إشعارات هذا الدرس'),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const Text('الإشعارات المجدولة حالياً', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_scheduled.isEmpty)
            const Text('لا توجد إشعارات مجدولة.')
          else
            ..._scheduled.map((n) {
              final id = n.content?.id;
              final title = n.content?.title ?? '';
              final body = n.content?.body ?? '';
              final schedule = n.schedule?.toString() ?? '';
              return Card(
                child: ListTile(
                  title: Text('#$id  $title'),
                  subtitle: Text('$body\n$schedule'),
                  isThreeLine: true,
                ),
              );
            }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
