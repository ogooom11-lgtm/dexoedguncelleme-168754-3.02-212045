// lib/src/pages/admin/admin_sheets.dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/admin_repository.dart';
import '../../services/teacher_permissions.dart';
import '../../services/timeline_models.dart';
import '../../theme/app_theme.dart';
import '../student/student_sheets.dart' show showStudentSheet, showStudentConfirm;
import 'admin_widgets.dart';

export '../student/student_sheets.dart' show showStudentSheet, showStudentConfirm;

void adminToast(BuildContext context, String msg, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? AppTheme.danger : null,
      content: Text(msg, style: TextStyle(color: error ? Colors.white : null)),
    ));
}

/// ينفّذ إجراءً غير متزامن مع رسالة نجاح/فشل موحّدة. يعيد true عند النجاح.
Future<bool> runAdminAction(
  BuildContext context,
  Future<void> Function() action, {
  String success = 'تم بنجاح ✅',
}) async {
  try {
    await action();
    timelineHaptic(true, heavy: true);
    adminToast(context, success);
    return true;
  } catch (e) {
    adminToast(context, e.toString().replaceFirst('Exception: ', ''), error: true);
    return false;
  }
}

Widget _pad(Widget child) =>
    Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 18), child: child);

InputDecoration _dec(String label, IconData icon, {String? hint}) =>
    InputDecoration(labelText: label, hintText: hint, prefixIcon: Icon(icon));

// =====================================================================
// إنشاء معلم / مدير
// =====================================================================

Future<void> showCreateTeacherSheet(BuildContext context, AdminRepository repo) async {
  final name = TextEditingController();
  final code = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  var perms = TeacherPermissions.full;
  var busy = false;

  await showStudentSheet<void>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => _pad(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'إضافة معلم جديد', subtitle: 'سيُنشأ حساب بدور «معلم» ويمكنه الدخول بالكود مباشرة'),
          const SizedBox(height: 14),
          TextField(controller: name, textInputAction: TextInputAction.next, decoration: _dec('اسم المعلم', Icons.person_rounded)),
          const SizedBox(height: 10),
          TextField(
            controller: code,
            keyboardType: TextInputType.number,
            maxLength: 8,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _dec('الكود (8 أرقام)', Icons.key_rounded, hint: 'اتركه فارغاً للتوليد التلقائي').copyWith(
              counterText: '',
              suffixIcon: IconButton(
                tooltip: 'توليد',
                icon: const Icon(Icons.casino_rounded),
                onPressed: () async {
                  code.text = await repo.generateCode();
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: TextField(controller: phone, keyboardType: TextInputType.phone, textDirection: ui.TextDirection.ltr, decoration: _dec('الهاتف', Icons.phone_rounded))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: email, keyboardType: TextInputType.emailAddress, textDirection: ui.TextDirection.ltr, decoration: _dec('البريد', Icons.alternate_email_rounded))),
            ],
          ),
          const SizedBox(height: 14),
          SheetSection(
            title: 'الصلاحيات الابتدائية',
            icon: Icons.verified_user_rounded,
            child: Row(
              children: [
                Expanded(
                  child: PillChoice(
                    label: 'كاملة',
                    icon: Icons.lock_open_rounded,
                    selected: perms.isFull,
                    onTap: () => setS(() => perms = TeacherPermissions.full),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PillChoice(
                    label: 'مقيّدة',
                    icon: Icons.lock_rounded,
                    color: AppTheme.warning,
                    selected: !perms.isFull,
                    onTap: () => setS(() => perms = TeacherPermissions.restricted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () async {
                    if (name.text.trim().isEmpty) {
                      adminToast(ctx, 'أدخل اسم المعلم', error: true);
                      return;
                    }
                    setS(() => busy = true);
                    try {
                      final c = await repo.createTeacher(
                        name: name.text,
                        code: code.text,
                        email: email.text,
                        phone: phone.text,
                        permissions: perms.isFull ? null : perms,
                      );
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (!context.mounted) return;
                      await showCodeCreatedSheet(context, title: 'تم إنشاء حساب المعلم', name: name.text.trim(), code: c);
                    } catch (e) {
                      if (ctx.mounted) {
                        setS(() => busy = false);
                        adminToast(ctx, e.toString().replaceFirst('Exception: ', ''), error: true);
                      }
                    }
                  },
            icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('إنشاء الحساب'),
          ),
        ],
      )),
    ),
  );
}

Future<void> showCreateAdminSheet(BuildContext context, AdminRepository repo) async {
  final name = TextEditingController();
  final code = TextEditingController();
  var busy = false;
  await showStudentSheet<void>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => _pad(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'إضافة حساب إدارة', subtitle: 'سيحصل على كامل صلاحيات لوحة الإدارة'),
          const SizedBox(height: 14),
          TextField(controller: name, decoration: _dec('الاسم', Icons.person_rounded)),
          const SizedBox(height: 10),
          TextField(
            controller: code,
            keyboardType: TextInputType.number,
            maxLength: 8,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _dec('الكود (8 أرقام)', Icons.key_rounded, hint: 'اتركه فارغاً للتوليد').copyWith(counterText: ''),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: RoleColors.admin),
            onPressed: busy
                ? null
                : () async {
                    if (name.text.trim().isEmpty) return;
                    setS(() => busy = true);
                    try {
                      final c = await repo.createAdmin(name: name.text, code: code.text);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (!context.mounted) return;
                      await showCodeCreatedSheet(context, title: 'تم إنشاء حساب الإدارة', name: name.text.trim(), code: c);
                    } catch (e) {
                      if (ctx.mounted) {
                        setS(() => busy = false);
                        adminToast(ctx, e.toString().replaceFirst('Exception: ', ''), error: true);
                      }
                    }
                  },
            icon: const Icon(Icons.admin_panel_settings_rounded),
            label: const Text('إنشاء'),
          ),
        ],
      )),
    ),
  );
}

