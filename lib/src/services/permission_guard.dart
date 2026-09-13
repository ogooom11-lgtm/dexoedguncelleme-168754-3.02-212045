// lib/src/services/permission_guard.dart
//
// 🔐 حارس الصلاحيات عند المعلم + إعدادات المنصة العامة (يُقرآن لحظياً).
// الاستخدام:
//   if (!await PermissionGuard.check(context, TeacherPermission.addStudents)) return;
// و:
//   StreamBuilder(stream: PlatformGate.watch(), ...)  أو  PlatformGate.current

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'admin_repository.dart' show PlatformSettings;
import 'teacher_permissions.dart';
import 'timeline_models.dart' show TimelineFormat;

export 'admin_repository.dart' show PlatformSettings;
export 'teacher_permissions.dart';

class PermissionGuard {
  PermissionGuard._();

  static String? _code;
  static TeacherPermissions _current = TeacherPermissions.full;
  static StreamSubscription<TeacherPermissions>? _sub;
  static final _controller = StreamController<TeacherPermissions>.broadcast();

  static TeacherPermissions get current => _current;
  static Stream<TeacherPermissions> get stream => _controller.stream;

  /// ابدأ المراقبة لمعلم محدد (يُستدعى من الشاشة الرئيسية للمعلم).
  static void start(String teacherCode) {
    if (teacherCode.isEmpty || _code == teacherCode) return;
    _code = teacherCode;
    _sub?.cancel();
    _sub = TeacherPermissions.watch(teacherCode).listen((p) {
      _current = p;
      _controller.add(p);
    }, onError: (Object _) {});
  }

  static void stop() {
    _sub?.cancel();
    _sub = null;
    _code = null;
    _current = TeacherPermissions.full;
  }

  static bool allows(TeacherPermission p) => _current.allows(p);

  /// يتحقق من الصلاحية ويعرض رسالة إن كانت محجوبة. يعيد true إن كان مسموحاً.
  static Future<bool> check(BuildContext context, TeacherPermission p, {String? teacherCode}) async {
    if (teacherCode != null && teacherCode.isNotEmpty && _code != teacherCode) {
      // لم تبدأ المراقبة بعد → جلب مباشر لمرة واحدة
      try {
        _current = await TeacherPermissions.fetch(teacherCode);
      } catch (_) {}
      start(teacherCode);
    }
    if (_current.allows(p)) return true;
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.lock_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('صلاحية «${p.label}» غير متاحة لحسابك. تواصل مع الإدارة.')),
            ],
          ),
        ));
    }
    return false;
  }
}

/// إعدادات المنصة العامة (settings/platform) — تُقرأ مرة واحدة وتُراقب.
class PlatformGate {
  PlatformGate._();

  static PlatformSettings _current = const PlatformSettings();
  static StreamSubscription<DatabaseEvent>? _sub;
  static final _controller = StreamController<PlatformSettings>.broadcast();

  static PlatformSettings get current => _current;

  static void _ensure() {
    if (_sub != null) return;
    _sub = FirebaseDatabase.instance.ref('settings/platform').onValue.listen((e) {
      final v = e.snapshot.value;
      _current = PlatformSettings.fromMap(v is Map ? Map<String, dynamic>.from(v) : null);
      TimelineFormat.currency = _current.currency;
      _controller.add(_current);
    }, onError: (Object _) {});
  }

  /// بث التغييرات (استخدم `snap.data ?? PlatformGate.current` كقيمة أولية).
  static Stream<PlatformSettings> watch() {
    _ensure();
    return _controller.stream;
  }
}

/// شريط إعلان الإدارة — يظهر فقط عند وجود إعلان موجّه لهذا الدور.
class AnnouncementBanner extends StatelessWidget {
  const AnnouncementBanner({super.key, required this.forTeacher, this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 0)});
  final bool forTeacher;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlatformSettings>(
      stream: PlatformGate.watch(),
      builder: (context, snap) {
        final s = snap.data ?? PlatformGate.current;
        final show = s.announcement.trim().isNotEmpty && (forTeacher ? s.announcementForTeachers : s.announcementForStudents);
        return AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !show
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  margin: margin,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFEA580C)], begin: AlignmentDirectional.centerStart, end: AlignmentDirectional.centerEnd),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.campaign_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(s.announcement, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.5))),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
