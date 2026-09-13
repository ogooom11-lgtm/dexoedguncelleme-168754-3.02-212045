// lib/src/pages/timeline/timeline_lesson_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../services/timeline_models.dart';
import '../../services/timeline_preferences.dart';
import '../../theme/app_theme.dart';
import 'timeline_widgets.dart';

/// بطاقة درس كاملة (تُستخدم في القوائم) مع سحب لإجراءات سريعة.
class TimelineLessonCard extends StatelessWidget {
  const TimelineLessonCard({
    super.key,
    required this.lesson,
    required this.prefs,
    required this.accent,
    required this.onTap,
    this.onEnd,
    this.onCancel,
    this.onLongPress,
    this.showDate = false,
    this.dense = false,
  });

  final TimelineLesson lesson;
  final TimelinePreferencesData prefs;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback? onEnd;
  final VoidCallback? onCancel;
  final VoidCallback? onLongPress;
  final bool showDate;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final status = lesson.status;
    final actionable = status.isActionable;
    final card = _CardBody(
      lesson: lesson,
      prefs: prefs,
      accent: accent,
      onTap: onTap,
      onLongPress: onLongPress,
      showDate: showDate,
      dense: dense,
    );

    if (!actionable || (onEnd == null && onCancel == null)) return card;

    return Slidable(
      key: ValueKey(lesson.uiKey),
      groupTag: 'timeline',
      startActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.48,
        children: [
          if (onEnd != null)
            SlidableAction(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              onPressed: (_) => onEnd!(),
              backgroundColor: AppTheme.success,
              foregroundColor: Colors.white,
              icon: Icons.check_circle_rounded,
              label: 'تم',
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
          if (onCancel != null)
            SlidableAction(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              onPressed: (_) => onCancel!(),
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              icon: Icons.cancel_rounded,
              label: 'إلغاء',
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
        ],
      ),
      child: card,
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.lesson,
    required this.prefs,
    required this.accent,
    required this.onTap,
    required this.onLongPress,
    required this.showDate,
    required this.dense,
  });

  final TimelineLesson lesson;
  final TimelinePreferencesData prefs;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showDate;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = lesson.status;
    final muted = status == TimelineStatus.canceled;
    final isRunning = status == TimelineStatus.started;
    final isVirtual = lesson.isVirtual;

    final bg = isDark ? const Color(0xFF161A23) : Colors.white;

    return PressScale(
      onTap: onTap,
      onLongPress: onLongPress,
      scale: 0.975,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: muted ? 0.62 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(
              color: isRunning
                  ? status.color.withValues(alpha: 0.6)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.05)),
              width: isRunning ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: (isRunning ? status.color : accent)
                    .withValues(alpha: isRunning ? 0.18 : 0.07),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // الشريط الجانبي الملوّن
                  Container(
                    width: 5,
                    decoration: BoxDecoration(
                      color: accent,
                      gradient: isVirtual
                          ? null
                          : LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                accent,
                                Color.alphaBlend(
                                    Colors.black.withValues(alpha: 0.15),
                                    accent),
                              ],
                            ),
                    ),
                    child: isVirtual
                        ? CustomPaint(
                            painter: _DashedBarPainter(color: bg),
                          )
                        : null,
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                          12, dense ? 9 : 12, 12, dense ? 9 : 12),
                      child: Row(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              StudentAvatar(
                                name: lesson.studentName,
                                color: accent,
                                size: dense ? 38 : 44,
                              ),
                              PositionedDirectional(
                                end: -4,
                                bottom: -4,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 350),
                                  transitionBuilder: (c, a) => ScaleTransition(
                                    scale: CurvedAnimation(
                                        parent: a, curve: Curves.easeOutBack),
                                    child: c,
                                  ),
                                  child: Container(
                                    key: ValueKey(status),
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: status.color,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: bg, width: 2),
                                    ),
                                    child: Icon(
                                      status.icon,
                                      size: 11,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        lesson.studentName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: dense ? 14 : 15,
                                          fontWeight: FontWeight.w800,
                                          decoration: muted
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                    ),
                                    if (isRunning)
                                      const PulsingDot(
                                          color: Color(0xFFF97316), size: 8),
                                    StatusChip(status: status, compact: true),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.schedule_rounded,
                                        size: 13,
                                        color: scheme.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        showDate
                                            ? '${TimelineFormat.relativeDay(lesson.start)} • ${TimelineFormat.range(lesson.start, lesson.end, use24h: prefs.use24h)}'
                                            : TimelineFormat.range(
                                                lesson.start, lesson.end,
                                                use24h: prefs.use24h),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        TimelineFormat.duration(
                                            lesson.minutes),
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: accent,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (!dense &&
                                    (lesson.note.isNotEmpty ||
                                        lesson.cancelReason.isNotEmpty ||
                                        lesson.recurring != null)) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        lesson.cancelReason.isNotEmpty
                                            ? Icons.info_outline_rounded
                                            : lesson.note.isNotEmpty
                                                ? Icons.sticky_note_2_outlined
                                                : Icons.event_repeat_rounded,
                                        size: 12,
                                        color: scheme.outline,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          lesson.cancelReason.isNotEmpty
                                              ? lesson.cancelReason
                                              : lesson.note.isNotEmpty
                                                  ? lesson.note
                                                  : TimelineFormat.repeatLabel(
                                                      lesson.recurring!),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: scheme.outline,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (prefs.showAmounts &&
                              status != TimelineStatus.canceled) ...[
                            const SizedBox(width: 8),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  TimelineFormat.money(lesson.displayAmount),
                                  style: TextStyle(
                                    fontSize: dense ? 12.5 : 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: status == TimelineStatus.ended
                                        ? AppTheme.success
                                        : scheme.onSurface,
                                  ),
                                ),
                                Text(
                                  status == TimelineStatus.ended
                                      ? 'فعلي'
                                      : 'تقديري',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: scheme.outline,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBarPainter extends CustomPainter {
  _DashedBarPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.55);
    const dash = 5.0;
    const gap = 4.0;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawRect(Rect.fromLTWH(0, y + dash, size.width, gap), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBarPainter old) => old.color != color;
}

