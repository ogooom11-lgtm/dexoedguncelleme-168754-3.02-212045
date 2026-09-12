import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class StudentPaymentsPage extends StatelessWidget {
  const StudentPaymentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final student = auth.currentUser!;
    final teacherCode = student.teacher ?? "";

    final paymentsRef =
    FirebaseDatabase.instance.ref("users/$teacherCode/payments/${student.code}");

    return Scaffold(
      appBar: AppBar(
        title: const Text("💳 مدفوعاتي"),
        centerTitle: true,
        backgroundColor: Colors.indigo,
      ),
      body: StreamBuilder(
        stream: paymentsRef.onValue,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data?.snapshot.value == null) {
            return const Center(
              child: Text("لا يوجد مدفوعات حتى الآن",
                  style: TextStyle(fontSize: 16, color: Colors.black54)),
            );
          }

          final data =
          Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);

          // ✅ حساب الرصيد ومعالجة البيانات
          num balance = 0;
          final payments = data.entries.map((e) {
            final v = Map<String, dynamic>.from(e.value);
            final amount = num.tryParse(v["amount"].toString()) ?? 0;
            final payer = v["payer"]?.toString() ?? "student";
            final date = v["date"]?.toString() ?? "";
            final note = v["note"]?.toString() ?? "";

            if (payer == "student") {
              balance += amount;
            } else {
              balance -= amount;
            }

            return {
              "amount": amount,
              "date": date,
              "note": note,
              "payer": payer,
            };
          }).toList()
            ..sort((a, b) {
              final da = DateTime.tryParse(a["date"].toString()) ?? DateTime.now();
              final db = DateTime.tryParse(b["date"].toString()) ?? DateTime.now();
              return db.compareTo(da);
            });

          return Column(
            children: [
              // ✅ بطاقة الرصيد
              Card(
                elevation: 4,
                margin: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: balance >= 0 ? Colors.green : Colors.red,
                    child: const Icon(Icons.account_balance_wallet,
                        color: Colors.white),
                  ),
                  title: const Text(
                    "الرصيد الكلي",
                    style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  trailing: Text(
                    "${balance >= 0 ? '+' : ''}$balance ر.ق",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: balance >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ),

              // ✅ قائمة العمليات
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: payments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final p = payments[i];
                    final amount = p["amount"] as num;
                    final date = p["date"].toString();
                    final note = p["note"].toString();
                    final payer = p["payer"].toString();

                    final isStudentPay = payer == "student";
                    final color = isStudentPay ? Colors.green : Colors.red;
                    final prefix = isStudentPay ? "+" : "-";
                    final payerText =
                    isStudentPay ? "👤 دفع الطالب" : "👨‍🏫 دفع المعلم";

                    return Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color,
                          child: Icon(
                            isStudentPay
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          "$prefix$amount ر.ق",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("📅 التاريخ: $date"),
                            Text(payerText),
                            if (note.isNotEmpty) Text("📝 $note"),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
