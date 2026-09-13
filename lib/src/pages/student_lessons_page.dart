// lib/src/pages/student_lessons_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/student_repository.dart';
import '../services/timeline_models.dart';
import '../theme/app_theme.dart';
import 'student/student_sheets.dart';
import 'student/student_widgets.dart';

enum _LessonFilter { all, upcoming, ended, pending, canceled, unpaid }

extension on _LessonFilter {
  String get label => switch (this) {
        _LessonFilter.all => 'الكل',
        _LessonFilter.upcoming => 'القادمة',
        _LessonFilter.ended => 'المنتهية',
        _LessonFilter.pending => 'الطلبات',
        _LessonFilter.canceled => 'الملغاة',
        _LessonFilter.unpaid => 'غير مدفوعة',
      };

  IconData get icon => switch (this) {
        _LessonFilter.all => Icons.all_inclusive_rounded,
        _LessonFilter.upcoming => Icons.upcoming_rounded,
        _LessonFilter.ended => Icons.check_circle_outline_rounded,
        _LessonFilter.pending => Icons.hourglass_top_rounded,
        _LessonFilter.canceled => Icons.cancel_outlined,
        _LessonFilter.unpaid => Icons.money_off_rounded,
      };

  Color? get color => switch (this) {
        _LessonFilter.upcoming => TimelineStatus.scheduled.color,
        _LessonFilter.ended => TimelineStatus.ended.color,
        _LessonFilter.pending => TimelineStatus.pending.color,
        _LessonFilter.canceled => TimelineStatus.canceled.color,
        _LessonFilter.unpaid => AppTheme.danger,
        _ => null,
      };
}

/// 📚 دروسي — قائمة مجمّعة حسب الشهر مع فلاتر وبحث.
class StudentLessonsPage extends StatefulWidget {
  const StudentLessonsPage({super.key});

  @override
  State<StudentLessonsPage> createState() => _StudentLessonsPageState();
}

class _StudentLessonsPageState extends State<StudentLessonsPage> {
  _LessonFilter _filter = _LessonFilter.all;
  String _query = '';
  bool _searching = false;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<StudentLesson> _apply(StudentRepository repo) {
    Iterable<StudentLesson> list = repo.lessons;
    switch (_filter) {
      case _LessonFilter.all:
        break;
      case _LessonFilter.upcoming:
        list = list.where((l) => l.isUpcoming || l.isRunning);
      case _LessonFilter.ended:
        list = list.where((l) => l.isEnded);
      case _LessonFilter.pending:
        list = list.where((l) => l.isPending);
      case _LessonFilter.canceled:
        list = list.where((l) => l.status == TimelineStatus.canceled || l.status == TimelineStatus.missed);
      case _LessonFilter.unpaid:
        list = list.where((l) => l.isEnded && !l.isPaid);
    }
    final q = _query.trim();
    if (q.isNotEmpty) {
      list = list.where((l) =>
          l.note.contains(q) ||
          l.cancelReason.contains(q) ||
          TimelineFormat.ymd(l.start).contains(q) ||
          l.status.label.contains(q));
    }
    final out = list.toList();
    // القادمة تصاعدياً، الباقي تنازلياً
    if (_filter == _LessonFilter.upcoming || _filter == _LessonFilter.pending) {
      out.sort((a, b) => a.start.compareTo(b.start));
    } else {
      out.sort((a, b) => b.start.compareTo(a.start));
    }
    return out;
  }

  int _count(StudentRepository repo, _LessonFilter f) => switch (f) {
        _LessonFilter.all => repo.lessons.length,
        _LessonFilter.upcoming => repo.upcomingLessons.length + (repo.runningLesson == null ? 0 : 1),
        _LessonFilter.ended => repo.endedLessons.length,
        _LessonFilter.pending => repo.pendingRequests.length,
        _LessonFilter.canceled => repo.lessons.where((l) => l.status == TimelineStatus.canceled || l.status == TimelineStatus.missed).length,
        _LessonFilter.unpaid => repo.unpaidLessons.length,
      };

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<StudentRepository>();
    final scheme = Theme.of(context).colorScheme;
    final lessons = _apply(repo);

    // تجميع حسب الشهر
    final groups = <String, List<StudentLesson>>{};
    final groupKeys = <String, DateTime>{};
    for (final l in lessons) {
      final key = '${l.start.year}-${l.start.month}';
      groups.putIfAbsent(key, () => []).add(l);
      groupKeys.putIfAbsent(key, () => DateTime(l.start.year, l.start.month));
    }

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'ابحث بالتاريخ أو الملاحظة…',
                  border: InputBorder.none,
                  isDense: true,
                ),
              )
            : const Text('دروسي'),
        actions: [
          IconButton(
            tooltip: _searching ? 'إغلاق البحث' : 'بحث',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _query = '';
                _searchCtrl.clear();
              }
            }),
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              children: [
                for (final f in _LessonFilter.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: PillChoice(
                      label: '${f.label} ${_count(repo, f)}',
                      icon: f.icon,
                      color: f.color,
                      selected: _filter == f,
                      onTap: () {
                        timelineHaptic(true);
                        setState(() => _filter = f);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: !repo.isReady
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: repo.refresh,
              child: lessons.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 60),
                        TimelineEmptyState(
                          icon: _filter.icon,
                          title: _query.isNotEmpty ? 'لا نتائج للبحث' : 'لا توجد دروس هنا',
                          subtitle: _filter == _LessonFilter.unpaid
                              ? 'رائع! جميع دروسك المنتهية مسدَّدة.'
                              : _filter == _LessonFilter.upcoming
                                  ? 'لا مواعيد قادمة — يمكنك طلب موعد جديد من زر ＋.'
                                  : null,
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                      itemCount: groups.length,
                      itemBuilder: (context, gi) {
                        final key = groups.keys.elementAt(gi);
                        final items = groups[key]!;
                        final month = groupKeys[key]!;
                        final ended = items.where((l) => l.isEnded).toList();
                        final minutes = ended.fold<int>(0, (s, l) => s + l.minutes);
                        final amount = ended.fold<double>(0, (s, l) => s + l.amount);
                        return StaggeredReveal(
                          index: gi,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                                child: Row(
                                  children: [
                                    Text(
                                      TimelineFormat.isSameMonth(month, DateTime.now()) ? 'هذا الشهر' : TimelineFormat.monthTitle(month),
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
                                      child: Text('${items.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: scheme.primary)),
                                    ),
                                    const Spacer(),
                                    if (ended.isNotEmpty)
                                      Text(
                                        '${TimelineFormat.duration(minutes)} • ${TimelineFormat.money(amount)}',
                                        style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                                      ),
                                  ],
                                ),
                              ),
                              for (final l in items)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: StudentLessonTile(
                                    lesson: l,
                                    onTap: () => showStudentLessonSheet(context, lesson: l, repo: repo),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

/// ⏱️ شريحة "قيد التنفيذ" تعرض الوقت المنقضي منذ بداية الدرس (متوافقة مع الاستخدام القديم).
class RunningTimeChip extends StatefulWidget {
  const RunningTimeChip({super.key, required this.startIso});
  final String startIso;

  @override
  State<RunningTimeChip> createState() => _RunningTimeChipState();
}

class _RunningTimeChipState extends State<RunningTimeChip> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final start = DateTime.tryParse(widget.startIso);
    final mins = start == null ? 0 : DateTime.now().difference(start).inMinutes.clamp(0, 99999);
    final color = TimelineStatus.started.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulsingDot(color: color),
          const SizedBox(width: 6),
          Text('منذ ${TimelineFormat.duration(mins)}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}
