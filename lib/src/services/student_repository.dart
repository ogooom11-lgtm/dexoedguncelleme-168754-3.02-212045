// lib/src/services/student_repository.dart
import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'recurrence_utils.dart';
import 'timeline_models.dart';

/// درس واحد للطالب.
class StudentLesson {
  final String id;
  final DateTime start;
  final DateTime end;
  final TimelineStatus status;
  final String rawStatus;
  final double amount;
  final String note;
  final String cancelReason;
  final bool isPaid;
  final Map<String, dynamic> raw;

  const StudentLesson({
    required this.id,
    required this.start,
    required this.end,
    required this.status,
    required this.rawStatus,
    required this.amount,
    required this.note,
    required this.cancelReason,
    required this.isPaid,
    required this.raw,
  });

  int get minutes => end.difference(start).inMinutes;
  DateTime get day => DateTime(start.year, start.month, start.day);
  bool get isEnded => status == TimelineStatus.ended;
  bool get isUpcoming =>
      status == TimelineStatus.scheduled && start.isAfter(DateTime.now());
  bool get isRunning => status == TimelineStatus.started;
  bool get isPending => status == TimelineStatus.pending;

  StudentLesson copyWith({bool? isPaid}) => StudentLesson(
        id: id,
        start: start,
        end: end,
        status: status,
        rawStatus: rawStatus,
        amount: amount,
        note: note,
        cancelReason: cancelReason,
        isPaid: isPaid ?? this.isPaid,
        raw: raw,
      );
}

/// دفعة واحدة.
class StudentPayment {
  final String id;
  final double amount;
  final DateTime? date;
  final String payer; // student | teacher
  final String method; // cash | bank | ...
  final String note;

  const StudentPayment({
    required this.id,
    required this.amount,
    required this.date,
    required this.payer,
    required this.method,
    required this.note,
  });

  bool get fromStudent => payer != 'teacher';

  /// الأثر على الحساب: دفع الطالب يُنقص المستحق، دفع المعلم (إرجاع) يزيده.
  double get signedAmount => fromStudent ? amount : -amount;

  String get methodLabel {
    switch (method) {
      case 'bank':
        return 'تحويل بنكي';
      case 'cash':
        return 'نقداً';
      case '':
        return 'غير محدد';
      default:
        return method;
    }
  }
}

/// ملخّص مالي.
class StudentFinance {
  final double lessonsTotal;
  final double paid;
  final double returned;

  const StudentFinance({
    required this.lessonsTotal,
    required this.paid,
    required this.returned,
  });

  /// موجب = على الطالب، سالب = رصيد زائد للطالب.
  double get balance => lessonsTotal - paid + returned;
  double get netPaid => paid - returned;
  double get owed => balance > 0 ? balance : 0;
  double get credit => balance < 0 ? -balance : 0;

  /// نسبة التغطية (0..1) من إجمالي الدروس.
  double get coverage {
    if (lessonsTotal <= 0) return netPaid > 0 ? 1 : 0;
    return (netPaid / lessonsTotal).clamp(0, 1).toDouble();
  }

  static const empty = StudentFinance(lessonsTotal: 0, paid: 0, returned: 0);
}

/// عنصر نشاط موحّد (درس أو دفعة) للعرض في «آخر النشاطات».
class StudentActivity {
  final DateTime date;
  final StudentLesson? lesson;
  final StudentPayment? payment;
  const StudentActivity._(this.date, {this.lesson, this.payment});
  factory StudentActivity.lesson(StudentLesson l) =>
      StudentActivity._(l.isEnded ? l.end : l.start, lesson: l);
  factory StudentActivity.payment(StudentPayment p) =>
      StudentActivity._(p.date ?? DateTime(2000), payment: p);
}

/// مستودع بيانات الطالب: يستمع لحظياً لبيانات المعلم والدروس والمدفوعات.
class StudentRepository extends ChangeNotifier {
  StudentRepository({required this.studentCode, required this.teacherCode});

  final String studentCode;
  final String teacherCode;

  // بيانات خام
  String teacherName = '';
  String teacherPhone = '';
  String teacherEmail = '';
  String studentName = '';
  String gender = '';
  double hourlyRate = 0;
  String? email;
  String? phone;

