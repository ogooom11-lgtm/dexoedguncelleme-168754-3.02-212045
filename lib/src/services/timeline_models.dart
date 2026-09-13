// lib/src/services/timeline_models.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import 'recurrence_utils.dart';

/// حالة الدرس كما تُعرض في الجدول الزمني.
enum TimelineStatus {
  scheduled,
  started,
  pending,
  ended,
  canceled,
  missed,
  recurring,
}

extension TimelineStatusX on TimelineStatus {
  String get label {
    switch (this) {
      case TimelineStatus.scheduled:
        return 'مجدول';
      case TimelineStatus.started:
        return 'جارٍ الآن';
      case TimelineStatus.pending:
        return 'بانتظار الموافقة';
      case TimelineStatus.ended:
        return 'منتهي';
      case TimelineStatus.canceled:
        return 'ملغي';
      case TimelineStatus.missed:
        return 'فائت';
      case TimelineStatus.recurring:
        return 'مكرر';
    }
  }

  IconData get icon {
    switch (this) {
      case TimelineStatus.scheduled:
        return Icons.event_available_rounded;
      case TimelineStatus.started:
        return Icons.play_circle_fill_rounded;
      case TimelineStatus.pending:
        return Icons.hourglass_top_rounded;
      case TimelineStatus.ended:
        return Icons.check_circle_rounded;
      case TimelineStatus.canceled:
        return Icons.cancel_rounded;
      case TimelineStatus.missed:
        return Icons.error_rounded;
      case TimelineStatus.recurring:
        return Icons.event_repeat_rounded;
    }
  }

  Color get color {
    switch (this) {
      case TimelineStatus.scheduled:
        return AppTheme.seed;
      case TimelineStatus.started:
        return const Color(0xFFF97316);
      case TimelineStatus.pending:
        return const Color(0xFF0D9488);
      case TimelineStatus.ended:
        return AppTheme.success;
      case TimelineStatus.canceled:
        return const Color(0xFF9CA3AF);
      case TimelineStatus.missed:
        return AppTheme.warning;
      case TimelineStatus.recurring:
        return const Color(0xFF8B5CF6);
    }
  }

  /// هل يمكن تسجيله كمنتهي/ملغي؟
  bool get isActionable =>
      this == TimelineStatus.scheduled ||
      this == TimelineStatus.started ||
      this == TimelineStatus.pending ||
      this == TimelineStatus.missed ||
      this == TimelineStatus.recurring;

  bool get isFinal =>
      this == TimelineStatus.ended || this == TimelineStatus.canceled;

  static TimelineStatus fromRaw(String raw) {
    switch (raw) {
      case 'ended':
        return TimelineStatus.ended;
      case 'canceled':
      case 'cancelled':
        return TimelineStatus.canceled;
      case 'started':
        return TimelineStatus.started;
      case 'pending':
        return TimelineStatus.pending;
      case 'recurring':
        return TimelineStatus.recurring;
      case 'scheduled':
      case '':
      default:
        return TimelineStatus.scheduled;
    }
  }
}

/// بيانات مختصرة عن الطالب.
class TimelineStudent {
  final String code;
  final String name;
  final double hourlyRate;
  final Color color;

  const TimelineStudent({
    required this.code,
    required this.name,
    required this.hourlyRate,
    required this.color,
  });

  String get initial => name.trim().isEmpty ? '؟' : name.trim()[0];
}

/// درس واحد في الجدول (مؤكد من `schedule` أو تكرار افتراضي من `recurringSchedules`).
class TimelineLesson {
  /// مفتاح الدرس في `schedule`، أو مفتاح السلسلة إن كان تكراراً افتراضياً.
  final String id;

  /// معرّف السلسلة المتكررة إن وُجد.
  final String? recurringId;

  /// true إن كان تكراراً محسوباً (غير مسجّل في `schedule`).
  final bool isVirtual;

  final RecurringSchedule? recurring;
  final String studentId;
  final String studentName;
  final double hourlyRate;
  final DateTime start;
  final DateTime end;
  final TimelineStatus status;
  final String rawStatus;
  final double amount;
  final String note;
  final String cancelReason;
  final Map<String, dynamic> raw;

  const TimelineLesson({
    required this.id,
    required this.recurringId,
    required this.isVirtual,
    required this.recurring,
    required this.studentId,
    required this.studentName,
    required this.hourlyRate,
    required this.start,
    required this.end,
    required this.status,
    required this.rawStatus,
    required this.amount,
    required this.note,
    required this.cancelReason,
    required this.raw,
  });

  Duration get duration => end.difference(start);
  int get minutes => duration.inMinutes;
  DateTime get day => DateTime(start.year, start.month, start.day);
  String get dateKey => TimelineFormat.ymd(start);

  bool get isToday => TimelineFormat.isSameDay(start, DateTime.now());
  bool get isPastDay => day.isBefore(TimelineFormat.today());
  bool get endedInPast => end.isBefore(DateTime.now());

  /// المبلغ التقديري بحسب سعر ساعة الطالب.
  double get estimatedAmount {
    if (minutes <= 0 || hourlyRate <= 0) return 0;
    return double.parse(((minutes / 60) * hourlyRate).toStringAsFixed(2));
  }

