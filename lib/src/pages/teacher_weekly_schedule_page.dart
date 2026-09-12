import 'dart:ui' as ui;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/recurrence_utils.dart';

class TeacherWeeklySchedulePage extends StatefulWidget {
  const TeacherWeeklySchedulePage({super.key});

  @override
  State<TeacherWeeklySchedulePage> createState() =>
      _TeacherWeeklySchedulePageState();
}

class _TeacherWeeklySchedulePageState extends State<TeacherWeeklySchedulePage> {
  static const int _startHour = 8;
  static const int _endHour = 22;
  static const int _slotMinutes = 30;

  late DateTime _weekStart;
  bool _freeOnly = false;

  @override
  void initState() {
    super.initState();
    _weekStart = _startOfWeek(DateTime.now());
  }

  DateTime _startOfWeek(DateTime date) {
    final clean = DateTime(date.year, date.month, date.day);
    final diff = (clean.weekday - DateTime.saturday) % 7;
    return clean.subtract(Duration(days: diff));
  }

  List<DateTime> get _weekDays =>
      List.generate(7, (index) => _weekStart.add(Duration(days: index)));

  List<TimeOfDay> get _slots {
    final total = ((_endHour - _startHour) * 60) ~/ _slotMinutes;
    return List.generate(total, (index) {
      final minutes = (_startHour * 60) + index * _slotMinutes;
      return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    });
  }

