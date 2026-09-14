// lib/src/pages/teacher_students_page.dart
//
// 👥 طلاب المعلم — تصميم عصري مع فرز ذكي:
//   • يستمع لعقدة المعلم كاملة ويحسب رصيد كل طالب لحظياً
//   • بحث، فلاتر سريعة (عليهم مستحقات / رصيد زائد / لم يحدد جنسه / بلا رقم)، ترتيب متعدد
//   • بطاقة الطالب: الرصيد ملوّن، آخر درس، سعر الساعة، الهاتف
//   • إجراءات: دفعة (recordPayments)، الدروس، تعديل (editRates)، مشاركة الكود، حذف (deleteStudents)
//   • حذف الطالب يحترم إعداد المنصة requireZeroBalanceToDelete

import 'dart:async';
import 'dart:ui' as ui;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/auth_provider.dart';
import '../services/permission_guard.dart';
import '../services/timeline_models.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import 'admin/admin_widgets.dart' show SearchField, SortButton, Tag;
import 'student/student_sheets.dart' show showStudentSheet;
import 'student/student_widgets.dart';
import 'teacher_add_student_page.dart';
import 'teacher_lessons_page.dart';
import 'teacher_pay_page.dart';
import 'timeline/timeline_widgets.dart';

class TeacherStudentsPage extends StatefulWidget {
  const TeacherStudentsPage({super.key});

  @override
  State<TeacherStudentsPage> createState() => _TeacherStudentsPageState();
}

enum _Sort { name, balance, recent, rate, lessons }

enum _Quick { all, owing, credit, noGender, noPhone }

class _Row {
  _Row({
    required this.code,
    required this.name,
    required this.gender,
    required this.rate,
    required this.phone,
    required this.balance,
    required this.endedCount,
    required this.lastLesson,
    required this.hasActive,
    required this.raw,
  });
  final String code;
  final String name;
  final String gender;
  final double rate;
  final String phone;
  final double balance;
  final int endedCount;
  final DateTime? lastLesson;
  final bool hasActive;
  final Map<String, dynamic> raw;
}

class _TeacherStudentsPageState extends State<TeacherStudentsPage> {
  final _search = TextEditingController();
  String _q = '';
  _Sort _sort = _Sort.balance;
  _Quick _quick = _Quick.all;

