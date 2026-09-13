// lib/src/pages/timeline/timeline_day_view.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../services/timeline_models.dart';
import '../../services/timeline_preferences.dart';
import '../../theme/app_theme.dart';
import 'timeline_lesson_card.dart';
import 'timeline_widgets.dart';

typedef LessonCallback = void Function(TimelineLesson lesson);
typedef AccentResolver = Color Function(TimelineLesson lesson);
typedef FreeSlotCallback = void Function(DateTime start, DateTime end);

/// توزيع الدروس المتداخلة على أعمدة جانبية.
class LaidOutLesson {
  final TimelineLesson lesson;
  final int column;
  final int columns;
  const LaidOutLesson(this.lesson, this.column, this.columns);
}

List<LaidOutLesson> layoutOverlaps(List<TimelineLesson> lessons) {
  final sorted = [...lessons]..sort((a, b) => a.start.compareTo(b.start));
  final result = <LaidOutLesson>[];
  var cluster = <TimelineLesson>[];
  DateTime? clusterEnd;

  void flush() {
    if (cluster.isEmpty) return;
    final columnEnds = <DateTime>[];
    final assigned = <TimelineLesson, int>{};
    for (final l in cluster) {
      var placed = false;
      for (var i = 0; i < columnEnds.length; i++) {
        if (!l.start.isBefore(columnEnds[i])) {
          columnEnds[i] = l.end;
          assigned[l] = i;
          placed = true;
          break;
        }
      }
      if (!placed) {
        columnEnds.add(l.end);
        assigned[l] = columnEnds.length - 1;
      }
    }
    for (final l in cluster) {
      result.add(LaidOutLesson(l, assigned[l]!, columnEnds.length));
    }
    cluster = [];
    clusterEnd = null;
  }

  for (final l in sorted) {
    if (clusterEnd == null || l.start.isBefore(clusterEnd!)) {
      cluster.add(l);
      if (clusterEnd == null || l.end.isAfter(clusterEnd!)) clusterEnd = l.end;
    } else {
      flush();
      cluster.add(l);
      clusterEnd = l.end;
    }
  }
  flush();
  return result;
}

/// نطاق الساعات المعروض (يتوسّع تلقائياً ليشمل الدروس خارج ساعات العمل).
({int start, int end}) visibleHourRange(
  TimelinePreferencesData prefs,
  Iterable<TimelineLesson> lessons,
) {
  var start = prefs.startHour;
  var end = prefs.endHour;
  for (final l in lessons) {
    if (l.start.hour < start) start = l.start.hour;
    final endHour = l.end.minute > 0 || l.end.second > 0
        ? l.end.hour + 1
        : l.end.hour;
    final sameDayEnd = TimelineFormat.isSameDay(l.end, l.start) ? endHour : 24;
    if (sameDayEnd > end) end = math.min(24, sameDayEnd);
  }
  if (end <= start) end = start + 1;
  return (start: start, end: end);
}

/// العرض اليومي.
class TimelineDayView extends StatelessWidget {
  const TimelineDayView({
    super.key,
    required this.day,
    required this.lessons,
    required this.prefs,
    required this.accentOf,
    required this.onTap,
    required this.onLongPress,
    required this.onEnd,
    required this.onCancel,
    required this.onFreeSlot,
    required this.onAddLesson,
  });

  final DateTime day;
  final List<TimelineLesson> lessons;
  final TimelinePreferencesData prefs;
  final AccentResolver accentOf;
  final LessonCallback onTap;
  final LessonCallback onLongPress;
  final LessonCallback onEnd;
  final LessonCallback onCancel;
  final FreeSlotCallback onFreeSlot;
  final VoidCallback onAddLesson;

  @override
  Widget build(BuildContext context) {
    if (lessons.isEmpty) {
      final isPast = day.isBefore(TimelineFormat.today());
      return TimelineEmptyState(
        icon: isPast ? Icons.history_rounded : Icons.event_available_rounded,
        title: isPast ? 'لا توجد دروس مسجّلة في هذا اليوم' : 'يوم فارغ',
        subtitle: isPast
            ? 'تُعرض في الأيام السابقة الدروس المنتهية والملغية فقط'
            : 'لا توجد دروس مجدولة أو متكررة في هذا اليوم',
        action: isPast
            ? null
            : FilledButton.tonalIcon(
                onPressed: onAddLesson,
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة درس'),
              ),
      );
    }

    if (prefs.dayLayout == TimelineDayLayout.list) {
      return _DayList(
        lessons: lessons,
        prefs: prefs,
        accentOf: accentOf,
        onTap: onTap,
        onLongPress: onLongPress,
        onEnd: onEnd,
        onCancel: onCancel,
      );
    }

    return _DayTimeline(
      day: day,
      lessons: lessons,
      prefs: prefs,
      accentOf: accentOf,
      onTap: onTap,
      onLongPress: onLongPress,
      onFreeSlot: onFreeSlot,
    );
  }
}