  Future<_WeeklyData> _loadData() async {
    final auth = context.read<AuthProvider>();
    final teacherCode = auth.currentUser?.code ?? '';
    if (teacherCode.isEmpty) return const _WeeklyData([], {});

    final studentsSnap = await FirebaseDatabase.instance
        .ref('users/$teacherCode/students')
        .get();
    final students = <String, String>{};
    if (studentsSnap.exists && studentsSnap.value is Map) {
      final raw = Map<String, dynamic>.from(studentsSnap.value as Map);
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is Map) {
          final map = Map<String, dynamic>.from(value);
          students[entry.key] = (map['name'] ?? 'طالب').toString();
        } else {
          students[entry.key] = value?.toString() ?? 'طالب';
        }
      }
    }

    final lessons = <_WeekLesson>[];
    final confirmedKeys = <String>{};
    final weekEnd = _weekStart.add(const Duration(days: 7));

    final scheduleSnap = await FirebaseDatabase.instance
        .ref('users/$teacherCode/schedule')
        .get();
    if (scheduleSnap.exists && scheduleSnap.value is Map) {
      final raw = Map<String, dynamic>.from(scheduleSnap.value as Map);
      for (final entry in raw.entries) {
        if (entry.value is! Map) continue;
        final map = Map<String, dynamic>.from(entry.value as Map);
        final status = (map['status'] ?? '').toString();
        if (status == 'canceled' ||
            status == 'temporary' ||
            status == 'pending') {
          continue;
        }

        final start = DateTime.tryParse(map['startTime']?.toString() ?? '');
        final end = DateTime.tryParse(map['endTime']?.toString() ?? '');
        if (start == null || end == null) continue;
        if (end.isBefore(_weekStart) || !start.isBefore(weekEnd)) continue;

        final studentId = (map['student'] ?? '').toString();
        final key = _lessonSignature(studentId, start, end);
        confirmedKeys.add(key);
        lessons.add(
          _WeekLesson(
            id: entry.key,
            studentId: studentId,
            studentName: students[studentId] ??
                (map['studentName']?.toString() ?? 'طالب'),
            date: DateTime(start.year, start.month, start.day),
            start: start,
            end: end,
            color: _colorFor(studentId),
            kind: _WeekLessonKind.confirmed,
            status: status.isEmpty ? 'scheduled' : status,
          ),
        );
      }
    }

    final recurringSnap = await FirebaseDatabase.instance
        .ref('users/$teacherCode/recurringSchedules')
        .get();
    if (recurringSnap.exists && recurringSnap.value is Map) {
      final raw = Map<String, dynamic>.from(recurringSnap.value as Map);
      for (final entry in raw.entries) {
        if (entry.value is! Map) continue;
        final recurring = RecurringSchedule.fromMap(
          entry.key,
          Map<String, dynamic>.from(entry.value as Map),
        );
        for (final day in _weekDays) {
          if (!RecurrenceUtils.occursOn(recurring, day)) continue;
          final start = RecurrenceUtils.buildStartForDay(recurring, day);
          final end = RecurrenceUtils.buildEndForDay(recurring, day);
          if (confirmedKeys
              .contains(_lessonSignature(recurring.student, start, end))) {
            continue;
          }
          lessons.add(
            _WeekLesson(
              id: recurring.id,
              studentId: recurring.student,
              studentName: students[recurring.student] ?? 'طالب',
              date: DateTime(day.year, day.month, day.day),
              start: start,
              end: end,
              color: _colorFor(recurring.student),
              kind: _WeekLessonKind.recurring,
              status: 'recurring',
            ),
          );
        }
      }
    }
    lessons.sort((a, b) => a.start.compareTo(b.start));
    return _WeeklyData(lessons, students);
  }

  static Color _colorFor(String key) {
    final colors = [
      Colors.teal,
      Colors.indigo,
      Colors.deepOrange,
      Colors.purple,
      Colors.blue,
      Colors.green,
      Colors.pink,
      Colors.cyan,
    ];
    return colors[key.hashCode.abs() % colors.length];
  }

  String _lessonSignature(String studentId, DateTime start, DateTime end) {
    return '$studentId|${start.toIso8601String()}|${end.toIso8601String()}';
  }

  @override
  Widget build(BuildContext context) {
    final range =
        '${DateFormat('yyyy/MM/dd').format(_weekStart)} - ${DateFormat('yyyy/MM/dd').format(_weekStart.add(const Duration(days: 6)))}';

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الجدول الأسبوعي'),
          actions: [
            IconButton(
              tooltip: 'الأسبوع الحالي',
              icon: const Icon(Icons.today_rounded),
              onPressed: () =>
                  setState(() => _weekStart = _startOfWeek(DateTime.now())),
            ),
          ],
        ),
        body: FutureBuilder<_WeeklyData>(
          future: _loadData(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data ?? const _WeeklyData([], {});
            return Column(
              children: [
                _toolbar(context, range),
                _legend(context, data.lessons),
                Expanded(child: _weeklyGrid(context, data.lessons)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context, String range) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: 'السابق',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => setState(() {
              _weekStart = _weekStart.subtract(const Duration(days: 7));
            }),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text(
                range,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'التالي',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => setState(() {
              _weekStart = _weekStart.add(const Duration(days: 7));
            }),
          ),
          const SizedBox(width: 8),
          FilterChip(
            selected: _freeOnly,
            label: const Text('الفارغ'),
            avatar: const Icon(Icons.event_available_rounded, size: 18),
            onSelected: (v) => setState(() => _freeOnly = v),
          ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, List<_WeekLesson> lessons) {
    final busy = lessons.length;
    final confirmed = lessons
        .where((lesson) => lesson.kind == _WeekLessonKind.confirmed)
        .length;
    final recurring = lessons
        .where((lesson) => lesson.kind == _WeekLessonKind.recurring)
        .length;
    final total = _slots.length * 7;
    final free = total -
        _slots
            .expand((slot) =>
                _weekDays.map((day) => _lessonsForSlot(lessons, day, slot)))
            .where((items) => items.isNotEmpty)
            .length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _pill(context, Icons.school_rounded, '$busy درس', Colors.indigo),
          const SizedBox(width: 8),
          _pill(
              context, Icons.verified_rounded, '$confirmed مؤكد', Colors.green),
          const SizedBox(width: 8),
          _pill(context, Icons.event_repeat_rounded, '$recurring متكرر',
              Colors.deepOrange),
          const SizedBox(width: 8),
          _pill(context, Icons.event_available_rounded, '$free وقت فارغ',
              Colors.teal),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _weeklyGrid(BuildContext context, List<_WeekLesson> lessons) {
    const timeWidth = 66.0;
    const dayWidth = 132.0;
    const cellHeight = 58.0;
    final scheme = Theme.of(context).colorScheme;

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  _headerCell('', width: timeWidth, scheme: scheme),
                  ..._slots.map(
                      (slot) => _timeCell(slot, timeWidth, cellHeight, scheme)),
                ],
              ),
              ..._weekDays.map((day) {
                return Column(
                  children: [
                    _dayHeader(day, dayWidth, scheme),
                    ..._slots.map((slot) {
                      final items = _lessonsForSlot(lessons, day, slot);
                      return _slotCell(
                        context,
                        width: dayWidth,
                        height: cellHeight,
                        day: day,
                        slot: slot,
                        lessons: items,
                        hideBusyDetails: _freeOnly && items.isNotEmpty,
                        scheme: scheme,
                      );
                    }),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCell(String text,
      {required double width, required ColorScheme scheme}) {
    return Container(
      width: width,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _dayHeader(DateTime day, double width, ColorScheme scheme) {
    final labels = [
      'السبت',
      'الأحد',
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة'
    ];
    final index = day.difference(_weekStart).inDays.clamp(0, 6);
    final isToday = DateFormat('yyyy-MM-dd').format(day) ==
        DateFormat('yyyy-MM-dd').format(DateTime.now());
    return Container(
      width: width,
      height: 54,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color:
            isToday ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(labels[index],
              style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(DateFormat('MM/dd').format(day),
              style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _timeCell(
      TimeOfDay slot, double width, double height, ColorScheme scheme) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Text(
        _formatTimeOfDay(slot),
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _slotCell(
    BuildContext context, {
    required double width,
    required double height,
    required DateTime day,
    required TimeOfDay slot,
    required List<_WeekLesson> lessons,
    required bool hideBusyDetails,
    required ColorScheme scheme,
  }) {
    final busy = lessons.isNotEmpty;
    return InkWell(
      onTap: () => _showSlotDetails(context, day, slot, lessons),
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: busy
              ? (hideBusyDetails
                  ? scheme.surfaceContainerHighest.withValues(alpha: 0.45)
                  : lessons.first.color.withValues(
                      alpha: lessons.first.kind == _WeekLessonKind.confirmed
                          ? 0.18
                          : 0.10,
                    ))
              : scheme.surface,
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: hideBusyDetails
            ? Center(
                child: Text(
                  'مشغول',
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              )
            : busy
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: lessons.take(2).map((lesson) {
                      final startsHere = lesson.start.hour == slot.hour &&
                          lesson.start.minute == slot.minute;
                      return Row(
                        children: [
                          Icon(
                            lesson.kind == _WeekLessonKind.confirmed
                                ? Icons.verified_rounded
                                : Icons.event_repeat_rounded,
                            size: 13,
                            color: lesson.color,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              startsHere
                                  ? lesson.studentName
                                  : '↳ ${lesson.studentName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: lesson.color,
                                fontWeight: startsHere
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  )
                : Center(
                    child: Text(
                      'فارغ',
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ),
      ),
    );
  }

  List<_WeekLesson> _lessonsForSlot(
    List<_WeekLesson> lessons,
    DateTime day,
    TimeOfDay slot,
  ) {
    final start =
        DateTime(day.year, day.month, day.day, slot.hour, slot.minute);
    final end = start.add(const Duration(minutes: _slotMinutes));
    return lessons.where((lesson) {
      final sameDay = lesson.date.year == day.year &&
          lesson.date.month == day.month &&
          lesson.date.day == day.day;
      return sameDay && start.isBefore(lesson.end) && end.isAfter(lesson.start);
    }).toList();
  }

  void _showSlotDetails(
    BuildContext context,
    DateTime day,
    TimeOfDay slot,
    List<_WeekLesson> lessons,
  ) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return Directionality(
          textDirection: ui.TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${DateFormat('yyyy/MM/dd').format(day)} • ${_formatTimeOfDay(slot)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  if (lessons.isEmpty)
                    const ListTile(
                      leading: Icon(Icons.event_available_rounded,
                          color: Colors.teal),
                      title: Text('وقت فارغ'),
                    )
                  else
                    ...lessons.map((lesson) {
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: lesson.color.withValues(alpha: 0.15),
                          child:
                              Icon(Icons.school_rounded, color: lesson.color),
                        ),
                        title: Text(lesson.studentName),
                        subtitle: Text(
                          '${lesson.kind.label} • ${DateFormat('HH:mm').format(lesson.start)} - ${DateFormat('HH:mm').format(lesson.end)}',
                        ),
                        trailing: _statusChip(context, lesson),
                      );
                    }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statusChip(BuildContext context, _WeekLesson lesson) {
    final color =
        lesson.kind == _WeekLessonKind.confirmed ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        lesson.kind.label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _formatTimeOfDay(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

class _WeeklyData {
  final List<_WeekLesson> lessons;
  final Map<String, String> students;

  const _WeeklyData(this.lessons, this.students);
}

class _WeekLesson {
  final String id;
  final String studentId;
  final String studentName;
  final DateTime date;
  final DateTime start;
  final DateTime end;
  final Color color;
  final _WeekLessonKind kind;
  final String status;

  const _WeekLesson({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.date,
    required this.start,
    required this.end,
    required this.color,
    required this.kind,
    required this.status,
  });
}

enum _WeekLessonKind {
  recurring,
  confirmed;

  String get label {
    switch (this) {
      case _WeekLessonKind.recurring:
        return 'متكرر';
      case _WeekLessonKind.confirmed:
        return 'مؤكد';
    }
  }
}
