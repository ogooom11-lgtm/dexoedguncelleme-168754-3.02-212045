// lib/src/pages/teacher_add_schedule_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../services/alarm_preferences.dart';
import '../services/notification_service_wrapper.dart';

class TeacherAddSchedulePage extends StatefulWidget {
  const TeacherAddSchedulePage({super.key});

  @override
  State<TeacherAddSchedulePage> createState() => _TeacherAddSchedulePageState();
}

class _TeacherAddSchedulePageState extends State<TeacherAddSchedulePage> {
  static const int kStartHour = 8;
  static const int kEndHour = 22;

  int _slotMinutes = 30;
  int get _totalSlots => ((kEndHour - kStartHour) * 60 ~/ _slotMinutes);

  String? _selectedStudentId;
  Map<String, Map<String, dynamic>> _students = {};

  DateTime? _selectedDate;
  int? _startIndex;
  int? _endIndex;

  bool _loading = false;
  bool _loadingSlots = false;
  String _error = '';

  final Set<int> _bookedIndices = {};

  // ==== خيارات التكرار ====
  String _repeatType = "none"; // none, daily, everyXDays, weekly, monthly
  int _repeatInterval = 1;
  String _endRepeatType = "none";
  int _occurrences = 1;
  DateTime? _endRepeatDate;

  @override
  void initState() {
    super.initState();
    _fetchStudents();
  }

  Future<void> _fetchStudents() async {
    final auth = context.read<AuthProvider>();
    final teacherCode = auth.currentUser?.code ?? "";

    try {
      final snap = await FirebaseDatabase.instance
          .ref("users/$teacherCode/students")
          .get();
      if (snap.exists && snap.value != null) {
        final raw = Map<String, dynamic>.from(snap.value as Map);
        final parsed = <String, Map<String, dynamic>>{};
        for (final e in raw.entries) {
          if (e.value is Map) {
            parsed[e.key] = Map<String, dynamic>.from(e.value as Map);
          } else {
            parsed[e.key] = {'name': e.value?.toString() ?? 'طالب'};
          }
        }
        if (mounted) setState(() => _students = parsed);
      } else {
        if (mounted) setState(() => _students = {});
      }
    } catch (e) {
      if (mounted) setState(() => _students = {});
    }
  }

  DateTime _slotIndexToDate(int idx) {
    final h = kStartHour + (idx * _slotMinutes) ~/ 60;
    final m = (idx * _slotMinutes) % 60;
    return DateTime(
        _selectedDate!.year, _selectedDate!.month, _selectedDate!.day, h, m);
  }

  int _dateTimeToSlotIndex(DateTime dt) {
    final minutesFromStart = (dt.hour - kStartHour) * 60 + dt.minute;
    return (minutesFromStart / _slotMinutes).floor().clamp(0, _totalSlots - 1);
  }

  String _labelForIndex(int idx) {
    final dt = _slotIndexToDate(idx);
    return DateFormat('HH:mm').format(dt);
  }

