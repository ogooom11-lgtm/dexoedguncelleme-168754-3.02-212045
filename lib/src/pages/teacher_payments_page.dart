import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../providers/auth_provider.dart';
import '../services/pdf_export_service_payments.dart';
import '../services/permission_guard.dart';

class TeacherPaymentsPage extends StatefulWidget {
  const TeacherPaymentsPage({super.key});

  @override
  State<TeacherPaymentsPage> createState() => _TeacherPaymentsPageState();
}

class _TeacherPaymentsPageState extends State<TeacherPaymentsPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();

  // فلترة
  List<String> _selectedStudents = [];
  List<String> _selectedMethods = [];
  String? _selectedDateFilter; // "today" | "yesterday" | "range" | null
  DateTime? _startDate;
  DateTime? _endDate;

  late final AnimationController _animCtrl =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  Map<String, String> _students = {};
  late DatabaseReference dbRef;

  @override
  void initState() {
    super.initState();
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final teacherCode = auth.currentUser?.code ?? "";
    dbRef = FirebaseDatabase.instance.ref("users/$teacherCode/payments");
    final studentsRef = FirebaseDatabase.instance.ref("users/$teacherCode/students");

    return Scaffold(
      appBar: AppBar(
        title: const Text("💰 سجل المدفوعات"),
        centerTitle: true,
        backgroundColor: Colors.indigo.shade600,
      ),
      floatingActionButton: _buildExportFab(context),
      body: FutureBuilder<DataSnapshot>(
        future: studentsRef.get(),
        builder: (context, studentsSnap) {
          if (studentsSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // جلب قائمة الطلاب
          _students = {};
          if (studentsSnap.hasData && studentsSnap.data!.value != null) {
            final raw = Map<String, dynamic>.from(studentsSnap.data!.value as Map);
            for (final e in raw.entries) {
              final v = Map<String, dynamic>.from(e.value);
              _students[e.key] = (v['name'] ?? 'طالب').toString();
            }
          }

          return StreamBuilder<DatabaseEvent>(
            stream: dbRef.onValue,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                return Column(
                  children: [
                    _filtersArea(context),
                    Expanded(child: _emptyState(context, "لا يوجد مدفوعات بعد")),
                  ],
                );
              }

              // تحويل البيانات إلى لائحة دفعات مفردة
              final allData = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
              final allPayments = <Map<String, dynamic>>[];

              allData.forEach((studentCode, payments) {
                final pm = Map<String, dynamic>.from(payments);
                pm.forEach((id, p) {
                  final rec = Map<String, dynamic>.from(p);
                  rec['studentCode'] = studentCode;
                  rec['id'] = id;
                  allPayments.add(rec);
                });
              });

              // ترتيب تنازلي حسب التاريخ/الوقت (الأحدث أول)
              allPayments.sort((a, b) {
                final da = DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(2000);
                final db = DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(2000);
                return db.compareTo(da);
              });

              final filtered = _applyFilters(allPayments);

              if (filtered.isEmpty) {
                return Column(
                  children: [
                    _filtersArea(context),
                    Expanded(child: _emptyState(context, "لا توجد نتائج مطابقة")),
                  ],
                );
              }

              // تقسيم حسب اليوم/أمس/بقية الأيام
              final today = DateTime.now();
              final yesterday = today.subtract(const Duration(days: 1));
              final todayList = <Map<String, dynamic>>[];
              final yesterdayList = <Map<String, dynamic>>[];
              final others = <DateTime, List<Map<String, dynamic>>>{};

              for (final p in filtered) {
                final date = DateTime.tryParse(p['date']?.toString() ?? "") ?? today;
                final dOnly = DateTime(date.year, date.month, date.day);
                if (dOnly == DateTime(today.year, today.month, today.day)) {
                  todayList.add(p);
                } else if (dOnly ==
                    DateTime(yesterday.year, yesterday.month, yesterday.day)) {
                  yesterdayList.add(p);
                } else {
                  others.putIfAbsent(dOnly, () => []).add(p);
                }
              }

              final sortedOthers = others.keys.toList()..sort((a, b) => b.compareTo(a));

              return Column(
                children: [
                  _filtersArea(context),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        if (todayList.isNotEmpty) ...[
                          _sectionTitle("اليوم"),
                          ...todayList.map((p) => _paymentTile(p)).toList(),
                        ],
                        if (yesterdayList.isNotEmpty) ...[
                          _sectionTitle("أمس"),
                          ...yesterdayList.map((p) => _paymentTile(p)).toList(),
                        ],
                        for (final d in sortedOthers) ...[
                          _sectionTitle(DateFormat("yyyy-MM-dd").format(d)),
                          ...others[d]!.map((p) => _paymentTile(p)).toList(),
                        ]
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
        textAlign: TextAlign.right,
      ),
    );
  }

  Widget _paymentTile(Map<String, dynamic> p) {
    final amount = num.tryParse(p['amount'].toString()) ?? 0;
    final payer = (p['payer'] ?? "student").toString();
    final studentName = _students[p['studentCode']] ?? "طالب";

    return _animatedCard(
      index: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          HapticFeedback.selectionClick();
          final date = DateTime.tryParse(p['date']?.toString() ?? "") ?? DateTime.now();
          final formattedDate = DateFormat("yyyy-MM-dd • HH:mm").format(date);
          final method = (p['method'] ?? "غير محدد").toString();
          await _showPaymentSheet(context, studentName, formattedDate, amount, payer, method, p);
        },
        child: Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            // العرض المطلوب: فقط الاسم + المبلغ
            title: Text(studentName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                textAlign: TextAlign.right),
            trailing: _amountChip(amount, payer),
          ),
        ),
      ),
    );
  }

  /// تفاصيل الدفع — استخدمت isScrollControlled + SafeArea + SingleChildScrollView
  /// بحيث زر الحذف لا يسبب overflow و يمكن سحب الSheet.
  Future<void> _showPaymentSheet(BuildContext context, String student, String date,
      num amount, String payer, String method, Map<String, dynamic> payment) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.48,
            minChildSize: 0.28,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: Colors.indigo.shade200,
                            child: const Icon(Icons.payments, color: Colors.indigo),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(student,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                textAlign: TextAlign.right),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _tile("التاريخ", date, Icons.event),
                      _tile("المبلغ", "$amount ر.ق", Icons.attach_money),
                      _tile("الدافع", payer == 'teacher' ? "المعلم" : "الطالب", Icons.person),
                      _tile("طريقة الدفع", method, Icons.credit_card),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () async {
                          // تأكيد الحذف ثم إغلاق الـ BottomSheet
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text("⚠️ تأكيد الحذف"),
                              content: const Text("هل تريد حذف هذا الدفع؟"),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("إلغاء")),
                                ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("حذف")),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await _deletePayment(payment);
                            if (mounted) {
                              Navigator.of(context).pop(); // close details sheet
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        icon: const Icon(Icons.delete),
                        label: const Text("حذف الدفع"),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text("إغلاق"),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// حذف دفعة (يستخدمه أيضاً زر الحذف من التفاصيل)
  Future<void> _deletePayment(Map<String, dynamic> p) async {
    if (!await PermissionGuard.check(context, TeacherPermission.recordPayments)) return;
    if (!mounted) return;
    try {
      await dbRef.child(p['studentCode']).child(p['id']).remove();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم حذف الدفع")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("حدث خطأ أثناء الحذف")));
      }
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

  /* ================= الفلاتر UI (زر الفلترة يفتح BottomSheet مع تبويبات) ================= */
  Widget _filtersArea(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: _SearchBox(
              controller: _searchCtrl,
              hintText: "ابحث باسم الطالب…",
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterSheet(context),
          )
        ],
      ),
    );
  }

  Future<void> _showFilterSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (context, setModal) {
              return SafeArea(
                child: DefaultTabController(
                  length: 3,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
                      ),
                      const SizedBox(height: 12),
                      const TabBar(
                        tabs: [
                          Tab(text: "👨‍🎓 الطلاب"),
                          Tab(text: "💳 طرق الدفع"),
                          Tab(text: "📅 التاريخ"),
                        ],
                        labelColor: Colors.indigo,
                        indicatorColor: Colors.indigo,
                        unselectedLabelColor: Colors.black54,
                      ),
                      SizedBox(
                        height: 360,
                        child: TabBarView(
                          children: [
                            // تبويب الطلاب: عرض قائمة الطلاب كـ CheckboxListTile
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: _students.isEmpty
                                  ? const Center(child: Text("لا يوجد طلاب"))
                                  : ListView(
                                children: _students.entries.map((e) {
                                  final selected = _selectedStudents.contains(e.key);
                                  return CheckboxListTile(
                                    value: selected,
                                    onChanged: (val) {
                                      setModal(() {
                                        if (val == true) {
                                          if (!_selectedStudents.contains(e.key)) _selectedStudents.add(e.key);
                                        } else {
                                          _selectedStudents.remove(e.key);
                                        }
                                      });
                                    },
                                    title: Text(e.value),
                                  );
                                }).toList(),
                              ),
                            ),

                            // تبويب طرق الدفع
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: ListView(
                                children: ["كاش", "بنك"].map((m) {
                                  final selected = _selectedMethods.contains(m);
                                  return CheckboxListTile(
                                    value: selected,
                                    onChanged: (val) {
                                      setModal(() {
                                        if (val == true) {
                                          if (!_selectedMethods.contains(m)) _selectedMethods.add(m);
                                        } else {
                                          _selectedMethods.remove(m);
                                        }
                                      });
                                    },
                                    title: Text(m),
                                  );
                                }).toList(),
                              ),
                            ),

                            // تبويب التاريخ (اليوم / أمس / المدة)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: ListView(
                                children: [
                                  RadioListTile<String>(
                                    value: "today",
                                    groupValue: _selectedDateFilter,
                                    onChanged: (val) {
                                      setModal(() {
                                        _selectedDateFilter = val;
                                        _startDate = null;
                                        _endDate = null;
                                      });
                                    },
                                    title: const Text("اليوم"),
                                  ),
                                  RadioListTile<String>(
                                    value: "yesterday",
                                    groupValue: _selectedDateFilter,
                                    onChanged: (val) {
                                      setModal(() {
                                        _selectedDateFilter = val;
                                        _startDate = null;
                                        _endDate = null;
                                      });
                                    },
                                    title: const Text("أمس"),
                                  ),
                                  RadioListTile<String>(
                                    value: "range",
                                    groupValue: _selectedDateFilter,
                                    onChanged: (val) async {
                                      // اختر المدة
                                      final range = await showDateRangePicker(
                                        context: context,
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2100),
                                      );
                                      if (range != null) {
                                        setModal(() {
                                          _selectedDateFilter = "range";
                                          _startDate = range.start;
                                          _endDate = range.end;
                                        });
                                      } else {
                                        // لو ألغى المستخدم، لا نغير المجموعة إلا لو خلاها
                                        setModal(() {
                                          // ليس ضروريًا تغيير
                                        });
                                      }
                                    },
                                    title: Text(
                                      "مدة محددة${_startDate != null && _endDate != null ? " (${DateFormat('yyyy-MM-dd').format(_startDate!)} - ${DateFormat('yyyy-MM-dd').format(_endDate!)})" : ""}",
                                    ),
                                  ),
                                  ListTile(
                                    title: const Text("مسح فلتر التاريخ"),
                                    trailing: TextButton(
                                      onPressed: () {
                                        setModal(() {
                                          _selectedDateFilter = null;
                                          _startDate = null;
                                          _endDate = null;
                                        });
                                      },
                                      child: const Text("مسح"),
                                    ),
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
                                  setState(() {}); // تطبيق الفلاتر و إعادة بناء
                                  Navigator.pop(context);
                                },
                                child: const Text("تطبيق الفلاتر"),
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  // مسح كل الفلاتر
                                  _selectedStudents.clear();
                                  _selectedMethods.clear();
                                  _selectedDateFilter = null;
                                  _startDate = null;
                                  _endDate = null;
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
            },
          ),
        );
      },
    );
  }

  /* ================= تطبيق فلترة البيانات ================= */
  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> all) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));

    return all.where((p) {
      final studentName = _students[p['studentCode']]?.toLowerCase() ?? "";
      final date = DateTime.tryParse(p['date']?.toString() ?? "");
      final method = (p['method'] ?? "").toString();

      // بحث نصي
      if (q.isNotEmpty && !studentName.contains(q)) return false;

      // فلترة بالطلاب (لو اخترت أي طلاب)
      if (_selectedStudents.isNotEmpty && !_selectedStudents.contains(p['studentCode'])) {
        return false;
      }

      // فلترة طرق الدفع
      if (_selectedMethods.isNotEmpty && !_selectedMethods.contains(method)) {
        return false;
      }

      // فلترة التاريخ حسب الاختيار
      if (_selectedDateFilter == "today") {
        if (date == null) return false;
        final dOnly = DateTime(date.year, date.month, date.day);
        if (dOnly != DateTime(today.year, today.month, today.day)) return false;
      } else if (_selectedDateFilter == "yesterday") {
        if (date == null) return false;
        final dOnly = DateTime(date.year, date.month, date.day);
        if (dOnly != DateTime(yesterday.year, yesterday.month, yesterday.day)) return false;
      } else if (_selectedDateFilter == "range") {
        if (_startDate != null && (date == null || date.isBefore(_startDate!))) return false;
        if (_endDate != null && (date == null || date.isAfter(_endDate!))) return false;
      }

      return true;
    }).toList();
  }

  /* ================= زر تصدير PDF ================= */
  Widget _buildExportFab(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack),
      child: FloatingActionButton.extended(
        heroTag: 'exportFab',
        backgroundColor: Colors.indigo.shade600,
        icon: const Icon(Icons.picture_as_pdf),
        label: const Text("تصدير PDF"),
        onPressed: () async {
          HapticFeedback.mediumImpact();
          await _exportCurrentFilteredPdf(context);
        },
      ),
    );
  }

  Future<void> _exportCurrentFilteredPdf(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final teacherCode = auth.currentUser?.code ?? "";
    final dbRefLocal = FirebaseDatabase.instance.ref("users/$teacherCode/payments");
    final snapshot = await dbRefLocal.once();

    if (snapshot.snapshot.value == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("لا توجد بيانات لتصديرها")));
      }
      return;
    }

    final allData = Map<String, dynamic>.from(snapshot.snapshot.value as Map);
    final payments = <Map<String, dynamic>>[];

    allData.forEach((studentCode, studentPayments) {
      final sp = Map<String, dynamic>.from(studentPayments);
      sp.forEach((id, payment) {
        final p = Map<String, dynamic>.from(payment);
        p['studentCode'] = studentCode;
        p['id'] = id;
        payments.add(p);
      });
    });

    payments.sort((a, b) {
      final da = DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(2000);
      final db = DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(2000);
      return db.compareTo(da);
    });

    final filtered = _applyFilters(payments);

    if (!await PermissionGuard.check(context, TeacherPermission.exportPdf)) return;
    if (!mounted) return;
    final pdfService = PdfExportServicePayments(
      students: _students,
      selectedStudentId: null,
    );

    await pdfService.exportPaymentsPdf(
      filtered,
      onSuccess: (msg) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      },
      onError: (msg) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
      },
    );
  }

  /* ================= مساعدة للعرض ================= */
  Widget _amountChip(num amount, String payer) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: payer == 'teacher' ? Colors.red.shade100 : Colors.green.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        "$amount ر.ق",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: payer == 'teacher' ? Colors.red.shade700 : Colors.green.shade700,
        ),
      ),
    );
  }

  Widget _animatedCard({required int index, required Widget child}) {
    final anim = CurvedAnimation(
      parent: _animCtrl,
      curve: Interval((index * 0.05).clamp(0, 1).toDouble(), 1, curve: Curves.easeOutBack),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.05), end: Offset.zero).animate(anim),
        child: child,
      ),
    );
  }

  Widget _emptyState(BuildContext context, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.payments, size: 64, color: Colors.indigo.shade300),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}

/* ============= Widgets مساعدة ============= */

class _SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  const _SearchBox({
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: hintText,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey.shade100,
      ),
      onChanged: onChanged,
    );
  }
}
