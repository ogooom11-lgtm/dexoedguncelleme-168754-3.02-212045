import 'dart:io' show Platform;
import 'package:permission_handler/permission_handler.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:android_intent_plus/android_intent.dart';

class PermissionsGate {
  static Future<bool> shouldShow() async {
    // فقط Android يحتاج هذا الفحص
    if (!Platform.isAndroid) return false;

    // 🔹 فحص إذن الإشعارات (Android 13+)
    bool notifOk = true;
    if (await Permission.notification.isDenied ||
        await Permission.notification.isPermanentlyDenied) {
      notifOk = false;
    } else {
      notifOk = await Permission.notification.isGranted;
    }

    // 🔹 فحص إذن التنبيهات الدقيقة (Exact Alarm)
    bool exactOk = true;
    final status = await Permission.scheduleExactAlarm.status;
    if (status.isDenied || status.isPermanentlyDenied) {
      exactOk = false;
      const packageName = 'com.example.tutor_me'; // غيّرها لاسم الباكيج عندك
      final intent = AndroidIntent(
        action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
        data: 'package:$packageName',
      );
      await intent.launch();
    }

    // 🔹 فحص استثناء توفير الطاقة (Battery Optimization)
    final batteryOk =
        (await DisableBatteryOptimization.isBatteryOptimizationDisabled) ?? false;

    // 🔹 إذا الأذونات كلها جاهزة -> لا داعي للصفحة
    final allOk = notifOk && exactOk && batteryOk;
    return !allOk;
  }
}
