// lib/src/pages/home_admin.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/admin_repository.dart';
import '../services/timeline_models.dart';
import '../theme/app_theme.dart';
import 'admin/admin_directory_tab.dart';
import 'admin/admin_settings_tab.dart';
import 'admin/admin_sheets.dart';
import 'admin/admin_student_page.dart';
import 'admin/admin_teacher_page.dart';
import 'admin/admin_widgets.dart';

/// 🛡️ لوحة الإدارة — مستودع واحد مشترك، ثلاثة تبويبات (نظرة عامة / الدليل / الإعدادات)
/// وزر إنشاء سريع.
class HomeAdmin extends StatefulWidget {
  const HomeAdmin({super.key});

  @override
  State<HomeAdmin> createState() => _HomeAdminState();
}

class _HomeAdminState extends State<HomeAdmin> {
  int _index = 0;
  AdminRepository? _repo;
  final _dirKey = GlobalKey<AdminDirectoryTabState>();
  DirView _dirView = DirView.byTeacher;
  String? _dirQuick;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final u = context.read<AuthProvider>().currentUser;
    final code = u?.code ?? '';
    if (_repo == null || _repo!.adminCode != code) {
      _repo?.dispose();
      _repo = AdminRepository(adminCode: code, adminName: u?.name ?? '')..start();
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

  /// فتح الدليل على عرض/فلتر محدد (من بطاقات النظرة العامة).
  void _openDirectory(DirView view, {String? quick}) {
    setState(() {
      _dirView = view;
      _dirQuick = quick;
      _index = 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _dirKey.currentState?.showView(view, quick: quick));
  }

  Future<void> _create() async {
    final repo = _repo!;
    final what = await showStudentSheet<String>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHeader(title: 'إنشاء جديد'),
            const SizedBox(height: 8),
            _CreateOption(icon: Icons.co_present_rounded, color: RoleColors.teacher, title: 'معلم', subtitle: 'حساب معلم جديد مع صلاحيات', onTap: () => Navigator.pop(ctx, 'teacher')),
            _CreateOption(icon: Icons.school_rounded, color: RoleColors.student, title: 'طالب', subtitle: 'يُضاف إلى معلم تختاره', onTap: () => Navigator.pop(ctx, 'student')),
            _CreateOption(icon: Icons.shield_rounded, color: RoleColors.admin, title: 'حساب إدارة', subtitle: 'مدير إضافي للوحة', onTap: () => Navigator.pop(ctx, 'admin')),
          ],
        ),
      ),
    );
    if (!mounted || what == null) return;
    switch (what) {
      case 'teacher':
        await showCreateTeacherSheet(context, repo);
      case 'admin':
        await showCreateAdminSheet(context, repo);
      case 'student':
        if (repo.teachers.isEmpty) {
          adminToast(context, 'أضف معلماً أولاً', error: true);
          return;
        }
        final code = await _pickTeacher(repo);
        if (code != null && mounted) await showStudentFormSheet(context, repo, teacherCode: code);
    }
  }

  Future<String?> _pickTeacher(AdminRepository repo) {
    return showStudentSheet<String>(
      context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHeader(title: 'اختر المعلم'),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final t in repo.teachers)
                      ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        leading: InitialAvatar(name: t.name, color: teacherHue(t.code), size: 40),
                        title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                        subtitle: Text('${t.students.length} طالب', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                        trailing: Icon(Icons.chevron_left_rounded, color: scheme.outline),
                        onTap: () => Navigator.pop(ctx, t.code),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repo!;
    return ChangeNotifierProvider<AdminRepository>.value(
      value: repo,
      child: Builder(
        builder: (context) {
          final pending = context.select<AdminRepository, int>((r) => r.totalPending);
          return Scaffold(
            extendBody: true,
            body: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(anim), child: child),
              ),
              child: KeyedSubtree(
                key: ValueKey(_index),
                child: switch (_index) {
                  0 => _AdminDashboard(onOpenDirectory: _openDirectory, onCreate: _create),
                  1 => AdminDirectoryTab(key: _dirKey, initialView: _dirView, initialQuick: _dirQuick),
                  _ => const AdminSettingsTab(),
                },
              ),
            ),
            floatingActionButton: _index == 2
                ? null
                : FloatingActionButton.extended(
                    heroTag: 'admin_create_fab',
                    onPressed: _create,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('إنشاء'),
                  ),
            bottomNavigationBar: _AdminNavBar(index: _index, onTap: _go, badges: {1: pending}),
          );
        },
      ),
    );
  }
}

