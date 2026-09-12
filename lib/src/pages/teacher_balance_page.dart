import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import 'teacher_lessons_page.dart';
import 'teacher_pay_page.dart';

class TeacherBalancePage extends StatefulWidget {
  const TeacherBalancePage({super.key});

  @override
  State<TeacherBalancePage> createState() => _TeacherBalancePageState();
}

class _TeacherBalancePageState extends State<TeacherBalancePage> {
  String _filter = "all"; // all | due | extra
  double _displayedTotal = 0; // لتحريك الرقم بسلاسة بدون متحكم يدوي

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final teacherCode = auth.currentUser?.code ?? "";

    final lessonsRef =
        FirebaseDatabase.instance.ref("users/$teacherCode/schedule");
    final paymentsRef =
        FirebaseDatabase.instance.ref("users/$teacherCode/payments");
    final studentsRef =
        FirebaseDatabase.instance.ref("users/$teacherCode/students");

    return Scaffold(
      appBar: AppBar(
        title: const Text("الأرصدة"),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: StreamBuilder(
            stream: studentsRef.onValue,
            builder: (context, studentsSnap) {
              if (studentsSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!studentsSnap.hasData ||
                  studentsSnap.data?.snapshot.value == null) {
                return _emptyState(
                  icon: Icons.group_off_outlined,
                  title: "لا يوجد طلاب مسجلين",
                  subtitle: "أضف طلاباً أولاً لتظهر أرصدتهم هنا",
                );
              }

              final studentsData = Map<String, dynamic>.from(
                studentsSnap.data!.snapshot.value as Map,
              );

              return StreamBuilder(
                stream: lessonsRef.onValue,
                builder: (context, lessonsSnap) {
                  if (!lessonsSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // مجموع الدروس المنتهية لكل طالب
                  final Map<String, double> studentLessons = {};
                  if (lessonsSnap.data?.snapshot.value != null) {
                    final lessonsData = Map<String, dynamic>.from(
                      lessonsSnap.data!.snapshot.value as Map,
                    );
                    lessonsData.forEach((_, value) {
                      if (value is! Map) return;
                      final lesson = Map<String, dynamic>.from(value);
                      if (lesson['status'] == 'ended') {
                        final student =
                            (lesson['student'] ?? "unknown").toString();
                        final amount =
                            double.tryParse("${lesson['amount']}") ?? 0.0;
                        studentLessons[student] =
                            (studentLessons[student] ?? 0) + amount;
                      }
                    });
                  }

                  return StreamBuilder(
                    stream: paymentsRef.onValue,
                    builder: (context, paymentsSnap) {
                      if (!paymentsSnap.hasData) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }

                      final Map<String, dynamic> paymentsData =
                          paymentsSnap.data?.snapshot.value != null
                              ? Map<String, dynamic>.from(
                                  paymentsSnap.data!.snapshot.value as Map)
                              : {};

                      final rows = <_StudentBalanceRow>[];
                      studentsData.forEach((studentCode, studentInfo) {
                        String name = studentCode;
                        try {
                          final info =
                              Map<String, dynamic>.from(studentInfo as Map);
                          name = (info['name'] ?? studentCode).toString();
                        } catch (_) {}

                        final lessonsTotal =
                            studentLessons[studentCode] ?? 0.0;

                        double paidTotal = 0;
                        double returnedTotal = 0;
                        DateTime? lastPayment;

                        final rawStudentPayments =
                            paymentsData[studentCode];
                        if (rawStudentPayments is Map) {
                          rawStudentPayments.forEach((_, payment) {
                            if (payment is! Map) return;
                            final payer =
                                (payment['payer'] ?? 'student').toString();
                            final amount =
                                double.tryParse("${payment['amount']}") ??
                                    0.0;
                            final date = DateTime.tryParse(
                                "${payment['date'] ?? ''}");

                            if (payer == 'teacher') {
                              returnedTotal += amount;
                            } else {
                              paidTotal += amount;
                            }
                            if (date != null &&
                                (lastPayment == null ||
                                    date.isAfter(lastPayment!))) {
                              lastPayment = date;
                            }
                          });
                        }

                        rows.add(
                          _StudentBalanceRow(
                            code: studentCode,
                            name: name,
                            lessonsTotal: lessonsTotal,
                            paidTotal: paidTotal,
                            returnedTotal: returnedTotal,
                            lastPayment: lastPayment,
                          ),
                        );
                      });

                      // الفرز: الأعلى رصيداً أولاً
                      rows.sort((a, b) => b.balance.compareTo(a.balance));

                      List<_StudentBalanceRow> visible = rows;
                      if (_filter == "due") {
                        visible =
                            rows.where((e) => e.balance > 0).toList();
                      } else if (_filter == "extra") {
                        visible = rows
                            .where((e) => e.balance < 0)
                            .toList()
                            .reversed
                            .toList();
                      }

                      final totalAll = rows.fold<double>(
                          0, (sum, e) => sum + e.balance);
                      final positives =
                          rows.where((e) => e.balance > 0).toList();
                      final positiveTotal = positives.fold<double>(
                          0, (sum, e) => sum + e.balance);
                      final negativeTotal = rows
                          .where((e) => e.balance < 0)
                          .fold<double>(0, (sum, e) => sum + e.balance);

                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          Responsive.gutter(context),
                          12,
                          Responsive.gutter(context),
                          0,
                        ),
                        child: Column(
                          children: [
                            _buildTotalCard(
                              context,
                              total: totalAll,
                              studentsCount: rows.length,
                              dueCount: positives.length,
                              dueTotal: positiveTotal,
                              extraTotal: negativeTotal,
                            ),
                            const SizedBox(height: 12),
                            _buildFilterChips(rows),
                            if (positives.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _buildDistribution(
                                  context, positives, positiveTotal),
                            ],
                            const SizedBox(height: 12),
                            Expanded(
                              child: visible.isEmpty
                                  ? _emptyState(
                                      icon: Icons.search_off_outlined,
                                      title: "لا توجد نتائج",
                                      subtitle:
                                          "جرّب تغيير الفلتر لعرض أرصدة أخرى",
                                    )
                                  : ListView.builder(
                                      padding:
                                          const EdgeInsets.only(bottom: 24),
                                      itemCount: visible.length,
                                      itemBuilder: (context, index) =>
                                          _buildStudentCard(
                                              context,
                                              teacherCode,
                                              visible[index]),
                                    ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // ===== بطاقة الإجمالي =====
  Widget _buildTotalCard(
    BuildContext context, {
    required double total,
    required int studentsCount,
    required int dueCount,
    required double dueTotal,
    required double extraTotal,
  }) {
    final fmt = NumberFormat('#,###');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Column(
        children: [
          const Text(
            "إجمالي الرصيد",
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: _displayedTotal, end: total),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOut,
            onEnd: () => _displayedTotal = total,
            builder: (context, value, _) {
              return Text(
                "${fmt.format(value.toInt())} ر.ق",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _miniStat("الطلاب", "$studentsCount"),
                _miniDivider(),
                _miniStat("مستحق عليهم", "$dueCount"),
                _miniDivider(),
                _miniStat("الإجمالي المستحق", "${fmt.format(dueTotal.toInt())}"),
                if (extraTotal < 0) ...[
                  _miniDivider(),
                  _miniStat(
                      "زيادة مدفوعة", "${fmt.format((-extraTotal).toInt())}"),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }

  Widget _miniDivider() => Container(
        width: 1,
        height: 26,
        color: Colors.white.withValues(alpha: 0.35),
      );

  // ===== فلاتر =====
  Widget _buildFilterChips(List<_StudentBalanceRow> rows) {
    final hasDue = rows.any((e) => e.balance > 0);
    final hasExtra = rows.any((e) => e.balance < 0);

    // إعادة الفلتر تلقائياً إلى «الكل» إن اختفت فئته
    if ((_filter == "due" && !hasDue) || (_filter == "extra" && !hasExtra)) {
      _filter = "all";
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterChip("all", "الكل (${rows.length})"),
          const SizedBox(width: 8),
          _filterChip(
            "due",
            "عليهم مستحق (${rows.where((e) => e.balance > 0).length})",
            enabled: hasDue,
          ),
          const SizedBox(width: 8),
          _filterChip(
            "extra",
            "لهم زيادة مدفوعة (${rows.where((e) => e.balance < 0).length})",
            enabled: hasExtra,
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String key, String label, {bool enabled = true}) {
    final selected = _filter == key;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: enabled
          ? (_) => setState(() => _filter = key)
          : null,
    );
  }

  // ===== شريط توزيع المستحقات =====
  Widget _buildDistribution(BuildContext context,
      List<_StudentBalanceRow> positives, double positiveTotal) {
    if (positiveTotal <= 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "توزيع المستحقات",
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Row(
                children: positives.map((e) {
                  final width =
                      constraints.maxWidth * (e.balance / positiveTotal);
                  return Container(
                    width: width,
                    height: 14,
                    color: _pickColor(e.code),
                  );
                }).toList(),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: positives.map((e) {
            final percent = (e.balance / positiveTotal) * 100;
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _pickColor(e.code),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "${e.name} • ${percent.toStringAsFixed(0)}%",
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ===== بطاقة طالب =====
  Widget _buildStudentCard(
      BuildContext context, String teacherCode, _StudentBalanceRow row) {
    final scheme = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,###');
    final color = row.balance > 0
        ? scheme.primary
        : row.balance < 0
            ? AppTheme.danger
            : scheme.outline;

    final lastPaymentText = row.lastPayment != null
        ? "آخر دفعة: ${DateFormat('yyyy-MM-dd').format(row.lastPayment!)}"
        : "لا توجد دفعات بعد";

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: () {
          // عرض دروس الطالب (مع إمكانية فرز غير المدفوعة من صفحة الدروس)
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  TeacherLessonsPage(initialStudentId: row.code),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _pickColor(row.code).withValues(alpha: 0.15),
                child: Text(
                  row.name.isNotEmpty ? row.name.characters.first : "؟",
                  style: TextStyle(
                    color: _pickColor(row.code),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lastPaymentText,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      "دروس: ${fmt.format(row.lessonsTotal.toInt())} • مدفوع: ${fmt.format(row.paidTotal.toInt())}",
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "${fmt.format(row.balance.toInt())} ر.ق",
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: color,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(64, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (ctx) => TeacherPayPage(
                            teacherCode: teacherCode,
                            studentCode: row.code,
                            studentName: row.name,
                            balance: row.balance,
                          ),
                        ),
                      );
                    },
                    child: const Text("دفع"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Color _pickColor(String name) {
    final materialColors = [
      Colors.blue,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.indigo,
      Colors.brown,
      Colors.pink,
      Colors.cyan,
      Colors.lime,
      Colors.amber,
      Colors.green,
      Colors.deepOrange,
      Colors.pinkAccent,
      Colors.lightBlue,
      Colors.lightGreen,
      Colors.blueGrey,
    ];
    return materialColors[name.hashCode.abs() % materialColors.length];
  }
}

/// نموذج صف الرصيد لطالب واحد.
class _StudentBalanceRow {
  final String code;
  final String name;
  final double lessonsTotal;
  final double paidTotal;
  final double returnedTotal;
  final DateTime? lastPayment;

  const _StudentBalanceRow({
    required this.code,
    required this.name,
    required this.lessonsTotal,
    required this.paidTotal,
    required this.returnedTotal,
    required this.lastPayment,
  });

  double get balance => lessonsTotal - paidTotal + returnedTotal;
}
