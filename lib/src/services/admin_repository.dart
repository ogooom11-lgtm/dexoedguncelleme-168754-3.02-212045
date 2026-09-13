// lib/src/services/admin_repository.dart
//
// 🛡️ مستودع بيانات لوحة الإدارة:
// يستمع لحظياً لجذر `users` ويبني شجرة (معلم ← طلابه ← دروسهم ودفعاتهم)
// مع إحصاءات جاهزة، ويوفّر إجراءات الإدارة (إنشاء/تعديل/تعطيل/نقل/حذف)
// مع تسجيل كل إجراء في `adminLog`.

import 'dart:async';
import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'teacher_permissions.dart';
import 'timeline_models.dart';

// =====================================================================
// النماذج
// =====================================================================

class AdminLesson {
  final String id;
  final String teacherCode;
  final String studentCode;
  final DateTime start;
  final DateTime end;
  final TimelineStatus status;
  final String rawStatus;
  final double amount;
  final String note;

  const AdminLesson({
    required this.id,
    required this.teacherCode,
    required this.studentCode,
    required this.start,
    required this.end,
    required this.status,
    required this.rawStatus,
    required this.amount,
    required this.note,
  });

  int get minutes => end.difference(start).inMinutes;
  bool get isEnded => status == TimelineStatus.ended;
  bool get isPending => status == TimelineStatus.pending;
  bool get isRunning => status == TimelineStatus.started;
  bool get isUpcoming =>
      status == TimelineStatus.scheduled && start.isAfter(DateTime.now());
}

class AdminPayment {
  final String id;
  final String teacherCode;
  final String studentCode;
  final double amount;
  final DateTime? date;
  final String payer; // student | teacher
  final String method;

  const AdminPayment({
    required this.id,
    required this.teacherCode,
    required this.studentCode,
    required this.amount,
    required this.date,
    required this.payer,
    required this.method,
  });

  bool get fromStudent => payer != 'teacher';
}

class AdminStudent {
  final String code;
  final String teacherCode;
  final String name;
  final double hourlyRate;
  final String gender;
  final DateTime? createdAt;

  /// هل يوجد سجل جذر `users/$code` (أي يستطيع الدخول فوراً)؟
  final bool linked;
  final bool disabled;
  final String email;
  final String phone;

  final List<AdminLesson> lessons;
  final List<AdminPayment> payments;

  const AdminStudent({
    required this.code,
    required this.teacherCode,
    required this.name,
    required this.hourlyRate,
    required this.gender,
    required this.createdAt,
    required this.linked,
    required this.disabled,
    required this.email,
    required this.phone,
    required this.lessons,
    required this.payments,
  });

  Iterable<AdminLesson> get ended => lessons.where((l) => l.isEnded);
  int get endedCount => ended.length;
  int get minutes => ended.fold(0, (s, l) => s + l.minutes);
  double get lessonsTotal => ended.fold(0.0, (s, l) => s + l.amount);
  double get paid => payments
      .where((p) => p.fromStudent)
      .fold(0.0, (s, p) => s + p.amount);
  double get returned => payments
      .where((p) => !p.fromStudent)
      .fold(0.0, (s, p) => s + p.amount);

  /// موجب = على الطالب، سالب = رصيد زائد له.
  double get balance => lessonsTotal - paid + returned;
  bool get owes => balance > 0.5;
  bool get hasCredit => balance < -0.5;

  DateTime? get lastLessonAt {
    DateTime? d;
    for (final l in ended) {
      if (d == null || l.start.isAfter(d)) d = l.start;
    }
    return d;
  }

  int get pendingCount => lessons.where((l) => l.isPending).length;
  int get upcomingCount => lessons.where((l) => l.isUpcoming).length;

  /// تعتبر "نشط" إذا كان له درس منتهٍ خلال آخر 30 يوماً أو درس قادم.
  bool get isActive {
    final last = lastLessonAt;
    if (upcomingCount > 0) return true;
    if (last == null) return false;
    return DateTime.now().difference(last).inDays <= 30;
  }
}

