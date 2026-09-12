// lib/src/pages/teacher_edit_schedule_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/alarm_preferences.dart';
import '../services/notification_service_wrapper.dart';

class TeacherEditSchedulePage extends StatefulWidget {
  final String lessonId;
  final Map<String, dynamic> lessonData;

  const TeacherEditSchedulePage({
    super.key,
    required this.lessonId,
    required this.lessonData,
  });

  @override
  State<TeacherEditSchedulePage> createState() =>
      _TeacherEditSchedulePageState();
}

class _TeacherEditSchedulePageState extends State<TeacherEditSchedulePage> {
  static const int kStartHour = 8;
  static const int kEndHour = 22;

  int _slotMinutes = 30;
  int get _totalSlots => ((kEndHour - kStartHour) * 60 ~/ _slotMinutes);

  DateTime? _selectedDate;
  int? _startIndex;
  int? _endIndex;

  bool _loading = false;
  bool _loadingSlots = false;
  String _error = '';

  final Set<int> _bookedIndices = {};

  @override
  void initState() {
    super.initState();
    _initFromLesson();
  }

  void _initFromLesson() {
    if (widget.lessonData['date'] != null &&
        widget.lessonData['date'].toString().isNotEmpty) {
      _selectedDate = DateTime.tryParse(widget.lessonData['date']);
    }

    if (widget.lessonData['startTime'] != null &&
        widget.lessonData['endTime'] != null) {
      final start = DateTime.tryParse(widget.lessonData['startTime']);
      final end = DateTime.tryParse(widget.lessonData['endTime']);
      if (start != null && end != null) {
        _startIndex = _dateTimeToSlotIndex(start);
        _endIndex = _dateTimeToSlotIndex(end);
      }
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
      _error = '';
    });

    try {
      final ref = FirebaseDatabase.instance.ref("users/$teacherCode/schedule");
      final snap = await ref.get();

      if (snap.exists) {
        final map = Map<String, dynamic>.from(snap.value as Map);
        final selectedDay = DateFormat('yyyy-MM-dd').format(_selectedDate!);

        for (final entry in map.entries) {
          if (entry.key == widget.lessonId) continue;

          final item = Map<String, dynamic>.from(entry.value);
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
      _selectedDate != null &&
      _startIndex != null &&
      _endIndex != null &&
      _endIndex! >= _startIndex!;

  void _onTapSlot(int idx) {
    setState(() {
      _error = '';
      if (_startIndex == null || _endIndex != null) {
        _startIndex = idx;
        _endIndex = null;
      } else if (_endIndex == null) {
        if (idx <= _startIndex!) {
          _startIndex = idx;
          _endIndex = null;
        } else {
          _endIndex = idx;
        }
      }
    });
  }

  Future<void> _saveChanges() async {
    if (!_hasValidSelection) {
      setState(() => _error = "الرجاء اختيار فترة صحيحة");
      return;
    }

    final auth = context.read<AuthProvider>();
    final teacherCode = auth.currentUser?.code ?? "";
    final ref = FirebaseDatabase.instance
        .ref("users/$teacherCode/schedule/${widget.lessonId}");

    final startDateTime = _slotIndexToDate(_startIndex!);
    final endDateTime = _slotIndexToDate(_endIndex!);

    final duration = endDateTime.difference(startDateTime).inMinutes * 60;

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      await ref.update({
        "date": DateFormat('yyyy-MM-dd').format(_selectedDate!),
        "startTime": startDateTime.toIso8601String(),
        "endTime": endDateTime.toIso8601String(),
        "duration": duration,
        "updatedAt": DateTime.now().toIso8601String(),
      });

      // 🟢 إعادة جدولة الإشعارات
      await NotificationServiceWrapper.cancelLessonNotification(
          widget.lessonId);

      final studentName =
          (widget.lessonData['studentName'] ?? 'طالب').toString();
      final prefs = await AlarmPreferences.load();
      final reminderTime = startDateTime.subtract(prefs.reminderLeadDuration);

      if (reminderTime.isAfter(DateTime.now())) {
        await NotificationServiceWrapper.scheduleReminderNotification(
          lessonId: widget.lessonId,
          student: studentName,
          reminderTime: reminderTime,
          teacherCode: teacherCode,
        );
      }

      if (startDateTime.isAfter(DateTime.now())) {
        await NotificationServiceWrapper.scheduleLessonStartNotification(
          lessonId: widget.lessonId,
          student: studentName,
          startTime: startDateTime,
          teacherCode: teacherCode,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم تحديث الموعد بنجاح ✅")),
      );
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = "خطأ أثناء الحفظ: $e");
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

  void _changeSlotMinutes(int minutes) {
    if (_slotMinutes == minutes) return;

    DateTime? startTime;
    DateTime? endTime;

    if (_selectedDate != null && _startIndex != null && _endIndex != null) {
      startTime = _slotIndexToDate(_startIndex!);
      endTime = _slotIndexToDate(_endIndex!);
    }

    setState(() {
      _slotMinutes = minutes;
      _startIndex = null;
      _endIndex = null;

      if (startTime != null && endTime != null) {
        _startIndex = _dateTimeToSlotIndex(startTime);
        _endIndex = _dateTimeToSlotIndex(endTime);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final teacherCode = auth.currentUser?.code ?? "";

    return Scaffold(
      appBar: AppBar(
        title: const Text("✏️ تعديل الموعد"),
        backgroundColor: Colors.teal,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: ToggleButtons(
              isSelected: [_slotMinutes == 30, _slotMinutes == 15],
              onPressed: (index) {
                _changeSlotMinutes(index == 0 ? 30 : 15);
              },
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text("نصف ساعة"),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text("ربع ساعة"),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.date_range),
            title: Text(_selectedDate == null
                ? "اختر التاريخ"
                : DateFormat('yyyy-MM-dd').format(_selectedDate!)),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate ?? DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
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
          const Divider(),
          Expanded(
            child: _selectedDate == null
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
                          childAspectRatio: 1.5,
                        ),
                        itemCount: _totalSlots,
                        itemBuilder: (context, index) {
                          final booked = _bookedIndices.contains(index);
                          final selectedStart = _startIndex == index;
                          final selectedRange = _startIndex != null &&
                              _endIndex != null &&
                              index >= _startIndex! &&
                              index <= _endIndex!;

                          Color bg;
                          if (booked) {
                            bg = Colors.orange;
                          } else if (selectedStart) {
                            bg = Colors.yellow;
                          } else if (selectedRange) {
                            bg = Colors.green;
                          } else {
                            bg = Colors.grey.shade200;
                          }

                          return GestureDetector(
                            onTap: () => _onTapSlot(index),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selectedStart ||
                                          (selectedRange && index == _endIndex)
                                      ? Colors.black
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Text(
                                _labelForIndex(index),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(_error,
                  style: const TextStyle(color: Colors.red, fontSize: 14)),
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
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                        minimumSize: const Size.fromHeight(50)),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text("إلغاء"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        minimumSize: const Size.fromHeight(50)),
                    onPressed:
                        _hasValidSelection && !_loading ? _saveChanges : null,
                    icon: const Icon(Icons.save),
                    label: const Text("حفظ التعديلات"),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
