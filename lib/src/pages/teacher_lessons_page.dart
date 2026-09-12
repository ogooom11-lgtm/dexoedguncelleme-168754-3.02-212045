import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'teacher_add_ended_lesson_page.dart';
import 'package:intl/intl.dart';

import '../providers/auth_provider.dart';
import '../services/pdf_export_service.dart';
import '../theme/app_theme.dart';

class TeacherLessonsPage extends StatefulWidget {
  const TeacherLessonsPage({super.key, this.initialStudentId});

  /// عند فتح الصفحة من صفحة الأرصدة مثلاً نُفعّل فلتر طالب مباشرة.
  final String? initialStudentId;

  @override
  State<TeacherLessonsPage> createState() => _TeacherLessonsPageState();
}

class _TeacherLessonsPageState extends State<TeacherLessonsPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedStudentId;
  final Set<String> _selectedStatuses = <String>{};

  // 💳 فلتر الدفع: الكل | غير المدفوعة | منذ آخر دفعة
  String _paymentFilter = 'all'; // all | unpaid | sinceLast

  // ↕️ ترتيب الدروس حسب التاريخ (الأحدث أولاً افتراضياً)
  bool _sortAscending = false;

  late final AnimationController _animCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  Map<String, String> _students = {};

  /// معلومات الدفع لكل طالب: إجمالي المدفوع وآخر تاريخ دفعة
  Map<String, _StudentPayInfo> _payInfo = {};

  /// مُعرّفات الدروس المنتهية التي غطّاها رصيد الطالب المدفوع (الأقدم أولاً)
  Set<String> _paidLessonIds = <String>{};

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
    _selectedStudentId = widget.initialStudentId;
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  // ===== filters area =====
  Widget _filtersArea(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: _SearchBox(
              controller: _searchCtrl,
              hintText: "ابحث بالاسم أو الملاحظة أو سبب الإلغاء…",
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          Badge(
            isLabelVisible: _paymentFilter != 'all',
            smallSize: 8,
            child: IconButton(
              tooltip: "الفلترة",
              icon: const Icon(Icons.filter_list, color: Colors.indigo),
              onPressed: () => _openFilterSheet(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Filter sheet like payments page
  Future<void> _openFilterSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(builder: (context, setModal) {
            return SafeArea(
              child: DefaultTabController(
                length: 4,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
                    ),
                    const SizedBox(height: 12),
                    const TabBar(
                      isScrollable: true,
                      tabs: [
                        Tab(text: "👨‍🎓 الطلاب"),
                        Tab(text: "🔖 الحالة"),
                        Tab(text: "📅 التاريخ"),
                        Tab(text: "💳 الدفع"),
                      ],
                      labelColor: Colors.indigo,
                      indicatorColor: Colors.indigo,
                      unselectedLabelColor: Colors.black54,
                    ),
                    SizedBox(
                      height: 380,
                      child: TabBarView(
                        children: [
                          // ---------- طلاب ----------
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: _students.isEmpty
                                ? const Center(child: Text("لا يوجد طلاب"))
                                : ListView(
                              children: _students.entries.map((e) {
                                return RadioListTile<String?>(
                                  value: e.key,
                                  groupValue: _selectedStudentId,
                                  onChanged: (val) {
                                    setModal(() {
                                      _selectedStudentId = val;
                                    });
                                  },
                                  title: Text(e.value),
                                );
                              }).toList()
                                ..insert(
                                  0,
                                  RadioListTile<String?>(
                                    value: null,
                                    groupValue: _selectedStudentId,
                                    onChanged: (val) {
                                      setModal(() {
                                        _selectedStudentId = val;
                                      });
                                    },
                                    title: const Text("كل الطلاب"),
                                  ),
                                ),
                            ),
                          ),

                          // ---------- الحالة ----------
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: ListView(
                              children: [
                                _statusCheckboxTile("pending", "بانتظار الموافقة", setModal),
                                _statusCheckboxTile("scheduled", "مجدولة", setModal),
                                _statusCheckboxTile("started", "جارية", setModal),
                                _statusCheckboxTile("ended", "منتهية", setModal),
                                _statusCheckboxTile("canceled", "ملغاة", setModal),
                              ],
                            ),
                          ),

                          // ---------- التاريخ ----------
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: ListView(
                              children: [
                                RadioListTile<String?>(
                                  value: null,
                                  groupValue:
                                  (_startDate == null && _endDate == null) ? null : "range",
                                  onChanged: (v) {
                                    setModal(() {
                                      _startDate = null;
                                      _endDate = null;
                                    });
                                  },
                                  title: const Text("كل الفترات"),
                                ),
                                RadioListTile<String?>(
                                  value: "range",
                                  groupValue:
                                  (_startDate == null && _endDate == null) ? null : "range",
                                  onChanged: (v) async {
                                    final now = DateTime.now();
                                    final picked = await showDateRangePicker(
                                      context: context,
                                      firstDate: DateTime(now.year - 5),
                                      lastDate: DateTime(now.year + 2),
                                      locale: const Locale('ar'),
                                    );
                                    if (picked != null) {
                                      setModal(() {
                                        _startDate = picked.start;
                                        _endDate = picked.end;
                                      });
                                    }
                                  },
                                  title: Text(
                                    "مدة محددة${_startDate != null && _endDate != null ? " (${DateFormat('yyyy-MM-dd').format(_startDate!)} - ${DateFormat('yyyy-MM-dd').format(_endDate!)})" : ""}",
                                  ),
                                ),
                                const Divider(height: 24),
                                SwitchListTile(
                                  value: _sortAscending,
                                  onChanged: (v) {
                                    setModal(() {
                                      _sortAscending = v;
                                    });
                                  },
                                  title: const Text("الترتيب حسب التاريخ"),
                                  subtitle: Text(
                                    _sortAscending
                                        ? "الأقدم أولاً"
                                        : "الأحدث أولاً",
                                  ),
                                  secondary: const Icon(Icons.swap_vert,
                                      color: Colors.indigo),
                                ),
                              ],
                            ),
                          ),

                          // ---------- الدفع ----------
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: ListView(
                              children: [
                                _paymentRadio(
                                  value: 'all',
                                  label: "كل الدروس",
                                  subtitle: "عرض كل الدروس بدون فلترة الدفع",
                                  setModal: setModal,
                                ),
                                _paymentRadio(
                                  value: 'unpaid',
                                  label: "غير المدفوعة",
                                  subtitle:
                                      "الدروس المنتهية التي ما زال رصيدها على الطالب",
                                  setModal: setModal,
                                ),
                                _paymentRadio(
                                  value: 'sinceLast',
                                  label: "منذ آخر دفعة",
                                  subtitle:
                                      "الدروس المنتهية بعد آخر دفعة سجّلها الطالب",
                                  setModal: setModal,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {}); // تطبيق الفلاتر
                                Navigator.pop(context);
                              },
                              child: const Text("تطبيق الفلاتر"),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _startDate = null;
                                _endDate = null;
                                _selectedStudentId = null;
                                _selectedStatuses.clear();
                                _paymentFilter = 'all';
                                _sortAscending = false;
                                _searchCtrl.clear();
                              });
                              Navigator.pop(context);
                            },
                            child: const Text("مسح الكل"),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _paymentRadio({
    required String value,
    required String label,
    required String subtitle,
    required void Function(void Function()) setModal,
  }) {
    return RadioListTile<String>(
      value: value,
      groupValue: _paymentFilter,
      onChanged: (v) {
        setModal(() {
          _paymentFilter = v ?? 'all';
        });
      },
      title: Text(label),
      subtitle: Text(subtitle),
    );
  }

  Widget _statusCheckboxTile(String key, String label, void Function(void Function()) setModal) {
    final selected = _selectedStatuses.contains(key);
    return CheckboxListTile(
      value: selected,
      onChanged: (val) {
        setModal(() {
          if (val == true) {
            _selectedStatuses.add(key);
          } else {
            _selectedStatuses.remove(key);
          }
        });
      },
      title: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final teacherCode = auth.currentUser?.code ?? "";
    final dbRef = FirebaseDatabase.instance.ref("users/$teacherCode/schedule");
    final paymentsRef =
        FirebaseDatabase.instance.ref("users/$teacherCode/payments");
    final studentsRef = FirebaseDatabase.instance.ref("users/$teacherCode/students");

    return Scaffold(
      appBar: AppBar(
        title: const Hero(
          tag: 'lessonsTitle',
          child: Material(
            type: MaterialType.transparency,
            child: Text("📚 سجل الدروس"),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: _sortAscending
                ? "الترتيب: الأقدم أولاً"
                : "الترتيب: الأحدث أولاً",
            icon: Icon(
              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
            ),
            onPressed: () =>
                setState(() => _sortAscending = !_sortAscending),
          ),
          IconButton(
            tooltip: "إضافة درس منتهي",
            icon: const Icon(Icons.history_edu),
            onPressed: () async {
              final added = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                    builder: (_) => const TeacherAddEndedLessonPage()),
              );
              if (added == true && context.mounted) setState(() {});
            },
          ),
        ],
      ),
      floatingActionButton: _buildExportFab(context),
      body: FutureBuilder<DataSnapshot>(
        future: studentsRef.get(),
        builder: (context, studentsSnap) {
          if (studentsSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          _students = {};
          if (studentsSnap.hasData && studentsSnap.data!.value != null) {
            final raw = Map<String, dynamic>.from(studentsSnap.data!.value as Map);
            for (final e in raw.entries) {
              if (e.value is! Map) continue;
              final v = Map<String, dynamic>.from(e.value);
              _students[e.key] = (v['name'] ?? 'طالب').toString();
            }
          }

          return StreamBuilder<DatabaseEvent>(
            stream: paymentsRef.onValue,
            builder: (context, paymentsSnap) {
              _payInfo = _computePayInfo(paymentsSnap.data?.snapshot.value);

              return StreamBuilder<DatabaseEvent>(
                stream: dbRef.onValue,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
                    return Column(
                      children: [
                        _filtersArea(context),
                        const SizedBox(height: 8),
                        Expanded(child: _emptyState(context, "لا يوجد دروس بعد")),
                      ],
                    );
                  }

                  final data =
                  Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);

                  final allLessons = data.entries.map<Map<String, dynamic>>((entry) {
                    final lesson = Map<String, dynamic>.from(entry.value);
                    lesson['id'] = entry.key;
                    return lesson;
                  }).toList();

                  // ↕️ فرز الدروس حسب التاريخ
                  allLessons.sort((a, b) {
                    final da = _lessonDate(a) ?? DateTime(2000);
                    final db = _lessonDate(b) ?? DateTime(2000);
                    return _sortAscending
                        ? da.compareTo(db)
                        : db.compareTo(da);
                  });

                  // 💳 حساب الدروس المدفوعة/غير المدفوعة
                  _paidLessonIds = _computePaidLessonIds(allLessons);

                  final filtered = _applyFilters(allLessons);

                  if (filtered.isEmpty) {
                    return Column(
                      children: [
                        _filtersArea(context),
                        const SizedBox(height: 8),
                        Expanded(child: _emptyState(context, "لا توجد نتائج مطابقة")),
                      ],
                    );
                  }

                  final grouped = _groupLessonsByDate(filtered);

                  return Column(
                    children: [
                      _filtersArea(context),
                      const SizedBox(height: 8),
                      _summaryBar(filtered),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                          children: grouped.entries.map((group) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _dateHeader(group.key, group.value.length),
                                const SizedBox(height: 6),
                                ...group.value.map((lesson) {
                                  final studentId = (lesson['student'] ?? '').toString();
                                  final studentName = _students[studentId] ?? "طالب غير معروف";
                                  final amount = (lesson['amount'] ?? '0').toString();
                                  final status = (lesson['status'] ?? '').toString();

                                  return Card(
                                    margin: const EdgeInsets.symmetric(vertical: 6),
                                    child: ListTile(
                                      leading: _statusIcon(status),
                                      title: Text(studentName),
                                      trailing: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            "$amount ر.ق",
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold),
                                          ),
                                          if (status == 'ended')
                                            _paymentBadge(lesson),
                                        ],
                                      ),
                                      onTap: () async {
                                        HapticFeedback.selectionClick();
                                        final startTime = _formatTime(lesson['startTime']);
                                        final endTime = _formatTime(lesson['endTime']);
                                        final duration = _formatDuration(lesson['duration']);
                                        final date = (lesson['date'] ?? '').toString();
                                        await _showLessonSheet(context, studentName, date,
                                            startTime, endTime, duration, lesson);
                                      },
                                    ),
                                  );
                                }),
                                const SizedBox(height: 14),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // ===== ترويسة المجموعة (التاريخ) =====
  Widget _dateHeader(String label, int count) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.calendar_month_rounded, size: 18, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            "$count",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  // ===== شارة مدفوع / غير مدفوع =====
  Widget _paymentBadge(Map<String, dynamic> lesson) {
    final paid =
        _paidLessonIds.contains((lesson['id'] ?? '').toString());
    final color = paid ? AppTheme.success : AppTheme.danger;
    final label = paid ? "مدفوع" : "غير مدفوع";

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // ===== Export FAB =====
  Widget _buildExportFab(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack),
      child: FloatingActionButton(
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.picture_as_pdf),
        onPressed: () async {
          final auth = context.read<AuthProvider>();
          final teacherCode = auth.currentUser?.code ?? "";
          final dbRef = FirebaseDatabase.instance.ref("users/$teacherCode/schedule");
          final event = await dbRef.once();
          if (event.snapshot.value == null) return;

          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          final lessons = data.entries.map<Map<String, dynamic>>((entry) {
            final lesson = Map<String, dynamic>.from(entry.value);
            lesson['id'] = entry.key;
            return lesson;
          }).toList();

          final filtered = _applyFilters(lessons);

          final service = PdfExportService(
            students: _students,
            selectedStudentId: _selectedStudentId,
          );
          await service.exportCurrentFilteredPdf(context, filtered);
        },
      ),
    );
  }

  // ===== Helper Widgets =====
  Widget _statusIcon(String status) {
    switch (status) {
      case "scheduled":
        return const Icon(Icons.event, color: Colors.blueAccent);
      case "started":
        return const Icon(Icons.play_arrow, color: Colors.orange);
      case "ended":
        return const Icon(Icons.check_circle, color: Colors.green);
      case "canceled":
        return const Icon(Icons.cancel, color: Colors.red);
      case "pending":
        return const Icon(Icons.hourglass_empty, color: Colors.purple);
      default:
        return const Icon(Icons.help, color: Colors.grey);
    }
  }

  /// تاريخ الدرس: وقت البداية ثم النهاية ثم حقل التاريخ.
  DateTime? _lessonDate(Map<String, dynamic> lesson) {
    for (final key in const ['startTime', 'endTime', 'date']) {
      final v = lesson[key];
      if (v == null || v.toString().isEmpty) continue;
      final d = DateTime.tryParse(v.toString());
      if (d != null) return d;
    }
    return null;
  }

  /// الحساب المالي لكل طالب من سجل الدفعات.
  Map<String, _StudentPayInfo> _computePayInfo(Object? raw) {
    final result = <String, _StudentPayInfo>{};
    if (raw is! Map) return result;

    raw.forEach((studentCode, payments) {
      final info = _StudentPayInfo();
      if (payments is Map) {
        payments.forEach((_, payment) {
          if (payment is! Map) return;
          final payer = (payment['payer'] ?? 'student').toString();
          final amount = double.tryParse("${payment['amount']}") ?? 0.0;
          final date = DateTime.tryParse("${payment['date'] ?? ''}");

          if (payer == 'teacher') {
            info.returned += amount;
          } else {
            info.paid += amount;
          }
          if (date != null &&
              (info.lastPayment == null || date.isAfter(info.lastPayment!))) {
            info.lastPayment = date;
          }
        });
      }
      result[studentCode.toString()] = info;
    });
    return result;
  }

  /// توزيع صافي المدفوعات على الدروس المنتهية من الأقدم للأحدث.
  /// الدرس الذي تغطيه المدفوعات بالكامل = "مدفوع".
  Set<String> _computePaidLessonIds(List<Map<String, dynamic>> lessons) {
    final byStudent = <String, List<Map<String, dynamic>>>{};
    for (final lesson in lessons) {
      if ((lesson['status'] ?? '') != 'ended') continue;
      byStudent
          .putIfAbsent((lesson['student'] ?? '').toString(), () => [])
          .add(lesson);
    }

    final paid = <String>{};
    byStudent.forEach((studentCode, list) {
      list.sort((a, b) {
        final da = _lessonDate(a) ?? DateTime(1900);
        final db = _lessonDate(b) ?? DateTime(1900);
        return da.compareTo(db);
      });

      var remaining = _payInfo[studentCode]?.net ?? 0.0;
      for (final lesson in list) {
        final amount = double.tryParse("${lesson['amount']}") ?? 0.0;
        if (remaining >= amount) {
          paid.add((lesson['id'] ?? '').toString());
          remaining -= amount;
        } else {
          // دفعة جزئية: تُستهلك بالكامل ولا يُعدّ الدرس مدفوعاً بالكامل
          remaining = 0.0;
        }
      }
    });
    return paid;
  }

  Map<String, List<Map<String, dynamic>>> _groupLessonsByDate(
      List<Map<String, dynamic>> lessons) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final yesterday = today.subtract(const Duration(days: 1));

    // ✅ تجميع حسب التاريخ الحقيقي مع الحفاظ على ترتيب الفرز المطلوب
    final Map<String, List<Map<String, dynamic>>> groups = {};

    for (final lesson in lessons) {
      final date = _lessonDate(lesson);
      final String label;

      if (date == null) {
        label = "بدون تاريخ";
      } else {
        final day = DateTime(date.year, date.month, date.day);
        final prefix = day == today
            ? "اليوم • "
            : day == tomorrow
                ? "غداً • "
                : day == yesterday
                    ? "أمس • "
                    : "";
        label =
            "$prefix${_weekdayNames[day.weekday - 1]} ${DateFormat('yyyy-MM-dd').format(day)}";
      }

      groups.putIfAbsent(label, () => []).add(lesson);
    }

    return groups;
  }

  Future<void> _showLessonSheet(
      BuildContext context,
      String studentName,
      String date,
      String startTime,
      String endTime,
      String duration,
      Map<String, dynamic> lesson,
      ) async {
    final amount = (lesson['amount'] ?? '').toString();
    final status = (lesson['status'] ?? '').toString();
    final note = (lesson['note'] ?? '').toString();
    final cancelReason = (lesson['cancelReason'] ?? '').toString();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              top: 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(studentName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  _tile("التاريخ", date, Icons.event),
                  _tile("الوقت", "$startTime ← $endTime", Icons.schedule),
                  _tile("المدة", duration, Icons.timelapse),
                  _tile("المبلغ", "$amount ر.ق", Icons.payments),
                  _tile("الحالة", _statusLabel(status), Icons.info),
                  if (status == 'ended')
                    _tile(
                      "الدفع",
                      _paidLessonIds.contains((lesson['id'] ?? '').toString())
                          ? "✅ مدفوع"
                          : "⚠️ غير مدفوع",
                      Icons.account_balance_wallet_outlined,
                    ),
                  if (note.isNotEmpty) _tileWithTruncate("ملاحظة", note, Icons.note),
                  if (cancelReason.isNotEmpty)
                    _tileWithTruncate("سبب الإلغاء", cancelReason, Icons.cancel),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _tileWithTruncate(String title, String value, IconData icon) {
    const int maxChars = 60;
    final truncated = value.length > maxChars ? "${value.substring(0, maxChars)}..." : value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.indigo),
      title: Text(title, textAlign: TextAlign.right),
      subtitle: Text(truncated, textAlign: TextAlign.right),
      trailing: IconButton(
        icon: const Icon(Icons.info_outline, color: Colors.indigo),
        onPressed: () {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(child: Text(value)),
              actions: [
                TextButton(
                  child: const Text("إغلاق"),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
          );
        },
      ),
    );
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
        return "⌛ بانتظار الموافقة";
      default:
        return "غير معروف";
    }
  }

  Widget _tile(String title, String value, IconData icon) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.indigo),
      title: Text(title, textAlign: TextAlign.right),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> all) {
    final q = _searchCtrl.text.trim().toLowerCase();

    return all.where((lesson) {
      final status = (lesson['status'] ?? '').toString();
      final studentId = (lesson['student'] ?? '').toString();
      final studentName = (_students[studentId] ?? '').toLowerCase();
      final note = (lesson['note'] ?? '').toString().toLowerCase();
      final cancelReason = (lesson['cancelReason'] ?? '').toString().toLowerCase();

      if (_selectedStatuses.isNotEmpty && !_selectedStatuses.contains(status)) return false;
      if (_selectedStudentId != null && _selectedStudentId!.isNotEmpty && studentId != _selectedStudentId) {
        return false;
      }

      DateTime? itemDate;
      if (lesson['endTime'] != null && (lesson['endTime'] ?? '').toString().isNotEmpty) {
        itemDate = DateTime.tryParse(lesson['endTime'].toString());
      }
      itemDate ??= DateTime.tryParse((lesson['date'] ?? '').toString());

      if (_startDate != null && itemDate != null && itemDate.isBefore(_startDate!)) return false;
      if (_endDate != null && itemDate != null && itemDate.isAfter(_endDate!.add(const Duration(days: 1)).subtract(const Duration(seconds: 1)))) {
        return false;
      }

      // 💳 فلتر الدفع — يعمل على الدروس المنتهية فقط
      if (_paymentFilter != 'all') {
        if (status != 'ended') return false;

        if (_paymentFilter == 'unpaid') {
          if (_paidLessonIds.contains((lesson['id'] ?? '').toString())) {
            return false;
          }
        } else if (_paymentFilter == 'sinceLast') {
          final last = _payInfo[studentId]?.lastPayment;
          if (last != null) {
            final lessonDate = _lessonDate(lesson);
            if (lessonDate == null || !lessonDate.isAfter(last)) {
              return false;
            }
          }
          // إن لم يدفع الطالب إطلاقاً → كل دروسه المنتهية "منذ آخر دفعة" (لا يوجد دفعات)
        }
      }

      if (q.isNotEmpty) {
        if (!studentName.contains(q) && !note.contains(q) && !cancelReason.contains(q)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Widget _summaryBar(List<Map<String, dynamic>> lessons) {
    final totalAmount = lessons.fold<num>(
        0, (prev, e) => prev + (num.tryParse(e['amount']?.toString() ?? '0') ?? 0));

    double unpaidAmount = 0;
    int unpaidCount = 0;
    for (final lesson in lessons) {
      if ((lesson['status'] ?? '') == 'ended' &&
          !_paidLessonIds.contains((lesson['id'] ?? '').toString())) {
        unpaidAmount += double.tryParse("${lesson['amount']}") ?? 0.0;
        unpaidCount++;
      }
    }

    final fmt = NumberFormat('#,###');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          _summaryChip(
            icon: Icons.format_list_numbered,
            label: "عدد الدروس: ${lessons.length}",
            color: Theme.of(context).colorScheme.primary,
          ),
          _summaryChip(
            icon: Icons.payments_outlined,
            label: "إجمالي: ${fmt.format(totalAmount.toInt())} ر.ق",
            color: Colors.teal.shade700,
          ),
          if (unpaidCount > 0)
            _summaryChip(
              icon: Icons.money_off_outlined,
              label:
                  "غير المدفوع: ${fmt.format(unpaidAmount.toInt())} ر.ق ($unpaidCount)",
              color: AppTheme.danger,
            ),
        ],
      ),
    );
  }

  Widget _summaryChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context, String text) {
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
}

/// معلومات الدفع الخاصة بطالب واحد.
class _StudentPayInfo {
  double paid = 0; // دفعات من الطالب
  double returned = 0; // مبالغ أعادها المعلم
  DateTime? lastPayment; // آخر تاريخ دفعة مسجلة (من أي جهة)

  /// صافي المدفوع (ما دفعه الطالب ناقص ما أعاده المعلم)
  double get net => paid - returned;
}

// ====== SearchBox with stable focus ======
class _SearchBox extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;

  const _SearchBox({
    required this.controller,
    required this.hintText,
    this.onChanged,
  });

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shadowColor: Colors.indigo.withOpacity(0.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        textAlign: TextAlign.right,
        onChanged: widget.onChanged,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.search,
        enableSuggestions: true,
        autocorrect: true,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.search),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
