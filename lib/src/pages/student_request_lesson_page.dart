// lib/src/pages/student_request_lesson_page.dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/student_repository.dart';
import '../services/timeline_models.dart';
import '../theme/app_theme.dart';
import 'student/student_widgets.dart';

/// 📅 طلب موعد جديد (نسخة معاد تصميمها):
/// - شريط أيام للأسبوعين القادمين + اختيار تاريخ.
/// - مدة جاهزة (30/45/60/90/120) ثم اختيار وقت بداية من الأوقات المتاحة فقط.
/// - يراعي الدروس المؤكدة والمواعيد المتكررة للمعلم.
class StudentRequestLessonPage extends StatefulWidget {
  const StudentRequestLessonPage({super.key, this.repo, this.initialDate});

  /// مستودع اختياري (من الشاشة الرئيسية)، وإلا يُنشأ داخلياً.
  final StudentRepository? repo;
  final DateTime? initialDate;

  @override
  State<StudentRequestLessonPage> createState() => _StudentRequestLessonPageState();
}

class _StudentRequestLessonPageState extends State<StudentRequestLessonPage> {
  static const int _startHour = 8;
  static const int _endHour = 22;
  static const int _step = 30;
  static const _durations = [30, 45, 60, 90, 120];

  StudentRepository? _own;
  StudentRepository get _repo => widget.repo ?? _own!;

