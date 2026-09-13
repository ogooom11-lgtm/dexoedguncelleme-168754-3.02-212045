// lib/src/pages/timeline/timeline_week_view.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../services/timeline_models.dart';
import '../../services/timeline_preferences.dart';
import '../../theme/app_theme.dart';
import 'timeline_day_view.dart';
import 'timeline_lesson_card.dart';
import 'timeline_widgets.dart';

/// العرض الأسبوعي (شبكة زمنية أو قائمة أيام).
class TimelineWeekView extends StatelessWidget {
  const TimelineWeekView({
    super.key,
    required this.weekStart,
    required this.lessons,
    required this.prefs,
    required this.accentOf,
    required this.onTap,
    required this.onLongPress,
    required this.onEnd,
    required this.onCancel,
    required this.onOpenDay,
  });

  final DateTime weekStart;
  final List<TimelineLesson> lessons;
  final TimelinePreferencesData prefs;
  final AccentResolver accentOf;
  final LessonCallback onTap;
  final LessonCallback onLongPress;
  final LessonCallback onEnd;
  final LessonCallback onCancel;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    if (prefs.weekLayout == TimelineWeekLayout.agenda) {
      return _WeekAgenda(
        days: days,
        lessons: lessons,
        prefs: prefs,
        accentOf: accentOf,
        onTap: onTap,
        onLongPress: onLongPress,
        onEnd: onEnd,
        onCancel: onCancel,
        onOpenDay: onOpenDay,
      );
    }
    return _WeekGrid(
      days: days,
      lessons: lessons,
      prefs: prefs,
      accentOf: accentOf,
      onTap: onTap,
      onLongPress: onLongPress,
      onOpenDay: onOpenDay,
    );
  }
}

// =====================================================================
// شبكة الأسبوع
// =====================================================================

class _WeekGrid extends StatefulWidget {
  const _WeekGrid({
    required this.days,
    required this.lessons,
    required this.prefs,
    required this.accentOf,
    required this.onTap,
    required this.onLongPress,
    required this.onOpenDay,
  });

  final List<DateTime> days;
  final List<TimelineLesson> lessons;
  final TimelinePreferencesData prefs;
  final AccentResolver accentOf;
  final LessonCallback onTap;
  final LessonCallback onLongPress;
  final ValueChanged<DateTime> onOpenDay;

  @override
  State<_WeekGrid> createState() => _WeekGridState();
}

