import 'dart:math';
import 'dart:ui' as ui;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class AccountDetailsPage extends StatefulWidget {
  final Map<String, dynamic> account;
  const AccountDetailsPage({super.key, required this.account});

  @override
  State<AccountDetailsPage> createState() => _AccountDetailsPageState();
}

class _AccountDetailsPageState extends State<AccountDetailsPage> {
  final Set<String> _selectedLessons = {};
  final _dateFormat = DateFormat('yyyy-MM-dd');
  final _timeFormat = DateFormat('HH:mm');

  String get _accountId => widget.account['id'].toString();

  Future<void> _editAccountField(
    String field,
    String label,
    String currentValue,
  ) async {
    final controller = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تعديل $label'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || result == currentValue) return;
    await FirebaseDatabase.instance
        .ref('users/$_accountId')
        .update({field: result});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم تحديث $label')),
    );
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الحساب'),
        content: Text('سيتم حذف حساب ${widget.account["name"]}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await FirebaseDatabase.instance.ref('users/$_accountId').remove();
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف الحساب')),
    );
  }

  Future<String> _generateStudentCode(String teacherCode) async {
    final random = Random();
    while (true) {
      final code = List.generate(8, (_) => random.nextInt(10)).join();
      final nested = await FirebaseDatabase.instance
          .ref('users/$teacherCode/students/$code')
          .get();
      final root = await FirebaseDatabase.instance.ref('users/$code').get();
      if (!nested.exists && !root.exists) return code;
    }
  }

  Future<void> _showAddStudentSheet(String teacherCode) async {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    String gender = 'male';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Directionality(
              textDirection: ui.TextDirection.rtl,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'إضافة طالب للمعلم',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'اسم الطالب',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: codeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'الكود',
                        hintText: 'اتركه فارغاً للتوليد',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: rateCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*$')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'سعر الساعة',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<String>(
                      selected: {gender},
                      onSelectionChanged: (v) =>
                          setModal(() => gender = v.first),
                      segments: const [
                        ButtonSegment(value: 'male', label: Text('ذكر')),
                        ButtonSegment(value: 'female', label: Text('أنثى')),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        final code = codeCtrl.text.trim().isEmpty
                            ? await _generateStudentCode(teacherCode)
                            : codeCtrl.text.trim();
                        final rate = double.tryParse(rateCtrl.text.trim()) ?? 0;
                        await FirebaseDatabase.instance
                            .ref('users/$teacherCode/students/$code')
                            .set({
                          'name': name,
                          'hourlyRate': rate,
                          'gender': gender,
                          'createdAt': DateTime.now().toIso8601String(),
                        });
                        await FirebaseDatabase.instance.ref('users/$code').set({
                          'name': name,
                          'role': 'student',
                          'teacher': teacherCode,
                          'createdAt': DateTime.now().toIso8601String(),
                        });
                        if (context.mounted) Navigator.pop(context);
                      },
                      icon: const Icon(Icons.person_add),
                      label: const Text('إضافة الطالب'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showEditStudentSheet(
    String teacherCode,
    String studentCode,
    Map<String, dynamic> student,
  ) async {
    final nameCtrl =
        TextEditingController(text: (student['name'] ?? '').toString());
    final rateCtrl =
        TextEditingController(text: (student['hourlyRate'] ?? '').toString());
    String gender = (student['gender'] ?? 'male').toString();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setModal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'تعديل الطالب',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'الاسم',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: rateCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'سعر الساعة',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    selected: {gender},
                    onSelectionChanged: (v) => setModal(() => gender = v.first),
                    segments: const [
                      ButtonSegment(value: 'male', label: Text('ذكر')),
                      ButtonSegment(value: 'female', label: Text('أنثى')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      final rate = double.tryParse(rateCtrl.text.trim()) ?? 0;
                      await FirebaseDatabase.instance
                          .ref('users/$teacherCode/students/$studentCode')
                          .update({
                        'name': name,
                        'hourlyRate': rate,
                        'gender': gender,
                      });
                      await FirebaseDatabase.instance
                          .ref('users/$studentCode')
                          .update({'name': name});
                      if (context.mounted) Navigator.pop(context);
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('حفظ'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _deleteStudent(String teacherCode, String studentCode) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الطالب'),
        content: const Text('سيتم حذف الطالب ودفعاته من حساب هذا المعلم.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final base = FirebaseDatabase.instance.ref('users/$teacherCode');
    await base.child('students/$studentCode').remove();
    await base.child('payments/$studentCode').remove();
    final rootSnap =
        await FirebaseDatabase.instance.ref('users/$studentCode').get();
    if (rootSnap.exists && rootSnap.value is Map) {
      final root = Map<String, dynamic>.from(rootSnap.value as Map);
      if ((root['teacher'] ?? '').toString() == teacherCode) {
        await FirebaseDatabase.instance.ref('users/$studentCode').remove();
      }
    }
  }

  Future<Map<String, Map<String, dynamic>>> _loadStudents(
      String teacherCode) async {
    final snap = await FirebaseDatabase.instance
        .ref('users/$teacherCode/students')
        .get();
    final students = <String, Map<String, dynamic>>{};
    if (snap.exists && snap.value is Map) {
      final raw = Map<String, dynamic>.from(snap.value as Map);
      for (final entry in raw.entries) {
        if (entry.value is Map) {
          students[entry.key] = Map<String, dynamic>.from(entry.value as Map);
        }
      }
    }
    return students;
  }

  double _amountFor(DateTime start, DateTime end, double hourlyRate) {
    final minutes = end.difference(start).inMinutes;
    if (minutes <= 0 || hourlyRate <= 0) return 0;
    return double.parse(((minutes / 60) * hourlyRate).toStringAsFixed(2));
  }

  Future<void> _showAddEndedBatchSheet(
    String teacherCode,
    Map<String, Map<String, dynamic>> students,
  ) async {
    if (students.isEmpty) return;
    String studentId = students.keys.first;
    final drafts = <_AdminLessonDraft>[
      _AdminLessonDraft(date: DateTime.now()),
    ];

    void syncAmounts() {
      final rate = double.tryParse(
            students[studentId]?['hourlyRate']?.toString() ?? '0',
          ) ??
          0;
      for (final draft in drafts) {
        if (!draft.amountEdited) {
          draft.amountController.text =
              _amountFor(draft.startDateTime, draft.endDateTime, rate)
                  .toStringAsFixed(0);
        }
      }
    }

    syncAmounts();
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModal) {
            syncAmounts();
            return Directionality(
              textDirection: ui.TextDirection.rtl,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'إضافة دروس منتهية',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: studentId,
                          decoration: const InputDecoration(
                            labelText: 'الطالب',
                            border: OutlineInputBorder(),
                          ),
                          items: students.entries.map((entry) {
                            return DropdownMenuItem(
                              value: entry.key,
                              child: Text((entry.value['name'] ?? entry.key)
                                  .toString()),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setModal(() {
                              studentId = value;
                              for (final draft in drafts) {
                                draft.amountEdited = false;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        ...drafts.asMap().entries.map((entry) {
                          final index = entry.key;
                          final draft = entry.value;
                          return _draftEditor(
                            context,
                            title: 'درس ${index + 1}',
                            draft: draft,
                            rate: double.tryParse(
                                  students[studentId]?['hourlyRate']
                                          ?.toString() ??
                                      '0',
                                ) ??
                                0,
                            onChanged: () => setModal(() {}),
                            onDelete: drafts.length == 1
                                ? null
                                : () => setModal(() => drafts.removeAt(index)),
                          );
                        }),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () {
                              setModal(() {
                                drafts.add(
                                    _AdminLessonDraft(date: DateTime.now()));
                              });
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('إضافة درس آخر'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () async {
                            for (final draft in drafts) {
                              final start = draft.startDateTime;
                              final end = draft.endDateTime;
                              if (!end.isAfter(start)) continue;
                              final ref = FirebaseDatabase.instance
                                  .ref('users/$teacherCode/schedule')
                                  .push();
                              await ref.set({
                                'teacher': teacherCode,
                                'student': studentId,
                                'date': _dateFormat.format(start),
                                'startTime': start.toIso8601String(),
                                'endTime': end.toIso8601String(),
                                'duration': end.difference(start).inSeconds,
                                'amount': double.tryParse(
                                        draft.amountController.text.trim()) ??
                                    0,
                                'status': 'ended',
                                'createdAt': DateTime.now().toIso8601String(),
                                'endedBy': 'admin',
                              });
                            }
                            if (context.mounted) Navigator.pop(context);
                          },
                          icon: const Icon(Icons.check_circle),
                          label: Text('حفظ ${drafts.length} دروس'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _draftEditor(
    BuildContext context, {
    required String title,
    required _AdminLessonDraft draft,
    required double rate,
    required VoidCallback onChanged,
    VoidCallback? onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'حذف',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: draft.date,
                      firstDate: DateTime(DateTime.now().year - 5),
                      lastDate: DateTime(DateTime.now().year + 2),
                      locale: const Locale('ar'),
                    );
                    if (picked != null) {
                      draft.date = picked;
                      draft.amountEdited = false;
                      onChanged();
                    }
                  },
                  icon: const Icon(Icons.event),
                  label: Text(_dateFormat.format(draft.date)),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: draft.start,
                    );
                    if (picked != null) {
                      draft.start = picked;
                      draft.amountEdited = false;
                      onChanged();
                    }
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: Text(draft.start.format(context)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: draft.end,
                    );
                    if (picked != null) {
                      draft.end = picked;
                      draft.amountEdited = false;
                      onChanged();
                    }
                  },
                  icon: const Icon(Icons.stop),
                  label: Text(draft.end.format(context)),
                ),
              ),
            ],
          ),
          TextField(
            controller: draft.amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
            ],
            onChanged: (_) => draft.amountEdited = true,
            decoration: InputDecoration(
              labelText: 'المبلغ',
              helperText: 'سعر الساعة: ${rate.toStringAsFixed(0)}',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _bulkEditPrice(String teacherCode) async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تعديل سعر ${_selectedLessons.length} دروس'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
          ],
          decoration: const InputDecoration(
            labelText: 'السعر الجديد',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              double.tryParse(controller.text.trim()),
            ),
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );
    if (amount == null) return;
    for (final lessonId in _selectedLessons) {
      await FirebaseDatabase.instance
          .ref('users/$teacherCode/schedule/$lessonId')
          .update({
        'amount': amount,
        'updatedAt': DateTime.now().toIso8601String()
      });
    }
    setState(_selectedLessons.clear);
  }

  Future<void> _bulkMarkEnded(
    String teacherCode,
    Map<String, Map<String, dynamic>> students,
  ) async {
    final ids = <String>[];
    final drafts = <_AdminLessonDraft>[];
    final lessons = <String, Map<String, dynamic>>{};
    final scheduleRef =
        FirebaseDatabase.instance.ref('users/$teacherCode/schedule');

    for (final id in ids) {
      final snap = await scheduleRef.child(id).get();
      if (!snap.exists || snap.value is! Map) continue;
      final lesson = Map<String, dynamic>.from(snap.value as Map);
      ids.add(id);
      lessons[id] = lesson;
      final start = DateTime.tryParse(lesson['startTime']?.toString() ?? '') ??
          DateTime.now();
      final end = DateTime.tryParse(lesson['endTime']?.toString() ?? '') ??
          start.add(const Duration(hours: 1));
      final draft = _AdminLessonDraft(
        date: DateTime(start.year, start.month, start.day),
        start: TimeOfDay(hour: start.hour, minute: start.minute),
        end: TimeOfDay(hour: end.hour, minute: end.minute),
      );
      final studentId = (lesson['student'] ?? '').toString();
      final rate = double.tryParse(
            students[studentId]?['hourlyRate']?.toString() ?? '0',
          ) ??
          0;
      draft.amountController.text =
          _amountFor(draft.startDateTime, draft.endDateTime, rate)
              .toStringAsFixed(0);
      drafts.add(draft);
    }
    if (drafts.isEmpty) return;
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Directionality(
              textDirection: ui.TextDirection.rtl,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'إنهاء الدروس المحددة',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        ...ids.asMap().entries.map((entry) {
                          final index = entry.key;
                          final id = entry.value;
                          final lesson = lessons[id]!;
                          final studentId =
                              (lesson['student'] ?? '').toString();
                          final rate = double.tryParse(
                                students[studentId]?['hourlyRate']
                                        ?.toString() ??
                                    '0',
                              ) ??
                              0;
                          return _draftEditor(
                            context,
                            title: students[studentId]?['name']?.toString() ??
                                'طالب',
                            draft: drafts[index],
                            rate: rate,
                            onChanged: () => setModal(() {}),
                          );
                        }),
                        FilledButton.icon(
                          onPressed: () async {
                            for (int i = 0; i < ids.length; i++) {
                              final id = ids[i];
                              final draft = drafts[i];
                              final start = draft.startDateTime;
                              final end = draft.endDateTime;
                              await scheduleRef.child(id).update({
                                'status': 'ended',
                                'date': _dateFormat.format(start),
                                'startTime': start.toIso8601String(),
                                'endTime': end.toIso8601String(),
                                'duration': end.difference(start).inSeconds,
                                'amount': double.tryParse(
                                        draft.amountController.text.trim()) ??
                                    0,
                                'updatedAt': DateTime.now().toIso8601String(),
                                'endedBy': 'admin',
                              });
                            }
                            if (context.mounted) Navigator.pop(context);
                          },
                          icon: const Icon(Icons.done_all),
                          label: const Text('تحويل لمنتهية'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    setState(_selectedLessons.clear);
  }

  Future<void> _deleteSelectedLessons(String teacherCode) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الدروس'),
        content: Text('سيتم حذف ${_selectedLessons.length} دروس.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final id in _selectedLessons) {
      await FirebaseDatabase.instance
          .ref('users/$teacherCode/schedule/$id')
          .remove();
    }
    setState(_selectedLessons.clear);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: StreamBuilder<DatabaseEvent>(
        stream: FirebaseDatabase.instance.ref('users/$_accountId').onValue,
        builder: (context, snapshot) {
          final value = snapshot.data?.snapshot.value;
          final account = value is Map
              ? Map<String, dynamic>.from(value)
              : Map<String, dynamic>.from(widget.account);
          account['id'] = _accountId;
          final role = (account['role'] ?? '').toString();
          final isTeacher = role == 'teacher';

          return DefaultTabController(
            length: isTeacher ? 3 : 1,
            child: Scaffold(
              appBar: AppBar(
                title: Text((account['name'] ?? 'حساب').toString()),
                actions: [
                  IconButton(
                    tooltip: 'حذف الحساب',
                    onPressed: _deleteAccount,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                ],
                bottom: TabBar(
                  tabs: [
                    const Tab(icon: Icon(Icons.person), text: 'الحساب'),
                    if (isTeacher)
                      const Tab(icon: Icon(Icons.groups), text: 'الطلاب'),
                    if (isTeacher)
                      const Tab(icon: Icon(Icons.menu_book), text: 'الدروس'),
                  ],
                ),
              ),
              body: TabBarView(
                children: [
                  _accountTab(account),
                  if (isTeacher) _studentsTab(_accountId),
                  if (isTeacher) _lessonsTab(_accountId),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _accountTab(Map<String, dynamic> account) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _infoTile(
          icon: Icons.badge_outlined,
          title: 'الكود',
          value: account['id'].toString(),
        ),
        _editableTile(
          icon: Icons.person_outline,
          title: 'الاسم',
          value: (account['name'] ?? '').toString(),
          onTap: () => _editAccountField(
            'name',
            'الاسم',
            (account['name'] ?? '').toString(),
          ),
        ),
        _editableTile(
          icon: Icons.email_outlined,
          title: 'البريد',
          value: (account['email'] ?? '').toString(),
          onTap: () => _editAccountField(
            'email',
            'البريد',
            (account['email'] ?? '').toString(),
          ),
        ),
        _editableTile(
          icon: Icons.verified_user_outlined,
          title: 'الدور',
          value: (account['role'] ?? '').toString(),
          onTap: () => _editAccountField(
            'role',
            'الدور',
            (account['role'] ?? '').toString(),
          ),
        ),
      ],
    );
  }

  Widget _studentsTab(String teacherCode) {
    return StreamBuilder<DatabaseEvent>(
      stream:
          FirebaseDatabase.instance.ref('users/$teacherCode/students').onValue,
      builder: (context, snapshot) {
        final value = snapshot.data?.snapshot.value;
        final students = <MapEntry<String, Map<String, dynamic>>>[];
        if (value is Map) {
          final raw = Map<String, dynamic>.from(value);
          for (final entry in raw.entries) {
            if (entry.value is Map) {
              students.add(
                MapEntry(
                    entry.key, Map<String, dynamic>.from(entry.value as Map)),
              );
            }
          }
        }
        return Scaffold(
          body: students.isEmpty
              ? const Center(child: Text('لا يوجد طلاب'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: students.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = students[index];
                    final student = entry.value;
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.school)),
                        title: Text((student['name'] ?? 'طالب').toString()),
                        subtitle: Text(
                          'الكود: ${entry.key} • سعر الساعة: ${student['hourlyRate'] ?? 0}',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              _showEditStudentSheet(
                                  teacherCode, entry.key, student);
                            } else if (value == 'delete') {
                              _deleteStudent(teacherCode, entry.key);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('تعديل')),
                            PopupMenuItem(value: 'delete', child: Text('حذف')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showAddStudentSheet(teacherCode),
            icon: const Icon(Icons.person_add),
            label: const Text('إضافة طالب'),
          ),
        );
      },
    );
  }

  Widget _lessonsTab(String teacherCode) {
    return FutureBuilder<Map<String, Map<String, dynamic>>>(
      future: _loadStudents(teacherCode),
      builder: (context, studentsSnap) {
        final students = studentsSnap.data ?? {};
        return StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance
              .ref('users/$teacherCode/schedule')
              .onValue,
          builder: (context, snapshot) {
            final lessons = <MapEntry<String, Map<String, dynamic>>>[];
            final value = snapshot.data?.snapshot.value;
            if (value is Map) {
              final raw = Map<String, dynamic>.from(value);
              for (final entry in raw.entries) {
                if (entry.value is Map) {
                  lessons.add(
                    MapEntry(entry.key,
                        Map<String, dynamic>.from(entry.value as Map)),
                  );
                }
              }
            }
            lessons.sort((a, b) {
              final da =
                  DateTime.tryParse(a.value['startTime']?.toString() ?? '') ??
                      DateTime(2000);
              final db =
                  DateTime.tryParse(b.value['startTime']?.toString() ?? '') ??
                      DateTime(2000);
              return db.compareTo(da);
            });

            return Scaffold(
              body: Column(
                children: [
                  if (_selectedLessons.isNotEmpty)
                    _bulkBar(teacherCode, students)
                  else
                    _lessonActionsBar(teacherCode, students),
                  Expanded(
                    child: lessons.isEmpty
                        ? const Center(child: Text('لا يوجد دروس'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: lessons.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final entry = lessons[index];
                              final lesson = entry.value;
                              final studentId =
                                  (lesson['student'] ?? '').toString();
                              final studentName =
                                  students[studentId]?['name']?.toString() ??
                                      'طالب';
                              final selected =
                                  _selectedLessons.contains(entry.key);
                              return Card(
                                elevation: 0,
                                color: selected
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                    : null,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                                  ),
                                ),
                                child: ListTile(
                                  leading: Checkbox(
                                    value: selected,
                                    onChanged: (value) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedLessons.add(entry.key);
                                        } else {
                                          _selectedLessons.remove(entry.key);
                                        }
                                      });
                                    },
                                  ),
                                  title: Text(studentName),
                                  subtitle: Text(_lessonSubtitle(lesson)),
                                  trailing: Text(
                                    '${lesson['amount'] ?? 0} ر.ق',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _lessonActionsBar(
    String teacherCode,
    Map<String, Map<String, dynamic>> students,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _showAddEndedBatchSheet(teacherCode, students),
              icon: const Icon(Icons.add_task),
              label: const Text('إضافة دروس منتهية'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulkBar(
    String teacherCode,
    Map<String, Map<String, dynamic>> students,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${_selectedLessons.length} محدد',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          FilledButton.tonalIcon(
            onPressed: () => _bulkEditPrice(teacherCode),
            icon: const Icon(Icons.price_change),
            label: const Text('تعديل السعر'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => _bulkMarkEnded(teacherCode, students),
            icon: const Icon(Icons.done_all),
            label: const Text('إنهاء المحدد'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => _deleteSelectedLessons(teacherCode),
            icon: const Icon(Icons.delete_outline),
            label: const Text('حذف'),
          ),
          IconButton(
            tooltip: 'إلغاء التحديد',
            onPressed: () => setState(_selectedLessons.clear),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  String _lessonSubtitle(Map<String, dynamic> lesson) {
    final start = DateTime.tryParse(lesson['startTime']?.toString() ?? '');
    final end = DateTime.tryParse(lesson['endTime']?.toString() ?? '');
    final status = (lesson['status'] ?? '').toString();
    if (start == null || end == null) {
      return 'الحالة: $status';
    }
    return '${_dateFormat.format(start)} • ${_timeFormat.format(start)} - ${_timeFormat.format(end)} • $status';
  }

  Widget _infoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(value.isEmpty ? 'غير محدد' : value),
      ),
    );
  }

  Widget _editableTile({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(value.isEmpty ? 'غير محدد' : value),
        trailing: const Icon(Icons.edit),
        onTap: onTap,
      ),
    );
  }
}

class _AdminLessonDraft {
  DateTime date;
  TimeOfDay start;
  TimeOfDay end;
  final TextEditingController amountController;
  bool amountEdited;

  _AdminLessonDraft({
    required this.date,
    this.start = const TimeOfDay(hour: 9, minute: 0),
    this.end = const TimeOfDay(hour: 10, minute: 0),
    String amount = '',
  })  : amountEdited = false,
        amountController = TextEditingController(text: amount);

  DateTime get startDateTime =>
      DateTime(date.year, date.month, date.day, start.hour, start.minute);

  DateTime get endDateTime =>
      DateTime(date.year, date.month, date.day, end.hour, end.minute);
}