  late DateTime _day = TimelineFormat.dateOnly(widget.initialDate ?? DateTime.now());
  int _duration = 60;
  DateTime? _start;
  List<(DateTime, DateTime)> _busy = const [];
  bool _loadingBusy = false;
  bool _sending = false;
  String _error = '';
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.repo == null) {
      final u = context.read<AuthProvider>().currentUser;
      _own = StudentRepository(studentCode: u?.code ?? '', teacherCode: u?.teacher ?? '')..start();
    }
    _loadBusy();
  }

  @override
  void dispose() {
    _own?.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadBusy() async {
    setState(() {
      _loadingBusy = true;
      _start = null;
      _error = '';
    });
    try {
      final b = await _repo.busyRangesOn(_day);
      if (!mounted) return;
      setState(() => _busy = b);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'تعذر تحميل المواعيد: $e');
    } finally {
      if (mounted) setState(() => _loadingBusy = false);
    }
  }

  List<DateTime> get _candidates {
    final list = <DateTime>[];
    var t = DateTime(_day.year, _day.month, _day.day, _startHour);
    final limit = DateTime(_day.year, _day.month, _day.day, _endHour);
    while (!t.add(Duration(minutes: _duration)).isAfter(limit)) {
      list.add(t);
      t = t.add(const Duration(minutes: _step));
    }
    return list;
  }

  bool _isFree(DateTime s) {
    final e = s.add(Duration(minutes: _duration));
    if (!s.isAfter(DateTime.now())) return false;
    for (final b in _busy) {
      if (s.isBefore(b.$2) && e.isAfter(b.$1)) return false;
    }
    return true;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: TimelineFormat.today(),
      lastDate: TimelineFormat.today().add(const Duration(days: 365)),
      builder: (ctx, child) => Directionality(textDirection: ui.TextDirection.rtl, child: child!),
    );
    if (picked == null) return;
    setState(() => _day = TimelineFormat.dateOnly(picked));
    _loadBusy();
  }

  Future<void> _submit() async {
    final s = _start;
    if (s == null) return;
    final e = s.add(Duration(minutes: _duration));
    setState(() {
      _sending = true;
      _error = '';
    });
    try {
      await _repo.requestLesson(start: s, end: e, note: _note.text.trim());
      if (!mounted) return;
      timelineHaptic(true, heavy: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.success,
          content: Text('تم إرسال طلبك ✅ بانتظار موافقة المعلم', style: TextStyle(color: Colors.white)),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'تعذر إرسال الطلب: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final candidates = _candidates;
    final free = candidates.where(_isFree).toList();
    final est = _repo.hourlyRate > 0 ? (_duration / 60) * _repo.hourlyRate : 0.0;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('طلب موعد جديد')),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                physics: const BouncingScrollPhysics(),
                children: [
                  // ===== التاريخ =====
                  SectionTitle(title: 'اليوم', icon: Icons.event_rounded, actionLabel: 'تاريخ آخر', onAction: _pickDate),
                  SizedBox(
                    height: 82,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: 14,
                      itemBuilder: (context, i) {
                        final d = TimelineFormat.today().add(Duration(days: i));
                        final selected = TimelineFormat.isSameDay(d, _day);
                        return PressScale(
                          scale: 0.92,
                          onTap: () {
                            timelineHaptic(true);
                            setState(() => _day = d);
                            _loadBusy();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 240),
                            width: 62,
                            margin: const EdgeInsetsDirectional.only(end: 8),
                            decoration: BoxDecoration(
                              color: selected ? scheme.primary : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: selected ? [BoxShadow(color: scheme.primary.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))] : null,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(i == 0 ? 'اليوم' : i == 1 ? 'غداً' : TimelineFormat.shortDayName(d),
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected ? scheme.onPrimary.withValues(alpha: 0.85) : scheme.onSurfaceVariant)),
                                const SizedBox(height: 2),
                                Text('${d.day}', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: selected ? scheme.onPrimary : scheme.onSurface, height: 1.1)),
                                Text(TimelineFormat.monthName(d), style: TextStyle(fontSize: 10, color: selected ? scheme.onPrimary.withValues(alpha: 0.8) : scheme.outline)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 10, right: 4),
                    child: Text(TimelineFormat.fullDate(_day), style: TextStyle(fontSize: 12.5, color: scheme.primary, fontWeight: FontWeight.w700)),
                  ),

                  // ===== المدة =====
                  const SectionTitle(title: 'المدة', icon: Icons.hourglass_bottom_rounded),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in _durations)
                        PillChoice(
                          label: TimelineFormat.duration(m),
                          selected: _duration == m,
                          onTap: () {
                            timelineHaptic(true);
                            setState(() {
                              _duration = m;
                              if (_start != null && !_isFree(_start!)) _start = null;
                            });
                          },
                        ),
                    ],
                  ),

                  // ===== الوقت =====
                  SectionTitle(
                    title: 'وقت البداية',
                    icon: Icons.schedule_rounded,
                    actionLabel: _loadingBusy ? null : '${free.length} متاح',
                  ),
                  if (_loadingBusy)
                    const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                  else if (free.isEmpty)
                    SoftCard(
                      child: Row(
                        children: [
                          const Icon(Icons.event_busy_rounded, color: AppTheme.warning),
                          const SizedBox(width: 10),
                          Expanded(child: Text('لا توجد أوقات متاحة بهذه المدة في هذا اليوم — جرّب يوماً آخر أو مدة أقصر.', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant))),
                        ],
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 96,
                        mainAxisExtent: 40,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemCount: candidates.length,
                      itemBuilder: (context, i) {
                        final t = candidates[i];
                        final ok = _isFree(t);
                        final sel = _start == t;
                        return PressScale(
                          enabled: ok,
                          scale: 0.92,
                          onTap: ok
                              ? () {
                                  timelineHaptic(true);
                                  setState(() => _start = t);
                                }
                              : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: sel
                                  ? scheme.primary
                                  : ok
                                      ? scheme.primary.withValues(alpha: 0.08)
                                      : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: sel ? scheme.primary : ok ? scheme.primary.withValues(alpha: 0.25) : Colors.transparent),
                            ),
                            child: Text(
                              TimelineFormat.time(t, use24h: false),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: sel ? scheme.onPrimary : ok ? scheme.primary : scheme.outline,
                                decoration: ok ? null : TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                  // ===== ملاحظة =====
                  const SectionTitle(title: 'ملاحظة للمعلم', icon: Icons.sticky_note_2_outlined),
                  TextField(
                    controller: _note,
                    maxLines: 2,
                    minLines: 1,
                    decoration: const InputDecoration(hintText: 'مثال: أريد مراجعة الفصل الثالث (اختياري)'),
                  ),
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error, style: const TextStyle(color: AppTheme.danger, fontSize: 12.5)),
                    ),
                  const SizedBox(height: 90),
                ],
              ),
            ),
          ],
        ),
        bottomSheet: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF141821) : Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -4))],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _start == null ? 'اختر وقتاً' : TimelineFormat.relativeDay(_start!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      _start == null
                          ? '${TimelineFormat.duration(_duration)}${est > 0 ? ' • تقديري ${TimelineFormat.money(est)}' : ''}'
                          : '${TimelineFormat.range(_start!, _start!.add(Duration(minutes: _duration)), use24h: false)}${est > 0 ? ' • ${TimelineFormat.money(est)}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 150,
                child: FilledButton.icon(
                  onPressed: _start == null || _sending ? null : _submit,
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 18),
                  label: const Text('إرسال الطلب'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
