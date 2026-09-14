// lib/src/pages/teacher_add_student_page.dart
//
// ➕ إضافة طالب — تصميم عصري:
//   • الاسم، الجنس (شرائح)، سعر الساعة (يُملأ من السعر الافتراضي للمعلم أو المنصة)
//   • هاتف الطالب (اختياري) — يُحفظ على السجل الجذري ليتمكن الطالب من رؤيته
//   • يخضع لصلاحية addStudents
//   • بعد الإنشاء: ورقة أنيقة بالكود مع نسخ/مشاركة وإضافة طالب آخر

import 'dart:math';
import 'dart:ui' as ui;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/auth_provider.dart';
import '../services/permission_guard.dart';
import '../services/teacher_account.dart';
import '../services/timeline_models.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import 'student/student_sheets.dart' show showStudentSheet;
import 'student/student_widgets.dart';
import 'timeline/timeline_widgets.dart';

class TeacherAddStudentPage extends StatefulWidget {
  const TeacherAddStudentPage({super.key});

  @override
  State<TeacherAddStudentPage> createState() => _TeacherAddStudentPageState();
}

class _TeacherAddStudentPageState extends State<TeacherAddStudentPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _rate = TextEditingController();
  final _phone = TextEditingController();
  String? _gender;
  bool _loading = false;
  bool _rateFromDefault = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillRate());
  }

  Future<void> _prefillRate() async {
    final code = context.read<AuthProvider>().currentUser?.code ?? '';
    var rate = await TeacherAccount.fetchDefaultRate(code);
    if (rate <= 0) rate = PlatformGate.current.defaultHourlyRate;
    if (!mounted || rate <= 0 || _rate.text.isNotEmpty) return;
    setState(() {
      _rate.text = rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toStringAsFixed(1);
      _rateFromDefault = true;
    });
  }

  Future<String> _generateUniqueCode() async {
    final random = Random();
    final root = FirebaseDatabase.instance.ref('users');
    while (true) {
      final code = List.generate(8, (_) => random.nextInt(10)).join();
      final snapshot = await root.child(code).get();
      if (!snapshot.exists) return code;
    }
  }

  Future<void> _addStudent() async {
    if (!_formKey.currentState!.validate()) return;
    if (_gender == null) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('يرجى تحديد الجنس')));
      return;
    }
    final auth = context.read<AuthProvider>();
    final teacherCode = auth.currentUser?.code ?? '';
    if (!await PermissionGuard.check(context, TeacherPermission.addStudents, teacherCode: teacherCode)) return;
    if (!mounted) return;

    setState(() => _loading = true);
    try {
      final name = _name.text.trim();
      final phone = _phone.text.trim();
      final hourlyRate = double.tryParse(_rate.text.trim()) ?? 0;
      final code = await _generateUniqueCode();

      await auth.createStudent(name, code, teacherCode);
      if (phone.isNotEmpty) {
        await FirebaseDatabase.instance.ref('users/$code').update({'phone': phone});
      }
      await FirebaseDatabase.instance.ref('users/$teacherCode/students/$code').set({
        'name': name,
        'hourlyRate': hourlyRate,
        'gender': _gender,
        'createdAt': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final again = await _showCreatedSheet(context, name: name, code: code, rate: hourlyRate);
      if (!mounted) return;
      if (again == true) {
        setState(() {
          _name.clear();
          _phone.clear();
          _gender = null;
        });
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppTheme.danger, content: Text('حدث خطأ: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة طالب')),
      body: AdaptiveBody(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.fromLTRB(Responsive.gutter(context), 8, Responsive.gutter(context), 120),
            children: [
              StaggeredReveal(
                index: 0,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: AppTheme.heroGradient(context),
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 34),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('طالب جديد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                            SizedBox(height: 2),
                            Text('سيحصل الطالب على كود دخول من 8 أرقام يمكنك مشاركته معه', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SectionTitle(title: 'البيانات الأساسية', icon: Icons.badge_outlined),
              StaggeredReveal(
                index: 1,
                child: SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'اسم الطالب', prefixIcon: Icon(Icons.person_rounded)),
                        validator: (v) => (v == null || v.trim().length < 2) ? 'الاسم مطلوب' : null,
                      ),
                      const SizedBox(height: 14),
                      Text('الجنس', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _GenderChip(
                              label: 'ذكر',
                              icon: Icons.male_rounded,
                              color: const Color(0xFF3B82F6),
                              selected: _gender == 'male',
                              onTap: () => setState(() => _gender = 'male'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _GenderChip(
                              label: 'أنثى',
                              icon: Icons.female_rounded,
                              color: const Color(0xFFEC4899),
                              selected: _gender == 'female',
                              onTap: () => setState(() => _gender = 'female'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SectionTitle(title: 'السعر والتواصل', icon: Icons.payments_outlined),
              StaggeredReveal(
                index: 2,
                child: SoftCard(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _rate,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                        textDirection: ui.TextDirection.ltr,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) {
                          if (_rateFromDefault) setState(() => _rateFromDefault = false);
                        },
                        decoration: InputDecoration(
                          labelText: 'سعر الساعة',
                          prefixIcon: const Icon(Icons.price_change_rounded),
                          suffixText: TimelineFormat.currency,
                          helperText: _rateFromDefault ? 'مقترح من سعرك الافتراضي — يمكنك تعديله' : null,
                        ),
                        validator: (v) {
                          final d = double.tryParse((v ?? '').trim());
                          if (d == null || d <= 0) return 'أدخل سعراً صحيحاً';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        textDirection: ui.TextDirection.ltr,
                        decoration: const InputDecoration(
                          labelText: 'هاتف الطالب (اختياري)',
                          prefixIcon: Icon(Icons.phone_rounded),
                          helperText: 'يستطيع الطالب تعديله لاحقاً من حسابه',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _loading
              ? const SizedBox(height: 52, child: Center(child: CircularProgressIndicator()))
              : FilledButton.icon(
                  key: const ValueKey('add'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: _addStudent,
                  icon: const Icon(Icons.person_add_rounded),
                  label: const Text('إضافة الطالب', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
        ),
      ),
    );
  }
}

class _GenderChip extends StatelessWidget {
  const _GenderChip({required this.label, required this.icon, required this.color, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressScale(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color : scheme.outlineVariant.withValues(alpha: 0.5), width: selected ? 1.6 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? color : scheme.onSurfaceVariant, size: 22),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? color : scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

Future<bool?> _showCreatedSheet(BuildContext context, {required String name, required String code, required double rate}) {
  final message = 'مرحباً $name 🌸\n\nتم إنشاء حسابك في Dexoed.\n🔑 كود الدخول الخاص بك: $code\n\nافتح التطبيق وأدخل الكود للمتابعة.';
  return showStudentSheet<bool>(
    context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                builder: (_, v, child) => Transform.scale(scale: v, child: child),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.14), shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, color: AppTheme.success, size: 40),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('تمت إضافة $name', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('سعر الساعة: ${TimelineFormat.money(rate)}', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 16),
            PressScale(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: code));
                HapticFeedback.lightImpact();
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('📋 تم نسخ الكود')));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Text('كود الدخول', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text(code, textDirection: ui.TextDirection.ltr, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 6, color: scheme.primary)),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy_rounded, size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text('اضغط للنسخ', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => Share.share(message),
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('مشاركة الكود مع الطالب'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.person_add_alt_rounded),
                    label: const Text('طالب آخر'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('تم'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
