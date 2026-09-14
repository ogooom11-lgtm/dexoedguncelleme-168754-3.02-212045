// lib/src/pages/admin/admin_teacher_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/admin_repository.dart';
import '../../services/timeline_models.dart';
import '../../theme/app_theme.dart';
import 'admin_sheets.dart';
import 'admin_student_page.dart';
import 'admin_widgets.dart';

/// 👨‍🏫 صفحة معلم: نظرة عامة + طلابه + دروسه + الصلاحيات والإجراءات.
class AdminTeacherPage extends StatefulWidget {
  const AdminTeacherPage({super.key, required this.teacherCode});
  final String teacherCode;

  @override
  State<AdminTeacherPage> createState() => _AdminTeacherPageState();
}

enum _StudentSort { name, balance, lessons, recent }

class _AdminTeacherPageState extends State<AdminTeacherPage> {
  int _tab = 0;
  _StudentSort _sort = _StudentSort.balance;
  String _q = '';
  final _search = TextEditingController();
  int _lessonFilter = 0; // 0 الكل 1 اليوم 2 قادمة 3 منتهية 4 طلبات

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<AdminStudent> _students(AdminTeacher t) {
    var list = t.students.where((s) {
      if (_q.isEmpty) return true;
      return s.name.contains(_q) || s.code.contains(_q) || s.phone.contains(_q);
    }).toList();
    switch (_sort) {
      case _StudentSort.name:
        list.sort((a, b) => a.name.compareTo(b.name));
      case _StudentSort.balance:
        list.sort((a, b) => b.balance.compareTo(a.balance));
      case _StudentSort.lessons:
        list.sort((a, b) => b.endedCount.compareTo(a.endedCount));
      case _StudentSort.recent:
        list.sort((a, b) => (b.lastLessonAt ?? DateTime(2000)).compareTo(a.lastLessonAt ?? DateTime(2000)));
    }
    return list;
  }

  List<AdminLesson> _lessons(AdminTeacher t) {
    final now = DateTime.now();
    var list = t.lessons.where((l) {
      switch (_lessonFilter) {
        case 1:
          return TimelineFormat.isSameDay(l.start, now);
        case 2:
          return l.isUpcoming || l.isRunning;
        case 3:
          return l.isEnded;
        case 4:
          return l.isPending;
        default:
          return true;
      }
    }).toList();
    if (_lessonFilter == 2 || _lessonFilter == 4) {
      list.sort((a, b) => a.start.compareTo(b.start));
    } else {
      list.sort((a, b) => b.start.compareTo(a.start));
    }
    return list.take(150).toList();
  }

