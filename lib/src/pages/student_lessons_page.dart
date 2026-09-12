import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import 'home_student.dart';

class StudentLessonsPage extends StatefulWidget {
  const StudentLessonsPage({super.key});

  @override
  State<StudentLessonsPage> createState() => _StudentLessonsPageState();
}

class _StudentLessonsPageState extends State<StudentLessonsPage>
    with SingleTickerProviderStateMixin {
  DateTime? _startDate;
  DateTime? _endDate;
  String _filterStatus = "all";

  late final AnimationController _animCtrl =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void initState() {
    super.initState();
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final student = auth.currentUser!;
    final teacherCode = student.teacher ?? "";
    final dbRef = FirebaseDatabase.instance.ref("users/$teacherCode/schedule");

    return Scaffold(
      appBar: AppBar(
        title: const Text("📖 سجل دروسي"),
        centerTitle: true,
        backgroundColor: Colors.indigo.shade600,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const HomeStudent()),
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt),
            tooltip: "فلترة",
            onPressed: () => _showFiltersSheet(context),
          ),
        ],
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: dbRef.onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
            return _emptyState("لا يوجد أي دروس بعد");
          }

          final data = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);

          // جلب دروس الطالب الحالي فقط
          final allLessons = data.entries.where((entry) {
            return (entry.value["student"] ?? "") == student.code;
          }).map<Map<String, dynamic>>((entry) {
            final lesson = Map<String, dynamic>.from(entry.value);
            lesson["id"] = entry.key;
            return lesson;
          }).toList();

          // ترتيب: started فوق
          allLessons.sort((a, b) {
            if (a["status"] == "started" && b["status"] != "started") return -1;
            if (b["status"] == "started" && a["status"] != "started") return 1;

            final da = DateTime.tryParse(a['endTime'] ?? '') ?? DateTime(2000);
            final db = DateTime.tryParse(b['endTime'] ?? '') ?? DateTime(2000);
            return db.compareTo(da);
          });

          // فلترة
          final filtered = _applyFilters(allLessons);

          if (filtered.isEmpty) {
            return Expanded(child: _emptyState("لا توجد نتائج مطابقة"));
          }

          return Column(
            children: [
              const SizedBox(height: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: ListView.builder(
                    key: ValueKey(
                        "${_startDate?.toIso8601String()}-${_endDate?.toIso8601String()}-$_filterStatus"),
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final lesson = filtered[index];
                      final startTime = _formatTime(lesson['startTime']);
                      final endTime = _formatTime(lesson['endTime']);
                      final duration = _formatDuration(lesson['duration']);
                      final date = (lesson['date'] ?? '').toString();
                      final status = (lesson['status'] ?? '').toString();

                      final amount = num.tryParse((lesson['amount'] ?? '0').toString()) ?? 0;

                      Widget rightChip;
                      if (status == "started" &&
                          (lesson['startTime'] ?? '').toString().isNotEmpty) {
                        rightChip = RunningTimeChip(
                            startIso: lesson['startTime'].toString());
                      } else {
                        rightChip = _valueChip("$amount ر.ق", false);
                      }

                      return _animatedLessonCard(
                        index: index,
                        child: InkWell(
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            await _showLessonSheet(
                                context, date, startTime, endTime, duration, lesson);
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Card(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            elevation: status == "started" ? 8 : 5,
                            shadowColor: Colors.indigo.withOpacity(0.15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              leading: Hero(
                                tag: "avatar_${lesson['id']}",
                                child: CircleAvatar(
                                  radius: 26,
                                  backgroundColor: Colors.indigo.shade100,
                                  child: const Icon(Icons.book,
                                      color: Colors.indigo, size: 28),
                                ),
                              ),
                              title: Text(
                                "📅 $date",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                              subtitle: Text(
                                "⏱ $startTime ← $endTime ($duration)",
                                style: TextStyle(
                                    color: Colors.grey.shade700, height: 1.35),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  rightChip,
                                  const SizedBox(width: 6),
                                  _statusChip(status),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ✅ BottomSheet للتفاصيل
  Future<void> _showLessonSheet(
      BuildContext context,
      String date,
      String startTime,
      String endTime,
      String duration,
      Map<String, dynamic> lesson,
      ) async {
    final amount = num.tryParse((lesson['amount'] ?? '0').toString()) ?? 0;
    final status = (lesson['status'] ?? '').toString();

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Hero(
                        tag: "avatar_${lesson['id']}",
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.indigo.shade200,
                          child: const Icon(Icons.book, color: Colors.indigo),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "تفاصيل الدرس",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _tile("التاريخ", date, Icons.event),
                  _tile("الوقت", "$startTime ← $endTime", Icons.schedule),
                  _tile("المدة", duration, Icons.timelapse),
                  _tile("المبلغ", "$amount ر.ق", Icons.payments),
                  _tile("الحالة", _statusLabel(status), Icons.info),

                  // ✅ الملاحظات أو سبب الإلغاء
                  Builder(builder: (context) {
                    final note =
                    (lesson['note'] ?? lesson['cancelReason'] ?? '').toString();
                    if (note.isEmpty) return const SizedBox.shrink();
                    return Column(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.note, color: Colors.indigo),
                          title: Text(
                            note,
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.article, color: Colors.indigo),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text("الملاحظة"),
                                  content:
                                  SingleChildScrollView(child: Text(note)),
                                  actions: [
                                    TextButton(
                                      child: const Text("إغلاق"),
                                      onPressed: () => Navigator.pop(context),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    );
                  }),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tile(String title, String value, IconData icon) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.indigo),
      title: Text(title, textAlign: TextAlign.right),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  // ✅ نافذة الفلترة
  Future<void> _showFiltersSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("خيارات الفلترة",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              _filtersArea(),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check),
                label: const Text("تطبيق الفلتر"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _startDate = null;
                    _endDate = null;
                    _filterStatus = "all";
                  });
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.clear),
                label: const Text("حذف الفلاتر"),
              ),
            ],
          ),
        );
      },
    );
  }

  // ✅ منطقة الفلاتر (مستعملة فقط بالنافذة)
  Widget _filtersArea() {
    return Column(
      children: [
        _DateRangeButton(
          startDate: _startDate,
          endDate: _endDate,
          onPick: (start, end) {
            setState(() {
              _startDate = start;
              _endDate = end;
            });
          },
          onClear: () {
            setState(() {
              _startDate = null;
              _endDate = null;
            });
          },
        ),
        const SizedBox(height: 12),
        DropdownButton<String>(
          value: _filterStatus,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: "all", child: Text("كل الحالات")),
            DropdownMenuItem(value: "pending", child: Text("بانتظار")),
            DropdownMenuItem(value: "scheduled", child: Text("مجدولة")),
            DropdownMenuItem(value: "started", child: Text("جارية")),
            DropdownMenuItem(value: "ended", child: Text("منتهية")),
            DropdownMenuItem(value: "canceled", child: Text("ملغاة")),
          ],
          onChanged: (v) => setState(() => _filterStatus = v ?? "all"),
        ),
      ],
    );
  }

  // ✅ فلترة
  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> all) {
    return all.where((lesson) {
      final status = (lesson['status'] ?? '').toString();

      if (_filterStatus != "all" && status != _filterStatus) {
        return false;
      }

      final endTimeStr = (lesson['endTime'] ?? '').toString();
      DateTime? endTime = DateTime.tryParse(endTimeStr);

      if (endTime == null) {
        final dateStr = (lesson['date'] ?? '').toString();
        try {
          endTime = DateFormat('yyyy-MM-dd').parse(dateStr);
        } catch (_) {}
      }

      if (_startDate != null && endTime != null && endTime.isBefore(_startDate!)) {
        return false;
      }
      if (_endDate != null &&
          endTime != null &&
          endTime.isAfter(_endDate!.add(const Duration(days: 1)).subtract(const Duration(seconds: 1)))) {
        return false;
      }

      return true;
    }).toList();
  }



  // ✅ Widgets
  Widget _valueChip(String text, bool isRunning) {
    final color = isRunning ? Colors.orange : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: color.shade700,
        ),
      ),
    );
  }

  Widget _statusChip(String? status) {
    final map = {
      "scheduled": {"label": "📅 مجدولة", "color": Colors.blueAccent},
      "started": {"label": "▶️ جارية", "color": Colors.orange},
      "ended": {"label": "✅ منتهية", "color": Colors.green},
      "canceled": {"label": "❌ ملغاة", "color": Colors.red},
      "pending": {"label": "⌛ بانتظار", "color": Colors.purple},
    };
    final data = map[status] ?? {"label": "غير معروف", "color": Colors.grey};
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (data["color"] as Color).withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: (data["color"] as Color).withOpacity(0.4)),
      ),
      child: Text(
        data["label"].toString(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: data["color"] as Color,
        ),
      ),
    );
  }

  Widget _animatedLessonCard({required int index, required Widget child}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 250 + (index * 30).clamp(0, 300)),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Transform.translate(
        offset: Offset(0, (1 - v) * 20),
        child: Opacity(opacity: v, child: child),
      ),
    );
  }

  Widget _emptyState(String text) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.hourglass_empty, size: 56, color: Colors.indigo.shade200),
        const SizedBox(height: 10),
        Text(text, style: const TextStyle(fontSize: 18, color: Colors.grey)),
      ],
    );
  }

  String _formatTime(dynamic isoString) {
    if (isoString == null || isoString.toString().isEmpty) return "--:--";
    try {
      final dt = DateTime.parse(isoString.toString());
      return DateFormat('HH:mm').format(dt);
    } catch (_) {
      return "--:--";
    }
  }

  String _formatDuration(dynamic duration) {
    if (duration == null) return "--:--:--";
    final totalSeconds = int.tryParse(duration.toString()) ?? 0;
    final h = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  String _statusLabel(String status) {
    switch (status) {
      case "scheduled":
        return "📅 مجدولة";
      case "started":
        return "▶️ جارية";
      case "ended":
        return "✅ منتهية";
      case "canceled":
        return "❌ ملغاة";
      case "pending":
        return "⌛ بانتظار";
      default:
        return "غير معروف";
    }
  }
}