  StreamSubscription<DatabaseEvent>? _sub;
  Map<String, dynamic> _teacher = {};
  final Map<String, String> _phones = {}; // من السجل الجذري users/$code/phone
  bool _ready = false;
  String _teacherCode = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final code = context.read<AuthProvider>().currentUser?.code ?? '';
      _teacherCode = code;
      if (code.isEmpty) return;
      PermissionGuard.start(code);
      _sub = FirebaseDatabase.instance.ref('users/$code').onValue.listen((e) {
        final v = e.snapshot.value;
        if (!mounted) return;
        setState(() {
          _teacher = v is Map ? Map<String, dynamic>.from(v) : {};
          _ready = true;
        });
        _watchPhones();
      }, onError: (_) {
        if (mounted) setState(() => _ready = true);
      });
    });
  }

  /// هواتف الطلاب موجودة على السجل الجذري users/$code/phone — نراقب كل طالب على حدة.
  final Map<String, StreamSubscription<DatabaseEvent>> _phoneSubs = {};
  void _watchPhones() {
    final students = _teacher['students'];
    final codes = students is Map ? students.keys.map((k) => k.toString()).toSet() : <String>{};
    // إلغاء المحذوفين
    for (final c in _phoneSubs.keys.toList()) {
      if (!codes.contains(c)) {
        _phoneSubs.remove(c)?.cancel();
        _phones.remove(c);
      }
    }
    for (final c in codes) {
      if (_phoneSubs.containsKey(c)) continue;
      _phoneSubs[c] = FirebaseDatabase.instance.ref('users/$c/phone').onValue.listen((e) {
        if (!mounted) return;
        setState(() => _phones[c] = (e.snapshot.value ?? '').toString());
      }, onError: (_) {});
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final s in _phoneSubs.values) {
      s.cancel();
    }
    _search.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- الحسابات

  List<_Row> get _rows {
    final students = _teacher['students'];
    if (students is! Map) return const [];
    final schedule = _teacher['schedule'];
    final payments = _teacher['payments'];

    final lessonsTotal = <String, double>{};
    final endedCount = <String, int>{};
    final last = <String, DateTime>{};
    final active = <String>{};
    if (schedule is Map) {
      for (final raw in schedule.values) {
        if (raw is! Map) continue;
        final sc = (raw['student'] ?? '').toString();
        final status = (raw['status'] ?? '').toString();
        final dt = DateTime.tryParse('${raw['startTime'] ?? raw['date'] ?? ''}');
        if (status == 'ended') {
          lessonsTotal[sc] = (lessonsTotal[sc] ?? 0) + (double.tryParse('${raw['amount'] ?? 0}') ?? 0);
          endedCount[sc] = (endedCount[sc] ?? 0) + 1;
          if (dt != null && (last[sc] == null || dt.isAfter(last[sc]!))) last[sc] = dt;
        } else if (status == 'scheduled' || status == 'started') {
          active.add(sc);
        }
      }
    }

    final out = <_Row>[];
    students.forEach((k, v) {
      if (v is! Map) return;
      final code = k.toString();
      final m = Map<String, dynamic>.from(v);
      double paid = 0, returned = 0;
      if (payments is Map && payments[code] is Map) {
        for (final p in (payments[code] as Map).values) {
          if (p is! Map) continue;
          final a = double.tryParse('${p['amount'] ?? 0}') ?? 0;
          if ((p['payer'] ?? 'student') == 'teacher') {
            returned += a;
          } else {
            paid += a;
          }
        }
      }
      out.add(_Row(
        code: code,
        name: (m['name'] ?? 'طالب').toString(),
        gender: (m['gender'] ?? '').toString(),
        rate: double.tryParse('${m['hourlyRate'] ?? 0}') ?? 0,
        phone: _phones[code] ?? '',
        balance: (lessonsTotal[code] ?? 0) - paid + returned,
        endedCount: endedCount[code] ?? 0,
        lastLesson: last[code],
        hasActive: active.contains(code),
        raw: m,
      ));
    });
    return out;
  }

  List<_Row> _filtered(List<_Row> all) {
    final q = _q.trim();
    var list = all.where((r) {
      if (q.isNotEmpty && !(r.name.contains(q) || r.code.contains(q) || r.phone.contains(q))) return false;
      switch (_quick) {
        case _Quick.all:
          return true;
        case _Quick.owing:
          return r.balance > 0.5;
        case _Quick.credit:
          return r.balance < -0.5;
        case _Quick.noGender:
          return r.gender.isEmpty;
        case _Quick.noPhone:
          return r.phone.isEmpty;
      }
    }).toList();
    switch (_sort) {
      case _Sort.name:
        list.sort((a, b) => a.name.compareTo(b.name));
      case _Sort.balance:
        list.sort((a, b) => b.balance.compareTo(a.balance));
      case _Sort.recent:
        list.sort((a, b) => (b.lastLesson ?? DateTime(2000)).compareTo(a.lastLesson ?? DateTime(2000)));
      case _Sort.rate:
        list.sort((a, b) => b.rate.compareTo(a.rate));
      case _Sort.lessons:
        list.sort((a, b) => b.endedCount.compareTo(a.endedCount));
    }
    return list;
  }

  // ------------------------------------------------------------- الإجراءات

  Future<void> _openMenu(_Row r) async {
    HapticFeedback.selectionClick();
    final perms = PermissionGuard.current;
    final action = await showStudentSheet<String>(
      context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final tone = r.balance > 0.5 ? AppTheme.warning : (r.balance < -0.5 ? AppTheme.success : scheme.primary);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: r.name,
                subtitle: 'الكود ${r.code} • ${TimelineFormat.money(r.rate)}/ساعة',
                leading: _Avatar(row: r, size: 46),
                trailing: Tag(
                  label: r.balance.abs() < 0.5 ? 'مسدَّد' : (r.balance > 0 ? 'عليه ${TimelineFormat.money(r.balance)}' : 'له ${TimelineFormat.money(-r.balance)}'),
                  color: tone,
                ),
              ),
              const SizedBox(height: 12),
              _MenuTile(icon: Icons.payments_rounded, color: AppTheme.success, title: 'تسجيل دفعة', subtitle: 'دفعة من الطالب أو إرجاع مبلغ', locked: !perms.allows(TeacherPermission.recordPayments), onTap: () => Navigator.pop(ctx, 'pay')),
              _MenuTile(icon: Icons.menu_book_rounded, color: const Color(0xFF8B5CF6), title: 'دروس الطالب', subtitle: '${r.endedCount} درس منتهٍ', onTap: () => Navigator.pop(ctx, 'lessons')),
              _MenuTile(icon: Icons.edit_rounded, color: const Color(0xFF3B82F6), title: 'تعديل البيانات', subtitle: 'الاسم، سعر الساعة، الجنس', locked: !perms.allows(TeacherPermission.editRates), onTap: () => Navigator.pop(ctx, 'edit')),
              if (r.phone.isNotEmpty)
                _MenuTile(icon: Icons.call_rounded, color: const Color(0xFF06B6D4), title: 'نسخ رقم الهاتف', subtitle: r.phone, onTap: () => Navigator.pop(ctx, 'phone')),
              _MenuTile(icon: Icons.ios_share_rounded, color: const Color(0xFFA855F7), title: 'مشاركة كود الدخول', subtitle: 'أرسل الكود للطالب', onTap: () => Navigator.pop(ctx, 'share')),
              _MenuTile(icon: Icons.delete_outline_rounded, color: AppTheme.danger, title: 'حذف الطالب', subtitle: 'يتطلب تصفية الرصيد', locked: !perms.allows(TeacherPermission.deleteStudents), onTap: () => Navigator.pop(ctx, 'delete')),
            ],
          ),
        );
      },
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'pay':
        if (!await PermissionGuard.check(context, TeacherPermission.recordPayments, teacherCode: _teacherCode)) return;
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(builder: (_) => TeacherPayPage(teacherCode: _teacherCode, studentCode: r.code, studentName: r.name, balance: r.balance)));
      case 'lessons':
        Navigator.push(context, MaterialPageRoute(builder: (_) => TeacherLessonsPage(initialStudentId: r.code)));
      case 'edit':
        if (!await PermissionGuard.check(context, TeacherPermission.editRates, teacherCode: _teacherCode)) return;
        if (!mounted) return;
        await _edit(r);
      case 'phone':
        await Clipboard.setData(ClipboardData(text: r.phone));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('📋 تم نسخ الرقم')));
      case 'share':
        await Share.share('مرحباً ${r.name} 🌸\n\nكود الدخول الخاص بك في Dexoed:\n🔑 ${r.code}\n\nافتح التطبيق وأدخل الكود للمتابعة.');
      case 'delete':
        if (!await PermissionGuard.check(context, TeacherPermission.deleteStudents, teacherCode: _teacherCode)) return;
        if (!mounted) return;
        await _delete(r);
    }
  }

  Future<void> _edit(_Row r) async {
    final name = TextEditingController(text: r.name);
    final rate = TextEditingController(text: r.rate > 0 ? _num(r.rate) : '');
    String gender = r.gender;
    final key = GlobalKey<FormState>();
    final ok = await showStudentSheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHeader(title: 'تعديل بيانات الطالب'),
                const SizedBox(height: 14),
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'الاسم', prefixIcon: Icon(Icons.person_rounded)),
                  validator: (v) => (v == null || v.trim().length < 2) ? 'الاسم مطلوب' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: rate,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                  textDirection: ui.TextDirection.ltr,
                  decoration: InputDecoration(labelText: 'سعر الساعة', prefixIcon: const Icon(Icons.price_change_rounded), suffixText: TimelineFormat.currency, helperText: 'يؤثر على الدروس الجديدة فقط'),
                  validator: (v) => (double.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'أدخل سعراً صحيحاً' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: PillChoice(label: 'ذكر', icon: Icons.male_rounded, selected: gender == 'male', onTap: () => setS(() => gender = 'male'))),
                    const SizedBox(width: 8),
                    Expanded(child: PillChoice(label: 'أنثى', icon: Icons.female_rounded, selected: gender == 'female', onTap: () => setS(() => gender = 'female'))),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    if (!(key.currentState?.validate() ?? false)) return;
                    Navigator.pop(ctx, true);
                  },
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('حفظ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final newName = name.text.trim();
    await FirebaseDatabase.instance.ref('users/$_teacherCode/students/${r.code}').update({
      'name': newName,
      'hourlyRate': double.tryParse(rate.text.trim()) ?? r.rate,
      'gender': gender,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    if (newName != r.name) {
      // مزامنة الاسم مع السجل الجذري إن كان موجوداً
      try {
        final root = FirebaseDatabase.instance.ref('users/${r.code}');
        if ((await root.child('role').get()).value == 'student') {
          await root.update({'name': newName});
        }
      } catch (_) {}
    }
    if (!mounted) return;
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('✅ تم تحديث بيانات الطالب')));
  }

  Future<void> _delete(_Row r) async {
    final requireZero = PlatformGate.current.requireZeroBalanceToDelete;
    final normalized = (r.balance * 100).round() / 100.0;
    if (requireZero && normalized != 0) {
      await _info(
        'لا يمكن الحذف',
        'رصيد الطالب حالياً: ${normalized > 0 ? 'عليه' : 'له'} ${TimelineFormat.money(normalized.abs())}\nيجب تصفية الرصيد قبل الحذف.',
        icon: Icons.account_balance_wallet_rounded,
      );
      return;
    }
    if (r.hasActive) {
      await _info('لا يمكن الحذف', 'يوجد دروس مجدولة أو قيد التنفيذ لهذا الطالب.\nأنهِ أو ألغِ هذه الدروس أولاً.', icon: Icons.event_busy_rounded);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_forever_rounded, color: AppTheme.danger, size: 34),
        title: Text('حذف ${r.name}؟'),
        content: Text('سيُحذف الطالب (الكود ${r.code}) مع سجل دفعاته وحساب دخوله. لا يمكن التراجع.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppTheme.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final base = FirebaseDatabase.instance.ref('users/$_teacherCode');
      await base.child('students/${r.code}').remove();
      await base.child('payments/${r.code}').remove();
      final rootRef = FirebaseDatabase.instance.ref('users/${r.code}');
      final rootSnap = await rootRef.get();
      if (rootSnap.exists && rootSnap.value is Map) {
        final m = Map<String, dynamic>.from(rootSnap.value as Map);
        if ((m['role'] ?? 'student') == 'student' && (m['teacher'] ?? '') == _teacherCode) {
          await rootRef.remove();
        }
      }
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text('تم حذف ${r.name}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppTheme.danger, content: Text('حدث خطأ أثناء الحذف: $e')));
    }
  }

  Future<void> _info(String title, String message, {required IconData icon}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(icon, color: AppTheme.warning, size: 34),
        title: Text(title),
        content: Text(message),
        actions: [FilledButton.tonal(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
      ),
    );
  }

  Future<void> _add() async {
    if (!await PermissionGuard.check(context, TeacherPermission.addStudents, teacherCode: _teacherCode)) return;
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherAddStudentPage()));
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  // ------------------------------------------------------------- الواجهة

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = _rows;
    final list = _filtered(all);
    final owing = all.where((r) => r.balance > 0.5).fold<double>(0, (s, r) => s + r.balance);
    final owingCount = all.where((r) => r.balance > 0.5).length;
    final creditCount = all.where((r) => r.balance < -0.5).length;
    final noGender = all.where((r) => r.gender.isEmpty).length;
    final noPhone = all.where((r) => r.phone.isEmpty).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('الطلاب${all.isEmpty ? '' : ' (${all.length})'}'),
        actions: [
          SortButton<_Sort>(
            value: _sort,
            options: const [
              (value: _Sort.balance, label: 'الرصيد', icon: Icons.account_balance_wallet_rounded),
              (value: _Sort.name, label: 'الاسم', icon: Icons.sort_by_alpha_rounded),
              (value: _Sort.recent, label: 'الأحدث نشاطاً', icon: Icons.history_rounded),
              (value: _Sort.lessons, label: 'عدد الدروس', icon: Icons.menu_book_rounded),
              (value: _Sort.rate, label: 'سعر الساعة', icon: Icons.price_change_rounded),
            ],
            onChanged: (v) => setState(() => _sort = v),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'students_add_fab',
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('إضافة طالب'),
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : AdaptiveBody(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(Responsive.gutter(context), 8, Responsive.gutter(context), 0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // ملخص
                        if (all.isNotEmpty)
                          StaggeredReveal(
                            index: 0,
                            child: SoftCard(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('مستحق على $owingCount طالب', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                                        const SizedBox(height: 2),
                                        AnimatedNumber(value: owing, suffix: ' ${TimelineFormat.currency}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: owing > 0 ? AppTheme.warning : AppTheme.success)),
                                      ],
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 6,
                                    children: [
                                      MiniStat(icon: Icons.group_rounded, label: 'طالب', value: '${all.length}', color: const Color(0xFF3B82F6)),
                                      MiniStat(icon: Icons.check_circle_rounded, label: 'مسدَّد', value: '${all.length - owingCount - creditCount}', color: AppTheme.success),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        SearchField(controller: _search, hint: 'ابحث بالاسم أو الكود أو الهاتف', onChanged: (v) => setState(() => _q = v)),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          child: Row(
                            children: [
                              PillChoice(label: 'الكل', selected: _quick == _Quick.all, onTap: () => setState(() => _quick = _Quick.all)),
                              const SizedBox(width: 6),
                              PillChoice(label: 'عليهم مستحقات ($owingCount)', icon: Icons.warning_amber_rounded, selected: _quick == _Quick.owing, onTap: () => setState(() => _quick = _Quick.owing)),
                              const SizedBox(width: 6),
                              PillChoice(label: 'رصيد زائد ($creditCount)', icon: Icons.savings_outlined, selected: _quick == _Quick.credit, onTap: () => setState(() => _quick = _Quick.credit)),
                              if (noGender > 0) ...[
                                const SizedBox(width: 6),
                                PillChoice(label: 'بلا جنس ($noGender)', icon: Icons.help_outline_rounded, selected: _quick == _Quick.noGender, onTap: () => setState(() => _quick = _Quick.noGender)),
                              ],
                              const SizedBox(width: 6),
                              PillChoice(label: 'بلا رقم ($noPhone)', icon: Icons.phone_disabled_rounded, selected: _quick == _Quick.noPhone, onTap: () => setState(() => _quick = _Quick.noPhone)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ]),
                    ),
                  ),
                  if (all.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: TimelineEmptyState(
                        icon: Icons.group_add_rounded,
                        title: 'لا يوجد طلاب بعد',
                        subtitle: 'أضف أول طالب وشارك معه كود الدخول.',
                        action: FilledButton.icon(onPressed: _add, icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('إضافة طالب')),
                      ),
                    )
                  else if (list.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: TimelineEmptyState(icon: Icons.search_off_rounded, title: 'لا نتائج', subtitle: 'جرّب كلمة أخرى أو غيّر الفلتر.'),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(Responsive.gutter(context), 0, Responsive.gutter(context), 110),
                      sliver: SliverList.builder(
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final r = list[i];
                          return StaggeredReveal(
                            index: i + 1,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _StudentCard(
                                row: r,
                                onTap: () => _openMenu(r),
                                onPay: () async {
                                  if (!await PermissionGuard.check(context, TeacherPermission.recordPayments, teacherCode: _teacherCode)) return;
                                  if (!context.mounted) return;
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => TeacherPayPage(teacherCode: _teacherCode, studentCode: r.code, studentName: r.name, balance: r.balance)));
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

// =====================================================================
// عناصر
// =====================================================================

class _Avatar extends StatelessWidget {
  const _Avatar({required this.row, this.size = 46});
  final _Row row;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = row.gender == 'female' ? const Color(0xFFEC4899) : (row.gender == 'male' ? const Color(0xFF3B82F6) : const Color(0xFF64748B));
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withValues(alpha: 0.85), color], begin: Alignment.topLeft, end: Alignment.bottomRight),
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Text(
        row.name.trim().isEmpty ? '؟' : row.name.trim().characters.first,
        style: TextStyle(color: Colors.white, fontSize: size * 0.42, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({required this.row, required this.onTap, required this.onPay});
  final _Row row;
  final VoidCallback onTap;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = row;
    final settled = r.balance.abs() < 0.5;
    final tone = settled ? AppTheme.success : (r.balance > 0 ? AppTheme.warning : const Color(0xFF3B82F6));
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      onTap: onTap,
      child: Column(
        children: [
          Row(
            children: [
              _Avatar(row: r),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15), overflow: TextOverflow.ellipsis)),
                        if (r.hasActive) const Padding(padding: EdgeInsetsDirectional.only(start: 6), child: PulsingDot(color: Color(0xFF10B981), size: 8)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${TimelineFormat.money(r.rate)}/ساعة • ${r.endedCount} درس'
                      '${r.lastLesson != null ? ' • آخر درس ${_ago(r.lastLesson!)}' : ''}',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    settled ? 'مسدَّد' : TimelineFormat.money(r.balance.abs()),
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: settled ? 13 : 15, color: tone),
                  ),
                  Text(
                    settled ? '' : (r.balance > 0 ? 'عليه' : 'له'),
                    style: TextStyle(fontSize: 11, color: tone.withValues(alpha: 0.85), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Tag(label: r.code, color: const Color(0xFF64748B), icon: Icons.key_rounded),
              const SizedBox(width: 6),
              if (r.phone.isNotEmpty)
                Tag(label: r.phone, color: const Color(0xFF06B6D4), icon: Icons.phone_rounded)
              else if (r.gender.isEmpty)
                const Tag(label: 'لم يُحدد الجنس', color: AppTheme.warning, icon: Icons.help_outline_rounded),
              const Spacer(),
              if (!settled && r.balance > 0)
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10)),
                  onPressed: onPay,
                  icon: const Icon(Icons.payments_rounded, size: 16),
                  label: const Text('دفعة', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              Icon(Icons.more_horiz_rounded, color: scheme.outline, size: 20),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.color, required this.title, this.subtitle, required this.onTap, this.locked = false});
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = locked ? scheme.outline : color;
    return ListTile(
      onTap: onTap,
      dense: true,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Icon(locked ? Icons.lock_rounded : icon, color: c, size: 20),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: locked ? scheme.outline : null)),
      subtitle: subtitle != null ? Text(locked ? 'موقوفة من الإدارة' : subtitle!, style: const TextStyle(fontSize: 11.5)) : null,
      trailing: Icon(Icons.chevron_left_rounded, color: scheme.outlineVariant),
    );
  }
}

String _ago(DateTime d) {
  final diff = DateTime.now().difference(d).inDays;
  if (diff <= 0) return 'اليوم';
  if (diff == 1) return 'أمس';
  if (diff < 7) return 'منذ $diff أيام';
  if (diff < 30) return 'منذ ${diff ~/ 7} أسبوع';
  return '${d.day}/${d.month}';
}