class _CreateOption extends StatelessWidget {
  const _CreateOption({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressScale(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.2))),
        child: Row(
          children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: Colors.white)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  Text(subtitle, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_left_rounded, color: color),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// شريط التنقل
// =====================================================================

class _AdminNavBar extends StatelessWidget {
  const _AdminNavBar({required this.index, required this.onTap, required this.badges});
  final int index;
  final ValueChanged<int> onTap;
  final Map<int, int> badges;

  static const _items = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'نظرة عامة'),
    (Icons.account_tree_outlined, Icons.account_tree_rounded, 'الدليل'),
    (Icons.settings_outlined, Icons.settings_rounded, 'الإعدادات'),
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
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                    decoration: BoxDecoration(color: index == i ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent, borderRadius: BorderRadius.circular(18)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: Icon(index == i ? _items[i].$2 : _items[i].$1, key: ValueKey(index == i), color: index == i ? scheme.primary : scheme.onSurfaceVariant, size: 23),
                            ),
                            if ((badges[i] ?? 0) > 0)
                              PositionedDirectional(
                                top: -4,
                                end: -6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  constraints: const BoxConstraints(minWidth: 16),
                                  decoration: BoxDecoration(color: TimelineStatus.pending.color, borderRadius: BorderRadius.circular(999), border: Border.all(color: scheme.surface, width: 1.5)),
                                  child: Text('${badges[i]}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, height: 1.2)),
                                ),
                              ),
                          ],
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          child: index == i
                              ? Padding(padding: const EdgeInsetsDirectional.only(start: 6), child: Text(_items[i].$3, maxLines: 1, style: TextStyle(color: scheme.primary, fontSize: 12, fontWeight: FontWeight.w800)))
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// النظرة العامة
// =====================================================================

class _AdminDashboard extends StatefulWidget {
  const _AdminDashboard({required this.onOpenDirectory, required this.onCreate});
  final void Function(DirView view, {String? quick}) onOpenDirectory;
  final VoidCallback onCreate;

  @override
  State<_AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<_AdminDashboard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AdminRepository>();
    final auth = context.watch<AuthProvider>();
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final name = auth.currentUser?.name ?? 'مدير';
    final h = now.hour;
    final greet = h < 12 ? 'صباح الخير' : h < 17 ? 'مساء الخير' : 'مساء النور';
    final months = repo.lastMonths();
    final today = repo.lessonsOn(now);
    final running = today.where((l) => l.isRunning).toList();
    final upcomingToday = today.where((l) => l.isUpcoming).toList();
    final endedToday = today.where((l) => l.isEnded).toList();
    final top = repo.topTeachers(now, limit: 5);
    final prevRev = repo.revenueIn(DateTime(now.year, now.month - 1));
    final curRev = repo.revenueIn(now);
    final growth = prevRev == 0 ? null : (curRev - prevRev) / prevRev * 100;
    final owingStudents = repo.allStudents.where((s) => s.owes).toList()..sort((a, b) => b.balance.compareTo(a.balance));
    final unlinked = repo.allStudents.where((s) => !s.linked).length;
    final alerts = <Widget>[];