class _WeekGridState extends State<_WeekGrid> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  bool _didAutoScroll = false;

  static const double _gutter = 44;
  static const double _headerH = 58;
  static const double _topPad = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoScroll());
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _autoScroll() {
    if (_didAutoScroll || !mounted || !_vertical.hasClients) return;
    _didAutoScroll = true;
    final range = visibleHourRange(widget.prefs, widget.lessons);
    final hourH = widget.prefs.hourHeight * 0.9;
    final now = DateTime.now();
    final hasToday = widget.days.any((d) => TimelineFormat.isSameDay(d, now));
    double target;
    if (hasToday && widget.prefs.autoScrollToNow) {
      target = (now.hour + now.minute / 60 - range.start) * hourH - 100;
    } else if (widget.lessons.isNotEmpty) {
      final first = widget.lessons
          .map((l) => l.start.hour + l.start.minute / 60)
          .reduce(math.min);
      target = (first - range.start) * hourH - 40;
    } else {
      return;
    }
    _vertical.animateTo(
      target.clamp(0, _vertical.position.maxScrollExtent),
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final prefs = widget.prefs;
    final hourH = prefs.hourHeight * 0.9;
    final range = visibleHourRange(prefs, widget.lessons);
    final hours = range.end - range.start;
    final bodyH = hours * hourH + _topPad * 2;
    final now = DateTime.now();

    final byDay = <int, List<TimelineLesson>>{};
    for (final l in widget.lessons) {
      final idx = widget.days.indexWhere((d) => TimelineFormat.isSameDay(d, l.start));
      if (idx >= 0) (byDay[idx] ??= []).add(l);
    }

    return LayoutBuilder(builder: (context, c) {
      final availableW = c.maxWidth - _gutter;
      // على الهاتف نعرض 7 أعمدة إن اتسعت (≥ 46px)، وإلا نمرر أفقياً
      const minCol = 46.0;
      final needsHScroll = availableW / 7 < minCol;
      final colW = needsHScroll ? minCol : (availableW / 7).floorToDouble();
      final gridW = colW * 7;

      Widget header = SizedBox(
        width: gridW,
        height: _headerH,
        child: Row(
          children: [
            for (var i = 0; i < 7; i++)
              SizedBox(
                width: colW,
                child: _DayHeader(
                  day: widget.days[i],
                  isToday: TimelineFormat.isSameDay(widget.days[i], now),
                  count: byDay[i]?.where((l) => l.status != TimelineStatus.canceled).length ?? 0,
                  onTap: () => widget.onOpenDay(widget.days[i]),
                ),
              ),
          ],
        ),
      );

      Widget body = SizedBox(
        width: gridW,
        height: bodyH,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _WeekGridPainter(
                  hours: hours,
                  hourHeight: hourH,
                  topPad: _topPad,
                  colW: colW,
                  lineColor: scheme.outlineVariant.withValues(alpha: 0.5),
                  todayIndex: widget.days.indexWhere((d) => TimelineFormat.isSameDay(d, now)),
                  todayColor: scheme.primary.withValues(alpha: 0.05),
                  textDirection: Directionality.of(context),
                ),
              ),
            ),
            for (final entry in byDay.entries)
              for (final item in layoutOverlaps(entry.value))
                Builder(builder: (context) {
                  final l = item.lesson;
                  final top = _topPad + (l.start.hour + l.start.minute / 60 - range.start) * hourH;
                  final endT = TimelineFormat.isSameDay(l.end, l.start) ? l.end : DateTime(l.start.year, l.start.month, l.start.day, 23, 59);
                  final bottom = _topPad + (endT.hour + endT.minute / 60 - range.start) * hourH;
                  final h = math.max(20.0, bottom - top - 2);
                  final subW = (colW - 4) / item.columns;
                  return PositionedDirectional(
                    start: entry.key * colW + 2 + item.column * subW,
                    width: subW - (item.columns > 1 ? 1.5 : 0),
                    top: top,
                    height: h,
                    child: TimelineBlock(
                      lesson: l,
                      accent: widget.accentOf(l),
                      prefs: prefs,
                      compact: true,
                      onTap: () => widget.onTap(l),
                      onLongPress: () => widget.onLongPress(l),
                    ),
                  );
                }),
            // خط الآن
            if (prefs.showNowLine &&
                widget.days.any((d) => TimelineFormat.isSameDay(d, now)) &&
                now.hour >= range.start &&
                now.hour < range.end)
              PositionedDirectional(
                start: 0,
                end: 0,
                top: _topPad + (now.hour + now.minute / 60 - range.start) * hourH - 1,
                child: IgnorePointer(
                  child: Container(
                    height: 2,
                    color: const Color(0xFFEF4444).withValues(alpha: 0.7),
                  ),
                ),
              ),
          ],
        ),
      );

      Widget gutter = SizedBox(
        width: _gutter,
        height: bodyH,
        child: CustomPaint(
          painter: _HourLabelsPainter(
            startHour: range.start,
            hours: hours,
            hourHeight: hourH,
            topPad: _topPad,
            textColor: scheme.onSurfaceVariant,
            use24h: prefs.use24h,
            textDirection: Directionality.of(context),
          ),
        ),
      );

      final grid = needsHScroll
          ? SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Column(children: [header, body]),
            )
          : Column(children: [header, body]);

      return SingleChildScrollView(
        controller: _vertical,
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.only(bottom: 120),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(children: [const SizedBox(height: _headerH), gutter]),
            Expanded(child: grid),
          ],
        ),
      );
    });
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.isToday,
    required this.count,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressScale(
      onTap: onTap,
      scale: 0.93,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              TimelineFormat.shortDayName(day),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: isToday ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isToday ? scheme.primary : Colors.transparent,
                shape: BoxShape.circle,
                boxShadow: isToday
                    ? [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ]
                    : null,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isToday ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              count == 0 ? '' : '$count',
              style: TextStyle(fontSize: 9.5, color: scheme.outline, height: 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekGridPainter extends CustomPainter {
  _WeekGridPainter({
    required this.hours,
    required this.hourHeight,
    required this.topPad,
    required this.colW,
    required this.lineColor,
    required this.todayIndex,
    required this.todayColor,
    required this.textDirection,
  });

  final int hours;
  final double hourHeight;
  final double topPad;
  final double colW;
  final Color lineColor;
  final int todayIndex;
  final Color todayColor;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    final isRtl = textDirection == TextDirection.rtl;

    if (todayIndex >= 0) {
      final x = isRtl ? size.width - (todayIndex + 1) * colW : todayIndex * colW;
      canvas.drawRect(Rect.fromLTWH(x, 0, colW, size.height), Paint()..color = todayColor);
    }
    for (var i = 0; i <= hours; i++) {
      final y = topPad + i * hourHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    for (var i = 0; i <= 7; i++) {
      final x = i * colW;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant _WeekGridPainter o) =>
      o.hours != hours || o.hourHeight != hourHeight || o.colW != colW || o.todayIndex != todayIndex || o.lineColor != lineColor;
}

class _HourLabelsPainter extends CustomPainter {
  _HourLabelsPainter({
    required this.startHour,
    required this.hours,
    required this.hourHeight,
    required this.topPad,
    required this.textColor,
    required this.use24h,
    required this.textDirection,
  });

  final int startHour;
  final int hours;
  final double hourHeight;
  final double topPad;
  final Color textColor;
  final bool use24h;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i <= hours; i++) {
      final y = topPad + i * hourHeight;
      final tp = TextPainter(
        text: TextSpan(
          text: TimelineFormat.hourLabel(startHour + i, use24h: use24h),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        textDirection: textDirection,
      )..layout(maxWidth: size.width);
      tp.paint(canvas, Offset((size.width - tp.width) / 2, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _HourLabelsPainter o) =>
      o.startHour != startHour || o.hours != hours || o.hourHeight != hourHeight || o.use24h != use24h || o.textColor != textColor;
}

// =====================================================================
// قائمة أيام الأسبوع
// =====================================================================

class _WeekAgenda extends StatelessWidget {
  const _WeekAgenda({
    required this.days,
    required this.lessons,
    required this.prefs,
    required this.accentOf,
    required this.onTap,
    required this.onLongPress,
    required this.onEnd,
    required this.onCancel,
    required this.onOpenDay,
  });

  final List<DateTime> days;
  final List<TimelineLesson> lessons;
  final TimelinePreferencesData prefs;
  final AccentResolver accentOf;
  final LessonCallback onTap;
  final LessonCallback onLongPress;
  final LessonCallback onEnd;
  final LessonCallback onCancel;
  final ValueChanged<DateTime> onOpenDay;

  @override
  Widget build(BuildContext context) {
    if (lessons.isEmpty) {
      return const TimelineEmptyState(
        icon: Icons.calendar_view_week_rounded,
        title: 'أسبوع فارغ',
        subtitle: 'لا توجد دروس في هذا الأسبوع ضمن الإعدادات الحالية',
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final items = <Widget>[];
    var index = 0;
    for (final d in days) {
      final dayLessons = lessons.where((l) => TimelineFormat.isSameDay(l.start, d)).toList();
      if (dayLessons.isEmpty) continue;
      final isToday = TimelineFormat.isSameDay(d, now);
      final total = dayLessons.where((l) => l.status != TimelineStatus.canceled).fold<int>(0, (s, l) => s + l.minutes);
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: PressScale(
          onTap: () => onOpenDay(d),
          scale: 0.98,
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isToday ? scheme.primary : scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${d.day}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isToday ? scheme.onPrimary : scheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TimelineFormat.relativeDay(d),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${dayLessons.length} دروس • ${TimelineFormat.duration(total)}',
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_left_rounded, color: scheme.outline),
            ],
          ),
        ),
      ));
      for (final l in dayLessons) {
        final i = index++;
        items.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: StaggeredReveal(
            index: i,
            child: TimelineLessonCard(
              lesson: l,
              prefs: prefs,
              accent: accentOf(l),
              dense: true,
              onTap: () => onTap(l),
              onLongPress: () => onLongPress(l),
              onEnd: () => onEnd(l),
              onCancel: () => onCancel(l),
            ),
          ),
        ));
      }
    }
    return SlidableAutoCloseBehavior(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 120),
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        children: items,
      ),
    );
  }
}

