import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../pages/teacher_add_student_page.dart';
import '../pages/teacher_add_ended_lesson_page.dart';
import '../pages/teacher_balance_page.dart';
import '../pages/teacher_lessons_page.dart';
import '../pages/teacher_payments_page.dart';
import '../pages/teacher_schedule_page.dart';
import '../providers/auth_provider.dart';
import '../pages/teacher_students_page.dart';
import '../pages/teacher_profile_page.dart';
import '../pages/notifications_debug_page.dart';
import '../pages/alarm_settings_page.dart';
import '../pages/today_recurring_page.dart';
import '../pages/recurring_schedules_page.dart';
import '../pages/teacher_timeline_page.dart';
import '../pages/teacher_profits_page.dart';
import '../services/notification_orchestrator.dart';
import '../theme/app_theme.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class TeacherSidebar extends StatelessWidget {
  const TeacherSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return Drawer(
      child: Column(
        children: [
          // ===== هيدر أنيق مع تدرج لوني =====
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              gradient: AppTheme.heroGradient(context),
            ),
            accountName: Text(
              user?.name ?? "معلم",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            accountEmail: Text("الكود: ${user?.code ?? ''}"),
            currentAccountPicture: CircleAvatar(
              radius: 35,
              backgroundColor: Colors.white,
              child:
                  Icon(Icons.person, size: 40, color: Colors.indigo.shade700),
            ),
          ),

          // ===== عناصر القائمة =====
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerItem(
                  context,
                  icon: Icons.people,
                  title: "الطلاب",
                  color: Colors.blue,
                  page: const TeacherStudentsPage(),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.person_add,
                  title: "إضافة طالب",
                  color: Colors.green,
                  page: const TeacherAddStudentPage(),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.history_edu,
                  title: "إضافة درس منتهي",
                  color: Colors.indigo,
                  page: const TeacherAddEndedLessonPage(),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.book,
                  title: "سجل الدروس",
                  color: Colors.deepPurple,
                  page: const TeacherLessonsPage(),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.event,
                  title: "المواعيد القادمة",
                  color: Colors.orange,
                  page: const TeacherSchedulePage(),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.event_available_sharp,
                  title: "تأكيد مواعيد اليوم",
                  color: Colors.pink,
                  page: const TodayRecurringPage(),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.event_repeat_outlined,
                  title: "المواعيد المكررة",
                  color: Colors.lime,
                  page: const RecurringSchedulesPage(),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.view_timeline_rounded,
                  title: "الجدول الزمني",
                  color: Colors.cyan,
                  page: const TeacherTimelinePage(),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.account_balance_wallet,
                  title: "الرصيد",
                  color: Colors.teal,
                  page: const TeacherBalancePage(),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.receipt_long,
                  title: "سجل الدفع",
                  color: Colors.red,
                  page: const TeacherPaymentsPage(),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.attach_money_outlined,
                  title: "المربح الشهري",
                  color: Colors.purpleAccent,
                  page: const ProfitsPage(),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.account_circle,
                  title: "الملف الشخصي",
                  color: Colors.blueGrey,
                  page: const TeacherProfilePage(),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.alarm,
                  title: "إعدادات المنبهات",
                  color: Colors.purple,
                  page: const AlarmSettingsPage(),
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.bug_report_outlined,
                  title: "فحص الإشعارات",
                  color: Colors.blueGrey,
                  page: const NotificationsDebugPage(),
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.withValues(alpha: 0.15),
                    child: const Icon(Icons.sync, color: Colors.orange),
                  ),
                  title: const Text("إعادة جدولة التنبيهات",
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text("تحليل الدروس وإنشاء التنبيهات يدوياً",
                      style: TextStyle(fontSize: 11)),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(context);
                    final code = user?.code ?? '';
                    if (code.isEmpty) return;
                    messenger.showSnackBar(const SnackBar(
                        content: Text("جارٍ إعادة جدولة التنبيهات...")));
                    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
                      await NotificationOrchestrator.rescheduleAll(
                          teacherCode: code);
                    }
                    messenger.showSnackBar(const SnackBar(
                        content: Text("تم تحديث تنبيهات الدروس ✅")));
                  },
                ),
                const Divider(),

                // ===== زر الوضع الداكن بشكل أنيق =====
                SwitchListTile(
                  title: const Text('الوضع الداكن',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  value: Theme.of(context).brightness == Brightness.dark,
                  onChanged: (_) => context.read<ThemeProvider>().toggle(),
                  secondary: const Icon(Icons.dark_mode, color: Colors.amber),
                ),
              ],
            ),
          ),

          // ===== زر تسجيل الخروج بالأسفل =====
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: Colors.red.shade600,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.logout, color: Colors.white),
                label: const Text("تسجيل الخروج",
                    style: TextStyle(color: Colors.white)),
                // عند تسجيل الخروج
                onPressed: () async {
                  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
                    await NotificationOrchestrator.onLogoutClearAll();
                  }

                  await auth.signOut();
                  if (!context.mounted) return;
                  Navigator.pushNamedAndRemoveUntil(
                      context, '/login', (route) => false);
                }),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget page,
    required Color color,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing:
          const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));
      },
    );
  }
}
