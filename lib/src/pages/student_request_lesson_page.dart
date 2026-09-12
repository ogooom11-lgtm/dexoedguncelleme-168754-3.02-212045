import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';

class StudentRequestLessonPage extends StatefulWidget {
  const StudentRequestLessonPage({super.key});

  @override
  State<StudentRequestLessonPage> createState() =>
      _StudentRequestLessonPageState();
}

class _StudentRequestLessonPageState extends State<StudentRequestLessonPage> {
  static const int kStartHour = 8;
  static const int kEndHour = 22;

  int _slotMinutes = 30; // خيار نصف ساعة / ربع ساعة
  int get _totalSlots =>
      ((kEndHour - kStartHour) * 60 ~/ _slotMinutes);

  DateTime? _selectedDate;
  int? _startIndex;
  int? _endIndex;

  bool _loading = false;
  bool _loadingSlots = false;
  String _error = '';

  final Set<int> _bookedIndices = {};

  DateTime _slotIndexToDate(int idx) {
    final h = kStartHour + (idx * _slotMinutes) ~/ 60;
    final m = (idx * _slotMinutes) % 60;
    return DateTime(_selectedDate!.year, _selectedDate!.month,
        _selectedDate!.day, h, m);
  }

  int _dateTimeToSlotIndex(DateTime dt) {
    final minutesFromStart = (dt.hour - kStartHour) * 60 + dt.minute;
    return (minutesFromStart / _slotMinutes)
        .floor()
        .clamp(0, _totalSlots - 1);
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
              status != 'started') continue;
          if ((item['date'] ?? '') != selectedDay) continue;
          if (item['startTime'] == null || item['endTime'] == null) continue;

          final start = DateTime.tryParse(item['startTime'].toString());
          final end = DateTime.tryParse(item['endTime'].toString());
          if (start == null || end == null) continue;

          final sIdx = _dateTimeToSlotIndex(start);
          final eIdx = _dateTimeToSlotIndex(end);
          // نعتبر end كقيمة حصرية (كما في صفحة المعلم) -> نغطي sIdx .. eIdx-1
          for (int i = sIdx; i < eIdx; i++) {
            _bookedIndices.add(i);
          }
        }
      }

      // قفل الساعات الماضية إذا نفس اليوم
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

  // نوافق اختيار حتى لو المدة خانة واحدة
  bool get _hasValidSelection =>
      _selectedDate != null &&
          _startIndex != null &&
          _endIndex != null &&
          _endIndex! >= _startIndex!;

  void _onTapSlot(int idx) {
    // إذا الخانة نفسها محجوزة، لا نفعل شيء
    if (_bookedIndices.contains(idx)) {
      setState(() {
        _error = "هذه الخانة محجوزة.";
      });
      return;
    }

    setState(() {
      _error = '';
      if (_startIndex == null) {
        // أول اختيار: يصبح البداية (أصفر)
        _startIndex = idx;
        _endIndex = null;
      } else if (_endIndex == null) {
        // نجهز للاختيار الثاني → إما إعادة تحديد البداية أو تحديد النهاية
        if (idx <= _startIndex!) {
          // المستخدم ضغط خانة قبل/مساوية للبداية → نعيد ضبط البداية (طالما غير محجوز)
          _startIndex = idx;
          _endIndex = null;
        } else {
          // المستخدم يختار نهاية (أكبر من البداية) → لازم نتأكد أن النطاق خالٍ من المحجوزات
          bool overlap = false;
          for (int i = _startIndex!; i <= idx; i++) {
            if (_bookedIndices.contains(i)) {
              overlap = true;
              break;
            }
          }
          if (overlap) {
            _error = "النطاق الذي اخترته يتداخل مع مواعيد محجوزة. حاول اختيار نهاية أبكر أو بداية لاحقة.";
            // لا نغير start/end هنا — نترك البداية كما هي لتجربة اختيار آخر
          } else {
            // صالح: نجعل idx هو النهاية
            _endIndex = idx;
          }
        }
      } else {
        // كان هناك تحديد كامل سابقًا -> نبدأ تحديد جديد من هذه الخانة (مثل صفحة المعلم)
        _startIndex = idx;
        _endIndex = null;
      }
    });
  }

  Future<void> _submit() async {
    if (!_hasValidSelection) {
      setState(() => _error = "الرجاء اختيار فترة صحيحة");
      return;
    }

    final auth = context.read<AuthProvider>();
    final student = auth.currentUser!;
    final teacherCode = student.teacher ?? "";

    final startDateTime = _slotIndexToDate(_startIndex!);
    // لحفظ نهاية الميعاد نأخذ endIndex + 1 (سلوك مطابق لصفحة المعلم)
    final endDateTime = _slotIndexToDate(_endIndex! + 1);

    final duration = endDateTime.difference(startDateTime).inMinutes * 60;

    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final ref = FirebaseDatabase.instance.ref("users/$teacherCode/schedule");
      await ref.push().set({
        "student": student.code,
        "date": DateFormat('yyyy-MM-dd').format(_selectedDate!),
        "startTime": startDateTime.toIso8601String(),
        "endTime": endDateTime.toIso8601String(),
        "duration": duration,
        "createdAt": DateTime.now().toIso8601String(),
        "status": "pending",
      });

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = "خطأ أثناء الإرسال: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _durationLabel(DateTime from, DateTime to) {
    final mins = to.difference(from).inMinutes;
    final h = mins ~/ 60;
    final m = mins % 60;
    if (h > 0 && m > 0) return "${h}س ${m}د";
    if (h > 0) return "${h}س";
    return "${m}د";
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final teacherCode = auth.currentUser?.teacher ?? "";

    return Scaffold(
      appBar: AppBar(
        title: const Text("📅 طلب موعد جديد"),
        backgroundColor: Colors.indigo,
      ),
      body: Column(
        children: [
          // اختيار نصف ساعة / ربع ساعة
          Padding(
            padding: const EdgeInsets.all(12),
            child: ToggleButtons(
              isSelected: [_slotMinutes == 30, _slotMinutes == 15],
              onPressed: (index) {
                setState(() {
                  _slotMinutes = index == 0 ? 30 : 15;
                  _startIndex = null;
                  _endIndex = null;
                  _error = '';
                });
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
                  bg = Colors.red.shade300;
                } else if (selectedStart) {
                  bg = Colors.yellow; // أول خانة
                } else if (selectedRange) {
                  bg = Colors.green.shade400; // المدى
                } else {
                  bg = Colors.grey.shade200;
                }

                return GestureDetector(
                  onTap: booked ? null : () => _onTapSlot(index),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selectedStart ||
                            (selectedRange &&
                                (index == _endIndex))
                            ? Colors.black
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Text(
                      _labelForIndex(index),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: booked ? Colors.white : Colors.black,
                      ),
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
            child: ElevatedButton.icon(
              icon: const Icon(Icons.send),
              label: const Text("إرسال الطلب"),
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: Colors.indigo),
              onPressed: _hasValidSelection && !_loading ? _submit : null,
            ),
          ),
        ],
      ),
    );
  }
}