  List<StudentLesson> lessons = const [];
  List<StudentPayment> payments = const [];
  StudentFinance finance = StudentFinance.empty;

  bool _teacherReady = false;
  bool _studentReady = false;
  bool _lessonsReady = false;
  bool _paymentsReady = false;
  bool _profileReady = false;
  String? error;

  bool get isReady =>
      _teacherReady &&
      _studentReady &&
      _lessonsReady &&
      _paymentsReady &&
      _profileReady;

  bool get hasTeacher => teacherCode.isNotEmpty;

  final List<StreamSubscription<DatabaseEvent>> _subs = [];
  DatabaseReference get _db => FirebaseDatabase.instance.ref();

  void start() {
    if (studentCode.isEmpty) {
      error = 'تعذر تحديد حساب الطالب';
      _markAllReady();
      notifyListeners();
      return;
    }
    // ملف الطالب في الجذر (بريد/هاتف)
    _subs.add(_db.child('users/$studentCode').onValue.listen((e) {
      final v = e.snapshot.value;
      if (v is Map) {
        final m = Map<String, dynamic>.from(v);
        email = m['email']?.toString();
        phone = m['phone']?.toString();
        if ((m['name'] ?? '').toString().isNotEmpty && studentName.isEmpty) {
          studentName = m['name'].toString();
        }
      }
      _profileReady = true;
      notifyListeners();
    }, onError: _onError));

    if (!hasTeacher) {
      _teacherReady = _studentReady = _lessonsReady = _paymentsReady = true;
      notifyListeners();
      return;
    }

    _subs.add(_db.child('users/$teacherCode').onValue.listen((e) {
      final v = e.snapshot.value;
      if (v is Map) {
        final m = Map<String, dynamic>.from(v);
        teacherName = (m['name'] ?? '').toString();
        teacherPhone = (m['phone'] ?? '').toString();
        teacherEmail = (m['email'] ?? '').toString();
        // بيانات الطالب داخل المعلم
        final students = m['students'];
        if (students is Map && students[studentCode] is Map) {
          final s = Map<String, dynamic>.from(students[studentCode] as Map);
          studentName = (s['name'] ?? studentName).toString();
          hourlyRate = double.tryParse('${s['hourlyRate'] ?? 0}') ?? 0;
          gender = (s['gender'] ?? '').toString();
        }
        _studentReady = true;
        // الدروس
        _parseLessons(m['schedule']);
        _lessonsReady = true;
        // المدفوعات
        final pays = m['payments'];
        _parsePayments(pays is Map ? pays[studentCode] : null);
        _paymentsReady = true;
      } else {
        _studentReady = _lessonsReady = _paymentsReady = true;
      }
      _teacherReady = true;
      _recompute();
      notifyListeners();
    }, onError: _onError));
  }

  void _markAllReady() {
    _teacherReady =
        _studentReady = _lessonsReady = _paymentsReady = _profileReady = true;
  }

