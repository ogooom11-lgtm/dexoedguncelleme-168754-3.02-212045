// lib/src/pages/admin/admin_directory_tab.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/admin_repository.dart';
import '../../services/timeline_models.dart';
import '../../theme/app_theme.dart';
import 'admin_sheets.dart';
import 'admin_student_page.dart';
import 'admin_teacher_page.dart';
import 'admin_widgets.dart';

enum DirView { byTeacher, students, teachers, admins }

enum _TeacherSort { name, revenue, students, owed, recent }

enum _StudentSort { name, balance, lessons, recent, teacher }

enum _Quick { none, owing, credit, inactive, pending, unlinked, disabled }

/// 📇 الدليل: كل معلم مع طلابه (قابل للطي)، أو قوائم مسطحة مع فرز ذكي وفلاتر سريعة.
class AdminDirectoryTab extends StatefulWidget {
  const AdminDirectoryTab({super.key, this.initialView = DirView.byTeacher, this.initialQuick});
  final DirView initialView;
  final String? initialQuick;

  @override
  State<AdminDirectoryTab> createState() => AdminDirectoryTabState();
}

class AdminDirectoryTabState extends State<AdminDirectoryTab> {
  late DirView _view = widget.initialView;
  _TeacherSort _tSort = _TeacherSort.revenue;
  _StudentSort _sSort = _StudentSort.balance;
  late _Quick _quick = _Quick.values.firstWhere((q) => q.name == widget.initialQuick, orElse: () => _Quick.none);
  final _search = TextEditingController();
  String _q = '';
  final Set<String> _collapsed = {};