    if (repo.totalPending > 0) {
      alerts.add(_Alert(icon: Icons.hourglass_top_rounded, color: TimelineStatus.pending.color, text: '${repo.totalPending} طلب موعد بانتظار موافقة المعلمين', onTap: () => widget.onOpenDirectory(DirView.students, quick: 'pending')));
    }
    if (unlinked > 0) {
      alerts.add(_Alert(icon: Icons.link_off_rounded, color: AppTheme.warning, text: '$unlinked طالب بلا سجل دخول — اضغط للمعالجة', onTap: () => widget.onOpenDirectory(DirView.students, quick: 'unlinked')));
    }
    if (repo.orphanStudents.isNotEmpty) {
      alerts.add(_Alert(icon: Icons.person_search_rounded, color: AppTheme.warning, text: '${repo.orphanStudents.length} سجل طالب بلا معلم', onTap: () => widget.onOpenDirectory(DirView.byTeacher)));
    }
    if (repo.disabledCount > 0) {
      alerts.add(_Alert(icon: Icons.block_rounded, color: scheme.error, text: '${repo.disabledCount} حساب معطّل', onTap: () => widget.onOpenDirectory(DirView.students, quick: 'disabled')));
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: repo.refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 14, 20, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF1E1B4B), Color(0xFF4C1D95), Color(0xFF7C3AED)], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppTheme.radiusLg + 4)),
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
                              Text('$greet، ${name.split(' ').first}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 4),
                              Text(TimelineFormat.fullDate(now), style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: 0.3))),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shield_rounded, color: Colors.white, size: 14),
                              SizedBox(width: 5),
                              Text('إدارة', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // شريط الحالة اللحظية
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppTheme.radiusMd), border: Border.all(color: Colors.white.withValues(alpha: 0.22))),
                      child: Row(
                        children: [
                          _Live(label: 'جارٍ الآن', value: running.length, icon: Icons.play_circle_fill_rounded, pulse: running.isNotEmpty),
                          _Live(label: 'متبقٍ اليوم', value: upcomingToday.length, icon: Icons.upcoming_rounded),
                          _Live(label: 'أُنجز اليوم', value: endedToday.length, icon: Icons.check_circle_rounded),
                          _Live(label: 'معلمون', value: repo.teachers.length, icon: Icons.co_present_rounded, onTap: () => widget.onOpenDirectory(DirView.teachers)),
                        ],
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
                  if (!repo.isReady)
                    const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                  else ...[
                    // ===== أرقام رئيسية =====
                    StaggeredReveal(
                      index: 0,
                      child: Row(
                        children: [
                          Expanded(child: GradientStat(icon: Icons.payments_rounded, label: 'إيراد ${TimelineFormat.monthName(now)}', value: curRev, color: AppTheme.success, subtitle: growth == null ? '${repo.endedIn(now)} درس' : '${growth >= 0 ? '▲' : '▼'} ${growth.abs().toStringAsFixed(0)}% عن ${TimelineFormat.monthName(DateTime(now.year, now.month - 1))}')),
                          const SizedBox(width: 10),
                          Expanded(child: GradientStat(icon: Icons.trending_down_rounded, label: 'مستحقات على الطلاب', value: repo.totalOwed, color: repo.totalOwed > 0 ? AppTheme.danger : scheme.primary, subtitle: '${owingStudents.length} طالب', onTap: () => widget.onOpenDirectory(DirView.students, quick: 'owing'))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    StaggeredReveal(
                      index: 1,
                      child: Row(
                        children: [
                          Expanded(child: MiniStat(icon: Icons.school_rounded, label: 'طلاب', value: '${repo.allStudents.length}', color: RoleColors.student)),
                          const SizedBox(width: 8),
                          Expanded(child: MiniStat(icon: Icons.menu_book_rounded, label: 'دروس منتهية', value: '${repo.totalEnded}', color: TimelineStatus.ended.color)),
                          const SizedBox(width: 8),
                          Expanded(child: MiniStat(icon: Icons.timer_outlined, label: 'ساعات', value: (repo.totalMinutes / 60).toStringAsFixed(0), color: const Color(0xFF8B5CF6))),
                          const SizedBox(width: 8),
                          Expanded(child: MiniStat(icon: Icons.account_balance_rounded, label: 'محصَّل', value: repo.totalCollected >= 1000 ? '${(repo.totalCollected / 1000).toStringAsFixed(1)}k' : repo.totalCollected.toStringAsFixed(0), color: scheme.primary)),
                        ],
                      ),
                    ),

                    // ===== تنبيهات =====
                    if (alerts.isNotEmpty) ...[
                      const SectionTitle(title: 'يحتاج انتباهك', icon: Icons.notifications_active_rounded),
                      for (final (i, a) in alerts.indexed) StaggeredReveal(index: 2 + i, child: Padding(padding: const EdgeInsets.only(bottom: 8), child: a)),
                    ],

                    // ===== الرسم =====
                    const SectionTitle(title: 'الإيراد خلال 6 أشهر', icon: Icons.bar_chart_rounded),
                    StaggeredReveal(
                      index: 3,
                      child: SoftCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MiniBarChart(
                              items: [for (final m in months) (label: TimelineFormat.monthName(m.month), value: m.revenue)],
                              color: scheme.primary,
                              valueLabel: (v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toStringAsFixed(0),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.info_outline_rounded, size: 14, color: scheme.outline),
                                const SizedBox(width: 4),
                                Expanded(child: Text('إجمالي الإيراد التاريخي ${TimelineFormat.money(repo.totalRevenue)} • متوسط ${TimelineFormat.money(months.fold(0.0, (s, m) => s + m.revenue) / months.length)} شهرياً', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ===== أفضل المعلمين =====
                    if (top.isNotEmpty) ...[
                      SectionTitle(title: 'المعلمون هذا الشهر', icon: Icons.leaderboard_rounded, actionLabel: 'الكل', onAction: () => widget.onOpenDirectory(DirView.teachers)),
                      StaggeredReveal(
                        index: 4,
                        child: SoftCard(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              for (final (i, t) in top.indexed)
                                _RankRow(
                                  rank: i + 1,
                                  teacher: t,
                                  max: top.first.revenueIn(now),
                                  month: now,
                                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminTeacherPage(teacherCode: t.code))),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // ===== جارٍ الآن =====
                    if (running.isNotEmpty) ...[
                      const SectionTitle(title: 'دروس جارية الآن', icon: Icons.play_circle_rounded),
                      for (final (i, l) in running.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: StaggeredReveal(
                            index: 5 + i,
                            child: LessonRow(
                              lesson: l,
                              subtitle: '${repo.student(l.studentCode)?.name ?? l.studentCode} • ${repo.teacher(l.teacherCode)?.name ?? ''}',
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminStudentPage(studentCode: l.studentCode))),
                            ),
                          ),
                        ),
                    ],

                    // ===== أعلى المستحقات =====
                    if (owingStudents.isNotEmpty) ...[
                      SectionTitle(title: 'أعلى المستحقات', icon: Icons.trending_down_rounded, actionLabel: 'الكل', onAction: () => widget.onOpenDirectory(DirView.students, quick: 'owing')),
                      for (final (i, s) in owingStudents.take(5).indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: StaggeredReveal(
                            index: 6 + i,
                            child: StudentRow(student: s, showTeacher: true, teacherName: repo.teacher(s.teacherCode)?.name, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminStudentPage(studentCode: s.code)))),
                          ),
                        ),
                    ],

                    if (repo.teachers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 30),
                        child: TimelineEmptyState(
                          icon: Icons.rocket_launch_rounded,
                          title: 'ابدأ بإضافة أول معلم',
                          subtitle: 'بعدها يمكنك إضافة الطلاب ومتابعة كل شيء من هنا.',
                          action: FilledButton.icon(onPressed: widget.onCreate, icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('إضافة معلم')),
                        ),
                      ),
                    if (repo.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(repo.error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12))),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Live extends StatelessWidget {
  const _Live({required this.label, required this.value, required this.icon, this.pulse = false, this.onTap});
  final String label;
  final int value;
  final IconData icon;
  final bool pulse;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (pulse) ...[const PulsingDot(color: Colors.white, size: 8), const SizedBox(width: 4)] else Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 14),
                const SizedBox(width: 4),
                AnimatedNumber(value: value.toDouble(), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, height: 1)),
              ],
            ),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 10.5)),
          ],
        ),
      ),
    );
  }
}

class _Alert extends StatelessWidget {
  const _Alert({required this.icon, required this.color, required this.text, required this.onTap});
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      onTap: onTap,
      glow: color,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
          Icon(Icons.chevron_left_rounded, color: scheme.outline),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank, required this.teacher, required this.max, required this.month, required this.onTap});
  final int rank;
  final AdminTeacher teacher;
  final double max;
  final DateTime month;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rev = teacher.revenueIn(month);
    final hue = teacherHue(teacher.code);
    final medal = switch (rank) { 1 => const Color(0xFFF59E0B), 2 => const Color(0xFF9CA3AF), 3 => const Color(0xFFB45309), _ => scheme.outline };
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: medal.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Text('$rank', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: medal)),
            ),
            const SizedBox(width: 8),
            InitialAvatar(name: teacher.name, color: hue, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(teacher.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                      Text(TimelineFormat.money(rev), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: hue)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ProgressBar(value: max <= 0 ? 0 : (rev / max).clamp(0, 1), color: hue, height: 5),
                  const SizedBox(height: 2),
                  Text('${teacher.endedIn(month)} درس • ${teacher.students.length} طالب', style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
