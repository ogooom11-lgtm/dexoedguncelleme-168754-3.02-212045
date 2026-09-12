// lib/src/pages/today_recurring_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/alarm_preferences.dart';
import '../services/recurrence_utils.dart';
import '../services/notification_service_wrapper.dart';

class TodayRecurringPage extends StatefulWidget {
  const TodayRecurringPage({super.key});
  @override
  State<TodayRecurringPage> createState() => _TodayRecurringPageState();
}

class _TodayRecurringPageState extends State<TodayRecurringPage> {
  bool _loading = true;
  String _error = '';
  final _items = <RecurringSchedule>[];
  final _studentNames = <String, String>{};

  late final String todayYmd;
  final _dfYmd = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    todayYmd = _dfYmd.format(DateTime.now());
    _loadToday();
  }

  Future<void> _loadToday() async {
    final auth = context.read<AuthProvider>();
    final code = auth.currentUser?.code ?? '';
    if (code.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'لم يتم العثور على المعلّم';
      });
      return;
    }

    try {
      // جلب أسماء الطلاب للعرض
      final stSnap =
          await FirebaseDatabase.instance.ref("users/$code/students").get();
      if (stSnap.exists && stSnap.value is Map) {
        final raw = Map<String, dynamic>.from(stSnap.value as Map);
        raw.forEach((k, v) {
          if (v is Map && v['name'] != null) {
            _studentNames[k] = v['name'].toString();
          } else {
            _studentNames[k] = v?.toString() ?? 'طالب';
          }
        });
      }

      // قراءة المواعيد المتكررة لليوم فقط
      final ref =
          FirebaseDatabase.instance.ref("users/$code/recurringSchedules");
      final snap = await ref.get();
      _items.clear();

      if (snap.exists && snap.value is Map) {
        final map = Map<String, dynamic>.from(snap.value as Map);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        for (final e in map.entries) {
          final r = RecurringSchedule.fromMap(
              e.key, Map<String, dynamic>.from(e.value));
          if (RecurrenceUtils.occursOn(r, today)) {
            // تفادي الازدواج: إن كان مؤكداً اليوم فلا نعرضه
            if (r.lastConfirmedDate == todayYmd) continue;
            _items.add(r);
          }
        }
      }

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'تعذر التحميل: $e';
      });
    }
  }

  Future<void> _confirm(RecurringSchedule r) async {
    final auth = context.read<AuthProvider>();
    final code = auth.currentUser?.code ?? '';
    if (code.isEmpty) return;

    try {
      setState(() => _loading = true);

      final start = RecurrenceUtils.buildStartForDay(r, DateTime.now());
      final end = RecurrenceUtils.buildEndForDay(r, DateTime.now());
      final scheduleRef =
          FirebaseDatabase.instance.ref("users/$code/schedule").push();
      final lessonId = scheduleRef.key!;

      await scheduleRef.set({
        "teacher": r.teacher,
        "student": r.student,
        "date": todayYmd,
        "startTime": start.toIso8601String(),
        "endTime": end.toIso8601String(),
        "duration": r.duration,
        "createdAt": DateTime.now().toIso8601String(),
        "status": "scheduled",
      });

      // تحديث آخر تأكيد في سجل التكرار
      final recurRef = FirebaseDatabase.instance
          .ref("users/$code/recurringSchedules/${r.id}");
      await recurRef.update({
        "lastConfirmedDate": todayYmd,
        "updatedAt": DateTime.now().toIso8601String(),
      });

      // جدولة الإشعارات (تذكير قبل 5 دقائق + بدء الدرس)
      try {
        final studentName = _studentNames[r.student] ?? 'طالب';
        final prefs = await AlarmPreferences.load();
        final reminderTime = start.subtract(prefs.reminderLeadDuration);
        if (reminderTime.isAfter(DateTime.now())) {
          await NotificationServiceWrapper.scheduleReminderNotification(
            lessonId: lessonId,
            student: studentName,
            reminderTime: reminderTime,
            teacherCode: code,
          );
        }
        if (start.isAfter(DateTime.now())) {
          await NotificationServiceWrapper.scheduleLessonStartNotification(
            lessonId: lessonId,
            student: studentName,
            startTime: start,
            teacherCode: code,
          );
        }
      } catch (_) {
        // تجاهل فشل الإشعارات والاستمرار
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تأكيد الموعد وإضافته لليوم ✅')),
      );

      // إزالة العنصر من القائمة الحالية
      setState(() {
        _items.removeWhere((x) => x.id == r.id);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء التأكيد: $e')),
      );
    }
  }

  String _timeRangeLabel(RecurringSchedule r) {
    final dfTime = DateFormat('HH:mm');
    final start = RecurrenceUtils.buildStartForDay(r, DateTime.now());
    final end = RecurrenceUtils.buildEndForDay(r, DateTime.now());
    return 'اليوم • من ${dfTime.format(start)} إلى ${dfTime.format(end)}';
  }

  // شارة صغيرة (badge)
  Widget _badge(IconData icon, String text, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // صورة رمزية من اختصار الاسم
  Widget _avatar(String name) {
    final initials = (name.isNotEmpty)
        ? name
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((w) => w.characters.first.toUpperCase())
            .join()
        : 'ط';
    return CircleAvatar(
      radius: 24,
      child: Text(
        initials,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  // بطاقة عنصر أنيقة
  Widget _itemCard(RecurringSchedule r, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = _studentNames[r.student] ?? 'طالب';

    final start = RecurrenceUtils.buildStartForDay(r, DateTime.now());
    final remaining = start.difference(DateTime.now());
    final remainingLabel = remaining.isNegative
        ? 'بدأ منذ ${remaining.abs().inMinutes} دقيقة'
        : 'يبدأ بعد ${remaining.inMinutes} دقيقة';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surfaceContainerHighest.withValues(alpha: 0.60),
            scheme.surfaceContainerHigh.withValues(alpha: 0.30),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // الاسم + عدّاد نصي
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _badge(
                            Icons.timelapse_rounded, remainingLabel, context),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // المدى الزمني اليوم
                    Row(
                      children: [
                        const Icon(Icons.schedule, size: 18),
                        const SizedBox(width: 6),
                        Text(_timeRangeLabel(r)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // زر التأكيد
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ElevatedButton.icon(
                        onPressed: () => _confirm(r),
                        icon: const Icon(Icons.check_circle_rounded),
                        label: const Text('تأكيد'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مواعيد اليوم المتكررة'),
      ),
      body: _loading
          ? const _LoadingState()
          : _error.isNotEmpty
              ? _ErrorState(message: _error, onRetry: _loadToday)
              : _items.isEmpty
                  ? const _EmptyState()
                  : RefreshIndicator(
                      onRefresh: _loadToday,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _itemCard(_items[i], context),
                      ),
                    ),
    );
  }
}

/// حالات واجهة (تحميل/خطأ/فارغ)

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: scheme.primary),
          const SizedBox(height: 12),
          const Text('جاري التحميل...'),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: scheme.primary),
            const SizedBox(height: 12),
            const Text(
              'لا يوجد اليوم ما يحتاج تأكيد 👍',
              style: TextStyle(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'ستظهر هنا المواعيد المتكررة الخاصة بهذا اليوم.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