  void showView(DirView v, {String? quick}) {
    setState(() {
      _view = v;
      _quick = _Quick.values.firstWhere((q) => q.name == quick, orElse: () => _Quick.none);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matchStudent(AdminStudent s) {
    if (_q.isNotEmpty && !(s.name.contains(_q) || s.code.contains(_q) || s.phone.contains(_q) || s.email.contains(_q))) return false;
    return switch (_quick) {
      _Quick.none => true,
      _Quick.owing => s.owes,
      _Quick.credit => s.hasCredit,
      _Quick.inactive => !s.isActive,
      _Quick.pending => s.pendingCount > 0,
      _Quick.unlinked => !s.linked,
      _Quick.disabled => s.disabled,
    };
  }

  bool _matchTeacher(AdminTeacher t) {
    if (_q.isNotEmpty && !(t.name.contains(_q) || t.code.contains(_q) || t.phone.contains(_q) || t.email.contains(_q))) return false;
    return switch (_quick) {
      _Quick.none => true,
      _Quick.owing => t.owed > 0,
      _Quick.credit => t.students.any((s) => s.hasCredit),
      _Quick.inactive => t.activeStudents == 0,
      _Quick.pending => t.pendingCount > 0,
      _Quick.unlinked => t.students.any((s) => !s.linked),
      _Quick.disabled => t.disabled,
    };
  }

  List<AdminTeacher> _sortTeachers(List<AdminTeacher> list) {
    final now = DateTime.now();
    switch (_tSort) {
      case _TeacherSort.name:
        list.sort((a, b) => a.name.compareTo(b.name));
      case _TeacherSort.revenue:
        list.sort((a, b) => b.revenueIn(now).compareTo(a.revenueIn(now)));
      case _TeacherSort.students:
        list.sort((a, b) => b.students.length.compareTo(a.students.length));
      case _TeacherSort.owed:
        list.sort((a, b) => b.owed.compareTo(a.owed));
      case _TeacherSort.recent:
        list.sort((a, b) => (b.lastActivityAt ?? DateTime(2000)).compareTo(a.lastActivityAt ?? DateTime(2000)));
    }
    return list;
  }

  List<AdminStudent> _sortStudents(List<AdminStudent> list, AdminRepository repo) {
    switch (_sSort) {
      case _StudentSort.name:
        list.sort((a, b) => a.name.compareTo(b.name));
      case _StudentSort.balance:
        list.sort((a, b) => b.balance.compareTo(a.balance));
      case _StudentSort.lessons:
        list.sort((a, b) => b.endedCount.compareTo(a.endedCount));
      case _StudentSort.recent:
        list.sort((a, b) => (b.lastLessonAt ?? DateTime(2000)).compareTo(a.lastLessonAt ?? DateTime(2000)));
      case _StudentSort.teacher:
        list.sort((a, b) {
          final c = (repo.teacher(a.teacherCode)?.name ?? '').compareTo(repo.teacher(b.teacherCode)?.name ?? '');
          return c != 0 ? c : a.name.compareTo(b.name);
        });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AdminRepository>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الدليل'),
        actions: [
          IconButton(
            tooltip: _collapsed.isEmpty ? 'طيّ الكل' : 'توسيع الكل',
            onPressed: _view != DirView.byTeacher
                ? null
                : () => setState(() {
                      if (_collapsed.isEmpty) {
                        _collapsed.addAll(repo.teachers.map((t) => t.code));
                      } else {
                        _collapsed.clear();
                      }
                    }),
            icon: Icon(_collapsed.isEmpty ? Icons.unfold_less_rounded : Icons.unfold_more_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(112),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(
              children: [
                Segmented<DirView>(
                  value: _view,
                  onChanged: (v) => setState(() => _view = v),
                  items: const [
                    (value: DirView.byTeacher, label: 'حسب المعلم', icon: Icons.account_tree_rounded),
                    (value: DirView.students, label: 'الطلاب', icon: Icons.school_rounded),
                    (value: DirView.teachers, label: 'المعلمون', icon: Icons.co_present_rounded),
                    (value: DirView.admins, label: 'الإدارة', icon: Icons.shield_rounded),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: SearchField(controller: _search, hint: 'ابحث بالاسم أو الكود أو الهاتف…', onChanged: (v) => setState(() => _q = v.trim()))),
                    const SizedBox(width: 8),
                    if (_view == DirView.students)
                      SortButton<_StudentSort>(
                        value: _sSort,
                        onChanged: (v) => setState(() => _sSort = v),
                        options: const [
                          (value: _StudentSort.balance, label: 'الرصيد', icon: Icons.account_balance_wallet_rounded),
                          (value: _StudentSort.name, label: 'الاسم', icon: Icons.sort_by_alpha_rounded),
                          (value: _StudentSort.teacher, label: 'المعلم', icon: Icons.co_present_rounded),
                          (value: _StudentSort.lessons, label: 'الدروس', icon: Icons.menu_book_rounded),
                          (value: _StudentSort.recent, label: 'الأحدث', icon: Icons.history_rounded),
                        ],
                      )
                    else if (_view != DirView.admins)
                      SortButton<_TeacherSort>(
                        value: _tSort,
                        onChanged: (v) => setState(() => _tSort = v),
                        options: const [
                          (value: _TeacherSort.revenue, label: 'إيراد الشهر', icon: Icons.payments_rounded),
                          (value: _TeacherSort.name, label: 'الاسم', icon: Icons.sort_by_alpha_rounded),
                          (value: _TeacherSort.students, label: 'عدد الطلاب', icon: Icons.groups_rounded),
                          (value: _TeacherSort.owed, label: 'المستحقات', icon: Icons.trending_down_rounded),
                          (value: _TeacherSort.recent, label: 'الأحدث نشاطاً', icon: Icons.history_rounded),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: !repo.isReady
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_view != DirView.admins)
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                      children: [
                        _quickChip(_Quick.none, 'الكل', Icons.all_inclusive_rounded, null),
                        _quickChip(_Quick.owing, 'عليهم مستحقات', Icons.trending_down_rounded, AppTheme.danger),
                        _quickChip(_Quick.pending, 'طلبات معلّقة', Icons.hourglass_top_rounded, TimelineStatus.pending.color),
                        _quickChip(_Quick.inactive, 'غير نشط', Icons.bedtime_outlined, scheme.outline),
                        _quickChip(_Quick.credit, 'رصيد زائد', Icons.trending_up_rounded, AppTheme.success),
                        _quickChip(_Quick.unlinked, 'بلا سجل دخول', Icons.link_off_rounded, AppTheme.warning),
                        _quickChip(_Quick.disabled, 'معطّل', Icons.block_rounded, scheme.error),
                      ],
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: repo.refresh,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: switch (_view) {
                        DirView.byTeacher => _byTeacher(repo, scheme),
                        DirView.students => _students(repo, scheme),
                        DirView.teachers => _teachers(repo, scheme),
                        DirView.admins => _admins(repo, scheme),
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _quickChip(_Quick q, String label, IconData icon, Color? color) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: PillChoice(label: label, icon: icon, color: color, selected: _quick == q, onTap: () => setState(() => _quick = q)),
    );
  }

  void _openTeacher(String code) => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminTeacherPage(teacherCode: code)));
  void _openStudent(String code) => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminStudentPage(studentCode: code)));

  // ------------------------------------------------------------------
  // حسب المعلم
  // ------------------------------------------------------------------
  Widget _byTeacher(AdminRepository repo, ColorScheme scheme) {
    final filtering = _q.isNotEmpty || _quick != _Quick.none;
    final teachers = _sortTeachers(repo.teachers.where((t) {
      if (!filtering) return true;
      // يظهر المعلم إن طابق هو أو أحد طلابه
      return _matchTeacher(t) || t.students.any(_matchStudent);
    }).toList());

    if (teachers.isEmpty && repo.orphanStudents.isEmpty) {
      return ListView(
        key: const ValueKey('bt-empty'),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 60),
          TimelineEmptyState(
            icon: Icons.account_tree_outlined,
            title: filtering ? 'لا نتائج' : 'لا يوجد معلمون بعد',
            subtitle: filtering ? 'جرّب تعديل البحث أو الفلتر.' : 'أضف أول معلم من زر ＋.',
            action: filtering ? null : FilledButton.icon(onPressed: () => showCreateTeacherSheet(context, repo), icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('إضافة معلم')),
          ),
        ],
      );
    }

    final children = <Widget>[];
    var idx = 0;
    for (final t in teachers) {
      // عند البحث باسم المعلم نفسه نعرض كل طلابه، وإلا نعرض الطلاب المطابقين فقط.
      final teacherHit = _q.isNotEmpty && (t.name.contains(_q) || t.code.contains(_q)) && _quick == _Quick.none;
      final shown = _sortStudents(
        (!filtering || teacherHit) ? t.students.toList() : t.students.where(_matchStudent).toList(),
        repo,
      );
      final collapsed = _collapsed.contains(t.code) && !filtering;
      final hue = teacherHue(t.code);
      children.add(StaggeredReveal(
        index: idx++,
        child: _TeacherGroupCard(
          teacher: t,
          hue: hue,
          collapsed: collapsed,
          shownStudents: shown,
          onToggle: () => setState(() => collapsed ? _collapsed.remove(t.code) : _collapsed.add(t.code)),
          onOpen: () => _openTeacher(t.code),
          onAddStudent: () => showStudentFormSheet(context, repo, teacherCode: t.code),
          onStudent: _openStudent,
        ),
      ));
      children.add(const SizedBox(height: 12));
    }

    final orphans = repo.orphanStudents.where((o) => _q.isEmpty || o.name.contains(_q) || o.code.contains(_q)).toList();
    if (orphans.isNotEmpty && (_quick == _Quick.none || _quick == _Quick.unlinked)) {
      children.add(GroupHeader(title: 'طلاب بلا معلم', count: orphans.length, color: AppTheme.warning, expanded: !_collapsed.contains('_orphans'), onTap: () => setState(() => _collapsed.contains('_orphans') ? _collapsed.remove('_orphans') : _collapsed.add('_orphans'))));
      if (!_collapsed.contains('_orphans')) {
        for (final o in orphans) {
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  InitialAvatar(name: o.name, color: AppTheme.warning, size: 38),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                        Text('${o.code} • سجل جذر بلا معلم يضمّه', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'حذف السجل',
                    icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger),
                    onPressed: () async {
                      final ok = await showStudentConfirm(context, title: 'حذف السجل اليتيم؟', message: 'سيُحذف سجل الدخول ${o.code} لعدم ارتباطه بأي معلم.', confirmLabel: 'حذف', icon: Icons.delete_forever_rounded, color: AppTheme.danger);
                      if (ok && context.mounted) await runAdminAction(context, () => repo.deleteOrphan(o.code), success: 'تم الحذف');
                    },
                  ),
                ],
              ),
            ),
          ));
        }
      }
    }