/// ورقة عرض الكود بعد الإنشاء مع نسخ.
Future<void> showCodeCreatedSheet(BuildContext context, {required String title, required String name, required String code}) {
  return showStudentSheet<void>(
    context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return _pad(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text(name, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          PressScale(
            onTap: () {
              Clipboard.setData(ClipboardData(text: code));
              adminToast(ctx, 'تم نسخ الكود');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.3), width: 1.5),
              ),
              child: Column(
                children: [
                  Text(code, textDirection: ui.TextDirection.ltr, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 6, color: scheme.primary)),
                  Text('اضغط للنسخ', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.check_rounded, size: 18), label: const Text('تم')),
        ],
      ));
    },
  );
}

// =====================================================================
// طالب: إضافة / تعديل / نقل
// =====================================================================

Future<void> showStudentFormSheet(
  BuildContext context,
  AdminRepository repo, {
  required String teacherCode,
  AdminStudent? existing,
}) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final code = TextEditingController();
  final rate = TextEditingController(
      text: existing != null
          ? (existing.hourlyRate == 0 ? '' : existing.hourlyRate.toStringAsFixed(existing.hourlyRate.truncateToDouble() == existing.hourlyRate ? 0 : 1))
          : (repo.settings.defaultHourlyRate > 0 ? repo.settings.defaultHourlyRate.toStringAsFixed(0) : ''));
  final email = TextEditingController(text: existing?.email ?? '');
  final phone = TextEditingController(text: existing?.phone ?? '');
  var gender = (existing?.gender.isNotEmpty ?? false) ? existing!.gender : 'male';
  var busy = false;
  final teacherName = repo.teacher(teacherCode)?.name ?? teacherCode;

  await showStudentSheet<void>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => _pad(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: existing == null ? 'إضافة طالب' : 'تعديل الطالب', subtitle: 'لدى المعلم: $teacherName'),
          const SizedBox(height: 14),
          TextField(controller: name, decoration: _dec('اسم الطالب', Icons.person_rounded)),
          if (existing == null) ...[
            const SizedBox(height: 10),
            TextField(
              controller: code,
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _dec('الكود (8 أرقام)', Icons.key_rounded, hint: 'اتركه فارغاً للتوليد').copyWith(counterText: ''),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: rate,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                  decoration: _dec('سعر الساعة', Icons.payments_rounded),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: PillChoice(label: 'ذكر', selected: gender == 'male', onTap: () => setS(() => gender = 'male'))),
                    const SizedBox(width: 6),
                    Expanded(child: PillChoice(label: 'أنثى', color: const Color(0xFFEC4899), selected: gender == 'female', onTap: () => setS(() => gender = 'female'))),
                  ],
                ),
              ),
            ],
          ),
          if (existing != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: TextField(controller: phone, keyboardType: TextInputType.phone, textDirection: ui.TextDirection.ltr, decoration: _dec('الهاتف', Icons.phone_rounded))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: email, keyboardType: TextInputType.emailAddress, textDirection: ui.TextDirection.ltr, decoration: _dec('البريد', Icons.alternate_email_rounded))),
              ],
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () async {
                    if (name.text.trim().isEmpty) {
                      adminToast(ctx, 'أدخل اسم الطالب', error: true);
                      return;
                    }
                    setS(() => busy = true);
                    final r = double.tryParse(rate.text.trim()) ?? 0;
                    try {
                      if (existing == null) {
                        final c = await repo.addStudent(teacherCode: teacherCode, name: name.text, code: code.text, hourlyRate: r, gender: gender);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!context.mounted) return;
                        await showCodeCreatedSheet(context, title: 'تمت إضافة الطالب', name: name.text.trim(), code: c);
                      } else {
                        await repo.updateStudent(teacherCode: teacherCode, code: existing.code, name: name.text, hourlyRate: r, gender: gender, email: email.text, phone: phone.text);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        adminToast(context, 'تم حفظ بيانات الطالب ✅');
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        setS(() => busy = false);
                        adminToast(ctx, e.toString().replaceFirst('Exception: ', ''), error: true);
                      }
                    }
                  },
            icon: Icon(existing == null ? Icons.person_add_alt_1_rounded : Icons.save_rounded),
            label: Text(existing == null ? 'إضافة' : 'حفظ'),
          ),
        ],
      )),
    ),
  );
}

