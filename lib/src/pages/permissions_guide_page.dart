import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:app_settings/app_settings.dart';

class PermissionsGuidePage extends StatefulWidget {
  const PermissionsGuidePage({super.key});

  @override
  State<PermissionsGuidePage> createState() => _PermissionsGuidePageState();
}

class _PermissionsGuidePageState extends State<PermissionsGuidePage> {
  bool _exactAlarmDone = false;
  bool _batteryDone = false;
  bool _notificationsDone = false;
  bool _saving = false;

  /// 🔔 فتح إعداد التنبيهات الدقيقة (Exact Alarm)
  Future<void> _openExactAlarmSettings() async {
    if (!Platform.isAndroid) return;
    try {
      const packageName = 'com.example.tutor_me';
      final intent = AndroidIntent(
        action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
        data: 'package:$packageName',
      );
      await intent.launch();
    } catch (_) {
      await AppSettings.openAppSettings();
    }
  }

  /// 🔋 فتح إعدادات البطارية
  Future<void> _openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.batteryOptimization);
    } catch (_) {
      await AppSettings.openAppSettings();
    }
  }

  /// 📱 فتح إعدادات الإشعارات
  Future<void> _openNotificationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    } catch (_) {
      await AppSettings.openAppSettings();
    }
  }

  /// ✅ إنهاء الخطوات
  Future<void> _finish() async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_permissions_done_v2', true);
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final ready = _exactAlarmDone && _batteryDone && _notificationsDone;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('⚙️ تهيئة أذونات الإشعارات'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text(
                '📲 لضمان وصول إشعارات بداية ونهاية الدروس بدقة، يرجى تنفيذ الخطوات التالية:',
                style: TextStyle(fontSize: 17, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              _buildStepCard(
                icon: Icons.alarm,
                title: 'السماح بالتنبيهات الدقيقة (Exact Alarms)',
                subtitle:
                'يسمح للتطبيق بجدولة المنبهات في الوقت المحدد تمامًا دون تأخير.',
                done: _exactAlarmDone,
                onPressed: _openExactAlarmSettings,
                onChanged: (v) => setState(() => _exactAlarmDone = v ?? false),
                buttonText: 'فتح إعداد التنبيهات الدقيقة',
              ),

              _buildStepCard(
                icon: Icons.battery_saver,
                title: 'تعطيل تحسينات البطارية',
                subtitle:
                'لضمان عمل الإشعارات في الخلفية دون تأخير أو إيقاف التطبيق.',
                done: _batteryDone,
                onPressed: _openBatteryOptimizationSettings,
                onChanged: (v) => setState(() => _batteryDone = v ?? false),
                buttonText: 'فتح إعدادات البطارية',
              ),

              _buildStepCard(
                icon: Icons.notifications_active,
                title: 'تفعيل الإشعارات و Full Screen',
                subtitle:
                'تأكد أن إشعارات التطبيق مفعلة بالكامل وصوت القناة مرفوع.',
                done: _notificationsDone,
                onPressed: _openNotificationSettings,
                onChanged: (v) => setState(() => _notificationsDone = v ?? false),
                buttonText: 'فتح إعدادات الإشعارات',
              ),

              const SizedBox(height: 30),

              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _saving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                      : const Icon(Icons.check_circle_outline, size: 22),
                  label: Text(
                    _saving
                        ? 'جاري الحفظ...'
                        : ready
                        ? 'تم — المتابعة'
                        : 'أكمل الخطوات أولاً',
                    style: const TextStyle(fontSize: 17),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor:
                    ready ? accent : Colors.grey.shade400.withOpacity(0.7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: ready ? 4 : 0,
                  ),
                  onPressed: (ready && !_saving) ? _finish : null,
                ),
              ),

              const SizedBox(height: 12),

              TextButton(
                onPressed: _saving ? null : _finish,
                child: const Text(
                  'تخطي الآن (يمكن ضبطها لاحقًا)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool done,
    required VoidCallback onPressed,
    required ValueChanged<bool?> onChanged,
    required String buttonText,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: done
            ? Colors.green.shade50
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    size: 26,
                    color: done
                        ? Colors.green.shade700
                        : Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.bold,
                      color: done ? Colors.green.shade800 : Colors.black87,
                    ),
                  ),
                ),
                Checkbox(
                  value: done,
                  onChanged: onChanged,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(height: 1.4)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.settings),
              label: Text(buttonText),
              style: OutlinedButton.styleFrom(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