// =====================================================================
// قائمة اليوم
// =====================================================================

class _DayList extends StatelessWidget {
  const _DayList({
    required this.lessons,
    required this.prefs,
    required this.accentOf,
    required this.onTap,
    required this.onLongPress,
    required this.onEnd,
    required this.onCancel,
  });

  final List<TimelineLesson> lessons;
  final TimelinePreferencesData prefs;
  final AccentResolver accentOf;
  final LessonCallback onTap;
  final LessonCallback onLongPress;
  final LessonCallback onEnd;
  final LessonCallback onCancel;

  String _periodOf(DateTime t) {
    if (t.hour < 12) return 'صباحاً';
    if (t.hour < 17) return 'ظهراً';
    return 'مساءً';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = <Widget>[];
    String? lastPeriod;
    var index = 0;
    for (final l in lessons) {
      final p = _periodOf(l.start);
      if (p != lastPeriod) {
        lastPeriod = p;
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
          child: Row(
            children: [
              Icon(
                p == 'صباحاً'
                    ? Icons.wb_twilight_rounded
                    : p == 'ظهراً'
                        ? Icons.wb_sunny_rounded
                        : Icons.nights_stay_rounded,
                size: 15,
                color: scheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                p,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ));
      }
      final i = index++;
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: StaggeredReveal(
          index: i,
          child: TimelineLessonCard(
            lesson: l,
            prefs: prefs,
            accent: accentOf(l),
            onTap: () => onTap(l),
            onLongPress: () => onLongPress(l),
            onEnd: () => onEnd(l),
            onCancel: () => onCancel(l),
          ),
        ),
      ));
    }

    return SlidableAutoCloseBehavior(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 120),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        children: items,
      ),
    );
  }
}

// =====================================================================
// الخط الزمني لليوم
// =====================================================================

class _DayTimeline extends StatefulWidget {
  const _DayTimeline({
    required this.day,
    required this.lessons,
    required this.prefs,
    required this.accentOf,
    required this.onTap,
    required this.onLongPress,
    required this.onFreeSlot,
  });

  final DateTime day;
  final List<TimelineLesson> lessons;
  final TimelinePreferencesData prefs;
  final AccentResolver accentOf;
  final LessonCallback onTap;
  final LessonCallback onLongPress;
  final FreeSlotCallback onFreeSlot;

  @override
  State<_DayTimeline> createState() => _DayTimelineState();
}

class _DayTimelineState extends State<_DayTimeline> {
  final _scroll = ScrollController();
  bool _didAutoScroll = false;

