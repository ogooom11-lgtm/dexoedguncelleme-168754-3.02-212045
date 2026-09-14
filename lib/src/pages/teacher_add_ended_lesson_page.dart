// lib/src/pages/teacher_add_ended_lesson_page.dart
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../services/timeline_models.dart' show TimelineFormat;

/// ✅ ميزة المعلم: إضافة درس منتهي (درس تمّ إعطاؤه سابقاً ولم يُسجَّل).
/// - يمكن إضافة أكثر من درس دفعة واحدة.
/// - يُحسب المبلغ تلقائياً من سعر ساعة الطالب مع إمكانية تعديله.
/// - لا يتم إنشاء أي تنبيهات لهذه الدروس (منتهية أصلاً).
class TeacherAddEndedLessonPage extends StatefulWidget {
  const TeacherAddEndedLessonPage({super.key, this.initialStudentCode});

  final String? initialStudentCode;

  @override
  State<TeacherAddEndedLessonPage> createState() =>
      _TeacherAddEndedLessonPageState();
}

class _TeacherAddEndedLessonPageState extends State<TeacherAddEndedLessonPage> {
  final _dateFormat = DateFormat('yyyy-MM-dd');
  final _timeFormat = DateFormat('HH:mm');

  Map<String, Map<String, dynamic>> _students = {};
  String? _studentCode;

  final List<_EndedLessonDraft> _drafts = [];

  bool _loadingStudents = true;
  bool _saving = false;
  String _error = '';

  String _teacherCode = '';

  @override
  void initState() {
    super.initState();
    _studentCode = widget.initialStudentCode;
    _drafts.add(_EndedLessonDraft.now());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStudents());
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  // ===================== البيانات =====================

