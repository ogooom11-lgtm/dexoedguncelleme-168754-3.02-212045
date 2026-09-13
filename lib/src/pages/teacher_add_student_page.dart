import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../providers/auth_provider.dart';
import '../services/permission_guard.dart';

class TeacherAddStudentPage extends StatefulWidget {
  const TeacherAddStudentPage({super.key});

  @override
  State<TeacherAddStudentPage> createState() => _TeacherAddStudentPageState();
}

class _TeacherAddStudentPageState extends State<TeacherAddStudentPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _rateController = TextEditingController();
  String? _gender; // ✅ متغير لتخزين الجنس
  bool _loading = false;

  Future<String> _generateUniqueCode(String teacherCode) async {
    const chars = "0123456789";
    final random = Random();
    final dbRef = FirebaseDatabase.instance.ref("users/$teacherCode/students");

    while (true) {
      final code =
      List.generate(8, (index) => chars[random.nextInt(chars.length)]).join();

      final snapshot = await dbRef.child(code).get();
      if (!snapshot.exists) {
        return code;
      }
    }
  }

  Future<void> _addStudent() async {
    if (!_formKey.currentState!.validate()) return;
    if (!await PermissionGuard.check(context, TeacherPermission.addStudents,
        teacherCode: context.read<AuthProvider>().currentUser?.code)) {
      return;
    }
    if (!mounted) return;
    if (_gender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ يرجى تحديد الجنس")),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final auth = context.read<AuthProvider>();
      final teacherCode = auth.currentUser?.code ?? "";
      final dbRef = FirebaseDatabase.instance.ref("users/$teacherCode/students");

      final name = _nameController.text.trim();
      final hourlyRate = double.tryParse(_rateController.text) ?? 0;

      final code = await _generateUniqueCode(teacherCode);

      await auth.createStudent(name, code, teacherCode);

      await dbRef.child(code).set({
        "name": name,
        "hourlyRate": hourlyRate,
        "gender": _gender, // ✅ تخزين الجنس
        "createdAt": DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ تم إضافة الطالب $name (الكود: $code)"),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ حدث خطأ: ${e.toString().replaceFirst('Exception: ', '')}"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("➕ إضافة طالب"),
          centerTitle: true,
          backgroundColor: Colors.indigo,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const Icon(Icons.school, size: 80, color: Colors.indigo),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: "اسم الطالب",
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (v) =>
                  (v == null || v.trim().isEmpty) ? "الاسم مطلوب" : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _rateController,
                  decoration: InputDecoration(
                    labelText: "سعر الساعة",
                    prefixIcon: const Icon(Icons.attach_money),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                  ],
                ),
                const SizedBox(height: 16),

                // ✅ اختيار الجنس
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text("ذكر"),
                        value: "male",
                        groupValue: _gender,
                        onChanged: (v) => setState(() => _gender = v),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text("أنثى"),
                        value: "female",
                        groupValue: _gender,
                        onChanged: (v) => setState(() => _gender = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                _loading
                    ? const CircularProgressIndicator()
                    : SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.person_add),
                    label: const Text("إضافة الطالب"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _addStudent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
