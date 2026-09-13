import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'src/models/role.dart';
import 'src/pages/home_admin.dart';
import 'src/pages/home_student.dart';
import 'src/pages/home_teacher.dart';
import 'src/pages/login_page.dart';
import 'src/pages/permissions_guide_page.dart';
import 'src/pages/setup_admin_page.dart';
import 'src/pages/teacher_add_ended_lesson_page.dart';
import 'src/pages/teacher_cancel_lesson_page.dart';
import 'src/pages/teacher_end_lesson_page.dart';
import 'src/pages/teacher_balance_page.dart';
import 'src/pages/teacher_lessons_page.dart';
import 'src/pages/teacher_schedule_page.dart';
import 'src/pages/teacher_students_page.dart';
import 'src/pages/teacher_timeline_page.dart';
import 'src/pages/today_recurring_page.dart';
import 'src/providers/auth_provider.dart';
import 'src/providers/theme_provider.dart';
import 'src/services/notification_service.dart';
import 'src/services/notification_service_wrapper.dart';
import 'src/theme/app_theme.dart';
import 'src/ui/alarm_end_page.dart';
import 'src/ui/alarm_page.dart';
import 'src/utils/app_navigator.dart' show navigatorKey;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ⚡ فقط Firebase مطلوب قبل الإقلاع — كل الباقي يعمل في الخلفية
  // حتى يفتح التطبيق ويسجّل الدخول بأسرع شكل ممكن.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform.copyWith(
      databaseURL: "https://doroos-khas-default-rtdb.firebaseio.com/",
    ),
  );

  runApp(const DoroosKhasApp());

  // 🔕 تهيئة الإشعارات بعد الإقلاع (لا تؤخّر فتح التطبيق ولا تسجيل الدخول)
  unawaited(_initNotificationsInBackground());
}

Future<void> _initNotificationsInBackground() async {
  try {
    await NotificationServiceWrapper.init();
    if (!kIsWeb && Platform.isAndroid) {
      await NotificationService.scheduleDailyMorningReminder();
    }
  } catch (e) {
    debugPrint('⚠️ init notifications: $e');
  }
}

@pragma('vm:entry-point')
Future<void> triggerAlarm(String lessonId, String student) async {
  if (kIsWeb) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final alarmParams =
        prefs.getString('alarm_params_${lessonId.hashCode ^ "start".hashCode}');

    String teacherCode = "";
    if (alarmParams != null) {
      final data = Map<String, dynamic>.from(jsonDecode(alarmParams) as Map);
      teacherCode = (data['teacherCode'] ?? '').toString();
    }

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => AlarmPage(
          lessonId: lessonId,
          student: student,
          teacherCode: teacherCode,
        ),
      ),
    );
  } catch (e) {
    debugPrint("❌ triggerAlarm error: $e");
  }
}

class DoroosKhasApp extends StatelessWidget {
  const DoroosKhasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()..load()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'دروس خاص',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: theme.mode,
            navigatorKey: navigatorKey,
            locale: const Locale('ar'),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('ar')],
            // 📱 توافق كامل مع الهواتف: منع تكبير الخط المبالغ فيه
            // الذي يكسر التصميم على بعض الأجهزة.
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  textScaler: media.textScaler.clamp(
                    minScaleFactor: 0.85,
                    maxScaleFactor: 1.25,
                  ),
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
            home: const _StartupGate(),
            routes: {
              '/login': (_) => const LoginPage(),
              '/permissions_guide': (_) => const PermissionsGuidePage(),
              '/admin': (_) => const HomeAdmin(),
              '/teacher': (_) => const HomeTeacher(),
              '/student': (_) => const HomeStudent(),
              '/today_recurring': (_) => const TodayRecurringPage(),
              '/teacher_add_ended': (_) => const TeacherAddEndedLessonPage(),
              '/teacher_students': (_) => const TeacherStudentsPage(),
              '/teacher_schedule': (_) => const TeacherSchedulePage(),
              '/teacher_lessons': (_) => const TeacherLessonsPage(),
              '/teacher_balance': (_) => const TeacherBalancePage(),
              '/teacher_timeline': (_) => const TeacherTimelinePage(),
              '/alarm_end': (context) {
                final args = ModalRoute.of(context)!.settings.arguments
                    as Map<String, dynamic>;
                return AlarmEndPage(
                  lessonId: args['lessonId'],
                  student: args['student'],
                  teacherCode: args['teacherCode'],
                );
              },
              '/teacher_end': (context) {
                final args = ModalRoute.of(context)!.settings.arguments
                    as Map<String, dynamic>;
                return TeacherEndLessonPage(payload: args);
              },
              '/teacher_cancel': (context) {
                final args = ModalRoute.of(context)!.settings.arguments
                    as Map<String, dynamic>;
                return TeacherCancelLessonPage(payload: args);
              },
            },
          );
        },
      ),
    );
  }
}

