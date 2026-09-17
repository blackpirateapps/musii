import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/app/app.dart';
import 'package:musii/app/bootstrap/providers.dart';
import 'package:musii/core/database/app_database.dart';
import 'package:musii/features/playback/domain/entities/playback_state.dart';
import 'package:musii/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:musii/features/settings/domain/entities/app_theme_mode.dart';

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

  Widget buildTestApp({AppThemeMode? initialMode}) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        if (initialMode != null)
          themeModeProvider.overrideWith(
            () => _MockThemeModeNotifier(initialMode, settingsRepo),
          ),
        playerStateProvider.overrideWith(
          (ref) => Stream.value(const PlayerStateSnapshot()),
        ),
        currentUserProvider.overrideWith((ref) => Stream.value(null)),
        recentlyPlayedTracksProvider.overrideWith((ref) => Stream.value([])),
        favoriteTracksProvider.overrideWith((ref) => Stream.value([])),
        allTracksProvider('recent').overrideWith((ref) => Stream.value([])),
        allTracksProvider(null).overrideWith((ref) => Stream.value([])),
        allAlbumsProvider.overrideWith((ref) => Stream.value([])),
        allArtistsProvider.overrideWith((ref) => Stream.value([])),
        playlistsProvider.overrideWith((ref) => Stream.value([])),
      ],
      child: const MusiiApp(),
    );
  }

  group('MusiiApp Theme Switching & System Brightness', () {
    testWidgets('adapts to dark mode when system platform brightness is dark', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(() {
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
      });

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      final cupertinoApp = tester.widget<CupertinoApp>(
        find.byType(CupertinoApp),
      );
      expect(cupertinoApp.theme?.brightness, equals(Brightness.dark));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'adapts to light mode when system platform brightness is light',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        addTearDown(() {
          tester.platformDispatcher.clearPlatformBrightnessTestValue();
        });

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        final cupertinoApp = tester.widget<CupertinoApp>(
          find.byType(CupertinoApp),
        );
        expect(cupertinoApp.theme?.brightness, equals(Brightness.light));

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'forces dark mode when themeMode is set to dark, even with light system brightness',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await settingsRepo.setThemeMode(AppThemeMode.dark);

        addTearDown(() {
          tester.platformDispatcher.clearPlatformBrightnessTestValue();
        });

        await tester.pumpWidget(buildTestApp(initialMode: AppThemeMode.dark));
        await tester.pumpAndSettle();

        final cupertinoApp = tester.widget<CupertinoApp>(
          find.byType(CupertinoApp),
        );
        expect(cupertinoApp.theme?.brightness, equals(Brightness.dark));

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'forces light mode when themeMode is set to light, even with dark system brightness',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await settingsRepo.setThemeMode(AppThemeMode.light);

        addTearDown(() {
          tester.platformDispatcher.clearPlatformBrightnessTestValue();
        });

        await tester.pumpWidget(buildTestApp(initialMode: AppThemeMode.light));
        await tester.pumpAndSettle();

        final cupertinoApp = tester.widget<CupertinoApp>(
          find.byType(CupertinoApp),
        );
        expect(cupertinoApp.theme?.brightness, equals(Brightness.light));

        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}

class _MockThemeModeNotifier extends ThemeModeNotifier {
  final AppThemeMode _initialMode;
  final SettingsRepository _repo;

  _MockThemeModeNotifier(this._initialMode, this._repo);

  @override
  AppThemeMode build() {
    return _initialMode;
  }

  @override
  Future<void> setThemeMode(AppThemeMode mode) async {
    state = mode;
    await _repo.setThemeMode(mode);
  }
}