  Future<void> _loadStudents() async {
    final auth = context.read<AuthProvider>();
    _teacherCode = auth.currentUser?.code ?? '';
    if (_teacherCode.isEmpty) {
      setState(() {
        _loadingStudents = false;
        _error = 'تعذر تحديد حساب المعلم';
      });
      return;
    }

    try {
      final snap = await FirebaseDatabase.instance
          .ref('users/$_teacherCode/students')
          .get();

      final parsed = <String, Map<String, dynamic>>{};
      if (snap.exists && snap.value is Map) {
        final raw = Map<String, dynamic>.from(snap.value as Map);
        for (final e in raw.entries) {
          parsed[e.key] = e.value is Map
              ? Map<String, dynamic>.from(e.value as Map)
              : {'name': e.value?.toString() ?? 'طالب'};
        }
      }

      if (!mounted) return;
      setState(() {
        _students = parsed;
        _loadingStudents = false;
        if (_studentCode == null || !parsed.containsKey(_studentCode)) {
          _studentCode = parsed.keys.isEmpty ? null : parsed.keys.first;
        }
      });
      _syncAmounts();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingStudents = false;
        _error = 'تعذر تحميل الطلاب: $e';
      });
    }
  }

  double get _hourlyRate {
    final raw = _students[_studentCode]?['hourlyRate'];
    return double.tryParse('${raw ?? 0}') ?? 0;
  }

  String get _studentName =>
      (_students[_studentCode]?['name'] ?? _studentCode ?? 'طالب').toString();

  double _amountFor(_EndedLessonDraft d) {
    final minutes = d.end.difference(d.start).inMinutes;
    if (minutes <= 0 || _hourlyRate <= 0) return 0;
    return double.parse(((minutes / 60) * _hourlyRate).toStringAsFixed(2));
  }

  void _syncAmounts() {
    for (final d in _drafts) {
      if (!d.amountEdited) {
        d.amountController.text = _amountFor(d).toStringAsFixed(0);
      }
    }
    if (mounted) setState(() {});
  }

  // ===================== الحفظ =====================

  Future<void> _save() async {
    if (_studentCode == null) {
      setState(() => _error = 'الرجاء اختيار الطالب');
      return;
    }

    final valid = _drafts.where((d) => d.end.isAfter(d.start)).toList();
    if (valid.isEmpty) {
      setState(() => _error = 'وقت النهاية يجب أن يكون بعد وقت البداية');
      return;
    }

    setState(() {
      _saving = true;
      _error = '';
    });

    try {
      final scheduleRef =
          FirebaseDatabase.instance.ref('users/$_teacherCode/schedule');

      for (final d in valid) {
        final amount =
            double.tryParse(d.amountController.text.trim()) ?? _amountFor(d);

        await scheduleRef.push().set({
          'teacher': _teacherCode,
          'student': _studentCode,
          'studentName': _studentName,
          'date': _dateFormat.format(d.start),
          'startTime': d.start.toIso8601String(),
          'endTime': d.end.toIso8601String(),
          'duration': d.end.difference(d.start).inSeconds,
          'amount': amount,
          'note': d.noteController.text.trim(),
          'status': 'ended',
          'endedBy': 'teacher',
          'manual': true,
          'createdAt': DateTime.now().toIso8601String(),
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.success,
          content: Text(
            valid.length == 1
                ? 'تمت إضافة الدرس المنتهي بنجاح'
                : 'تمت إضافة ${valid.length} دروس منتهية بنجاح',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'تعذر الحفظ: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ===================== الواجهة =====================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = _drafts.fold<double>(0, (sum, d) {
      return sum + (double.tryParse(d.amountController.text.trim()) ?? 0);
    });
    final totalMinutes = _drafts.fold<int>(0, (sum, d) {
      final m = d.end.difference(d.start).inMinutes;
      return sum + (m > 0 ? m : 0);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة درس منتهي'),
        actions: [
          IconButton(
            tooltip: 'إضافة درس آخر',
            onPressed: _loadingStudents ? null : _addDraft,
            icon: const Icon(Icons.playlist_add_rounded),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.symmetric(
          horizontal: Responsive.gutter(context),
          vertical: 10,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('الإجمالي',
                      style: TextStyle(fontSize: 12, color: cs.outline)),
                  Text(
                    '${total.toStringAsFixed(0)} ${TimelineFormat.currency} • ${_durationLabel(totalMinutes)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _saving || _loadingStudents || _studentCode == null
                    ? null
                    : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle_rounded),
                label: Text(_saving
                    ? 'جارٍ الحفظ...'
                    : 'حفظ ${_drafts.length > 1 ? '${_drafts.length} دروس' : 'الدرس'}'),
              ),
            ),
          ],
        ),
      ),
      body: _loadingStudents
          ? const Center(child: CircularProgressIndicator())
          : _students.isEmpty
              ? _emptyStudents(cs)
              : AdaptiveBody(
                  padding: EdgeInsets.fromLTRB(
                    Responsive.gutter(context),
                    12,
                    Responsive.gutter(context),
                    24,
                  ),
                  child: ListView(
                    children: [
                      _studentCard(cs),
                      const SizedBox(height: 14),
                      ..._drafts.asMap().entries.map(
                            (e) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _draftCard(e.key, e.value, cs),
                            ),
                          ),
                      OutlinedButton.icon(
                        onPressed: _addDraft,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('إضافة درس آخر'),
                      ),
                      if (_error.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSm),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded,
                                  color: cs.onErrorContainer),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error,
                                  style:
                                      TextStyle(color: cs.onErrorContainer),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _emptyStudents(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline_rounded, size: 64, color: cs.outline),
            const SizedBox(height: 12),
            const Text(
              'لا يوجد طلاب بعد',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              'أضف طالباً أولاً ثم يمكنك تسجيل دروس منتهية له',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _studentCard(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: _studentCode,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'الطالب',
                prefixIcon: Icon(Icons.person_rounded),
              ),
              items: _students.entries
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(
                        (e.value['name'] ?? e.key).toString(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _studentCode = v);
                for (final d in _drafts) {
                  d.amountEdited = false;
                }
                _syncAmounts();
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.payments_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _hourlyRate > 0
                        ? 'سعر الساعة: ${_hourlyRate.toStringAsFixed(0)} ${TimelineFormat.currency}'
                        : 'لم يتم تحديد سعر ساعة لهذا الطالب — أدخل المبلغ يدوياً',
                    style: TextStyle(fontSize: 12.5, color: cs.outline),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _draftCard(int index, _EndedLessonDraft d, ColorScheme cs) {
    final minutes = d.end.difference(d.start).inMinutes;
    final invalid = minutes <= 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: cs.primary.withValues(alpha: 0.12),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'درس منتهي',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: Responsive.scaleText(context, 15),
                    ),
                  ),
                ),
                if (_drafts.length > 1)
                  IconButton(
                    tooltip: 'حذف',
                    onPressed: () {
                      setState(() {
                        _drafts.removeAt(index).dispose();
                      });
                    },
                    icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            _pickerTile(
              icon: Icons.calendar_month_rounded,
              label: 'التاريخ',
              value: _dateFormat.format(d.start),
              onTap: () => _pickDate(d),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, c) {
                final stacked = c.maxWidth < 340;
                final startTile = _pickerTile(
                  icon: Icons.play_circle_outline_rounded,
                  label: 'البداية',
                  value: _timeFormat.format(d.start),
                  onTap: () => _pickTime(d, isStart: true),
                );
                final endTile = _pickerTile(
                  icon: Icons.stop_circle_outlined,
                  label: 'النهاية',
                  value: _timeFormat.format(d.end),
                  onTap: () => _pickTime(d, isStart: false),
                  error: invalid,
                );
                if (stacked) {
                  return Column(
                    children: [
                      startTile,
                      const SizedBox(height: 8),
                      endTile,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: startTile),
                    const SizedBox(width: 8),
                    Expanded(child: endTile),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [30, 45, 60, 90, 120].map((m) {
                final selected = minutes == m;
                return ChoiceChip(
                  label: Text(_durationLabel(m)),
                  selected: selected,
                  onSelected: (_) {
                    setState(() {
                      d.end = d.start.add(Duration(minutes: m));
                      d.amountEdited = false;
                    });
                    _syncAmounts();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: d.amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: 'المبلغ (${TimelineFormat.currency})',
                prefixIcon: const Icon(Icons.attach_money_rounded),
                suffixIcon: IconButton(
                  tooltip: 'إعادة الحساب من سعر الساعة',
                  onPressed: () {
                    d.amountEdited = false;
                    _syncAmounts();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
              onChanged: (_) {
                d.amountEdited = true;
                setState(() {});
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: d.noteController,
              maxLines: 2,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'ملاحظة (ماذا تم شرحه؟)',
                prefixIcon: Icon(Icons.sticky_note_2_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  invalid
                      ? Icons.error_outline_rounded
                      : Icons.schedule_rounded,
                  size: 18,
                  color: invalid ? cs.error : cs.outline,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    invalid
                        ? 'وقت النهاية يجب أن يكون بعد البداية'
                        : 'المدة: ${_durationLabel(minutes)}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: invalid ? cs.error : cs.outline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
    bool error = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: error ? cs.error : cs.outlineVariant),
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(fontSize: 11, color: cs.outline)),
                  Text(
                    value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit_rounded, size: 16, color: cs.outline),
          ],
        ),
      ),
    );
  }

  // ===================== أدوات =====================

  void _addDraft() {
    setState(() {
      final last = _drafts.isNotEmpty ? _drafts.last : null;
      _drafts.add(
        _EndedLessonDraft(
          start: last?.start ?? DateTime.now(),
          end: last?.end ?? DateTime.now().add(const Duration(hours: 1)),
        ),
      );
    });
    _syncAmounts();
  }

  Future<void> _pickDate(_EndedLessonDraft d) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: d.start,
      firstDate: DateTime(now.year - 2),
      lastDate: now.add(const Duration(days: 1)),
      helpText: 'اختر تاريخ الدرس',
    );
    if (picked == null) return;

    setState(() {
      final duration = d.end.difference(d.start);
      d.start = DateTime(
          picked.year, picked.month, picked.day, d.start.hour, d.start.minute);
      d.end = d.start.add(duration);
    });
    _syncAmounts();
  }

  Future<void> _pickTime(_EndedLessonDraft d, {required bool isStart}) async {
    final base = isStart ? d.start : d.end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
      helpText: isStart ? 'وقت بداية الدرس' : 'وقت نهاية الدرس',
    );
    if (picked == null) return;

    setState(() {
      if (isStart) {
        final duration = d.end.difference(d.start);
        d.start = DateTime(d.start.year, d.start.month, d.start.day,
            picked.hour, picked.minute);
        d.end = d.start.add(duration.inMinutes > 0
            ? duration
            : const Duration(minutes: 60));
      } else {
        d.end = DateTime(d.start.year, d.start.month, d.start.day, picked.hour,
            picked.minute);
        if (!d.end.isAfter(d.start)) {
          // درس امتدّ بعد منتصف الليل
          d.end = d.end.add(const Duration(days: 1));
        }
      }
      d.amountEdited = false;
    });
    _syncAmounts();
  }

  String _durationLabel(int minutes) {
    if (minutes <= 0) return '0 د';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '$h س $m د';
    if (h > 0) return '$h س';
    return '$m د';
  }
}

class _EndedLessonDraft {
  _EndedLessonDraft({required this.start, required this.end})
      : amountController = TextEditingController(),
        noteController = TextEditingController(),
        amountEdited = false;

  factory _EndedLessonDraft.now() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, now.hour, 0);
    return _EndedLessonDraft(
      start: start,
      end: start.add(const Duration(hours: 1)),
    );
  }

  DateTime start;
  DateTime end;
  bool amountEdited;
  final TextEditingController amountController;
  final TextEditingController noteController;

  void dispose() {
    amountController.dispose();
    noteController.dispose();
  }
}
