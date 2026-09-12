import 'package:shared_preferences/shared_preferences.dart';

class AlarmSoundOption {
  final String id;
  final String label;
  final String assetPath;
  final String resourcePath;
  final String channelKey;

  const AlarmSoundOption({
    required this.id,
    required this.label,
    required this.assetPath,
    required this.resourcePath,
    required this.channelKey,
  });
}

class AlarmPreferencesData {
  final String alarmSoundId;
  final String notificationSoundId;
  final int snoozeMinutes;
  final int reminderLeadMinutes;
  final double alarmVolume;
  final bool vibrationEnabled;

  const AlarmPreferencesData({
    required this.alarmSoundId,
    required this.notificationSoundId,
    required this.snoozeMinutes,
    required this.reminderLeadMinutes,
    required this.alarmVolume,
    required this.vibrationEnabled,
  });

  Duration get snoozeDuration => Duration(minutes: snoozeMinutes);
  Duration get reminderLeadDuration => Duration(minutes: reminderLeadMinutes);
}

class AlarmPreferences {
  static const _alarmSoundKey = 'alarm_sound_id';
  static const _notificationSoundKey = 'notification_sound_id';
  static const _snoozeMinutesKey = 'alarm_snooze_minutes';
  static const _reminderLeadMinutesKey = 'alarm_reminder_lead_minutes';
  static const _alarmVolumeKey = 'alarm_volume';
  static const _vibrationKey = 'alarm_vibration_enabled';

  static const alarmOptions = <AlarmSoundOption>[
    AlarmSoundOption(
      id: 'focus',
      label: 'تركيز واضح',
      assetPath: 'project_root/assets/sounds/lesson_alarm_focus.wav',
      resourcePath: 'resource://raw/lesson_alarm_focus',
      channelKey: 'lesson_alarm_focus_v2',
    ),
    AlarmSoundOption(
      id: 'soft',
      label: 'هادئ ومتدرج',
      assetPath: 'project_root/assets/sounds/lesson_alarm_soft.wav',
      resourcePath: 'resource://raw/lesson_alarm_soft',
      channelKey: 'lesson_alarm_soft_v2',
    ),
  ];

  static const notificationOptions = <AlarmSoundOption>[
    AlarmSoundOption(
      id: 'chime',
      label: 'تنبيه قصير',
      assetPath: 'project_root/assets/sounds/lesson_notify_chime.wav',
      resourcePath: 'resource://raw/lesson_notify_chime',
      channelKey: 'lesson_notify_chime_v2',
    ),
    AlarmSoundOption(
      id: 'soft',
      label: 'إشعار ناعم',
      assetPath: 'project_root/assets/sounds/lesson_notify_soft.wav',
      resourcePath: 'resource://raw/lesson_notify_soft',
      channelKey: 'lesson_notify_soft_v2',
    ),
  ];

  static AlarmSoundOption alarmOption(String id) {
    return alarmOptions.firstWhere(
      (option) => option.id == id,
      orElse: () => alarmOptions.first,
    );
  }

  static AlarmSoundOption notificationOption(String id) {
    return notificationOptions.firstWhere(
      (option) => option.id == id,
      orElse: () => notificationOptions.first,
    );
  }

  static Future<AlarmPreferencesData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final alarmSoundId =
        prefs.getString(_alarmSoundKey) ?? alarmOptions.first.id;
    final notificationSoundId =
        prefs.getString(_notificationSoundKey) ?? notificationOptions.first.id;

    return AlarmPreferencesData(
      alarmSoundId: alarmOption(alarmSoundId).id,
      notificationSoundId: notificationOption(notificationSoundId).id,
      snoozeMinutes: (prefs.getInt(_snoozeMinutesKey) ?? 5).clamp(1, 30),
      reminderLeadMinutes:
          (prefs.getInt(_reminderLeadMinutesKey) ?? 5).clamp(1, 60),
      alarmVolume: (prefs.getDouble(_alarmVolumeKey) ?? 1.0).clamp(0.2, 1.0),
      vibrationEnabled: prefs.getBool(_vibrationKey) ?? true,
    );
  }

  static Future<void> save(AlarmPreferencesData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_alarmSoundKey, alarmOption(data.alarmSoundId).id);
    await prefs.setString(
      _notificationSoundKey,
      notificationOption(data.notificationSoundId).id,
    );
    await prefs.setInt(_snoozeMinutesKey, data.snoozeMinutes.clamp(1, 30));
    await prefs.setInt(
      _reminderLeadMinutesKey,
      data.reminderLeadMinutes.clamp(1, 60),
    );
    await prefs.setDouble(_alarmVolumeKey, data.alarmVolume.clamp(0.2, 1.0));
    await prefs.setBool(_vibrationKey, data.vibrationEnabled);
  }
}