/// بوابة الإقلاع: تقرأ الجلسة من التخزين المحلي (فوري) وتفتح الصفحة المناسبة.
/// لا تقوم بأي تحليل للدروس ولا بإنشاء تنبيهات.
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  static bool _initialActionHandled = false;

  late final Future<Widget> _startup = _resolveStartPage();

  Future<Widget> _resolveStartPage() async {
    final auth = context.read<AuthProvider>();

    // 1) قراءة الجلسة محلياً — بدون شبكة، لذلك الفتح فوري تقريباً
    await auth.loadUserFromStorage();
    final user = auth.currentUser;

    if (user != null) {
      // تحديث بيانات المستخدم لاحقاً في الخلفية دون تعطيل الواجهة
      unawaited(auth.refreshCurrentUserSilently());
      auth.watchDisabled();
      unawaited(_handleInitialNotificationAction(user.role));

      if (user.role == UserRole.admin) return const HomeAdmin();
      if (user.role == UserRole.teacher) return const HomeTeacher();
      return const HomeStudent();
    }

    // 2) لا يوجد مستخدم: نحتاج فقط معرفة إن كان هناك مدير (مع كاش + مهلة)
    bool hasAdmin = true;
    try {
      hasAdmin = await auth
          .adminExists()
          .timeout(const Duration(seconds: 6), onTimeout: () => true);
    } catch (_) {
      hasAdmin = true;
    }

    return hasAdmin ? const LoginPage() : const SetupAdminPage();
  }

  Future<void> _handleInitialNotificationAction(UserRole role) async {
    if (kIsWeb || _initialActionHandled) return;
    _initialActionHandled = true;

    try {
      final action = await AwesomeNotifications()
          .getInitialNotificationAction(removeFromActionEvents: true);
      final payload = action?.payload ?? {};
      if (payload.isEmpty) return;

      final type = (payload['type'] ?? '').toString();
      final lessonId = payload['lessonId'];

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (payload['action'] == 'open_today_page' &&
            role == UserRole.teacher) {
          navigatorKey.currentState?.pushNamed('/today_recurring');
          return;
        }
        if ((type == 'start' || type == 'end') && lessonId != null) {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => type == 'end'
                  ? AlarmEndPage(
                      lessonId: lessonId,
                      student: (payload['student'] ?? '').toString(),
                      teacherCode: payload['teacherCode'],
                    )
                  : AlarmPage(
                      lessonId: lessonId,
                      student: (payload['student'] ?? '').toString(),
                      teacherCode: payload['teacherCode'],
                    ),
            ),
          );
        }
      });
    } catch (e) {
      debugPrint('⚠️ initial notification action: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !snapshot.hasData) {
          return const _SplashScreen();
        }
        return snapshot.data!;
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.heroGradient(context)),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_rounded, size: 72, color: Colors.white),
              SizedBox(height: 16),
              Text(
                'دروس خاص',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 18),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