// =====================================================================
// العرض الشهري
// =====================================================================

class TimelineMonthView extends StatelessWidget {
  const TimelineMonthView({
    super.key,
    required this.month,
    required this.selectedDay,
    required this.lessons,
    required this.prefs,
    required this.accentOf,
    required this.onSelectDay,
    required this.onOpenDay,
    required this.onTap,
    required this.onLongPress,
    required this.onEnd,
    required this.onCancel,
  });

  final DateTime month;
  final DateTime selectedDay;
  final List<TimelineLesson> lessons;
  final TimelinePreferencesData prefs;
  final AccentResolver accentOf;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<DateTime> onOpenDay;
  final LessonCallback onTap;
  final LessonCallback onLongPress;
  final LessonCallback onEnd;
  final LessonCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final first = DateTime(month.year, month.month, 1);
    final gridStart = TimelineFormat.startOfWeek(first, prefs.weekStartDay);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final last = DateTime(month.year, month.month, daysInMonth);
    final totalCells = ((last.difference(gridStart).inDays + 1) / 7).ceil() * 7;
    final now = DateTime.now();

    final byDay = <String, List<TimelineLesson>>{};
    for (final l in lessons) {
      (byDay[l.dateKey] ??= []).add(l);
    }
    final selectedLessons = byDay[TimelineFormat.ymd(selectedDay)] ?? const <TimelineLesson>[];

