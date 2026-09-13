// lib/src/pages/student_payments_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/student_repository.dart';
import '../services/timeline_models.dart';
import '../theme/app_theme.dart';
import 'student/student_sheets.dart';
import 'student/student_widgets.dart';

/// 💳 المدفوعات — ملخص الحساب، نسبة التغطية، إحصاءات الشهر، وسجل الدفعات.
class StudentPaymentsPage extends StatefulWidget {
  const StudentPaymentsPage({super.key});

  @override
  State<StudentPaymentsPage> createState() => _StudentPaymentsPageState();
}

class _StudentPaymentsPageState extends State<StudentPaymentsPage> {
  int _segment = 0; // 0 دفعات — 1 دروس غير مدفوعة

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<StudentRepository>();
    final scheme = Theme.of(context).colorScheme;
    final f = repo.finance;
    final tone = balanceTone(f.balance);
    final now = DateTime.now();
    final thisMonth = repo.monthStats(now);
    final prevMonth = repo.monthStats(DateTime(now.year, now.month - 1));
    final unpaid = repo.unpaidLessons;

    return Scaffold(
      appBar: AppBar(
        title: const Text('المدفوعات'),
        actions: [
          IconButton(
            tooltip: 'مشاركة كشف الحساب',
            onPressed: repo.isReady ? () => shareStatement(context, repo) : null,
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: !repo.isReady
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: repo.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                children: [
                  // ===== بطاقة الرصيد =====
                  StaggeredReveal(
                    index: 0,
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [tone.color, Color.lerp(tone.color, Colors.black, 0.25)!],
                          begin: AlignmentDirectional.topStart,
                          end: AlignmentDirectional.bottomEnd,
                        ),
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                        boxShadow: [BoxShadow(color: tone.color.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(tone.icon, color: Colors.white.withValues(alpha: 0.9), size: 20),
                              const SizedBox(width: 8),
                              Text(tone.label, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.w700, fontSize: 13)),
                              const Spacer(),
                              if (repo.hourlyRate > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(999)),
                                  child: Text('${TimelineFormat.money(repo.hourlyRate)} / ساعة', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          AnimatedNumber(
                            value: f.balance.abs(),
                            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, height: 1.1),
                          ),
                          const SizedBox(height: 14),
                          ProgressBar(value: f.coverage, color: Colors.white, background: Colors.white.withValues(alpha: 0.25), height: 7),
                          const SizedBox(height: 6),
                          Text(
                            'غطّت دفعاتك ${(f.coverage * 100).round()}% من إجمالي الدروس',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 11.5),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              _Cell(label: 'إجمالي الدروس', value: TimelineFormat.money(f.lessonsTotal)),
                              _Cell(label: 'المدفوع', value: TimelineFormat.money(f.paid)),
                              _Cell(label: f.returned > 0 ? 'المُرجَع' : 'عدد الدفعات', value: f.returned > 0 ? TimelineFormat.money(f.returned) : '${repo.payments.length}'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ===== إحصاءات الشهر =====
                  const SectionTitle(title: 'هذا الشهر مقابل الماضي', icon: Icons.insights_rounded),
                  StaggeredReveal(
                    index: 1,
                    child: Row(
                      children: [
                        Expanded(child: _MonthCard(title: TimelineFormat.monthName(now), stats: thisMonth, highlight: true)),
                        const SizedBox(width: 10),
                        Expanded(child: _MonthCard(title: TimelineFormat.monthName(DateTime(now.year, now.month - 1)), stats: prevMonth)),
                      ],
                    ),
                  ),

                  // ===== المُبدّل =====
                  const SizedBox(height: 18),
                  StaggeredReveal(
                    index: 2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          _Seg(label: 'سجل الدفعات', count: repo.payments.length, selected: _segment == 0, onTap: () => setState(() => _segment = 0)),
                          _Seg(label: 'دروس غير مدفوعة', count: unpaid.length, selected: _segment == 1, color: AppTheme.danger, onTap: () => setState(() => _segment = 1)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: _segment == 0
                        ? Column(
                            key: const ValueKey('pay'),
                            children: [
                              if (repo.payments.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 30),
                                  child: TimelineEmptyState(icon: Icons.receipt_long_outlined, title: 'لا توجد دفعات مسجّلة بعد', subtitle: 'تظهر هنا الدفعات التي يسجّلها المعلم.'),
                                )
                              else
                                for (var i = 0; i < repo.payments.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: StaggeredReveal(
                                      index: i,
                                      child: StudentPaymentTile(
                                        payment: repo.payments[i],
                                        onTap: () => showStudentPaymentSheet(context, payment: repo.payments[i]),
                                      ),
                                    ),
                                  ),
                            ],
                          )
                        : Column(
                            key: const ValueKey('unpaid'),
                            children: [
                              if (unpaid.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 30),
                                  child: TimelineEmptyState(icon: Icons.verified_rounded, title: 'كل الدروس مسدَّدة 🎉', subtitle: 'لا توجد دروس منتهية غير مغطاة بدفعاتك.'),
                                )
                              else ...[
                                SoftCard(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.info_outline_rounded, color: AppTheme.danger, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${unpaid.length} ${unpaid.length == 1 ? 'درس' : 'دروس'} بإجمالي ${TimelineFormat.money(unpaid.fold<double>(0, (s, l) => s + l.amount))} — تُسدَّد الدروس من الأقدم للأحدث.',
                                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.4),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                for (var i = 0; i < unpaid.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: StaggeredReveal(
                                      index: i,
                                      child: StudentLessonTile(
                                        lesson: unpaid[unpaid.length - 1 - i],
                                        onTap: () => showStudentLessonSheet(context, lesson: unpaid[unpaid.length - 1 - i], repo: repo),
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800))),
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 10.5)),
        ],
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.title, required this.stats, this.highlight = false});
  final String title;
  final ({int count, int minutes, double amount, double paid}) stats;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = highlight ? scheme.primary : scheme.onSurfaceVariant;
    return SoftCard(
      padding: const EdgeInsets.all(14),
      glow: highlight ? scheme.primary : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded, size: 16, color: c),
              const SizedBox(width: 6),
              Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: c))),
            ],
          ),
          const SizedBox(height: 10),
          _kv(context, 'الدروس', '${stats.count}'),
          _kv(context, 'الوقت', TimelineFormat.duration(stats.minutes)),
          _kv(context, 'التكلفة', TimelineFormat.money(stats.amount)),
          _kv(context, 'دفعت', TimelineFormat.money(stats.paid), color: AppTheme.success),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v, {Color? color}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(k, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
          const Spacer(),
          Text(v, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color ?? scheme.onSurface)),
        ],
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({required this.label, required this.count, required this.selected, required this.onTap, this.color});
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          timelineHaptic(true);
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? scheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: selected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: selected ? c : scheme.onSurfaceVariant)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: (selected ? c : scheme.outline).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                child: Text('$count', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: selected ? c : scheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
