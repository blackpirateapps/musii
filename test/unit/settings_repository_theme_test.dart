import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/core/database/app_database.dart';
import 'package:musii/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:musii/features/settings/domain/entities/app_theme_mode.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = SettingsRepositoryImpl(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('SettingsRepository - Theme Mode', () {
    test('defaults to AppThemeMode.system when not set', () async {
      final mode = await repository.getThemeMode();
      expect(mode, equals(AppThemeMode.system));
    });

    test('persists and retrieves AppThemeMode.dark', () async {
      await repository.setThemeMode(AppThemeMode.dark);
      final mode = await repository.getThemeMode();
      expect(mode, equals(AppThemeMode.dark));
    });

    test('persists and retrieves AppThemeMode.light', () async {
      await repository.setThemeMode(AppThemeMode.light);
      final mode = await repository.getThemeMode();
      expect(mode, equals(AppThemeMode.light));
    });

    test(
      'persists and retrieves AppThemeMode.system after modification',
      () async {
        await repository.setThemeMode(AppThemeMode.dark);
        expect(await repository.getThemeMode(), equals(AppThemeMode.dark));

        await repository.setThemeMode(AppThemeMode.system);
        expect(await repository.getThemeMode(), equals(AppThemeMode.system));
      },
    );
  });

  group('AppThemeMode enum & parser', () {
    test('fromString parses known and unknown values gracefully', () {
      expect(AppThemeMode.fromString('dark'), equals(AppThemeMode.dark));
      expect(AppThemeMode.fromString('DARK'), equals(AppThemeMode.dark));
      expect(AppThemeMode.fromString('light'), equals(AppThemeMode.light));
      expect(AppThemeMode.fromString('LIGHT'), equals(AppThemeMode.light));
      expect(AppThemeMode.fromString('system'), equals(AppThemeMode.system));
      expect(AppThemeMode.fromString(''), equals(AppThemeMode.system));
      expect(AppThemeMode.fromString(null), equals(AppThemeMode.system));
      expect(
        AppThemeMode.fromString('invalid_mode'),
        equals(AppThemeMode.system),
      );
    });

    test('label returns human-readable titles', () {
      expect(AppThemeMode.system.label, equals('Follow System'));
      expect(AppThemeMode.dark.label, equals('Dark'));
      expect(AppThemeMode.light.label, equals('Light'));
    });
  });
}