class AdminTeacher {
  final String code;
  final String name;
  final String email;
  final String phone;
  final DateTime? createdAt;
  final bool disabled;
  final TeacherPermissions permissions;
  final List<AdminStudent> students;
  final int recurringCount;
  final Map<String, dynamic> raw;

  const AdminTeacher({
    required this.code,
    required this.name,
    required this.email,
    required this.phone,
    required this.createdAt,
    required this.disabled,
    required this.permissions,
    required this.students,
    required this.recurringCount,
    required this.raw,
  });

  Iterable<AdminLesson> get lessons => students.expand((s) => s.lessons);
  Iterable<AdminPayment> get payments => students.expand((s) => s.payments);

  int get endedCount => students.fold(0, (s, st) => s + st.endedCount);
  int get minutes => students.fold(0, (s, st) => s + st.minutes);
  double get revenue => students.fold(0.0, (s, st) => s + st.lessonsTotal);
  double get collected =>
      students.fold(0.0, (s, st) => s + st.paid - st.returned);
  double get owed =>
      students.where((s) => s.owes).fold(0.0, (s, st) => s + st.balance);
  int get owingStudents => students.where((s) => s.owes).length;
  int get pendingCount => students.fold(0, (s, st) => s + st.pendingCount);
  int get upcomingCount => students.fold(0, (s, st) => s + st.upcomingCount);
  int get activeStudents => students.where((s) => s.isActive).length;
  bool get hasRunningLesson => lessons.any((l) => l.isRunning);

  DateTime? get lastActivityAt {
    DateTime? d;
    for (final l in lessons) {
      if (d == null || l.start.isAfter(d)) d = l.start;
    }
    return d;
  }

  double revenueIn(DateTime month) => lessons
      .where((l) => l.isEnded && TimelineFormat.isSameMonth(l.start, month))
      .fold(0.0, (s, l) => s + l.amount);

  int endedIn(DateTime month) => lessons
      .where((l) => l.isEnded && TimelineFormat.isSameMonth(l.start, month))
      .length;
}

class AdminAccount {
  final String code;
  final String name;
  final String email;
  final String role;
  final bool disabled;
  final DateTime? createdAt;

  const AdminAccount({
    required this.code,
    required this.name,
    required this.email,
    required this.role,
    required this.disabled,
    required this.createdAt,
  });
}

class AdminLogEntry {
  final String id;
  final String action;
  final String target;
  final String by;
  final DateTime at;
  final String details;

  const AdminLogEntry({
    required this.id,
    required this.action,
    required this.target,
    required this.by,
    required this.at,
    required this.details,
  });
}

/// إعدادات المنصة (تُقرأ من `settings/platform`).
class PlatformSettings {
  final String currency;
  final bool allowStudentRequests;
  final bool allowStudentContactEdit;
  final bool requireZeroBalanceToDelete;
  final double defaultHourlyRate;
  final String announcement;
  final bool announcementForTeachers;
  final bool announcementForStudents;

  const PlatformSettings({
    this.currency = 'ر.ق',
    this.allowStudentRequests = true,
    this.allowStudentContactEdit = true,
    this.requireZeroBalanceToDelete = true,
    this.defaultHourlyRate = 0,
    this.announcement = '',
    this.announcementForTeachers = true,
    this.announcementForStudents = true,
  });

