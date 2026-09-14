// lib/src/widgets/teacher_sidebar.dart
//
// القائمة الجانبية للمعلم — مجموعات منظمة، تحترم الصلاحيات (العناصر الموقوفة تظهر بقفل).

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../pages/alarm_settings_page.dart';
import '../pages/notifications_debug_page.dart';
import '../pages/recurring_schedules_page.dart';
import '../pages/teacher_add_ended_lesson_page.dart';
import '../pages/teacher_add_student_page.dart';
import '../pages/teacher_balance_page.dart';
import '../pages/teacher_lessons_page.dart';
import '../pages/teacher_payments_page.dart';
import '../pages/teacher_profile_page.dart';
import '../pages/teacher_profits_page.dart';
import '../pages/teacher_schedule_page.dart';
import '../pages/teacher_students_page.dart';
import '../pages/teacher_timeline_page.dart';
import '../pages/today_recurring_page.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/notification_orchestrator.dart';
import '../services/permission_guard.dart';
import '../theme/app_theme.dart';

class TeacherSidebar extends StatelessWidget {
  const TeacherSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final scheme = Theme.of(context).colorScheme;

    return Drawer(
      child: StreamBuilder<TeacherPermissions>(
        stream: PermissionGuard.stream,
        initialData: PermissionGuard.current,
        builder: (context, snap) {
          final perms = snap.data ?? PermissionGuard.current;
          return Column(
            children: [
              // ===== الترويسة =====
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _open(context, const TeacherProfilePage()),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(18, MediaQuery.paddingOf(context).top + 18, 18, 18),
                    decoration: BoxDecoration(gradient: AppTheme.heroGradient(context)),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
                          ),
                          child: Text(
                            (user?.name ?? '').trim().isEmpty ? '؟' : (user?.name ?? '').trim().characters.first,
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user?.name ?? 'معلم', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17), overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 3),
                              Text('الكود: ${user?.code ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                              if (!perms.isFull)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('${perms.deniedCount} صلاحيات موقوفة', style: const TextStyle(color: Colors.amber, fontSize: 11.5, fontWeight: FontWeight.w700)),
                                ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_left_rounded, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
              ),

              // ===== العناصر =====
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 12),
                  children: [
                    _group(context, 'الطلاب'),
                    _item(context, icon: Icons.people_alt_rounded, title: 'الطلاب', color: const Color(0xFF3B82F6), page: const TeacherStudentsPage()),
                    _item(context, icon: Icons.person_add_alt_1_rounded, title: 'إضافة طالب', color: const Color(0xFF10B981), page: const TeacherAddStudentPage(), permission: TeacherPermission.addStudents, perms: perms),

                    _group(context, 'الدروس والمواعيد'),
                    _item(context, icon: Icons.view_timeline_rounded, title: 'الجدول الزمني', color: const Color(0xFF06B6D4), page: const TeacherTimelinePage()),
                    _item(context, icon: Icons.event_rounded, title: 'المواعيد القادمة', color: const Color(0xFFF59E0B), page: const TeacherSchedulePage()),
                    _item(context, icon: Icons.event_available_rounded, title: 'تأكيد مواعيد اليوم', color: const Color(0xFFEC4899), page: const TodayRecurringPage()),
                    _item(context, icon: Icons.event_repeat_rounded, title: 'المواعيد المكررة', color: const Color(0xFF84CC16), page: const RecurringSchedulesPage(), permission: TeacherPermission.recurringSchedules, perms: perms),
                    _item(context, icon: Icons.history_edu_rounded, title: 'إضافة درس منتهي', color: const Color(0xFF6366F1), page: const TeacherAddEndedLessonPage()),
                    _item(context, icon: Icons.menu_book_rounded, title: 'سجل الدروس', color: const Color(0xFF8B5CF6), page: const TeacherLessonsPage()),

                    _group(context, 'المال'),
                    _item(context, icon: Icons.account_balance_wallet_rounded, title: 'الرصيد', color: const Color(0xFF14B8A6), page: const TeacherBalancePage()),
                    _item(context, icon: Icons.receipt_long_rounded, title: 'سجل الدفع', color: const Color(0xFFEF4444), page: const TeacherPaymentsPage()),
                    _item(context, icon: Icons.insights_rounded, title: 'المربح الشهري', color: const Color(0xFFA855F7), page: const ProfitsPage()),

                    _group(context, 'الحساب والإعدادات'),
                    _item(context, icon: Icons.manage_accounts_rounded, title: 'حسابي', color: const Color(0xFF64748B), page: const TeacherProfilePage(), subtitle: 'البيانات، الخصوصية، الصلاحيات'),
                    _item(context, icon: Icons.alarm_rounded, title: 'إعدادات المنبهات', color: const Color(0xFF9333EA), page: const AlarmSettingsPage()),
                    _item(context, icon: Icons.bug_report_outlined, title: 'فحص الإشعارات', color: const Color(0xFF78716C), page: const NotificationsDebugPage()),
                    ListTile(
                      dense: true,
                      leading: _iconBox(Icons.sync_rounded, const Color(0xFFF97316)),
                      title: const Text('إعادة جدولة التنبيهات', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      subtitle: const Text('تحليل الدروس وإنشاء التنبيهات يدوياً', style: TextStyle(fontSize: 11)),
                      onTap: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(context);
                        final code = user?.code ?? '';
                        if (code.isEmpty) return;
                        messenger.showSnackBar(const SnackBar(content: Text('جارٍ إعادة جدولة التنبيهات...')));
                        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
                          await NotificationOrchestrator.rescheduleAll(teacherCode: code);
                        }
                        messenger.showSnackBar(const SnackBar(content: Text('تم تحديث تنبيهات الدروس ✅')));
                      },
                    ),
                    SwitchListTile.adaptive(
                      dense: true,
                      title: const Text('الوضع الداكن', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      value: Theme.of(context).brightness == Brightness.dark,
                      onChanged: (_) => context.read<ThemeProvider>().toggle(),
                      secondary: _iconBox(Icons.dark_mode_rounded, const Color(0xFFF59E0B)),
                    ),
                  ],
                ),
              ),

              // ===== الخروج =====
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: AppTheme.danger.withValues(alpha: 0.12),
                    foregroundColor: AppTheme.danger,
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.w800)),
                  onPressed: () async {
                    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
                      await NotificationOrchestrator.onLogoutClearAll();
                    }
                    PermissionGuard.stop();
                    await auth.signOut();
                    if (!context.mounted) return;
                    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                  },
                ),
              ),
              Text('Dexoed', style: TextStyle(fontSize: 10.5, color: scheme.outline)),
              const SizedBox(height: 6),
            ],
          );
        },
      ),
    );
  }

  Widget _group(BuildContext context, String title) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
      child: Text(title, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: scheme.primary, letterSpacing: 0.3)),
    );
  }

  Widget _iconBox(IconData icon, Color color) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(11)),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget page,
    required Color color,
    String? subtitle,
    TeacherPermission? permission,
    TeacherPermissions? perms,
  }) {
    final locked = permission != null && perms != null && !perms.allows(permission);
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: _iconBox(icon, locked ? scheme.outline : color),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: locked ? scheme.outline : null)),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 11)) : null,
      trailing: locked
          ? Icon(Icons.lock_rounded, size: 16, color: scheme.outline)
          : Icon(Icons.chevron_left_rounded, size: 20, color: scheme.outlineVariant),
      onTap: () {
        if (locked) {
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text('صلاحية «${permission!.label}» موقوفة من الإدارة.')));
          return;
        }
        _open(context, page);
      },
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}