    final weekdayHeaders = List.generate(7, (i) => gridStart.add(Duration(days: i)));

    return SlidableAutoCloseBehavior(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 120),
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        children: [
          // التقويم
          Container(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161A23) : Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    for (final d in weekdayHeaders)
                      Expanded(
                        child: Center(
                          child: Text(
                            TimelineFormat.shortDayName(d),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                for (var row = 0; row < totalCells ~/ 7; row++)
                  Row(
                    children: [
                      for (var col = 0; col < 7; col++)
                        Expanded(
                          child: Builder(builder: (context) {
                            final d = gridStart.add(Duration(days: row * 7 + col));
                            final inMonth = d.month == month.month;
                            final dayLessons = byDay[TimelineFormat.ymd(d)] ?? const <TimelineLesson>[];
                            return _MonthCell(
                              day: d,
                              inMonth: inMonth,
                              isToday: TimelineFormat.isSameDay(d, now),
                              isSelected: TimelineFormat.isSameDay(d, selectedDay),
                              lessons: dayLessons,
                              accentOf: accentOf,
                              onTap: () {
                                if (TimelineFormat.isSameDay(d, selectedDay)) {
                                  onOpenDay(d);
                                } else {
                                  onSelectDay(d);
                                }
                              },
                            );
                          }),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // عنوان اليوم المحدد
          Row(
            children: [
              Expanded(
                child: Text(
                  TimelineFormat.relativeDay(selectedDay),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: () => onOpenDay(selectedDay),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('فتح اليوم', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'اضغط على اليوم المحدد مرة أخرى لفتحه في العرض اليومي',
              style: TextStyle(fontSize: 10.5, color: scheme.outline),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.05), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey(TimelineFormat.ymd(selectedDay)),
              children: [
                if (selectedLessons.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.event_busy_rounded, color: scheme.outline, size: 28),
                        const SizedBox(height: 6),
                        Text(
                          'لا توجد دروس في هذا اليوم',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                else
                  for (var i = 0; i < selectedLessons.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: StaggeredReveal(
                        index: i,
                        child: TimelineLessonCard(
                          lesson: selectedLessons[i],
                          prefs: prefs,
                          accent: accentOf(selectedLessons[i]),
                          dense: true,
                          onTap: () => onTap(selectedLessons[i]),
                          onLongPress: () => onLongPress(selectedLessons[i]),
                          onEnd: () => onEnd(selectedLessons[i]),
                          onCancel: () => onCancel(selectedLessons[i]),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.lessons,
    required this.accentOf,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final List<TimelineLesson> lessons;
  final AccentResolver accentOf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = lessons.where((l) => l.status != TimelineStatus.canceled).toList();
    final ended = active.where((l) => l.status == TimelineStatus.ended).length;
    final dots = active.take(3).map(accentOf).toList();

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        margin: const EdgeInsets.all(2),
        height: 50,
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary
              : isToday
                  ? scheme.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isToday && !isSelected ? Border.all(color: scheme.primary.withValues(alpha: 0.5)) : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Opacity(
          opacity: inMonth ? 1 : 0.35,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: isToday || isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? scheme.onPrimary : scheme.onSurface,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 8,
                child: active.isEmpty
                    ? null
                    : active.length > 3
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.white.withValues(alpha: 0.3) : scheme.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${active.length}',
                              style: TextStyle(
                                fontSize: 7.5,
                                fontWeight: FontWeight.w800,
                                color: isSelected ? Colors.white : scheme.primary,
                                height: 1.1,
                              ),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < dots.length; i++)
                                Container(
                                  width: 5,
                                  height: 5,
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.white : dots[i],
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
              ),
              if (active.isNotEmpty && ended == active.length && !isSelected)
                Container(
                  margin: const EdgeInsets.only(top: 1),
                  width: 10,
                  height: 2,
                  decoration: BoxDecoration(
                    color: AppTheme.success,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              else
                const SizedBox(height: 3),
            ],
          ),
        ),
      ),
    );
  }
}
