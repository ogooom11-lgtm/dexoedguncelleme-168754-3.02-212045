// lib/src/pages/teacher_timeline_page.dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/timeline_models.dart';
import '../services/timeline_preferences.dart';
import '../services/timeline_repository.dart';
import '../theme/app_theme.dart';
import 'teacher_add_ended_lesson_page.dart';
import 'teacher_add_schedule_page.dart';
import 'teacher_edit_schedule_page.dart';
import 'teacher_lesson_timer_page.dart';
import 'timeline/timeline_day_view.dart';
import 'timeline/timeline_settings_sheet.dart';
import 'timeline/timeline_sheets.dart';
import 'timeline/timeline_week_view.dart';
import 'timeline/timeline_widgets.dart';

/// 🗓️ الجدول الزمني للمعلم: يومي / أسبوعي / شهري
/// - الضغط على أي درس يفتح ورقة تفاصيل مع إجراءات (تم الإنهاء / إلغاء / بدء / تأكيد …).
/// - «تم الإنهاء» يسجّل درساً منتهياً بنفس منطق صفحة «إضافة درس منتهي».
/// - الأيام السابقة تعرض المنتهي والملغي (والفائت اختيارياً)، واليوم والأيام
///   التالية تعرض المنتهي والمجدول والمكرر والملغي.
class TeacherTimelinePage extends StatefulWidget {
  const TeacherTimelinePage({super.key, this.initialView, this.initialDate});

  final TimelineView? initialView;
  final DateTime? initialDate;

  @override
  State<TeacherTimelinePage> createState() => _TeacherTimelinePageState();
}