  static const double _gutter = 52;
  static const double _topPad = 14;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoScroll());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll() {
    if (_didAutoScroll || !mounted || !_scroll.hasClients) return;
    _didAutoScroll = true;
    final now = DateTime.now();
    final range = visibleHourRange(widget.prefs, widget.lessons);
    final hourH = widget.prefs.hourHeight;
    double target;
    if (TimelineFormat.isSameDay(widget.day, now) &&
        widget.prefs.autoScrollToNow) {
      target = (now.hour + now.minute / 60 - range.start) * hourH - 110;
    } else if (widget.lessons.isNotEmpty) {
      final first = widget.lessons.first.start;
      target = (first.hour + first.minute / 60 - range.start) * hourH - 60;
    } else {
      return;
    }
    final max = _scroll.position.maxScrollExtent;
    _scroll.animateTo(
      target.clamp(0, max),
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prefs = widget.prefs;
    final hourH = prefs.hourHeight;
    final range = visibleHourRange(prefs, widget.lessons);
    final hours = range.end - range.start;
    final totalH = hours * hourH + _topPad * 2;
    final now = DateTime.now();
    final isToday = TimelineFormat.isSameDay(widget.day, now);
    final laidOut = layoutOverlaps(widget.lessons);

    double offsetOf(DateTime t) {
      final clamped = TimelineFormat.isSameDay(t, widget.day)
          ? t
          : DateTime(widget.day.year, widget.day.month, widget.day.day, 23, 59);
      return _topPad +
          (clamped.hour + clamped.minute / 60 - range.start) * hourH;
    }

    final List<(DateTime, DateTime)> freeSlots =
        prefs.showFreeSlots ? _freeSlots(range) : const [];

    return SingleChildScrollView(
      controller: _scroll,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.only(bottom: 120),
      child: SizedBox(
        height: totalH,
        child: LayoutBuilder(builder: (context, c) {
          final laneW = c.maxWidth - _gutter - 12;
          return Stack(
            children: [
              // خطوط الساعات والتسميات
              Positioned.fill(
                child: CustomPaint(
                  painter: _HourGridPainter(
                    startHour: range.start,
                    hours: hours,
                    hourHeight: hourH,
                    topPad: _topPad,
                    gutter: _gutter,
                    lineColor: scheme.outlineVariant.withValues(alpha: 0.55),
                    halfLineColor:
                        scheme.outlineVariant.withValues(alpha: 0.25),
                    textColor: scheme.onSurfaceVariant,
                    use24h: prefs.use24h,
                    textDirection: Directionality.of(context),
                    workStart: prefs.startHour,
                    workEnd: prefs.endHour,
                    offHoursColor:
                        scheme.onSurface.withValues(alpha: 0.025),
                  ),
                ),
              ),

              // الفراغات
              for (final slot in freeSlots)
                PositionedDirectional(
                  start: _gutter,
                  width: laneW,
                  top: offsetOf(slot.$1) + 2,
                  height: math.max(
                      0.0,
                      slot.$2.difference(slot.$1).inMinutes / 60 * hourH -
                          4),
                  child: _FreeSlotBox(
                    start: slot.$1,
                    end: slot.$2,
                    use24h: prefs.use24h,
                    onTap: () => widget.onFreeSlot(slot.$1, slot.$2),
                  ),
                ),

              // الدروس
              for (final item in laidOut)
                Builder(builder: (context) {
                  final l = item.lesson;
                  final top = offsetOf(l.start);
                  final bottom = offsetOf(l.end);
                  final h = math.max(26.0, bottom - top - 3);
                  final colW = laneW / item.columns;
                  return PositionedDirectional(
                    start: _gutter + item.column * colW,
                    width: colW - (item.columns > 1 ? 3 : 0),
                    top: top,
                    height: h,
                    child: StaggeredReveal(
                      index: laidOut.indexOf(item),
                      offsetY: 10,
                      child: TimelineBlock(
                        lesson: l,
                        accent: widget.accentOf(l),
                        prefs: prefs,
                        onTap: () => widget.onTap(l),
                        onLongPress: () => widget.onLongPress(l),
                      ),
                    ),
                  );
                }),

              // خط الآن
              if (isToday &&
                  prefs.showNowLine &&
                  now.hour >= range.start &&
                  now.hour < range.end)
                PositionedDirectional(
                  start: 0,
                  end: 0,
                  top: offsetOf(now) - 12,
                  child: IgnorePointer(
                    child: _NowLine(
                      label: TimelineFormat.time(now, use24h: prefs.use24h),
                      gutter: _gutter,
                    ),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  List<(DateTime, DateTime)> _freeSlots(({int start, int end}) range) {
    final d = widget.day;
    final dayStart = DateTime(d.year, d.month, d.day, widget.prefs.startHour);
    final dayEnd = widget.prefs.endHour >= 24
        ? DateTime(d.year, d.month, d.day, 23, 59)
        : DateTime(d.year, d.month, d.day, widget.prefs.endHour);
    final busy = widget.lessons
        .where((l) => l.status != TimelineStatus.canceled)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final slots = <(DateTime, DateTime)>[];
    var cursor = dayStart;
    final now = DateTime.now();
    for (final l in busy) {
      if (l.start.isAfter(cursor) &&
          l.start.difference(cursor).inMinutes >= 30) {
        slots.add((cursor, l.start));
      }
      if (l.end.isAfter(cursor)) cursor = l.end;
    }
    if (dayEnd.isAfter(cursor) && dayEnd.difference(cursor).inMinutes >= 30) {
      slots.add((cursor, dayEnd));
    }
    // لا نعرض الفراغات التي مضت
    return slots.where((s) => s.$2.isAfter(now)).map((s) {
      if (s.$1.isBefore(now) && TimelineFormat.isSameDay(now, d)) {
        final rounded = DateTime(
            now.year, now.month, now.day, now.hour, (now.minute ~/ 15) * 15);
        return (rounded, s.$2);
      }
      return s;
    }).where((s) => s.$2.difference(s.$1).inMinutes >= 30).toList();
  }
}

class _HourGridPainter extends CustomPainter {
  _HourGridPainter({
    required this.startHour,
    required this.hours,
    required this.hourHeight,
    required this.topPad,
    required this.gutter,
    required this.lineColor,
    required this.halfLineColor,
    required this.textColor,
    required this.use24h,
    required this.textDirection,
    required this.workStart,
    required this.workEnd,
    required this.offHoursColor,
  });

  final int startHour;
  final int hours;
  final double hourHeight;
  final double topPad;
  final double gutter;
  final Color lineColor;
  final Color halfLineColor;
  final Color textColor;
  final bool use24h;
  final TextDirection textDirection;
  final int workStart;
  final int workEnd;
  final Color offHoursColor;

  @override
  void paint(Canvas canvas, Size size) {
    final isRtl = textDirection == TextDirection.rtl;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    final halfPaint = Paint()
      ..color = halfLineColor
      ..strokeWidth = 1;
    final offPaint = Paint()..color = offHoursColor;

    final laneStart = isRtl ? 0.0 : gutter;
    final laneEnd = isRtl ? size.width - gutter : size.width;

    for (var i = 0; i <= hours; i++) {
      final hour = startHour + i;
      final y = topPad + i * hourHeight;

      // تظليل خارج ساعات العمل
      if (i < hours && (hour < workStart || hour >= workEnd)) {
        canvas.drawRect(
          Rect.fromLTRB(laneStart, y, laneEnd, y + hourHeight),
          offPaint,
        );
      }

      canvas.drawLine(Offset(laneStart, y), Offset(laneEnd, y), linePaint);
      if (i < hours) {
        final hy = y + hourHeight / 2;
        _dashed(canvas, Offset(laneStart, hy), Offset(laneEnd, hy), halfPaint);
      }

      final tp = TextPainter(
        text: TextSpan(
          text: TimelineFormat.hourLabel(hour, use24h: use24h),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        textDirection: textDirection,
      )..layout(maxWidth: gutter - 6);
      final tx = isRtl ? size.width - gutter + (gutter - tp.width) / 2 : (gutter - tp.width) / 2;
      tp.paint(canvas, Offset(tx, y - tp.height / 2));
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p) {
    const dash = 4.0;
    const gap = 4.0;
    var x = a.dx;
    while (x < b.dx) {
      canvas.drawLine(Offset(x, a.dy), Offset(math.min(x + dash, b.dx), a.dy), p);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _HourGridPainter o) =>
      o.startHour != startHour ||
      o.hours != hours ||
      o.hourHeight != hourHeight ||
      o.lineColor != lineColor ||
      o.use24h != use24h ||
      o.workStart != workStart ||
      o.workEnd != workEnd;
}

class _NowLine extends StatelessWidget {
  const _NowLine({required this.label, required this.gutter});
  final String label;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFEF4444);
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          SizedBox(
            width: gutter,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          const PulsingDot(color: color, size: 8),
          Expanded(
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: color,
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _FreeSlotBox extends StatelessWidget {
  const _FreeSlotBox({
    required this.start,
    required this.end,
    required this.use24h,
    required this.onTap,
  });

  final DateTime start;
  final DateTime end;
  final bool use24h;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const color = AppTheme.success;
    final minutes = end.difference(start).inMinutes;
    return PressScale(
      onTap: onTap,
      scale: 0.98,
      child: CustomPaint(
        painter: _DashedBorderPainter(color: color.withValues(alpha: 0.45)),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: LayoutBuilder(builder: (context, c) {
            if (c.maxHeight < 22) return const SizedBox.shrink();
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_circle_outline_rounded,
                    size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  'فارغ • ${TimelineFormat.duration(minutes)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    final path = Path()..addRRect(rrect);
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + dash, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) => old.color != color;
}