    return ListView(
      key: const ValueKey('bt'),
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
      children: children,
    );
  }

  // ------------------------------------------------------------------
  // كل الطلاب
  // ------------------------------------------------------------------
  Widget _students(AdminRepository repo, ColorScheme scheme) {
    final list = _sortStudents(repo.allStudents.where(_matchStudent).toList(), repo);
    final totalOwed = list.where((s) => s.owes).fold(0.0, (a, s) => a + s.balance);
    return ListView(
      key: const ValueKey('st'),
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
          child: Text('${list.length} طالب${totalOwed > 0 ? ' • مستحقات ${TimelineFormat.money(totalOwed)}' : ''}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
        ),
        if (list.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 40), child: TimelineEmptyState(icon: Icons.school_outlined, title: 'لا نتائج'))
        else
          for (final (i, s) in list.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: StaggeredReveal(
                index: i,
                child: StudentRow(student: s, showTeacher: true, teacherName: repo.teacher(s.teacherCode)?.name, onTap: () => _openStudent(s.code)),
              ),
            ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // المعلمون (مسطح)
  // ------------------------------------------------------------------
  Widget _teachers(AdminRepository repo, ColorScheme scheme) {
    final list = _sortTeachers(repo.teachers.where(_matchTeacher).toList());
    final now = DateTime.now();
    return ListView(
      key: const ValueKey('tc'),
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
      children: [
        if (list.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 40), child: TimelineEmptyState(icon: Icons.co_present_outlined, title: 'لا نتائج'))
        else
          for (final (i, t) in list.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: StaggeredReveal(
                index: i,
                child: SoftCard(
                  onTap: () => _openTeacher(t.code),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      InitialAvatar(name: t.name, color: teacherHue(t.code), size: 48, disabled: t.disabled),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                                if (t.disabled) ...[const SizedBox(width: 6), const Tag(label: 'معطّل', color: AppTheme.danger)],
                                if (t.hasRunningLesson) ...[const SizedBox(width: 6), PulsingDot(color: TimelineStatus.started.color)],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('${t.students.length} طالب • ${t.endedIn(now)} درس هذا الشهر • ${t.code}', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Tag(label: TimelineFormat.money(t.revenueIn(now)), color: AppTheme.success, icon: Icons.payments_rounded),
                                const SizedBox(width: 6),
                                if (t.owed > 0) Tag(label: TimelineFormat.money(t.owed), color: AppTheme.danger, icon: Icons.trending_down_rounded),
                                if (t.pendingCount > 0) ...[const SizedBox(width: 6), Tag(label: '${t.pendingCount}', color: TimelineStatus.pending.color, icon: Icons.hourglass_top_rounded)],
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_left_rounded, color: scheme.outline),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // الإدارة
  // ------------------------------------------------------------------
  Widget _admins(AdminRepository repo, ColorScheme scheme) {
    final list = repo.admins.where((a) => _q.isEmpty || a.name.contains(_q) || a.code.contains(_q)).toList();
    return ListView(
      key: const ValueKey('ad'),
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
      children: [
        for (final (i, a) in list.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: StaggeredReveal(
              index: i,
              child: SoftCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    InitialAvatar(name: a.name, color: RoleColors.admin, size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                              if (a.code == repo.adminCode) ...[const SizedBox(width: 6), const Tag(label: 'أنت', color: RoleColors.admin)],
                            ],
                          ),
                          Text('${a.code}${a.createdAt != null ? ' • منذ ${TimelineFormat.monthName(a.createdAt!)} ${a.createdAt!.year}' : ''}', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    if (a.code != repo.adminCode)
                      PopupMenuButton<String>(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        onSelected: (v) async {
                          if (v == 'name') {
                            final n = await showEditFieldSheet(context, title: 'تعديل الاسم', label: 'الاسم', value: a.name, icon: Icons.person_rounded);
                            if (n != null && n.isNotEmpty && context.mounted) await runAdminAction(context, () => repo.updateAccount(a.code, {'name': n}, label: 'الاسم'));
                          } else if (v == 'delete') {
                            final ok = await showStudentConfirm(context, title: 'حذف حساب الإدارة؟', message: 'سيفقد ${a.name} صلاحية الدخول للوحة.', confirmLabel: 'حذف', icon: Icons.delete_forever_rounded, color: AppTheme.danger);
                            if (ok && context.mounted) await runAdminAction(context, () => repo.deleteAdmin(a.code), success: 'تم الحذف');
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'name', child: Text('تعديل الاسم')),
                          PopupMenuItem(value: 'delete', child: Text('حذف', style: TextStyle(color: AppTheme.danger))),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          onPressed: () => showCreateAdminSheet(context, repo),
          icon: const Icon(Icons.add_moderator_rounded),
          label: const Text('إضافة حساب إدارة'),
        ),
      ],
    );
  }
}

/// بطاقة معلم قابلة للطي تحوي طلابه.
class _TeacherGroupCard extends StatelessWidget {
  const _TeacherGroupCard({
    required this.teacher,
    required this.hue,
    required this.collapsed,
    required this.shownStudents,
    required this.onToggle,
    required this.onOpen,
    required this.onAddStudent,
    required this.onStudent,
  });
  final AdminTeacher teacher;
  final Color hue;
  final bool collapsed;
  final List<AdminStudent> shownStudents;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final VoidCallback onAddStudent;
  final ValueChanged<String> onStudent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = teacher;
    final now = DateTime.now();
    return SoftCard(
      padding: EdgeInsets.zero,
      glow: t.hasRunningLesson ? TimelineStatus.started.color : null,
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusMd)),
            onTap: onOpen,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [hue.withValues(alpha: 0.14), hue.withValues(alpha: 0.03)], begin: AlignmentDirectional.centerStart, end: AlignmentDirectional.centerEnd),
                borderRadius: BorderRadius.vertical(top: const Radius.circular(AppTheme.radiusMd), bottom: collapsed ? const Radius.circular(AppTheme.radiusMd) : Radius.zero),
              ),
              child: Row(
                children: [
                  InitialAvatar(name: t.name, color: hue, size: 44, disabled: t.disabled),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                            const SizedBox(width: 6),
                            if (t.hasRunningLesson) PulsingDot(color: TimelineStatus.started.color),
                            if (t.disabled) const Tag(label: 'معطّل', color: AppTheme.danger),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${t.students.length} طالب • ${TimelineFormat.money(t.revenueIn(now))} هذا الشهر${t.owed > 0 ? ' • مستحق ${TimelineFormat.money(t.owed)}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(tooltip: 'إضافة طالب', visualDensity: VisualDensity.compact, onPressed: onAddStudent, icon: Icon(Icons.person_add_alt_1_rounded, color: hue, size: 20)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: onToggle,
                    icon: AnimatedRotation(turns: collapsed ? 0 : 0.5, duration: const Duration(milliseconds: 240), child: Icon(Icons.expand_more_rounded, color: scheme.outline)),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: collapsed
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: shownStudents.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.groups_outlined, size: 16, color: scheme.outline),
                                const SizedBox(width: 6),
                                Text('لا يوجد طلاب', style: TextStyle(fontSize: 12, color: scheme.outline)),
                              ],
                            ),
                          )
                        : Column(
                            children: [
                              for (final s in shownStudents.take(30))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: StudentRow(student: s, onTap: () => onStudent(s.code)),
                                ),
                              if (shownStudents.length > 30)
                                TextButton(onPressed: onOpen, child: Text('عرض كل ${shownStudents.length} طالب')),
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
