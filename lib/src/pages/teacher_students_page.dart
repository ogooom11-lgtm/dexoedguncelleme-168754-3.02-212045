// lib/src/pages/teacher_students_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/auth_provider.dart';
import '../services/permission_guard.dart';

class TeacherStudentsPage extends StatefulWidget {
  const TeacherStudentsPage({super.key});

  @override
  State<TeacherStudentsPage> createState() => _TeacherStudentsPageState();
}

class _TeacherStudentsPageState extends State<TeacherStudentsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final teacherCode = auth.currentUser?.code ?? "00000000";
    final dbRef = FirebaseDatabase.instance.ref("users/$teacherCode/students");

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: !_isSearching
              ? const Text("👥 الطلاب")
              : TextField(
            controller: _searchController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: "ابحث بالاسم أو الكود...",
              border: InputBorder.none,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  _searchController.clear();
                  _searchQuery = "";
                });
              },
            ),
          ],
        ),
        body: StreamBuilder<DatabaseEvent>(
          stream: dbRef.onValue,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
              return const Center(
                child: Text("لا يوجد طلاب بعد",
                    style: TextStyle(fontSize: 18, color: Colors.grey)),
              );
            }

            final data =
            Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
            final students = data.entries.where((entry) {
              final student = Map<String, dynamic>.from(entry.value);
              final name = (student['name'] ?? "").toString();
              final code = entry.key.toString();
              final q = _searchQuery.trim();
              if (q.isEmpty) return true;
              return name.contains(q) || code.contains(q);
            }).toList();

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: students.length,
              itemBuilder: (context, index) {
                final entry = students[index];
                final code = entry.key;
                final student = Map<String, dynamic>.from(entry.value);
                final name = (student['name'] ?? "طالب").toString();
                final rate = (student['hourlyRate'] ?? 0).toString();
                final gender = (student['gender'] ?? "").toString();

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                  child: ListTile(
                    leading: CircleAvatar(
                      radius: 26,
                      backgroundColor: _pickColor(name).withOpacity(.15),
                      child: Icon(Icons.person, color: _pickColor(name), size: 28),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("الكود: $code • سعر الساعة: $rate ر.ق"),
                        if (gender.isEmpty)
                          TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text("تحديد الجنس"),
                            onPressed: () => _openGenderDialog(context, teacherCode, code),
                          )
                        else
                          Text("الجنس: ${gender == "male" ? "ذكر" : "أنثى"}"),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == "profile") {
                          _openProfile(context, teacherCode, code, student);
                        } else if (value == "edit") {
                          if (!await PermissionGuard.check(context, TeacherPermission.editRates, teacherCode: teacherCode)) return;
                          if (!context.mounted) return;
                          _openEditStudent(context, teacherCode, code, student);
                        } else if (value == "share") {
                          final message =
                              "مرحباً $name 🌸\n\n"
                              "يمكنك متابعة حسابك من خلال الرابط التالي:\n"
                              "https://yourapp.com/update?code=$code\n\n"
                              "يرجى الدخول باستخدام الكود الخاص بك: $code";
                          await Share.share(message);
                        } else if (value == "copy") {
                          final message = "👤 $name • 🔑 $code";
                          await Clipboard.setData(ClipboardData(text: message));
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("📋 تم نسخ المعلومات")),
                            );
                          }
                        } else if (value == "delete") {
                          if (!await PermissionGuard.check(context, TeacherPermission.deleteStudents, teacherCode: teacherCode)) return;
                          if (!context.mounted) return;
                          await _attemptDeleteStudent(context, teacherCode, code, name);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: "profile",
                          child: Row(
                            children: [
                              Icon(Icons.folder_open, color: Colors.blue),
                              SizedBox(width: 8),
                              Text("عرض الملف"),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: "edit",
                          child: Row(
                            children: [
                              Icon(Icons.edit, color: Colors.green),
                              SizedBox(width: 8),
                              Text("تعديل"),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: "share",
                          child: Row(
                            children: [
                              Icon(Icons.share, color: Colors.purple),
                              SizedBox(width: 8),
                              Text("مشاركة"),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: "copy",
                          child: Row(
                            children: [
                              Icon(Icons.copy, color: Colors.orange),
                              SizedBox(width: 8),
                              Text("نسخ المعلومات"),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: "delete",
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red),
                              SizedBox(width: 8),
                              Text("حذف"),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ========= نافذة اختيار الجنس =========
  void _openGenderDialog(
      BuildContext context, String teacherCode, String studentCode) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("تحديد الجنس"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.panorama_fisheye_outlined),
              label: const Text("ذكر"),
              onPressed: () async {
                await FirebaseDatabase.instance
                    .ref("users/$teacherCode/students/$studentCode")
                    .update({"gender": "male"});
                if (context.mounted) Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.panorama_fisheye_outlined),
              label: const Text("أنثى"),
              onPressed: () async {
                await FirebaseDatabase.instance
                    .ref("users/$teacherCode/students/$studentCode")
                    .update({"gender": "female"});
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ========= منطق الحذف مع القيود =========
  Future<void> _attemptDeleteStudent(BuildContext context, String teacherCode,
      String studentCode, String name) async {
    final balance = await _calculateStudentBalance(
        teacherCode: teacherCode, studentCode: studentCode);

    final normalized = (balance * 100).round() / 100.0;

    if (normalized != 0) {
      await _showErrorDialog(
        context,
        title: "لا يمكن الحذف",
        message:
        "رصيد الطالب حالياً: ${normalized >= 0 ? '+' : ''}$normalized ر.ق\n"
            "لا يمكن حذف الطالب إلا إذا كان الرصيد = 0.",
      );
      return;
    }

    final hasActive = await _hasActiveLessons(
      teacherCode: teacherCode,
      studentCode: studentCode,
    );
    if (hasActive) {
      await _showErrorDialog(
        context,
        title: "لا يمكن الحذف",
        message: "يوجد دروس مجدولة أو قيد التنفيذ لهذا الطالب.\n"
            "رجاءً أنهِ أو ألغِ هذه الدروس أولاً.",
      );
      return;
    }

    final confirm = await _confirmDelete(context,
        message:
        "هل أنت متأكد أنك تريد حذف الطالب $name (الكود: $studentCode)؟");
    if (confirm != true) return;

    try {
      final base = FirebaseDatabase.instance.ref("users/$teacherCode");
      await base.child("students/$studentCode").remove();
      await base.child("payments/$studentCode").remove();

      final rootRef = FirebaseDatabase.instance.ref("users/$studentCode");
      final rootSnap = await rootRef.get();
      if (rootSnap.exists) {
        final rootMap = Map<String, dynamic>.from(rootSnap.value as Map);
        final role = (rootMap['role'] ?? 'student').toString();
        final teacher = (rootMap['teacher'] ?? '').toString();
        if (role == 'student' && teacher == teacherCode) {
          await rootRef.remove();
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ تم حذف الطالب $name"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ حدث خطأ أثناء الحذف: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<double> _calculateStudentBalance({
    required String teacherCode,
    required String studentCode,
  }) async {
    final lessonsRef =
    FirebaseDatabase.instance.ref("users/$teacherCode/schedule");
    final paymentsRef =
    FirebaseDatabase.instance.ref("users/$teacherCode/payments/$studentCode");

    double lessonsTotal = 0;
    final lessonsSnap = await lessonsRef.get();
    if (lessonsSnap.exists && lessonsSnap.value != null) {
      final lessons = Map<String, dynamic>.from(lessonsSnap.value as Map);
      lessons.forEach((_, v) {
        final m = Map<String, dynamic>.from(v);
        final s = (m['status'] ?? '').toString();
        final forStudent = (m['student'] ?? '').toString() == studentCode;
        if (forStudent && s == 'ended') {
          lessonsTotal += double.tryParse("${m['amount']}") ?? 0.0;
        }
      });
    }

    double studentPaymentsTotal = 0;
    double teacherPaymentsTotal = 0;

    final paymentsSnap = await paymentsRef.get();
    if (paymentsSnap.exists && paymentsSnap.value != null) {
      final payments = Map<String, dynamic>.from(paymentsSnap.value as Map);
      payments.forEach((_, v) {
        final p = Map<String, dynamic>.from(v as Map);
        final payer = (p['payer'] ?? 'student').toString();
        final amount = double.tryParse("${p['amount']}") ?? 0.0;
        if (payer == "student") {
          studentPaymentsTotal += amount;
        } else if (payer == "teacher") {
          teacherPaymentsTotal += amount;
        }
      });
    }

    return lessonsTotal - studentPaymentsTotal + teacherPaymentsTotal;
  }

  Future<bool> _hasActiveLessons({
    required String teacherCode,
    required String studentCode,
  }) async {
    final ref = FirebaseDatabase.instance.ref("users/$teacherCode/schedule");
    final snap = await ref.get();
    if (!snap.exists || snap.value == null) return false;

    final map = Map<String, dynamic>.from(snap.value as Map);
    for (final v in map.values) {
      final m = Map<String, dynamic>.from(v as Map);
      final forStudent = (m['student'] ?? '').toString() == studentCode;
      final status = (m['status'] ?? '').toString();
      if (forStudent && (status == 'scheduled' || status == 'started')) {
        return true;
      }
    }
    return false;
  }

  // ========= حواريات وأدوات واجهة ==========
  Future<void> _showErrorDialog(BuildContext context,
      {required String title, required String message}) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("حسناً"),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context,
      {required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("تأكيد الحذف"),
        content: Text(message),
        actions: [
          TextButton(
            child: const Text("إلغاء"),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("حذف"),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
  }

  void _openProfile(BuildContext context, String teacherCode, String code,
      Map<String, dynamic> student) {
    final name = student['name'] ?? "غير معروف";
    final gender = student['gender'] ?? "غير محدد";
    final message =
        "🌟 معلومات الطالب\n👤 الاسم: $name\n🔑 الكود: $code\n الجنس: $gender";
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("ملف الطالب",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(message),
              const SizedBox(height: 16),
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text("نسخ"),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: message));
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("📋 تم نسخ المعلومات")),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.share),
                    label: const Text("مشاركة"),
                    onPressed: () => Share.share(message),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openEditStudent(BuildContext context, String teacherCode,
      String oldCode, Map<String, dynamic> student) {
    final nameController =
    TextEditingController(text: (student['name'] ?? "").toString());
    final rateController =
    TextEditingController(text: (student['hourlyRate'] ?? "").toString());
    String gender = (student['gender'] ?? "").toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("تعديل بيانات الطالب",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: "الاسم",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rateController,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
              ],
              decoration: const InputDecoration(
                labelText: "سعر الساعة",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: gender.isEmpty ? null : gender,
              items: const [
                DropdownMenuItem(value: "male", child: Text("ذكر")),
                DropdownMenuItem(value: "female", child: Text("أنثى")),
              ],
              decoration: const InputDecoration(
                labelText: "الجنس",
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => gender = v ?? "",
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text("حفظ"),
                onPressed: () async {
                  final name = nameController.text.trim();
                  final rate =
                      double.tryParse(rateController.text.trim()) ?? 0;
                  final dbRef = FirebaseDatabase.instance
                      .ref("users/$teacherCode/students");
                  await dbRef.child(oldCode).update({
                    "name": name,
                    "hourlyRate": rate,
                    "gender": gender,
                  });
                  if (context.mounted) Navigator.pop(context);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text("✅ تم تحديث بيانات الطالب")),
                    );
                  }
                },
              ),
            )
          ],
        ),
      ),
    );
  }

  Color _pickColor(String name) {
    final materialColors = [
      Colors.blue,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.indigo,
      Colors.brown,
      Colors.pink,
      Colors.cyan,
      Colors.lime,
      Colors.amber,
    ];
    final i = name.hashCode.abs() % materialColors.length;
    return materialColors[i];
  }
}
