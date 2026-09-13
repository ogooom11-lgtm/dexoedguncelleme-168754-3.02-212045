// lib/src/pages/student/student_sheets.dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/student_repository.dart';
import '../../services/timeline_models.dart';
import '../../theme/app_theme.dart';
import 'student_widgets.dart';

Future<T?> showStudentSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(child: builder(ctx)),
      ),
    ),
  );
}

// =====================================================================
// تفاصيل درس
// =====================================================================

Future<void> showStudentLessonSheet(
  BuildContext context, {
  required StudentLesson lesson,
  required StudentRepository repo,
  bool use24h = false,
}) async {
  final action = await showStudentSheet<String>(
    context,
    builder: (ctx) => _LessonSheet(lesson: lesson, use24h: use24h, teacherName: repo.teacherName),
  );
  if (action == 'withdraw' && context.mounted) {
    final ok = await showStudentConfirm(
      context,
      title: 'سحب الطلب؟',
      message: 'سيتم حذف طلب الموعد قبل موافقة المعلم.',
      confirmLabel: 'سحب الطلب',
      icon: Icons.undo_rounded,
      color: AppTheme.danger,
    );
    if (ok && context.mounted) {
      try {
        await repo.withdrawRequest(lesson);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم سحب الطلب')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: AppTheme.danger, content: Text('تعذر سحب الطلب: $e')),
          );
        }
      }
    }
  }
}

class _LessonSheet extends StatelessWidget {
  const _LessonSheet({required this.lesson, required this.use24h, required this.teacherName});
  final StudentLesson lesson;
  final bool use24h;
  final String teacherName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = lesson.status;
    final color = status.color;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.05)],
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
                  child: Icon(status.icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(TimelineFormat.fullDate(lesson.start), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        'مع ${teacherName.isEmpty ? 'المعلم' : teacherName}',
                        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                StatusChip(status: status),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _Info(icon: Icons.schedule_rounded, label: 'الوقت', value: TimelineFormat.range(lesson.start, lesson.end, use24h: use24h))),
              const SizedBox(width: 8),
              Expanded(child: _Info(icon: Icons.hourglass_bottom_rounded, label: 'المدة', value: TimelineFormat.duration(lesson.minutes))),
              if (lesson.isEnded) ...[
                const SizedBox(width: 8),
                Expanded(child: _Info(icon: Icons.payments_rounded, label: 'المبلغ', value: TimelineFormat.money(lesson.amount))),
              ],
            ],
          ),
          if (lesson.isEnded) ...[
            const SizedBox(height: 10),
            _Line(
              icon: lesson.isPaid ? Icons.verified_rounded : Icons.error_outline_rounded,
              text: lesson.isPaid ? 'هذا الدرس مسدَّد ضمن دفعاتك' : 'هذا الدرس لم يُغطَّ بعد بدفعاتك',
              color: lesson.isPaid ? AppTheme.success : AppTheme.danger,
            ),
          ],
          if (lesson.note.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Line(icon: Icons.sticky_note_2_outlined, text: lesson.note, color: scheme.primary),
          ],
          if (lesson.cancelReason.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Line(icon: Icons.info_outline_rounded, text: 'سبب الإلغاء: ${lesson.cancelReason}', color: AppTheme.danger),
          ],
          if (lesson.isPending) ...[
            const SizedBox(height: 10),
            _Line(icon: Icons.hourglass_top_rounded, text: 'طلبك بانتظار موافقة المعلم. ستظهر الحالة هنا فور الرد.', color: TimelineStatus.pending.color),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
              onPressed: () => Navigator.pop(context, 'withdraw'),
              icon: const Icon(Icons.undo_rounded),
              label: const Text('سحب الطلب'),
            ),
          ],
          if (lesson.isUpcoming) ...[
            const SizedBox(height: 10),
            _Line(icon: Icons.notifications_active_outlined, text: _countdown(lesson.start), color: scheme.primary),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final text = 'درس ${TimelineFormat.fullDate(lesson.start)} • ${TimelineFormat.range(lesson.start, lesson.end, use24h: use24h)} (${TimelineFormat.duration(lesson.minutes)}) • ${status.label}${lesson.isEnded ? ' • ${TimelineFormat.money(lesson.amount)}' : ''}';
                    Clipboard.setData(ClipboardData(text: text));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ تفاصيل الدرس')));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('نسخ'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('حسناً'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _countdown(DateTime start) {
    final diff = start.difference(DateTime.now());
    if (diff.inDays >= 1) return 'يبدأ بعد ${diff.inDays} ${diff.inDays == 1 ? 'يوم' : 'أيام'} و ${diff.inHours % 24} ساعة';
    if (diff.inHours >= 1) return 'يبدأ بعد ${diff.inHours} ساعة و ${diff.inMinutes % 60} دقيقة';
    return 'يبدأ بعد ${diff.inMinutes} دقيقة';
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, maxLines: 1, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800))),
          Text(label, style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppTheme.radiusSm)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: color, height: 1.5))),
        ],
      ),
    );
  }
}

