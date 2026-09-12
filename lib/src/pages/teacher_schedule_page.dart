import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../providers/auth_provider.dart';
import '../services/alarm_preferences.dart';
import 'teacher_lesson_timer_page.dart';
import 'teacher_add_schedule_page.dart';
import '../services/notification_service.dart';
import 'teacher_edit_schedule_page.dart';

class TeacherSchedulePage extends StatefulWidget {
  const TeacherSchedulePage({super.key});

  @override
  State<TeacherSchedulePage> createState() => _TeacherSchedulePageState();
}

class _TeacherSchedulePageState extends State<TeacherSchedulePage> {
  final ValueNotifier<Set<String>> selectedLessons = ValueNotifier({});
  List<MapEntry<String, dynamic>> latestScheduleList = [];

  Future<void> _confirmDelete(String teacherCode, String key) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("تأكيد الحذف"),
        content: const Text("هل أنت متأكد أنك تريد حذف هذا الموعد؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("حذف"),
          ),
        ],
      ),
    );

    if (result == true) {
      final dbRef =
          FirebaseDatabase.instance.ref("users/$teacherCode/schedule/$key");
      await dbRef.remove();
    }
  }

  Future<void> _startSelectedLessons(String teacherCode) async {
    for (var key in selectedLessons.value) {
      final ref =
          FirebaseDatabase.instance.ref("users/$teacherCode/schedule/$key");
      await ref.update({
        "status": "started",
        "startTime": DateTime.now().toIso8601String(),
      });
    }
    selectedLessons.value = {};
  }

  bool _allSelectedAreTodayAndScheduled() {
    if (selectedLessons.value.isEmpty) return false;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    for (var key in selectedLessons.value) {
      final item = latestScheduleList
          .firstWhere((e) => e.key == key, orElse: () => MapEntry("", {}))
          .value;
      final date = item['date'] ?? "";
      final status = item['status'] ?? "";
      if (date != today || status != "scheduled") return false;
    }
    return true;
  }

  Map<String, List<MapEntry<String, dynamic>>> _groupLessons(
      List<MapEntry<String, dynamic>> list) {
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final tomorrow =
        DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 1)));

    final Map<String, List<MapEntry<String, dynamic>>> groups = {
      "الدروس الجارية": [],
      "المواعيد المعلقة": [],
      "اليوم": [],
      "الغد": [],
      "قادمة": [],
      "قديمة": [],
    };

    for (var entry in list) {
      final item = entry.value;
      final status = item['status'] ?? "scheduled";
      final date = item['date'] ?? "";

      if (!(["scheduled", "started", "pending"].contains(status))) {
        continue;
      }

      if (status == "started") {
        groups["الدروس الجارية"]!.add(entry);
      } else if (status == "pending") {
        groups["المواعيد المعلقة"]!.add(entry);
      } else if (date == today) {
        groups["اليوم"]!.add(entry);
      } else if (date == tomorrow) {
        groups["الغد"]!.add(entry);
      } else {
        final dt = DateTime.tryParse(date);
        if (dt != null) {
          if (dt.isBefore(now)) {
            groups["قديمة"]!.add(entry);
          } else {
            groups["قادمة"]!.add(entry);
          }
        } else {
          groups["قادمة"]!.add(entry);
        }
      }
    }

    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final teacherCode = auth.currentUser?.code ?? "";
    final dbRef = FirebaseDatabase.instance.ref("users/$teacherCode/schedule");
    final recRef =
        FirebaseDatabase.instance.ref("users/$teacherCode/recurringSchedules");

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ValueListenableBuilder<Set<String>>(
          valueListenable: selectedLessons,
          builder: (context, selected, _) {
            if (selected.isNotEmpty) {
              return AppBar(
                title: Text("${selected.length} محدد"),
                backgroundColor: Colors.teal,
                actions: [
                  if (_allSelectedAreTodayAndScheduled())
                    TextButton.icon(
                      onPressed: () async {
                        await _startSelectedLessons(teacherCode);
                      },
                      icon: const Icon(Icons.play_arrow, color: Colors.white),
                      label: const Text("ابدأ الدرس",
                          style: TextStyle(color: Colors.white)),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                      selectedLessons.value = {};
                    },
                  )
                ],
              );
            } else {
              return AppBar(
                title: const Text("📅 جدول الدروس"),
                centerTitle: true,
                backgroundColor: Colors.teal,
              );
            }
          },
        ),
      ),
      body: StreamBuilder(
        stream: dbRef.onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
            return const Center(child: Text("لا يوجد مواعيد مجدولة"));
          }

          final data =
              Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);

          latestScheduleList = data.entries.toList();

          final grouped = _groupLessons(latestScheduleList);

          return StreamBuilder(
            stream: recRef.onValue,
            builder: (context, recSnap) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (grouped.values.every((list) => list.isEmpty))
                    const Center(child: Text("لا يوجد دروس قادمة"))
                  else
                    ...grouped.entries
                        .where((e) => e.value.isNotEmpty)
                        .map((group) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.key,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...group.value.map((entry) {
                            final item = Map<String, dynamic>.from(entry.value);

                            final status = item['status'] ?? 'scheduled';
                            final lessonDate =
                                DateTime.tryParse(item['date'] ?? "");
                            final isToday = lessonDate != null &&
                                DateFormat('yyyy-MM-dd').format(lessonDate) ==
                                    DateFormat('yyyy-MM-dd')
                                        .format(DateTime.now());
                            final isPast = lessonDate != null &&
                                lessonDate.isBefore(DateTime.now()) &&
                                !isToday;

                            final start = item['startTime'] != null &&
                                    item['startTime'] != ""
                                ? DateFormat('HH:mm')
                                    .format(DateTime.parse(item['startTime']))
                                : "";
                            final end =
                                item['endTime'] != null && item['endTime'] != ""
                                    ? DateFormat('HH:mm')
                                        .format(DateTime.parse(item['endTime']))
                                    : "";

                            final isSelected =
                                selectedLessons.value.contains(entry.key);

                            return Slidable(
                              key: ValueKey(entry.key),
                              startActionPane: ActionPane(
                                motion: const DrawerMotion(),
                                children: [],
                              ),
                              child: Card(
                                elevation: 3,
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: isPast
                                      ? const BorderSide(
                                          color: Colors.amber, width: 2)
                                      : BorderSide.none,
                                ),
                                color: isToday
                                    ? Colors.teal.shade100
                                    : Colors.grey.shade50,
                                child: ListTile(
                                  leading: Checkbox(
                                    value: isSelected,
                                    onChanged: (value) {
                                      final newSelected = Set<String>.from(
                                          selectedLessons.value);

                                      if (value == true) {
                                        newSelected.add(entry.key);
                                      } else {
                                        newSelected.remove(entry.key);
                                      }
                                      selectedLessons.value = newSelected;
                                    },
                                  ),
                                  title: FutureBuilder(
                                    future: FirebaseDatabase.instance
                                        .ref(
                                            "users/$teacherCode/students/${item['student']}")
                                        .get(),
                                    builder: (context, snap) {
                                      if (!snap.hasData || !snap.data!.exists) {
                                        return const Text("طالب غير معروف",
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87));
                                      }
                                      final student = Map<String, dynamic>.from(
                                          snap.data!.value as Map);
                                      return Text(student['name'] ?? "طالب",
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black));
                                    },
                                  ),
                                  subtitle: Text(
                                    "📅 ${item['date'] ?? ''} • 🕒 $start ← $end\nالحالة: $status",
                                    style:
                                        const TextStyle(color: Colors.black87),
                                  ),
                                  trailing: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 200),
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        if (status == "pending") ...[
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green),
                                            onPressed: () async {
                                              final ref =
                                                  FirebaseDatabase.instance.ref(
                                                      "users/$teacherCode/schedule/${entry.key}");
                                              await ref.update(
                                                  {"status": "scheduled"});
                                            },
                                            child: const Text("قبول"),
                                          ),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red),
                                            onPressed: () async {
                                              final ref =
                                                  FirebaseDatabase.instance.ref(
                                                      "users/$teacherCode/schedule/${entry.key}");
                                              await ref.update(
                                                  {"status": "canceled"});
                                            },
                                            child: const Text("رفض"),
                                          ),
                                        ],
                                        if (isToday && status == "scheduled")
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.teal),
                                            onPressed: () async {
                                              final ref =
                                                  FirebaseDatabase.instance.ref(
                                                      "users/$teacherCode/schedule/${entry.key}");
                                              await ref.update({
                                                "status": "started",
                                                "startTime": DateTime.now()
                                                    .toIso8601String(),
                                              });

                                              final snap = await ref.get();
                                              if (snap.exists) {
                                                final data =
                                                    Map<String, dynamic>.from(
                                                        snap.value as Map);
                                                final startTime =
                                                    DateTime.tryParse(
                                                        data['startTime'] ??
                                                            '');
                                                final durationSec = int.tryParse(
                                                        "${data['duration']}") ??
                                                    0;
                                                final student = data['student']
                                                        ?.toString() ??
                                                    "طالب";

                                                if (startTime != null &&
                                                    durationSec > 0) {
                                                  final endTime = startTime.add(
                                                      Duration(
                                                          seconds:
                                                              durationSec));

                                                  await NotificationService
                                                      .cancelLessonNotification(
                                                          entry.key);

                                                  final prefs =
                                                      await AlarmPreferences
                                                          .load();
                                                  final reminderEndTime =
                                                      endTime.subtract(prefs
                                                          .reminderLeadDuration);
                                                  if (reminderEndTime.isAfter(
                                                      DateTime.now())) {
                                                    await NotificationService
                                                        .scheduleLessonEndReminderNotification(
                                                      lessonId: entry.key,
                                                      student: student,
                                                      reminderTime:
                                                          reminderEndTime,
                                                      teacherCode: teacherCode,
                                                    );
                                                  }

                                                  if (endTime.isAfter(
                                                      DateTime.now())) {
                                                    await NotificationService
                                                        .scheduleLessonEndedNotification(
                                                      lessonId: entry.key,
                                                      student: student,
                                                      endTime: endTime,
                                                      teacherCode: teacherCode,
                                                    );
                                                  }
                                                }
                                              }

                                              if (!context.mounted) return;
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      TeacherLessonTimerPage(
                                                          lessonId: entry.key),
                                                ),
                                              );
                                            },
                                            child: const Text("ابدأ"),
                                          ),
                                        if (status == "started")
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.blue),
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      TeacherLessonTimerPage(
                                                          lessonId: entry.key),
                                                ),
                                              );
                                            },
                                            child: const Text("تتبع"),
                                          ),
                                        if (status == "scheduled")
                                          PopupMenuButton<String>(
                                            onSelected: (value) {
                                              if (value == "delete") {
                                                _confirmDelete(
                                                    teacherCode, entry.key);
                                              } else if (value == "edit") {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        TeacherEditSchedulePage(
                                                      lessonId: entry.key,
                                                      lessonData: item,
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              const PopupMenuItem(
                                                value: "edit",
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.edit,
                                                        color: Colors.blue),
                                                    SizedBox(width: 8),
                                                    Text("تعديل"),
                                                  ],
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value: "delete",
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.delete,
                                                        color: Colors.red),
                                                    SizedBox(width: 8),
                                                    Text("حذف"),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 24),
                        ],
                      );
                    }),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.teal,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          "إضافة موعد",
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const TeacherAddSchedulePage(),
            ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
