import 'package:audioplayers/audioplayers.dart';

import 'alarm_preferences.dart';

class AlarmAudioService {
  static final AudioPlayer _player =
      AudioPlayer(playerId: 'lesson_alarm_player')
        ..audioCache = AudioCache(prefix: '');

  static Future<void> playAlarm({bool looping = true}) async {
    final prefs = await AlarmPreferences.load();
    final option = AlarmPreferences.alarmOption(prefs.alarmSoundId);

    await _player.stop();
    await _player.setReleaseMode(looping ? ReleaseMode.loop : ReleaseMode.stop);
    await _player.setVolume(prefs.alarmVolume);
    await _player.play(AssetSource(option.assetPath));
  }

  static Future<void> preview(String assetPath, {double volume = 0.85}) async {
    await _player.stop();
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setVolume(volume);
    await _player.play(AssetSource(assetPath));
  }

  static Future<void> stop() async {
    await _player.stop();
  }
}