Future<void> showTransferStudentSheet(BuildContext context, AdminRepository repo, AdminStudent s) async {
  final targets = repo.teachers.where((t) => t.code != s.teacherCode).toList();
  if (targets.isEmpty) {
    adminToast(context, 'لا يوجد معلم آخر للنقل إليه', error: true);
    return;
  }
  String? chosen;
  await showStudentSheet<void>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final scheme = Theme.of(ctx).colorScheme;
        return _pad(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: 'نقل ${s.name} إلى معلم آخر', subtitle: 'تُنقل الدروس والدفعات وسجل الطالب بالكامل'),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final t in targets)
                    PressScale(
                      onTap: () => setS(() => chosen = t.code),
                      scale: 0.98,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: chosen == t.code ? scheme.primary.withValues(alpha: 0.1) : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: chosen == t.code ? scheme.primary : Colors.transparent, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            InitialAvatar(name: t.name, color: teacherHue(t.code), size: 36),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                                  Text('${t.students.length} طالب • ${t.code}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            if (chosen == t.code) Icon(Icons.check_circle_rounded, color: scheme.primary),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: chosen == null
                  ? null
                  : () async {
                      final ok = await showStudentConfirm(
                        ctx,
                        title: 'تأكيد النقل',
                        message: 'سيُنقل ${s.name} مع ${s.lessons.length} درس و${s.payments.length} دفعة إلى ${repo.teacher(chosen!)?.name ?? ''}.',
                        confirmLabel: 'نقل',
                        icon: Icons.swap_horiz_rounded,
                      );
                      if (!ok || !ctx.mounted) return;
                      final done = await runAdminAction(context, () => repo.transferStudent(s, chosen!), success: 'تم نقل الطالب ✅');
                      if (done && ctx.mounted) Navigator.pop(ctx);
                    },
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('نقل الطالب'),
            ),
          ],
        ));
      },
    ),
  );
}

