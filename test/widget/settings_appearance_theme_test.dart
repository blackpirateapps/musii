import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/app/bootstrap/providers.dart';
import 'package:musii/core/database/app_database.dart';
import 'package:musii/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:musii/features/settings/domain/entities/app_theme_mode.dart';
import 'package:musii/features/settings/presentation/pages/settings_page.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settingsRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settingsRepo = SettingsRepositoryImpl(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('SettingsPage Appearance & Theme Mode Selector', () {
    testWidgets(
      'displays Follow System by default and opens action sheet on tap',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              settingsRepositoryProvider.overrideWithValue(settingsRepo),
            ],
            child: const CupertinoApp(home: SettingsPage()),
          ),
        );
        await tester.pumpAndSettle();

        // Verify Appearance section and Theme tile
        expect(find.text('APPEARANCE'), findsOneWidget);
        expect(find.text('Theme'), findsOneWidget);
        expect(find.text('Follow System'), findsOneWidget);

        // Tap Theme tile
        await tester.tap(find.text('Theme'));
        await tester.pumpAndSettle();

        // Action sheet should appear with options
        expect(find.text('Appearance Theme'), findsOneWidget);
        expect(
          find.text('Choose how Musii looks on your device'),
          findsOneWidget,
        );
        expect(find.text('Dark Mode'), findsOneWidget);
        expect(find.text('Light Mode'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);

        // Tap Dark Mode
        await tester.tap(find.text('Dark Mode'));
        await tester.pumpAndSettle();

        // Action sheet should dismiss and theme should update to Dark
        expect(find.text('Appearance Theme'), findsNothing);
        expect(find.text('Dark'), findsOneWidget);

        // Verify DB persistence
        final persistedMode = await settingsRepo.getThemeMode();
        expect(persistedMode, equals(AppThemeMode.dark));
      },
    );

    testWidgets('selecting Light Mode updates state and persistence', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
          ],
          child: const CupertinoApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Theme tile
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();

      // Tap Light Mode
      await tester.tap(find.text('Light Mode'));
      await tester.pumpAndSettle();

      expect(find.text('Light'), findsOneWidget);

      final persistedMode = await settingsRepo.getThemeMode();
      expect(persistedMode, equals(AppThemeMode.light));
    });
  });
}