class _TeacherTimelinePageState extends State<TeacherTimelinePage>
    with TickerProviderStateMixin {
  static const int _center = 5000;

  TimelinePreferencesData? _prefs;
  TimelineRepository? _repo;

  late TimelineView _view = widget.initialView ?? TimelineView.day;
  late DateTime _base = TimelineFormat.dateOnly(widget.initialDate ?? DateTime.now());
  int _page = _center;
  late PageController _pageController = PageController(initialPage: _center);
  DateTime _selectedDay = TimelineFormat.today();

  TimelineFilter _filter = const TimelineFilter();
  bool _busy = false;
  bool _fabOpen = false;

  late final AnimationController _fabController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void initState() {
    super.initState();
    _selectedDay = _base;
    _init();
  }

  Future<void> _init() async {
    final prefs = await TimelinePreferences.load();
    if (!mounted) return;
    final code = context.read<AuthProvider>().currentUser?.code ?? '';
    final repo = TimelineRepository(code)..start();
    setState(() {
      _prefs = prefs;
      _repo = repo;
      if (widget.initialView == null) _view = prefs.defaultView;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fabController.dispose();
    _repo?.dispose();
    super.dispose();
  }

  // ===================== التواريخ =====================

  DateTime _dateForPage(int page, {TimelineView? view, DateTime? base}) {
    final v = view ?? _view;
    final b = base ?? _base;
    final off = page - _center;
    switch (v) {
      case TimelineView.day:
        return b.add(Duration(days: off));
      case TimelineView.week:
        return TimelineFormat.startOfWeek(b, _prefs!.weekStartDay)
            .add(Duration(days: 7 * off));
      case TimelineView.month:
        return DateTime(b.year, b.month + off, 1);
    }
  }

  DateTime get _current => _dateForPage(_page);

  /// نطاق الصفحة الحالية [start, endExclusive).
  (DateTime, DateTime) _rangeFor(DateTime d) {
    switch (_view) {
      case TimelineView.day:
        return (d, d.add(const Duration(days: 1)));
      case TimelineView.week:
        return (d, d.add(const Duration(days: 7)));
      case TimelineView.month:
        final first = DateTime(d.year, d.month, 1);
        final gridStart = TimelineFormat.startOfWeek(first, _prefs!.weekStartDay);
        final last = DateTime(d.year, d.month + 1, 0);
        final rows = ((last.difference(gridStart).inDays + 1) / 7).ceil();
        return (gridStart, gridStart.add(Duration(days: rows * 7)));
    }
  }

  void _resetPager(DateTime base, {TimelineView? view}) {
    final old = _pageController;
    setState(() {
      if (view != null) _view = view;
      _base = base;
      _page = _center;
      _pageController = PageController(initialPage: _center);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void _switchView(TimelineView v) {
    if (v == _view) return;
    timelineHaptic(_prefs!.haptics);
    // نحافظ على التاريخ المرئي حالياً
    DateTime anchor;
    switch (_view) {
      case TimelineView.day:
        anchor = _current;
        _selectedDay = anchor;
        break;
      case TimelineView.week:
        final ws = _current;
        final today = TimelineFormat.today();
        anchor = (!today.isBefore(ws) && today.isBefore(ws.add(const Duration(days: 7))))
            ? today
            : ws;
        _selectedDay = anchor;
        break;
      case TimelineView.month:
        anchor = _selectedDay;
        break;
    }
    _resetPager(anchor, view: v);
  }

  void _goToday() {
    timelineHaptic(_prefs!.haptics);
    _selectedDay = TimelineFormat.today();
    _resetPager(TimelineFormat.today());
  }

  void _openDay(DateTime d) {
    timelineHaptic(_prefs!.haptics);
    _selectedDay = TimelineFormat.dateOnly(d);
    _resetPager(_selectedDay, view: TimelineView.day);
  }

  void _step(int delta) {
    _pageController.animateToPage(
      _page + delta,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _view == TimelineView.month ? _selectedDay : _current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (ctx, child) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: child!,
      ),
    );
    if (picked == null) return;
    _selectedDay = TimelineFormat.dateOnly(picked);
    _resetPager(_selectedDay);
  }

  // ===================== الألوان =====================

  Color _accentOf(TimelineLesson l) {
    if (_prefs!.colorMode == TimelineColorMode.status) return l.status.color;
    return _repo!.studentOf(l.studentId).color;
  }

  // ===================== الإجراءات =====================

  Future<void> _openDetails(TimelineLesson lesson) async {
    timelineHaptic(_prefs!.haptics);
    final action = await showLessonDetailsSheet(
      context,
      lesson: lesson,
      prefs: _prefs!,
      accent: _accentOf(lesson),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case LessonAction.end:
        await _endLesson(lesson);
        break;
      case LessonAction.cancel:
        await _cancelLesson(lesson);
        break;
      case LessonAction.start:
        await _startLesson(lesson);
        break;
      case LessonAction.confirm:
        await _confirmRecurring(lesson);
        break;
      case LessonAction.revert:
        await _revert(lesson);
        break;
      case LessonAction.edit:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TeacherEditSchedulePage(
              lessonId: lesson.id,
              lessonData: Map<String, dynamic>.from(lesson.raw),
            ),
          ),
        );
        break;
      case LessonAction.delete:
        await _delete(lesson);
        break;
      case LessonAction.editNote:
        final note = await showNoteSheet(context, initial: lesson.note);
        if (note == null) return;
        await _run(() => _repo!.updateNote(lesson, note), success: 'تم حفظ الملاحظة');
        break;
      case LessonAction.openTimer:
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TeacherLessonTimerPage(lessonId: lesson.id)),
        );
        break;
    }
  }

  Future<void> _endLesson(TimelineLesson lesson, {bool quick = false}) async {
    if (!lesson.status.isActionable) return;
    EndLessonResult? result;
    if (quick && !_prefs!.confirmQuickActions) {
      final end = lesson.status == TimelineStatus.started &&
              DateTime.now().isAfter(lesson.start)
          ? DateTime.now()
          : lesson.end;
      final minutes = end.difference(lesson.start).inMinutes;
      final amount = minutes > 0 && lesson.hourlyRate > 0
          ? double.parse(((minutes / 60) * lesson.hourlyRate).toStringAsFixed(2))
          : 0.0;
      result = EndLessonResult(start: lesson.start, end: end, amount: amount, note: lesson.note);
    } else {
      result = await showEndLessonSheet(
        context,
        lesson: lesson,
        prefs: _prefs!,
        accent: _accentOf(lesson),
      );
    }
    if (result == null || !mounted) return;
    final r = result;
    await _run(
      () => _repo!.markEnded(lesson, start: r.start, end: r.end, amount: r.amount, note: r.note),
      success: 'تم تسجيل درس ${lesson.studentName} كمنتهي • ${TimelineFormat.money(r.amount)}',
      color: AppTheme.success,
      undoable: true,
    );
  }

  Future<void> _cancelLesson(TimelineLesson lesson, {bool quick = false}) async {
    if (!lesson.status.isActionable) return;
    String? reason;
    if (quick && !_prefs!.confirmQuickActions) {
      reason = '';
    } else {
      reason = await showCancelLessonSheet(context, lesson: lesson, prefs: _prefs!);
    }
    if (reason == null || !mounted) return;
    final rs = reason;
    await _run(
      () => _repo!.markCanceled(lesson, reason: rs),
      success: 'تم إلغاء درس ${lesson.studentName}',
      color: AppTheme.danger,
      undoable: true,
    );
  }

  Future<void> _startLesson(TimelineLesson lesson) async {
    final ok = await showConfirmSheet(
      context,
      title: 'بدء الدرس الآن؟',
      message: 'سيبدأ المؤقّت لدرس ${lesson.studentName} وتُجدول تنبيهات الانتهاء.',
      confirmLabel: 'ابدأ',
      icon: Icons.play_arrow_rounded,
      color: TimelineStatus.started.color,
    );
    if (!ok || !mounted) return;
    String? startedId;
    await _run(
      () async {
        startedId = await _repo!.startNow(lesson);
        return startedId;
      },
      success: null,
    );
    final id = startedId;
    if (id != null && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TeacherLessonTimerPage(lessonId: id)),
      );
    }
  }

  Future<void> _confirmRecurring(TimelineLesson lesson) async {
    await _run(
      () => _repo!.confirmRecurring(lesson),
      success: 'تم تأكيد موعد ${lesson.studentName} وجدولة التنبيهات',
    );
  }

  Future<void> _revert(TimelineLesson lesson) async {
    final ok = await showConfirmSheet(
      context,
      title: 'إعادة الدرس إلى «مجدول»؟',
      message: 'سيُلغى تسجيل ${lesson.status.label} ويعود الدرس كموعد مجدول.',
      confirmLabel: 'إعادة',
      icon: Icons.undo_rounded,
    );
    if (!ok || !mounted) return;
    await _run(() => _repo!.revertToScheduled(lesson), success: 'تمت إعادة الدرس إلى المجدول');
  }

  Future<void> _delete(TimelineLesson lesson) async {
    final ok = await showConfirmSheet(
      context,
      title: 'حذف الدرس نهائياً؟',
      message: 'لا يمكن التراجع عن الحذف. درس ${lesson.studentName} • ${TimelineFormat.relativeDay(lesson.start)}',
      confirmLabel: 'حذف',
      icon: Icons.delete_forever_rounded,
      color: AppTheme.danger,
    );
    if (!ok || !mounted) return;
    await _run(() => _repo!.deleteLesson(lesson), success: 'تم حذف الدرس', color: AppTheme.danger);
  }

  Future<void> _run(
    Future<dynamic> Function() task, {
    required String? success,
    Color? color,
    bool undoable = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await task();
      if (!mounted) return;
      timelineHaptic(_prefs!.haptics, heavy: true);
      if (success != null) {
        _snack(
          success,
          color: color,
          undo: undoable && result is TimelineUndo
              ? () => _run(() => _repo!.undo(result), success: 'تم التراجع')
              : null,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _snack('تعذر تنفيذ العملية: $e', color: AppTheme.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text, {Color? color, VoidCallback? undo}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: color ?? Theme.of(context).colorScheme.inverseSurface,
        duration: Duration(seconds: undo != null ? 6 : 3),
        content: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        action: undo == null
            ? null
            : SnackBarAction(label: 'تراجع', textColor: Colors.white, onPressed: undo),
      ),
    );
  }

  Future<void> _openSettings() async {
    timelineHaptic(_prefs!.haptics);
    final next = await showTimelineSettingsSheet(context, initial: _prefs!);
    if (next == null || !mounted) return;
    final weekChanged = next.weekStartDay != _prefs!.weekStartDay;
    setState(() => _prefs = next);
    await TimelinePreferences.save(next);
    if (weekChanged && _view != TimelineView.day) _resetPager(_selectedDay);
  }

  Future<void> _openFilter() async {
    timelineHaptic(_prefs!.haptics);
    final next = await showTimelineFilterSheet(
      context,
      initial: _filter,
      students: _repo!.students.values.toList(),
    );
    if (next == null || !mounted) return;
    setState(() => _filter = next);
  }

  void _toggleFab() {
    setState(() => _fabOpen = !_fabOpen);
    if (_fabOpen) {
      _fabController.forward();
    } else {
      _fabController.reverse();
    }
    timelineHaptic(_prefs!.haptics);
  }

  Future<void> _openAddLesson() async {
    if (_fabOpen) _toggleFab();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherAddSchedulePage()));
  }

  Future<void> _openAddEnded() async {
    if (_fabOpen) _toggleFab();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherAddEndedLessonPage()));
  }

  // ===================== الواجهة =====================

  @override
  Widget build(BuildContext context) {
    final prefs = _prefs;
    final repo = _repo;
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        body: prefs == null || repo == null
            ? const _LoadingSkeleton()
            : AnimatedBuilder(
                animation: repo,
                builder: (context, _) => _buildBody(context, prefs, repo),
              ),
        floatingActionButton: prefs == null ? null : _buildFab(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context, TimelinePreferencesData prefs, TimelineRepository repo) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _buildHeader(context, prefs, repo),
          if (repo.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Material(
                color: AppTheme.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.wifi_off_rounded, color: AppTheme.danger),
                  title: Text(repo.error!, style: const TextStyle(fontSize: 12)),
                  trailing: TextButton(onPressed: repo.refresh, child: const Text('إعادة')),
                ),
              ),
            ),
          Expanded(
            child: !repo.isReady
                ? const _LoadingSkeleton(compact: true)
                : Stack(
                    children: [
                      PageView.builder(
                        controller: _pageController,
                        physics: const BouncingScrollPhysics(),
                        onPageChanged: (i) {
                          timelineHaptic(prefs.haptics);
                          setState(() {
                            _page = i;
                            if (_view == TimelineView.month) {
                              final m = _current;
                              final today = TimelineFormat.today();
                              _selectedDay = TimelineFormat.isSameMonth(m, today)
                                  ? today
                                  : DateTime(m.year, m.month, 1);
                            } else if (_view == TimelineView.day) {
                              _selectedDay = _current;
                            }
                          });
                        },
                        itemBuilder: (context, index) {
                          final d = _dateForPage(index);
                          return _buildPage(context, d, prefs, repo);
                        },
                      ),
                      if (_busy)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              color: scheme.surface.withValues(alpha: 0.35),
                              alignment: Alignment.topCenter,
                              padding: const EdgeInsets.only(top: 8),
                              child: const LinearProgressIndicator(minHeight: 3),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(BuildContext context, DateTime d, TimelinePreferencesData prefs, TimelineRepository repo) {
    final range = _rangeFor(d);
    final lessons = repo.lessonsBetween(
      range.$1,
      range.$2,
      prefs,
      studentFilter: _filter.students,
      statusFilter: _filter.statuses,
    );

    Widget content;
    switch (_view) {
      case TimelineView.day:
        content = TimelineDayView(
          key: ValueKey('d${TimelineFormat.ymd(d)}${prefs.dayLayout}'),
          day: d,
          lessons: lessons,
          prefs: prefs,
          accentOf: _accentOf,
          onTap: _openDetails,
          onLongPress: _openDetails,
          onEnd: (l) => _endLesson(l, quick: true),
          onCancel: (l) => _cancelLesson(l, quick: true),
          onFreeSlot: (s, e) => _openAddLesson(),
          onAddLesson: _openAddLesson,
        );
        break;
      case TimelineView.week:
        content = TimelineWeekView(
          key: ValueKey('w${TimelineFormat.ymd(d)}${prefs.weekLayout}'),
          weekStart: d,
          lessons: lessons,
          prefs: prefs,
          accentOf: _accentOf,
          onTap: _openDetails,
          onLongPress: _openDetails,
          onEnd: (l) => _endLesson(l, quick: true),
          onCancel: (l) => _cancelLesson(l, quick: true),
          onOpenDay: _openDay,
        );
        break;
      case TimelineView.month:
        content = TimelineMonthView(
          key: ValueKey('m${d.year}-${d.month}'),
          month: d,
          selectedDay: _selectedDay,
          lessons: lessons,
          prefs: prefs,
          accentOf: _accentOf,
          onSelectDay: (day) {
            timelineHaptic(prefs.haptics);
            setState(() => _selectedDay = day);
          },
          onOpenDay: _openDay,
          onTap: _openDetails,
          onLongPress: _openDetails,
          onEnd: (l) => _endLesson(l, quick: true),
          onCancel: (l) => _cancelLesson(l, quick: true),
        );
        break;
    }

    return Column(
      children: [
        if (prefs.showSummary) _SummaryBar(lessons: lessons, prefs: prefs),
        Expanded(
          child: RefreshIndicator(
            onRefresh: repo.refresh,
            edgeOffset: 4,
            child: content,
          ),
        ),
      ],
    );
  }

  // ---------- الرأس ----------

  Widget _buildHeader(BuildContext context, TimelinePreferencesData prefs, TimelineRepository repo) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = _current;
    final isTodayVisible = switch (_view) {
      TimelineView.day => TimelineFormat.isSameDay(current, DateTime.now()),
      TimelineView.week => () {
          final t = TimelineFormat.today();
          return !t.isBefore(current) && t.isBefore(current.add(const Duration(days: 7)));
        }(),
      TimelineView.month => TimelineFormat.isSameMonth(current, DateTime.now()),
    };

    String title;
    String subtitle;
    switch (_view) {
      case TimelineView.day:
        title = TimelineFormat.relativeDay(current);
        subtitle = '${current.day} ${TimelineFormat.monthName(current)} ${current.year}';
        break;
      case TimelineView.week:
        title = TimelineFormat.weekRange(current);
        subtitle = 'الأسبوع';
        break;
      case TimelineView.month:
        title = TimelineFormat.monthTitle(current);
        subtitle = 'الشهر';
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141821) : Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppTheme.radiusLg)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
      child: Column(
        children: [
          // الصف العلوي
          Row(
            children: [
              IconButton(
                tooltip: 'رجوع',
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: () => Navigator.maybePop(context),
              ),
              const Expanded(
                child: Text(
                  'الجدول الزمني',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              _HeaderIcon(
                icon: Icons.filter_alt_rounded,
                tooltip: 'تصفية',
                badge: _filter.count,
                active: _filter.isActive,
                onTap: _openFilter,
              ),
              _HeaderIcon(
                icon: Icons.tune_rounded,
                tooltip: 'الإعدادات',
                onTap: _openSettings,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // المبدّل
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: ViewSwitcher(value: _view, onChanged: _switchView),
          ),
          const SizedBox(height: 10),
          // التنقّل بالتاريخ
          Row(
            children: [
              _NavButton(icon: Icons.chevron_right_rounded, onTap: () => _step(-1)),
              Expanded(
                child: PressScale(
                  onTap: _pickDate,
                  scale: 0.97,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Column(
                      key: ValueKey('$title$subtitle'),
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _NavButton(icon: Icons.chevron_left_rounded, onTap: () => _step(1)),
              const SizedBox(width: 4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: isTodayVisible
                    ? const SizedBox(width: 40, key: ValueKey('none'))
                    : SizedBox(
                        key: const ValueKey('today'),
                        width: 40,
                        child: IconButton.filledTonal(
                          tooltip: 'اليوم',
                          icon: const Icon(Icons.today_rounded, size: 20),
                          onPressed: _goToday,
                        ),
                      ),
              ),
            ],
          ),
          if (_view == TimelineView.day) ...[
            const SizedBox(height: 8),
            _DayStrip(
              current: current,
              weekStartDay: prefs.weekStartDay,
              repo: repo,
              prefs: prefs,
              onSelect: (d) {
                final diff = d.difference(current).inDays;
                if (diff == 0) return;
                timelineHaptic(prefs.haptics);
                _pageController.animateToPage(
                  _page + diff,
                  duration: Duration(milliseconds: (220 + diff.abs() * 40).clamp(220, 480)),
                  curve: Curves.easeOutCubic,
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  // ---------- الزر العائم ----------

  Widget _buildFab(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _FabItem(
          controller: _fabController,
          index: 1,
          icon: Icons.check_circle_rounded,
          label: 'درس منتهي',
          color: AppTheme.success,
          onTap: _openAddEnded,
        ),
        _FabItem(
          controller: _fabController,
          index: 0,
          icon: Icons.event_rounded,
          label: 'درس جديد',
          color: scheme.primary,
          onTap: _openAddLesson,
        ),
        FloatingActionButton(
          heroTag: 'timeline_fab',
          onPressed: _toggleFab,
          child: AnimatedRotation(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            turns: _fabOpen ? 0.125 : 0,
            child: const Icon(Icons.add_rounded, size: 28),
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// مكوّنات داخلية
// =====================================================================

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge = 0,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: tooltip,
          icon: Icon(icon, color: active ? scheme.primary : null),
          onPressed: onTap,
        ),
        if (badge > 0)
          PositionedDirectional(
            end: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$badge',
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: scheme.onPrimary),
              ),
            ),
          ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressScale(
      onTap: onTap,
      scale: 0.88,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 22),
      ),
    );
  }
}

/// شريط الأيام السبعة في العرض اليومي مع مؤشرات الدروس.
class _DayStrip extends StatelessWidget {
  const _DayStrip({
    required this.current,
    required this.weekStartDay,
    required this.repo,
    required this.prefs,
    required this.onSelect,
  });

  final DateTime current;
  final int weekStartDay;
  final TimelineRepository repo;
  final TimelinePreferencesData prefs;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final start = TimelineFormat.startOfWeek(current, weekStartDay);
    final now = DateTime.now();
    final weekLessons = repo.lessonsBetween(start, start.add(const Duration(days: 7)), prefs);
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Builder(builder: (context) {
              final d = start.add(Duration(days: i));
              final selected = TimelineFormat.isSameDay(d, current);
              final isToday = TimelineFormat.isSameDay(d, now);
              final dayLessons = weekLessons.where((l) => TimelineFormat.isSameDay(l.start, d)).toList();
              final active = dayLessons.where((l) => l.status != TimelineStatus.canceled).toList();
              final allDone = active.isNotEmpty && active.every((l) => l.status == TimelineStatus.ended);
              return PressScale(
                onTap: () => onSelect(d),
                scale: 0.9,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? scheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: isToday && !selected
                        ? Border.all(color: scheme.primary.withValues(alpha: 0.5))
                        : null,
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: scheme.primary.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : null,
                  ),
                  child: Column(
                    children: [
                      Text(
                        TimelineFormat.shortDayName(d),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: selected ? scheme.onPrimary.withValues(alpha: 0.85) : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${d.day}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          color: selected ? scheme.onPrimary : scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      SizedBox(
                        height: 6,
                        child: active.isEmpty
                            ? null
                            : allDone
                                ? Icon(Icons.check_rounded,
                                    size: 8, color: selected ? Colors.white : AppTheme.success)
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      for (var k = 0; k < active.length.clamp(0, 3); k++)
                                        Container(
                                          width: 4,
                                          height: 4,
                                          margin: const EdgeInsets.symmetric(horizontal: 1),
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? Colors.white
                                                : (prefs.colorMode == TimelineColorMode.status
                                                    ? active[k].status.color
                                                    : repo.studentOf(active[k].studentId).color),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }
}

/// شريط الملخص للنطاق الحالي.
class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.lessons, required this.prefs});
  final List<TimelineLesson> lessons;
  final TimelinePreferencesData prefs;

  @override
  Widget build(BuildContext context) {
    final active = lessons.where((l) => l.status != TimelineStatus.canceled).toList();
    final ended = active.where((l) => l.status == TimelineStatus.ended).toList();
    final upcoming = active.where((l) => !l.status.isFinal).toList();
    final canceled = lessons.length - active.length;
    final minutes = active.fold<int>(0, (s, l) => s + l.minutes);
    final earned = ended.fold<double>(0, (s, l) => s + l.amount);
    final expected = upcoming.fold<double>(0, (s, l) => s + l.estimatedAmount);

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          physics: const BouncingScrollPhysics(),
          children: [
            MiniStat(
              icon: Icons.school_rounded,
              label: 'درس',
              value: '${active.length}',
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            MiniStat(
              icon: Icons.check_circle_rounded,
              label: 'منتهي',
              value: '${ended.length}',
              color: AppTheme.success,
            ),
            const SizedBox(width: 8),
            MiniStat(
              icon: Icons.timelapse_rounded,
              label: 'الساعات',
              value: TimelineFormat.duration(minutes),
              color: const Color(0xFF0EA5E9),
            ),
            if (prefs.showAmounts) ...[
              const SizedBox(width: 8),
              MiniStat(
                icon: Icons.payments_rounded,
                label: 'محقق',
                value: TimelineFormat.money(earned),
                color: AppTheme.success,
              ),
              if (expected > 0) ...[
                const SizedBox(width: 8),
                MiniStat(
                  icon: Icons.trending_up_rounded,
                  label: 'متوقع',
                  value: TimelineFormat.money(expected),
                  color: const Color(0xFF8B5CF6),
                ),
              ],
            ],
            if (canceled > 0) ...[
              const SizedBox(width: 8),
              MiniStat(
                icon: Icons.cancel_rounded,
                label: 'ملغي',
                value: '$canceled',
                color: TimelineStatus.canceled.color,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FabItem extends StatelessWidget {
  const _FabItem({
    required this.controller,
    required this.index,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final AnimationController controller;
  final int index;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(
      parent: controller,
      curve: Interval(0.1 * index, 1, curve: Curves.easeOutBack),
      reverseCurve: Interval(0, 1 - 0.1 * index, curve: Curves.easeIn),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final v = anim.value.clamp(0.0, 1.0);
        if (v == 0) return const SizedBox.shrink();
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 20),
            child: Transform.scale(scale: 0.8 + 0.2 * v, alignment: Alignment.centerRight, child: child),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: PressScale(
          onTap: onTap,
          scale: 0.95,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 5)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// هيكل تحميل متحرّك.
class _LoadingSkeleton extends StatefulWidget {
  const _LoadingSkeleton({this.compact = false});
  final bool compact;

  @override
  State<_LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<_LoadingSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final a = 0.25 + 0.25 * _c.value;
        Widget box(double h, {double? w, double r = 14}) => Container(
              height: h,
              width: w,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: a * 0.25),
                borderRadius: BorderRadius.circular(r),
              ),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.compact) ...[
                  box(28, w: 160),
                  box(44),
                  box(40),
                ],
                box(48),
                box(84),
                box(84),
                box(84),
                box(84),
              ],
            ),
          ),
        );
      },
    );
  }
}
