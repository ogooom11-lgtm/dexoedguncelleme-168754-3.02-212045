// lib/src/pages/teacher_profile_page.dart
//
// 👤 حساب المعلم — تصميم عصري:
//   • ترويسة متدرجة بأرقام متحركة (الطلاب / إيراد الشهر / المستحقات)
//   • شبكة إحصائيات + رسم بياني 6 أشهر
//   • بياناتي: الاسم / الهاتف / البريد (تعديل عبر ورقة سفلية — يخضع لصلاحية editProfile)
//   • الخصوصية: إظهار رقم الهاتف للطلاب (تبديل لحظي) — البريد لا يظهر للطلاب أبداً
//   • التفضيلات: سعر الساعة الافتراضي للطلاب الجدد، المظهر
//   • صلاحياتي: ما سمحت به الإدارة لهذا الحساب
//   • مشاركة بطاقة المعلم (الاسم + الكود [+ الهاتف إن كان ظاهراً])

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/permission_guard.dart';
import '../services/teacher_account.dart';
import '../services/timeline_models.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import 'admin/admin_widgets.dart' show MiniBarChart, GradientStat, Tag;
import 'student/student_sheets.dart' show showStudentSheet;
import 'student/student_widgets.dart';
import 'timeline/timeline_widgets.dart';

class TeacherProfilePage extends StatefulWidget {
  const TeacherProfilePage({super.key});

  @override
  State<TeacherProfilePage> createState() => _TeacherProfilePageState();
}

