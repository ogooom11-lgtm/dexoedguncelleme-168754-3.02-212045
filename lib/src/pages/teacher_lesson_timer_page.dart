import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:awesome_notifications/awesome_notifications.dart';

import '../providers/auth_provider.dart';
import 'teacher_end_lesson_page.dart';
import 'teacher_cancel_lesson_page.dart';


class TeacherLessonTimerPage extends StatefulWidget {
  final String lessonId;

  const TeacherLessonTimerPage({
    super.key,
    required this.lessonId,
  });

  @override
  State<TeacherLessonTimerPage> createState() => _TeacherLessonTimerPageState();
}

class _TeacherLessonTimerPageState extends State<TeacherLessonTimerPage>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  int _seconds = 0;
  bool _running = false;

  Map<String, dynamic>? _lesson;
  double _hourlyRate = 0;

  String _billingMode = "hour"; // "hour", "minute", "half"
  bool _lessonEnded = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  List<Map<String, dynamic>> _runningLessons = [];
  int _currentIndex = 0;
  late PageController _pageController;

  DateTime? _endTime;

  bool _completeHour = false; // خيار إكمال أجور الساعة داخل صفحة المؤقت

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.85);
    _loadRunningLessons();

    _animController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeInOut);
    _scaleAnim = Tween<double>(begin: 0.9, end: 1.0).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOutBack));

    _animController.forward();
  }

  Future<void> _loadRunningLessons() async {
    final auth = context.read<AuthProvider>();
    final teacherCode = auth.currentUser?.code ?? "";
    final ref = FirebaseDatabase.instance.ref("users/$teacherCode/schedule");

    final snap = await ref.get();
    if (!snap.exists) {
      setState(() => _runningLessons = []);
      return;
    }

    final data = Map<String, dynamic>.from(snap.value as Map);
    final running = <Map<String, dynamic>>[];

    for (final e in data.entries) {
      if (e.value is Map && (e.value as Map)['status'] == "started") {
        final lesson = Map<String, dynamic>.from(e.value as Map);
        lesson['id'] = e.key;

        if (lesson['student'] != null) {
          final studentSnap = await FirebaseDatabase.instance
              .ref("users/$teacherCode/students/${lesson['student']}")
              .get();
          if (studentSnap.exists) {
            final studentData = Map<String, dynamic>.from(studentSnap.value as Map);
            lesson['studentName'] = studentData['name'] ?? lesson['student'];
            lesson['hourlyRate'] =
                double.tryParse(studentData['hourlyRate'].toString()) ?? 0;
          }
        }

        running.add(lesson);
      }
    }

    setState(() {
      _runningLessons = running;
      if (_runningLessons.isNotEmpty) {
        final index = _runningLessons.indexWhere((l) => l['id'] == widget.lessonId);
        _currentIndex = index != -1 ? index : 0;

        _lesson = _runningLessons[_currentIndex];
        _hourlyRate = _lesson?['hourlyRate'] ?? 0;
        _resumeTimerIfStarted(_lesson!);

        if (_lesson?['startTime'] != null && _lesson?['duration'] != null) {
          final start = DateTime.tryParse(_lesson!['startTime']);
          final durationSec = int.tryParse(_lesson!['duration'].toString()) ?? 0;
          if (start != null && durationSec > 0) {
            _endTime = start.add(Duration(seconds: durationSec));
          }
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pageController.jumpToPage(_currentIndex);
        });
      }
    });
  }

  void _resumeTimerIfStarted(Map<String, dynamic> lessonData) {
    if (lessonData['status'] == "started" && lessonData['startTime'] != null) {
      final startTime = DateTime.tryParse(lessonData['startTime']);
      if (startTime != null) {
        final elapsed = DateTime.now().difference(startTime).inSeconds;
        setState(() {
          _seconds = elapsed;
          _running = true;
        });
        _startTimer();
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_lessonEnded) {
        setState(() => _seconds++);
      }
    });
  }

  Future<void> _startLesson() async {
    if (_lesson == null) return;

    final auth = context.read<AuthProvider>();
    final teacherCode = auth.currentUser?.code ?? "";
    final ref =
    FirebaseDatabase.instance.ref("users/$teacherCode/schedule/${_lesson!['id']}");

    final now = DateTime.now();

    await ref.update({
      "status": "started",
      "startTime": now.toIso8601String(),
    });

    setState(() {
      _seconds = 0;
      _running = true;
    });

    _startTimer();
  }

  double _calculateAmount() {
    if (_hourlyRate <= 0) return 0;

    double amount;
    if (_billingMode == "minute") {
      final minutes = (_seconds / 60).floor();
      final perMinute = _hourlyRate / 60.0;
      amount = minutes * perMinute;
    } else if (_billingMode == "half") {
      final halfHours = (_seconds / 1800).floor();
      final perHalfHour = _hourlyRate / 2.0;
      amount = halfHours * perHalfHour;
    } else {
      final hours = (_seconds / 3600).floor();
      amount = hours * _hourlyRate;
    }

    // إذا الخيار مفعل والشرط يتوافر -> نكمل للساعة التالية أو للساعات التالية
    if (_completeHour && _shouldShowCompleteHourOption) {
      final baseFullHours = _seconds ~/ 3600; // ساعات كاملة الموجودة
      amount = (baseFullHours + 1) * _hourlyRate;
    }

    // احتفظ بدقة بسيطة ولكن اقرب قيمة عشرية صحيحة كما في المشروع الأصلي
    return double.parse(amount.toStringAsFixed(2));
  }

  // دالة تحدد متى يظهر خيار إكمال أجور الساعة:
  // if fractional part of hours is between 0.5 (>=) and <1.0 -> show.
  // هذا ينطبق لأي ساعة: بين 0.5-1.0 أو 1.5-2.0 أو 2.5-3.0 وهكذا.
  bool get _shouldShowCompleteHourOption {
    final hours = _seconds / 3600.0;
    final fractional = hours - hours.floor();
    return fractional >= 0.5 && fractional < 1.0;
  }

  String _formatTime(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  String _countdownText(DateTime endTime) {
    final remaining = endTime.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      final overtime = -remaining;
      return "+${_formatTime(overtime)}";
    }
    return _formatTime(remaining);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    if (index < 0 || index >= _runningLessons.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeFormatted = _formatTime(_seconds);
    final currentAmount = _calculateAmount();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundGradient = isDark
        ? const LinearGradient(
      colors: [Colors.black, Colors.grey],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    )
        : const LinearGradient(
      colors: [Color(0xFFEDE7F6), Color(0xFFD1C4E9)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Scaffold(
      // SafeArea لضمان عدم تداخل العناصر مع شريط النظام -> يمنع overflow من الأسفل
      body: SafeArea(
        bottom: true,
        child: Container(
          decoration: BoxDecoration(gradient: backgroundGradient),
          // نستخدم padding أسفل إضافي بسيط لضمان مسافة بين العناصر وبين حافة الشاشة
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8),
          child: _runningLessons.isEmpty
              ? const Center(
              child: Text("لا يوجد دروس جارية",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)))
              : Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: _runningLessons.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                    _lesson = _runningLessons[index];
                    _seconds = 0;
                    _running = false;
                    _lessonEnded = false;
                    _hourlyRate = _lesson?['hourlyRate'] ?? 0;
                    _completeHour = false;
                    _resumeTimerIfStarted(_lesson!);

                    if (_lesson?['startTime'] != null &&
                        _lesson?['duration'] != null) {
                      final start = DateTime.tryParse(_lesson!['startTime']);
                      final durationSec =
                          int.tryParse(_lesson!['duration'].toString()) ?? 0;
                      if (start != null && durationSec > 0) {
                        _endTime = start.add(Duration(seconds: durationSec));
                      }
                    }
                  });
                },
                itemBuilder: (context, index) {
                  final lesson = _runningLessons[index];
                  final startTime = lesson['startTime'] != null
                      ? DateTime.tryParse(lesson['startTime'])
                      : null;

                  final durationSeconds = lesson['duration'] != null
                      ? int.tryParse(lesson['duration'].toString()) ?? 0
                      : 0;

                  DateTime? endTime;
                  double progress = 0;

                  if (startTime != null && durationSeconds > 0) {
                    endTime = startTime.add(Duration(seconds: durationSeconds));
                    progress =
                        (_seconds / durationSeconds).clamp(0, 1).toDouble();
                  }

                  return FadeTransition(
                    opacity: _fadeAnim,
                    child: ScaleTransition(
                      scale: _scaleAnim,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Card(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          elevation: 10,
                          color: isDark
                              ? Colors.grey.shade900
                              : Colors.white.withOpacity(0.9),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                // المحتوى العلوي يمكنه التمرير إذا شاشات صغيرة -> يمنع overflow
                                Flexible(
                                  child: SingleChildScrollView(
                                    physics: const BouncingScrollPhysics(),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          lesson['studentName'] ??
                                              lesson['student'] ??
                                              '',
                                          style: const TextStyle(
                                              fontSize: 28,
                                              fontWeight: FontWeight.bold),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 15),

                                        if (endTime != null) ...[
                                          if (endTime
                                              .difference(DateTime.now())
                                              .inMinutes <=
                                              5 ||
                                              endTime.isBefore(DateTime.now()))
                                            Text(
                                              _countdownText(endTime),
                                              style: TextStyle(
                                                fontSize: 40,
                                                fontWeight: FontWeight.bold,
                                                color: endTime
                                                    .difference(DateTime.now())
                                                    .inSeconds <=
                                                    0
                                                    ? Colors.red
                                                    : Colors.deepPurple,
                                              ),
                                            ),
                                          const SizedBox(height: 8),
                                          LinearProgressIndicator(
                                            value: progress,
                                            minHeight: 10,
                                            backgroundColor: Colors.grey.shade300,
                                            color: Colors.deepPurple,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            "ينتهي عند: ${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}",
                                            style: const TextStyle(
                                                fontSize: 14, color: Colors.grey),
                                          ),
                                        ],

                                        const SizedBox(height: 25),

                                        ToggleButtons(
                                          isSelected: [
                                            _billingMode == "hour",
                                            _billingMode == "minute",
                                            _billingMode == "half",
                                          ],
                                          onPressed: (i) {
                                            setState(() {
                                              if (i == 0) _billingMode = "hour";
                                              if (i == 1) _billingMode = "minute";
                                              if (i == 2) _billingMode = "half";
                                            });
                                          },
                                          borderRadius: BorderRadius.circular(12),
                                          selectedColor: Colors.white,
                                          fillColor: Colors.deepPurple,
                                          color: Colors.deepPurple,
                                          children: const [
                                            Padding(
                                                padding: EdgeInsets.symmetric(
                                                    horizontal: 16),
                                                child: Text("بالساعة")),
                                            Padding(
                                                padding: EdgeInsets.symmetric(
                                                    horizontal: 16),
                                                child: Text("بالدقيقة")),
                                            Padding(
                                                padding: EdgeInsets.symmetric(
                                                    horizontal: 16),
                                                child: Text("نصف ساعة")),
                                          ],
                                        ),

                                        const SizedBox(height: 25),
                                        Text(
                                          timeFormatted,
                                          style: const TextStyle(
                                              fontSize: 50,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.deepPurple),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          "💰 ${currentAmount.toStringAsFixed(0)} ر.ق",
                                          style: const TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green),
                                        ),

                                        const SizedBox(height: 15),

                                        // خيار إكمال أجور الساعة (يظهر فقط عندما ينطبق الشرط)
                                        if (_shouldShowCompleteHourOption)
                                          Row(
                                            mainAxisAlignment:
                                            MainAxisAlignment.center,
                                            children: [
                                              Switch(
                                                value: _completeHour,
                                                activeColor: Colors.deepPurple,
                                                onChanged: (val) {
                                                  setState(() => _completeHour = val);
                                                },
                                              ),
                                              const SizedBox(width: 8),
                                              const Text(
                                                "إكمال أجور الساعة",
                                                style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),

                                        const SizedBox(height: 8),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 8),

                                // أزرار التشغيل/الإنهاء/إلغاء محفوظة في أسفل البطاقة
                                if (!_running)
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.play_arrow),
                                    label: const Text("بدء"),
                                    style: ElevatedButton.styleFrom(
                                      shape: const StadiumBorder(),
                                      backgroundColor: Colors.deepPurple,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 40, vertical: 15),
                                    ),
                                    onPressed: _startLesson,
                                  )
                                else
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Column(
                                        children: [
                                          FloatingActionButton(
                                            heroTag: "end_$index",
                                            backgroundColor: Colors.red,
                                            onPressed: () async {
                                              final amount = _calculateAmount();
                                              final result = await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => TeacherEndLessonPage(
                                                    payload: {
                                                      "lessonId": lesson['id'],
                                                      "student": lesson['studentName'] ??
                                                          lesson['student'] ??
                                                          "طالب",
                                                      "date": lesson['date'] ?? "",
                                                      "time": lesson['time'] ?? "",
                                                      "seconds": _seconds.toString(),
                                                      "amount": amount.toString(),
                                                      "hourlyRate": _hourlyRate.toString(),
                                                      "completeHour": _completeHour,
                                                    },
                                                  ),
                                                ),
                                              );
                                              if (result == true) {
                                                _loadRunningLessons();
                                              }
                                            },
                                            child: const Icon(Icons.stop),
                                          ),
                                          const SizedBox(height: 5),
                                          const Text("إنهاء"),
                                        ],
                                      ),
                                      const SizedBox(width: 40),
                                      Column(
                                        children: [
                                          FloatingActionButton(
                                            heroTag: "cancel_$index",
                                            backgroundColor: Colors.orange,
                                            onPressed: () async {
                                              final result = await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      TeacherCancelLessonPage(
                                                        payload: {
                                                          "lessonId": lesson['id'],
                                                          "student": lesson['studentName'] ??
                                                              lesson['student'] ??
                                                              "طالب",
                                                          "date": lesson['date'] ?? "",
                                                          "time": lesson['time'] ?? "",
                                                          "seconds": _seconds.toString(),
                                                        },
                                                      ),
                                                ),
                                              );
                                              if (result == true) {
                                                _loadRunningLessons();
                                              }
                                            },
                                            child: const Icon(Icons.cancel),
                                          ),
                                          const SizedBox(height: 5),
                                          const Text("إلغاء"),
                                        ],
                                      ),
                                    ],
                                  ),

                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              Positioned(
                right: 10,
                top: MediaQuery.of(context).size.height * 0.4,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios,
                      size: 32, color: Colors.deepPurpleAccent),
                  onPressed: () => _goToPage(_currentIndex - 1),
                ),
              ),
              Positioned(
                left: 10,
                top: MediaQuery.of(context).size.height * 0.4,
                child: IconButton(
                  icon: const Icon(Icons.arrow_forward_ios,
                      size: 32, color: Colors.deepPurpleAccent),
                  onPressed: () => _goToPage(_currentIndex + 1),
                ),
              ),

              Positioned(
                top: 12,
                right: 12,
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.deepPurple,
                  onPressed: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
