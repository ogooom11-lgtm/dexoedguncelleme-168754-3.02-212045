// lib/src/pages/admin/admin_widgets.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/admin_repository.dart';
import '../../services/timeline_models.dart';
import '../../theme/app_theme.dart';
import '../student/student_widgets.dart';

/// يفتح صفحة إدارية مع تمرير [AdminRepository] لها (الصفحات المدفوعة تخرج من شجرة الـ Provider).
Future<T?> pushAdminPage<T>(BuildContext context, Widget page) {
  final repo = context.read<AdminRepository>();
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) => ChangeNotifierProvider<AdminRepository>.value(value: repo, child: page),
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

export '../student/student_widgets.dart';

/// ألوان الأدوار.
class RoleColors {
  RoleColors._();
  static const admin = Color(0xFF8B5CF6);
  static const teacher = Color(0xFF0D9488);
  static const student = Color(0xFFF97316);

  static Color of(String role) => switch (role) {
        'admin' => admin,
        'teacher' => teacher,
        _ => student,
      };

  static String label(String role) => switch (role) {
        'admin' => 'إدارة',
        'teacher' => 'معلم',
        _ => 'طالب',
      };
}

/// لون ثابت لكل معلم (حسب الكود) لتمييزه في القوائم.
Color teacherHue(String code) {
  const palette = [
    Color(0xFF3B5BFE),
    Color(0xFF0D9488),
    Color(0xFFDB2777),
    Color(0xFFF59E0B),
    Color(0xFF7C3AED),
    Color(0xFF0891B2),
    Color(0xFF65A30D),
    Color(0xFFEA580C),
  ];
  var h = 0;
  for (final c in code.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

/// صورة رمزية بحرف أول + حلقة لونية.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({
    super.key,
    required this.name,
    required this.color,
    this.size = 44,
    this.disabled = false,
    this.badge,
  });
  final String name;
  final Color color;
  final double size;
  final bool disabled;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final ch = name.trim().isEmpty ? '؟' : name.trim().characters.first;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: disabled
                  ? [Colors.grey.shade400, Colors.grey.shade600]
                  : [color.withValues(alpha: 0.85), color],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (disabled ? Colors.grey : color).withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            ch,
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.42,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (badge != null)
          PositionedDirectional(bottom: -2, end: -2, child: badge!),
      ],
    );
  }
}

/// بطاقة إحصائية متدرجة كبيرة.
class GradientStat extends StatelessWidget {
  const GradientStat({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.suffix = '',
    this.subtitle,
    this.onTap,
    this.decimals = 0,
  });
  final IconData icon;
  final String label;
  final double value;
  final Color color;
  final String suffix;
  final String? subtitle;
  final VoidCallback? onTap;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      enabled: onTap != null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, Color.lerp(color, Colors.black, 0.22)!],
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                const Spacer(),
                if (onTap != null)
                  Icon(Icons.chevron_left_rounded,
                      color: Colors.white.withValues(alpha: 0.7), size: 18),
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: AnimatedNumber(
                value: value,
                decimals: decimals,
                suffix: suffix,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700)),
            if (subtitle != null)
              Text(subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 10.5)),
          ],
        ),
      ),
    );
  }
}

