// lib/src/services/timeline_repository.dart
import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'alarm_preferences.dart';
import 'notification_service_wrapper.dart';
import 'recurrence_utils.dart';
import 'timeline_models.dart';
import 'timeline_preferences.dart';

/// معلومات للتراجع عن آخر إجراء (إنهاء/إلغاء).
class TimelineUndo {
  final String lessonId;

  /// true إن كان الإجراء أنشأ عقدة جديدة في `schedule` (يُحذف عند التراجع).
  final bool created;

  /// القيم السابقة لاستعادتها عند التراجع (عند التعديل فقط).
  final Map<String, Object?> previous;

  /// السلسلة المتكررة وقيمة `lastConfirmedDate` السابقة إن تم تغييرها.
  final String? recurringId;
  final String? previousLastConfirmed;
  final bool touchedLastConfirmed;

  const TimelineUndo({
    required this.lessonId,
    required this.created,
    required this.previous,
    this.recurringId,
    this.previousLastConfirmed,
    this.touchedLastConfirmed = false,
  });
}

/// مستودع بيانات الجدول الزمني: يستمع لتغيّرات الطلاب والدروس والمواعيد المتكررة
/// ويُنتج قائمة الدروس لأي نطاق زمني، كما ينفّذ إجراءات الإنهاء/الإلغاء/التأكيد.
class TimelineRepository extends ChangeNotifier {
  TimelineRepository(this.teacherCode);

  final String teacherCode;

  Map<String, TimelineStudent> students = {};
  Map<String, Map<String, dynamic>> scheduleRaw = {};
  Map<String, RecurringSchedule> recurring = {};

  bool _studentsReady = false;
  bool _scheduleReady = false;
  bool _recurringReady = false;
  String? error;

  bool get isReady => _studentsReady && _scheduleReady && _recurringReady;

  final List<StreamSubscription<DatabaseEvent>> _subs = [];

  DatabaseReference get _root =>
      FirebaseDatabase.instance.ref('users/$teacherCode');

  void start() {
    if (teacherCode.isEmpty) {
      error = 'تعذر تحديد حساب المعلم';
      _studentsReady = _scheduleReady = _recurringReady = true;
      notifyListeners();
      return;
    }
    _subs.add(_root.child('students').onValue.listen((event) {
      _parseStudents(event.snapshot.value);
      _studentsReady = true;
      notifyListeners();
    }, onError: _onError));
    _subs.add(_root.child('schedule').onValue.listen((event) {
      _parseSchedule(event.snapshot.value);
      _scheduleReady = true;
      notifyListeners();
    }, onError: _onError));
    _subs.add(_root.child('recurringSchedules').onValue.listen((event) {
      _parseRecurring(event.snapshot.value);
      _recurringReady = true;
      notifyListeners();
    }, onError: _onError));
  }

