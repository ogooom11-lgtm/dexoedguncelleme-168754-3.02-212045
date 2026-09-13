import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/permission_guard.dart';

class TeacherPayPage extends StatefulWidget {
  final String teacherCode;
  final String studentCode;
  final String studentName;
  final double balance;

  const TeacherPayPage({
    super.key,
    required this.teacherCode,
    required this.studentCode,
    required this.studentName,
    required this.balance,
  });

  @override
  State<TeacherPayPage> createState() => _TeacherPayPageState();
}

class _TeacherPayPageState extends State<TeacherPayPage> {
  final TextEditingController _amountController = TextEditingController();

  String payer = "student"; // student | teacher
  String method = "cash"; // cash | bank

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _savePayment() async {
    if (!await PermissionGuard.check(context, TeacherPermission.recordPayments,
        teacherCode: widget.teacherCode)) {
      return;
    }
    if (!mounted) return;
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ أدخل مبلغاً صحيحاً")),
      );
      return;
    }

    final paymentsRef = FirebaseDatabase.instance.ref(
      "users/${widget.teacherCode}/payments/${widget.studentCode}",
    );

    await paymentsRef.push().set({
      "amount": amount,
      "payer": payer,
      "method": method,
      "date": DateTime.now().toIso8601String(),
    });

    if (mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "✅ تم تسجيل دفعة $amount ر.ق (${payer == 'teacher' ? 'المعلم' : 'الطالب'}) - ${method == 'cash' ? 'كاش' : 'بنك'}"),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildHeaderCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              widget.studentName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "الرصيد: ${widget.balance.toStringAsFixed(2)} ر.ق",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: widget.balance < 0 ? Colors.red : Colors.blue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionsCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ✅ اختيار الدافع + طريقة الدفع جنب بعض
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text("الدافع", style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 8),
                      ToggleButtons(
                        borderRadius: BorderRadius.circular(12),
                        borderColor: Colors.grey.shade400,
                        selectedBorderColor: Colors.green.shade700,
                        fillColor: Colors.green.shade100,
                        isSelected: [payer == "student", payer == "teacher"],
                        onPressed: (index) {
                          setState(() {
                            payer = index == 0 ? "student" : "teacher";
                          });
                        },
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: const [
                                Icon(Icons.school, size: 30, color: Colors.blue),
                                SizedBox(height: 4),
                                Text("الطالب"),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: const [
                                Icon(Icons.person,
                                    size: 30, color: Colors.deepOrange),
                                SizedBox(height: 4),
                                Text("المعلم"),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [
                      const Text("طريقة الدفع", style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 8),
                      ToggleButtons(
                        borderRadius: BorderRadius.circular(12),
                        borderColor: Colors.grey.shade400,
                        selectedBorderColor: Colors.green.shade700,
                        fillColor: Colors.green.shade100,
                        isSelected: [method == "cash", method == "bank"],
                        onPressed: (index) {
                          setState(() {
                            method = index == 0 ? "cash" : "bank";
                          });
                        },
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: const [
                                Icon(Icons.attach_money,
                                    size: 30, color: Colors.green),
                                SizedBox(height: 4),
                                Text("كاش"),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: const [
                                Icon(Icons.account_balance,
                                    size: 30, color: Colors.indigo),
                                SizedBox(height: 4),
                                Text("بنك"),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ✅ إدخال المبلغ
            TextField(
              controller: _amountController,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: "المبلغ",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.payments),
              ),
            ),

            const SizedBox(height: 12),

            // زر دفع كامل المبلغ
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {
                final fill = widget.balance > 0 ? widget.balance : 0;
                _amountController.text =
                    fill.toStringAsFixed(0).replaceAll('.0', '');
              },
              icon: const Icon(Icons.done_all),
              label: const Text("دفع المبلغ كامل"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: Text("💵 دفع - ${widget.studentName}"),
        backgroundColor: Colors.green.shade700,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: isWide
            ? Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 1, child: _buildHeaderCard()),
            const SizedBox(width: 20),
            Expanded(flex: 2, child: _buildOptionsCard()),
          ],
        )
            : Column(
          children: [
            _buildHeaderCard(),
            const SizedBox(height: 20),
            _buildOptionsCard(),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
          onPressed: _savePayment,
          child: const Text(
            "تسجيل الدفع",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
