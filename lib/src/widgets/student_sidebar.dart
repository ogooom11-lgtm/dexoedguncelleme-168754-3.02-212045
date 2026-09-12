import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../pages/student_payments_page.dart';
import '../pages/student_lessons_page.dart';
import '../pages/student_request_lesson_page.dart'; // ✅ استدعاء صفحة الطلب

class StudentSidebar extends StatelessWidget {
  const StudentSidebar({super.key});

  Future<String> _fetchTeacherName(String teacherCode) async {
    if (teacherCode.isEmpty) return "غير معروف";
    final snap = await FirebaseDatabase.instance.ref("users/$teacherCode").get();
    if (snap.exists) {
      final data = Map<String, dynamic>.from(snap.value as Map);
      return data['name']?.toString() ?? "غير معروف";
    }
    return "غير معروف";
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;

    return Drawer(
      child: FutureBuilder<String>(
        future: _fetchTeacherName(user?.teacher ?? ""),
        builder: (context, snap) {
          final teacherName = snap.data ?? "جاري التحميل...";
          return Column(
            children: [
              UserAccountsDrawerHeader(
                decoration: BoxDecoration(
                  gradient: AppTheme.heroGradient(context),
                ),
                currentAccountPicture: const CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Icon(Icons.school, size: 40, color: Colors.indigo),
                ),
                accountName: Text(
                  user?.name ?? "الطالب",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.white,
                  ),
                ),
                accountEmail: Text(
                  "👨‍🏫 معلمك: $teacherName",
                  style: const TextStyle(color: Colors.white70),
                ),
              ),

              ListTile(
                leading: const Icon(Icons.book, color: Colors.indigo),
                title: const Text("دروسي",
                    style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StudentLessonsPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.payment, color: Colors.indigo),
                title: const Text("مدفوعاتي",
                    style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StudentPaymentsPage()),
                  );
                },
              ),

              // ✅ زر جديد لطلب موعد
              ListTile(
                leading: const Icon(Icons.add_circle, color: Colors.indigo),
                title: const Text("طلب موعد جديد",
                    style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StudentRequestLessonPage()),
                  );
                },
              ),

              const Spacer(),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text("تسجيل الخروج",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.red)),
                onTap: () async {
                  await auth.signOut();
                  if (!context.mounted) return;
                  Navigator.pushNamedAndRemoveUntil(
                      context, '/login', (route) => false);
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