  Future<void> _fetchBooked(String teacherCode) async {
    if (_selectedDate == null || teacherCode.isEmpty) return;
    setState(() {
      _loadingSlots = true;
      _bookedIndices.clear();
      _startIndex = null;
      _endIndex = null;
      _error = '';
    });

    try {
      final ref = FirebaseDatabase.instance.ref("users/$teacherCode/schedule");
      final snap = await ref.get();

      if (snap.exists) {
        final map = Map<String, dynamic>.from(snap.value as Map);
        final selectedDay = DateFormat('yyyy-MM-dd').format(_selectedDate!);

        for (final v in map.values) {
          final item = Map<String, dynamic>.from(v);
          final status = (item['status'] ?? '').toString();
          if (status != 'scheduled' &&
              status != 'pending' &&
              status != 'started') {
            continue;
          }
          if ((item['date'] ?? '') != selectedDay) continue;
          if (item['startTime'] == null || item['endTime'] == null) continue;

          final start = DateTime.tryParse(item['startTime'].toString());
          final end = DateTime.tryParse(item['endTime'].toString());
          if (start == null || end == null) continue;

          final sIdx = _dateTimeToSlotIndex(start);
          final eIdx = _dateTimeToSlotIndex(end);
          for (int i = sIdx; i < eIdx; i++) {
            _bookedIndices.add(i);
          }
        }
      }

      final today = DateTime.now();
      if (_selectedDate != null &&
          DateFormat('yyyy-MM-dd').format(_selectedDate!) ==
              DateFormat('yyyy-MM-dd').format(today)) {
        final nowIdx = _dateTimeToSlotIndex(today);
        for (int i = 0; i <= nowIdx; i++) {
          _bookedIndices.add(i);
        }
      }
    } catch (e) {
      _error = "تعذر تحميل المواعيد: $e";
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  bool get _hasValidSelection =>
      _selectedStudentId != null &&
      _selectedDate != null &&
      _startIndex != null &&
      _endIndex != null &&
      _endIndex! >= _startIndex!;

  void _onTapSlot(int idx) {
    setState(() {
      if (_startIndex == null) {
        _startIndex = idx;
        _endIndex = null;
      } else if (_endIndex == null) {
        if (idx <= _startIndex!) {
          _startIndex = idx;
          _endIndex = null;
        } else {
          _endIndex = idx;
        }
      } else {
        _startIndex = idx;
        _endIndex = null;
      }
    });
  }

  Future<void> _submit() async {
    if (!_hasValidSelection) {
      setState(() => _error = "الرجاء اختيار الطالب والفترة");
      return;
    }

    final auth = context.read<AuthProvider>();
    final teacher = auth.currentUser!;
    final teacherCode = teacher.code;

    final startDateTime = _slotIndexToDate(_startIndex!);
    final endDateTime = _slotIndexToDate(_endIndex!);

    final duration = endDateTime.difference(startDateTime).inMinutes * 60;

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      if (_repeatType == "none") {
        // حفظ الموعد في Firebase
        final ref =
            FirebaseDatabase.instance.ref("users/$teacherCode/schedule");
        final newRef = ref.push();
        final lessonId = newRef.key!;

        await newRef.set({
          "teacher": teacher.code,
          "student": _selectedStudentId,
          "date": DateFormat('yyyy-MM-dd').format(_selectedDate!),
          "startTime": startDateTime.toIso8601String(),
          "endTime": endDateTime.toIso8601String(),
          "duration": duration,
          "createdAt": DateTime.now().toIso8601String(),
          "status": "scheduled",
        });

        final studentName =
            _students[_selectedStudentId]?['name']?.toString() ?? 'طالب';

        // 🟢 جدولة إشعارات Awesome فقط
        try {
          final prefs = await AlarmPreferences.load();
          final reminderTime =
              startDateTime.subtract(prefs.reminderLeadDuration);

          // ⏰ تذكير قبل 5 دقائق
          if (reminderTime.isAfter(DateTime.now())) {
            await NotificationServiceWrapper.scheduleReminderNotification(
              lessonId: lessonId,
              student: studentName,
              reminderTime: reminderTime,
              teacherCode: teacherCode,
            );
          }

          // 🚀 إشعار بداية الدرس (يوقظ الشاشة ويفتح AlarmPage)
          if (startDateTime.isAfter(DateTime.now())) {
            await NotificationServiceWrapper.scheduleLessonStartNotification(
              lessonId: lessonId,
              student: studentName,
              startTime: startDateTime,
              teacherCode: teacherCode,
            );
          }
        } catch (notifErr) {
          debugPrint("❌ Notification scheduling failed: $notifErr");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("تم حفظ الموعد لكن حدث خطأ في الإشعارات"),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        // 🌀 في حال التكرار (ما نضيف إشعار مباشر)
        final ref = FirebaseDatabase.instance
            .ref("users/$teacherCode/recurringSchedules");
        final newRef = ref.push();
        await newRef.set({
          "teacher": teacher.code,
          "student": _selectedStudentId,
          "startDate": DateFormat('yyyy-MM-dd').format(_selectedDate!),
          "startTime": startDateTime.toIso8601String(),
          "endTime": endDateTime.toIso8601String(),
          "duration": duration,
          "createdAt": DateTime.now().toIso8601String(),
          "repeatType": _repeatType,
          "repeatInterval": _repeatInterval,
          "endRepeatType": _endRepeatType,
          "occurrences": _occurrences,
          "endRepeatDate": _endRepeatDate?.toIso8601String(),
          "status": "temporary",
        });
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = "خطأ أثناء الإضافة: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _durationLabel(DateTime from, DateTime to) {
    final mins = to.difference(from).inMinutes;
    final h = mins ~/ 60;
    final m = mins % 60;
    if (h > 0 && m > 0) return "$hس $mد";
    if (h > 0) return "$hس";
    return "$mد";
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final teacherCode = auth.currentUser?.code ?? "";

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text("إضافة موعد"),
        centerTitle: true,
        backgroundColor: Colors.indigo,
        elevation: 4,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // === اختيار المدة ===
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 30, label: Text("نصف ساعة")),
                    ButtonSegment(value: 15, label: Text("ربع ساعة")),
                  ],
                  selected: {_slotMinutes},
                  onSelectionChanged: (val) {
                    setState(() {
                      _slotMinutes = val.first;
                      _startIndex = null;
                      _endIndex = null;
                    });
                  },
                ),
              ),
            ),

