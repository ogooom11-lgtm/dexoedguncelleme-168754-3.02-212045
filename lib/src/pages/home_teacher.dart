import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../widgets/teacher_sidebar.dart';
import 'teacher_add_schedule_page.dart';
import 'teacher_add_student_page.dart';
import 'teacher_add_ended_lesson_page.dart';
import 'permissions_guide_page.dart';
import '../services/permissions_gate.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';
import 'teacher_lesson_timer_page.dart';
import '../services/alarm_preferences.dart';
import '../services/notification_service_wrapper.dart';
import '../services/recurrence_utils.dart';
import 'today_recurring_page.dart';
import '../services/permission_guard.dart';
import '../services/timeline_models.dart' show TimelineFormat;
import 'recurring_schedules_page.dart';
import 'teacher_payments_page.dart';
import 'teacher_profile_page.dart';
import 'teacher_profits_page.dart';
import 'timeline/timeline_widgets.dart' show PressScale, PulsingDot;

class HomeTeacher extends StatefulWidget {
  const HomeTeacher({super.key});

  @override
  State<HomeTeacher> createState() => _HomeTeacherState();
}

class _HomeTeacherState extends State<HomeTeacher> {
  final ScrollController _scrollController = ScrollController();
  double _lastScrollOffset = 0.0;
  bool _fabVisible = true;
  bool _fabExpanded = true;
  Timer? _shrinkTimer;

  Map<String, dynamic> _studentsMap = {};
  Map<String, dynamic> _scheduleMap = {};
  Map<String, dynamic> _paymentsMap = {};
  double _computedBalance = 0.0;

  bool _isLoading = true;
  String _teacherCodeCached = "";

  double _animatedBalance = 0.0;

  StreamSubscription<DatabaseEvent>? _studentsSub;
  StreamSubscription<DatabaseEvent>? _scheduleSub;
  StreamSubscription<DatabaseEvent>? _paymentsSub;