  void _onError(Object e) {
    error = 'تعذر تحميل البيانات: $e';
    _markAllReady();
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!hasTeacher) return;
    try {
      final snap = await _db.child('users/$teacherCode').get();
      final v = snap.value;
      if (v is Map) {
        final m = Map<String, dynamic>.from(v);
        teacherName = (m['name'] ?? '').toString();
        teacherPhone = (m['phone'] ?? '').toString();
        final students = m['students'];
        if (students is Map && students[studentCode] is Map) {
          final s = Map<String, dynamic>.from(students[studentCode] as Map);
          studentName = (s['name'] ?? studentName).toString();
          hourlyRate = double.tryParse('${s['hourlyRate'] ?? 0}') ?? 0;
        }
        _parseLessons(m['schedule']);
        final pays = m['payments'];
        _parsePayments(pays is Map ? pays[studentCode] : null);
        _recompute();
      }
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

  void _parseLessons(Object? value) {
    final list = <StudentLesson>[];
    if (value is Map) {
      final now = DateTime.now();
      for (final e in Map<String, dynamic>.from(value).entries) {
        if (e.value is! Map) continue;
        final m = Map<String, dynamic>.from(e.value as Map);
        if ((m['student'] ?? '').toString() != studentCode) continue;
        final rawStatus = (m['status'] ?? '').toString();
        if (rawStatus == 'temporary') continue;
        final s = DateTime.tryParse(m['startTime']?.toString() ?? '');
        if (s == null) continue;
        var en = DateTime.tryParse(m['endTime']?.toString() ?? '');
        final durSec = int.tryParse('${m['duration'] ?? ''}') ?? 0;
        if (en == null || !en.isAfter(s)) {
          en = s.add(Duration(seconds: durSec > 0 ? durSec : 3600));
        }
        var status = TimelineStatusX.fromRaw(rawStatus);
        if ((status == TimelineStatus.scheduled ||
                status == TimelineStatus.pending) &&
            en.isBefore(now)) {
          status = TimelineStatus.missed;
        }
        list.add(StudentLesson(
          id: e.key,
          start: s,
          end: en,
          status: status,
          rawStatus: rawStatus,
          amount: double.tryParse('${m['amount'] ?? 0}') ?? 0,
          note: (m['note'] ?? '').toString(),
          cancelReason: (m['cancelReason'] ?? '').toString(),
          isPaid: false,
          raw: m,
        ));
      }
    }
    list.sort((a, b) => b.start.compareTo(a.start));
    lessons = list;
  }

  void _parsePayments(Object? value) {
    final list = <StudentPayment>[];
    if (value is Map) {
      for (final e in Map<String, dynamic>.from(value).entries) {
        if (e.value is! Map) continue;
        final m = Map<String, dynamic>.from(e.value as Map);
        list.add(StudentPayment(
          id: e.key,
          amount: double.tryParse('${m['amount'] ?? 0}') ?? 0,
          date: DateTime.tryParse(m['date']?.toString() ?? ''),
          payer: (m['payer'] ?? 'student').toString(),
          method: (m['method'] ?? '').toString(),
          note: (m['note'] ?? '').toString(),
        ));
      }
    }
    list.sort((a, b) =>
        (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)));
    payments = list;
  }

  /// نفس صيغة صفحة أرصدة المعلم:
  /// الرصيد = مجموع الدروس المنتهية − ما دفعه الطالب + ما أرجعه المعلم.
  void _recompute() {
    double lessonsTotal = 0;
    for (final l in lessons) {
      if (l.isEnded) lessonsTotal += l.amount;
    }
    double paid = 0, returned = 0;
    for (final p in payments) {
      if (p.fromStudent) {
        paid += p.amount;
      } else {
        returned += p.amount;
      }
    }
    finance =
        StudentFinance(lessonsTotal: lessonsTotal, paid: paid, returned: returned);

    // توزيع صافي المدفوعات على الدروس المنتهية من الأقدم للأحدث
    final ended = lessons.where((l) => l.isEnded).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    var remaining = finance.netPaid;
    final paidIds = <String>{};
    for (final l in ended) {
      if (remaining >= l.amount && l.amount >= 0) {
        paidIds.add(l.id);
        remaining -= l.amount;
      } else {
        remaining = 0;
      }
    }
    lessons = lessons
        .map((l) => l.isEnded ? l.copyWith(isPaid: paidIds.contains(l.id)) : l)
        .toList();
  }

  // ===================== مشتقات =====================

  List<StudentLesson> get endedLessons =>
      lessons.where((l) => l.isEnded).toList();

