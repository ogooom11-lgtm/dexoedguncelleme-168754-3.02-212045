import 'dart:ui' as ui;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';

class StudentProfilePage extends StatelessWidget {
  const StudentProfilePage({super.key});

  Future<Map<String, dynamic>> _loadHeaderData(
    String teacherCode,
    String studentCode,
  ) async {
    String teacherName = 'غير محدد';
    double hourlyRate = 0;

    if (teacherCode.isNotEmpty) {
      final teacherSnap =
          await FirebaseDatabase.instance.ref('users/$teacherCode').get();
      if (teacherSnap.exists && teacherSnap.value is Map) {
        final data = Map<String, dynamic>.from(teacherSnap.value as Map);
        teacherName = (data['name'] ?? teacherName).toString();
      }

      final studentSnap = await FirebaseDatabase.instance
          .ref('users/$teacherCode/students/$studentCode')
          .get();
      if (studentSnap.exists && studentSnap.value is Map) {
        final data = Map<String, dynamic>.from(studentSnap.value as Map);
        hourlyRate =
            double.tryParse(data['hourlyRate']?.toString() ?? '0') ?? 0;
      }
    }

    return {'teacherName': teacherName, 'hourlyRate': hourlyRate};
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final student = auth.currentUser!;
    final teacherCode = student.teacher ?? '';

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('حساب الطالب')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _loadHeaderData(teacherCode, student.code),
          builder: (context, headerSnap) {
            final header = headerSnap.data ?? {};
            final teacherName =
                (header['teacherName'] ?? 'جاري التحميل...').toString();
            final hourlyRate = (header['hourlyRate'] ?? 0) as double;

            return StreamBuilder<DatabaseEvent>(
              stream: FirebaseDatabase.instance
                  .ref('users/$teacherCode/schedule')
                  .onValue,
              builder: (context, lessonsSnap) {
                final lessons = _studentLessons(
                  lessonsSnap.data?.snapshot.value,
                  student.code,
                );
                final completed = lessons
                    .where((lesson) => (lesson['status'] ?? '') == 'ended')
                    .toList();
                final next = _nextLesson(lessons);
                final lessonsTotal = completed.fold<double>(
                  0,
                  (sum, lesson) =>
                      sum + (double.tryParse('${lesson['amount'] ?? 0}') ?? 0),
                );

                return StreamBuilder<DatabaseEvent>(
                  stream: FirebaseDatabase.instance
                      .ref('users/$teacherCode/payments/${student.code}')
                      .onValue,
                  builder: (context, paymentsSnap) {
                    final payments =
                        _payments(paymentsSnap.data?.snapshot.value);
                    double studentPayments = 0;
                    double teacherPayments = 0;
                    for (final payment in payments) {
                      final amount =
                          double.tryParse('${payment['amount'] ?? 0}') ?? 0;
                      final payer = (payment['payer'] ?? 'student').toString();
                      if (payer == 'teacher') {
                        teacherPayments += amount;
                      } else {
                        studentPayments += amount;
                      }
                    }
                    final balance =
                        lessonsTotal - studentPayments + teacherPayments;

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        _ProfileHero(
                          name: student.name,
                          code: student.code,
                          email: student.email ?? '',
                          teacherName: teacherName,
                        ),
                        const SizedBox(height: 12),
                        _StatsGrid(
                          completedCount: completed.length,
                          balance: balance,
                          hourlyRate: hourlyRate,
                          paymentsCount: payments.length,
                        ),
                        const SizedBox(height: 12),
                        _TeacherPanel(
                          teacherName: teacherName,
                          hourlyRate: hourlyRate,
                        ),
                        const SizedBox(height: 12),
                        _NextLessonPanel(lesson: next),
                        const SizedBox(height: 12),
                        _AccountActionsPanel(
                          darkMode:
                              Theme.of(context).brightness == Brightness.dark,
                          onToggleTheme: () =>
                              context.read<ThemeProvider>().toggle(),
                          onLogout: () {
                            auth.signOut();
                            Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                          },
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _studentLessons(
    dynamic value,
    String studentCode,
  ) {
    if (value is! Map) return [];
    final raw = Map<String, dynamic>.from(value);
    return raw.entries
        .where((entry) => entry.value is Map)
        .map((entry) => Map<String, dynamic>.from(entry.value as Map))
        .where((lesson) => (lesson['student'] ?? '').toString() == studentCode)
        .toList();
  }

  Map<String, dynamic>? _nextLesson(List<Map<String, dynamic>> lessons) {
    final now = DateTime.now();
    final upcoming = lessons.where((lesson) {
      final status = (lesson['status'] ?? '').toString();
      final start = DateTime.tryParse(lesson['startTime']?.toString() ?? '');
      return status == 'scheduled' && start != null && start.isAfter(now);
    }).toList();
    upcoming.sort((a, b) {
      final da = DateTime.parse(a['startTime'].toString());
      final db = DateTime.parse(b['startTime'].toString());
      return da.compareTo(db);
    });
    return upcoming.isEmpty ? null : upcoming.first;
  }

  List<Map<String, dynamic>> _payments(dynamic value) {
    if (value is! Map) return [];
    return Map<String, dynamic>.from(value)
        .values
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }
}

class _ProfileHero extends StatelessWidget {
  final String name;
  final String code;
  final String email;
  final String teacherName;

  const _ProfileHero({
    required this.name,
    required this.code,
    required this.email,
    required this.teacherName,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = name.trim().isEmpty ? 'ط' : name.trim().characters.first;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: scheme.primary,
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w900,
                color: scheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email.isEmpty ? 'الكود: $code' : email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MiniBadge(
                      icon: Icons.badge_outlined,
                      label: code,
                      color: Colors.indigo,
                    ),
                    _MiniBadge(
                      icon: Icons.co_present_rounded,
                      label: teacherName,
                      color: Colors.teal,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final int completedCount;
  final double balance;
  final double hourlyRate;
  final int paymentsCount;

  const _StatsGrid({
    required this.completedCount,
    required this.balance,
    required this.hourlyRate,
    required this.paymentsCount,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.65,
      children: [
        _MetricTile(
          icon: Icons.done_all_rounded,
          label: 'دروس منتهية',
          value: completedCount.toString(),
          color: Colors.teal,
        ),
        _MetricTile(
          icon: Icons.account_balance_wallet_rounded,
          label: 'الرصيد',
          value: '${_formatNumber(balance)} ر.ق',
          color: balance >= 0 ? Colors.deepOrange : Colors.green,
        ),
        _MetricTile(
          icon: Icons.timer_outlined,
          label: 'سعر الساعة',
          value: '${_formatNumber(hourlyRate)} ر.ق',
          color: Colors.indigo,
        ),
        _MetricTile(
          icon: Icons.payments_rounded,
          label: 'الدفعات',
          value: paymentsCount.toString(),
          color: Colors.purple,
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TeacherPanel extends StatelessWidget {
  final String teacherName;
  final double hourlyRate;

  const _TeacherPanel({required this.teacherName, required this.hourlyRate});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            child: Icon(Icons.co_present_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('المعلم المسؤول',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(teacherName, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          _MiniBadge(
            icon: Icons.timer_outlined,
            label: '${_formatNumber(hourlyRate)} ر.ق',
            color: Colors.indigo,
          ),
        ],
      ),
    );
  }
}

class _NextLessonPanel extends StatelessWidget {
  final Map<String, dynamic>? lesson;

  const _NextLessonPanel({required this.lesson});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (lesson == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.teal.withValues(alpha: 0.24)),
        ),
        child: const Row(
          children: [
            Icon(Icons.event_available_rounded, color: Colors.teal),
            SizedBox(width: 10),
            Expanded(child: Text('لا يوجد درس قادم حالياً')),
          ],
        ),
      );
    }

    final start = DateTime.tryParse(lesson!['startTime']?.toString() ?? '');
    final end = DateTime.tryParse(lesson!['endTime']?.toString() ?? '');
    final label = start == null
        ? 'موعد قادم'
        : '${DateFormat('yyyy-MM-dd').format(start)} • ${DateFormat('HH:mm').format(start)} - ${end == null ? '--:--' : DateFormat('HH:mm').format(end)}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.event_rounded, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('الدرس القادم',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(label),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountActionsPanel extends StatelessWidget {
  final bool darkMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onLogout;

  const _AccountActionsPanel({
    required this.darkMode,
    required this.onToggleTheme,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('الوضع الداكن'),
            secondary: const Icon(Icons.dark_mode_rounded, color: Colors.amber),
            value: darkMode,
            onChanged: (_) => onToggleTheme(),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.logout_rounded, color: Colors.red.shade600),
            title: const Text('تسجيل الخروج'),
            onTap: onLogout,
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MiniBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatNumber(double value) {
  return NumberFormat('#,##0').format(value);
}
