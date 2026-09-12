// lib/src/models/user.dart
import 'role.dart';

/// نموذج المستخدم داخل التطبيق.
/// ✅ تمت إزالة منطق التحقق من البريد الإلكتروني بالكامل،
/// البريد أصبح معلومة اختيارية للتواصل فقط.
class AppUser {
  final String name;
  final String code;
  final UserRole role;
  final String? teacher;
  final String? email;
  final String? phone;

  const AppUser({
    required this.name,
    required this.code,
    required this.role,
    this.teacher,
    this.email,
    this.phone,
  });

  AppUser copyWith({
    String? name,
    String? code,
    UserRole? role,
    String? teacher,
    String? email,
    String? phone,
  }) {
    return AppUser(
      name: name ?? this.name,
      code: code ?? this.code,
      role: role ?? this.role,
      teacher: teacher ?? this.teacher,
      email: email ?? this.email,
      phone: phone ?? this.phone,
    );
  }

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      name: (map['name'] ?? "").toString(),
      code: (map['code'] ?? "").toString(),
      role: UserRole.values.firstWhere(
        (r) => r.name == (map['role'] ?? 'student').toString(),
        orElse: () => UserRole.student,
      ),
      teacher: map['teacher']?.toString(),
      email: map['email']?.toString(),
      phone: map['phone']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "name": name,
      "code": code,
      "role": role.name,
      "teacher": teacher,
      "email": email,
      "phone": phone,
    };
  }
}
