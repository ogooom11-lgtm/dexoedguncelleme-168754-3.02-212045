// lib/src/pages/home_student.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/student_repository.dart';
import '../services/timeline_models.dart';
import '../theme/app_theme.dart';
import 'student/student_sheets.dart';
import 'student/student_widgets.dart';
import 'student_lessons_page.dart';
import 'student_payments_page.dart';
import 'student_profile_page.dart';
import 'student_request_lesson_page.dart';

/// 🎓 الشاشة الرئيسية للطالب — مستودع بيانات واحد مشترك بين التبويبات،
/// شريط تنقّل سفلي عصري، وزر طلب موعد عائم.
class HomeStudent extends StatefulWidget {
  const HomeStudent({super.key});

  @override
  State<HomeStudent> createState() => _HomeStudentState();
}

class _HomeStudentState extends State<HomeStudent> {
  int _index = 0;
  StudentRepository? _repo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.read<AuthProvider>().currentUser;
    final code = user?.code ?? '';
    final teacher = user?.teacher ?? '';
    if (_repo == null || _repo!.studentCode != code || _repo!.teacherCode != teacher) {
      _repo?.dispose();
      _repo = StudentRepository(studentCode: code, teacherCode: teacher)..start();
    }
  }

  @override
  void dispose() {
    _repo?.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (i == _index) return;
    timelineHaptic(true);
    setState(() => _index = i);
  }

  Future<void> _request() async {
    final repo = _repo!;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => StudentRequestLessonPage(repo: repo)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repo!;
    return ChangeNotifierProvider<StudentRepository>.value(
      value: repo,
      child: Builder(
        builder: (context) {
          final pending = context.select<StudentRepository, int>((r) => r.pendingRequests.length);
          final unpaid = context.select<StudentRepository, int>((r) => r.unpaidLessons.length);
          return Scaffold(
            extendBody: true,
            body: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(_index),
                child: switch (_index) {
                  0 => _StudentDashboard(onTab: _go, onRequest: _request),
                  1 => const StudentLessonsPage(),
                  2 => const StudentPaymentsPage(),
                  _ => const StudentProfilePage(),
                },
              ),
            ),
            floatingActionButton: _index == 3
                ? null
                : FloatingActionButton.extended(
                    heroTag: 'student_request_fab',
                    onPressed: _request,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('طلب موعد'),
                  ),
            bottomNavigationBar: _StudentNavBar(
              index: _index,
              onTap: _go,
              badges: {1: pending, 2: unpaid},
            ),
          );
        },
      ),
    );
  }
}

// =====================================================================
// شريط التنقل
// =====================================================================

