import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import '../providers/auth_provider.dart';
import 'student_lessons_page.dart';
import 'student_payments_page.dart';
import 'student_request_lesson_page.dart';
import 'student_profile_page.dart'; // ✅ استدعاء صفحة الحساب الجديدة

class HomeStudent extends StatefulWidget {
  const HomeStudent({super.key});

  @override
  State<HomeStudent> createState() => _HomeStudentState();
}

class _HomeStudentState extends State<HomeStudent> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();

  void _onTap(int index) {
    setState(() => _selectedIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          _DashboardPage(),
          StudentLessonsPage(),
          StudentPaymentsPage(),
          StudentProfilePage(), // ✅ صفحة الحساب الجديدة
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTap,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.indigo,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "الرئيسية"),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: "الدروس"),
          BottomNavigationBarItem(icon: Icon(Icons.payment), label: "المدفوعات"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "الحساب"),
        ],
      ),
    );
  }
}

//
// ✅ الصفحة الرئيسية (Dashboard)
//
class _DashboardPage extends StatelessWidget {
  const _DashboardPage();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final student = auth.currentUser!;
    final teacherCode = student.teacher ?? "";

    final db = FirebaseDatabase.instance;
    final lessonsRef = db.ref("users/$teacherCode/schedule");
    final paymentsRef = db.ref("users/$teacherCode/payments/${student.code}");

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: const Text(
          "مرحباً 👋",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.indigo,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            //
            // 💳 بطاقة الرصيد
            //
            StreamBuilder(
              stream: paymentsRef.onValue,
              builder: (context, snapshot) {
                num balance = 0;
                if (snapshot.hasData && snapshot.data?.snapshot.value != null) {
                  final data = Map<String, dynamic>.from(
                      snapshot.data!.snapshot.value as Map);
                  for (final e in data.values) {
                    final v = Map<String, dynamic>.from(e);
                    final amount = num.tryParse(v["amount"].toString()) ?? 0;
                    final payer = v["payer"]?.toString() ?? "student";
                    if (payer == "student") {
                      balance += amount;
                    } else {
                      balance -= amount;
                    }
                  }
                }
                return Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.indigo, Colors.deepPurple],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.account_balance_wallet,
                          color: Colors.white, size: 40),
                      const SizedBox(height: 10),
                      const Text(
                        "رصيدي",
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontWeight: FontWeight.w500),
                      ),
                      Text(
                        "$balance ر.ق",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            //
            // 📅 أقرب موعد
            //
            StreamBuilder(
              stream: lessonsRef.onValue,
              builder: (context, snapshot) {
                if (!snapshot.hasData ||
                    snapshot.data?.snapshot.value == null) {
                  return const SizedBox.shrink();
                }

                final data = Map<String, dynamic>.from(
                    snapshot.data!.snapshot.value as Map);

                final lessons = data.entries
                    .map((e) => Map<String, dynamic>.from(e.value))
                    .where((e) => e["student"] == student.code)
                    .toList();

                lessons.sort((a, b) {
                  final da = DateTime.tryParse(a['startTime'] ?? '') ??
                      DateTime(2100);
                  final db = DateTime.tryParse(b['startTime'] ?? '') ??
                      DateTime(2100);
                  return da.compareTo(db);
                });

                final nextLesson =
                lessons.firstWhere((l) => l['status'] == "scheduled",
                    orElse: () => {});

                if (nextLesson.isEmpty) return const SizedBox.shrink();

                return Card(
                  elevation: 6,
                  color: Colors.indigo.shade50,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.indigo,
                      child: const Icon(Icons.event, color: Colors.white),
                    ),
                    title: Text("موعدك القادم: ${nextLesson['date']}"),
                    subtitle: Text(
                        "⏱ ${nextLesson['startTime']} → ${nextLesson['endTime']}"),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),

            //
            // 📖 آخر 3 دروس
            //
            _SectionHeader(title: "📖 آخر 3 دروس"),
            StreamBuilder(
              stream: lessonsRef.onValue,
              builder: (context, snapshot) {
                if (!snapshot.hasData ||
                    snapshot.data?.snapshot.value == null) {
                  return const Text("لا يوجد دروس بعد");
                }

                final data = Map<String, dynamic>.from(
                    snapshot.data!.snapshot.value as Map);

                final lessons = data.entries
                    .map((e) => Map<String, dynamic>.from(e.value))
                    .where((e) => e["student"] == student.code)
                    .toList();

                lessons.sort((a, b) {
                  final da = DateTime.tryParse(a['endTime'] ?? '') ??
                      DateTime(2000);
                  final db = DateTime.tryParse(b['endTime'] ?? '') ??
                      DateTime(2000);
                  return db.compareTo(da);
                });

                final last3 = lessons.take(3).toList();

                return Column(
                  children: last3.map((l) {
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const Icon(Icons.book,
                            color: Colors.deepPurple),
                        title: Text("📅 ${l['date']}"),
                        subtitle: Text("⏱ ${l['startTime']} → ${l['endTime']}"),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 20),

            //
            // 💵 آخر 3 مدفوعات
            //
            _SectionHeader(title: "💵 آخر 3 مدفوعات"),
            StreamBuilder(
              stream: paymentsRef.onValue,
              builder: (context, snapshot) {
                if (!snapshot.hasData ||
                    snapshot.data?.snapshot.value == null) {
                  return const Text("لا يوجد مدفوعات بعد");
                }

                final data = Map<String, dynamic>.from(
                    snapshot.data!.snapshot.value as Map);

                final payments = data.values.map((e) {
                  final v = Map<String, dynamic>.from(e);
                  return v;
                }).toList()
                  ..sort((a, b) {
                    final da =
                        DateTime.tryParse(a["date"].toString()) ??
                            DateTime.now();
                    final db =
                        DateTime.tryParse(b["date"].toString()) ??
                            DateTime.now();
                    return db.compareTo(da);
                  });

                final last3 = payments.take(3).toList();

                return Column(
                  children: last3.map((p) {
                    final amount = p["amount"].toString();
                    final date = p["date"].toString();
                    final isStudent = p["payer"] == "student";
                    final color = isStudent ? Colors.green : Colors.red;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color,
                          child: Icon(
                              isStudent
                                  ? Icons.arrow_downward
                                  : Icons.arrow_upward,
                              color: Colors.white),
                        ),
                        title: Text("$amount ر.ق",
                            style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold)),
                        subtitle: Text("📅 $date"),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 20),

            ElevatedButton.icon(
              icon: const Icon(Icons.add_circle),
              label: const Text("طلب موعد جديد"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const StudentRequestLessonPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

//
// ✅ عنوان القسم
//
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.indigo,
          ),
        ),
      ),
    );
  }
}