  Future<void> _menu(AdminTeacher t, AdminRepository repo) async {
    final action = await showStudentSheet<String>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: t.name, subtitle: 'الكود ${t.code}'),
            const SizedBox(height: 8),
            _ActionTile(icon: Icons.edit_rounded, label: 'تعديل الاسم', onTap: () => Navigator.pop(ctx, 'name')),
            _ActionTile(icon: Icons.phone_rounded, label: 'تعديل الهاتف', onTap: () => Navigator.pop(ctx, 'phone')),
            _ActionTile(icon: Icons.alternate_email_rounded, label: 'تعديل البريد', onTap: () => Navigator.pop(ctx, 'email')),
            _ActionTile(icon: Icons.verified_user_rounded, label: 'الصلاحيات', onTap: () => Navigator.pop(ctx, 'perms')),
            _ActionTile(icon: Icons.copy_rounded, label: 'نسخ الكود', onTap: () => Navigator.pop(ctx, 'copy')),
            _ActionTile(
              icon: t.disabled ? Icons.lock_open_rounded : Icons.block_rounded,
              label: t.disabled ? 'تفعيل الحساب' : 'تعطيل الحساب',
              color: t.disabled ? AppTheme.success : AppTheme.warning,
              onTap: () => Navigator.pop(ctx, 'toggle'),
            ),
            _ActionTile(icon: Icons.delete_forever_rounded, label: 'حذف المعلم', color: AppTheme.danger, onTap: () => Navigator.pop(ctx, 'delete')),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'name':
      case 'phone':
      case 'email':
        final labels = {'name': 'الاسم', 'phone': 'الهاتف', 'email': 'البريد'};
        final cur = {'name': t.name, 'phone': t.phone, 'email': t.email}[action]!;
        final v = await showEditFieldSheet(context, title: 'تعديل ${labels[action]}', label: labels[action]!, value: cur, ltr: action != 'name', keyboard: action == 'phone' ? TextInputType.phone : action == 'email' ? TextInputType.emailAddress : null);
        if (v == null || v == cur || !mounted) return;
        if (action == 'name' && v.isEmpty) return;
        await runAdminAction(context, () => repo.updateAccount(t.code, {action: v}, label: labels[action]));
      case 'perms':
        await showPermissionsSheet(context, repo, t);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: t.code));
        adminToast(context, 'تم نسخ الكود');
      case 'toggle':
        final ok = await showStudentConfirm(
          context,
          title: t.disabled ? 'تفعيل الحساب؟' : 'تعطيل الحساب؟',
          message: t.disabled ? 'سيتمكن المعلم من الدخول مجدداً.' : 'لن يتمكن المعلم من الدخول حتى تعيد تفعيله. بيانات الطلاب تبقى محفوظة.',
          confirmLabel: t.disabled ? 'تفعيل' : 'تعطيل',
          icon: t.disabled ? Icons.lock_open_rounded : Icons.block_rounded,
          color: t.disabled ? AppTheme.success : AppTheme.warning,
        );
        if (ok && mounted) await runAdminAction(context, () => repo.setDisabled(t.code, !t.disabled, name: t.name));
      case 'delete':
        final ok = await showStudentConfirm(
          context,
          title: 'حذف ${t.name}؟',
          message: 'سيُحذف المعلم مع ${t.students.length} طالب وجميع الدروس والدفعات. هذا الإجراء لا يمكن التراجع عنه.',
          confirmLabel: 'حذف نهائي',
          icon: Icons.delete_forever_rounded,
          color: AppTheme.danger,
        );
        if (ok && mounted) {
          final done = await runAdminAction(context, () => repo.deleteTeacher(t.code), success: 'تم حذف المعلم');
          if (done && mounted) Navigator.pop(context);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AdminRepository>();
    final t = repo.teacher(widget.teacherCode);
    final scheme = Theme.of(context).colorScheme;
    if (t == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const TimelineEmptyState(icon: Icons.person_off_rounded, title: 'المعلم غير موجود', subtitle: 'ربما تم حذفه.'),
      );
    }
    final hue = teacherHue(t.code);
    final month = DateTime.now();
    final chart = List.generate(6, (i) {
      final m = DateTime(month.year, month.month - (5 - i));
      return (label: TimelineFormat.monthName(m), value: t.revenueIn(m));
    });

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            backgroundColor: hue,
            foregroundColor: Colors.white,
            actions: [
              IconButton(tooltip: 'إجراءات', onPressed: () => _menu(t, repo), icon: const Icon(Icons.more_horiz_rounded)),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              titlePadding: const EdgeInsetsDirectional.only(start: 56, bottom: 14, end: 56),
              title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [hue, Color.lerp(hue, Colors.black, 0.3)!], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 52, 18, 44),
                    child: Row(
                      children: [
                        InitialAvatar(name: t.name, color: Colors.white.withValues(alpha: 0.25), size: 60, disabled: t.disabled),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Tag(label: 'معلم', color: Colors.white, icon: Icons.co_present_rounded),
                                  const SizedBox(width: 6),
                                  if (t.disabled) const Tag(label: 'معطّل', color: Colors.white, icon: Icons.block_rounded),
                                  if (!t.permissions.isFull) Tag(label: '${t.permissions.deniedCount} محجوبة', color: Colors.white, icon: Icons.lock_rounded),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text('الكود ${t.code}${t.phone.isNotEmpty ? ' • ${t.phone}' : ''}', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5)),
                              if (t.createdAt != null) Text('منذ ${TimelineFormat.monthName(t.createdAt!)} ${t.createdAt!.year}', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11.5)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(56),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                color: hue,
                child: Segmented<int>(
                  value: _tab,
                  onChanged: (v) => setState(() => _tab = v),
                  items: [
                    (value: 0, label: 'نظرة', icon: Icons.dashboard_rounded),
                    (value: 1, label: 'الطلاب ${t.students.length}', icon: Icons.groups_rounded),
                    (value: 2, label: 'الدروس', icon: Icons.menu_book_rounded),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: switch (_tab) {
            0 => _overview(t, repo, chart, scheme),
            1 => _studentsTab(t, repo, scheme),
            _ => _lessonsTab(t, repo, scheme),
          },
        ),
      ),
      floatingActionButton: _tab == 1
          ? FloatingActionButton.extended(
              heroTag: 'admin_add_student',
              onPressed: () => showStudentFormSheet(context, repo, teacherCode: t.code),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('إضافة طالب'),
            )
          : null,
    );
  }

  Widget _overview(AdminTeacher t, AdminRepository repo, List<({String label, double value})> chart, ColorScheme scheme) {
    final now = DateTime.now();
    final prev = DateTime(now.year, now.month - 1);
    final cur = t.revenueIn(now);
    final prevRev = t.revenueIn(prev);
    final growth = prevRev == 0 ? null : ((cur - prevRev) / prevRev * 100);
    return ListView(
      key: const ValueKey('ov'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
      physics: const BouncingScrollPhysics(),
      children: [
        StaggeredReveal(
          index: 0,
          child: Row(
            children: [
              Expanded(child: GradientStat(icon: Icons.payments_rounded, label: 'إيراد هذا الشهر', value: cur, color: AppTheme.success, subtitle: growth == null ? '${t.endedIn(now)} درس' : '${growth >= 0 ? '▲' : '▼'} ${growth.abs().toStringAsFixed(0)}% عن الشهر الماضي')),
              const SizedBox(width: 10),
              Expanded(child: GradientStat(icon: Icons.account_balance_wallet_rounded, label: 'مستحقات على الطلاب', value: t.owed, color: t.owed > 0 ? AppTheme.danger : scheme.primary, subtitle: '${t.owingStudents} طالب')),
            ],
          ),
        ),
        const SizedBox(height: 10),
        StaggeredReveal(
          index: 1,
          child: Row(
            children: [
              Expanded(child: MiniStat(icon: Icons.groups_rounded, label: 'طلاب نشطون', value: '${t.activeStudents}/${t.students.length}', color: RoleColors.student)),
              const SizedBox(width: 8),
              Expanded(child: MiniStat(icon: Icons.menu_book_rounded, label: 'دروس منتهية', value: '${t.endedCount}', color: TimelineStatus.ended.color)),
              const SizedBox(width: 8),
              Expanded(child: MiniStat(icon: Icons.timer_outlined, label: 'ساعات', value: (t.minutes / 60).toStringAsFixed(0), color: const Color(0xFF8B5CF6))),
            ],
          ),
        ),
        const SizedBox(height: 8),
        StaggeredReveal(
          index: 2,
          child: Row(
            children: [
              Expanded(child: MiniStat(icon: Icons.upcoming_rounded, label: 'قادمة', value: '${t.upcomingCount}', color: TimelineStatus.scheduled.color)),
              const SizedBox(width: 8),
              Expanded(child: MiniStat(icon: Icons.hourglass_top_rounded, label: 'طلبات معلّقة', value: '${t.pendingCount}', color: TimelineStatus.pending.color)),
              const SizedBox(width: 8),
              Expanded(child: MiniStat(icon: Icons.repeat_rounded, label: 'مواعيد متكررة', value: '${t.recurringCount}', color: TimelineStatus.recurring.color)),
            ],
          ),
        ),
        const SectionTitle(title: 'الإيراد خلال 6 أشهر', icon: Icons.bar_chart_rounded),
        StaggeredReveal(
          index: 3,
          child: SoftCard(
            child: MiniBarChart(items: chart, color: teacherHue(t.code), valueLabel: (v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toStringAsFixed(0)),
          ),
        ),
        SectionTitle(title: 'الصلاحيات', icon: Icons.verified_user_rounded, actionLabel: 'تعديل', onAction: () => showPermissionsSheet(context, repo, t)),
        StaggeredReveal(
          index: 4,
          child: SoftCard(
            onTap: () => showPermissionsSheet(context, repo, t),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in t.permissions.toMap().entries)
                  Tag(
                    label: _permLabel(p.key),
                    color: p.value == true ? AppTheme.success : scheme.outline,
                    icon: p.value == true ? Icons.check_rounded : Icons.close_rounded,
                  ),
              ],
            ),
          ),
        ),
        const SectionTitle(title: 'بيانات التواصل', icon: Icons.contact_phone_outlined),
        StaggeredReveal(
          index: 5,
          child: SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(
              children: [
                InfoRow(icon: Icons.key_rounded, label: 'الكود', value: t.code, trailing: const Icon(Icons.copy_rounded, size: 16), onTap: () {
                  Clipboard.setData(ClipboardData(text: t.code));
                  adminToast(context, 'تم نسخ الكود');
                }),
                InfoRow(icon: Icons.phone_rounded, label: 'الهاتف', value: t.phone.isEmpty ? 'غير مضاف' : t.phone),
                InfoRow(icon: Icons.alternate_email_rounded, label: 'البريد', value: t.email.isEmpty ? 'غير مضاف' : t.email),
              ],
            ),
          ),
        ),
        if (t.students.where((s) => s.owes).isNotEmpty) ...[
          SectionTitle(title: 'أعلى المستحقات', icon: Icons.trending_down_rounded, actionLabel: 'الكل', onAction: () => setState(() => _tab = 1)),
          for (final (i, s) in (t.students.where((s) => s.owes).toList()..sort((a, b) => b.balance.compareTo(a.balance))).take(3).indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: StaggeredReveal(index: 6 + i, child: StudentRow(student: s, onTap: () => _openStudent(s))),
            ),
        ],
      ],
    );
  }

  String _permLabel(String key) {
    const map = {
      'addStudents': 'إضافة طلاب',
      'deleteStudents': 'حذف طلاب',
      'editRates': 'تعديل الأسعار',
      'recordPayments': 'الدفعات',
      'deleteLessons': 'حذف الدروس',
      'recurringSchedules': 'المتكررة',
      'exportPdf': 'PDF',
      'editProfile': 'الملف الشخصي',
    };
    return map[key] ?? key;
  }

  void _openStudent(AdminStudent s) {
    pushAdminPage(context, AdminStudentPage(studentCode: s.code));
  }

  Widget _studentsTab(AdminTeacher t, AdminRepository repo, ColorScheme scheme) {
    final list = _students(t);
    return ListView(
      key: const ValueKey('st'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
      physics: const BouncingScrollPhysics(),
      children: [
        Row(
          children: [
            Expanded(child: SearchField(controller: _search, hint: 'ابحث بالاسم أو الكود…', onChanged: (v) => setState(() => _q = v.trim()))),
            const SizedBox(width: 8),
            SortButton<_StudentSort>(
              value: _sort,
              onChanged: (v) => setState(() => _sort = v),
              options: const [
                (value: _StudentSort.balance, label: 'الرصيد', icon: Icons.account_balance_wallet_rounded),
                (value: _StudentSort.name, label: 'الاسم', icon: Icons.sort_by_alpha_rounded),
                (value: _StudentSort.lessons, label: 'الدروس', icon: Icons.menu_book_rounded),
                (value: _StudentSort.recent, label: 'الأحدث', icon: Icons.history_rounded),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          TimelineEmptyState(icon: Icons.groups_outlined, title: _q.isEmpty ? 'لا يوجد طلاب بعد' : 'لا نتائج', subtitle: _q.isEmpty ? 'أضف أول طالب لهذا المعلم.' : null)
        else
          for (final (i, s) in list.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: StaggeredReveal(index: i, child: StudentRow(student: s, onTap: () => _openStudent(s))),
            ),
      ],
    );
  }

  Widget _lessonsTab(AdminTeacher t, AdminRepository repo, ColorScheme scheme) {
    final list = _lessons(t);
    final names = {for (final s in t.students) s.code: s.name};
    const filters = ['الكل', 'اليوم', 'القادمة', 'المنتهية', 'الطلبات'];
    return ListView(
      key: const ValueKey('ls'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
      physics: const BouncingScrollPhysics(),
      children: [
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              for (var i = 0; i < filters.length; i++)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: PillChoice(label: filters[i], selected: _lessonFilter == i, onTap: () => setState(() => _lessonFilter = i)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          const TimelineEmptyState(icon: Icons.event_busy_rounded, title: 'لا توجد دروس هنا')
        else
          for (final (i, l) in list.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: StaggeredReveal(
                index: i,
                child: LessonRow(
                  lesson: l,
                  subtitle: '${names[l.studentCode] ?? l.studentCode} • ${TimelineFormat.duration(l.minutes)}',
                  onTap: () => showAdminLessonSheet(context, repo, l, studentName: names[l.studentCode], teacherName: t.name),
                ),
              ),
            ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onSurface;
    return ListTile(
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: c),
      ),
      title: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c)),
      trailing: Icon(Icons.chevron_left_rounded, color: scheme.outline),
      onTap: onTap,
    );
  }
}