class _StudentNavBar extends StatelessWidget {
  const _StudentNavBar({required this.index, required this.onTap, required this.badges});
  final int index;
  final ValueChanged<int> onTap;
  final Map<int, int> badges;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'الرئيسية'),
    (Icons.menu_book_outlined, Icons.menu_book_rounded, 'دروسي'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'المدفوعات'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'حسابي'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF181C26) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.35 : 0.1), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Row(
          children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: _NavItem(
                  selected: index == i,
                  icon: _items[i].$1,
                  activeIcon: _items[i].$2,
                  label: _items[i].$3,
                  badge: badges[i] ?? 0,
                  badgeColor: i == 2 ? AppTheme.danger : TimelineStatus.pending.color,
                  onTap: () => onTap(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.selected,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.badge,
    required this.badgeColor,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int badge;
  final Color badgeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(selected ? activeIcon : icon, key: ValueKey(selected), color: selected ? scheme.primary : scheme.onSurfaceVariant, size: 23),
                ),
                if (badge > 0)
                  PositionedDirectional(
                    top: -4,
                    end: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 16),
                      decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(999), border: Border.all(color: scheme.surface, width: 1.5)),
                      child: Text('$badge', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, height: 1.2)),
                    ),
                  ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: selected
                  ? Padding(
                      padding: const EdgeInsetsDirectional.only(start: 6),
                      child: Text(label, maxLines: 1, style: TextStyle(color: scheme.primary, fontSize: 12, fontWeight: FontWeight.w800)),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// لوحة الطالب الرئيسية
// =====================================================================

class _StudentDashboard extends StatefulWidget {
  const _StudentDashboard({required this.onTab, required this.onRequest});
  final ValueChanged<int> onTab;
  final VoidCallback onRequest;

  @override
  State<_StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<_StudentDashboard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _greeting(String name) {
    final h = DateTime.now().hour;
    final g = h < 12 ? 'صباح الخير' : h < 17 ? 'مساء الخير' : 'مساء النور';
    final n = name.trim().isEmpty ? '' : '، ${name.trim().split(' ').first}';
    return '$g$n';
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<StudentRepository>();
    final scheme = Theme.of(context).colorScheme;
    final user = context.watch<AuthProvider>().currentUser;
    final name = repo.studentName.isNotEmpty ? repo.studentName : (user?.name ?? '');
    final f = repo.finance;
    final tone = balanceTone(f.balance);
    final running = repo.runningLesson;
    final next = repo.nextLesson;
    final pending = repo.pendingRequests;
    final activity = repo.recentActivity(limit: 6);
    final month = repo.monthStats(DateTime.now());
    final unpaid = repo.unpaidLessons;

    if (!repo.hasTeacher) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: TimelineEmptyState(
              icon: Icons.link_off_rounded,
              title: 'الحساب غير مرتبط بمعلم',
              subtitle: 'اطلب من معلمك إضافة رمزك من حسابه لتظهر دروسك هنا.',
              action: OutlinedButton.icon(
                onPressed: () => context.read<AuthProvider>().refreshCurrentUserSilently(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: repo.refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            // ===== الترويسة =====
            SliverToBoxAdapter(
              child: Container(
                padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 14, 20, 26),
                decoration: BoxDecoration(
                  gradient: AppTheme.heroGradient(context),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppTheme.radiusLg + 4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_greeting(name), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 4),
                              Text(
                                repo.teacherName.isEmpty ? TimelineFormat.fullDate(DateTime.now()) : 'معلمك: ${repo.teacherName} • ${TimelineFormat.fullDate(DateTime.now())}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                        PressScale(
                          onTap: () => widget.onTab(3),
                          child: Container(
                            width: 46,
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.5))),
                            child: Text(name.trim().isEmpty ? '؟' : name.trim().characters.first, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // بطاقة المحفظة
                    PressScale(
                      onTap: () => widget.onTab(2),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(tone.icon, color: Colors.white.withValues(alpha: 0.9), size: 16),
                                      const SizedBox(width: 6),
                                      Text(tone.label, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  repo.isReady
                                      ? AnimatedNumber(value: f.balance.abs(), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, height: 1.1))
                                      : Container(width: 90, height: 30, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(8))),
                                  const SizedBox(height: 4),
                                  Text(
                                    unpaid.isEmpty ? 'كل الدروس مسدَّدة' : '${unpaid.length} ${unpaid.length == 1 ? 'درس غير مدفوع' : 'دروس غير مدفوعة'}',
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11.5),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 64,
                              height: 64,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0, end: f.coverage),
                                    duration: const Duration(milliseconds: 900),
                                    curve: Curves.easeOutCubic,
                                    builder: (_, v, __) => CircularProgressIndicator(
                                      value: v,
                                      strokeWidth: 6,
                                      strokeCap: StrokeCap.round,
                                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text('${(f.coverage * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900)),
                                ],
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

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ===== الدرس الجاري / القادم =====
                  if (running != null)
                    StaggeredReveal(index: 0, child: _LiveCard(lesson: running, onTap: () => showStudentLessonSheet(context, lesson: running, repo: repo)))
                  else if (next != null)
                    StaggeredReveal(index: 0, child: _NextCard(lesson: next, onTap: () => showStudentLessonSheet(context, lesson: next, repo: repo)))
                  else if (repo.isReady)
                    StaggeredReveal(
                      index: 0,
                      child: SoftCard(
                        onTap: widget.onRequest,
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                              child: Icon(Icons.event_available_rounded, color: scheme.primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('لا يوجد موعد قادم', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 2),
                                  Text('اطلب موعداً جديداً وسيؤكده معلمك.', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_left_rounded, color: scheme.outline),
                          ],
                        ),
                      ),
                    ),

                  // ===== إحصاءات سريعة =====
                  const SizedBox(height: 12),
                  StaggeredReveal(
                    index: 1,
                    child: Row(
                      children: [
                        Expanded(child: MiniStat(icon: Icons.menu_book_rounded, label: 'دروس الشهر', value: '${month.count}', color: scheme.primary)),
                        const SizedBox(width: 8),
                        Expanded(child: MiniStat(icon: Icons.timer_outlined, label: 'وقت الشهر', value: TimelineFormat.duration(month.minutes), color: const Color(0xFF8B5CF6))),
                        const SizedBox(width: 8),
                        Expanded(child: MiniStat(icon: Icons.upcoming_rounded, label: 'قادمة', value: '${repo.upcomingLessons.length}', color: TimelineStatus.scheduled.color)),
                      ],
                    ),
                  ),

                  // ===== إجراءات سريعة =====
                  const SectionTitle(title: 'إجراءات سريعة', icon: Icons.bolt_rounded),
                  StaggeredReveal(
                    index: 2,
                    child: Row(
                      children: [
                        _Quick(icon: Icons.add_circle_rounded, label: 'طلب موعد', color: scheme.primary, onTap: widget.onRequest),
                        const SizedBox(width: 8),
                        _Quick(icon: Icons.receipt_long_rounded, label: 'كشف حساب', color: AppTheme.success, onTap: () => shareStatement(context, repo)),
                        const SizedBox(width: 8),
                        _Quick(icon: Icons.school_rounded, label: 'معلمي', color: const Color(0xFF06B6D4), onTap: () => widget.onTab(3)),
                      ],
                    ),
                  ),

                  // ===== الطلبات المعلّقة =====
                  if (pending.isNotEmpty) ...[
                    SectionTitle(title: 'طلبات بانتظار الموافقة', icon: Icons.hourglass_top_rounded, actionLabel: 'الكل', onAction: () => widget.onTab(1)),
                    for (var i = 0; i < pending.length && i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: StaggeredReveal(
                          index: 3 + i,
                          child: StudentLessonTile(lesson: pending[i], dense: true, onTap: () => showStudentLessonSheet(context, lesson: pending[i], repo: repo)),
                        ),
                      ),
                  ],

                  // ===== غير مدفوعة =====
                  if (unpaid.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    StaggeredReveal(
                      index: 4,
                      child: SoftCard(
                        glow: AppTheme.danger,
                        onTap: () => widget.onTab(2),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.money_off_rounded, color: AppTheme.danger),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'لديك ${unpaid.length} ${unpaid.length == 1 ? 'درس غير مدفوع' : 'دروس غير مدفوعة'} بقيمة ${TimelineFormat.money(unpaid.fold<double>(0, (s, l) => s + l.amount))}',
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                              ),
                            ),
                            Icon(Icons.chevron_left_rounded, color: scheme.outline),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // ===== النشاط الأخير =====
                  SectionTitle(title: 'النشاط الأخير', icon: Icons.history_rounded, actionLabel: 'دروسي', onAction: () => widget.onTab(1)),
                  if (!repo.isReady)
                    const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
                  else if (activity.isEmpty)
                    const TimelineEmptyState(icon: Icons.auto_awesome_rounded, title: 'ابدأ رحلتك!', subtitle: 'ستظهر دروسك ودفعاتك هنا فور تسجيلها.')
                  else
                    for (var i = 0; i < activity.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: StaggeredReveal(
                          index: 5 + i,
                          child: activity[i].lesson != null
                              ? StudentLessonTile(lesson: activity[i].lesson!, dense: true, onTap: () => showStudentLessonSheet(context, lesson: activity[i].lesson!, repo: repo))
                              : StudentPaymentTile(payment: activity[i].payment!, onTap: () => showStudentPaymentSheet(context, payment: activity[i].payment!)),
                        ),
                      ),
                  if (repo.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(repo.error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: PressScale(
        onTap: () {
          timelineHaptic(true);
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// درس قيد التنفيذ الآن.
class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.lesson, required this.onTap});
  final StudentLesson lesson;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = TimelineStatus.started.color;
    final elapsed = DateTime.now().difference(lesson.start).inMinutes.clamp(0, 9999);
    final progress = lesson.minutes == 0 ? 0.0 : (elapsed / lesson.minutes).clamp(0.0, 1.0);
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.25)!], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const PulsingDot(color: Colors.white),
                const SizedBox(width: 8),
                const Text('درس جارٍ الآن', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                const Spacer(),
                Text('منذ ${TimelineFormat.duration(elapsed)}', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            Text(TimelineFormat.range(lesson.start, lesson.end, use24h: false), style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5)),
            const SizedBox(height: 12),
            ProgressBar(value: progress, color: Colors.white, background: Colors.white.withValues(alpha: 0.25), height: 6),
          ],
        ),
      ),
    );
  }
}

/// الموعد القادم مع عدّاد تنازلي.
class _NextCard extends StatelessWidget {
  const _NextCard({required this.lesson, required this.onTap});
  final StudentLesson lesson;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final diff = lesson.start.difference(DateTime.now());
    final soon = diff.inHours < 24;
    final String countdown;
    if (diff.isNegative) {
      countdown = 'الآن';
    } else if (diff.inDays >= 1) {
      countdown = '${diff.inDays} ${diff.inDays == 1 ? 'يوم' : 'أيام'}';
    } else if (diff.inHours >= 1) {
      countdown = '${diff.inHours} س ${diff.inMinutes % 60} د';
    } else {
      countdown = '${diff.inMinutes} دقيقة';
    }
    return SoftCard(
      onTap: onTap,
      glow: soon ? scheme.primary : null,
      child: Row(
        children: [
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                Text('${lesson.start.day}', style: TextStyle(color: scheme.onPrimary, fontSize: 20, fontWeight: FontWeight.w900, height: 1)),
                Text(TimelineFormat.monthName(lesson.start), style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.85), fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('موعدك القادم', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey)),
                const SizedBox(height: 2),
                Text('${TimelineFormat.relativeDay(lesson.start)} • ${TimelineFormat.range(lesson.start, lesson.end, use24h: false)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(TimelineFormat.duration(lesson.minutes), style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: (soon ? AppTheme.warning : scheme.primary).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Column(
              children: [
                Icon(Icons.hourglass_bottom_rounded, size: 14, color: soon ? AppTheme.warning : scheme.primary),
                Text(countdown, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: soon ? AppTheme.warning : scheme.primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