  void _onError(Object e) {
    error = 'تعذر تحميل البيانات: $e';
    _studentsReady = _scheduleReady = _recurringReady = true;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (teacherCode.isEmpty) return;
    try {
      final results = await Future.wait([
        _root.child('students').get(),
        _root.child('schedule').get(),
        _root.child('recurringSchedules').get(),
      ]);
      _parseStudents(results[0].value);
      _parseSchedule(results[1].value);
      _parseRecurring(results[2].value);
      error = null;
    } catch (e) {
      error = 'تعذر تحديث البيانات: $e';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  // ===================== التحليل =====================

  void _parseStudents(Object? value) {
    final parsed = <String, TimelineStudent>{};
    if (value is Map) {
      final raw = Map<String, dynamic>.from(value);
      for (final e in raw.entries) {
        final code = e.key;
        String name;
        double rate = 0;
        if (e.value is Map) {
          final m = Map<String, dynamic>.from(e.value as Map);
          name = (m['name'] ?? 'طالب').toString();
          rate = double.tryParse('${m['hourlyRate'] ?? 0}') ?? 0;
        } else {
          name = e.value?.toString() ?? 'طالب';
        }
        parsed[code] = TimelineStudent(
          code: code,
          name: name,
          hourlyRate: rate,
          color: TimelineFormat.colorFor(code),
        );
      }
    }
    students = parsed;
  }

  void _parseSchedule(Object? value) {
    final parsed = <String, Map<String, dynamic>>{};
    if (value is Map) {
      final raw = Map<String, dynamic>.from(value);
      for (final e in raw.entries) {
        if (e.value is Map) {
          parsed[e.key] = Map<String, dynamic>.from(e.value as Map);
        }
      }
    }
    scheduleRaw = parsed;
  }

  void _parseRecurring(Object? value) {
    final parsed = <String, RecurringSchedule>{};
    if (value is Map) {
      final raw = Map<String, dynamic>.from(value);
      for (final e in raw.entries) {
        if (e.value is! Map) continue;
        try {
          parsed[e.key] = RecurringSchedule.fromMap(
            e.key,
            Map<String, dynamic>.from(e.value as Map),
          );
        } catch (_) {
          // تجاهل السجلات التالفة
        }
      }
    }
    recurring = parsed;
  }

  TimelineStudent studentOf(String code, {String? fallbackName}) {
    return students[code] ??
        TimelineStudent(
          code: code,
          name: fallbackName ?? 'طالب',
          hourlyRate: 0,
          color: TimelineFormat.colorFor(code),
        );
  }

  // ===================== بناء الدروس =====================

  /// كل الدروس في النطاق [start, endExclusive) مع تطبيق إعدادات الإظهار.
  List<TimelineLesson> lessonsBetween(
    DateTime start,
    DateTime endExclusive,
    TimelinePreferencesData prefs, {
    Set<String>? studentFilter,
    Set<TimelineStatus>? statusFilter,
  }) {
    final now = DateTime.now();
    final today = TimelineFormat.today();
    final lessons = <TimelineLesson>[];
    final takenRecurring = <String>{}; // recurringId|ymd
    final takenSignature = <String>{}; // student|yyyy-MM-ddTHH:mm

    for (final entry in scheduleRaw.entries) {
      final m = entry.value;
      final rawStatus = (m['status'] ?? '').toString();
      if (rawStatus == 'temporary') continue;

      final s = DateTime.tryParse(m['startTime']?.toString() ?? '');
      if (s == null) continue;
      DateTime? e = DateTime.tryParse(m['endTime']?.toString() ?? '');
      final durationSec = int.tryParse('${m['duration'] ?? ''}') ?? 0;
      if (e == null || !e.isAfter(s)) {
        e = s.add(Duration(seconds: durationSec > 0 ? durationSec : 3600));
      }
      if (s.isBefore(start) || !s.isBefore(endExclusive)) continue;

      final studentId = (m['student'] ?? '').toString();
      final student =
          studentOf(studentId, fallbackName: m['studentName']?.toString());

      // منع ازدواج التكرار
      final recurringId = m['recurringId']?.toString();
      if (recurringId != null && recurringId.isNotEmpty) {
        takenRecurring.add('$recurringId|${TimelineFormat.ymd(s)}');
      }
      takenSignature.add(_signature(studentId, s));

      var status = TimelineStatusX.fromRaw(rawStatus);
      if ((status == TimelineStatus.scheduled ||
              status == TimelineStatus.pending) &&
          e.isBefore(now)) {
        status = TimelineStatus.missed;
      }

      lessons.add(TimelineLesson(
        id: entry.key,
        recurringId: recurringId,
        isVirtual: false,
        recurring: recurringId != null ? recurring[recurringId] : null,
        studentId: studentId,
        studentName: student.name,
        hourlyRate: student.hourlyRate,
        start: s,
        end: e,
        status: status,
        rawStatus: rawStatus,
        amount: double.tryParse('${m['amount'] ?? 0}') ?? 0,
        note: (m['note'] ?? '').toString(),
        cancelReason: (m['cancelReason'] ?? '').toString(),
        raw: m,
      ));
    }

    // التكرارات الافتراضية
    if (prefs.showRecurring && recurring.isNotEmpty) {
      var day = TimelineFormat.dateOnly(start);
      final last = TimelineFormat.dateOnly(endExclusive);
      while (day.isBefore(last)) {
        final isPast = day.isBefore(today);
        if (!isPast || prefs.showPastRecurring) {
          final ymd = TimelineFormat.ymd(day);
          for (final r in recurring.values) {
            if (!RecurrenceUtils.occursOn(r, day)) continue;
            if (takenRecurring.contains('${r.id}|$ymd')) continue;
            final s = RecurrenceUtils.buildStartForDay(r, day);
            if (takenSignature.contains(_signature(r.student, s))) continue;
            if (r.lastConfirmedDate == ymd) continue;
            final e = RecurrenceUtils.buildEndForDay(r, day);
            final student = studentOf(r.student);
            lessons.add(TimelineLesson(
              id: r.id,
              recurringId: r.id,
              isVirtual: true,
              recurring: r,
              studentId: r.student,
              studentName: student.name,
              hourlyRate: student.hourlyRate,
              start: s,
              end: e,
              status: TimelineStatus.recurring,
              rawStatus: 'recurring',
              amount: 0,
              note: '',
              cancelReason: '',
              raw: const {},
            ));
          }
        }
        day = day.add(const Duration(days: 1));
      }
    }

    // تطبيق قواعد الإظهار
    final filtered = lessons.where((l) {
      if (studentFilter != null &&
          studentFilter.isNotEmpty &&
          !studentFilter.contains(l.studentId)) {
        return false;
      }
      if (statusFilter != null &&
          statusFilter.isNotEmpty &&
          !statusFilter.contains(l.status)) {
        return false;
      }
      switch (l.status) {
        case TimelineStatus.canceled:
          return prefs.showCanceled;
        case TimelineStatus.missed:
          return prefs.showMissed;
        default:
          return true;
      }
    }).toList();

    filtered.sort((a, b) {
      final c = a.start.compareTo(b.start);
      if (c != 0) return c;
      return a.studentName.compareTo(b.studentName);
    });
    return filtered;
  }

  List<TimelineLesson> lessonsOn(
    DateTime day,
    TimelinePreferencesData prefs, {
    Set<String>? studentFilter,
    Set<TimelineStatus>? statusFilter,
  }) {
    final d = TimelineFormat.dateOnly(day);
    return lessonsBetween(
      d,
      d.add(const Duration(days: 1)),
      prefs,
      studentFilter: studentFilter,
      statusFilter: statusFilter,
    );
  }

  static String _signature(String studentId, DateTime s) =>
      '$studentId|${s.year}-${s.month}-${s.day}T${s.hour}:${s.minute}';

  // ===================== الإجراءات =====================

  /// تسجيل الدرس كمنتهي (نفس منطق صفحة «إضافة درس منتهي»).
  Future<TimelineUndo> markEnded(
    TimelineLesson lesson, {
    required DateTime start,
    required DateTime end,
    required double amount,
    String note = '',
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    final ymd = TimelineFormat.ymd(start);
    final durationSec = end.difference(start).inSeconds;

    if (lesson.isVirtual) {
      final ref = _root.child('schedule').push();
      await ref.set({
        'teacher': teacherCode,
        'student': lesson.studentId,
        'studentName': lesson.studentName,
        'date': ymd,
        'startTime': start.toIso8601String(),
        'endTime': end.toIso8601String(),
        'duration': durationSec,
        'amount': amount,
        'note': note,
        'status': 'ended',
        'endedBy': 'teacher',
        'manual': true,
        'fromTimeline': true,
        'recurringId': lesson.recurringId,
        'occurrenceDate': ymd,
        'createdAt': nowIso,
        'endedAt': nowIso,
      });
      final touched = await _bumpLastConfirmed(lesson.recurringId, ymd);
      return TimelineUndo(
        lessonId: ref.key!,
        created: true,
        previous: const {},
        recurringId: lesson.recurringId,
        previousLastConfirmed: touched.$2,
        touchedLastConfirmed: touched.$1,
      );
    }

    final ref = _root.child('schedule/${lesson.id}');
    final previous = <String, Object?>{
      'status': lesson.raw['status'],
      'startTime': lesson.raw['startTime'],
      'endTime': lesson.raw['endTime'],
      'duration': lesson.raw['duration'],
      'amount': lesson.raw['amount'],
      'note': lesson.raw['note'],
      'endedBy': lesson.raw['endedBy'],
      'endedAt': lesson.raw['endedAt'],
      'fromTimeline': lesson.raw['fromTimeline'],
    };
    await ref.update({
      'status': 'ended',
      'startTime': start.toIso8601String(),
      'endTime': end.toIso8601String(),
      'date': ymd,
      'duration': durationSec,
      'amount': amount,
      'note': note,
      'endedBy': 'teacher',
      'endedAt': nowIso,
      'fromTimeline': true,
    });
    await _safeCancelNotifications(lesson.id);
    return TimelineUndo(
        lessonId: lesson.id, created: false, previous: previous);
  }

  /// إلغاء الدرس (نفس منطق صفحة إلغاء الدرس).
  Future<TimelineUndo> markCanceled(
    TimelineLesson lesson, {
    String reason = '',
  }) async {
    final nowIso = DateTime.now().toIso8601String();
    final ymd = TimelineFormat.ymd(lesson.start);

    if (lesson.isVirtual) {
      final ref = _root.child('schedule').push();
      await ref.set({
        'teacher': teacherCode,
        'student': lesson.studentId,
        'studentName': lesson.studentName,
        'date': ymd,
        'startTime': lesson.start.toIso8601String(),
        'endTime': lesson.end.toIso8601String(),
        'duration': lesson.duration.inSeconds,
        'amount': 0,
        'status': 'canceled',
        if (reason.isNotEmpty) 'cancelReason': reason,
        'canceledBy': 'teacher',
        'fromTimeline': true,
        'recurringId': lesson.recurringId,
        'occurrenceDate': ymd,
        'createdAt': nowIso,
        'canceledAt': nowIso,
      });
      final touched = await _bumpLastConfirmed(lesson.recurringId, ymd);
      return TimelineUndo(
        lessonId: ref.key!,
        created: true,
        previous: const {},
        recurringId: lesson.recurringId,
        previousLastConfirmed: touched.$2,
        touchedLastConfirmed: touched.$1,
      );
    }

    final ref = _root.child('schedule/${lesson.id}');
    final previous = <String, Object?>{
      'status': lesson.raw['status'],
      'amount': lesson.raw['amount'],
      'cancelReason': lesson.raw['cancelReason'],
      'canceledBy': lesson.raw['canceledBy'],
      'canceledAt': lesson.raw['canceledAt'],
      'fromTimeline': lesson.raw['fromTimeline'],
    };
    await ref.update({
      'status': 'canceled',
      'amount': 0,
      'cancelReason': reason.isNotEmpty ? reason : null,
      'canceledBy': 'teacher',
      'canceledAt': nowIso,
      'fromTimeline': true,
    });
    await _safeCancelNotifications(lesson.id);
    return TimelineUndo(
        lessonId: lesson.id, created: false, previous: previous);
  }

  /// التراجع عن إجراء سابق.
  Future<void> undo(TimelineUndo u) async {
    if (u.created) {
      await _root.child('schedule/${u.lessonId}').remove();
    } else {
      await _root.child('schedule/${u.lessonId}').update(u.previous);
    }
    if (u.touchedLastConfirmed && u.recurringId != null) {
      await _root.child('recurringSchedules/${u.recurringId}').update({
        'lastConfirmedDate': u.previousLastConfirmed,
      });
    }
  }

  /// إعادة درس منتهٍ/ملغي إلى «مجدول» (لدروس اليوم والمستقبل).
  Future<void> revertToScheduled(TimelineLesson lesson) async {
    if (lesson.isVirtual) return;
    await _root.child('schedule/${lesson.id}').update({
      'status': 'scheduled',
      'cancelReason': null,
      'canceledAt': null,
      'endedAt': null,
      'endedBy': null,
      'endTime': lesson.end.toIso8601String(),
      'duration': lesson.duration.inSeconds,
    });
  }

  /// تحويل تكرار افتراضي إلى درس مجدول مؤكد (مع جدولة التنبيهات).
  Future<String> confirmRecurring(TimelineLesson lesson) async {
    final r = lesson.recurring;
    final ref = _root.child('schedule').push();
    final lessonId = ref.key!;
    final ymd = TimelineFormat.ymd(lesson.start);
    await ref.set({
      'teacher': teacherCode,
      'student': lesson.studentId,
      'date': ymd,
      'startTime': lesson.start.toIso8601String(),
      'endTime': lesson.end.toIso8601String(),
      'duration': r?.duration ?? lesson.duration.inSeconds,
      'createdAt': DateTime.now().toIso8601String(),
      'status': 'scheduled',
      'recurringId': lesson.recurringId,
      'occurrenceDate': ymd,
      'fromTimeline': true,
    });
    await _bumpLastConfirmed(lesson.recurringId, ymd);
    await _scheduleStartNotifications(
      lessonId: lessonId,
      studentName: lesson.studentName,
      start: lesson.start,
    );
    return lessonId;
  }

  /// بدء الدرس الآن (نفس منطق الصفحة الرئيسية) — يعيد معرّف الدرس.
  Future<String> startNow(TimelineLesson lesson) async {
    String lessonId = lesson.id;
    if (lesson.isVirtual) {
      lessonId = await confirmRecurring(lesson);
    }
    final ref = _root.child('schedule/$lessonId');
    final now = DateTime.now();
    await ref.update({
      'status': 'started',
      'startTime': now.toIso8601String(),
    });
    final durationSec = lesson.duration.inSeconds;
    if (durationSec > 0) {
      final endTime = now.add(Duration(seconds: durationSec));
      await _safeCancelNotifications(lessonId);
      try {
        final prefs = await AlarmPreferences.load();
        final reminderEnd = endTime.subtract(prefs.reminderLeadDuration);
        if (reminderEnd.isAfter(DateTime.now())) {
          await NotificationServiceWrapper.scheduleLessonEndReminderNotification(
            lessonId: lessonId,
            student: lesson.studentName,
            reminderTime: reminderEnd,
            teacherCode: teacherCode,
          );
        }
        if (endTime.isAfter(DateTime.now())) {
          await NotificationServiceWrapper.scheduleLessonEndedNotification(
            lessonId: lessonId,
            student: lesson.studentName,
            endTime: endTime,
            teacherCode: teacherCode,
          );
        }
      } catch (_) {}
    }
    return lessonId;
  }

  Future<void> deleteLesson(TimelineLesson lesson) async {
    if (lesson.isVirtual) return;
    await _root.child('schedule/${lesson.id}').remove();
    await _safeCancelNotifications(lesson.id);
  }

  /// تحديث ملاحظة الدرس فقط.
  Future<void> updateNote(TimelineLesson lesson, String note) async {
    if (lesson.isVirtual) return;
    await _root.child('schedule/${lesson.id}').update({'note': note});
  }

  // ===================== مساعدات =====================

  Future<(bool, String?)> _bumpLastConfirmed(
      String? recurringId, String ymd) async {
    if (recurringId == null || recurringId.isEmpty) return (false, null);
    final r = recurring[recurringId];
    final prev = r?.lastConfirmedDate;
    if (prev != null && prev.compareTo(ymd) > 0) return (false, prev);
    await _root.child('recurringSchedules/$recurringId').update({
      'lastConfirmedDate': ymd,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    return (true, prev);
  }

  Future<void> _scheduleStartNotifications({
    required String lessonId,
    required String studentName,
    required DateTime start,
  }) async {
    try {
      final prefs = await AlarmPreferences.load();
      final reminderTime = start.subtract(prefs.reminderLeadDuration);
      if (reminderTime.isAfter(DateTime.now())) {
        await NotificationServiceWrapper.scheduleReminderNotification(
          lessonId: lessonId,
          student: studentName,
          reminderTime: reminderTime,
          teacherCode: teacherCode,
        );
      }
      if (start.isAfter(DateTime.now())) {
        await NotificationServiceWrapper.scheduleLessonStartNotification(
          lessonId: lessonId,
          student: studentName,
          startTime: start,
          teacherCode: teacherCode,
        );
      }
    } catch (_) {}
  }

  Future<void> _safeCancelNotifications(String lessonId) async {
    try {
      await NotificationServiceWrapper.cancelLessonNotification(lessonId);
    } catch (_) {}
  }
}
