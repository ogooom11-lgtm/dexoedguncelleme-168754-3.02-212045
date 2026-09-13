// lib/src/services/teacher_permissions.dart
//
// 🔐 صلاحيات المعلم التي تتحكم بها الإدارة.
// تُخزَّن في `users/$teacherCode/permissions` وتُقرأ عند المعلم عبر
// `TeacherPermissions.watch(code)`. القيمة الافتراضية لكل صلاحية = مسموح.

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

enum TeacherPermission {
  addStudents,
  deleteStudents,
  editRates,
  recordPayments,
  deleteLessons,
  recurringSchedules,
  exportPdf,
  editProfile,
}

extension TeacherPermissionX on TeacherPermission {
  String get key => name;

  String get label => switch (this) {
        TeacherPermission.addStudents => 'إضافة طلاب',
        TeacherPermission.deleteStudents => 'حذف طلاب',
        TeacherPermission.editRates => 'تعديل سعر الساعة',
        TeacherPermission.recordPayments => 'تسجيل الدفعات',
        TeacherPermission.deleteLessons => 'حذف الدروس',
        TeacherPermission.recurringSchedules => 'المواعيد المتكررة',
        TeacherPermission.exportPdf => 'تصدير التقارير PDF',
        TeacherPermission.editProfile => 'تعديل الملف الشخصي',
      };

  String get description => switch (this) {
        TeacherPermission.addStudents => 'يستطيع إنشاء حسابات طلاب جديدة.',
        TeacherPermission.deleteStudents => 'يستطيع حذف طلابه (بشرط تصفية الرصيد).',
        TeacherPermission.editRates => 'يستطيع تغيير سعر الساعة للطلاب.',
        TeacherPermission.recordPayments => 'يستطيع تسجيل دفعات الطلاب وإرجاع المبالغ.',
        TeacherPermission.deleteLessons => 'يستطيع حذف الدروس من السجل.',
        TeacherPermission.recurringSchedules => 'يستطيع إنشاء وإدارة المواعيد المتكررة.',
        TeacherPermission.exportPdf => 'يستطيع تصدير كشوفات PDF.',
        TeacherPermission.editProfile => 'يستطيع تعديل اسمه وبريده وهاتفه.',
      };

  IconData get icon => switch (this) {
        TeacherPermission.addStudents => Icons.person_add_alt_1_rounded,
        TeacherPermission.deleteStudents => Icons.person_remove_alt_1_rounded,
        TeacherPermission.editRates => Icons.price_change_rounded,
        TeacherPermission.recordPayments => Icons.payments_rounded,
        TeacherPermission.deleteLessons => Icons.delete_sweep_rounded,
        TeacherPermission.recurringSchedules => Icons.repeat_rounded,
        TeacherPermission.exportPdf => Icons.picture_as_pdf_rounded,
        TeacherPermission.editProfile => Icons.manage_accounts_rounded,
      };
}

class TeacherPermissions {
  final Map<TeacherPermission, bool> _values;

  const TeacherPermissions._(this._values);

  /// الكل مسموح.
  static const TeacherPermissions full = TeacherPermissions._({});

  /// حساب مقيّد: عرض فقط + تسجيل الدروس.
  static TeacherPermissions get restricted => TeacherPermissions._({
        for (final p in TeacherPermission.values) p: false,
      });

  factory TeacherPermissions.fromMap(Map<String, dynamic>? m) {
    if (m == null) return full;
    final out = <TeacherPermission, bool>{};
    for (final p in TeacherPermission.values) {
      final v = m[p.key];
      if (v is bool) out[p] = v;
    }
    return TeacherPermissions._(out);
  }

  Map<String, dynamic> toMap() => {
        for (final p in TeacherPermission.values) p.key: allows(p),
      };

  bool allows(TeacherPermission p) => _values[p] ?? true;

  TeacherPermissions copyWith(TeacherPermission p, bool value) =>
      TeacherPermissions._({..._values, p: value});

  int get deniedCount =>
      TeacherPermission.values.where((p) => !allows(p)).length;
  bool get isFull => deniedCount == 0;

  /// بث لحظي لصلاحيات معلم — للاستخدام من واجهة المعلم.
  static Stream<TeacherPermissions> watch(String teacherCode) {
    return FirebaseDatabase.instance
        .ref('users/$teacherCode/permissions')
        .onValue
        .map((e) {
      final v = e.snapshot.value;
      return TeacherPermissions.fromMap(
          v is Map ? Map<String, dynamic>.from(v) : null);
    });
  }

  static Future<TeacherPermissions> fetch(String teacherCode) async {
    final snap = await FirebaseDatabase.instance
        .ref('users/$teacherCode/permissions')
        .get();
    final v = snap.value;
    return TeacherPermissions.fromMap(
        v is Map ? Map<String, dynamic>.from(v) : null);
  }
}
