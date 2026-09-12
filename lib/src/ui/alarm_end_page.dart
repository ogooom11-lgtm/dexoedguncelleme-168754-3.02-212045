import 'dart:async';
import 'dart:math' as math;
import 'dart:ui'; // For ImageFilter
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/alarm_audio_service.dart';
import '../services/alarm_preferences.dart';
import '../services/notification_service.dart';
import '../providers/auth_provider.dart';

class AlarmEndPage extends StatefulWidget {
  final String lessonId;
  final String student;
  final String? teacherCode;

  const AlarmEndPage({
    super.key,
    required this.lessonId,
    required this.student,
    this.teacherCode,
  });

  @override
  State<AlarmEndPage> createState() => _AlarmEndPageState();
}

class _AlarmEndPageState extends State<AlarmEndPage>
    with SingleTickerProviderStateMixin {
  // ==========================================
  //  LOGIC SECTION
  // ==========================================

  bool _loading = false;
  bool _playing = false;
  late AnimationController _controller;

  // Note
  bool _noteEnabled = false;
  final _noteController = TextEditingController();

  // Billing model
  String _billingMode = "hour"; // "hour", "minute", "half"
  bool _completeHour = false;

  // Data
  String? _teacherCode;
  String? _studentId;
  String _studentNameLabel = "";
  double _hourlyRate = 0;

  DateTime? _startTime;
  int _plannedDurationSec = 0;
  int _elapsedSec = 0;
  DateTime? _computedEnd;

  @override
  void initState() {
    super.initState();
    _studentNameLabel = widget.student;
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initData();
      await _startAlarmUI();
    });
  }

  Future<void> _initData() async {
    final auth = context.read<AuthProvider>();
    final storedTeacherCode = auth.currentUser?.code ?? "";
    _teacherCode = storedTeacherCode.isNotEmpty
        ? storedTeacherCode
        : (widget.teacherCode ?? "");
    if ((_teacherCode ?? "").isEmpty) return;

    final scheduleRef = FirebaseDatabase.instance
        .ref("users/$_teacherCode/schedule/${widget.lessonId}");
    final snap = await scheduleRef.get();
    if (snap.exists) {
      final data = Map<String, dynamic>.from(snap.value as Map);
      _studentId = data['student']?.toString();
      _studentNameLabel =
          (data['studentName']?.toString() ?? _studentNameLabel).toString();
      _startTime = DateTime.tryParse(data['startTime']?.toString() ?? "");
      _plannedDurationSec =
          int.tryParse(data['duration']?.toString() ?? "0") ?? 0;

      if (_startTime != null && _plannedDurationSec > 0) {
        _computedEnd = _startTime!.add(Duration(seconds: _plannedDurationSec));
        final now = DateTime.now();
        _elapsedSec = now.difference(_startTime!).inSeconds;
        if (_elapsedSec < 0) _elapsedSec = 0;
      }

      // Fetch hourlyRate
      if ((_studentId ?? "").isNotEmpty) {
        final studentSnap = await FirebaseDatabase.instance
            .ref("users/$_teacherCode/students/$_studentId")
            .get();
        if (studentSnap.exists) {
          final s = Map<String, dynamic>.from(studentSnap.value as Map);
          _hourlyRate =
              double.tryParse(s['hourlyRate']?.toString() ?? "0") ?? 0;
          if ((_studentNameLabel).isEmpty) {
            _studentNameLabel = s['name']?.toString() ?? _studentId!;
          }
        }
      }
      setState(() {});
    }
  }

  Future<void> _startAlarmUI() async {
    await WakelockPlus.enable();
    await AlarmAudioService.playAlarm(looping: true);
    setState(() => _playing = true);
  }

  Future<void> _stopAlarm() async {
    try {
      await AlarmAudioService.stop();
      await WakelockPlus.disable();
      _controller.stop();
      setState(() => _playing = false);
    } catch (_) {}
  }

  String _formatHMS(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  bool get _shouldShowCompleteHourOption {
    final hours = _elapsedSec / 3600.0;
    final fractional = hours - hours.floor();
    return fractional >= 0.5 && fractional < 1.0;
  }

  double _calculateAmount() {
    if (_hourlyRate <= 0) return 0;
    double amount;
    if (_billingMode == "minute") {
      final minutes = (_elapsedSec / 60).floor();
      final perMinute = _hourlyRate / 60.0;
      amount = minutes * perMinute;
    } else if (_billingMode == "half") {
      final halfHours = (_elapsedSec / 1800).floor();
      final perHalfHour = _hourlyRate / 2.0;
      amount = halfHours * perHalfHour;
    } else {
      final hours = (_elapsedSec / 3600).floor();
      amount = hours * _hourlyRate;
    }
    if (_completeHour && _shouldShowCompleteHourOption) {
      final baseFullHours = _elapsedSec ~/ 3600;
      amount = (baseFullHours + 1) * _hourlyRate;
    }
    return double.parse(amount.toStringAsFixed(2));
  }

  // ==========================================
  //  CONFIRMATION & TIMER LOGIC
  // ==========================================

  /// يظهر نافذة تأكيد مع عداد تنازلي 5 ثواني
  Future<void> _showAutoConfirmDialog({
    required String title,
    required String content,
    required Color color,
    required IconData icon,
    required Function() onConfirm,
  }) async {
    // إيقاف الرنين مؤقتاً أثناء الحوار لتجنب الإزعاج (اختياري، يمكنك إزالته)
    await AlarmAudioService.stop();
    if (!mounted) return;

    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: "Confirm",
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) {
        return _AutoConfirmDialogContent(
          title: title,
          content: content,
          themeColor: color,
          icon: icon,
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return Transform.scale(
          scale: Curves.easeOutBack.transform(anim1.value),
          child: FadeTransition(opacity: anim1, child: child),
        );
      },
    );

    // إذا كانت النتيجة true (تم التأكيد أو انتهى الوقت)
    if (result == true) {
      onConfirm();
    } else {
      // إذا تم الإلغاء، نعيد تشغيل المنبه إذا كان يجب أن يعمل
      if (_playing && !_loading) {
        AlarmAudioService.playAlarm(looping: true);
      }
    }
  }

  void _onEndPressed() {
    _showAutoConfirmDialog(
      title: "إنهاء الدرس؟",
      content: "سيتم حفظ الوقت والمبلغ المستحق وإنهاء الجلسة.",
      color: Colors.green,
      icon: Icons.check_circle_outline,
      onConfirm: _executeEndLesson,
    );
  }

  void _onCancelPressed() {
    _showAutoConfirmDialog(
      title: "إلغاء الدرس؟",
      content: "سيتم إلغاء الدرس وتسجيل المبلغ كـ 0.",
      color: Colors.redAccent,
      icon: Icons.cancel_outlined,
      onConfirm: _executeCancelLesson,
    );
  }

  // ==========================================
  //  EXECUTION LOGIC (Refactored)
  // ==========================================

  Future<void> _executeEndLesson() async {
    if ((_teacherCode ?? "").isEmpty) return;
    setState(() => _loading = true);
    try {
      final ref = FirebaseDatabase.instance
          .ref("users/$_teacherCode/schedule/${widget.lessonId}");
      final now = DateTime.now();
      final amountDouble = _calculateAmount();
      final amountInt = amountDouble.round();
      await ref.update({
        "status": "ended",
        "endTime": now.toIso8601String(),
        "duration": _elapsedSec,
        "amount": amountInt,
        if (_noteEnabled) "note": _noteController.text.trim(),
      });
      await NotificationService.cancelLessonNotification(widget.lessonId);
      await _stopAlarm(); // Stop completely

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("✅ تم إنهاء الدرس وحفظ التفاصيل"),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        Navigator.of(context).maybePop(true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("خطأ: $e")));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _executeCancelLesson() async {
    if ((_teacherCode ?? "").isEmpty) return;
    setState(() => _loading = true);
    try {
      final ref = FirebaseDatabase.instance
          .ref("users/$_teacherCode/schedule/${widget.lessonId}");
      final now = DateTime.now();
      await ref.update({
        "status": "canceled",
        "endTime": now.toIso8601String(),
        "duration": _elapsedSec,
        "amount": 0,
        if (_noteEnabled) "cancelReason": _noteController.text.trim(),
      });
      await NotificationService.cancelLessonNotification(widget.lessonId);
      await _stopAlarm(); // Stop completely

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🗑️ تم إلغاء الدرس"),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        Navigator.of(context).maybePop(true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("خطأ: $e")));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _snooze5() async {
    setState(() => _loading = true);
    try {
      await NotificationService.cancelLessonNotification(widget.lessonId);
      final prefs = await AlarmPreferences.load();
      final when = DateTime.now().add(prefs.snoozeDuration);
      await NotificationService.scheduleLessonEndedNotification(
        lessonId: widget.lessonId,
        student: _studentNameLabel,
        endTime: when,
        teacherCode: _teacherCode,
      );
      await _stopAlarm();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("⏳ سيتم تذكيرك بعد 5 دقائق"),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("خطأ: $e"),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  void dispose() {
    _controller.dispose();
    _noteController.dispose();
    _stopAlarm();
    super.dispose();
  }

  // ==========================================
  //  MODERN UI REDESIGN
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Rich modern gradients
    final backgroundGradient = isDark
        ? const LinearGradient(
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          )
        : const LinearGradient(
            colors: [Color(0xFFffffff), Color(0xFFE6E9F0)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          );
    final textColor = isDark ? Colors.white : const Color(0xFF2D3436);
    final glassColor =
        isDark ? Colors.black.withOpacity(0.3) : Colors.white.withOpacity(0.6);
    final borderColor =
        isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05);

    final amount = _calculateAmount();
    final elapsedHMS = _formatHMS(_elapsedSec);
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // 1. Background
          Container(decoration: BoxDecoration(gradient: backgroundGradient)),

          // 2. Decorative blur circles (Ambient effect)
          if (isDark)
            Positioned(
              top: -100,
              right: -50,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.3),
                    shape: BoxShape.circle),
              ),
            ),

          // 3. Main Content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Column(
                children: [
                  // --- Header ---
                  const SizedBox(height: 10),
                  Text("انتهى وقت الدرس",
                      style: TextStyle(
                          color: textColor.withOpacity(0.6),
                          fontSize: 16,
                          letterSpacing: 1.2)),
                  const SizedBox(height: 5),
                  Text(
                    _studentNameLabel,
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: textColor),
                    textAlign: TextAlign.center,
                  ),
                  if (_computedEnd != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        "الموعد: ${_computedEnd!.hour.toString().padLeft(2, '0')}:${_computedEnd!.minute.toString().padLeft(2, '0')}",
                        style: TextStyle(
                            color: textColor.withOpacity(0.5), fontSize: 14),
                      ),
                    ),

                  const SizedBox(height: 30),

                  // --- Pulsing Alarm Icon ---
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (_, __) {
                      final scale =
                          1 + (math.sin(_controller.value * math.pi) * 0.1);
                      final glowOpacity =
                          (math.sin(_controller.value * math.pi) * 0.5)
                              .clamp(0.0, 1.0);

                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 120 * scale,
                            height: 120 * scale,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: (isDark
                                      ? Colors.purpleAccent
                                      : Colors.deepPurple)
                                  .withOpacity(0.2 * glowOpacity),
                            ),
                          ),
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                    colors: [
                                      Colors.deepPurple.shade400,
                                      Colors.deepPurple.shade700
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.deepPurple.withOpacity(0.4),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                      offset: const Offset(0, 10))
                                ]),
                            child: const Icon(Icons.timer_off_outlined,
                                color: Colors.white, size: 50),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 40),

                  // --- Billing & Time Card (Glassmorphism) ---
                  _GlassContainer(
                    color: glassColor,
                    borderColor: borderColor,
                    child: Column(
                      children: [
                        // Toggle Buttons (Custom Look)
                        Container(
                          height: 45,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color:
                                isDark ? Colors.black26 : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              _buildSegmentOption("ساعة", "hour", textColor),
                              _buildSegmentOption("دقيقة", "minute", textColor),
                              _buildSegmentOption("نصف", "half", textColor),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Stats Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildInfoColumn(
                                "المدة الزمنية",
                                elapsedHMS,
                                Icons.access_time_filled,
                                Colors.blueAccent,
                                textColor),
                            Container(width: 1, height: 40, color: borderColor),
                            _buildInfoColumn(
                                "السعر/ساعة",
                                "${_hourlyRate.toInt()}",
                                Icons.sell,
                                Colors.orangeAccent,
                                textColor),
                          ],
                        ),

                        if (_shouldShowCompleteHourOption) ...[
                          const SizedBox(height: 15),
                          Divider(color: borderColor),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("إكمال أجور الساعة",
                                  style: TextStyle(
                                      color: textColor,
                                      fontWeight: FontWeight.w600)),
                              Switch.adaptive(
                                value: _completeHour,
                                onChanged: (v) =>
                                    setState(() => _completeHour = v),
                                activeColor: Colors.deepPurple,
                              )
                            ],
                          )
                        ],

                        const SizedBox(height: 15),
                        Divider(color: borderColor),
                        const SizedBox(height: 10),

                        // Total Amount Hero
                        Column(
                          children: [
                            Text("المبلغ المستحق",
                                style: TextStyle(
                                    color: textColor.withOpacity(0.5),
                                    fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(
                              "${amount.toStringAsFixed(0)} ر.ق",
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                color: Colors
                                    .green, // Keep green strictly for money for psychological association
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // --- Note Section ---
                  _GlassContainer(
                    color: glassColor,
                    borderColor: borderColor,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () =>
                              setState(() => _noteEnabled = !_noteEnabled),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              children: [
                                Icon(
                                    _noteEnabled
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank,
                                    color: Colors.deepPurple),
                                const SizedBox(width: 10),
                                Text("إضافة ملاحظة للدرس",
                                    style: TextStyle(
                                        color: textColor,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                        AnimatedCrossFade(
                          crossFadeState: _noteEnabled
                              ? CrossFadeState.showFirst
                              : CrossFadeState.showSecond,
                          duration: const Duration(milliseconds: 300),
                          firstChild: Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: TextField(
                              controller: _noteController,
                              maxLines: 2,
                              style: TextStyle(color: textColor),
                              decoration: InputDecoration(
                                hintText: "اكتب ملاحظاتك هنا...",
                                hintStyle: TextStyle(
                                    color: textColor.withOpacity(0.4)),
                                filled: true,
                                fillColor: isDark
                                    ? Colors.black12
                                    : Colors.grey.shade100,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                            ),
                          ),
                          secondChild: const SizedBox(width: double.infinity),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // --- Actions ---
                  Row(
                    children: [
                      // End Button (Hero)
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _onEndPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Colors.transparent, // Uses Gradient
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            elevation: 8,
                            shadowColor: Colors.deepPurple.withOpacity(0.5),
                          ),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                Colors.deepPurple,
                                Color(0xFF673AB7)
                              ]),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Container(
                              height: 60,
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
                                        Icon(Icons.check, color: Colors.white),
                                        SizedBox(width: 8),
                                        Text("إنهاء الدرس",
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

                      const SizedBox(width: 12),

                      // Cancel Button
                      Expanded(
                        child: TextButton(
                          onPressed: _loading ? null : _onCancelPressed,
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.red.withOpacity(0.1),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            fixedSize: const Size.fromHeight(60),
                          ),
                          child: const Text("إلغاء",
                              style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Snooze Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _snooze5,
                      icon: Icon(Icons.snooze,
                          size: 18, color: textColor.withOpacity(0.7)),
                      label: Text("تذكير بعد 5 دقائق",
                          style: TextStyle(color: textColor.withOpacity(0.7))),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: borderColor),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper Widgets for UI ---

  Widget _buildSegmentOption(String label, String mode, Color textColor) {
    final bool isSelected = _billingMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _billingMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2))
                  ]
                : [],
          ),
          child: Text(
            label,
            style: TextStyle(
                color: isSelected ? Colors.black : textColor.withOpacity(0.5),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoColumn(String label, String value, IconData icon,
      Color iconColor, Color textColor) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
          Text(label,
              style:
                  TextStyle(fontSize: 12, color: textColor.withOpacity(0.5))),
        ],
      ),
    );
  }
}

// ==========================================
//  WIDGETS (Helpers & Dialogs)
// ==========================================

class _GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color color;
  final Color borderColor;

  const _GlassContainer({
    required this.child,
    this.padding,
    required this.color,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A modern Dialog Content Widget with internal Timer state
class _AutoConfirmDialogContent extends StatefulWidget {
  final String title;
  final String content;
  final Color themeColor;
  final IconData icon;

  const _AutoConfirmDialogContent({
    required this.title,
    required this.content,
    required this.themeColor,
    required this.icon,
  });

  @override
  State<_AutoConfirmDialogContent> createState() =>
      _AutoConfirmDialogContentState();
}

class _AutoConfirmDialogContentState extends State<_AutoConfirmDialogContent> {
  int _secondsLeft = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft == 1) {
        timer.cancel();
        // Auto confirm
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _secondsLeft--;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E2C).withOpacity(0.85)
                    : Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Colors.white.withOpacity(0.2), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: 5,
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon Bubble
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: widget.themeColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child:
                        Icon(widget.icon, size: 36, color: widget.themeColor),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.content,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Timer & Auto Action text
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 50,
                        height: 50,
                        child: CircularProgressIndicator(
                          value: _secondsLeft / 5.0,
                          backgroundColor: Colors.grey.withOpacity(0.2),
                          color: widget.themeColor,
                          strokeWidth: 4,
                        ),
                      ),
                      Text(
                        "$_secondsLeft",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: widget.themeColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "سيتم التأكيد تلقائياً",
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.grey),
                  ),

                  const SizedBox(height: 24),

                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text("تراجع",
                              style: TextStyle(
                                  color:
                                      isDark ? Colors.white60 : Colors.grey)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.themeColor,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text("تأكيد الآن",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