  factory PlatformSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const PlatformSettings();
    return PlatformSettings(
      currency: (m['currency'] ?? 'ر.ق').toString(),
      allowStudentRequests: m['allowStudentRequests'] != false,
      allowStudentContactEdit: m['allowStudentContactEdit'] != false,
      requireZeroBalanceToDelete: m['requireZeroBalanceToDelete'] != false,
      defaultHourlyRate:
          double.tryParse('${m['defaultHourlyRate'] ?? 0}') ?? 0,
      announcement: (m['announcement'] ?? '').toString(),
      announcementForTeachers: m['announcementForTeachers'] != false,
      announcementForStudents: m['announcementForStudents'] != false,
    );
  }

  Map<String, dynamic> toMap() => {
        'currency': currency,
        'allowStudentRequests': allowStudentRequests,
        'allowStudentContactEdit': allowStudentContactEdit,
        'requireZeroBalanceToDelete': requireZeroBalanceToDelete,
        'defaultHourlyRate': defaultHourlyRate,
        'announcement': announcement,
        'announcementForTeachers': announcementForTeachers,
        'announcementForStudents': announcementForStudents,
        'updatedAt': DateTime.now().toIso8601String(),
      };

  PlatformSettings copyWith({
    String? currency,
    bool? allowStudentRequests,
    bool? allowStudentContactEdit,
    bool? requireZeroBalanceToDelete,
    double? defaultHourlyRate,
    String? announcement,
    bool? announcementForTeachers,
    bool? announcementForStudents,
  }) {
    return PlatformSettings(
      currency: currency ?? this.currency,
      allowStudentRequests: allowStudentRequests ?? this.allowStudentRequests,
      allowStudentContactEdit:
          allowStudentContactEdit ?? this.allowStudentContactEdit,
      requireZeroBalanceToDelete:
          requireZeroBalanceToDelete ?? this.requireZeroBalanceToDelete,
      defaultHourlyRate: defaultHourlyRate ?? this.defaultHourlyRate,
      announcement: announcement ?? this.announcement,
      announcementForTeachers:
          announcementForTeachers ?? this.announcementForTeachers,
      announcementForStudents:
          announcementForStudents ?? this.announcementForStudents,
    );
  }
}

// =====================================================================
// المستودع
// =====================================================================

class AdminRepository extends ChangeNotifier {
  AdminRepository({required this.adminCode, required this.adminName});

  final String adminCode;
  final String adminName;

  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final List<StreamSubscription<DatabaseEvent>> _subs = [];

  List<AdminTeacher> teachers = const [];
  List<AdminAccount> admins = const [];

  /// طلاب لهم سجل جذر لكن معلمهم غير موجود أو لم يعد يضمّهم.
  List<AdminAccount> orphanStudents = const [];
  List<AdminLogEntry> log = const [];
  PlatformSettings settings = const PlatformSettings();

  bool _usersReady = false;
  bool _logReady = false;
  bool _settingsReady = false;
  String? error;

  bool get isReady => _usersReady && _logReady && _settingsReady;

  void start() {
    _subs.add(_db.child('users').onValue.listen((e) {
      _parseUsers(e.snapshot.value);
      _usersReady = true;
      error = null;
      notifyListeners();
    }, onError: _onError));

    _subs.add(_db
        .child('adminLog')
        .orderByChild('at')
        .limitToLast(80)
        .onValue
        .listen((e) {
      _parseLog(e.snapshot.value);
      _logReady = true;
      notifyListeners();
    }, onError: (Object _) {
      _logReady = true;
      notifyListeners();
    }));

    _subs.add(_db.child('settings/platform').onValue.listen((e) {
      final v = e.snapshot.value;
      settings = PlatformSettings.fromMap(
          v is Map ? Map<String, dynamic>.from(v) : null);
      TimelineFormat.currency = settings.currency;
      _settingsReady = true;
      notifyListeners();
    }, onError: (Object _) {
      _settingsReady = true;
      notifyListeners();
    }));
  }

  void _onError(Object e) {
    error = e.toString();
    _usersReady = true;
    notifyListeners();
  }

