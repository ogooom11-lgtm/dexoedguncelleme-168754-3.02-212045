// lib/src/pages/admin/admin_settings_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/admin_repository.dart';
import '../../services/timeline_models.dart';
import '../../theme/app_theme.dart';
import 'admin_sheets.dart';
import 'admin_widgets.dart';

/// ⚙️ الإعدادات: إعدادات المنصة، الإعلان، سجل الإجراءات، المظهر، الحساب.
class AdminSettingsTab extends StatefulWidget {
  const AdminSettingsTab({super.key});

  @override
  State<AdminSettingsTab> createState() => _AdminSettingsTabState();
}

class _AdminSettingsTabState extends State<AdminSettingsTab> {
  PlatformSettings? _draft;
  bool _saving = false;

  PlatformSettings _s(AdminRepository repo) => _draft ?? repo.settings;

  void _set(PlatformSettings s) => setState(() => _draft = s);

  Future<void> _save(AdminRepository repo) async {
    if (_draft == null) return;
    setState(() => _saving = true);
    final ok = await runAdminAction(context, () => repo.saveSettings(_draft!), success: 'تم حفظ الإعدادات ✅');
    if (mounted) {
      setState(() {
        _saving = false;
        if (ok) _draft = null;
      });
    }
  }

  Future<void> _editAnnouncement(AdminRepository repo) async {
    final s = _s(repo);
    final c = TextEditingController(text: s.announcement);
    var teachers = s.announcementForTeachers;
    var students = s.announcementForStudents;
    final r = await showStudentSheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHeader(title: 'إعلان عام', subtitle: 'يظهر كشريط في أعلى الرئيسية عند المعلمين/الطلاب'),
              const SizedBox(height: 12),
              TextField(controller: c, maxLines: 3, minLines: 2, decoration: const InputDecoration(hintText: 'مثال: سيتوقف التطبيق للصيانة يوم الجمعة من 2 إلى 4 مساءً', prefixIcon: Icon(Icons.campaign_rounded))),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: PillChoice(label: 'المعلمون', icon: Icons.co_present_rounded, color: RoleColors.teacher, selected: teachers, onTap: () => setS(() => teachers = !teachers))),
                  const SizedBox(width: 8),
                  Expanded(child: PillChoice(label: 'الطلاب', icon: Icons.school_rounded, color: RoleColors.student, selected: students, onTap: () => setS(() => students = !students))),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  if (s.announcement.isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
                        onPressed: () {
                          c.clear();
                          Navigator.pop(ctx, true);
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('إزالة الإعلان'),
                      ),
                    ),
                  if (s.announcement.isNotEmpty) const SizedBox(width: 8),
                  Expanded(child: FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.save_rounded, size: 18), label: const Text('حفظ'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (r != true || !mounted) return;
    final next = s.copyWith(announcement: c.text.trim(), announcementForTeachers: teachers, announcementForStudents: students);
    setState(() => _draft = next);
    await _save(repo);
  }

