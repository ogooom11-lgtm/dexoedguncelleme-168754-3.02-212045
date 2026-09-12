import 'dart:math' as math;
import 'dart:ui'; // For ImageFilter
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../providers/auth_provider.dart';
import '../services/alarm_audio_service.dart';
import '../services/alarm_preferences.dart';
import '../services/notification_service.dart';

class AlarmPage extends StatefulWidget {
  final String lessonId;
  final String student;
  final String? teacherCode;

  const AlarmPage({
    super.key,
    required this.lessonId,
    required this.student,
    this.teacherCode,
  });

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage>
    with SingleTickerProviderStateMixin {
  // ==========================================
  //  LOGIC SECTION (UNCHANGED)
  // ==========================================

  bool _loading = false;
  late AnimationController _controller;
  late String _lessonTime;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _lessonTime = _formatTime(now);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) => _startAlarmUI());
  }

  Future<void> _startAlarmUI() async {
    await WakelockPlus.enable();
    await AlarmAudioService.playAlarm(looping: true);
  }

  Future<void> _stopAlarm() async {
    try {
      await AlarmAudioService.stop();
      await WakelockPlus.disable();
      _controller.stop();
    } catch (_) {}
  }

  Future<void> _startLesson() async {
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthProvider>();
      final storedTeacherCode = auth.currentUser?.code ?? "";
      final teacherCode = storedTeacherCode.isNotEmpty
          ? storedTeacherCode
          : (widget.teacherCode ?? "");
      if (teacherCode.isEmpty) {
        throw Exception("لم يتم العثور على كود المعلم لهذا الدرس");
      }

      // 1. تحديث الحالة في Firebase
      final ref = FirebaseDatabase.instance
          .ref("users/$teacherCode/schedule/${widget.lessonId}");
      await ref.update({
        "status": "started",
        "startTime": DateTime.now().toIso8601String(),
      });

      // 2. جدولة إشعارات النهاية
      final snap = await ref.get();
      if (snap.exists) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        final startTime = DateTime.tryParse(data['startTime'] ?? '');
        final durationSec = int.tryParse('${data['duration']}') ?? 0;
        final studentName = data['student']?.toString() ?? widget.student;

        if (startTime != null && durationSec > 0) {
          final endTime = startTime.add(Duration(seconds: durationSec));

          await NotificationService.cancelLessonNotification(widget.lessonId);

          final prefs = await AlarmPreferences.load();
          final reminderEndTime = endTime.subtract(prefs.reminderLeadDuration);
          if (reminderEndTime.isAfter(DateTime.now())) {
            await NotificationService.scheduleLessonEndReminderNotification(
              lessonId: widget.lessonId,
              student: studentName,
              reminderTime: reminderEndTime,
              teacherCode: teacherCode,
            );
          }

          if (endTime.isAfter(DateTime.now())) {
            await NotificationService.scheduleLessonEndedNotification(
              lessonId: widget.lessonId,
              student: studentName,
              endTime: endTime,
              teacherCode: teacherCode,
            );
          }
        }
      }

      await _stopAlarm();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("✅ تم بدء الدرس، يرجى التركيز!"),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        Navigator.of(context).maybePop(true);
      }
    } catch (e) {
      debugPrint("❌ startLesson error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _snoozeLesson() async {
    setState(() => _loading = true);
    try {
      await NotificationService.cancelLessonNotification(widget.lessonId);
      final prefs = await AlarmPreferences.load();
      final snoozeTime = DateTime.now().add(prefs.snoozeDuration);
      final auth = context.read<AuthProvider>();
      final storedTeacherCode = auth.currentUser?.code ?? "";
      final teacherCode = storedTeacherCode.isNotEmpty
          ? storedTeacherCode
          : (widget.teacherCode ?? "");
      await NotificationService.scheduleLessonStartNotification(
        lessonId: widget.lessonId,
        student: widget.student,
        startTime: snoozeTime,
        teacherCode: teacherCode,
      );
      await _stopAlarm();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("⏳ سيتم تذكيرك بعد ${prefs.snoozeMinutes} دقائق"),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        Navigator.of(context).maybePop(true);
      }
    } catch (e) {
      debugPrint("❌ snoozeLesson error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'م' : 'ص';
    return "$hour:$minute $period";
  }

  @override
  void dispose() {
    _controller.dispose();
    _stopAlarm();
    super.dispose();
  }

  // ==========================================
  //  MODERN UI REDESIGN
  // ==========================================

  @override
  Widget build(BuildContext context) {
    // نستخدم خلفية داكنة دائماً في التنبيه لأنها أكثر عصرية وراحة للعين
    const backgroundGradient = LinearGradient(
      colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    const textColor = Colors.white;
    final glassColor = Colors.white.withValues(alpha: 0.1);
    final borderColor = Colors.white.withValues(alpha: 0.2);

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // 1. Background
          Container(
              decoration: const BoxDecoration(gradient: backgroundGradient)),

          // 3. Main Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // --- Header: Time ---
                  Column(
                    children: [
                      const SizedBox(height: 10),
                      Text("حان موعد الدرس",
                          style: TextStyle(
                              color: textColor.withValues(alpha: 0.7),
                              fontSize: 16,
                              letterSpacing: 1.1)),
                      const SizedBox(height: 5),
                      Text(
                        _lessonTime,
                        style: const TextStyle(
                          color: textColor,
                          fontSize: 48,
                          fontWeight: FontWeight.w200, // Thin modern font
                        ),
                      ),
                    ],
                  ),

                  // --- Center: Student & Icon ---
                  Column(
                    children: [
                      // Pulsing Icon
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (_, __) {
                          // تدرج في الحجم والشفافية
                          final waveValue =
                              math.sin(_controller.value * math.pi);
                          final scale = 1 + (waveValue * 0.1);
                          final glowOpacity = (waveValue * 0.4).clamp(0.0, 1.0);

                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer Glow
                              Container(
                                width: 180 * scale,
                                height: 180 * scale,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.deepPurpleAccent.withValues(
                                    alpha: 0.2 * glowOpacity,
                                  ),
                                ),
                              ),
                              // Inner Icon Circle
                              Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF654ea3),
                                      Color(0xFFeaafc8)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.deepPurple.withValues(
                                        alpha: 0.5,
                                      ),
                                      blurRadius: 25,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.notifications_active,
                                    color: Colors.white, size: 60),
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 40),

                      // Student Name Card (Glass)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 24, horizontal: 20),
                            decoration: BoxDecoration(
                              color: glassColor,
                              border: Border.all(color: borderColor),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  "الطالب",
                                  style: TextStyle(
                                      color: textColor.withValues(alpha: 0.6),
                                      fontSize: 14),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  widget.student,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: textColor,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // --- Bottom: Actions ---
                  Column(
                    children: [
                      // Start Lesson Button (Primary)
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _startLesson,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            elevation: 8,
                            shadowColor:
                                Colors.greenAccent.withValues(alpha: 0.4),
                          ),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF00b09b),
                                  Color(0xFF96c93d)
                                ], // Green gradient
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Container(
                              alignment: Alignment.center,
                              child: _loading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2))
                                  : const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.play_arrow_rounded,
                                            color: Colors.white, size: 28),
                                        SizedBox(width: 8),
                                        Text("بدء الدرس الآن",
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Snooze Button (Secondary)
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : _snoozeLesson,
                          icon: const Icon(Icons.snooze, color: Colors.white70),
                          label: const Text("تذكير بعد 5 دقائق",
                              style:
                                  TextStyle(color: Colors.white, fontSize: 16)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
