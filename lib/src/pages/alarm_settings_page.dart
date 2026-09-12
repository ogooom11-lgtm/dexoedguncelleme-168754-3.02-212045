import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/role.dart';
import '../providers/auth_provider.dart';
import '../services/alarm_audio_service.dart';
import '../services/alarm_preferences.dart';
import '../services/notification_orchestrator.dart';
import '../services/notification_service.dart';

class AlarmSettingsPage extends StatefulWidget {
  const AlarmSettingsPage({super.key});

  @override
  State<AlarmSettingsPage> createState() => _AlarmSettingsPageState();
}

class _AlarmSettingsPageState extends State<AlarmSettingsPage> {
  bool _loading = true;
  bool _saving = false;

  String _alarmSoundId = AlarmPreferences.alarmOptions.first.id;
  String _notificationSoundId = AlarmPreferences.notificationOptions.first.id;
  int _snoozeMinutes = 5;
  int _reminderLeadMinutes = 5;
  double _volume = 1;
  bool _vibrationEnabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await AlarmPreferences.load();
    if (!mounted) return;
    setState(() {
      _alarmSoundId = data.alarmSoundId;
      _notificationSoundId = data.notificationSoundId;
      _snoozeMinutes = data.snoozeMinutes;
      _reminderLeadMinutes = data.reminderLeadMinutes;
      _volume = data.alarmVolume;
      _vibrationEnabled = data.vibrationEnabled;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final data = AlarmPreferencesData(
      alarmSoundId: _alarmSoundId,
      notificationSoundId: _notificationSoundId,
      snoozeMinutes: _snoozeMinutes,
      reminderLeadMinutes: _reminderLeadMinutes,
      alarmVolume: _volume,
      vibrationEnabled: _vibrationEnabled,
    );
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;

    try {
      await AlarmPreferences.save(data);
      if (user?.role == UserRole.teacher && (user?.code ?? '').isNotEmpty) {
        await NotificationOrchestrator.rescheduleAll(
            teacherCode: user!.code);
      } else {
        await NotificationService.scheduleDailyMorningReminder();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إعدادات المنبهات')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ الإعدادات: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إعدادات المنبهات'),
          actions: [
            TextButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('حفظ'),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _section(
                    context,
                    title: 'صوت المنبه',
                    icon: Icons.alarm_rounded,
                    children: AlarmPreferences.alarmOptions.map((option) {
                      return _soundTile(
                        option: option,
                        selected: _alarmSoundId == option.id,
                        onSelect: () =>
                            setState(() => _alarmSoundId = option.id),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    context,
                    title: 'صوت الإشعارات',
                    icon: Icons.notifications_active_rounded,
                    children:
                        AlarmPreferences.notificationOptions.map((option) {
                      return _soundTile(
                        option: option,
                        selected: _notificationSoundId == option.id,
                        onSelect: () {
                          setState(() => _notificationSoundId = option.id);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  _section(
                    context,
                    title: 'التوقيت',
                    icon: Icons.tune_rounded,
                    children: [
                      _stepperTile(
                        label: 'تأجيل المنبه',
                        value: _snoozeMinutes,
                        suffix: 'د',
                        min: 1,
                        max: 30,
                        onChanged: (v) => setState(() => _snoozeMinutes = v),
                      ),
                      _stepperTile(
                        label: 'التذكير قبل الدرس',
                        value: _reminderLeadMinutes,
                        suffix: 'د',
                        min: 1,
                        max: 60,
                        onChanged: (v) {
                          setState(() => _reminderLeadMinutes = v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _section(
                    context,
                    title: 'التشغيل',
                    icon: Icons.graphic_eq_rounded,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('مستوى صوت المنبه'),
                        subtitle: Slider(
                          value: _volume,
                          min: 0.2,
                          max: 1,
                          divisions: 8,
                          label: '${(_volume * 100).round()}%',
                          onChanged: (v) => setState(() => _volume = v),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('الاهتزاز'),
                        secondary: Icon(Icons.vibration, color: scheme.primary),
                        value: _vibrationEnabled,
                        onChanged: (v) => setState(() => _vibrationEnabled = v),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _soundTile({
    required AlarmSoundOption option,
    required bool selected,
    required VoidCallback onSelect,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? scheme.primary : scheme.outline,
      ),
      title: Text(option.label),
      trailing: IconButton(
        tooltip: 'تجربة',
        icon: const Icon(Icons.play_circle_outline_rounded),
        onPressed: () => AlarmAudioService.preview(option.assetPath),
      ),
      onTap: onSelect,
    );
  }

  Widget _stepperTile({
    required String label,
    required int value,
    required String suffix,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'إنقاص',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value <= min ? null : () => onChanged(value - 1),
          ),
          SizedBox(
            width: 54,
            child: Text(
              '$value $suffix',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'زيادة',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value >= max ? null : () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}