            // === اختيار الطالب ===
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: "اختر الطالب",
                    border: OutlineInputBorder(),
                  ),
                  value: _selectedStudentId,
                  items: _students.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value['name']?.toString() ?? "طالب"),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedStudentId = value;
                      _selectedDate = null;
                      _startIndex = null;
                      _endIndex = null;
                    });
                  },
                ),
              ),
            ),

            // === اختيار التاريخ ===
            if (_selectedStudentId != null)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: const Icon(Icons.date_range, color: Colors.indigo),
                  title: Text(
                    _selectedDate == null
                        ? "اختر التاريخ"
                        : DateFormat('yyyy-MM-dd').format(_selectedDate!),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      locale: const Locale("ar"),
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedDate = picked;
                      });
                      await _fetchBooked(teacherCode);
                    }
                  },
                ),
              ),

            const SizedBox(height: 12),

            // === خيارات التكرار ===
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: "التكرار",
                        border: OutlineInputBorder(),
                      ),
                      value: _repeatType,
                      items: const [
                        DropdownMenuItem(
                            value: "none", child: Text("بدون تكرار")),
                        DropdownMenuItem(value: "daily", child: Text("يومي")),
                        DropdownMenuItem(
                            value: "everyXDays", child: Text("كل X يوم")),
                        DropdownMenuItem(
                            value: "weekly", child: Text("أسبوعي")),
                        DropdownMenuItem(value: "monthly", child: Text("شهري")),
                      ],
                      onChanged: (val) {
                        setState(() => _repeatType = val!);
                      },
                    ),
                    if (_repeatType == "everyXDays" || _repeatType == "weekly")
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextFormField(
                          initialValue: "1",
                          decoration: InputDecoration(
                            labelText: _repeatType == "weekly"
                                ? "كل كم أسبوع"
                                : "كل كم يوم",
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            _repeatInterval = int.tryParse(val) ?? 1;
                          },
                        ),
                      ),
                    if (_repeatType != "none")
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: "توقف التكرار",
                            border: OutlineInputBorder(),
                          ),
                          value: _endRepeatType,
                          items: const [
                            DropdownMenuItem(
                                value: "none", child: Text("بدون")),
                            DropdownMenuItem(
                                value: "occurrences", child: Text("عدد مرات")),
                            DropdownMenuItem(
                                value: "untilDate", child: Text("حتى تاريخ")),
                            DropdownMenuItem(
                                value: "endOfMonth",
                                child: Text("نهاية الشهر")),
                            DropdownMenuItem(
                                value: "endOfYear", child: Text("نهاية السنة")),
                          ],
                          onChanged: (val) {
                            setState(() => _endRepeatType = val!);
                          },
                        ),
                      ),
                    if (_endRepeatType == "occurrences")
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextFormField(
                          initialValue: "1",
                          decoration: const InputDecoration(
                            labelText: "عدد مرات التكرار",
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            _occurrences = int.tryParse(val) ?? 1;
                          },
                        ),
                      ),
                    if (_endRepeatType == "untilDate")
                      ListTile(
                        leading: const Icon(Icons.calendar_month,
                            color: Colors.indigo),
                        title: Text(
                          _endRepeatDate == null
                              ? "اختر تاريخ النهاية"
                              : DateFormat('yyyy-MM-dd')
                                  .format(_endRepeatDate!),
                        ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                DateTime.now().add(const Duration(days: 7)),
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                            locale: const Locale("ar"),
                          );
                          if (picked != null) {
                            setState(() {
                              _endRepeatDate = picked;
                            });
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // === الشبكة ===
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: SizedBox(
                height: 320,
                child: _selectedStudentId == null
                    ? const Center(child: Text("اختر الطالب أولاً"))
                    : _selectedDate == null
                        ? const Center(child: Text("اختر تاريخاً"))
                        : _loadingSlots
                            ? const Center(child: CircularProgressIndicator())
                            : GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 6,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8,
                                  childAspectRatio: 1.4,
                                ),
                                itemCount: _totalSlots,
                                itemBuilder: (context, index) {
                                  final selectedStart = _startIndex == index;
                                  final selectedRange = _startIndex != null &&
                                      _endIndex != null &&
                                      index >= _startIndex! &&
                                      index <= _endIndex!;

                                  Color bg;
                                  IconData? icon;
                                  if (selectedStart) {
                                    bg = Colors.indigo.shade300;
                                    icon = Icons.flag_sharp;
                                  } else if (selectedRange) {
                                    bg = Colors.green.shade400;
                                    icon = Icons.check;
                                  } else if (_bookedIndices.contains(index)) {
                                    bg = Colors.red.shade300;
                                    icon = Icons.lock;
                                  } else {
                                    bg = Colors.grey.shade500;
                                  }

                                  return GestureDetector(
                                    onTap: () => _onTapSlot(index),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: bg,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      alignment: Alignment.center,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            _labelForIndex(index),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                          if (icon != null)
                                            Icon(icon,
                                                color: Colors.white, size: 18),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
            ),

            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  _error,
                  style: const TextStyle(color: Colors.red, fontSize: 14),
                ),
              ),

            if (_hasValidSelection)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  "من: ${_labelForIndex(_startIndex!)} → إلى: ${_labelForIndex(_endIndex!)} "
                  "(${_durationLabel(_slotIndexToDate(_startIndex!), _slotIndexToDate(_endIndex!))})",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: _loading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text("تأكيد الموعد"),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: Colors.indigoAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _hasValidSelection && !_loading ? _submit : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
