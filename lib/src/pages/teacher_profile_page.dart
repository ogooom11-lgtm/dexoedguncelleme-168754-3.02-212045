// lib/src/pages/teacher_profile_page.dart
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// الملف الشخصي للمعلم: بيانات الحساب + إحصائيات سريعة + إعدادات المظهر.
class TeacherProfilePage extends StatefulWidget {
  const TeacherProfilePage({super.key});

  @override
  State<TeacherProfilePage> createState() => _TeacherProfilePageState();
}

class _TeacherProfilePageState extends State<TeacherProfilePage> {
  bool _loading = true;
  int _studentsCount = 0;
  int _endedLessons = 0;
  int _upcomingLessons = 0;
  double _totalEarnings = 0;
  double _monthEarnings = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final code = context.read<AuthProvider>().currentUser?.code ?? '';
    if (code.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    try {
      final db = FirebaseDatabase.instance;
      final students = await db.ref('users/$code/students').get();
      final schedule = await db.ref('users/$code/schedule').get();

      int studentsCount = 0;
      if (students.exists && students.value is Map) {
        studentsCount = (students.value as Map).length;
      }

      int ended = 0;
      int upcoming = 0;
      double total = 0;
      double month = 0;
      final now = DateTime.now();

      if (schedule.exists && schedule.value is Map) {
        final raw = Map<String, dynamic>.from(schedule.value as Map);
        for (final v in raw.values) {
          if (v is! Map) continue;
          final lesson = Map<String, dynamic>.from(v);
          final status = (lesson['status'] ?? '').toString();
          final amount = double.tryParse('${lesson['amount'] ?? 0}') ?? 0;
          final start = DateTime.tryParse('${lesson['startTime'] ?? ''}');

          if (status == 'ended') {
            ended++;
            total += amount;
            if (start != null &&
                start.year == now.year &&
                start.month == now.month) {
              month += amount;
            }
          } else if (status == 'scheduled' || status == 'pending') {
            if (start != null && start.isAfter(now)) upcoming++;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _studentsCount = studentsCount;
        _endedLessons = ended;
        _upcomingLessons = upcoming;
        _totalEarnings = total;
        _monthEarnings = month;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final theme = context.watch<ThemeProvider>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('الملف الشخصي')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: AdaptiveBody(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: AppTheme.heroGradient(context),
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      child: const Icon(Icons.person,
                          size: 34, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.name ?? 'معلم',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'الكود: ${user?.code ?? '-'}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: Responsive.gridColumns(context,
                      itemWidth: 170),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.7,
                  children: [
                    _stat('الطلاب', '$_studentsCount', Icons.group_rounded,
                        Colors.blue),
                    _stat('دروس منتهية', '$_endedLessons',
                        Icons.history_edu_rounded, Colors.indigo),
                    _stat('دروس قادمة', '$_upcomingLessons',
                        Icons.event_available_rounded, Colors.orange),
                    _stat(
                      'أرباح هذا الشهر',
                      '${_monthEarnings.toStringAsFixed(0)} ر.ق',
                      Icons.trending_up_rounded,
                      AppTheme.success,
                    ),
                    _stat(
                      'إجمالي الأرباح',
                      '${_totalEarnings.toStringAsFixed(0)} ر.ق',
                      Icons.savings_rounded,
                      Colors.teal,
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.brightness_6_rounded),
                      title: const Text('مظهر التطبيق'),
                      subtitle: Text(
                        switch (theme.mode) {
                          ThemeMode.dark => 'داكن',
                          ThemeMode.light => 'فاتح',
                          ThemeMode.system => 'حسب النظام',
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode),
                            label: Text('فاتح'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.settings_suggest),
                            label: Text('النظام'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode),
                            label: Text('داكن'),
                          ),
                        ],
                        selected: {theme.mode},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) => theme.setMode(s.first),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                onPressed: () async {
                  final auth = context.read<AuthProvider>();
                  await auth.signOut();
                  if (!context.mounted) return;
                  Navigator.pushNamedAndRemoveUntil(
                      context, '/login', (route) => false);
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('تسجيل الخروج'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