  static const List<String> _weekdayNames = [
    "الاثنين",
    "الثلاثاء",
    "الأربعاء",
    "الخميس",
    "الجمعة",
    "السبت",
    "الأحد",
  ];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final code = context.read<AuthProvider>().currentUser?.code ?? '';
      if (code.isNotEmpty) PermissionGuard.start(code);
    });

    _shrinkTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _fabExpanded = false);
    });

    _scrollController.addListener(() {
      final offset = _scrollController.offset;
      final delta = offset - _lastScrollOffset;

      const threshold = 12.0;

      if (delta > threshold && _fabVisible) {
        setState(() => _fabVisible = false);
      } else if (delta < -threshold && !_fabVisible) {
        setState(() => _fabVisible = true);
      }

      _lastScrollOffset = offset;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final teacherCode = auth.currentUser?.code ?? "";
      if (teacherCode.isNotEmpty) {
        _listenToData(teacherCode: teacherCode);
      }
      // ✅ فحص الأذونات بعد ظهور الواجهة (لا يؤخّر تسجيل الدخول)
      _checkPermissionsLater();
    });
  }

  Future<void> _openAddEndedLesson() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const TeacherAddEndedLessonPage()),
    );
    if (added == true && mounted) setState(() {});
  }

  /// فحص الأذونات مرة واحدة فقط، بعد أن تظهر الصفحة الرئيسية،
  /// حتى يبقى تسجيل الدخول سريعاً وبدون أي تعليق.
  Future<void> _checkPermissionsLater() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await Future.delayed(const Duration(milliseconds: 1200));
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('onboarding_permissions_done_v2') ?? false) return;
      final shouldShow = await PermissionsGate.shouldShow();
      if (!shouldShow) {
        await prefs.setBool('onboarding_permissions_done_v2', true);
        return;
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PermissionsGuidePage()),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _shrinkTimer?.cancel();
    _studentsSub?.cancel();
    _scheduleSub?.cancel();
    _paymentsSub?.cancel();
    super.dispose();
  }

  String _niceDateTime(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final now = DateTime.now();
    if (DateFormat('yyyy-MM-dd').format(dt) ==
        DateFormat('yyyy-MM-dd').format(now)) {
      return "اليوم • ${DateFormat('HH:mm').format(dt)}";
    } else if (DateFormat('yyyy-MM-dd').format(dt) ==
        DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 1)))) {
      return "غداً • ${DateFormat('HH:mm').format(dt)}";
    } else {
      return "${DateFormat('yyyy-MM-dd').format(dt)} • ${DateFormat('HH:mm').format(dt)}";
    }
  }

  Future<void> _listenToData({required String teacherCode}) async {
    await _studentsSub?.cancel();
    await _scheduleSub?.cancel();
    await _paymentsSub?.cancel();

    _studentsSub = FirebaseDatabase.instance
        .ref("users/$teacherCode/students")
        .onValue
        .listen((event) => _updateData(teacherCode, event, "students"));

    _scheduleSub = FirebaseDatabase.instance
        .ref("users/$teacherCode/schedule")
        .onValue
        .listen((event) => _updateData(teacherCode, event, "schedule"));

    _paymentsSub = FirebaseDatabase.instance
        .ref("users/$teacherCode/payments")
        .onValue
        .listen((event) => _updateData(teacherCode, event, "payments"));
  }

  void _updateData(String teacherCode, DatabaseEvent event, String type) async {
    if (!mounted) return;

    setState(() {
      if (type == "students") {
        _studentsMap = (event.snapshot.value != null)
            ? Map<String, dynamic>.from(event.snapshot.value as Map)
            : {};
      } else if (type == "schedule") {
        _scheduleMap = (event.snapshot.value != null)
            ? Map<String, dynamic>.from(event.snapshot.value as Map)
            : {};
      } else if (type == "payments") {
        _paymentsMap = (event.snapshot.value != null)
            ? Map<String, dynamic>.from(event.snapshot.value as Map)
            : {};
      }
    });

    final balance =
        await _computeBalanceFromMaps(_studentsMap, _scheduleMap, _paymentsMap);
    if (mounted) {
      setState(() {
        _computedBalance = balance;
        _isLoading = false;
        _teacherCodeCached = teacherCode;
      });
    }
  }

  Future<double> _computeBalanceFromMaps(
      Map<String, dynamic> studentsData,
      Map<String, dynamic> lessonsData,
      Map<String, dynamic> paymentsData) async {
    final Map<String, double> studentLessons = {};
    lessonsData.forEach((key, value) {
      try {
        final lesson = Map<String, dynamic>.from(value);
        if (lesson['status'] == 'ended') {
          final student = (lesson['student'] ?? "unknown").toString();
          final amount = double.tryParse("${lesson['amount']}") ?? 0.0;
          studentLessons[student] = (studentLessons[student] ?? 0) + amount;
        }
      } catch (_) {}
    });

    double total = 0.0;

    studentsData.forEach((studentCode, studentInfo) {
      final lessonsTotal = studentLessons[studentCode] ?? 0.0;
      double studentPaymentsTotal = 0.0;
      double teacherPaymentsTotal = 0.0;

      if (paymentsData[studentCode] != null) {
        try {
          final studentPayments =
              Map<String, dynamic>.from(paymentsData[studentCode]);
          studentPayments.forEach((id, payment) {
            try {
              final pm = Map<String, dynamic>.from(payment as Map);
              final payer = pm['payer'] ?? 'student';
              final amount = double.tryParse("${pm['amount']}") ?? 0.0;
              if (payer == "student") studentPaymentsTotal += amount;
              if (payer == "teacher") teacherPaymentsTotal += amount;
            } catch (_) {}
          });
        } catch (_) {}
      }

      final balance =
          lessonsTotal - studentPaymentsTotal + teacherPaymentsTotal;
      total += balance;
    });

    return total;
  }

  String _studentNameFrom(
      Map<String, dynamic> studentsMap, String? studentCodeOrName) {
    if (studentCodeOrName == null) return "طالب";
    if (studentsMap.containsKey(studentCodeOrName)) {
      final info = Map<String, dynamic>.from(studentsMap[studentCodeOrName]);
      return info['name']?.toString() ?? studentCodeOrName;
    }
    return studentCodeOrName;
  }

  int get _endedLessonsCount {
    var count = 0;
    _scheduleMap.forEach((_, value) {
      try {
        if (value is Map && value['status'] == 'ended') count++;
      } catch (_) {}
    });
    return count;
  }

  Future<void> _onStartLesson({
    required String teacherCode,
    required String lessonId,
  }) async {
    final ref =
        FirebaseDatabase.instance.ref("users/$teacherCode/schedule/$lessonId");

    // تحديث حالة الدرس كبداية
    await ref.update({
      "status": "started",
      "startTime": DateTime.now().toIso8601String(),
    });

    // جلب بيانات الدرس لحساب وقت الانتهاء
    final snap = await ref.get();
    if (snap.exists) {
      final data = Map<String, dynamic>.from(snap.value as Map);

      final startTime = DateTime.tryParse(data['startTime'] ?? '');
      final durationSeconds = int.tryParse("${data['duration']}") ?? 0;
      final student = data['student']?.toString() ?? "طالب";

      if (startTime != null && durationSeconds > 0) {
        final endTime = startTime.add(Duration(seconds: durationSeconds));

        // ✅ إلغاء إشعارات البداية القديمة
        await NotificationServiceWrapper.cancelLessonNotification(lessonId);

        // ✅ إشعار قبل 5 دقائق من الانتهاء
        final prefs = await AlarmPreferences.load();
        final reminderEndTime = endTime.subtract(prefs.reminderLeadDuration);
        if (reminderEndTime.isAfter(DateTime.now())) {
          await NotificationServiceWrapper
              .scheduleLessonEndReminderNotification(
            lessonId: lessonId,
            student: student,
            reminderTime: reminderEndTime,
            teacherCode: teacherCode,
          );
        }

        // ✅ إشعار انتهاء الدرس
        if (endTime.isAfter(DateTime.now())) {
          await NotificationServiceWrapper.scheduleLessonEndedNotification(
            lessonId: lessonId,
            student: student,
            endTime: endTime,
            teacherCode: teacherCode,
          );
        }
      }
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeacherLessonTimerPage(lessonId: lessonId),
      ),
    );
  }

  Future<List<RecurringSchedule>> _loadTodayRecurring() async {
    if (_teacherCodeCached.isEmpty) return [];
    final snap = await FirebaseDatabase.instance
        .ref("users/$_teacherCodeCached/recurringSchedules")
        .get();
    if (!snap.exists || snap.value is! Map) return [];

    final today = DateTime.now();
    final todayYmd = DateFormat('yyyy-MM-dd').format(today);
    final raw = Map<String, dynamic>.from(snap.value as Map);
    final items = <RecurringSchedule>[];

    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final recurring = RecurringSchedule.fromMap(
        entry.key,
        Map<String, dynamic>.from(entry.value as Map),
      );
      if (!RecurrenceUtils.occursOn(recurring, today)) continue;
      if (recurring.lastConfirmedDate == todayYmd) continue;
      items.add(recurring);
    }

    items.sort((a, b) {
      final da = RecurrenceUtils.buildStartForDay(a, today);
      final db = RecurrenceUtils.buildStartForDay(b, today);
      return da.compareTo(db);
    });
    return items;
  }

  Future<void> _confirmRecurringToday(RecurringSchedule recurring) async {
    if (_teacherCodeCached.isEmpty) return;
    final today = DateTime.now();
    final todayYmd = DateFormat('yyyy-MM-dd').format(today);
    final start = RecurrenceUtils.buildStartForDay(recurring, today);
    final end = RecurrenceUtils.buildEndForDay(recurring, today);

    final scheduleRef = FirebaseDatabase.instance
        .ref("users/$_teacherCodeCached/schedule")
        .push();
    final lessonId = scheduleRef.key!;
    await scheduleRef.set({
      "teacher": recurring.teacher,
      "student": recurring.student,
      "date": todayYmd,
      "startTime": start.toIso8601String(),
      "endTime": end.toIso8601String(),
      "duration": recurring.duration,
      "createdAt": DateTime.now().toIso8601String(),
      "status": "scheduled",
    });

    await FirebaseDatabase.instance
        .ref("users/$_teacherCodeCached/recurringSchedules/${recurring.id}")
        .update({
      "lastConfirmedDate": todayYmd,
      "updatedAt": DateTime.now().toIso8601String(),
    });

    try {
      final prefs = await AlarmPreferences.load();
      final studentName = _studentNameFrom(_studentsMap, recurring.student);
      final reminderTime = start.subtract(prefs.reminderLeadDuration);
      if (reminderTime.isAfter(DateTime.now())) {
        await NotificationServiceWrapper.scheduleReminderNotification(
          lessonId: lessonId,
          student: studentName,
          reminderTime: reminderTime,
          teacherCode: _teacherCodeCached,
        );
      }
      if (start.isAfter(DateTime.now())) {
        await NotificationServiceWrapper.scheduleLessonStartNotification(
          lessonId: lessonId,
          student: studentName,
          startTime: start,
          teacherCode: _teacherCodeCached,
        );
      }
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("تم تأكيد درس اليوم")),
    );
    setState(() {});
  }

  // ============================================================
  //                           الواجهة
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final teacherName = auth.currentUser?.name ?? "أستاذ";

    return Scaffold(
      drawer: const TeacherSidebar(),
      appBar: AppBar(
        title: const Text("الرئيسية"),
        centerTitle: true,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            tooltip: "الجدول الزمني",
            icon: const Icon(Icons.view_timeline_rounded),
            onPressed: () => Navigator.pushNamed(context, '/teacher_timeline'),
          ),
          IconButton(
            tooltip: "حسابي",
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TeacherProfilePage()),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFabColumn(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                setState(() {});
                await Future<void>.delayed(const Duration(milliseconds: 350));
              },
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  Responsive.gutter(context),
                  8,
                  Responsive.gutter(context),
                  150,
                ),
                children: [
                  const AnnouncementBanner(forTeacher: true, margin: EdgeInsets.only(bottom: 12)),
                  _buildHeroCard(context, teacherName),
                  const SizedBox(height: 14),
                  _buildStatsRow(context),
                  const SizedBox(height: 14),
                  _buildLessonsSection(context),
                ],
              ),
            ),
    );
  }

  // ===== عدّادات اليوم =====
  ({int today, int running, int pending, int upcoming}) get _counts {
    final now = DateTime.now();
    int today = 0, running = 0, pending = 0, upcoming = 0;
    _scheduleMap.forEach((_, v) {
      if (v is! Map) return;
      final status = (v['status'] ?? '').toString();
      final dt = DateTime.tryParse('${v['startTime'] ?? v['date'] ?? ''}');
      if (dt != null && dt.year == now.year && dt.month == now.month && dt.day == now.day && status != 'canceled') {
        today++;
      }
      if (status == 'started') running++;
      if (status == 'pending') pending++;
      if (status == 'scheduled' && dt != null && dt.isAfter(now)) upcoming++;
    });
    return (today: today, running: running, pending: pending, upcoming: upcoming);
  }

  // ===== بطاقة الترحيب + الرصيد =====
  Widget _buildHeroCard(BuildContext context, String teacherName) {
    final now = DateTime.now();
    final fmt = NumberFormat('#,###');
    final c = _counts;
    final hour = now.hour;
    final greeting = hour < 12 ? 'صباح الخير ☀️' : (hour < 17 ? 'مساء الخير 👋' : 'مساء النور 🌙');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: [
          BoxShadow(
            color: AppTheme.seed.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      teacherName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 21,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${_weekdayNames[now.weekday - 1]} • ${DateFormat('yyyy-MM-dd').format(now)}",
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              PressScale(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TeacherProfilePage()),
                ),
                child: Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1.5),
                  ),
                  child: Text(
                    teacherName.trim().isEmpty ? '؟' : teacherName.trim().characters.first,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // شريط حالة اليوم
          Row(
            children: [
              _HeroChip(
                icon: Icons.today_rounded,
                label: 'دروس اليوم',
                value: '${c.today}',
              ),
              const SizedBox(width: 8),
              _HeroChip(
                icon: Icons.play_circle_fill_rounded,
                label: 'جارية',
                value: '${c.running}',
                live: c.running > 0,
              ),
              const SizedBox(width: 8),
              _HeroChip(
                icon: Icons.hourglass_top_rounded,
                label: 'طلبات',
                value: '${c.pending}',
                highlight: c.pending > 0,
              ),
            ],
          ),
          const SizedBox(height: 12),

          PressScale(
            onTap: () => Navigator.pushNamed(context, '/teacher_balance'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "المستحق على الطلاب",
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: _animatedBalance, end: _computedBalance),
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeOut,
                          builder: (context, value, _) {
                            return Text(
                              "${fmt.format(value.toInt())} ${TimelineFormat.currency}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                              ),
                            );
                          },
                          onEnd: () {
                            _animatedBalance = _computedBalance;
                          },
                        ),
                      ],
                    ),
                  ),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("التفاصيل", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                      Icon(Icons.chevron_left, size: 18, color: Colors.white),
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

  // ===== صف الإحصائيات + الاختصارات =====
  Widget _buildStatsRow(BuildContext context) {
    final c = _counts;
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _statCard(
                  context,
                  icon: Icons.group_rounded,
                  color: const Color(0xFF3B82F6),
                  label: "الطلاب",
                  value: "${_studentsMap.length}",
                  onTap: () => Navigator.pushNamed(context, '/teacher_students'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statCard(
                  context,
                  icon: Icons.event_note_rounded,
                  color: const Color(0xFFF59E0B),
                  label: "قادمة",
                  value: "${c.upcoming}",
                  onTap: () => Navigator.pushNamed(context, '/teacher_schedule'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statCard(
                  context,
                  icon: Icons.check_circle_outline_rounded,
                  color: const Color(0xFF10B981),
                  label: "منتهية",
                  value: "$_endedLessonsCount",
                  onTap: () => Navigator.pushNamed(context, '/teacher_lessons'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              _QuickAction(icon: Icons.view_timeline_rounded, label: 'الجدول', color: const Color(0xFF06B6D4), onTap: () => Navigator.pushNamed(context, '/teacher_timeline')),
              const SizedBox(width: 8),
              _QuickAction(icon: Icons.receipt_long_rounded, label: 'الدفعات', color: const Color(0xFFEF4444), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherPaymentsPage()))),
              const SizedBox(width: 8),
              _QuickAction(icon: Icons.insights_rounded, label: 'الأرباح', color: const Color(0xFFA855F7), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfitsPage()))),
              const SizedBox(width: 8),
              _QuickAction(icon: Icons.event_repeat_rounded, label: 'المتكررة', color: const Color(0xFF84CC16), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecurringSchedulesPage()))),
              const SizedBox(width: 8),
              _QuickAction(icon: Icons.manage_accounts_rounded, label: 'حسابي', color: const Color(0xFF64748B), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherProfilePage()))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(anim), child: child),
              ),
              child: Text(
                value,
                key: ValueKey(value),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== أزرار الإضافة العائمة =====
  Widget _buildFabColumn() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: _fabVisible ? 1.0 : 0.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ إضافة درس منتهي (درس تم إعطاؤه ولم يُسجَّل)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: _fabExpanded
                ? FloatingActionButton.extended(
                    key: const ValueKey('addEnded_ext'),
                    heroTag: 'addEndedLesson',
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    icon: const Icon(Icons.history_edu),
                    label: const Text("درس منتهي"),
                    onPressed: _openAddEndedLesson,
                  )
                : FloatingActionButton(
                    key: const ValueKey('addEnded_icon'),
                    heroTag: 'addEndedLesson',
                    mini: true,
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    onPressed: _openAddEndedLesson,
                    child: const Icon(Icons.history_edu),
                  ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: _fabExpanded
                ? FloatingActionButton.extended(
                    key: const ValueKey('addLesson_ext'),
                    heroTag: 'addLesson',
                    icon: const Icon(Icons.today),
                    label: const Text("إضافة موعد"),
                    onPressed: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const TeacherAddSchedulePage()));
                    },
                  )
                : FloatingActionButton(
                    key: const ValueKey('addLesson_icon'),
                    heroTag: 'addLesson',
                    mini: true,
                    child: const Icon(Icons.today),
                    onPressed: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const TeacherAddSchedulePage()));
                    },
                  ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: _fabExpanded
                ? FloatingActionButton.extended(
                    key: const ValueKey('addStudent_ext'),
                    heroTag: 'addStudent',
                    icon: const Icon(Icons.person_add),
                    label: const Text("إضافة طالب"),
                    onPressed: () async {
                      if (!await PermissionGuard.check(context, TeacherPermission.addStudents)) return;
                      if (!context.mounted) return;
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const TeacherAddStudentPage()));
                    },
                  )
                : FloatingActionButton(
                    key: const ValueKey('addStudent_icon'),
                    heroTag: 'addStudent',
                    mini: true,
                    child: const Icon(Icons.person_add),
                    onPressed: () async {
                      if (!await PermissionGuard.check(context, TeacherPermission.addStudents)) return;
                      if (!context.mounted) return;
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const TeacherAddStudentPage()));
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildTodayRecurringSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<RecurringSchedule>>(
      future: _loadTodayRecurring(),
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final items = snapshot.data ?? [];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusSm),
                      ),
                      child: Icon(Icons.event_repeat_rounded,
                          color: scheme.onPrimaryContainer, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "دروس اليوم المتكررة",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TodayRecurringPage(),
                          ),
                        ).then((_) => setState(() {}));
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text("عرض"),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (items.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.55,
                      ),
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusSm),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                            color: Colors.teal.shade700),
                        const SizedBox(width: 8),
                        const Expanded(
                          child:
                              Text("لا يوجد اليوم دروس متكررة بحاجة لتأكيد"),
                        ),
                      ],
                    ),
                  )
                else
                  Column(
                    children: items.take(4).map((recurring) {
                      final name =
                          _studentNameFrom(_studentsMap, recurring.student);
                      final start = RecurrenceUtils.buildStartForDay(
                          recurring, DateTime.now());
                      final end = RecurrenceUtils.buildEndForDay(
                          recurring, DateTime.now());
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.35,
                          ),
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusSm),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  Colors.teal.withValues(alpha: 0.14),
                              child: const Icon(Icons.school_rounded,
                                  color: Colors.teal),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    "${DateFormat('HH:mm').format(start)} - ${DateFormat('HH:mm').format(end)}",
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(80, 38),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              onPressed: () =>
                                  _confirmRecurringToday(recurring),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text("تأكيد"),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLessonsSection(BuildContext context) {
    final now = DateTime.now();
    final current = <MapEntry<String, dynamic>>[];
    final upcoming = <MapEntry<String, dynamic>>[];
    final pending = <MapEntry<String, dynamic>>[];

    _scheduleMap.forEach((key, value) {
      try {
        final item = Map<String, dynamic>.from(value);
        final status = (item['status'] ?? '').toString();
        if (status == 'started') {
          current.add(MapEntry(key, item));
        } else if (status == 'pending') {
          pending.add(MapEntry(key, item));
        } else if (status == 'scheduled') {
          final dateStr =
              item['startTime']?.toString() ?? item['date']?.toString();
          DateTime? dt = DateTime.tryParse(dateStr ?? '');
          if (dt == null && item['date'] != null) {
            dt = DateTime.tryParse(item['date']);
          }
          if (dt != null && dt.isAfter(now.subtract(const Duration(days: 1)))) {
            upcoming.add(MapEntry(key, item));
          }
        }
      } catch (_) {}
    });

    upcoming.sort((a, b) {
      DateTime da =
          DateTime.tryParse(a.value['startTime'] ?? '') ?? DateTime.now();
      DateTime db =
          DateTime.tryParse(b.value['startTime'] ?? '') ?? DateTime.now();
      return da.compareTo(db);
    });

    final upcomingLimited = upcoming.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTodayRecurringSection(context),
        const SizedBox(height: 12),
        _sectionCard(
          icon: Icons.play_circle,
          color: Colors.green,
          title: "الدروس الجارية",
          child: current.isEmpty
              ? _emptyHint("لا توجد دروس جارية الآن")
              : Column(
                  children: current.map((entry) {
                    final studentName =
                        _studentNameFrom(_studentsMap, entry.value['student']);
                    return _lessonBubble(
                      context: context,
                      leading:
                          const Icon(Icons.play_circle, color: Colors.green),
                      title: studentName,
                      subtitle: _niceDateTime(
                          entry.value['startTime'] ?? entry.value['date']),
                      trailing: _smallActionButton(
                        label: "تتبع",
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  TeacherLessonTimerPage(lessonId: entry.key),
                            ),
                          );
                        },
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          icon: Icons.schedule,
          color: Colors.cyan,
          title: "أقرب ٣ دروس",
          child: upcomingLimited.isEmpty
              ? _emptyHint("لا توجد مواعيد قادمة")
              : Column(
                  children: upcomingLimited.map((entry) {
                    final studentName =
                        _studentNameFrom(_studentsMap, entry.value['student']);
                    return _lessonBubble(
                      context: context,
                      leading: const Icon(Icons.schedule, color: Colors.cyan),
                      title: studentName,
                      subtitle: _niceDateTime(
                          entry.value['startTime'] ?? entry.value['date']),
                      trailing: _smallActionButton(
                        label: "ابدأ",
                        onPressed: () {
                          _onStartLesson(
                              teacherCode: _teacherCodeCached,
                              lessonId: entry.key);
                        },
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          icon: Icons.hourglass_bottom,
          color: Colors.orange,
          title: "دروس معلقة",
          child: pending.isEmpty
              ? _emptyHint("لا توجد دروس معلقة")
              : Column(
                  children: pending.map((entry) {
                    final studentName =
                        _studentNameFrom(_studentsMap, entry.value['student']);
                    return _lessonBubble(
                      context: context,
                      leading:
                          const Icon(Icons.hourglass_top, color: Colors.orange),
                      title: studentName,
                      subtitle: _niceDateTime(
                          entry.value['startTime'] ?? entry.value['date']),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: "قبول",
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: () async {
                              HapticFeedback.lightImpact();
                              await FirebaseDatabase.instance
                                  .ref(
                                      "users/$_teacherCodeCached/schedule/${entry.key}")
                                  .update({
                                "status": "scheduled",
                                "updatedAt": DateTime.now().toIso8601String(),
                              });
                              setState(() {
                                _scheduleMap[entry.key]?['status'] =
                                    'scheduled';
                              });
                            },
                          ),
                          IconButton(
                            tooltip: "رفض",
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () async {
                              HapticFeedback.mediumImpact();
                              await FirebaseDatabase.instance
                                  .ref(
                                      "users/$_teacherCodeCached/schedule/${entry.key}")
                                  .update({
                                "status": "canceled",
                                "updatedAt": DateTime.now().toIso8601String(),
                              });
                              setState(() {
                                _scheduleMap[entry.key]?['status'] = 'canceled';
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _emptyHint(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      ),
    );
  }

  Widget _smallActionButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 38),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 13,
          fontFamily: 'Cairo',
        ),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }

  Widget _lessonBubble({
    required BuildContext context,
    required Widget leading,
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        leading: leading,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: trailing,
      ),
    );
  }
}

// =====================================================================
// عناصر مساعدة للرئيسية
// =====================================================================

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label, required this.value, this.live = false, this.highlight = false});
  final IconData icon;
  final String label;
  final String value;
  final bool live;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: highlight ? 0.24 : 0.12),
          borderRadius: BorderRadius.circular(14),
          border: highlight ? Border.all(color: Colors.amber.withValues(alpha: 0.7)) : null,
        ),
        child: Row(
          children: [
            if (live) const PulsingDot(color: Color(0xFF4ADE80), size: 9) else Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, height: 1.1)),
                  Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10.5), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: scheme.onSurface)),
          ],
        ),
      ),
    );
  }
}
