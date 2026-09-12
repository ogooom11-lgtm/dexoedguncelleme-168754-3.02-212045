// lib/src/services/recurrence_utils.dart
import 'package:intl/intl.dart';

class RecurringSchedule {
  final String id;
  final String teacher;
  final String student;
  final DateTime startDate;     // date-only anchor
  final DateTime startTime;     // full ISO of same day; نستخدم الساعات والدقائق
  final DateTime endTime;       // full ISO
  final int duration;           // بالثواني (يبدو عندك = دقائق * 60)
  final String repeatType;      // none, daily, everyXDays, weekly, monthly
  final int repeatInterval;     // افتراضي 1
  final String endRepeatType;   // none, occurrences, untilDate, endOfMonth, endOfYear
  final int occurrences;        // عند استخدام occurrences
  final DateTime? endRepeatDate;
  final String? lastConfirmedDate; // yyyy-MM-dd

  RecurringSchedule({
    required this.id,
    required this.teacher,
    required this.student,
    required this.startDate,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.repeatType,
    required this.repeatInterval,
    required this.endRepeatType,
    required this.occurrences,
    required this.endRepeatDate,
    required this.lastConfirmedDate,
  });

  factory RecurringSchedule.fromMap(String id, Map<String, dynamic> m) {
    final sd = DateTime.parse((m['startDate'] as String));
    final st = DateTime.parse((m['startTime'] as String));
    final et = DateTime.parse((m['endTime'] as String));
    return RecurringSchedule(
      id: id,
      teacher: (m['teacher'] ?? '').toString(),
      student: (m['student'] ?? '').toString(),
      startDate: DateTime(sd.year, sd.month, sd.day),
      startTime: st,
      endTime: et,
      duration: (m['duration'] ?? 0) as int,
      repeatType: (m['repeatType'] ?? 'none').toString(),
      repeatInterval: (m['repeatInterval'] ?? 1) is int
          ? m['repeatInterval']
          : int.tryParse(m['repeatInterval'].toString()) ?? 1,
      endRepeatType: (m['endRepeatType'] ?? 'none').toString(),
      occurrences: (m['occurrences'] ?? 0) is int
          ? m['occurrences']
          : int.tryParse(m['occurrences'].toString()) ?? 0,
      endRepeatDate: (m['endRepeatDate'] != null && (m['endRepeatDate'] as String).isNotEmpty)
          ? DateTime.tryParse(m['endRepeatDate'])
          : null,
      lastConfirmedDate: (m['lastConfirmedDate'] as String?),
    );
  }
}

class RecurrenceUtils {
  static final _ymd = DateFormat('yyyy-MM-dd');

  static bool _withinEnd(RecurringSchedule r, DateTime day) {
    // حدود الإنهاء
    switch (r.endRepeatType) {
      case 'untilDate':
        if (r.endRepeatDate == null) return true;
        return !day.isAfter(DateTime(r.endRepeatDate!.year, r.endRepeatDate!.month, r.endRepeatDate!.day));
      case 'endOfMonth':
      // تفسير عملي: لغاية نهاية شهر startDate
        final lastDay = DateTime(r.startDate.year, r.startDate.month + 1, 0).day;
        final endM = DateTime(r.startDate.year, r.startDate.month, lastDay);
        return !day.isAfter(endM);
      case 'endOfYear':
        final endY = DateTime(r.startDate.year, 12, 31);
        return !day.isAfter(endY);
      case 'occurrences':
      // نعد كم مرة حدثت من startDate حتى day
        final count = countOccurrencesUpTo(r, day);
        return count <= r.occurrences;
      case 'none':
      default:
        return true;
    }
  }

  static int _daysBetween(DateTime a, DateTime b) {
    final da = DateTime(a.year, a.month, a.day);
    final db = DateTime(b.year, b.month, b.day);
    return db.difference(da).inDays;
  }

  static bool occursOn(RecurringSchedule r, DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(r.startDate)) return false;
    if (!_withinEnd(r, d)) return false;

    switch (r.repeatType) {
      case 'daily':
      case 'everyXDays':
        final diff = _daysBetween(r.startDate, d);
        return diff % (r.repeatInterval <= 0 ? 1 : r.repeatInterval) == 0;
      case 'weekly':
      // نفس يوم الأسبوع + فرق أسابيع مضاعف لـ repeatInterval
        if (d.weekday != r.startDate.weekday) return false;
        final weeks = _daysBetween(r.startDate, d) ~/ 7;
        return weeks % (r.repeatInterval <= 0 ? 1 : r.repeatInterval) == 0;
      case 'monthly':
      // يوم الشهر نفسه قدر الإمكان
        final targetDay = r.startDate.day;
        final lastDay = DateTime(d.year, d.month + 1, 0).day;
        final clamped = targetDay.clamp(1, lastDay);
        if (d.day != clamped) return false;
        // تحقق من الفاصل الشهري
        final months = (d.year - r.startDate.year) * 12 + (d.month - r.startDate.month);
        return months % (r.repeatInterval <= 0 ? 1 : r.repeatInterval) == 0;
      default:
        return false;
    }
  }

  static int countOccurrencesUpTo(RecurringSchedule r, DateTime day) {
    // عدّ سريع بدون loop يومي
    final d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(r.startDate)) return 0;

    switch (r.repeatType) {
      case 'daily':
      case 'everyXDays':
        final diff = _daysBetween(r.startDate, d);
        final step = r.repeatInterval <= 0 ? 1 : r.repeatInterval;
        return (diff ~/ step) + 1;
      case 'weekly':
        if (d.weekday != r.startDate.weekday) {
          // أقرب يوم مطابِق للأسبوع قبل/يساوي d
          final delta = (d.weekday - r.startDate.weekday);
          final aligned = d.subtract(Duration(days: (delta < 0 ? (delta + 7) : delta)));
          if (aligned.isBefore(r.startDate)) return 0;
          final weeks = _daysBetween(r.startDate, aligned) ~/ 7;
          final step = r.repeatInterval <= 0 ? 1 : r.repeatInterval;
          return (weeks ~/ step) + 1;
        } else {
          final weeks = _daysBetween(r.startDate, d) ~/ 7;
          final step = r.repeatInterval <= 0 ? 1 : r.repeatInterval;
          return (weeks ~/ step) + 1;
        }
      case 'monthly':
        final months = (d.year - r.startDate.year) * 12 + (d.month - r.startDate.month);
        final step = r.repeatInterval <= 0 ? 1 : r.repeatInterval;
        // نعد فقط الأشهر التي يومها يطابق قاعدة اليوم المقيّد
        int count = 0;
        for (int m = 0; m <= months; m++) {
          if (m % step != 0) continue;
          final year = r.startDate.year + (r.startDate.month - 1 + m) ~/ 12;
          final month = ((r.startDate.month - 1 + m) % 12) + 1;
          final lastDay = DateTime(year, month + 1, 0).day;
          final clamped = r.startDate.day.clamp(1, lastDay);
          final occ = DateTime(year, month, clamped);
          if (!occ.isAfter(d)) count++;
        }
        return count;
      default:
        return 0;
    }
  }

  static DateTime buildStartForDay(RecurringSchedule r, DateTime day) {
    // نركّب وقت البدء لليوم target مع ساعة/دقيقة من startTime الأصلي
    return DateTime(day.year, day.month, day.day, r.startTime.hour, r.startTime.minute);
  }

  static DateTime buildEndForDay(RecurringSchedule r, DateTime day) {
    final s = buildStartForDay(r, day);
    return s.add(Duration(seconds: r.duration));
  }

  static String ymd(DateTime d) => _ymd.format(d);
}