// =====================================================================
// تفاصيل دفعة
// =====================================================================

Future<void> showStudentPaymentSheet(BuildContext context, {required StudentPayment payment}) {
  return showStudentSheet<void>(
    context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      final color = payment.fromStudent ? AppTheme.success : const Color(0xFFF97316);
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              height: 70,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(payment.fromStudent ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, color: color, size: 34),
            ),
            const SizedBox(height: 12),
            Text(
              '${payment.fromStudent ? '+' : '−'}${TimelineFormat.money(payment.amount)}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color),
            ),
            Text(
              payment.fromStudent ? 'دفعة مسدّدة' : 'مبلغ مُرجَع من المعلم',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            InfoRow(icon: Icons.event_rounded, label: 'التاريخ', value: payment.date == null ? '—' : '${TimelineFormat.fullDate(payment.date!)} • ${TimelineFormat.time(payment.date!, use24h: false)}'),
            InfoRow(icon: Icons.account_balance_wallet_rounded, label: 'طريقة الدفع', value: payment.methodLabel, color: color),
            if (payment.note.isNotEmpty) InfoRow(icon: Icons.sticky_note_2_outlined, label: 'ملاحظة', value: payment.note, color: scheme.tertiary),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('حسناً'),
            ),
          ],
        ),
      );
    },
  );
}

// =====================================================================
// تأكيد عام
// =====================================================================

Future<bool> showStudentConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required IconData icon,
  Color? color,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final c = color ?? scheme.primary;
  final r = await showStudentSheet<bool>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: c, size: 32),
          ),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: c), onPressed: () => Navigator.pop(ctx, true), child: Text(confirmLabel))),
            ],
          ),
        ],
      ),
    ),
  );
  return r ?? false;
}

// =====================================================================
// تعديل بيانات التواصل
// =====================================================================

Future<({String email, String phone})?> showEditContactSheet(
  BuildContext context, {
  required String email,
  required String phone,
}) {
  final e = TextEditingController(text: email);
  final p = TextEditingController(text: phone);
  return showStudentSheet<({String email, String phone})>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'بيانات التواصل', subtitle: 'اختيارية — تساعد المعلم على التواصل معك'),
          const SizedBox(height: 14),
          TextField(
            controller: p,
            keyboardType: TextInputType.phone,
            textDirection: ui.TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone_rounded)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: e,
            keyboardType: TextInputType.emailAddress,
            textDirection: ui.TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.alternate_email_rounded)),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, (email: e.text.trim(), phone: p.text.trim())),
            icon: const Icon(Icons.save_rounded),
            label: const Text('حفظ'),
          ),
        ],
      ),
    ),
  );
}

// =====================================================================
// كشف حساب — مشاركة نصية
// =====================================================================

Future<void> shareStatement(BuildContext context, StudentRepository repo) async {
  final f = repo.finance;
  final b = StringBuffer();
  b.writeln('📋 كشف حساب — ${repo.studentName}');
  if (repo.teacherName.isNotEmpty) b.writeln('👨‍🏫 المعلم: ${repo.teacherName}');
  b.writeln('📅 ${TimelineFormat.fullDate(DateTime.now())}');
  b.writeln('');
  b.writeln('📚 الدروس المنتهية: ${repo.endedLessons.length} (${TimelineFormat.duration(repo.totalMinutesLearned)})');
  b.writeln('💰 إجمالي الدروس: ${TimelineFormat.money(f.lessonsTotal)}');
  b.writeln('✅ المدفوع: ${TimelineFormat.money(f.paid)}');
  if (f.returned > 0) b.writeln('↩️ المُرجَع: ${TimelineFormat.money(f.returned)}');
  b.writeln(f.balance > 0.5
      ? '🔴 المستحق عليك: ${TimelineFormat.money(f.balance)}'
      : f.balance < -0.5
          ? '🟢 رصيد زائد لك: ${TimelineFormat.money(-f.balance)}'
          : '🟢 الحساب مسدّد بالكامل');
  final unpaid = repo.unpaidLessons;
  if (unpaid.isNotEmpty) {
    b.writeln('');
    b.writeln('الدروس غير المدفوعة:');
    for (final l in unpaid.take(15)) {
      b.writeln('• ${TimelineFormat.ymd(l.start)} — ${TimelineFormat.duration(l.minutes)} — ${TimelineFormat.money(l.amount)}');
    }
    if (unpaid.length > 15) b.writeln('… و ${unpaid.length - 15} دروس أخرى');
  }
  await Share.share(b.toString());
}