  /// المبلغ الذي يُعرض: الفعلي للمنتهي، والتقديري لغيره.
  double get displayAmount =>
      status == TimelineStatus.ended ? amount : estimatedAmount;

  /// مفتاح فريد للعنصر داخل الواجهة.
  String get uiKey => isVirtual ? 'r:$id:$dateKey' : 's:$id';

  TimelineLesson copyWith({TimelineStatus? status}) {
    return TimelineLesson(
      id: id,
      recurringId: recurringId,
      isVirtual: isVirtual,
      recurring: recurring,
      studentId: studentId,
      studentName: studentName,
      hourlyRate: hourlyRate,
      start: start,
      end: end,
      status: status ?? this.status,
      rawStatus: rawStatus,
      amount: amount,
      note: note,
      cancelReason: cancelReason,
      raw: raw,
    );
  }
}

/// أدوات تنسيق عربية موحّدة للجدول الزمني.
class TimelineFormat {
  TimelineFormat._();

  static final DateFormat _ymd = DateFormat('yyyy-MM-dd');

  static const List<String> dayNames = [
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];

  static const List<String> shortDayNames = [
    'اثنين',
    'ثلاثاء',
    'أربعاء',
    'خميس',
    'جمعة',
    'سبت',
    'أحد',
  ];

  static const List<String> monthNames = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  static const List<Color> palette = [
    Color(0xFF3B5BFE),
    Color(0xFF0EA5E9),
    Color(0xFF14B8A6),
    Color(0xFF22C55E),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF6366F1),
    Color(0xFF84CC16),
    Color(0xFFF43F5E),
    Color(0xFF06B6D4),
  ];

  static Color colorFor(String key) {
    if (key.isEmpty) return palette.first;
    var hash = 0;
    for (final unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }

  static String ymd(DateTime d) => _ymd.format(d);

  static DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  /// بداية الأسبوع بحسب اليوم المختار (السبت افتراضياً).
  static DateTime startOfWeek(DateTime date, int weekStartDay) {
    final clean = dateOnly(date);
    final diff = (clean.weekday - weekStartDay + 7) % 7;
    return clean.subtract(Duration(days: diff));
  }

  static String dayName(DateTime d) => dayNames[d.weekday - 1];
  static String shortDayName(DateTime d) => shortDayNames[d.weekday - 1];
  static String monthName(DateTime d) => monthNames[d.month - 1];

  static String time(DateTime d, {required bool use24h}) {
    if (use24h) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final suffix = d.hour < 12 ? 'ص' : 'م';
    return '$h:${d.minute.toString().padLeft(2, '0')} $suffix';
  }

  static String hourLabel(int hour, {required bool use24h}) {
    final h = hour % 24;
    if (use24h) return '${h.toString().padLeft(2, '0')}:00';
    final display = h % 12 == 0 ? 12 : h % 12;
    return '$display ${h < 12 ? 'ص' : 'م'}';
  }

  static String range(DateTime a, DateTime b, {required bool use24h}) =>
      '${time(a, use24h: use24h)} - ${time(b, use24h: use24h)}';

  static String duration(int minutes) {
    if (minutes <= 0) return '0 د';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '$h س $m د';
    if (h > 0) return h == 1 ? 'ساعة' : (h == 2 ? 'ساعتان' : '$h ساعات');
    return '$m دقيقة';
  }

  /// رمز العملة المعروض في كل التطبيق (قابل للتغيير من إعدادات الإدارة).
  static String currency = 'ر.ق';

  static String money(num value) {
    final rounded = value.roundToDouble() == value
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$rounded $currency';
  }

  /// "اليوم • الأربعاء 12 سبتمبر"
  static String relativeDay(DateTime d) {
    final t = today();
    final clean = dateOnly(d);
    final diff = clean.difference(t).inDays;
    final base = '${dayName(d)} ${d.day} ${monthName(d)}';
    if (diff == 0) return 'اليوم • $base';
    if (diff == 1) return 'غداً • $base';
    if (diff == -1) return 'أمس • $base';
    return base;
  }

  static String fullDate(DateTime d) =>
      '${dayName(d)} ${d.day} ${monthName(d)} ${d.year}';

  static String weekRange(DateTime start) {
    final end = start.add(const Duration(days: 6));
    if (start.month == end.month) {
      return '${start.day} - ${end.day} ${monthName(start)} ${start.year}';
    }
    if (start.year == end.year) {
      return '${start.day} ${monthName(start)} - ${end.day} ${monthName(end)} ${start.year}';
    }
    return '${start.day} ${monthName(start)} ${start.year} - ${end.day} ${monthName(end)} ${end.year}';
  }

  static String monthTitle(DateTime d) => '${monthName(d)} ${d.year}';

  static String repeatLabel(RecurringSchedule r) {
    final n = r.repeatInterval <= 0 ? 1 : r.repeatInterval;
    switch (r.repeatType) {
      case 'daily':
        return 'يومياً';
      case 'everyXDays':
        return n == 1 ? 'يومياً' : 'كل $n أيام';
      case 'weekly':
        return n == 1 ? 'أسبوعياً' : 'كل $n أسابيع';
      case 'monthly':
        return n == 1 ? 'شهرياً' : 'كل $n أشهر';
      default:
        return 'متكرر';
    }
  }
}