/// رسم أعمدة بسيط متحرك (بدون حزم خارجية).
class MiniBarChart extends StatelessWidget {
  const MiniBarChart({
    super.key,
    required this.items,
    required this.color,
    this.height = 120,
    this.valueLabel,
  });
  final List<({String label, double value})> items;
  final Color color;
  final double height;
  final String Function(double)? valueLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final max = items.fold<double>(0, (m, e) => e.value > m ? e.value : m);
    final lastIndex = items.length - 1;
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (valueLabel != null)
                      Text(
                        valueLabel!(items[i].value),
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: i == lastIndex ? color : scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 4),
                    TweenAnimationBuilder<double>(
                      tween: Tween(
                          begin: 0,
                          end: max <= 0 ? 0.04 : (items[i].value / max).clamp(0.04, 1.0)),
                      duration: Duration(milliseconds: 500 + i * 80),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, __) => Container(
                        height: (height - 38) * v,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: i == lastIndex
                                ? [color, color.withValues(alpha: 0.7)]
                                : [
                                    color.withValues(alpha: 0.45),
                                    color.withValues(alpha: 0.2)
                                  ],
                          ),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      items[i].label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            i == lastIndex ? FontWeight.w800 : FontWeight.w600,
                        color: i == lastIndex ? color : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// شارة صغيرة ملوّنة (نص + أيقونة).
class Tag extends StatelessWidget {
  const Tag({super.key, required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

/// صف طالب مضغوط (يُستخدم داخل بطاقة المعلم وفي قائمة الطلاب).
class StudentRow extends StatelessWidget {
  const StudentRow({
    super.key,
    required this.student,
    required this.onTap,
    this.showTeacher = false,
    this.teacherName,
  });
  final AdminStudent student;
  final VoidCallback onTap;
  final bool showTeacher;
  final String? teacherName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = student;
    final tone = balanceTone(s.balance);
    return PressScale(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            InitialAvatar(
              name: s.name,
              color: s.gender == 'female' ? const Color(0xFFEC4899) : RoleColors.student,
              size: 38,
              disabled: s.disabled,
              badge: s.linked
                  ? null
                  : Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                          color: AppTheme.warning,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.surface, width: 1.5)),
                      child: const Icon(Icons.link_off_rounded,
                          size: 9, color: Colors.white),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                decoration: s.disabled
                                    ? TextDecoration.lineThrough
                                    : null)),
                      ),
                      if (s.pendingCount > 0) ...[
                        const SizedBox(width: 6),
                        Tag(
                            label: '${s.pendingCount} طلب',
                            color: TimelineStatus.pending.color,
                            icon: Icons.hourglass_top_rounded),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    showTeacher && teacherName != null
                        ? '$teacherName • ${s.endedCount} درس • ${TimelineFormat.duration(s.minutes)}'
                        : '${s.code} • ${s.endedCount} درس • ${TimelineFormat.duration(s.minutes)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  s.balance.abs() < 0.5
                      ? 'مسدّد'
                      : TimelineFormat.money(s.balance.abs()),
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: tone.color),
                ),
                Text(
                  s.balance.abs() < 0.5 ? '' : (s.owes ? 'مستحق' : 'زائد'),
                  style: TextStyle(fontSize: 10, color: tone.color),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// صف درس مضغوط.
class LessonRow extends StatelessWidget {
  const LessonRow({super.key, required this.lesson, this.subtitle, this.onTap});
  final AdminLesson lesson;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = lesson;
    final color = l.status.color;
    return PressScale(
      onTap: onTap,
      enabled: onTap != null,
      scale: 0.98,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 36,
              margin: const EdgeInsetsDirectional.only(end: 8),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
            ),
            Container(
              width: 40,
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: [
                  Text('${l.start.day}',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: color,
                          height: 1)),
                  Text(TimelineFormat.monthName(l.start),
                      maxLines: 1,
                      style: TextStyle(fontSize: 8.5, color: color)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TimelineFormat.range(l.start, l.end, use24h: false),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle ?? TimelineFormat.duration(l.minutes),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusChip(status: l.status, compact: true),
                if (l.isEnded) ...[
                  const SizedBox(height: 4),
                  Text(TimelineFormat.money(l.amount),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// مبدّل مقطعي أنيق.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
  });
  final List<({T value, String label, IconData? icon})> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final it in items)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  timelineHaptic(true);
                  onChanged(it.value);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: it.value == value ? scheme.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: it.value == value
                        ? [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 6,
                                offset: const Offset(0, 2))
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (it.icon != null) ...[
                        Icon(it.icon,
                            size: 15,
                            color: it.value == value
                                ? scheme.primary
                                : scheme.onSurfaceVariant),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        it.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: it.value == value
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// زر ترتيب بقائمة منبثقة.
class SortButton<T> extends StatelessWidget {
  const SortButton({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final List<({T value, String label, IconData icon})> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cur = options.firstWhere((o) => o.value == value);
    return PopupMenuButton<T>(
      tooltip: 'ترتيب',
      onSelected: onChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (_) => [
        for (final o in options)
          PopupMenuItem<T>(
            value: o.value,
            child: Row(
              children: [
                Icon(o.icon,
                    size: 18,
                    color: o.value == value ? scheme.primary : null),
                const SizedBox(width: 10),
                Text(o.label,
                    style: TextStyle(
                        fontWeight: o.value == value
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: o.value == value ? scheme.primary : null)),
                if (o.value == value) ...[
                  const Spacer(),
                  Icon(Icons.check_rounded, size: 18, color: scheme.primary),
                ],
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert_rounded, size: 16, color: scheme.primary),
            const SizedBox(width: 4),
            Text(cur.label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary)),
          ],
        ),
      ),
    );
  }
}

/// حقل بحث موحّد.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: 13, color: scheme.outline),
          prefixIcon: Icon(Icons.search_rounded, color: scheme.outline, size: 20),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

/// ترويسة قسم قابلة للطي (لتجميع الطلاب حسب المعلم مثلاً).
class GroupHeader extends StatelessWidget {
  const GroupHeader({
    super.key,
    required this.title,
    required this.count,
    required this.color,
    required this.expanded,
    required this.onTap,
    this.trailing,
  });
  final String title;
  final int count;
  final Color color;
  final bool expanded;
  final VoidCallback onTap;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        timelineHaptic(true);
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w800)),
            ),
            if (trailing != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Text(trailing!,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999)),
              child: Text('$count',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800, color: color)),
            ),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 240),
              child: Icon(Icons.expand_more_rounded, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
