import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

class ProfitsPage extends StatefulWidget {
  const ProfitsPage({super.key});

  @override
  State<ProfitsPage> createState() => _ProfitsPageState();
}

class _ProfitsPageState extends State<ProfitsPage> with SingleTickerProviderStateMixin {
  late DateTime _currentMonth;
  Map<String, String> _students = {};
  late final AnimationController _animCtrl =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  // Tooltip (بالضغط فقط داخل الرسم)
  int? _tooltipIndex;
  Offset _tooltipPos = Offset.zero;

  // يومي للشهر الحالي (للشارت)
  late Map<int, DayBreakdown> _dailyDetailed;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _prevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
      _tooltipIndex = null;
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
      _tooltipIndex = null;
    });
  }

  String _monthTitle(DateTime m) => DateFormat.yMMMM('ar').format(m);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final teacherCode = auth.currentUser?.code ?? "";
    final dbRef = FirebaseDatabase.instance.ref("users/$teacherCode/schedule");
    final studentsRef = FirebaseDatabase.instance.ref("users/$teacherCode/students");

    return Scaffold(
      appBar: AppBar(
        title: const Text("💰 المرابح"),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.indigo.shade700, Colors.purple.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
      ),
      body: FutureBuilder<DataSnapshot>(
        future: studentsRef.get(),
        builder: (context, studentsSnap) {
          if (studentsSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          _students = {};
          if (studentsSnap.hasData && studentsSnap.data!.value != null) {
            final raw = Map<String, dynamic>.from(studentsSnap.data!.value as Map);
            for (final e in raw.entries) {
              final v = Map<String, dynamic>.from(e.value);
              _students[e.key] = (v['name'] ?? 'طالب').toString();
            }
          }

          return StreamBuilder<DatabaseEvent>(
            stream: dbRef.onValue,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
                return _emptyState("لا توجد بيانات دروس بعد");
              }

              final all = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map)
                  .entries
                  .map<Map<String, dynamic>>((e) {
                final m = Map<String, dynamic>.from(e.value);
                m['id'] = e.key;
                return m;
              }).toList();

              // ===== شهري (للشارت والملخّص) =====
              final monthData = _filterMonth(all, _currentMonth);
              final prevMonthStart = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
              final prevData = _filterMonth(all, prevMonthStart);

              final totalThis = _sumAmount(monthData);
              final totalPrev = _sumAmount(prevData);
              final diff = totalThis - totalPrev;
              final pct = totalPrev == 0 ? null : (diff / totalPrev) * 100.0;

              _dailyDetailed = _aggregateDailyDetailed(monthData, _currentMonth);
              final dailyTotals = {for (final e in _dailyDetailed.entries) e.key: e.value.total};
              final dailyMax = dailyTotals.values.isEmpty ? 0.0 : dailyTotals.values.reduce(math.max);

              // ===== إجماليات عبر كل الأشهر (GLOBAL) =====
              final globalByStudent = _aggregateByStudent(all.where(_ended).toList());
              final globalTopStudent = globalByStudent.isEmpty
                  ? null
                  : globalByStudent.entries.reduce((a, b) => a.value >= b.value ? a : b);

              final globalByDay = _aggregateByDay(all.where(_ended).toList());
              final globalBestDay = globalByDay.isEmpty
                  ? null
                  : globalByDay.entries.reduce((a, b) => a.value >= b.value ? a : b);

              final globalTopLesson = _findTopLesson(all.where(_ended).toList());

              return LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  final sidePadding = EdgeInsets.symmetric(horizontal: wide ? 24 : 12);

                  // ملاحظة: أزلنا GestureDetector الخارجي كي لا تعيد الشاشة بناءً كليًا عند أي نقرة.
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        children: [
                          const SizedBox(height: 10),

                          // شريط الشهر
                          Padding(
                            padding: sidePadding,
                            child: Row(
                              children: [
                                _NavPill(icon: Icons.chevron_left, onTap: _prevMonth),
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      _monthTitle(_currentMonth),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 20,
                                      ),
                                    ),
                                  ),
                                ),
                                _NavPill(icon: Icons.chevron_right, onTap: _nextMonth),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          // ملخّص الشهر (جمالية أعلى)
                          Padding(
                            padding: sidePadding,
                            child: wide
                                ? Row(
                              children: [
                                Expanded(
                                  child: _FancyStatCard(
                                    gradient: [Colors.indigo, Colors.blue],
                                    icon: Icons.payments,
                                    title: "إجمالي ربح الشهر",
                                    value: "${_fmt(totalThis)} ر.ق",
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _FancyStatCard(
                                    gradient: diff >= 0
                                        ? [Colors.teal, Colors.green]
                                        : [Colors.red, Colors.deepOrange],
                                    icon: diff >= 0 ? Icons.trending_up : Icons.trending_down,
                                    title: "مقارنة بالشهر الماضي",
                                    value: pct == null
                                        ? (diff >= 0
                                        ? "+${_fmt(diff)} ر.ق"
                                        : "-${_fmt(diff.abs())} ر.ق")
                                        : "${diff >= 0 ? "▲" : "▼"} ${_fmt(diff.abs())} ر.ق (${pct!.toStringAsFixed(1)}%)",
                                  ),
                                ),
                              ],
                            )
                                : Column(
                              children: [
                                _FancyStatCard(
                                  gradient: [Colors.indigo, Colors.blue],
                                  icon: Icons.payments,
                                  title: "إجمالي ربح الشهر",
                                  value: "${_fmt(totalThis)} ر.ق",
                                ),
                                const SizedBox(height: 10),
                                _FancyStatCard(
                                  gradient: diff >= 0
                                      ? [Colors.teal, Colors.green]
                                      : [Colors.red, Colors.deepOrange],
                                  icon: diff >= 0 ? Icons.trending_up : Icons.trending_down,
                                  title: "مقارنة بالشهر الماضي",
                                  value: pct == null
                                      ? (diff >= 0
                                      ? "+${_fmt(diff)} ر.ق"
                                      : "-${_fmt(diff.abs())} ر.ق")
                                      : "${diff >= 0 ? "▲" : "▼"} ${_fmt(diff.abs())} ر.ق (${pct!.toStringAsFixed(1)}%)",
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 14),

                          // شبكة المحتوى
                          Padding(
                            padding: sidePadding,
                            child: wide
                                ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // يسار: شارت
                                Expanded(
                                  flex: 3,
                                  child: _ChartCard(
                                    title: "الربح اليومي (الشهر الحالي)",
                                    child: _DailyChart(
                                      monthStart: _currentMonth,
                                      dailyDetailed: _dailyDetailed,
                                      maxY: (dailyMax == 0 ? 1 : dailyMax) * 1.2,
                                      // الفقاعة تظهر فقط عند النقرة داخل الرسم
                                      onTapPoint: (pos, index) {
                                        // تحديث محلي بسيط، لا يغير حجم الحاويات → لا اهتزاز
                                        setState(() {
                                          _tooltipPos = pos;
                                          _tooltipIndex = index;
                                        });
                                      },
                                      tooltipIndex: _tooltipIndex,
                                      tooltipPos: _tooltipPos,
                                      studentsNames: _students,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                // يمين: بطاقات GLOBAL
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    children: [
                                      _InfoCard(
                                        icon: Icons.star_rounded,
                                        color: Colors.purple,
                                        title: "أكثر طالب ربحًا (كل الأشهر)",
                                        child: globalTopStudent == null
                                            ? const Text("—")
                                            : _kv(
                                          _students[globalTopStudent.key] ??
                                              "طالب غير معروف",
                                          "${_fmt(globalTopStudent.value)} ر.ق",
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      _InfoCard(
                                        icon: Icons.event_available,
                                        color: Colors.indigo,
                                        title: "أكثر يوم ربحًا (كل الأشهر)",
                                        child: globalBestDay == null
                                            ? const Text("—")
                                            : _kv(
                                          DateFormat.yMMMd('ar')
                                              .format(globalBestDay.key),
                                          "${_fmt(globalBestDay.value)} ر.ق",
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      _InfoCard(
                                        icon: Icons.star_rate_rounded,
                                        color: Colors.amber.shade700,
                                        title: "أعلى درس ربحًا (كل الأشهر)",
                                        child: globalTopLesson == null
                                            ? const Text("—")
                                            : Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                          children: [
                                            _kv(
                                              _formatLessonTitle(
                                                  globalTopLesson, _students),
                                              "${_fmt(num.tryParse((globalTopLesson['amount'] ?? '0').toString()) ?? 0)} ر.ق",
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              _formatLessonDate(globalTopLesson),
                                              textAlign: TextAlign.right,
                                              style: const TextStyle(
                                                  color: Colors.black54),
                                            )
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                                : Column(
                              children: [
                                _ChartCard(
                                  title: "الربح اليومي (الشهر الحالي)",
                                  child: _DailyChart(
                                    monthStart: _currentMonth,
                                    dailyDetailed: _dailyDetailed,
                                    maxY: (dailyMax == 0 ? 1 : dailyMax) * 1.2,
                                    onTapPoint: (pos, index) {
                                      setState(() {
                                        _tooltipPos = pos;
                                        _tooltipIndex = index;
                                      });
                                    },
                                    tooltipIndex: _tooltipIndex,
                                    tooltipPos: _tooltipPos,
                                    studentsNames: _students,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _InfoCard(
                                  icon: Icons.star_rounded,
                                  color: Colors.purple,
                                  title: "أكثر طالب ربحًا (كل الأشهر)",
                                  child: globalTopStudent == null
                                      ? const Text("—")
                                      : _kv(
                                    _students[globalTopStudent.key] ??
                                        "طالب غير معروف",
                                    "${_fmt(globalTopStudent.value)} ر.ق",
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _InfoCard(
                                  icon: Icons.event_available,
                                  color: Colors.indigo,
                                  title: "أكثر يوم ربحًا (كل الأشهر)",
                                  child: globalBestDay == null
                                      ? const Text("—")
                                      : _kv(
                                    DateFormat.yMMMd('ar')
                                        .format(globalBestDay.key),
                                    "${_fmt(globalBestDay.value)} ر.ق",
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _InfoCard(
                                  icon: Icons.star_rate_rounded,
                                  color: Colors.amber.shade700,
                                  title: "أعلى درس ربحًا (كل الأشهر)",
                                  child: globalTopLesson == null
                                      ? const Text("—")
                                      : Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                    children: [
                                      _kv(
                                        _formatLessonTitle(
                                            globalTopLesson, _students),
                                        "${_fmt(num.tryParse((globalTopLesson['amount'] ?? '0').toString()) ?? 0)} ر.ق",
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _formatLessonDate(globalTopLesson),
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                            color: Colors.black54),
                                      )
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // ====== Helpers & Aggregations ======

  static bool _ended(Map<String, dynamic> e) => (e['status'] ?? '').toString() == 'ended';

  Widget _emptyState(String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hourglass_empty, size: 56, color: Colors.indigo.shade200),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(fontSize: 18, color: Colors.grey)),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filterMonth(List<Map<String, dynamic>> src, DateTime monthStart) {
    final start = DateTime(monthStart.year, monthStart.month, 1);
    final end = DateTime(monthStart.year, monthStart.month + 1, 1)
        .subtract(const Duration(seconds: 1));
    return src.where((e) {
      if (!_ended(e)) return false;
      DateTime? dt = _parseDate(e);
      if (dt == null) return false;
      return !dt.isBefore(start) && !dt.isAfter(end);
    }).toList();
  }

  DateTime? _parseDate(Map<String, dynamic> e) {
    DateTime? dt;
    final endIso = (e['endTime'] ?? '').toString();
    if (endIso.isNotEmpty) dt = DateTime.tryParse(endIso);
    dt ??= DateTime.tryParse((e['date'] ?? '').toString());
    return dt;
  }

  num _sumAmount(List<Map<String, dynamic>> items) {
    return items.fold<num>(0, (p, e) => p + (num.tryParse((e['amount'] ?? '0').toString()) ?? 0));
  }

  Map<String, double> _aggregateByStudent(List<Map<String, dynamic>> items) {
    final Map<String, double> map = {};
    for (final e in items) {
      final sid = (e['student'] ?? '').toString();
      final amount = (num.tryParse((e['amount'] ?? '0').toString()) ?? 0).toDouble();
      map[sid] = (map[sid] ?? 0) + amount;
    }
    return map;
  }

  Map<DateTime, double> _aggregateByDay(List<Map<String, dynamic>> items) {
    // نجمع على أساس التاريخ (اليوم فقط بدون وقت)
    final Map<DateTime, double> map = {};
    for (final e in items) {
      final dt = _parseDate(e);
      if (dt == null) continue;
      final day = DateTime(dt.year, dt.month, dt.day);
      final amount = (num.tryParse((e['amount'] ?? '0').toString()) ?? 0).toDouble();
      map[day] = (map[day] ?? 0) + amount;
    }
    return map;
  }

  Map<String, dynamic>? _findTopLesson(List<Map<String, dynamic>> items) {
    Map<String, dynamic>? best;
    for (final e in items) {
      final amount = (num.tryParse((e['amount'] ?? '0').toString()) ?? 0).toDouble();
      if (best == null ||
          amount > (num.tryParse((best['amount'] ?? '0').toString()) ?? 0)) {
        best = e;
      }
    }
    return best;
  }

  Map<int, DayBreakdown> _aggregateDailyDetailed(
      List<Map<String, dynamic>> items, DateTime monthStart) {
    final days = _daysInMonth(monthStart);
    final Map<int, DayBreakdown> map = {for (int d = 1; d <= days; d++) d: DayBreakdown()};
    for (final e in items) {
      final dt = _parseDate(e);
      if (dt == null) continue;
      final day = dt.day;
      final amount = (num.tryParse((e['amount'] ?? '0').toString()) ?? 0).toDouble();
      final studentId = (e['student'] ?? '').toString();
      map[day]!.total += amount;
      map[day]!.byStudent[studentId] = (map[day]!.byStudent[studentId] ?? 0) + amount;
    }
    return map;
  }

  int _daysInMonth(DateTime m) {
    final next = DateTime(m.year, m.month + 1, 1);
    return next.subtract(const Duration(days: 1)).day;
  }

  String _formatLessonTitle(Map<String, dynamic> lesson, Map<String, String> students) {
    final sid = (lesson['student'] ?? '').toString();
    final name = students[sid] ?? "طالب غير معروف";
    return "درس مع $name";
  }

  String _formatLessonDate(Map<String, dynamic> lesson) {
    final dt = _parseDate(lesson);
    if (dt == null) return "—";
    return DateFormat.yMMMd('ar').add_jm().format(dt);
  }

  /// فاصل آلاف بنقطة . كل 3 خانات
  String _fmt(num v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      buf.write(s[i]);
      count++;
      if (count == 3 && i != 0) {
        buf.write('.');
        count = 0;
      }
    }
    return buf.toString().split('').reversed.join();
  }
}

// ======= UI Pieces =======

class _NavPill extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavPill({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6.0),
          child: Icon(icon, size: 26, color: Colors.white),
        ),
      ),
    );
  }
}

class _FancyStatCard extends StatelessWidget {
  final List<Color> gradient;
  final IconData icon;
  final String title;
  final String value;

  const _FancyStatCard({
    required this.gradient,
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: gradient.last.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white.withOpacity(0.18),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(title, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                Text(value, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final Widget child;

  const _InfoCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

Widget _kv(String k, String v) {
  return Row(
    children: [
      Expanded(child: Text(k, textAlign: TextAlign.right)),
      const SizedBox(width: 8),
      Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  );
}

class DayBreakdown {
  double total = 0.0;
  final Map<String, double> byStudent = {};
}

// ======= Chart (tap-only tooltip, no hover) =======

class _DailyChart extends StatelessWidget {
  final DateTime monthStart;
  final Map<int, DayBreakdown> dailyDetailed;
  final double maxY;
  final void Function(Offset pos, int index) onTapPoint;
  final int? tooltipIndex;
  final Offset tooltipPos;
  final Map<String, String> studentsNames;

  const _DailyChart({
    required this.monthStart,
    required this.dailyDetailed,
    required this.maxY,
    required this.onTapPoint,
    required this.tooltipIndex,
    required this.tooltipPos,
    required this.studentsNames,
  });

  @override
  Widget build(BuildContext context) {
    final days = _daysInMonth(monthStart);
    final series = [for (int d = 1; d <= days; d++) dailyDetailed[d]?.total ?? 0.0];

    return SizedBox(
      height: 240,
      child: LayoutBuilder(
        builder: (context, cons) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              final idx = _indexFromDx(d.localPosition.dx, cons.maxWidth, days);
              onTapPoint(d.localPosition, idx);
            },
            child: Stack(
              children: [
                CustomPaint(
                  painter: _LineChartPainter(
                    data: series,
                    maxY: (maxY == 0 ? 1 : maxY),
                    xLabelsBuilder: (i) {
                      final day = i + 1;
                      if (day == 1 || day == 10 || day == 20 || day == 30) return day.toString();
                      return "";
                    },
                    gridColor: Colors.grey.shade300,
                    lineColor: Colors.indigo,
                    fillTop: Colors.indigo.withOpacity(0.15),
                    fillBottom: Colors.teal.withOpacity(0.05),
                    dotColor: Colors.indigo,
                    padding: 32,
                    highlightIndex: tooltipIndex,
                  ),
                  child: const SizedBox.expand(),
                ),
                if (tooltipIndex != null)
                  _TooltipBubble(
                    anchor: tooltipPos,
                    width: 260,
                    title: DateFormat.yMMMd('ar').format(
                        DateTime(monthStart.year, monthStart.month, (tooltipIndex! + 1))),
                    total: dailyDetailed[tooltipIndex! + 1]?.total ?? 0,
                    rows: () {
                      final bySt = dailyDetailed[tooltipIndex! + 1]?.byStudent ?? {};
                      final entries = bySt.entries.toList()
                        ..sort((a, b) => b.value.compareTo(a.value));
                      final top = entries.take(6).toList();
                      final leftover = entries.length - top.length;
                      return [
                        for (final e in top)
                          _TooltipRow(
                            name: studentsNames[e.key] ?? "طالب غير معروف",
                            amount: e.value,
                          ),
                        if (leftover > 0) _TooltipRow(name: "+$leftover طلاب", amount: null),
                      ];
                    }(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  int _indexFromDx(double dx, double width, int len) {
    const padding = 32.0;
    final chartW = width - padding * 2;
    if (chartW <= 0 || len <= 1) return 0;
    final t = ((dx - padding) / chartW).clamp(0.0, 1.0);
    return (t * (len - 1)).round();
  }

  int _daysInMonth(DateTime m) {
    final next = DateTime(m.year, m.month + 1, 1);
    return next.subtract(const Duration(days: 1)).day;
  }
}

class _TooltipBubble extends StatelessWidget {
  final Offset anchor;
  final double width;
  final String title;
  final double total;
  final List<_TooltipRow> rows;

  const _TooltipBubble({
    required this.anchor,
    required this.width,
    required this.title,
    required this.total,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      const double bubblePadding = 12;
      const double vOffset = 14;
      // موضع ثابت نسبياً دون تغيير حجم الStack → لا اهتزاز
      final left = (anchor.dx - width / 2).clamp(8.0, cons.maxWidth - width - 8.0);
      final top = (anchor.dy - vOffset - 170).clamp(8.0, cons.maxHeight - 130.0);

      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: Material(
              elevation: 5,
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width),
                child: Padding(
                  padding: const EdgeInsets.all(bubblePadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(title,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.black87)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.monetization_on, color: Colors.indigo, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "الإجمالي: ${_fmtLocal(total)} ر.ق",
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final r in rows)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  r.name,
                                  textAlign: TextAlign.right,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (r.amount != null)
                                Text("${_fmtLocal(r.amount!)} ر.ق",
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  // نفس منطق النقطة كل 3 خانات (محلي داخل البالون)
  static String _fmtLocal(num v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      buf.write(s[i]);
      count++;
      if (count == 3 && i != 0) {
        buf.write('.');
        count = 0;
      }
    }
    return buf.toString().split('').reversed.join();
  }
}

class _TooltipRow {
  final String name;
  final double? amount;
  _TooltipRow({required this.name, this.amount});
}

class _LineChartPainter extends CustomPainter {
  final List<double> data;
  final double maxY;
  final String Function(int xIndex)? xLabelsBuilder;
  final Color gridColor;
  final Color lineColor;
  final Color dotColor;
  final double padding;
  final int? highlightIndex;
  final Color fillTop;
  final Color fillBottom;

  _LineChartPainter({
    required this.data,
    required this.maxY,
    required this.xLabelsBuilder,
    required this.gridColor,
    required this.lineColor,
    required this.dotColor,
    required this.fillTop,
    required this.fillBottom,
    this.padding = 32.0,
    this.highlightIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final chartW = size.width - padding * 2;
    final chartH = size.height - padding * 2;

    final axisPaint = Paint()..color = gridColor..strokeWidth = 1;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(padding, padding),
        Offset(size.width - padding, size.height - padding),
        [fillTop, fillBottom],
      )
      ..style = PaintingStyle.fill;
    final dotPaint = Paint()..color = dotColor;

    final tpStyle = const TextStyle(color: Colors.black54, fontSize: 10);
    TextPainter textPainterFn(String t) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: tpStyle),
        textDirection: ui.TextDirection.rtl,
      )..layout();
      return tp;
    }

    final origin = Offset(padding, size.height - padding);
    final maxX = (data.length - 1).toDouble();

    // شبكة Y + تسميات
    for (int i = 0; i <= 4; i++) {
      final y = origin.dy - chartH * i / 4;
      canvas.drawLine(Offset(padding, y), Offset(size.width - padding, y), axisPaint);
      final label = (maxY * i / 4).toStringAsFixed(0);
      final tp = textPainterFn(label);
      tp.paint(canvas, Offset(4, y - tp.height / 2));
    }

    Offset toPoint(int i, double v) {
      final x = padding + chartW * (i / (maxX == 0 ? 1 : maxX));
      final y = origin.dy - (v / (maxY == 0 ? 1 : maxY)) * chartH;
      return Offset(x, y);
    }

    // Path
    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final p = toPoint(i, data[i]);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }

    // تعبئة تدرج
    final fillPath = Path.from(path)
      ..lineTo(padding + chartW, origin.dy)
      ..lineTo(padding, origin.dy)
      ..close();
    canvas.drawPath(fillPath, fillPaint);

    // الخط
    canvas.drawPath(path, linePaint);

    // نقاط + تمييز
    for (int i = 0; i < data.length; i++) {
      final p = toPoint(i, data[i]);
      final r = (highlightIndex == i) ? 4.0 : 2.5;
      canvas.drawCircle(p, r, dotPaint);
      if (highlightIndex == i) {
        final hlPaint = Paint()
          ..color = lineColor.withOpacity(0.18)
          ..strokeWidth = 1;
        canvas.drawLine(Offset(p.dx, padding), Offset(p.dx, origin.dy), hlPaint);
      }
    }

    // تسميات X
    if (xLabelsBuilder != null) {
      for (int i = 0; i < data.length; i++) {
        final label = xLabelsBuilder!(i);
        if (label.isEmpty) continue;
        final tp = textPainterFn(label);
        final x = padding + chartW * (i / (maxX == 0 ? 1 : maxX)) - tp.width / 2;
        tp.paint(canvas, Offset(x, origin.dy + 4));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) {
    return old.data != data ||
        old.maxY != maxY ||
        old.highlightIndex != highlightIndex ||
        old.fillTop != fillTop ||
        old.fillBottom != fillBottom;
  }
}

// ======= Reusable cards =======

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.insights, color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