class _TeacherProfilePageState extends State<TeacherProfilePage> {
  TeacherAccount? _acc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final code = context.read<AuthProvider>().currentUser?.code ?? '';
    if (_acc == null || _acc!.code != code) {
      _acc?.dispose();
      _acc = TeacherAccount(code)..start();
      PermissionGuard.start(code);
    }
  }

  @override
  void dispose() {
    _acc?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ إجراءات

  Future<void> _editProfile(TeacherAccount acc) async {
    if (!await PermissionGuard.check(context, TeacherPermission.editProfile, teacherCode: acc.code)) return;
    if (!mounted) return;
    final r = await _showEditProfileSheet(context, name: acc.name, phone: acc.phone, email: acc.email);
    if (r == null) return;
    try {
      await acc.updateProfile(name: r.name, phone: r.phone, email: r.email);
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      await auth.refreshCurrentUserSilently();
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ تم حفظ بياناتك')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e')));
    }
  }

  Future<void> _editDefaultRate(TeacherAccount acc) async {
    final c = TextEditingController(text: acc.defaultHourlyRate > 0 ? _num(acc.defaultHourlyRate) : '');
    final v = await showStudentSheet<double>(
      context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader(title: 'سعر الساعة الافتراضي', subtitle: 'يُقترح تلقائياً عند إضافة طالب جديد — يمكنك تغييره لكل طالب'),
            const SizedBox(height: 14),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              textDirection: ui.TextDirection.ltr,
              decoration: InputDecoration(labelText: 'المبلغ', suffixText: TimelineFormat.currency, prefixIcon: const Icon(Icons.price_change_rounded)),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, double.tryParse(c.text.trim()) ?? 0),
              icon: const Icon(Icons.save_rounded),
              label: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (v == null) return;
    await acc.setDefaultHourlyRate(v);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(v > 0 ? '✅ السعر الافتراضي: ${TimelineFormat.money(v)}' : 'تم إلغاء السعر الافتراضي')));
  }

  Future<void> _togglePhone(TeacherAccount acc, bool v) async {
    HapticFeedback.selectionClick();
    await acc.setShowPhoneToStudents(v);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(v ? '📞 رقمك ظاهر الآن لطلابك' : '🔒 رقمك مخفي عن الطلاب'),
      ));
  }

  Future<void> _share(TeacherAccount acc) async {
    final b = StringBuffer()
      ..writeln('👨‍🏫 ${acc.name}')
      ..writeln('🔑 كود المعلم: ${acc.code}');
    if (acc.showPhoneToStudents && acc.phone.isNotEmpty) b.writeln('📞 ${acc.phone}');
    b.writeln('');
    b.writeln('Dexoed');
    await Share.share(b.toString());
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.lightImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('📋 تم نسخ الكود')));
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل تريد تسجيل الخروج من حسابك؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('خروج'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    PermissionGuard.stop();
    await context.read<AuthProvider>().signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  // ------------------------------------------------------------------ الواجهة

  @override
  Widget build(BuildContext context) {
    final acc = _acc!;
    return ChangeNotifierProvider<TeacherAccount>.value(
      value: acc,
      child: Consumer<TeacherAccount>(
        builder: (context, acc, _) {
          final scheme = Theme.of(context).colorScheme;
          final theme = context.watch<ThemeProvider>();
          final user = context.watch<AuthProvider>().currentUser;
          final displayName = acc.name.isNotEmpty ? acc.name : (user?.name ?? 'معلم');

          return Scaffold(
            appBar: AppBar(
              title: const Text('حسابي'),
              actions: [
                IconButton(tooltip: 'مشاركة بطاقتي', onPressed: () => _share(acc), icon: const Icon(Icons.ios_share_rounded)),
              ],
            ),
            body: !acc.ready
                ? const Center(child: CircularProgressIndicator())
                : AdaptiveBody(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(Responsive.gutter(context), 8, Responsive.gutter(context), 32),
                      children: [
                        // ===== الترويسة =====
                        StaggeredReveal(
                          index: 0,
                          child: _Hero(
                            name: displayName,
                            code: acc.code,
                            acc: acc,
                            onCopy: () => _copyCode(acc.code),
                            onEdit: () => _editProfile(acc),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ===== الأرقام =====
                        StaggeredReveal(
                          index: 1,
                          child: Row(
                            children: [
                              Expanded(
                                child: GradientStat(
                                  icon: Icons.trending_up_rounded,
                                  label: 'إيراد هذا الشهر',
                                  value: acc.monthRevenue,
                                  color: AppTheme.success,
                                  suffix: ' ${TimelineFormat.currency}',
                                  subtitle: acc.prevMonthRevenue > 0
                                      ? '${acc.growth >= 0 ? '▲' : '▼'} ${(acc.growth.abs() * 100).toStringAsFixed(0)}% عن الشهر الماضي'
                                      : 'الشهر الماضي: ${TimelineFormat.money(acc.prevMonthRevenue)}',
                                  onTap: () => Navigator.pushNamed(context, '/teacher_balance'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: GradientStat(
                                  icon: Icons.account_balance_wallet_rounded,
                                  label: 'مستحق على الطلاب',
                                  value: acc.owed,
                                  color: acc.owed > 0 ? AppTheme.warning : scheme.primary,
                                  suffix: ' ${TimelineFormat.currency}',
                                  subtitle: acc.credit > 0 ? 'رصيد زائد للطلاب: ${TimelineFormat.money(acc.credit)}' : 'لا أرصدة زائدة',
                                  onTap: () => Navigator.pushNamed(context, '/teacher_balance'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        StaggeredReveal(
                          index: 2,
                          child: SoftCard(
                            padding: const EdgeInsets.all(14),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                MiniStat(icon: Icons.group_rounded, label: 'الطلاب', value: '${acc.studentsCount}', color: const Color(0xFF3B82F6)),
                                MiniStat(icon: Icons.check_circle_rounded, label: 'دروس منتهية', value: '${acc.endedCount}', color: const Color(0xFF10B981)),
                                MiniStat(icon: Icons.event_available_rounded, label: 'قادمة', value: '${acc.upcomingCount}', color: const Color(0xFF06B6D4)),
                                MiniStat(icon: Icons.hourglass_top_rounded, label: 'طلبات معلّقة', value: '${acc.pendingCount}', color: AppTheme.warning),
                                MiniStat(icon: Icons.timer_outlined, label: 'ساعات التدريس', value: TimelineFormat.duration(acc.totalMinutes), color: const Color(0xFF8B5CF6)),
                                MiniStat(icon: Icons.savings_rounded, label: 'إجمالي الإيراد', value: TimelineFormat.money(acc.totalRevenue), color: const Color(0xFF14B8A6)),
                              ],
                            ),
                          ),
                        ),

                        // ===== الرسم البياني =====
                        const SectionTitle(title: 'الإيراد خلال 6 أشهر', icon: Icons.bar_chart_rounded),
                        StaggeredReveal(
                          index: 3,
                          child: SoftCard(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                            child: acc.months.every((m) => m.value == 0)
                                ? const TimelineEmptyState(icon: Icons.insights_rounded, title: 'لا توجد دروس منتهية بعد', subtitle: 'سيظهر الرسم البياني بعد أول درس منتهٍ.')
                                : MiniBarChart(items: acc.months, color: scheme.primary, valueLabel: (v) => TimelineFormat.money(v)),
                          ),
                        ),

                        // ===== بياناتي =====
                        SectionTitle(title: 'بياناتي', icon: Icons.badge_outlined, actionLabel: 'تعديل', onAction: () => _editProfile(acc)),
                        StaggeredReveal(
                          index: 4,
                          child: SoftCard(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            onTap: () => _editProfile(acc),
                            child: Column(
                              children: [
                                InfoRow(icon: Icons.person_rounded, label: 'الاسم', value: displayName),
                                InfoRow(icon: Icons.phone_rounded, label: 'الهاتف', value: acc.phone.isEmpty ? 'غير مضاف' : acc.phone),
                                InfoRow(icon: Icons.alternate_email_rounded, label: 'البريد', value: acc.email.isEmpty ? 'غير مضاف' : acc.email),
                                if (acc.createdAt != null)
                                  InfoRow(icon: Icons.calendar_month_rounded, label: 'عضو منذ', value: TimelineFormat.fullDate(acc.createdAt!)),
                              ],
                            ),
                          ),
                        ),

                        // ===== الخصوصية =====
                        const SectionTitle(title: 'الخصوصية', icon: Icons.shield_outlined),
                        StaggeredReveal(
                          index: 5,
                          child: SoftCard(
                            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                            child: Column(
                              children: [
                                SwitchListTile.adaptive(
                                  value: acc.showPhoneToStudents,
                                  onChanged: (v) => _togglePhone(acc, v),
                                  secondary: _ToggleIcon(
                                    on: acc.showPhoneToStudents,
                                    onIcon: Icons.phone_enabled_rounded,
                                    offIcon: Icons.phonelink_lock_rounded,
                                    color: acc.showPhoneToStudents ? AppTheme.success : scheme.onSurfaceVariant,
                                  ),
                                  title: const Text('إظهار رقم هاتفي للطلاب', style: TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                    acc.phone.isEmpty
                                        ? 'أضف رقم هاتفك أولاً من «بياناتي»'
                                        : acc.showPhoneToStudents
                                            ? 'يستطيع طلابك الاتصال بك من صفحة «معلمي»'
                                            : 'يرى الطلاب «التواصل عبر المنصة» بدل رقمك',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                const Divider(height: 1, indent: 16, endIndent: 16),
                                ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                                    child: Icon(Icons.mark_email_read_outlined, color: scheme.primary, size: 20),
                                  ),
                                  title: const Text('البريد الإلكتروني خاص', style: TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: const Text('لا يظهر بريدك للطلاب أبداً — تراه الإدارة فقط', style: TextStyle(fontSize: 12)),
                                  trailing: const Tag(label: 'خاص', color: Color(0xFF64748B), icon: Icons.lock_rounded),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ===== التفضيلات =====
                        const SectionTitle(title: 'التفضيلات', icon: Icons.tune_rounded),
                        StaggeredReveal(
                          index: 6,
                          child: SoftCard(
                            padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
                            child: Column(
                              children: [
                                ListTile(
                                  onTap: () => _editDefaultRate(acc),
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                                    child: const Icon(Icons.price_change_rounded, color: AppTheme.success, size: 20),
                                  ),
                                  title: const Text('سعر الساعة الافتراضي', style: TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: const Text('يُملأ تلقائياً عند إضافة طالب جديد', style: TextStyle(fontSize: 12)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        acc.defaultHourlyRate > 0 ? TimelineFormat.money(acc.defaultHourlyRate) : 'غير محدد',
                                        style: TextStyle(fontWeight: FontWeight.w800, color: acc.defaultHourlyRate > 0 ? AppTheme.success : scheme.outline),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.chevron_left_rounded, color: scheme.outline),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1, indent: 16, endIndent: 16),
                                ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                                    child: const Icon(Icons.brightness_6_rounded, color: Color(0xFFF59E0B), size: 20),
                                  ),
                                  title: const Text('المظهر', style: TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                    switch (theme.mode) {
                                      ThemeMode.dark => 'داكن',
                                      ThemeMode.light => 'فاتح',
                                      ThemeMode.system => 'حسب النظام',
                                    },
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                                  child: SegmentedButton<ThemeMode>(
                                    segments: const [
                                      ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('فاتح')),
                                      ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.settings_suggest_rounded), label: Text('النظام')),
                                      ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('داكن')),
                                    ],
                                    selected: {theme.mode},
                                    showSelectedIcon: false,
                                    onSelectionChanged: (s) => theme.setMode(s.first),
                                  ),
                                ),
                                const Divider(height: 1, indent: 16, endIndent: 16),
                                ListTile(
                                  onTap: () => Navigator.pushNamed(context, '/teacher_timeline'),
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: const Color(0xFF8B5CF6).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                                    child: const Icon(Icons.view_timeline_rounded, color: Color(0xFF8B5CF6), size: 20),
                                  ),
                                  title: const Text('إعدادات الجدول الزمني', style: TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: const Text('ساعات العمل، نظام الوقت، الاهتزاز… من داخل الجدول', style: TextStyle(fontSize: 12)),
                                  trailing: Icon(Icons.chevron_left_rounded, color: scheme.outline),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ===== صلاحياتي =====
                        const SectionTitle(title: 'صلاحياتي', icon: Icons.verified_user_outlined),
                        StaggeredReveal(
                          index: 7,
                          child: StreamBuilder<TeacherPermissions>(
                            stream: PermissionGuard.stream,
                            initialData: PermissionGuard.current,
                            builder: (context, snap) {
                              final p = snap.data ?? PermissionGuard.current;
                              return SoftCard(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(p.isFull ? Icons.verified_rounded : Icons.info_outline_rounded, color: p.isFull ? AppTheme.success : AppTheme.warning, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            p.isFull ? 'صلاحيات كاملة' : '${p.deniedCount} من ${TeacherPermission.values.length} صلاحيات موقوفة',
                                            style: const TextStyle(fontWeight: FontWeight.w800),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final perm in TeacherPermission.values)
                                          Tag(
                                            label: perm.label,
                                            icon: p.allows(perm) ? perm.icon : Icons.lock_rounded,
                                            color: p.allows(perm) ? AppTheme.success : const Color(0xFF94A3B8),
                                          ),
                                      ],
                                    ),
                                    if (!p.isFull) ...[
                                      const SizedBox(height: 8),
                                      Text('لتفعيل صلاحية موقوفة تواصل مع الإدارة.', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                        const SizedBox(height: 18),
                        StaggeredReveal(
                          index: 8,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.danger,
                              side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.5)),
                              minimumSize: const Size.fromHeight(48),
                            ),
                            onPressed: _logout,
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(child: Text('Dexoed • حساب المعلم', style: TextStyle(fontSize: 11, color: scheme.outline))),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }
}

// =====================================================================
// الترويسة
// =====================================================================

class _Hero extends StatelessWidget {
  const _Hero({required this.name, required this.code, required this.acc, required this.onCopy, required this.onEdit});
  final String name;
  final String code;
  final TeacherAccount acc;
  final VoidCallback onCopy;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: [BoxShadow(color: AppTheme.seed.withValues(alpha: 0.25), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
                ),
                child: Text(
                  name.trim().isEmpty ? '؟' : name.trim().characters.first,
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    PressScale(
                      onTap: onCopy,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.key_rounded, size: 14, color: Colors.white),
                            const SizedBox(width: 5),
                            Text(code, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 13)),
                            const SizedBox(width: 6),
                            const Icon(Icons.copy_rounded, size: 13, color: Colors.white70),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'تعديل بياناتي',
                onPressed: onEdit,
                style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.16), foregroundColor: Colors.white),
                icon: const Icon(Icons.edit_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _HeroNum(label: 'الطلاب', value: acc.studentsCount.toDouble()),
              _divider(),
              _HeroNum(label: 'دروس اليوم', value: acc.todayCount.toDouble()),
              _divider(),
              _HeroNum(label: 'إيراد الشهر', value: acc.monthRevenue, suffix: ' ${TimelineFormat.currency}'),
            ],
          ),
          if (!acc.profileComplete) ...[
            const SizedBox(height: 12),
            PressScale(
              onTap: onEdit,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                child: const Row(
                  children: [
                    Icon(Icons.tips_and_updates_rounded, color: Colors.amber, size: 18),
                    SizedBox(width: 8),
                    Expanded(child: Text('أكمل ملفك: أضف رقم هاتفك ليتمكن طلابك من التواصل معك', style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600))),
                    Icon(Icons.chevron_left_rounded, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 30, color: Colors.white.withValues(alpha: 0.25));
}

class _HeroNum extends StatelessWidget {
  const _HeroNum({required this.label, required this.value, this.suffix = ''});
  final String label;
  final double value;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          AnimatedNumber(value: value, suffix: suffix, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ToggleIcon extends StatelessWidget {
  const _ToggleIcon({required this.on, required this.onIcon, required this.offIcon, required this.color});
  final bool on;
  final IconData onIcon;
  final IconData offIcon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
        child: Icon(on ? onIcon : offIcon, key: ValueKey(on), color: color, size: 20),
      ),
    );
  }
}

// =====================================================================
// ورقة تعديل البيانات
// =====================================================================

Future<({String name, String phone, String email})?> _showEditProfileSheet(
  BuildContext context, {
  required String name,
  required String phone,
  required String email,
}) {
  final n = TextEditingController(text: name);
  final p = TextEditingController(text: phone);
  final e = TextEditingController(text: email);
  final key = GlobalKey<FormState>();
  return showStudentSheet<({String name, String phone, String email})>(
    context,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + MediaQuery.viewInsetsOf(ctx).bottom),
      child: Form(
        key: key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHeader(title: 'تعديل بياناتي', subtitle: 'الاسم يظهر لطلابك وللإدارة'),
            const SizedBox(height: 14),
            TextFormField(
              controller: n,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'الاسم', prefixIcon: Icon(Icons.person_rounded)),
              validator: (v) => (v == null || v.trim().length < 2) ? 'أدخل اسماً صحيحاً' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: p,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              textDirection: ui.TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone_rounded), helperText: 'يمكنك التحكم بظهوره للطلاب من «الخصوصية»'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: e,
              keyboardType: TextInputType.emailAddress,
              textDirection: ui.TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.alternate_email_rounded), helperText: 'خاص — لا يظهر للطلاب'),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'بريد غير صالح';
              },
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                if (!(key.currentState?.validate() ?? false)) return;
                Navigator.pop(ctx, (name: n.text.trim(), phone: p.text.trim(), email: e.text.trim()));
              },
              icon: const Icon(Icons.save_rounded),
              label: const Text('حفظ'),
            ),
          ],
        ),
      ),
    ),
  );
}
