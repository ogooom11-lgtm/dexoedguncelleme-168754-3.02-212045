// lib/src/providers/auth_provider.dart
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/role.dart';
import '../models/user.dart';

/// إدارة تسجيل الدخول بالكود (8 أرقام).
/// ✅ لا يوجد أي منطق تحقق من البريد الإلكتروني.
/// ✅ الدخول سريع: قراءة مباشرة للسجل + مهلة قصوى + كاش محلي.
class AuthProvider extends ChangeNotifier {
  static const _userKey = 'user';
  static const _adminCacheKey = 'admin_exists_cache_v1';

  /// مهلة قصوى لأي عملية شبكة أثناء الدخول حتى لا تتجمّد الواجهة.
  static const Duration networkTimeout = Duration(seconds: 12);

  final DatabaseReference _rtdb = FirebaseDatabase.instance.ref();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;

  bool get isLoggedIn => _currentUser != null;

  // ===================== التخزين المحلي =====================

  Future<void> _saveUser(AppUser user) async {
    final data = jsonEncode(user.toMap());
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userKey, data);
      } else {
        await _secureStorage.write(key: _userKey, value: data);
      }
    } catch (_) {
      // كحل بديل دائماً نحفظ نسخة في SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, data);
    }
  }

  /// تحميل المستخدم من التخزين المحلي (بدون أي طلب شبكة).
  Future<void> loadUserFromStorage() async {
    String? data;
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        data = prefs.getString(_userKey);
      } else {
        data = await _secureStorage.read(key: _userKey);
        data ??= (await SharedPreferences.getInstance()).getString(_userKey);
      }
    } catch (_) {
      data = (await SharedPreferences.getInstance()).getString(_userKey);
    }

    if (data == null || data.isEmpty) return;
    try {
      _currentUser = AppUser.fromMap(
        Map<String, dynamic>.from(jsonDecode(data) as Map),
      );
      notifyListeners();
    } catch (_) {
      // بيانات تالفة → نتجاهلها
    }
  }

  Future<void> signOut() async {
    _currentUser = null;
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_userKey);
      } else {
        await _secureStorage.delete(key: _userKey);
        (await SharedPreferences.getInstance()).remove(_userKey);
      }
    } catch (_) {}
    notifyListeners();
  }

  /// تحديث بيانات المستخدم الحالي من قاعدة البيانات في الخلفية (اختياري).
  Future<void> refreshCurrentUserSilently() async {
    final user = _currentUser;
    if (user == null || user.code.isEmpty) return;
    try {
      final snap =
          await _rtdb.child('users/${user.code}').get().timeout(networkTimeout);
      if (!snap.exists || snap.value is! Map) return;
      final data = Map<String, dynamic>.from(snap.value as Map);
      _currentUser = user.copyWith(
        name: (data['name'] ?? user.name).toString(),
        role: _roleFromString((data['role'] ?? user.role.name).toString()),
        teacher: data['teacher']?.toString() ?? user.teacher,
        email: data['email']?.toString() ?? user.email,
        phone: data['phone']?.toString() ?? user.phone,
      );
      await _saveUser(_currentUser!);
      notifyListeners();
    } catch (_) {}
  }

  // ===================== تسجيل الدخول =====================

  /// تسجيل الدخول باستخدام كود مكوّن من 8 أرقام.
  /// لا يقوم بأي تحليل للدروس ولا بإنشاء أي تنبيهات — فقط الدخول.
  Future<AppUser> signInWithCode(String code, {UserRole? forceRole}) async {
    final trimmed = code.trim();
    if (trimmed.length != 8 || int.tryParse(trimmed) == null) {
      throw Exception('الرجاء إدخال 8 أرقام صحيحة');
    }

    // 1) قراءة مباشرة للسجل (أسرع مسار ممكن)
    final directSnap =
        await _rtdb.child('users/$trimmed').get().timeout(networkTimeout);

    if (directSnap.exists && directSnap.value is Map) {
      final data = Map<String, dynamic>.from(directSnap.value as Map);
      final role = _roleFromString((data['role'] ?? 'student').toString());

      if (forceRole != null && role != forceRole) {
        throw Exception('هذا الكود لا يخص هذا الدور');
      }

      _currentUser = AppUser(
        name: (data['name'] ?? 'مستخدم').toString(),
        code: trimmed,
        role: role,
        teacher: data['teacher']?.toString(),
        email: data['email']?.toString(),
        phone: data['phone']?.toString(),
      );

      await _saveUser(_currentUser!);
      if (role == UserRole.admin) await _cacheAdminExists(true);
      notifyListeners();
      return _currentUser!;
    }

    // 2) الكود قد يكون طالباً مضافاً عند معلم فقط
    final student = await _findStudentInsideTeachers(trimmed);
    if (student != null) {
      if (forceRole != null && forceRole != UserRole.student) {
        throw Exception('هذا الكود لا يخص هذا الدور');
      }
      _currentUser = student;
      await _saveUser(_currentUser!);
      notifyListeners();
      return _currentUser!;
    }

    throw Exception('لم يتم العثور على مستخدم بهذا الكود');
  }

  Future<AppUser?> _findStudentInsideTeachers(String code) async {
    try {
      final usersSnap = await _rtdb.child('users').get().timeout(networkTimeout);
      if (!usersSnap.exists || usersSnap.value is! Map) return null;

      final users = Map<String, dynamic>.from(usersSnap.value as Map);
      for (final entry in users.entries) {
        final teacherCode = entry.key.toString();
        if (entry.value is! Map) continue;
        final userData = Map<String, dynamic>.from(entry.value as Map);
        if (userData['role'] != 'teacher') continue;

        final students = userData['students'];
        if (students is! Map) continue;
        final studentRaw = students[code];
        if (studentRaw == null) continue;

        final studentData = studentRaw is Map
            ? Map<String, dynamic>.from(studentRaw)
            : <String, dynamic>{'name': studentRaw.toString()};
        final studentName = (studentData['name'] ?? 'طالب').toString();

        // إنشاء سجل الطالب في الجذر ليصبح الدخول لاحقاً فورياً
        await _rtdb.child('users/$code').set({
          'name': studentName,
          'role': 'student',
          'teacher': teacherCode,
          'createdAt': DateTime.now().toIso8601String(),
        });

        return AppUser(
          name: studentName,
          code: code,
          role: UserRole.student,
          teacher: teacherCode,
        );
      }
    } catch (_) {}
    return null;
  }

  // ===================== إنشاء الحسابات =====================

  Future<void> createAdmin(String name, String code) async {
    _validateCode(code);
    if (await adminExists(forceRefresh: true)) {
      throw Exception('يوجد مدير بالفعل');
    }
    await _rtdb.child('users/$code').set({
      'name': name,
      'role': 'admin',
      'createdAt': DateTime.now().toIso8601String(),
    });
    await _cacheAdminExists(true);
  }

  Future<void> createTeacher(String name, String code) async {
    _validateCode(code);
    await _rtdb.child('users/$code').set({
      'name': name,
      'role': 'teacher',
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> createStudent(String name, String code, String teacherCode) async {
    _validateCode(code);
    await _rtdb.child('users/$code').set({
      'name': name,
      'role': 'student',
      'teacher': teacherCode,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  void _validateCode(String code) {
    if (code.length != 8 || int.tryParse(code) == null) {
      throw Exception('الرجاء إدخال 8 أرقام صحيحة');
    }
  }

  // ===================== المدير =====================

  Future<void> _cacheAdminExists(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_adminCacheKey, value);
    } catch (_) {}
  }

  /// التحقق من وجود مدير — مع كاش محلي لتسريع فتح التطبيق.
  Future<bool> adminExists({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool(_adminCacheKey) == true) return true;
      } catch (_) {}
    }

    try {
      // استعلام مُحدَّد أسرع بكثير من تحميل كل المستخدمين
      final snap = await _rtdb
          .child('users')
          .orderByChild('role')
          .equalTo('admin')
          .limitToFirst(1)
          .get()
          .timeout(networkTimeout);
      final exists = snap.exists && snap.value != null;
      if (exists) await _cacheAdminExists(true);
      return exists;
    } catch (_) {
      // في حال عدم توفر الفهرس أو الشبكة → محاولة احتياطية
      try {
        final snap = await _rtdb.child('users').get().timeout(networkTimeout);
        if (!snap.exists || snap.value is! Map) return false;
        final users = Map<String, dynamic>.from(snap.value as Map);
        final exists = users.values
            .any((u) => u is Map && (u['role']?.toString() == 'admin'));
        if (exists) await _cacheAdminExists(true);
        return exists;
      } catch (_) {
        // لا شبكة: لا نمنع المستخدم المسجّل مسبقاً من الدخول
        return _currentUser != null;
      }
    }
  }

  // ===================== بيانات إضافية =====================

  /// تحديث البريد الإلكتروني (معلومة تواصل فقط، بدون تحقق).
  Future<void> updateEmail(String code, String email) async {
    await _rtdb.child('users/$code').update({'email': email});
    if (_currentUser != null && _currentUser!.code == code) {
      _currentUser = _currentUser!.copyWith(email: email);
      await _saveUser(_currentUser!);
      notifyListeners();
    }
  }

  UserRole _roleFromString(String roleStr) {
    switch (roleStr) {
      case 'admin':
        return UserRole.admin;
      case 'teacher':
        return UserRole.teacher;
      case 'student':
      default:
        return UserRole.student;
    }
  }
}
