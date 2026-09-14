// lib/src/services/teacher_account.dart
//
// 👨‍🏫 حساب المعلم: بيانات الملف الشخصي + الخصوصية + إحصائيات لحظية.
// يستمع لعقدة users/$code كاملة (بيانات، طلاب، جدول، دفعات) ويحسب:
//   - عدد الطلاب / الدروس المنتهية / القادمة / الطلبات المعلقة
//   - إيراد الشهر الحالي والسابق، الإجمالي، المستحقات على الطلاب
//   - سلسلة 6 أشهر للرسم البياني
//
// إعدادات المعلم (على جذر عقدته):
//   users/$code/showPhoneToStudents : bool   (افتراضياً true)
//   users/$code/defaultHourlyRate   : num    (سعر الساعة الافتراضي للطلاب الجدد)

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'timeline_models.dart' show TimelineFormat;

class TeacherAccount extends ChangeNotifier {
  TeacherAccount(this.code);

  final String code;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  StreamSubscription<DatabaseEvent>? _sub;

  // ---- الملف الشخصي
  String name = '';
  String phone = '';
  String email = '';
  DateTime? createdAt;
  bool showPhoneToStudents = true;
  double defaultHourlyRate = 0;

  // ---- الإحصائيات
  int studentsCount = 0;
  int endedCount = 0;
  int upcomingCount = 0;
  int pendingCount = 0;
  int todayCount = 0;
  int totalMinutes = 0;
  double totalRevenue = 0;
  double monthRevenue = 0;
  double prevMonthRevenue = 0;
  double owed = 0; // مجموع ما على الطلاب (الأرصدة الموجبة)
  double credit = 0; // مجموع الأرصدة الزائدة لصالح الطلاب
  List<({String label, double value})> months = const [];

  bool ready = false;
  String? error;

  double get growth {
    if (prevMonthRevenue <= 0) return monthRevenue > 0 ? 1 : 0;
    return (monthRevenue - prevMonthRevenue) / prevMonthRevenue;
  }

  bool get profileComplete => name.isNotEmpty && phone.isNotEmpty;

  void start() {
    if (code.isEmpty) {
      ready = true;
      notifyListeners();
      return;
    }
    _sub?.cancel();
    _sub = _db.child('users/$code').onValue.listen((e) {
      final v = e.snapshot.value;
      if (v is Map) {
        _parse(Map<String, dynamic>.from(v));
      }
      ready = true;
      error = null;
      notifyListeners();
    }, onError: (Object err) {
      error = 'تعذر تحميل البيانات: $err';
      ready = true;
      notifyListeners();
    });
  }