  Future<void> _exportSummary(AdminRepository repo) async {
    final now = DateTime.now();
    final b = StringBuffer()
      ..writeln('📊 ملخص المنصة — ${TimelineFormat.fullDate(now)}')
      ..writeln('')
      ..writeln('👨‍🏫 المعلمون: ${repo.teachers.length}')
      ..writeln('🎓 الطلاب: ${repo.allStudents.length}')
      ..writeln('📚 دروس منتهية: ${repo.totalEnded} (${TimelineFormat.duration(repo.totalMinutes)})')
      ..writeln('💰 إجمالي الإيراد: ${TimelineFormat.money(repo.totalRevenue)}')
      ..writeln('✅ المحصَّل: ${TimelineFormat.money(repo.totalCollected)}')
      ..writeln('🔴 مستحقات على الطلاب: ${TimelineFormat.money(repo.totalOwed)}')
      ..writeln('')
      ..writeln('إيراد ${TimelineFormat.monthName(now)}: ${TimelineFormat.money(repo.revenueIn(now))} (${repo.endedIn(now)} درس)')
      ..writeln('')
      ..writeln('حسب المعلم:');
    for (final t in repo.topTeachers(now, limit: 50)) {
      b.writeln('• ${t.name}: ${t.students.length} طالب — ${TimelineFormat.money(t.revenueIn(now))} هذا الشهر${t.owed > 0 ? ' — مستحق ${TimelineFormat.money(t.owed)}' : ''}');
    }
    await Share.share(b.toString());
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AdminRepository>();
    final theme = context.watch<ThemeProvider>();
    final auth = context.watch<AuthProvider>();
    final scheme = Theme.of(context).colorScheme;
    final s = _s(repo);
    final dirty = _draft != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
        actions: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: dirty
                ? Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: FilledButton.icon(
                      onPressed: _saving ? null : () => _save(repo),
                      icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded, size: 18),
                      label: const Text('حفظ'),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        physics: const BouncingScrollPhysics(),
        children: [
          // ===== الحساب =====
          StaggeredReveal(
            index: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [RoleColors.admin, Color(0xFF5B21B6)], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                boxShadow: [BoxShadow(color: RoleColors.admin.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Row(
                children: [
                  InitialAvatar(name: auth.currentUser?.name ?? 'م', color: Colors.white.withValues(alpha: 0.25), size: 54),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(auth.currentUser?.name ?? 'مدير', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text('حساب إدارة • ${auth.currentUser?.code ?? ''}', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'نسخ الكود',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: auth.currentUser?.code ?? ''));
                      adminToast(context, 'تم نسخ الكود');
                    },
                    icon: const Icon(Icons.copy_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),

          // ===== الإعلان =====
          SectionTitle(title: 'إعلان عام', icon: Icons.campaign_rounded, actionLabel: s.announcement.isEmpty ? 'إضافة' : 'تعديل', onAction: () => _editAnnouncement(repo)),
          StaggeredReveal(
            index: 1,
            child: SoftCard(
              onTap: () => _editAnnouncement(repo),
              glow: s.announcement.isEmpty ? null : AppTheme.warning,
              child: Row(
                children: [
                  Icon(s.announcement.isEmpty ? Icons.campaign_outlined : Icons.campaign_rounded, color: s.announcement.isEmpty ? scheme.outline : AppTheme.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.announcement.isEmpty ? 'لا يوجد إعلان نشط. اضغط لإضافة رسالة تظهر للمعلمين والطلاب.' : s.announcement,
                      style: TextStyle(fontSize: 12.5, color: s.announcement.isEmpty ? scheme.onSurfaceVariant : scheme.onSurface, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ===== سياسات المنصة =====
          const SectionTitle(title: 'سياسات المنصة', icon: Icons.policy_rounded),
          StaggeredReveal(
            index: 2,
            child: SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                children: [
                  _toggle(
                    icon: Icons.event_available_rounded,
                    title: 'السماح للطلاب بطلب مواعيد',
                    subtitle: 'يظهر زر «طلب موعد» في حساب الطالب',
                    value: s.allowStudentRequests,
                    onChanged: (v) => _set(s.copyWith(allowStudentRequests: v)),
                  ),
                  _toggle(
                    icon: Icons.contact_phone_rounded,
                    title: 'السماح للطلاب بتعديل بيانات التواصل',
                    subtitle: 'الهاتف والبريد من صفحة «حسابي»',
                    value: s.allowStudentContactEdit,
                    onChanged: (v) => _set(s.copyWith(allowStudentContactEdit: v)),
                  ),
                  _toggle(
                    icon: Icons.verified_rounded,
                    title: 'اشتراط تصفية الرصيد قبل حذف الطالب',
                    subtitle: 'يمنع الحذف إن كان الرصيد ≠ 0 (ما لم يكن قسرياً)',
                    value: s.requireZeroBalanceToDelete,
                    onChanged: (v) => _set(s.copyWith(requireZeroBalanceToDelete: v)),
                  ),
                  const Divider(height: 1, indent: 14, endIndent: 14),
                  ListTile(
                    leading: Icon(Icons.attach_money_rounded, color: scheme.primary),
                    title: const Text('رمز العملة', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    subtitle: Text('يظهر في كل المبالغ • حالياً: ${s.currency}', style: const TextStyle(fontSize: 11.5)),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () async {
                      final v = await showEditFieldSheet(context, title: 'رمز العملة', label: 'الرمز', value: s.currency, icon: Icons.attach_money_rounded);
                      if (v != null && v.isNotEmpty) _set(s.copyWith(currency: v));
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.price_check_rounded, color: scheme.primary),
                    title: const Text('سعر الساعة الافتراضي', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    subtitle: Text(s.defaultHourlyRate > 0 ? 'يُقترح عند إضافة طالب جديد: ${TimelineFormat.money(s.defaultHourlyRate)}' : 'غير محدد', style: const TextStyle(fontSize: 11.5)),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () async {
                      final v = await showEditFieldSheet(context, title: 'سعر الساعة الافتراضي', label: 'السعر', value: s.defaultHourlyRate > 0 ? s.defaultHourlyRate.toStringAsFixed(0) : '', icon: Icons.price_check_rounded, keyboard: const TextInputType.numberWithOptions(decimal: true));
                      if (v != null) _set(s.copyWith(defaultHourlyRate: double.tryParse(v) ?? 0));
                    },
                  ),
                ],
              ),
            ),
          ),

          // ===== سجل الإجراءات =====
          SectionTitle(
            title: 'سجل إجراءات الإدارة',
            icon: Icons.history_edu_rounded,
            actionLabel: repo.log.isEmpty ? null : 'مسح',
            onAction: repo.log.isEmpty
                ? null
                : () async {
                    final ok = await showStudentConfirm(context, title: 'مسح السجل؟', message: 'سيُحذف سجل الإجراءات بالكامل.', confirmLabel: 'مسح', icon: Icons.delete_sweep_rounded, color: AppTheme.danger);
                    if (ok && context.mounted) await runAdminAction(context, repo.clearLog, success: 'تم مسح السجل');
                  },
          ),
          StaggeredReveal(
            index: 3,
            child: SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: repo.log.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.history_toggle_off_rounded, color: scheme.outline),
                          const SizedBox(width: 10),
                          Expanded(child: Text('لا توجد إجراءات مسجّلة بعد. كل تغيير من لوحة الإدارة يُسجَّل هنا تلقائياً.', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant))),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        for (final e in repo.log.take(25)) _LogTile(e: e),
                        if (repo.log.length > 25)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('… و ${repo.log.length - 25} إجراء أقدم', style: TextStyle(fontSize: 11.5, color: scheme.outline)),
                          ),
                      ],
                    ),
            ),
          ),

          // ===== المظهر والأدوات =====
          const SectionTitle(title: 'المظهر والأدوات', icon: Icons.tune_rounded),
          StaggeredReveal(
            index: 4,
            child: SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.brightness_6_rounded, color: scheme.primary),
                    title: const Text('المظهر', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    trailing: SizedBox(
                      width: 190,
                      child: Segmented<ThemeMode>(
                        value: theme.mode,
                        onChanged: theme.setMode,
                        items: const [
                          (value: ThemeMode.light, label: 'فاتح', icon: null),
                          (value: ThemeMode.system, label: 'تلقائي', icon: null),
                          (value: ThemeMode.dark, label: 'داكن', icon: null),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.ios_share_rounded, color: scheme.primary),
                    title: const Text('مشاركة ملخص المنصة', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    subtitle: Text('نص جاهز بالأرقام الرئيسية وحسب المعلم', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => _exportSummary(repo),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.refresh_rounded, color: scheme.primary),
                    title: const Text('إعادة تحميل البيانات', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () async {
                      await repo.refresh();
                      adminToast(context, 'تم التحديث');
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          StaggeredReveal(
            index: 5,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger, side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.5)), padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                final ok = await showStudentConfirm(context, title: 'تسجيل الخروج؟', message: 'ستحتاج إلى كود الإدارة للعودة.', confirmLabel: 'خروج', icon: Icons.logout_rounded, color: AppTheme.danger);
                if (!ok || !context.mounted) return;
                await context.read<AuthProvider>().signOut();
                if (context.mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('تسجيل الخروج'),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text('Dexoed • لوحة الإدارة', style: TextStyle(fontSize: 11, color: scheme.outline))),
        ],
      ),
    );
  }

  Widget _toggle({required IconData icon, required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged}) {
    final scheme = Theme.of(context).colorScheme;
    return SwitchListTile.adaptive(
      secondary: Icon(icon, color: scheme.primary),
      title: Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.e});
  final AdminLogEntry e;

  static const _meta = <String, (IconData, Color, String)>{
    'create_teacher': (Icons.person_add_alt_1_rounded, RoleColors.teacher, 'إنشاء معلم'),
    'create_admin': (Icons.add_moderator_rounded, RoleColors.admin, 'إنشاء مدير'),
    'create_student': (Icons.school_rounded, RoleColors.student, 'إضافة طالب'),
    'update_account': (Icons.edit_rounded, Color(0xFF3B5BFE), 'تعديل حساب'),
    'update_student': (Icons.edit_rounded, RoleColors.student, 'تعديل طالب'),
    'disable': (Icons.block_rounded, AppTheme.warning, 'تعطيل'),
    'enable': (Icons.lock_open_rounded, AppTheme.success, 'تفعيل'),
    'permissions': (Icons.verified_user_rounded, Color(0xFF8B5CF6), 'صلاحيات'),
    'delete_teacher': (Icons.delete_forever_rounded, AppTheme.danger, 'حذف معلم'),
    'delete_admin': (Icons.delete_forever_rounded, AppTheme.danger, 'حذف مدير'),
    'delete_student': (Icons.person_remove_rounded, AppTheme.danger, 'حذف طالب'),
    'delete_orphan': (Icons.cleaning_services_rounded, AppTheme.danger, 'حذف سجل يتيم'),
    'delete_lesson': (Icons.event_busy_rounded, AppTheme.danger, 'حذف درس'),
    'lesson_amount': (Icons.price_change_rounded, Color(0xFF3B5BFE), 'تعديل مبلغ'),
    'transfer_student': (Icons.swap_horiz_rounded, Color(0xFF06B6D4), 'نقل طالب'),
    'link_student': (Icons.link_rounded, AppTheme.success, 'ربط طالب'),
    'payment': (Icons.payments_rounded, AppTheme.success, 'دفعة'),
    'settings': (Icons.settings_rounded, Color(0xFF3B5BFE), 'إعدادات'),
    'clear_log': (Icons.delete_sweep_rounded, AppTheme.warning, 'مسح السجل'),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = _meta[e.action] ?? (Icons.circle_outlined, scheme.outline, e.action);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 30, height: 30, decoration: BoxDecoration(color: m.$2.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)), child: Icon(m.$1, size: 15, color: m.$2)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${m.$3}${e.details.isNotEmpty ? ' — ${e.details}' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                Text('${e.by} • ${TimelineFormat.relativeDay(e.at)} ${TimelineFormat.time(e.at, use24h: false)}${e.target.isNotEmpty ? ' • ${e.target}' : ''}', style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
