// lib/src/pages/student/student_widgets.dart
import 'package:flutter/material.dart';

import '../../services/student_repository.dart';
import '../../services/timeline_models.dart';
import '../../theme/app_theme.dart';
import '../timeline/timeline_widgets.dart';

export '../timeline/timeline_widgets.dart'
    show
        PressScale,
        StaggeredReveal,
        StatusChip,
        PulsingDot,
        TimelineEmptyState,
        SheetHeader,
        SheetSection,
        PillChoice,
        MiniStat,
        timelineHaptic;

/// بطاقة سطحية موحّدة لواجهة الطالب.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.glow,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? glow;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161A23) : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: (glow ?? Colors.black).withValues(alpha: glow == null ? (isDark ? 0.25 : 0.04) : 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return PressScale(onTap: onTap, scale: 0.98, child: card);
  }
}

/// عنوان قسم مع زر «الكل» اختياري.
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: scheme.primary),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel!, style: const TextStyle(fontSize: 12.5)),
                  if (onAction != null)
                    const Icon(Icons.chevron_left_rounded, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// رقم متحرك.
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber({
    super.key,
    required this.value,
    required this.style,
    this.suffix = '',
    this.decimals = 0,
  });

  final double value;
  final TextStyle style;
  final String suffix;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        '${_fmt(v)}$suffix',
        style: style,
      ),
    );
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(decimals);
    // فواصل الآلاف
    final parts = s.split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (m) => ',',
    );
    return parts.length > 1 ? '$intPart.${parts[1]}' : intPart;
  }
}

/// بطاقة درس للطالب.
class StudentLessonTile extends StatelessWidget {
  const StudentLessonTile({
    super.key,
    required this.lesson,
    required this.onTap,
    this.use24h = false,
    this.showPaid = true,
    this.dense = false,
  });

  final StudentLesson lesson;
  final VoidCallback onTap;
  final bool use24h;
  final bool showPaid;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = lesson.status;
    final color = status.color;
    final muted = status == TimelineStatus.canceled;

    return SoftCard(
      onTap: onTap,
      padding: EdgeInsets.fromLTRB(12, dense ? 10 : 12, 14, dense ? 10 : 12),
      child: Opacity(
        opacity: muted ? 0.6 : 1,
        child: Row(
          children: [
            // مربّع التاريخ
            Container(
              width: 50,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '${lesson.start.day}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: color,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    TimelineFormat.monthName(lesson.start).substring(0, 3),
                    style: TextStyle(fontSize: 10, color: color, height: 1.2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          TimelineFormat.relativeDay(lesson.start),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            decoration: muted ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      if (lesson.isRunning) const PulsingDot(color: Color(0xFFF97316), size: 7),
                      StatusChip(status: status, compact: true),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 13, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${TimelineFormat.range(lesson.start, lesson.end, use24h: use24h)} • ${TimelineFormat.duration(lesson.minutes)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  if (!dense && (lesson.note.isNotEmpty || lesson.cancelReason.isNotEmpty)) ...[
                    const SizedBox(height: 3),
                    Text(
                      lesson.cancelReason.isNotEmpty ? lesson.cancelReason : lesson.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ],
                ],
              ),
            ),
            if (lesson.isEnded) ...[
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    TimelineFormat.money(lesson.amount),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  if (showPaid)
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: (lesson.isPaid ? AppTheme.success : AppTheme.danger).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        lesson.isPaid ? 'مدفوع' : 'غير مدفوع',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: lesson.isPaid ? AppTheme.success : AppTheme.danger,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// بطاقة دفعة للطالب.
class StudentPaymentTile extends StatelessWidget {
  const StudentPaymentTile({super.key, required this.payment, this.onTap});

  final StudentPayment payment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fromStudent = payment.fromStudent;
    final color = fromStudent ? AppTheme.success : const Color(0xFFF97316);
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, Color.alphaBlend(Colors.white24, color)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              fromStudent ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fromStudent ? 'دفعة مسدّدة' : 'مبلغ مُرجَع من المعلم',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (payment.date != null) TimelineFormat.relativeDay(payment.date!),
                    payment.methodLabel,
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
                if (payment.note.isNotEmpty)
                  Text(
                    payment.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: scheme.outline),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${fromStudent ? '+' : '−'}${TimelineFormat.money(payment.amount)}',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

/// شريط تقدّم ملوّن.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 8,
    this.background,
  });

  final double value;
  final Color color;
  final double height;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(builder: (context, c) {
          return Stack(
            children: [
              Container(color: background ?? color.withValues(alpha: 0.15)),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value.clamp(0, 1)),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Container(
                  width: c.maxWidth * v,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, Color.alphaBlend(Colors.white30, color)],
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// صف معلومة (أيقونة + عنوان + قيمة).
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: c),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing! else if (onTap != null) Icon(Icons.chevron_left_rounded, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

/// نوع الرصيد كنص ولون.
({String label, Color color, IconData icon}) balanceTone(double balance) {
  if (balance > 0.5) {
    return (label: 'مستحق عليك', color: AppTheme.danger, icon: Icons.trending_down_rounded);
  }
  if (balance < -0.5) {
    return (label: 'رصيد زائد لك', color: AppTheme.success, icon: Icons.trending_up_rounded);
  }
  return (label: 'حسابك مسدّد بالكامل', color: AppTheme.success, icon: Icons.verified_rounded);
}