// =====================================================================
// دفعة يدوية من الإدارة
// =====================================================================

Future<void> showAdminPaymentSheet(BuildContext context, AdminRepository repo, AdminStudent s) async {
  final amount = TextEditingController(text: s.owes ? s.balance.toStringAsFixed(0) : '');
  final note = TextEditingController();
  var payer = 'student';
  var method = 'cash';
  var busy = false;
  await showStudentSheet<void>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => _pad(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: 'تسجيل دفعة — ${s.name}', subtitle: 'الرصيد الحالي: ${TimelineFormat.money(s.balance)}'),
          const SizedBox(height: 14),
          TextField(
            controller: amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
            decoration: _dec('المبلغ', Icons.payments_rounded),
          ),
          const SizedBox(height: 12),
          SheetSection(
            title: 'النوع',
            child: Row(
              children: [
                Expanded(child: PillChoice(label: 'دفعة من الطالب', icon: Icons.arrow_upward_rounded, color: AppTheme.success, selected: payer == 'student', onTap: () => setS(() => payer = 'student'))),
                const SizedBox(width: 8),
                Expanded(child: PillChoice(label: 'إرجاع للطالب', icon: Icons.arrow_downward_rounded, color: const Color(0xFFF97316), selected: payer == 'teacher', onTap: () => setS(() => payer = 'teacher'))),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SheetSection(
            title: 'الطريقة',
            child: Row(
              children: [
                Expanded(child: PillChoice(label: 'نقداً', icon: Icons.money_rounded, selected: method == 'cash', onTap: () => setS(() => method = 'cash'))),
                const SizedBox(width: 8),
                Expanded(child: PillChoice(label: 'تحويل', icon: Icons.account_balance_rounded, selected: method == 'bank', onTap: () => setS(() => method = 'bank'))),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(controller: note, decoration: _dec('ملاحظة (اختياري)', Icons.sticky_note_2_outlined)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final a = double.tryParse(amount.text.trim()) ?? 0;
                    if (a <= 0) {
                      adminToast(ctx, 'أدخل مبلغاً صحيحاً', error: true);
                      return;
                    }
                    setS(() => busy = true);
                    final ok = await runAdminAction(context, () => repo.addPayment(s: s, amount: a, payer: payer, method: method, note: note.text.trim()), success: 'تم تسجيل الدفعة ✅');
                    if (ctx.mounted) {
                      if (ok) {
                        Navigator.pop(ctx);
                      } else {
                        setS(() => busy = false);
                      }
                    }
                  },
            icon: const Icon(Icons.check_rounded),
            label: const Text('تسجيل'),
          ),
        ],
      )),
    ),
  );
}

// =====================================================================
// الصلاحيات
// =====================================================================

Future<void> showPermissionsSheet(BuildContext context, AdminRepository repo, AdminTeacher t) async {
  var p = t.permissions;
  var dirty = false;
  await showStudentSheet<void>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final scheme = Theme.of(ctx).colorScheme;
        return _pad(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(
              title: 'صلاحيات ${t.name}',
              subtitle: p.isFull ? 'كل الصلاحيات ممنوحة' : '${p.deniedCount} صلاحية محجوبة',
              trailing: TextButton(
                onPressed: () => setS(() {
                  p = p.isFull ? TeacherPermissions.restricted : TeacherPermissions.full;
                  dirty = true;
                }),
                child: Text(p.isFull ? 'حجب الكل' : 'منح الكل'),
              ),
            ),
            const SizedBox(height: 8),
            for (final perm in TeacherPermission.values)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SwitchListTile.adaptive(
                  dense: true,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  secondary: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: (p.allows(perm) ? scheme.primary : scheme.outline).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(perm.icon, size: 18, color: p.allows(perm) ? scheme.primary : scheme.outline),
                  ),
                  title: Text(perm.label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                  subtitle: Text(perm.description, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  value: p.allows(perm),
                  onChanged: (v) => setS(() {
                    p = p.copyWith(perm, v);
                    dirty = true;
                  }),
                ),
              ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: !dirty
                  ? null
                  : () async {
                      final ok = await runAdminAction(context, () => repo.setPermissions(t.code, p, name: t.name), success: 'تم حفظ الصلاحيات ✅');
                      if (ok && ctx.mounted) Navigator.pop(ctx);
                    },
              icon: const Icon(Icons.save_rounded),
              label: const Text('حفظ الصلاحيات'),
            ),
          ],
        ));
      },
    ),
  );
}