  Future<void> refresh() async {
    try {
      final snap = await _db.child('users').get();
      _parseUsers(snap.value);
      _usersReady = true;
      notifyListeners();
    } catch (e) {
      _onError(e);
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // التحليل
  // ------------------------------------------------------------------

  void _parseUsers(Object? value) {
    final teachersOut = <AdminTeacher>[];
    final adminsOut = <AdminAccount>[];
    final orphansOut = <AdminAccount>[];
    if (value is! Map) {
      teachers = teachersOut;
      admins = adminsOut;
      orphanStudents = orphansOut;
      return;
    }
    final users = Map<String, dynamic>.from(value);
    final teacherCodes = <String>{};
    // خريطة كود الطالب ← سجل الجذر
    final rootStudents = <String, Map<String, dynamic>>{};

    for (final e in users.entries) {
      if (e.value is! Map) continue;
      final m = Map<String, dynamic>.from(e.value as Map);
      final role = (m['role'] ?? '').toString();
      if (role == 'teacher') teacherCodes.add(e.key);
      if (role == 'student') rootStudents[e.key] = m;
      if (role == 'admin') {
        adminsOut.add(AdminAccount(
          code: e.key,
          name: (m['name'] ?? 'مدير').toString(),
          email: (m['email'] ?? '').toString(),
          role: role,
          disabled: m['disabled'] == true,
          createdAt: DateTime.tryParse('${m['createdAt'] ?? ''}'),
        ));
      }
    }

    final claimed = <String>{};

    for (final code in teacherCodes) {
      final m = Map<String, dynamic>.from(users[code] as Map);
      final now = DateTime.now();

      // الدروس مجمّعة حسب الطالب
      final lessonsByStudent = <String, List<AdminLesson>>{};
      final sched = m['schedule'];
      if (sched is Map) {
        for (final le in Map<String, dynamic>.from(sched).entries) {
          if (le.value is! Map) continue;
          final lm = Map<String, dynamic>.from(le.value as Map);
          final rawStatus = (lm['status'] ?? '').toString();
          if (rawStatus == 'temporary') continue;
          final s = DateTime.tryParse(lm['startTime']?.toString() ?? '');
          if (s == null) continue;
          var en = DateTime.tryParse(lm['endTime']?.toString() ?? '');
          final durSec = int.tryParse('${lm['duration'] ?? ''}') ?? 0;
          if (en == null || !en.isAfter(s)) {
            en = s.add(Duration(seconds: durSec > 0 ? durSec : 3600));
          }
          var status = TimelineStatusX.fromRaw(rawStatus);
          if ((status == TimelineStatus.scheduled ||
                  status == TimelineStatus.pending) &&
              en.isBefore(now)) {
            status = TimelineStatus.missed;
          }
          final st = (lm['student'] ?? '').toString();
          lessonsByStudent.putIfAbsent(st, () => []).add(AdminLesson(
                id: le.key,
                teacherCode: code,
                studentCode: st,
                start: s,
                end: en,
                status: status,
                rawStatus: rawStatus,
                amount: double.tryParse('${lm['amount'] ?? 0}') ?? 0,
                note: (lm['note'] ?? '').toString(),
              ));
        }
      }

      final paymentsByStudent = <String, List<AdminPayment>>{};
      final pays = m['payments'];
      if (pays is Map) {
        for (final pe in Map<String, dynamic>.from(pays).entries) {
          if (pe.value is! Map) continue;
          final list = <AdminPayment>[];
          for (final x in Map<String, dynamic>.from(pe.value as Map).entries) {
            if (x.value is! Map) continue;
            final pm = Map<String, dynamic>.from(x.value as Map);
            list.add(AdminPayment(
              id: x.key,
              teacherCode: code,
              studentCode: pe.key,
              amount: double.tryParse('${pm['amount'] ?? 0}') ?? 0,
              date: DateTime.tryParse(pm['date']?.toString() ?? ''),
              payer: (pm['payer'] ?? 'student').toString(),
              method: (pm['method'] ?? '').toString(),
            ));
          }
          list.sort((a, b) => (b.date ?? DateTime(2000))
              .compareTo(a.date ?? DateTime(2000)));
          paymentsByStudent[pe.key] = list;
        }
      }

      final students = <AdminStudent>[];
      final stRaw = m['students'];
      if (stRaw is Map) {
        for (final se in Map<String, dynamic>.from(stRaw).entries) {
          final sm = se.value is Map
              ? Map<String, dynamic>.from(se.value as Map)
              : <String, dynamic>{'name': se.value?.toString() ?? ''};
          final root = rootStudents[se.key];
          claimed.add(se.key);
          final lessons = lessonsByStudent[se.key] ?? <AdminLesson>[];
          lessons.sort((a, b) => b.start.compareTo(a.start));
          students.add(AdminStudent(
            code: se.key,
            teacherCode: code,
            name: (sm['name'] ?? root?['name'] ?? 'طالب').toString(),
            hourlyRate: double.tryParse('${sm['hourlyRate'] ?? 0}') ?? 0,
            gender: (sm['gender'] ?? '').toString(),
            createdAt: DateTime.tryParse('${sm['createdAt'] ?? ''}'),
            linked: root != null,
            disabled: root?['disabled'] == true,
            email: (root?['email'] ?? '').toString(),
            phone: (root?['phone'] ?? '').toString(),
            lessons: lessons,
            payments: paymentsByStudent[se.key] ?? const [],
          ));
        }
      }
      students.sort((a, b) => a.name.compareTo(b.name));

      final rec = m['recurringSchedules'];
      teachersOut.add(AdminTeacher(
        code: code,
        name: (m['name'] ?? 'معلم').toString(),
        email: (m['email'] ?? '').toString(),
        phone: (m['phone'] ?? '').toString(),
        createdAt: DateTime.tryParse('${m['createdAt'] ?? ''}'),
        disabled: m['disabled'] == true,
        permissions: TeacherPermissions.fromMap(
            m['permissions'] is Map ? Map<String, dynamic>.from(m['permissions'] as Map) : null),
        students: students,
        recurringCount: rec is Map ? rec.length : 0,
        raw: m,
      ));
    }

    for (final e in rootStudents.entries) {
      if (claimed.contains(e.key)) continue;
      orphansOut.add(AdminAccount(
        code: e.key,
        name: (e.value['name'] ?? 'طالب').toString(),
        email: (e.value['email'] ?? '').toString(),
        role: 'student',
        disabled: e.value['disabled'] == true,
        createdAt: DateTime.tryParse('${e.value['createdAt'] ?? ''}'),
      ));
    }

    teachersOut.sort((a, b) => a.name.compareTo(b.name));
    adminsOut.sort((a, b) => a.name.compareTo(b.name));
    teachers = teachersOut;
    admins = adminsOut;
    orphanStudents = orphansOut;
  }

  void _parseLog(Object? value) {
    final out = <AdminLogEntry>[];
    if (value is Map) {
      for (final e in Map<String, dynamic>.from(value).entries) {
        if (e.value is! Map) continue;
        final m = Map<String, dynamic>.from(e.value as Map);
        out.add(AdminLogEntry(
          id: e.key,
          action: (m['action'] ?? '').toString(),
          target: (m['target'] ?? '').toString(),
          by: (m['by'] ?? '').toString(),
          at: DateTime.tryParse('${m['at'] ?? ''}') ?? DateTime(2000),
          details: (m['details'] ?? '').toString(),
        ));
      }
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    log = out;
  }

  // ------------------------------------------------------------------
  // مشتقات
  // ------------------------------------------------------------------

  List<AdminStudent> get allStudents =>
      teachers.expand((t) => t.students).toList();

  AdminTeacher? teacher(String code) {
    for (final t in teachers) {
      if (t.code == code) return t;
    }
    return null;
  }

  AdminStudent? student(String code) {
    for (final t in teachers) {
      for (final s in t.students) {
        if (s.code == code) return s;
      }
    }
    return null;
  }

  int get totalAccounts =>
      teachers.length + allStudents.length + admins.length + orphanStudents.length;

  double get totalRevenue => teachers.fold(0.0, (s, t) => s + t.revenue);
  double get totalCollected => teachers.fold(0.0, (s, t) => s + t.collected);
  double get totalOwed => teachers.fold(0.0, (s, t) => s + t.owed);
  int get totalEnded => teachers.fold(0, (s, t) => s + t.endedCount);
  int get totalMinutes => teachers.fold(0, (s, t) => s + t.minutes);
  int get totalPending => teachers.fold(0, (s, t) => s + t.pendingCount);
  int get runningNow => teachers.where((t) => t.hasRunningLesson).length;
  int get disabledCount =>
      teachers.where((t) => t.disabled).length +
      allStudents.where((s) => s.disabled).length;

  double revenueIn(DateTime month) =>
      teachers.fold(0.0, (s, t) => s + t.revenueIn(month));
  int endedIn(DateTime month) =>
      teachers.fold(0, (s, t) => s + t.endedIn(month));

  /// دروس اليوم عبر كل المعلمين (منتهية + مجدولة + جارية).
  List<AdminLesson> lessonsOn(DateTime day) {
    final list = teachers
        .expand((t) => t.lessons)
        .where((l) => TimelineFormat.isSameDay(l.start, day))
        .toList();
    list.sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  /// أفضل المعلمين هذا الشهر حسب الإيراد.
  List<AdminTeacher> topTeachers(DateTime month, {int limit = 5}) {
    final list = teachers.toList()
      ..sort((a, b) => b.revenueIn(month).compareTo(a.revenueIn(month)));
    return list.take(limit).toList();
  }

  /// إيراد آخر 6 أشهر (للرسم البياني).
  List<({DateTime month, double revenue, int lessons})> lastMonths(
      {int count = 6}) {
    final now = DateTime.now();
    return List.generate(count, (i) {
      final m = DateTime(now.year, now.month - (count - 1 - i));
      return (month: m, revenue: revenueIn(m), lessons: endedIn(m));
    });
  }

  // ------------------------------------------------------------------
  // الإجراءات
  // ------------------------------------------------------------------

  Future<void> _log(String action, String target, [String details = '']) {
    return _db.child('adminLog').push().set({
      'action': action,
      'target': target,
      'details': details,
      'by': adminName.isEmpty ? adminCode : adminName,
      'byCode': adminCode,
      'at': DateTime.now().toIso8601String(),
    });
  }

  static void _validateCode(String code) {
    if (code.length != 8 || int.tryParse(code) == null) {
      throw Exception('الكود يجب أن يكون 8 أرقام');
    }
  }

  Future<String> generateCode() async {
    final r = Random();
    while (true) {
      final code = List.generate(8, (_) => r.nextInt(10)).join();
      final snap = await _db.child('users/$code').get();
      if (!snap.exists && student(code) == null) return code;
    }
  }

  Future<String> createTeacher({
    required String name,
    String? code,
    String email = '',
    String phone = '',
    TeacherPermissions? permissions,
  }) async {
    final c = (code ?? '').trim().isEmpty ? await generateCode() : code!.trim();
    _validateCode(c);
    if ((await _db.child('users/$c').get()).exists) {
      throw Exception('هذا الكود مستخدم بالفعل');
    }
    await _db.child('users/$c').set({
      'name': name.trim(),
      'role': 'teacher',
      if (email.trim().isNotEmpty) 'email': email.trim(),
      if (phone.trim().isNotEmpty) 'phone': phone.trim(),
      'createdAt': DateTime.now().toIso8601String(),
      'createdBy': adminCode,
      if (permissions != null) 'permissions': permissions.toMap(),
    });
    await _log('create_teacher', c, name.trim());
    return c;
  }

  Future<String> createAdmin({required String name, String? code}) async {
    final c = (code ?? '').trim().isEmpty ? await generateCode() : code!.trim();
    _validateCode(c);
    if ((await _db.child('users/$c').get()).exists) {
      throw Exception('هذا الكود مستخدم بالفعل');
    }
    await _db.child('users/$c').set({
      'name': name.trim(),
      'role': 'admin',
      'createdAt': DateTime.now().toIso8601String(),
      'createdBy': adminCode,
    });
    await _log('create_admin', c, name.trim());
    return c;
  }

  Future<void> updateAccount(String code, Map<String, dynamic> fields,
      {String? label}) async {
    await _db.child('users/$code').update({
      ...fields,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await _log('update_account', code, label ?? fields.keys.join(', '));
  }

  Future<void> setDisabled(String code, bool disabled, {String? name}) async {
    await _db.child('users/$code').update({
      'disabled': disabled,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await _log(disabled ? 'disable' : 'enable', code, name ?? '');
  }

  Future<void> setPermissions(String teacherCode, TeacherPermissions p,
      {String? name}) async {
    await _db.child('users/$teacherCode/permissions').set(p.toMap());
    await _log('permissions', teacherCode, name ?? '');
  }

  Future<void> deleteAdmin(String code) async {
    if (code == adminCode) throw Exception('لا يمكنك حذف حسابك الحالي');
    if (admins.length <= 1) throw Exception('لا يمكن حذف آخر حساب إدارة');
    await _db.child('users/$code').remove();
    await _log('delete_admin', code);
  }

  /// حذف معلم. مع `cascade` تُحذف سجلات الجذر لطلابه أيضاً.
  Future<void> deleteTeacher(String code, {bool cascade = true}) async {
    final t = teacher(code);
    final updates = <String, Object?>{'users/$code': null};
    if (cascade && t != null) {
      for (final s in t.students) {
        if (s.linked) updates['users/${s.code}'] = null;
      }
    }
    await _db.update(updates);
    await _log('delete_teacher', code,
        '${t?.name ?? ''}${cascade ? ' (مع ${t?.students.length ?? 0} طالب)' : ''}');
  }

  Future<void> deleteOrphan(String code) async {
    await _db.child('users/$code').remove();
    await _log('delete_orphan', code);
  }

  Future<String> addStudent({
    required String teacherCode,
    required String name,
    String? code,
    double hourlyRate = 0,
    String gender = 'male',
  }) async {
    final c = (code ?? '').trim().isEmpty ? await generateCode() : code!.trim();
    _validateCode(c);
    if ((await _db.child('users/$c').get()).exists) {
      throw Exception('هذا الكود مستخدم بالفعل');
    }
    final now = DateTime.now().toIso8601String();
    await _db.update({
      'users/$teacherCode/students/$c': {
        'name': name.trim(),
        'hourlyRate': hourlyRate,
        'gender': gender,
        'createdAt': now,
      },
      'users/$c': {
        'name': name.trim(),
        'role': 'student',
        'teacher': teacherCode,
        'createdAt': now,
        'createdBy': adminCode,
      },
    });
    await _log('create_student', c, '${name.trim()} ← ${teacher(teacherCode)?.name ?? teacherCode}');
    return c;
  }

  Future<void> updateStudent({
    required String teacherCode,
    required String code,
    required String name,
    required double hourlyRate,
    required String gender,
    String? email,
    String? phone,
  }) async {
    final updates = <String, Object?>{
      'users/$teacherCode/students/$code/name': name.trim(),
      'users/$teacherCode/students/$code/hourlyRate': hourlyRate,
      'users/$teacherCode/students/$code/gender': gender,
    };
    final rootExists = (await _db.child('users/$code').get()).exists;
    if (rootExists) {
      updates['users/$code/name'] = name.trim();
      if (email != null) updates['users/$code/email'] = email.trim();
      if (phone != null) updates['users/$code/phone'] = phone.trim();
    } else {
      updates['users/$code'] = {
        'name': name.trim(),
        'role': 'student',
        'teacher': teacherCode,
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        'createdAt': DateTime.now().toIso8601String(),
      };
    }
    await _db.update(updates);
    await _log('update_student', code, name.trim());
  }

  /// ربط طالب بلا سجل جذر (حتى يستطيع الدخول فوراً).
  Future<void> linkStudent(AdminStudent s) async {
    await _db.child('users/${s.code}').set({
      'name': s.name,
      'role': 'student',
      'teacher': s.teacherCode,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await _log('link_student', s.code, s.name);
  }

  Future<void> deleteStudent(AdminStudent s, {bool force = false}) async {
    if (!force && settings.requireZeroBalanceToDelete && s.balance.abs() > 0.5) {
      throw Exception('رصيد الطالب ليس صفراً (${TimelineFormat.money(s.balance)}). فعّل «حذف قسري» أو سوِّ الرصيد أولاً.');
    }
    final updates = <String, Object?>{
      'users/${s.teacherCode}/students/${s.code}': null,
      'users/${s.teacherCode}/payments/${s.code}': null,
    };
    if (force) {
      for (final l in s.lessons) {
        updates['users/${s.teacherCode}/schedule/${l.id}'] = null;
      }
    }
    if (s.linked) updates['users/${s.code}'] = null;
    await _db.update(updates);
    await _log('delete_student', s.code, '${s.name}${force ? ' (قسري)' : ''}');
  }

  /// نقل طالب من معلم إلى آخر مع سجل دروسه ودفعاته.
  Future<void> transferStudent(AdminStudent s, String toTeacher) async {
    if (toTeacher == s.teacherCode) return;
    if (teacher(toTeacher) == null) throw Exception('المعلم الهدف غير موجود');
    final base = _db.child('users/${s.teacherCode}');
    final stSnap = await base.child('students/${s.code}').get();
    final paySnap = await base.child('payments/${s.code}').get();
    final updates = <String, Object?>{
      'users/$toTeacher/students/${s.code}': stSnap.value,
      'users/${s.teacherCode}/students/${s.code}': null,
      'users/${s.code}/teacher': toTeacher,
    };
    if (paySnap.exists) {
      updates['users/$toTeacher/payments/${s.code}'] = paySnap.value;
      updates['users/${s.teacherCode}/payments/${s.code}'] = null;
    }
    if (!s.linked) {
      updates['users/${s.code}'] = {
        'name': s.name,
        'role': 'student',
        'teacher': toTeacher,
        'createdAt': DateTime.now().toIso8601String(),
      };
    }
    // الدروس: ننسخها إلى جدول المعلم الجديد ونحدّث حقل teacher
    for (final l in s.lessons) {
      final snap = await base.child('schedule/${l.id}').get();
      if (snap.value is Map) {
        final m = Map<String, dynamic>.from(snap.value as Map);
        m['teacher'] = toTeacher;
        m['transferredFrom'] = s.teacherCode;
        updates['users/$toTeacher/schedule/${l.id}'] = m;
        updates['users/${s.teacherCode}/schedule/${l.id}'] = null;
      }
    }
    await _db.update(updates);
    await _log('transfer_student', s.code,
        '${s.name}: ${teacher(s.teacherCode)?.name ?? s.teacherCode} ← ${teacher(toTeacher)?.name ?? toTeacher}');
  }

  Future<void> addPayment({
    required AdminStudent s,
    required double amount,
    required String payer,
    required String method,
    String note = '',
  }) async {
    await _db.child('users/${s.teacherCode}/payments/${s.code}').push().set({
      'amount': amount,
      'payer': payer,
      'method': method,
      'date': DateTime.now().toIso8601String(),
      if (note.isNotEmpty) 'note': note,
      'by': 'admin',
    });
    await _log('payment', s.code, '${s.name}: ${TimelineFormat.money(amount)} (${payer == 'teacher' ? 'إرجاع' : 'دفعة'})');
  }

  Future<void> deleteLesson(AdminLesson l) async {
    await _db.child('users/${l.teacherCode}/schedule/${l.id}').remove();
    await _log('delete_lesson', l.studentCode, TimelineFormat.ymd(l.start));
  }

  Future<void> updateLessonAmount(AdminLesson l, double amount) async {
    await _db.child('users/${l.teacherCode}/schedule/${l.id}').update({
      'amount': amount,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await _log('lesson_amount', l.studentCode, '${TimelineFormat.ymd(l.start)} → ${TimelineFormat.money(amount)}');
  }

  Future<void> saveSettings(PlatformSettings s) async {
    await _db.child('settings/platform').set(s.toMap());
    TimelineFormat.currency = s.currency;
    await _log('settings', 'platform');
  }

  Future<void> clearLog() async {
    await _db.child('adminLog').remove();
    await _log('clear_log', 'adminLog');
  }
}
