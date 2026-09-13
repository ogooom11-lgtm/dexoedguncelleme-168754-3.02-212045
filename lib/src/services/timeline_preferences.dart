// lib/src/services/timeline_preferences.dart
import 'package:shared_preferences/shared_preferences.dart';

/// أنماط العرض المتاحة في الجدول الزمني.
enum TimelineView { day, week, month }

extension TimelineViewX on TimelineView {
  String get label {
    switch (this) {
      case TimelineView.day:
        return 'يومي';
      case TimelineView.week:
        return 'أسبوعي';
      case TimelineView.month:
        return 'شهري';
    }
  }
}

/// كثافة العرض (ارتفاع الساعة الواحدة في الخط الزمني).
enum TimelineDensity { compact, normal, spacious }

extension TimelineDensityX on TimelineDensity {
  String get label {
    switch (this) {
      case TimelineDensity.compact:
        return 'مضغوط';
      case TimelineDensity.normal:
        return 'عادي';
      case TimelineDensity.spacious:
        return 'واسع';
    }
  }

  double get hourHeight {
    switch (this) {
      case TimelineDensity.compact:
        return 56;
      case TimelineDensity.normal:
        return 76;
      case TimelineDensity.spacious:
        return 100;
    }
  }
}

/// طريقة تلوين الدروس.
enum TimelineColorMode { student, status }

/// نمط العرض اليومي.
enum TimelineDayLayout { timeline, list }

/// نمط العرض الأسبوعي.
enum TimelineWeekLayout { grid, agenda }

class TimelinePreferencesData {
  final TimelineView defaultView;
  final int weekStartDay; // DateTime.saturday / sunday / monday
  final int startHour;
  final int endHour;
  final TimelineDensity density;
  final TimelineColorMode colorMode;
  final TimelineDayLayout dayLayout;
  final TimelineWeekLayout weekLayout;
  final bool use24h;
  final bool showCanceled;
  final bool showMissed;
  final bool showRecurring;
  final bool showPastRecurring;
  final bool showAmounts;
  final bool showNowLine;
  final bool showSummary;
  final bool showFreeSlots;
  final bool autoScrollToNow;
  final bool haptics;
  final bool confirmQuickActions;
  final int defaultSlotMinutes;

  const TimelinePreferencesData({
    this.defaultView = TimelineView.day,
    this.weekStartDay = DateTime.saturday,
    this.startHour = 7,
    this.endHour = 23,
    this.density = TimelineDensity.normal,
    this.colorMode = TimelineColorMode.student,
    this.dayLayout = TimelineDayLayout.timeline,
    this.weekLayout = TimelineWeekLayout.grid,
    this.use24h = false,
    this.showCanceled = true,
    this.showMissed = true,
    this.showRecurring = true,
    this.showPastRecurring = false,
    this.showAmounts = true,
    this.showNowLine = true,
    this.showSummary = true,
    this.showFreeSlots = false,
    this.autoScrollToNow = true,
    this.haptics = true,
    this.confirmQuickActions = true,
    this.defaultSlotMinutes = 60,
  });

  static const defaults = TimelinePreferencesData();

  double get hourHeight => density.hourHeight;

  int get visibleHours => (endHour - startHour).clamp(1, 24);

  TimelinePreferencesData copyWith({
    TimelineView? defaultView,
    int? weekStartDay,
    int? startHour,
    int? endHour,
    TimelineDensity? density,
    TimelineColorMode? colorMode,
    TimelineDayLayout? dayLayout,
    TimelineWeekLayout? weekLayout,
    bool? use24h,
    bool? showCanceled,
    bool? showMissed,
    bool? showRecurring,
    bool? showPastRecurring,
    bool? showAmounts,
    bool? showNowLine,
    bool? showSummary,
    bool? showFreeSlots,
    bool? autoScrollToNow,
    bool? haptics,
    bool? confirmQuickActions,
    int? defaultSlotMinutes,
  }) {
    return TimelinePreferencesData(
      defaultView: defaultView ?? this.defaultView,
      weekStartDay: weekStartDay ?? this.weekStartDay,
      startHour: startHour ?? this.startHour,
      endHour: endHour ?? this.endHour,
      density: density ?? this.density,
      colorMode: colorMode ?? this.colorMode,
      dayLayout: dayLayout ?? this.dayLayout,
      weekLayout: weekLayout ?? this.weekLayout,
      use24h: use24h ?? this.use24h,
      showCanceled: showCanceled ?? this.showCanceled,
      showMissed: showMissed ?? this.showMissed,
      showRecurring: showRecurring ?? this.showRecurring,
      showPastRecurring: showPastRecurring ?? this.showPastRecurring,
      showAmounts: showAmounts ?? this.showAmounts,
      showNowLine: showNowLine ?? this.showNowLine,
      showSummary: showSummary ?? this.showSummary,
      showFreeSlots: showFreeSlots ?? this.showFreeSlots,
      autoScrollToNow: autoScrollToNow ?? this.autoScrollToNow,
      haptics: haptics ?? this.haptics,
      confirmQuickActions: confirmQuickActions ?? this.confirmQuickActions,
      defaultSlotMinutes: defaultSlotMinutes ?? this.defaultSlotMinutes,
    );
  }
}