/// كتلة مضغوطة للدرس داخل الخط الزمني (اليومي والأسبوعي).
class TimelineBlock extends StatelessWidget {
  const TimelineBlock({
    super.key,
    required this.lesson,
    required this.accent,
    required this.prefs,
    required this.onTap,
    this.onLongPress,
    this.compact = false,
  });

  final TimelineLesson lesson;
  final Color accent;
  final TimelinePreferencesData prefs;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// وضع الأسبوع (عرض ضيق جداً).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final status = lesson.status;
    final muted = status == TimelineStatus.canceled;
    final isVirtual = lesson.isVirtual;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PressScale(
      onTap: onTap,
      onLongPress: onLongPress,
      scale: 0.95,
      child: LayoutBuilder(builder: (context, c) {
        final tiny = c.maxHeight < 34;
        final showTime = c.maxHeight >= 52 && !compact;
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: muted ? 0.55 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: isVirtual
                  ? accent.withValues(alpha: isDark ? 0.14 : 0.10)
                  : accent.withValues(alpha: isDark ? 0.28 : 0.16),
              borderRadius: BorderRadius.circular(compact ? 7 : 11),
              border: Border.all(
                color: accent.withValues(alpha: isVirtual ? 0.55 : 0.35),
                width: 1,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            child: Stack(
              children: [
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: compact ? 3 : 4,
                    color: accent,
                  ),
                ),
                if (status == TimelineStatus.ended)
                  PositionedDirectional(
                    end: 4,
                    top: 3,
                    child: Icon(Icons.check_circle_rounded,
                        size: compact ? 10 : 13, color: status.color),
                  )
                else if (status == TimelineStatus.canceled)
                  PositionedDirectional(
                    end: 4,
                    top: 3,
                    child: Icon(Icons.cancel_rounded,
                        size: compact ? 10 : 13, color: status.color),
                  )
                else if (status == TimelineStatus.missed)
                  PositionedDirectional(
                    end: 4,
                    top: 3,
                    child: Icon(Icons.error_rounded,
                        size: compact ? 10 : 13, color: status.color),
                  )
                else if (status == TimelineStatus.started)
                  const PositionedDirectional(
                    end: 0,
                    top: 0,
                    child: PulsingDot(color: Color(0xFFF97316), size: 6),
                  )
                else if (isVirtual)
                  PositionedDirectional(
                    end: 4,
                    top: 3,
                    child: Icon(Icons.event_repeat_rounded,
                        size: compact ? 10 : 13, color: accent),
                  ),
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                      compact ? 6 : 10, tiny ? 2 : 5, compact ? 3 : 18, 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        compact && c.maxWidth < 56
                            ? lesson.studentName.trim().split(' ').first
                            : lesson.studentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 9.5 : (tiny ? 11 : 12.5),
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? Colors.white
                              : Color.alphaBlend(
                                  Colors.black.withValues(alpha: 0.45),
                                  accent),
                          height: 1.2,
                          decoration:
                              muted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (showTime)
                        Text(
                          TimelineFormat.range(lesson.start, lesson.end,
                              use24h: prefs.use24h),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark
                                ? Colors.white70
                                : Color.alphaBlend(
                                    Colors.black.withValues(alpha: 0.3),
                                    accent),
                            height: 1.3,
                          ),
                        ),
                      if (showTime && c.maxHeight >= 72)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: StatusChip(status: status, compact: true),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