  void _parse(Map<String, dynamic> m) {
    name = (m['name'] ?? '').toString();
    phone = (m['phone'] ?? '').toString();
    email = (m['email'] ?? '').toString();
    createdAt = DateTime.tryParse('${m['createdAt'] ?? ''}');
    showPhoneToStudents = m['showPhoneToStudents'] != false;
    defaultHourlyRate = double.tryParse('${m['defaultHourlyRate'] ?? 0}') ?? 0;

    final students = m['students'];
    final studentCodes = <String>{};
    if (students is Map) {
      studentsCount = students.length;
      studentCodes.addAll(students.keys.map((k) => k.toString()));
    } else {
      studentsCount = 0;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisMonth = DateTime(now.year, now.month);
    final prevMonth = DateTime(now.year, now.month - 1);
    final buckets = <String, double>{};
    for (var i = 5; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i);
      buckets['${d.year}-${d.month}'] = 0;
    }

    int ended = 0, upcoming = 0, pending = 0, todayN = 0, minutes = 0;
    double total = 0, month = 0, prev = 0;
    final lessonsByStudent = <String, double>{};

    final schedule = m['schedule'];
    if (schedule is Map) {
      for (final raw in schedule.values) {
        if (raw is! Map) continue;
        final l = Map<String, dynamic>.from(raw);
        final status = (l['status'] ?? '').toString();
        final amount = double.tryParse('${l['amount'] ?? 0}') ?? 0;
        final start = DateTime.tryParse('${l['startTime'] ?? l['date'] ?? ''}');
        final end = DateTime.tryParse('${l['endTime'] ?? ''}');
        final student = (l['student'] ?? '').toString();

        if (start != null &&
            DateTime(start.year, start.month, start.day) == today &&
            status != 'canceled') {
          todayN++;
        }

        switch (status) {
          case 'ended':
            ended++;
            total += amount;
            lessonsByStudent[student] = (lessonsByStudent[student] ?? 0) + amount;
            if (start != null) {
              final key = '${start.year}-${start.month}';
              if (buckets.containsKey(key)) buckets[key] = buckets[key]! + amount;
              final sm = DateTime(start.year, start.month);
              if (sm == thisMonth) month += amount;
              if (sm == prevMonth) prev += amount;
              if (end != null && end.isAfter(start)) {
                minutes += end.difference(start).inMinutes;
              } else {
                final sec = int.tryParse('${l['duration'] ?? 0}') ?? 0;
                minutes += sec ~/ 60;
              }
            }
          case 'pending':
            pending++;
          case 'scheduled':
          case 'started':
            if (start != null && start.isAfter(now.subtract(const Duration(hours: 3)))) {
              upcoming++;
            }
        }
      }
    }

    // الأرصدة: دروس منتهية − دفعات الطالب + إرجاعات المعلم
    double owedSum = 0, creditSum = 0;
    final payments = m['payments'];
    for (final sc in studentCodes) {
      double paid = 0, returned = 0;
      if (payments is Map && payments[sc] is Map) {
        for (final p in (payments[sc] as Map).values) {
          if (p is! Map) continue;
          final amount = double.tryParse('${p['amount'] ?? 0}') ?? 0;
          if ((p['payer'] ?? 'student') == 'teacher') {
            returned += amount;
          } else {
            paid += amount;
          }
        }
      }
      final bal = (lessonsByStudent[sc] ?? 0) - paid + returned;
      if (bal > 0) owedSum += bal;
      if (bal < 0) creditSum += -bal;
    }

    endedCount = ended;
    upcomingCount = upcoming;
    pendingCount = pending;
    todayCount = todayN;
    totalMinutes = minutes;
    totalRevenue = total;
    monthRevenue = month;
    prevMonthRevenue = prev;
    owed = owedSum;
    credit = creditSum;
    months = buckets.entries.map((e) {
      final parts = e.key.split('-');
      final d = DateTime(int.parse(parts[0]), int.parse(parts[1]));
      return (label: TimelineFormat.monthName(d), value: e.value);
    }).toList();
  }

  // ---- التعديلات

  Future<void> setShowPhoneToStudents(bool value) async {
    showPhoneToStudents = value;
    notifyListeners();
    await _db.child('users/$code').update({
      'showPhoneToStudents': value,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> setDefaultHourlyRate(double value) async {
    defaultHourlyRate = value;
    notifyListeners();
    await _db.child('users/$code').update({
      'defaultHourlyRate': value,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateProfile({String? name, String? phone, String? email}) async {
    final data = <String, dynamic>{'updatedAt': DateTime.now().toIso8601String()};
    if (name != null && name.trim().isNotEmpty) data['name'] = name.trim();
    if (phone != null) data['phone'] = phone.trim();
    if (email != null) data['email'] = email.trim();
    await _db.child('users/$code').update(data);
  }

  /// سعر الساعة الافتراضي للمعلم (يُستخدم عند إضافة طالب جديد).
  static Future<double> fetchDefaultRate(String teacherCode) async {
    if (teacherCode.isEmpty) return 0;
    try {
      final snap = await FirebaseDatabase.instance.ref('users/$teacherCode/defaultHourlyRate').get();
      return double.tryParse('${snap.value ?? 0}') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
