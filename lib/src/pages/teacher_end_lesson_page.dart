import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/notification_service_wrapper.dart';
import '../services/timeline_models.dart' show TimelineFormat;

class TeacherEndLessonPage extends StatefulWidget {
  final Map<String, dynamic> payload;

  const TeacherEndLessonPage({
    super.key,
    required this.payload,
  });

  @override
  State<TeacherEndLessonPage> createState() => _TeacherEndLessonPageState();
}

class _TeacherEndLessonPageState extends State<TeacherEndLessonPage> {
  final _noteController = TextEditingController();
  bool _loading = false;

  late String lessonId;
  late String student;
  late int seconds;
  late int amount; // صار int بدل double

  @override
  void initState() {
    super.initState();
    final p = widget.payload;
    lessonId = p["lessonId"] ?? "";
    student = p["student"] ?? "";
    seconds = int.tryParse(p["seconds"] ?? "0") ?? 0;
    amount = double.tryParse(p["amount"] ?? "0")?.round() ?? 0; // تحويل لعدد صحيح
  }

  Future<void> _finishLesson() async {
    setState(() => _loading = true);

    try {
      final auth = context.read<AuthProvider>();
      final teacherCode = auth.currentUser?.code ?? "";
      final ref =
      FirebaseDatabase.instance.ref("users/$teacherCode/schedule/$lessonId");

      await ref.update({
        "status": "ended",
        "endTime": DateTime.now().toIso8601String(),
        "duration": seconds,
        "amount": amount, // تخزين كعدد صحيح
        "note": _noteController.text.trim(),
      });

      await NotificationServiceWrapper.cancelLessonNotification(lessonId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "تم إنهاء الدرس بنجاح",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("خطأ: $e")),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatTime(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundGradient = isDark
        ? const LinearGradient(
      colors: [Color(0xFF1E1E2C), Color(0xFF121212)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    )
        : const LinearGradient(
      colors: [Color(0xFFEDE7F6), Color(0xFFD1C4E9)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // العنوان العلوي
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "إنهاء الدرس",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: textColor),
                      onPressed: () => Navigator.pop(context),
                    )
                  ],
                ),
                const SizedBox(height: 20),

                // اسم الطالب
                Text(
                  student,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // فقاعة فيها المدة + المبلغ
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[900] : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Icon(Icons.timer,
                              size: 40, color: Colors.deepPurple),
                          const SizedBox(height: 8),
                          Text(
                            _formatTime(seconds),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          const Icon(Icons.attach_money,
                              size: 40, color: Colors.green),
                          const SizedBox(height: 8),
                          Text(
                            "$amount ${TimelineFormat.currency}", // عرض بدون فاصلات
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // مربع النص للملاحظات
                TextField(
                  controller: _noteController,
                  maxLines: 3,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: isDark ? Colors.grey[850] : Colors.white,
                    labelText: "ماذا درست اليوم؟",
                    labelStyle: TextStyle(color: textColor),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),

                const Spacer(),

                _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : ElevatedButton.icon(
                  icon: const Icon(Icons.save, color: Colors.white),
                  label: const Text(
                    "إنهاء وحفظ",
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    minimumSize: const Size.fromHeight(55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 6,
                  ),
                  onPressed: _finishLesson,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
