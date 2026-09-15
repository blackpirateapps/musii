import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/app/bootstrap/providers.dart';
import 'package:musii/core/constants/app_constants.dart';
import 'package:musii/core/database/app_database.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/library/presentation/pages/home_page.dart';
import 'package:musii/features/library/presentation/pages/library_page.dart';
import 'package:musii/features/playback/domain/entities/playback_state.dart';
import 'package:musii/features/playlists/domain/entities/playlist.dart';
import 'package:musii/features/search/presentation/pages/search_page.dart';
import 'package:musii/features/settings/presentation/pages/settings_page.dart';

void main() {
  const sampleTrack = Track(
    id: 't_home_1',
    driveFileId: 'df_1',
    sourceId: 'src_1',
    title: 'Ride on Time',
    normalizedTitle: 'ride on time',
    artistName: 'Tatsuro Yamashita',
    albumName: 'Ride on Time',
    format: 'FLAC',
  );

  const sampleAlbum = Album(
    id: 'alb_1',
    title: 'Ride on Time',
    normalizedTitle: 'ride on time',
    artistName: 'Tatsuro Yamashita',
    trackCount: 9,
  );

  const sampleArtist = Artist(
    id: 'art_1',
    name: 'Tatsuro Yamashita',
    normalizedName: 'tatsuro yamashita',
    trackCount: 9,
    albumCount: 1,
  );

  group('HomePage', () {
    testWidgets('renders dynamic greeting and library sections with real data', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            playerStateProvider.overrideWith(
              (ref) => Stream.value(const PlayerStateSnapshot()),
            ),
            recentlyPlayedTracksProvider.overrideWith(
              (ref) => Stream.value([sampleTrack]),
            ),
            favoriteTracksProvider.overrideWith(
              (ref) => Stream.value([sampleTrack]),
            ),
            allTracksProvider('recent').overrideWith(
              (ref) => Stream.value([sampleTrack]),
            ),
            allAlbumsProvider.overrideWith(
              (ref) => Stream.value([sampleAlbum]),
            ),
            allArtistsProvider.overrideWith(
              (ref) => Stream.value([sampleArtist]),
            ),
            playlistsProvider.overrideWith(
              (ref) => Stream.value([]),
            ),
          ],
          child: const CupertinoApp(
            home: HomePage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final expectedGreeting = AppGreeting.getGreeting();
      expect(find.text(expectedGreeting), findsWidgets);
      expect(find.text('Recently Played'), findsOneWidget);
      expect(find.text('Favorites'), findsOneWidget);
      expect(find.text('Recently Added'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Artists'), findsOneWidget);
    });
  });

  group('LibraryPage', () {
    testWidgets('renders segmented control with Albums, Artists, Songs, Playlists', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            playerStateProvider.overrideWith(
              (ref) => Stream.value(const PlayerStateSnapshot()),
            ),
            allAlbumsProvider.overrideWith(
              (ref) => Stream.value([sampleAlbum]),
            ),
            allArtistsProvider.overrideWith(
              (ref) => Stream.value([sampleArtist]),
            ),
            allTracksProvider(null).overrideWith(
              (ref) => Stream.value([sampleTrack]),
            ),
            allTracksProvider('title').overrideWith(
              (ref) => Stream.value([sampleTrack]),
            ),
            playlistsProvider.overrideWith(
              (ref) => Stream.value([
                Playlist(
                  id: 'pl_1',
                  name: 'Summer Vibes',
                  trackCount: 5,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ),
              ]),
            ),
          ],
          child: const CupertinoApp(
            home: LibraryPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Library'), findsWidgets);
      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Songs'), findsOneWidget);
      expect(find.text('Playlists'), findsOneWidget);

      // Default tab is Albums: sampleAlbum is rendered
      expect(find.text('Ride on Time'), findsWidgets);
    });
  });

  group('SearchPage', () {
    testWidgets('renders search text field and debounced search UI', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            playerStateProvider.overrideWith(
              (ref) => Stream.value(const PlayerStateSnapshot()),
            ),
            searchQueryStateProvider.overrideWith(() => SearchQueryNotifier()),
          ],
          child: const CupertinoApp(
            home: SearchPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Search'), findsOneWidget);
      expect(find.byType(CupertinoSearchTextField), findsOneWidget);
    });
  });

  group('SettingsPage', () {
    testWidgets('renders Playback, Storage & Cache, Google Drive, and About Cupertino sections', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            currentUserProvider.overrideWith((ref) => Stream.value(null)),
            cacheSizeProvider.overrideWith((ref) => Stream.value(1024 * 1024 * 50)),
            allTracksProvider('title').overrideWith((ref) => Stream.value([sampleTrack])),
          ],
          child: const CupertinoApp(
            home: SettingsPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('GOOGLE DRIVE'), findsOneWidget);
      expect(find.text('PLAYBACK'), findsOneWidget);
      expect(find.text('STORAGE & CACHE'), findsOneWidget);
      expect(find.text('APPEARANCE'), findsOneWidget);
      expect(find.text('ABOUT'), findsOneWidget);
      expect(find.text('Gapless Playback'), findsOneWidget);
      expect(find.text('Current Cache Usage'), findsOneWidget);
      expect(find.text('Automatic Cache Limit'), findsOneWidget);
      expect(find.text('Connect Google Drive'), findsOneWidget);
      expect(find.text('Musii'), findsOneWidget);
      expect(find.text('Open Source Licenses'), findsOneWidget);
    });
  });
}
