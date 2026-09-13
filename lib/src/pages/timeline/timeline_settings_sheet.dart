// lib/src/pages/timeline/timeline_settings_sheet.dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../services/timeline_models.dart';
import '../../services/timeline_preferences.dart';
import '../../theme/app_theme.dart';
import 'timeline_widgets.dart';

/// ورقة إعدادات الجدول الزمني (تُحفظ محلياً).
Future<TimelinePreferencesData?> showTimelineSettingsSheet(
  BuildContext context, {
  required TimelinePreferencesData initial,
}) {
  return showModalBottomSheet<TimelinePreferencesData>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Directionality(
      textDirection: ui.TextDirection.rtl,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        minChildSize: 0.5,
        maxChildSize: 0.96,
        builder: (ctx, controller) =>
            _SettingsSheet(initial: initial, controller: controller),
      ),
    ),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.initial, required this.controller});
  final TimelinePreferencesData initial;
  final ScrollController controller;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late TimelinePreferencesData _p = widget.initial;

  void _set(TimelinePreferencesData next) {
    timelineHaptic(_p.haptics);
    setState(() => _p = next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: SheetHeader(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppTheme.heroGradient(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.tune_rounded, color: Colors.white),
            ),
            title: 'إعدادات الجدول الزمني',
            subtitle: 'خصّص العرض حسب طريقة عملك',
            trailing: TextButton.icon(
              onPressed: () => _set(TimelinePreferencesData.defaults),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('افتراضي', style: TextStyle(fontSize: 12)),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.controller,
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
            children: [
              _group(
                title: 'العرض',
                icon: Icons.dashboard_customize_rounded,
                children: [
                  _label('العرض الافتراضي عند الفتح'),
                  _segmented<TimelineView>(
                    values: TimelineView.values,
                    selected: _p.defaultView,
                    labelOf: (v) => v.label,
                    onChanged: (v) => _set(_p.copyWith(defaultView: v)),
                  ),
                  const SizedBox(height: 12),
                  _label('نمط العرض اليومي'),
                  _segmented<TimelineDayLayout>(
                    values: TimelineDayLayout.values,
                    selected: _p.dayLayout,
                    labelOf: (v) => v == TimelineDayLayout.timeline
                        ? 'خط زمني'
                        : 'قائمة',
                    iconOf: (v) => v == TimelineDayLayout.timeline
                        ? Icons.view_timeline_rounded
                        : Icons.view_agenda_rounded,
                    onChanged: (v) => _set(_p.copyWith(dayLayout: v)),
                  ),
                  const SizedBox(height: 12),
                  _label('نمط العرض الأسبوعي'),
                  _segmented<TimelineWeekLayout>(
                    values: TimelineWeekLayout.values,
                    selected: _p.weekLayout,
                    labelOf: (v) => v == TimelineWeekLayout.grid
                        ? 'شبكة'
                        : 'قائمة الأيام',
                    iconOf: (v) => v == TimelineWeekLayout.grid
                        ? Icons.grid_view_rounded
                        : Icons.view_list_rounded,
                    onChanged: (v) => _set(_p.copyWith(weekLayout: v)),
                  ),
                  const SizedBox(height: 12),
                  _label('كثافة الخط الزمني'),
                  _segmented<TimelineDensity>(
                    values: TimelineDensity.values,
                    selected: _p.density,
                    labelOf: (v) => v.label,
                    onChanged: (v) => _set(_p.copyWith(density: v)),
                  ),
                  const SizedBox(height: 12),
                  _label('تلوين الدروس حسب'),
                  _segmented<TimelineColorMode>(
                    values: TimelineColorMode.values,
                    selected: _p.colorMode,
                    labelOf: (v) => v == TimelineColorMode.student
                        ? 'الطالب'
                        : 'الحالة',
                    iconOf: (v) => v == TimelineColorMode.student
                        ? Icons.person_rounded
                        : Icons.flag_rounded,
                    onChanged: (v) => _set(_p.copyWith(colorMode: v)),
                  ),
                ],
              ),
              _group(
                title: 'الوقت',
                icon: Icons.schedule_rounded,
                children: [
                  _label('بداية الأسبوع'),
                  _segmented<int>(
                    values: const [
                      DateTime.saturday,
                      DateTime.sunday,
                      DateTime.monday
                    ],
                    selected: _p.weekStartDay,
                    labelOf: (v) => TimelineFormat.dayNames[v - 1],
                    onChanged: (v) => _set(_p.copyWith(weekStartDay: v)),
                  ),
                  const SizedBox(height: 14),
                  _label(
                    'ساعات العمل المعروضة: ${TimelineFormat.hourLabel(_p.startHour, use24h: _p.use24h)} → ${TimelineFormat.hourLabel(_p.endHour, use24h: _p.use24h)}',
                  ),
                  RangeSlider(
                    values: RangeValues(
                      _p.startHour.toDouble(),
                      _p.endHour.toDouble(),
                    ),
                    min: 0,
                    max: 24,
                    divisions: 24,
                    labels: RangeLabels(
                      TimelineFormat.hourLabel(_p.startHour, use24h: _p.use24h),
                      TimelineFormat.hourLabel(_p.endHour, use24h: _p.use24h),
                    ),
                    onChanged: (r) {
                      final s = r.start.round();
                      final e = r.end.round();
                      if (e - s < 4) return;
                      setState(() => _p = _p.copyWith(startHour: s, endHour: e));
                    },
                  ),
                  _switch(
                    title: 'نظام 24 ساعة',
                    subtitle: 'عرض الأوقات بصيغة 14:30 بدل 2:30 م',
                    icon: Icons.access_time_rounded,
                    value: _p.use24h,
                    onChanged: (v) => _set(_p.copyWith(use24h: v)),
                  ),
                  _switch(
                    title: 'خط «الآن»',
                    subtitle: 'مؤشر متحرك على الوقت الحالي',
                    icon: Icons.horizontal_rule_rounded,
                    value: _p.showNowLine,
                    onChanged: (v) => _set(_p.copyWith(showNowLine: v)),
                  ),
                  _switch(
                    title: 'التمرير التلقائي إلى الآن',
                    subtitle: 'عند فتح اليوم الحالي',
                    icon: Icons.my_location_rounded,
                    value: _p.autoScrollToNow,
                    onChanged: (v) => _set(_p.copyWith(autoScrollToNow: v)),
                  ),
                ],
              ),
              _group(
                title: 'ما الذي يظهر؟',
                icon: Icons.visibility_rounded,
                children: [
                  _switch(
                    title: 'المواعيد المتكررة',
                    subtitle: 'عرض التكرارات غير المؤكدة لليوم والأيام القادمة',
                    icon: Icons.event_repeat_rounded,
                    color: TimelineStatus.recurring.color,
                    value: _p.showRecurring,
                    onChanged: (v) => _set(_p.copyWith(showRecurring: v)),
                  ),
                  _switch(
                    title: 'التكرارات في الأيام السابقة',
                    subtitle:
                        'افتراضياً تُعرض الأيام السابقة بالدروس المنتهية والملغية فقط',
                    icon: Icons.history_rounded,
                    color: TimelineStatus.recurring.color,
                    value: _p.showPastRecurring,
                    enabled: _p.showRecurring,
                    onChanged: (v) => _set(_p.copyWith(showPastRecurring: v)),
                  ),
                  _switch(
                    title: 'الدروس الملغية',
                    icon: Icons.cancel_rounded,
                    color: TimelineStatus.canceled.color,
                    value: _p.showCanceled,
                    onChanged: (v) => _set(_p.copyWith(showCanceled: v)),
                  ),
                  _switch(
                    title: 'الدروس الفائتة',
                    subtitle: 'دروس مجدولة انقضى وقتها دون تسجيل نتيجة',
                    icon: Icons.error_rounded,
                    color: TimelineStatus.missed.color,
                    value: _p.showMissed,
                    onChanged: (v) => _set(_p.copyWith(showMissed: v)),
                  ),
                  _switch(
                    title: 'المبالغ',
                    subtitle: 'إظهار المبلغ التقديري/الفعلي على البطاقات',
                    icon: Icons.payments_rounded,
                    value: _p.showAmounts,
                    onChanged: (v) => _set(_p.copyWith(showAmounts: v)),
                  ),
                  _switch(
                    title: 'شريط الملخّص',
                    subtitle: 'عدد الدروس والساعات والمبلغ للنطاق الحالي',
                    icon: Icons.insights_rounded,
                    value: _p.showSummary,
                    onChanged: (v) => _set(_p.copyWith(showSummary: v)),
                  ),
                  _switch(
                    title: 'الفراغات المتاحة',
                    subtitle: 'إبراز الأوقات الفارغة في الخط الزمني اليومي',
                    icon: Icons.space_bar_rounded,
                    value: _p.showFreeSlots,
                    onChanged: (v) => _set(_p.copyWith(showFreeSlots: v)),
                  ),
                ],
              ),
              _group(
                title: 'التفاعل',
                icon: Icons.touch_app_rounded,
                children: [
                  _switch(
                    title: 'اهتزاز خفيف',
                    subtitle: 'عند التبديل والإجراءات',
                    icon: Icons.vibration_rounded,
                    value: _p.haptics,
                    onChanged: (v) => _set(_p.copyWith(haptics: v)),
                  ),
                  _switch(
                    title: 'تأكيد الإجراءات السريعة',
                    subtitle: 'طلب تأكيد عند السحب لإنهاء/إلغاء درس',
                    icon: Icons.verified_user_rounded,
                    value: _p.confirmQuickActions,
                    onChanged: (v) =>
                        _set(_p.copyWith(confirmQuickActions: v)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, _p),
                icon: const Icon(Icons.check_rounded),
                label: const Text('حفظ الإعدادات'),
              ),
              const SizedBox(height: 6),
              Text(
                'تُحفظ الإعدادات على هذا الجهاز فقط',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _group({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _label(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _segmented<T>({
    required List<T> values,
    required T selected,
    required String Function(T) labelOf,
    required ValueChanged<T> onChanged,
    IconData Function(T)? iconOf,
  }) {
    return Row(
      children: [
        for (var i = 0; i < values.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: PillChoice(
              label: labelOf(values[i]),
              icon: iconOf?.call(values[i]),
              selected: values[i] == selected,
              onTap: () => onChanged(values[i]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _switch({
    required String title,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? subtitle,
    Color? color,
    bool enabled = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: value,
        onChanged: enabled ? onChanged : null,
        secondary: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: c),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}

// =====================================================================
// ورقة الفلترة (الطلاب + الحالات)
// =====================================================================

class TimelineFilter {
  final Set<String> students;
  final Set<TimelineStatus> statuses;
  const TimelineFilter({this.students = const {}, this.statuses = const {}});

  bool get isActive => students.isNotEmpty || statuses.isNotEmpty;
  int get count => students.length + statuses.length;

  TimelineFilter copyWith({
    Set<String>? students,
    Set<TimelineStatus>? statuses,
  }) =>
      TimelineFilter(
        students: students ?? this.students,
        statuses: statuses ?? this.statuses,
      );
}

Future<TimelineFilter?> showTimelineFilterSheet(
  BuildContext context, {
  required TimelineFilter initial,
  required List<TimelineStudent> students,
}) {
  return showModalBottomSheet<TimelineFilter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Directionality(
      textDirection: ui.TextDirection.rtl,
      child: _FilterSheet(initial: initial, students: students),
    ),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.students});
  final TimelineFilter initial;
  final List<TimelineStudent> students;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<String> _students = {...widget.initial.students};
  late Set<TimelineStatus> _statuses = {...widget.initial.statuses};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sorted = [...widget.students]
      ..sort((a, b) => a.name.compareTo(b.name));
    final visible = _query.trim().isEmpty
        ? sorted
        : sorted
            .where((s) =>
                s.name.contains(_query.trim()) || s.code.contains(_query.trim()))
            .toList();

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: SheetHeader(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.filter_alt_rounded, color: scheme.primary),
              ),
              title: 'تصفية الجدول',
              subtitle: 'اختر طلاباً أو حالات محددة',
              trailing: TextButton(
                onPressed: () => setState(() {
                  _students = {};
                  _statuses = {};
                }),
                child: const Text('مسح الكل'),
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
              children: [
                SheetSection(
                  title: 'الحالة',
                  icon: Icons.flag_rounded,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in TimelineStatus.values)
                        PillChoice(
                          label: s.label,
                          icon: s.icon,
                          color: s.color,
                          selected: _statuses.contains(s),
                          onTap: () => setState(() {
                            if (!_statuses.remove(s)) _statuses.add(s);
                          }),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SheetSection(
                  title: 'الطلاب',
                  icon: Icons.group_rounded,
                  child: Column(
                    children: [
                      if (widget.students.length > 6)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextField(
                            onChanged: (v) => setState(() => _query = v),
                            decoration: const InputDecoration(
                              hintText: 'ابحث عن طالب…',
                              prefixIcon: Icon(Icons.search_rounded),
                              isDense: true,
                            ),
                          ),
                        ),
                      if (visible.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'لا يوجد طلاب',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      for (final s in visible)
                        PressScale(
                          scale: 0.98,
                          onTap: () => setState(() {
                            if (!_students.remove(s.code)) {
                              _students.add(s.code);
                            }
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: _students.contains(s.code)
                                  ? s.color.withValues(alpha: 0.12)
                                  : scheme.surfaceContainerHighest
                                      .withValues(alpha: 0.35),
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusSm),
                              border: Border.all(
                                color: _students.contains(s.code)
                                    ? s.color
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                StudentAvatar(
                                    name: s.name, color: s.color, size: 34),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    s.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                AnimatedScale(
                                  scale: _students.contains(s.code) ? 1 : 0,
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOutBack,
                                  child: Icon(Icons.check_circle_rounded,
                                      color: s.color),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(
                context,
                TimelineFilter(students: _students, statuses: _statuses),
              ),
              icon: const Icon(Icons.check_rounded),
              label: Text(
                _students.isEmpty && _statuses.isEmpty
                    ? 'عرض الكل'
                    : 'تطبيق (${_students.length + _statuses.length})',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
