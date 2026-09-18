import 'package:drift/drift.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/entities/app_theme_mode.dart';

abstract class SettingsRepository {
  Future<int> getCacheLimitBytes();
  Future<void> setCacheLimitBytes(int bytes);
  Future<bool> getGaplessPlayback();
  Future<void> setGaplessPlayback(bool enabled);
  Future<int> getCrossfadeDurationMs();
  Future<void> setCrossfadeDurationMs(int ms);
  Future<AppThemeMode> getThemeMode();
  Future<void> setThemeMode(AppThemeMode mode);
  Future<bool> getInlineLyricsEnabled();
  Future<void> setInlineLyricsEnabled(bool enabled);
}

class SettingsRepositoryImpl implements SettingsRepository {
  final AppDatabase database;

  SettingsRepositoryImpl({required this.database});

  Future<String?> _getValue(String key) async {
    final record = await (database.select(
      database.appSettings,
    )..where((tbl) => tbl.key.equals(key))).getSingleOrNull();
    return record?.value;
  }

  Future<void> _setValue(String key, String value) async {
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion(key: Value(key), value: Value(value)),
        );
  }

  @override
  Future<int> getCacheLimitBytes() async {
    final val = await _getValue('cache_limit_bytes');
    return int.tryParse(val ?? '') ?? AppAudioConstants.defaultCacheSizeBytes;
  }

  @override
  Future<void> setCacheLimitBytes(int bytes) async {
    // Validate min/max boundaries
    final clamped = bytes.clamp(
      AppAudioConstants.minCacheSizeBytes,
      AppAudioConstants.maxCacheSizeBytes,
    );
    await _setValue('cache_limit_bytes', clamped.toString());
  }

  @override
  Future<bool> getGaplessPlayback() async {
    final val = await _getValue('gapless_playback');
    return val != 'false';
  }

  @override
  Future<void> setGaplessPlayback(bool enabled) async {
    await _setValue('gapless_playback', enabled.toString());
  }

  @override
  Future<int> getCrossfadeDurationMs() async {
    final val = await _getValue('crossfade_duration_ms');
    return int.tryParse(val ?? '') ?? 0;
  }

  @override
  Future<void> setCrossfadeDurationMs(int ms) async {
    await _setValue('crossfade_duration_ms', ms.clamp(0, 10000).toString());
  }

  @override
  Future<AppThemeMode> getThemeMode() async {
    final val = await _getValue('theme_mode');
    return AppThemeMode.fromString(val);
  }

  @override
  Future<void> setThemeMode(AppThemeMode mode) async {
    await _setValue('theme_mode', mode.name);
  }

  @override
  Future<bool> getInlineLyricsEnabled() async {
    final val = await _getValue('inline_lyrics_enabled');
    return val != 'false';
  }

  @override
  Future<void> setInlineLyricsEnabled(bool enabled) async {
    await _setValue('inline_lyrics_enabled', enabled.toString());
  }
}