// 🔎 زر اختيار التاريخ
class _DateRangeButton extends StatelessWidget {
  final DateTime? startDate;
  final DateTime? endDate;
  final void Function(DateTime start, DateTime end) onPick;
  final VoidCallback onClear;

  const _DateRangeButton({
    required this.startDate,
    required this.endDate,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final text = (startDate == null || endDate == null)
        ? "حسب التاريخ"
        : "${DateFormat('yyyy-MM-dd').format(startDate!)} ← ${DateFormat('yyyy-MM-dd').format(endDate!)}";

    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
        backgroundColor: Colors.indigo.shade200,
        foregroundColor: Colors.indigo.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () async {
        final now = DateTime.now();
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(now.year - 3),
          lastDate: DateTime(now.year + 1),
          locale: const Locale('ar'),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: Colors.indigo,
                  onPrimary: Colors.white,
                  surface: Colors.indigo.shade200,
                ),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) {
          onPick(picked.start, picked.end);
          HapticFeedback.lightImpact();
        }
      },
      icon: const Icon(Icons.date_range),
      label: Row(
        children: [
          Expanded(child: Text(text, textAlign: TextAlign.right)),
          if (startDate != null && endDate != null)
            IconButton(
              tooltip: "مسح",
              onPressed: onClear,
              icon: const Icon(Icons.close, size: 18),
            ),
        ],
      ),
    );
  }
}

// ✅ ودجت خاصة لعرض الوقت الجاري
class RunningTimeChip extends StatefulWidget {
  final String startIso;

  const RunningTimeChip({super.key, required this.startIso});

  @override
  State<RunningTimeChip> createState() => _RunningTimeChipState();
}

class _RunningTimeChipState extends State<RunningTimeChip> {
  late Timer _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _calculate();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _calculate());
      }
    });
  }

  void _calculate() {
    final parsed = DateTime.tryParse(widget.startIso);
    if (parsed != null) {
      final now = DateTime.now();
      _elapsed = now.difference(parsed);
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withOpacity(0.35)),
      ),
      child: Text(
        _formatDuration(_elapsed),
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: Colors.orange,
        ),
      ),
    );
  }
}
