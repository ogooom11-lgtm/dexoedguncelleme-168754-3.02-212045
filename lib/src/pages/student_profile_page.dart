// lib/src/pages/student_profile_page.dart
import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/student_repository.dart';
import '../services/timeline_models.dart';
import '../theme/app_theme.dart';
import 'student/student_sheets.dart';
import 'student/student_widgets.dart';
import '../services/permission_guard.dart';

/// 👤 حسابي — بطاقة الطالب، الإنجازات، بيانات التواصل، معلومات المعلم، الإعدادات.
class StudentProfilePage extends StatelessWidget {
  const StudentProfilePage({super.key});

  Future<void> _open(BuildContext context, String action, String data, String copyLabel) async {
    if (Platform.isAndroid) {
      try {
        await AndroidIntent(action: action, data: data).launch();
        return;
      } catch (_) {}
    }
    await Clipboard.setData(ClipboardData(text: copyLabel));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم نسخ: $copyLabel')));
    }
  }

  Future<void> _editContact(BuildContext context, StudentRepository repo) async {
    final r = await showEditContactSheet(context, email: repo.email ?? '', phone: repo.phone ?? '');
    if (r == null || !context.mounted) return;
    try {
      await repo.updateContact(email: r.email, phone: r.phone);
      if (context.mounted) {
        await context.read<AuthProvider>().refreshCurrentUserSilently();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ بيانات التواصل ✅')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppTheme.danger, content: Text('تعذر الحفظ: $e')));
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await showStudentConfirm(
      context,
      title: 'تسجيل الخروج؟',
      message: 'ستحتاج إلى رمز الدخول الخاص بك للعودة.',
      confirmLabel: 'خروج',
      icon: Icons.logout_rounded,
      color: AppTheme.danger,
    );
    if (!ok || !context.mounted) return;
    await context.read<AuthProvider>().signOut();
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<StudentRepository>();
    final auth = context.watch<AuthProvider>();
    final theme = context.watch<ThemeProvider>();
    final scheme = Theme.of(context).colorScheme;
    final user = auth.currentUser;
    final name = repo.studentName.isNotEmpty ? repo.studentName : (user?.name ?? 'طالب');
    final initials = name.trim().isEmpty ? '؟' : name.trim().characters.first;
    final ended = repo.endedLessons.length;
    final hours = repo.totalMinutesLearned / 60;
    final first = repo.endedLessons.isEmpty
        ? null
        : repo.endedLessons.map((l) => l.start).reduce((a, b) => a.isBefore(b) ? a : b);
    final f = repo.finance;

    return StreamBuilder<PlatformSettings>(
      stream: PlatformGate.watch(),
      builder: (context, snap) {
        final canEditContact = (snap.data ?? PlatformGate.current).allowStudentContactEdit;
        return Scaffold(
      appBar: AppBar(title: const Text('حسابي')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          // ===== بطاقة الهوية =====
          StaggeredReveal(
            index: 0,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: AppTheme.heroGradient(context),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
                        ),
                        child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text(
                              repo.gender == 'female' ? 'طالبة' : 'طالب',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      PressScale(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: user?.code ?? ''));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ رمز الدخول')));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.key_rounded, color: Colors.white, size: 14),
                              const SizedBox(width: 5),
                              Text(user?.code ?? '', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _Stat(icon: Icons.menu_book_rounded, value: '$ended', label: 'درس منتهٍ'),
                      _Stat(icon: Icons.timer_outlined, value: hours >= 10 ? hours.round().toString() : hours.toStringAsFixed(1), label: 'ساعة تعلّم'),
                      _Stat(icon: Icons.local_fire_department_rounded, value: '${repo.monthStats(DateTime.now()).count}', label: 'هذا الشهر'),
                    ],
                  ),
                  if (first != null) ...[
                    const SizedBox(height: 10),
                    Text('معك منذ ${TimelineFormat.monthName(first)} ${first.year}', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11.5)),
                  ],
                ],
              ),
            ),
          ),

          // ===== الإنجازات =====
          const SectionTitle(title: 'إنجازاتك', icon: Icons.emoji_events_rounded),
          StaggeredReveal(
            index: 1,
            child: SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: [
                  _Badge(icon: Icons.flag_rounded, label: 'أول درس', unlocked: ended >= 1, color: scheme.primary),
                  _Badge(icon: Icons.looks_5_rounded, label: '5 دروس', unlocked: ended >= 5, color: const Color(0xFF8B5CF6)),
                  _Badge(icon: Icons.stars_rounded, label: '10 دروس', unlocked: ended >= 10, color: AppTheme.warning),
                  _Badge(icon: Icons.workspace_premium_rounded, label: '25 درساً', unlocked: ended >= 25, color: const Color(0xFFEC4899)),
                  _Badge(icon: Icons.schedule_rounded, label: '10 ساعات', unlocked: hours >= 10, color: const Color(0xFF06B6D4)),
                  _Badge(icon: Icons.verified_rounded, label: 'حساب مسدّد', unlocked: repo.isReady && f.lessonsTotal > 0 && f.balance <= 0.5, color: AppTheme.success),
                  _Badge(icon: Icons.contact_mail_rounded, label: 'ملف مكتمل', unlocked: (repo.phone ?? '').isNotEmpty && (repo.email ?? '').isNotEmpty, color: const Color(0xFF10B981)),
                ],
              ),
            ),
          ),

          // ===== بيانات التواصل =====
          SectionTitle(title: 'بيانات التواصل', icon: Icons.contact_phone_outlined, actionLabel: canEditContact ? 'تعديل' : null, onAction: canEditContact ? () => _editContact(context, repo) : null),
          StaggeredReveal(
            index: 2,
            child: SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              onTap: canEditContact ? () => _editContact(context, repo) : null,
              child: Column(
                children: [
                  InfoRow(icon: Icons.phone_rounded, label: 'الهاتف', value: (repo.phone ?? '').isEmpty ? 'غير مضاف' : repo.phone!),
                  InfoRow(icon: Icons.alternate_email_rounded, label: 'البريد', value: (repo.email ?? '').isEmpty ? 'غير مضاف' : repo.email!),
                ],
              ),
            ),
          ),

          // ===== المعلم =====
          const SectionTitle(title: 'معلمي', icon: Icons.school_rounded),
          StaggeredReveal(
            index: 3,
            child: SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(
                children: [
                  InfoRow(icon: Icons.person_rounded, label: 'الاسم', value: repo.teacherName.isEmpty ? '—' : repo.teacherName),
                  if (repo.hourlyRate > 0)
                    InfoRow(icon: Icons.payments_outlined, label: 'سعر الساعة', value: TimelineFormat.money(repo.hourlyRate), color: AppTheme.success),
                  if (repo.teacherVisiblePhone.isNotEmpty)
                    InfoRow(
                      icon: Icons.call_rounded,
                      label: 'الهاتف',
                      value: repo.teacherVisiblePhone,
                      trailing: Icon(Icons.open_in_new_rounded, size: 16, color: scheme.primary),
                      onTap: () => _open(context, 'android.intent.action.DIAL', 'tel:${repo.teacherVisiblePhone}', repo.teacherVisiblePhone),
                    )
                  else
                    const InfoRow(icon: Icons.call_rounded, label: 'التواصل', value: 'عبر المنصة'),
                ],
              ),
            ),
          ),

          // ===== الإعدادات =====
          const SectionTitle(title: 'الإعدادات', icon: Icons.tune_rounded),
          StaggeredReveal(
            index: 4,
            child: SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(theme.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, color: scheme.primary),
                    title: const Text('الوضع الداكن', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      theme.mode == ThemeMode.system ? 'يتبع إعداد النظام حالياً' : theme.isDark ? 'مفعّل' : 'متوقف',
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                    ),
                    value: theme.isDark || (theme.mode == ThemeMode.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark),
                    onChanged: (v) => theme.setMode(v ? ThemeMode.dark : ThemeMode.light),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.ios_share_rounded, color: scheme.primary),
                    title: const Text('مشاركة كشف الحساب', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    subtitle: Text('ملخص نصي للدروس والمدفوعات', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => shareStatement(context, repo),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.refresh_rounded, color: scheme.primary),
                    title: const Text('تحديث البيانات', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () async {
                      await repo.refresh();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم التحديث')));
                      }
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
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => _logout(context),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('تسجيل الخروج'),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text('Dexoed • حساب الطالب', style: TextStyle(fontSize: 11, color: scheme.outline)),
          ),
        ],
      ),
    );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
            Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 10.5)),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.unlocked, required this.color});
  final IconData icon;
  final String label;
  final bool unlocked;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: unlocked ? 1 : 0.45,
      child: Container(
        width: 84,
        margin: const EdgeInsetsDirectional.only(end: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: unlocked ? color.withValues(alpha: 0.1) : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: unlocked ? color.withValues(alpha: 0.35) : Colors.transparent),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: unlocked ? color : scheme.outline.withValues(alpha: 0.3), shape: BoxShape.circle),
              child: Icon(unlocked ? icon : Icons.lock_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 6),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: unlocked ? color : scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