/// حفظ/قراءة إعدادات الجدول الزمني محلياً.
class TimelinePreferences {
  TimelinePreferences._();

  static const _p = 'timeline_';

  static Future<TimelinePreferencesData> load() async {
    final prefs = await SharedPreferences.getInstance();
    const d = TimelinePreferencesData.defaults;

    int startHour = prefs.getInt('${_p}start_hour') ?? d.startHour;
    int endHour = prefs.getInt('${_p}end_hour') ?? d.endHour;
    startHour = startHour.clamp(0, 23);
    endHour = endHour.clamp(1, 24);
    if (endHour <= startHour) {
      startHour = d.startHour;
      endHour = d.endHour;
    }

    return TimelinePreferencesData(
      defaultView: TimelineView.values[
          (prefs.getInt('${_p}default_view') ?? d.defaultView.index)
              .clamp(0, TimelineView.values.length - 1)],
      weekStartDay: prefs.getInt('${_p}week_start') ?? d.weekStartDay,
      startHour: startHour,
      endHour: endHour,
      density: TimelineDensity.values[
          (prefs.getInt('${_p}density') ?? d.density.index)
              .clamp(0, TimelineDensity.values.length - 1)],
      colorMode: TimelineColorMode.values[
          (prefs.getInt('${_p}color_mode') ?? d.colorMode.index)
              .clamp(0, TimelineColorMode.values.length - 1)],
      dayLayout: TimelineDayLayout.values[
          (prefs.getInt('${_p}day_layout') ?? d.dayLayout.index)
              .clamp(0, TimelineDayLayout.values.length - 1)],
      weekLayout: TimelineWeekLayout.values[
          (prefs.getInt('${_p}week_layout') ?? d.weekLayout.index)
              .clamp(0, TimelineWeekLayout.values.length - 1)],
      use24h: prefs.getBool('${_p}use_24h') ?? d.use24h,
      showCanceled: prefs.getBool('${_p}show_canceled') ?? d.showCanceled,
      showMissed: prefs.getBool('${_p}show_missed') ?? d.showMissed,
      showRecurring: prefs.getBool('${_p}show_recurring') ?? d.showRecurring,
      showPastRecurring:
          prefs.getBool('${_p}show_past_recurring') ?? d.showPastRecurring,
      showAmounts: prefs.getBool('${_p}show_amounts') ?? d.showAmounts,
      showNowLine: prefs.getBool('${_p}show_now_line') ?? d.showNowLine,
      showSummary: prefs.getBool('${_p}show_summary') ?? d.showSummary,
      showFreeSlots: prefs.getBool('${_p}show_free_slots') ?? d.showFreeSlots,
      autoScrollToNow:
          prefs.getBool('${_p}auto_scroll_now') ?? d.autoScrollToNow,
      haptics: prefs.getBool('${_p}haptics') ?? d.haptics,
      confirmQuickActions:
          prefs.getBool('${_p}confirm_quick') ?? d.confirmQuickActions,
      defaultSlotMinutes:
          prefs.getInt('${_p}slot_minutes') ?? d.defaultSlotMinutes,
    );
  }

  static Future<void> save(TimelinePreferencesData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${_p}default_view', data.defaultView.index);
    await prefs.setInt('${_p}week_start', data.weekStartDay);
    await prefs.setInt('${_p}start_hour', data.startHour);
    await prefs.setInt('${_p}end_hour', data.endHour);
    await prefs.setInt('${_p}density', data.density.index);
    await prefs.setInt('${_p}color_mode', data.colorMode.index);
    await prefs.setInt('${_p}day_layout', data.dayLayout.index);
    await prefs.setInt('${_p}week_layout', data.weekLayout.index);
    await prefs.setBool('${_p}use_24h', data.use24h);
    await prefs.setBool('${_p}show_canceled', data.showCanceled);
    await prefs.setBool('${_p}show_missed', data.showMissed);
    await prefs.setBool('${_p}show_recurring', data.showRecurring);
    await prefs.setBool('${_p}show_past_recurring', data.showPastRecurring);
    await prefs.setBool('${_p}show_amounts', data.showAmounts);
    await prefs.setBool('${_p}show_now_line', data.showNowLine);
    await prefs.setBool('${_p}show_summary', data.showSummary);
    await prefs.setBool('${_p}show_free_slots', data.showFreeSlots);
    await prefs.setBool('${_p}auto_scroll_now', data.autoScrollToNow);
    await prefs.setBool('${_p}haptics', data.haptics);
    await prefs.setBool('${_p}confirm_quick', data.confirmQuickActions);
    await prefs.setInt('${_p}slot_minutes', data.defaultSlotMinutes);
  }

  static Future<void> reset() async {
    await save(TimelinePreferencesData.defaults);
  }
}
