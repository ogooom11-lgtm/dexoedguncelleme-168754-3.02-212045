// lib/src/pages/admin/admin_student_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/admin_repository.dart';
import '../../services/timeline_models.dart';
import '../../theme/app_theme.dart';
import 'admin_sheets.dart';
import 'admin_widgets.dart';

/// 🎓 صفحة طالب من منظور الإدارة: الرصيد، الدروس، الدفعات، والإجراءات.
class AdminStudentPage extends StatefulWidget {
  const AdminStudentPage({super.key, required this.studentCode});
  final String studentCode;

  @override
  State<AdminStudentPage> createState() => _AdminStudentPageState();
}

class _AdminStudentPageState extends State<AdminStudentPage> {
  int _tab = 0;

  Future<void> _menu(AdminStudent s, AdminRepository repo) async {
    final action = await showStudentSheet<String>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: s.name, subtitle: 'الكود ${s.code}'),
            const SizedBox(height: 8),
            _tile(ctx, Icons.edit_rounded, 'تعديل البيانات', 'edit'),
            _tile(ctx, Icons.payments_rounded, 'تسجيل دفعة / إرجاع', 'pay'),
            _tile(ctx, Icons.swap_horiz_rounded, 'نقل إلى معلم آخر', 'transfer'),
            if (!s.linked) _tile(ctx, Icons.link_rounded, 'تفعيل الدخول (إنشاء سجل)', 'link', color: AppTheme.success),
            _tile(ctx, Icons.copy_rounded, 'نسخ الكود', 'copy'),
            if (s.linked)
              _tile(ctx, s.disabled ? Icons.lock_open_rounded : Icons.block_rounded, s.disabled ? 'تفعيل الحساب' : 'تعطيل الحساب', 'toggle', color: s.disabled ? AppTheme.success : AppTheme.warning),
            _tile(ctx, Icons.delete_forever_rounded, 'حذف الطالب', 'delete', color: AppTheme.danger),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'edit':
        await showStudentFormSheet(context, repo, teacherCode: s.teacherCode, existing: s);
      case 'pay':
        await showAdminPaymentSheet(context, repo, s);
      case 'transfer':
        await showTransferStudentSheet(context, repo, s);
      case 'link':
        await runAdminAction(context, () => repo.linkStudent(s), success: 'أصبح بإمكان الطالب الدخول ✅');
      case 'copy':
        await Clipboard.setData(ClipboardData(text: s.code));
        adminToast(context, 'تم نسخ الكود');
      case 'toggle':
        await runAdminAction(context, () => repo.setDisabled(s.code, !s.disabled, name: s.name));
      case 'delete':
        await _delete(s, repo);
    }
  }

  Future<void> _delete(AdminStudent s, AdminRepository repo) async {
    final hasBalance = s.balance.abs() > 0.5;
    var force = false;
    final ok = await showStudentSheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final scheme = Theme.of(ctx).colorScheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 64, height: 64, alignment: Alignment.center, decoration: BoxDecoration(color: AppTheme.danger.withValues(alpha: 0.12), shape: BoxShape.circle), child: const Icon(Icons.delete_forever_rounded, color: AppTheme.danger, size: 32)),
                const SizedBox(height: 12),
                Text('حذف ${s.name}؟', textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  hasBalance ? 'رصيد الطالب ${TimelineFormat.money(s.balance)} وليس صفراً.' : 'سيُحذف الطالب ودفعاته وسجل دخوله.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(color: AppTheme.danger.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14)),
                  child: SwitchListTile.adaptive(
                    dense: true,
                    title: const Text('حذف قسري', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                    subtitle: Text('يتجاهل الرصيد ويحذف ${s.lessons.length} درس أيضاً', style: const TextStyle(fontSize: 11)),
                    value: force,
                    onChanged: (v) => setS(() => force = v),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع'))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
                        onPressed: (hasBalance && repo.settings.requireZeroBalanceToDelete && !force) ? null : () => Navigator.pop(ctx, true),
                        child: const Text('حذف'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    final done = await runAdminAction(context, () => repo.deleteStudent(s, force: force), success: 'تم حذف الطالب');
    if (done && mounted) Navigator.pop(context);
  }

  Widget _tile(BuildContext ctx, IconData icon, String label, String v, {Color? color}) {
    final scheme = Theme.of(ctx).colorScheme;
    final c = color ?? scheme.onSurface;
    return ListTile(
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 18, color: c)),
      title: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c)),
      trailing: Icon(Icons.chevron_left_rounded, color: scheme.outline),
      onTap: () => Navigator.pop(ctx, v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AdminRepository>();
    final s = repo.student(widget.studentCode);
    final scheme = Theme.of(context).colorScheme;
    if (s == null) {
      return Scaffold(appBar: AppBar(), body: const TimelineEmptyState(icon: Icons.person_off_rounded, title: 'الطالب غير موجود'));
    }
    final t = repo.teacher(s.teacherCode);
    final tone = balanceTone(s.balance);
    final color = s.gender == 'female' ? const Color(0xFFEC4899) : RoleColors.student;
    final coverage = s.lessonsTotal <= 0 ? 1.0 : ((s.paid - s.returned) / s.lessonsTotal).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.name),
        actions: [IconButton(onPressed: () => _menu(s, repo), icon: const Icon(Icons.more_horiz_rounded))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        physics: const BouncingScrollPhysics(),
        children: [
          StaggeredReveal(
            index: 0,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [tone.color, Color.lerp(tone.color, Colors.black, 0.25)!], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                boxShadow: [BoxShadow(color: tone.color.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      InitialAvatar(name: s.name, color: color, size: 52, disabled: s.disabled),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Tag(label: 'طالب', color: Colors.white, icon: Icons.school_rounded),
                                const SizedBox(width: 6),
                                if (s.disabled) const Tag(label: 'معطّل', color: Colors.white, icon: Icons.block_rounded),
                                if (!s.linked) const Tag(label: 'لا يستطيع الدخول', color: Colors.white, icon: Icons.link_off_rounded),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('الكود ${s.code} • ${TimelineFormat.money(s.hourlyRate)}/ساعة', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5)),
                            if (t != null) Text('المعلم: ${t.name}', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(tone.icon, color: Colors.white.withValues(alpha: 0.9), size: 18),
                      const SizedBox(width: 6),
                      Text(tone.label, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  AnimatedNumber(value: s.balance.abs(), style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, height: 1.1)),
                  const SizedBox(height: 12),
                  ProgressBar(value: coverage, color: Colors.white, background: Colors.white.withValues(alpha: 0.25), height: 6),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _cell('إجمالي الدروس', TimelineFormat.money(s.lessonsTotal)),
                      _cell('المدفوع', TimelineFormat.money(s.paid)),
                      _cell(s.returned > 0 ? 'المُرجَع' : 'الدروس', s.returned > 0 ? TimelineFormat.money(s.returned) : '${s.endedCount}'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          StaggeredReveal(
            index: 1,
            child: Row(
              children: [
                _Quick(icon: Icons.payments_rounded, label: 'دفعة', color: AppTheme.success, onTap: () => showAdminPaymentSheet(context, repo, s)),
                const SizedBox(width: 8),
                _Quick(icon: Icons.edit_rounded, label: 'تعديل', color: scheme.primary, onTap: () => showStudentFormSheet(context, repo, teacherCode: s.teacherCode, existing: s)),
                const SizedBox(width: 8),
                _Quick(icon: Icons.swap_horiz_rounded, label: 'نقل', color: const Color(0xFF06B6D4), onTap: () => showTransferStudentSheet(context, repo, s)),
                const SizedBox(width: 8),
                _Quick(icon: Icons.copy_rounded, label: 'الكود', color: const Color(0xFF8B5CF6), onTap: () {
                  Clipboard.setData(ClipboardData(text: s.code));
                  adminToast(context, 'تم نسخ الكود');
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Segmented<int>(
            value: _tab,
            onChanged: (v) => setState(() => _tab = v),
            items: [
              (value: 0, label: 'الدروس ${s.lessons.length}', icon: Icons.menu_book_rounded),
              (value: 1, label: 'الدفعات ${s.payments.length}', icon: Icons.receipt_long_rounded),
              (value: 2, label: 'معلومات', icon: Icons.info_outline_rounded),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: switch (_tab) {
              0 => Column(
                  key: const ValueKey(0),
                  children: [
                    if (s.lessons.isEmpty)
                      const TimelineEmptyState(icon: Icons.event_busy_rounded, title: 'لا توجد دروس')
                    else
                      for (final (i, l) in s.lessons.take(120).indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: StaggeredReveal(index: i, child: LessonRow(lesson: l, onTap: () => showAdminLessonSheet(context, repo, l, studentName: s.name, teacherName: t?.name))),
                        ),
                  ],
                ),
              1 => Column(
                  key: const ValueKey(1),
                  children: [
                    if (s.payments.isEmpty)
                      const TimelineEmptyState(icon: Icons.receipt_long_outlined, title: 'لا توجد دفعات')
                    else
                      for (final (i, p) in s.payments.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: StaggeredReveal(index: i, child: _PaymentRow(p: p)),
                        ),
                  ],
                ),
              _ => SoftCard(
                  key: const ValueKey(2),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Column(
                    children: [
                      InfoRow(icon: Icons.person_rounded, label: 'الجنس', value: s.gender == 'female' ? 'أنثى' : 'ذكر'),
                      InfoRow(icon: Icons.phone_rounded, label: 'الهاتف', value: s.phone.isEmpty ? 'غير مضاف' : s.phone),
                      InfoRow(icon: Icons.alternate_email_rounded, label: 'البريد', value: s.email.isEmpty ? 'غير مضاف' : s.email),
                      InfoRow(icon: Icons.event_rounded, label: 'تاريخ الإضافة', value: s.createdAt == null ? '—' : TimelineFormat.fullDate(s.createdAt!)),
                      InfoRow(icon: Icons.history_rounded, label: 'آخر درس', value: s.lastLessonAt == null ? '—' : TimelineFormat.relativeDay(s.lastLessonAt!)),
                      InfoRow(icon: Icons.timer_outlined, label: 'إجمالي الوقت', value: TimelineFormat.duration(s.minutes)),
                      InfoRow(icon: Icons.login_rounded, label: 'سجل الدخول', value: s.linked ? 'موجود' : 'غير موجود', color: s.linked ? AppTheme.success : AppTheme.warning),
                    ],
                  ),
                ),
            },
          ),
        ],
      ),
    );
  }

  Widget _cell(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800))),
            Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 10.5)),
          ],
        ),
      );
}

class _Quick extends StatelessWidget {
  const _Quick({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: PressScale(
        onTap: () {
          timelineHaptic(true);
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppTheme.radiusMd), border: Border.all(color: color.withValues(alpha: 0.2))),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.p});
  final AdminPayment p;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = p.fromStudent ? AppTheme.success : const Color(0xFFF97316);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Icon(p.fromStudent ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, color: color, size: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.fromStudent ? 'دفعة من الطالب' : 'إرجاع من المعلم', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                Text('${p.date == null ? '—' : TimelineFormat.fullDate(p.date!)} • ${p.method == 'bank' ? 'تحويل' : 'نقداً'}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Text('${p.fromStudent ? '+' : '−'}${TimelineFormat.money(p.amount)}', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }
}