// =====================================================================
// تعديل حقل نصي
// =====================================================================

Future<String?> showEditFieldSheet(
  BuildContext context, {
  required String title,
  required String label,
  required String value,
  IconData icon = Icons.edit_rounded,
  TextInputType? keyboard,
  bool ltr = false,
}) {
  final c = TextEditingController(text: value);
  return showStudentSheet<String>(
    context,
    builder: (ctx) => _pad(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title: title),
        const SizedBox(height: 14),
        TextField(
          controller: c,
          autofocus: true,
          keyboardType: keyboard,
          textDirection: ltr ? ui.TextDirection.ltr : null,
          decoration: _dec(label, icon),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(onPressed: () => Navigator.pop(ctx, c.text.trim()), icon: const Icon(Icons.save_rounded), label: const Text('حفظ')),
      ],
    )),
  );
}

// =====================================================================
// تفاصيل درس (إدارة)
// =====================================================================

Future<void> showAdminLessonSheet(BuildContext context, AdminRepository repo, AdminLesson l, {String? studentName, String? teacherName}) async {
  final action = await showStudentSheet<String>(
    context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final color = l.status.color;
      return _pad(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
                child: Icon(l.status.icon, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(TimelineFormat.fullDate(l.start), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    Text('${studentName ?? l.studentCode}${teacherName != null ? ' • $teacherName' : ''}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              StatusChip(status: l.status),
            ],
          ),
          const SizedBox(height: 14),
          InfoRow(icon: Icons.schedule_rounded, label: 'الوقت', value: TimelineFormat.range(l.start, l.end, use24h: false)),
          InfoRow(icon: Icons.hourglass_bottom_rounded, label: 'المدة', value: TimelineFormat.duration(l.minutes)),
          if (l.isEnded) InfoRow(icon: Icons.payments_rounded, label: 'المبلغ', value: TimelineFormat.money(l.amount), color: AppTheme.success),
          if (l.note.isNotEmpty) InfoRow(icon: Icons.sticky_note_2_outlined, label: 'ملاحظة', value: l.note),
          const SizedBox(height: 12),
          Row(
            children: [
              if (l.isEnded)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'amount'),
                    icon: const Icon(Icons.price_change_rounded, size: 18),
                    label: const Text('تعديل المبلغ'),
                  ),
                ),
              if (l.isEnded) const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
                  onPressed: () => Navigator.pop(ctx, 'delete'),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('حذف الدرس'),
                ),
              ),
            ],
          ),
        ],
      ));
    },
  );
  if (!context.mounted || action == null) return;
  if (action == 'amount') {
    final v = await showEditFieldSheet(context, title: 'تعديل مبلغ الدرس', label: 'المبلغ', value: l.amount.toStringAsFixed(0), icon: Icons.payments_rounded, keyboard: const TextInputType.numberWithOptions(decimal: true));
    final a = double.tryParse(v ?? '');
    if (a == null || !context.mounted) return;
    await runAdminAction(context, () => repo.updateLessonAmount(l, a), success: 'تم تعديل المبلغ ✅');
  } else if (action == 'delete') {
    final ok = await showStudentConfirm(context, title: 'حذف الدرس؟', message: 'سيُحذف الدرس نهائياً من سجل المعلم.', confirmLabel: 'حذف', icon: Icons.delete_forever_rounded, color: AppTheme.danger);
    if (ok && context.mounted) {
      await runAdminAction(context, () => repo.deleteLesson(l), success: 'تم حذف الدرس');
    }
  }
}
