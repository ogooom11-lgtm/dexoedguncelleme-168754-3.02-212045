import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class StudentBalancePage extends StatelessWidget {
  final String teacherCode;
  final String studentCode;
  final num hourlyRate;

  const StudentBalancePage({
    super.key,
    required this.teacherCode,
    required this.studentCode,
    required this.hourlyRate,
  });

  @override
  Widget build(BuildContext context) {
    final paymentsRef =
    FirebaseDatabase.instance.ref("users/$teacherCode/payments/$studentCode");
    final scheduleRef =
    FirebaseDatabase.instance.ref("users/$teacherCode/schedule");

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text("📊 تفاصيل الرصيد"),
            bottom: const TabBar(
              tabs: [
                Tab(text: "📖 الدروس"),
                Tab(text: "💳 المدفوعات"),
              ],
            ),
          ),
          body: Column(
            children: [
              // 🟢 الرصيد النهائي
              StreamBuilder(
                stream: paymentsRef.onValue,
                builder: (context, snapPayments) {
                  return StreamBuilder(
                    stream: scheduleRef.onValue,
                    builder: (context, snapLessons) {
                      num total = 0;

                      // ✅ المدفوعات
                      if (snapPayments.hasData &&
                          snapPayments.data?.snapshot.value != null) {
                        final map = Map<String, dynamic>.from(
                            snapPayments.data!.snapshot.value as Map);
                        for (var v in map.values) {
                          final p = Map<String, dynamic>.from(v);
                          final amount =
                              num.tryParse(p['amount']?.toString() ?? "0") ?? 0;
                          final payer =
                          (p['payer'] ?? "").toString().toLowerCase();
                          if (payer == "teacher") {
                            total -= amount;
                          } else {
                            total += amount;
                          }
                        }
                      }

                      // ✅ أجرة الدروس
                      if (snapLessons.hasData &&
                          snapLessons.data?.snapshot.value != null) {
                        final map = Map<String, dynamic>.from(
                            snapLessons.data!.snapshot.value as Map);
                        for (var v in map.values) {
                          final lesson = Map<String, dynamic>.from(v);
                          if (lesson['student'] == studentCode &&
                              lesson['status'] == "ended") {
                            final durationSec =
                                int.tryParse(lesson['duration']?.toString() ?? "0") ??
                                    0;
                            final hours = durationSec / 3600;
                            total -= (hours * hourlyRate);
                          }
                        }
                      }

                      return Card(
                        margin: const EdgeInsets.all(12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: total >= 0 ? Colors.green : Colors.red,
                            child: const Icon(Icons.account_balance_wallet,
                                color: Colors.white),
                          ),
                          title: const Text("الرصيد النهائي"),
                          trailing: Text(
                            "${total.toStringAsFixed(2)} ر.ق",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: total >= 0 ? Colors.green : Colors.red),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),

              Expanded(
                child: TabBarView(
                  children: [
                    // 🟢 تبويب الدروس
                    StreamBuilder(
                      stream: scheduleRef.onValue,
                      builder: (context, snap) {
                        if (!snap.hasData || snap.data?.snapshot.value == null) {
                          return const Center(child: Text("لا توجد دروس"));
                        }
                        final map = Map<String, dynamic>.from(
                            snap.data!.snapshot.value as Map);
                        final lessons = map.values
                            .map((e) => Map<String, dynamic>.from(e))
                            .where((l) =>
                        l['student'] == studentCode &&
                            l['status'] == "ended")
                            .toList();

                        return ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: lessons.length,
                          itemBuilder: (_, i) {
                            final l = lessons[i];
                            final durationSec =
                                int.tryParse(l['duration']?.toString() ?? "0") ??
                                    0;
                            final hours = durationSec / 3600;
                            final cost = hours * hourlyRate;
                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.book,
                                    color: Colors.indigo),
                                title: Text("📅 ${l['date']} • 🕒 ${l['time']}"),
                                subtitle: Text(
                                    "⏱ ${(hours).toStringAsFixed(2)} ساعة"),
                                trailing: Text(
                                  "-${cost.toStringAsFixed(2)} ر.ق",
                                  style: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),

                    // 🟢 تبويب المدفوعات
                    StreamBuilder(
                      stream: paymentsRef.onValue,
                      builder: (context, snap) {
                        if (!snap.hasData || snap.data?.snapshot.value == null) {
                          return const Center(child: Text("لا توجد مدفوعات"));
                        }
                        final map = Map<String, dynamic>.from(
                            snap.data!.snapshot.value as Map);
                        final payments = map.values
                            .map((e) => Map<String, dynamic>.from(e))
                            .toList();

                        return ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: payments.length,
                          itemBuilder: (_, i) {
                            final p = payments[i];
                            final amount =
                                num.tryParse(p['amount']?.toString() ?? "0") ??
                                    0;
                            final payer =
                            (p['payer'] ?? "").toString().toLowerCase();
                            final isTeacher = payer == "teacher";
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                  isTeacher ? Colors.red : Colors.green,
                                  child: Icon(
                                    isTeacher
                                        ? Icons.arrow_upward
                                        : Icons.arrow_downward,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                                    "📅 ${p['date'] ?? ''} ${p['time'] ?? ''}"),
                                subtitle: Text(isTeacher
                                    ? "دفعة من المعلم"
                                    : "دفعة من الطالب"),
                                trailing: Text(
                                  "${isTeacher ? '-' : '+'}$amount ر.ق",
                                  style: TextStyle(
                                    color:
                                    isTeacher ? Colors.red : Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