  List<StudentLesson> get upcomingLessons {
    final list = lessons.where((l) => l.isUpcoming).toList();
    list.sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  List<StudentLesson> get pendingRequests {
    final list = lessons.where((l) => l.isPending).toList();
    list.sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  StudentLesson? get runningLesson {
    for (final l in lessons) {
      if (l.isRunning) return l;
    }
    return null;
  }

  StudentLesson? get nextLesson =>
      upcomingLessons.isEmpty ? null : upcomingLessons.first;

  List<StudentLesson> get unpaidLessons =>
      endedLessons.where((l) => !l.isPaid).toList();

  int get totalMinutesLearned =>
      endedLessons.fold<int>(0, (s, l) => s + l.minutes);

  /// إحصائيات شهر معيّن.
  ({int count, int minutes, double amount, double paid}) monthStats(
      DateTime month) {
    var count = 0, minutes = 0;
    double amount = 0, paid = 0;
    for (final l in endedLessons) {
      if (TimelineFormat.isSameMonth(l.start, month)) {
        count++;
        minutes += l.minutes;
        amount += l.amount;
      }
    }
    for (final p in payments) {
      if (p.date != null && TimelineFormat.isSameMonth(p.date!, month)) {
        paid += p.signedAmount;
      }
    }
    return (count: count, minutes: minutes, amount: amount, paid: paid);
  }

  /// آخر النشاطات (دروس منتهية/ملغية + دفعات) مرتبة تنازلياً.
  List<StudentActivity> recentActivity({int limit = 6}) {
    final items = <StudentActivity>[
      for (final l in lessons)
        if (l.isEnded || l.status == TimelineStatus.canceled)
          StudentActivity.lesson(l),
      for (final p in payments) StudentActivity.payment(p),
    ]..sort((a, b) => b.date.compareTo(a.date));
    return items.take(limit).toList();
  }

  StudentPayment? get lastPayment {
    for (final p in payments) {
      if (p.fromStudent) return p;
    }
    return null;
  }

  // ===================== الإجراءات =====================

  /// إرسال طلب موعد جديد (نفس البنية القديمة مع حقول إضافية).
  Future<String> requestLesson({
    required DateTime start,
    required DateTime end,
    String note = '',
  }) async {
    final ref = _db.child('users/$teacherCode/schedule').push();
    await ref.set({
      'teacher': teacherCode,
      'student': studentCode,
      'studentName': studentName,
      'date': TimelineFormat.ymd(start),
      'startTime': start.toIso8601String(),
      'endTime': end.toIso8601String(),
      'duration': end.difference(start).inSeconds,
      'createdAt': DateTime.now().toIso8601String(),
      'status': 'pending',
      'requestedBy': 'student',
      if (note.isNotEmpty) 'note': note,
    });
    return ref.key!;
  }

  /// سحب طلب معلّق (قبل موافقة المعلم فقط).
  Future<void> withdrawRequest(StudentLesson lesson) async {
    if (!lesson.isPending) return;
    await _db.child('users/$teacherCode/schedule/${lesson.id}').remove();
  }

  /// تحديث بيانات التواصل للطالب.
  Future<void> updateContact({String? email, String? phone}) async {
    await _db.child('users/$studentCode').update({
      if (email != null) 'email': email.trim(),
      if (phone != null) 'phone': phone.trim(),
    });
  }

  /// الفترات المحجوزة عند المعلم في يوم معيّن (دروس مؤكدة + مواعيد متكررة).
  Future<List<(DateTime, DateTime)>> busyRangesOn(DateTime day) async {
    final result = <(DateTime, DateTime)>[];
    final results = await Future.wait([
      _db.child('users/$teacherCode/schedule').get(),
      _db.child('users/$teacherCode/recurringSchedules').get(),
    ]);
    final sched = results[0].value;
    if (sched is Map) {
      for (final v in sched.values) {
        if (v is! Map) continue;
        final m = Map<String, dynamic>.from(v);
        final st = (m['status'] ?? '').toString();
        if (st != 'scheduled' && st != 'pending' && st != 'started') continue;
        final s = DateTime.tryParse(m['startTime']?.toString() ?? '');
        final e = DateTime.tryParse(m['endTime']?.toString() ?? '');
        if (s == null || e == null) continue;
        if (!TimelineFormat.isSameDay(s, day)) continue;
        result.add((s, e));
      }
    }
    final rec = results[1].value;
    if (rec is Map) {
      for (final entry in Map<String, dynamic>.from(rec).entries) {
        if (entry.value is! Map) continue;
        try {
          final r = RecurringSchedule.fromMap(
              entry.key, Map<String, dynamic>.from(entry.value as Map));
          if (!RecurrenceUtils.occursOn(r, day)) continue;
          result.add((
            RecurrenceUtils.buildStartForDay(r, day),
            RecurrenceUtils.buildEndForDay(r, day),
          ));
        } catch (_) {}
      }
    }
    return result;
  }
}
