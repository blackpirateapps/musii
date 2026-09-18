import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/app/bootstrap/providers.dart';
import 'package:musii/core/database/app_database.dart';
import 'package:musii/features/last_fm/presentation/providers/last_fm_providers.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/lyrics/domain/entities/lyric_model.dart';
import 'package:musii/features/lyrics/presentation/pages/lyrics_sheet.dart';
import 'package:musii/features/lyrics/presentation/widgets/word_synced_lyric_text.dart';
import 'package:musii/features/playback/domain/entities/playback_state.dart';
import 'package:musii/features/playback/presentation/pages/now_playing_page.dart';
import 'package:musii/features/playback/presentation/widgets/now_playing_inline_lyrics.dart';
import 'package:musii/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:musii/features/settings/presentation/pages/settings_page.dart';

Finder findCurrentLyricSemantics(String text) {
  return find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == 'Current lyric: $text',
  );
}

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

  const track1 = Track(
    id: 'track_1',
    driveFileId: 'drive_1',
    sourceId: 'source_1',
    title: 'Stay With Me',
    normalizedTitle: 'stay with me',
    artistName: 'Miki Matsubara',
    albumName: 'Best Collection',
    format: 'FLAC',
    bitrate: 706000,
    durationMs: 243000,
  );

  const track2 = Track(
    id: 'track_2',
    driveFileId: 'drive_2',
    sourceId: 'source_2',
    title: 'Plastic Love',
    normalizedTitle: 'plastic love',
    artistName: 'Mariya Takeuchi',
    albumName: 'Variety',
    format: 'MP3',
    bitrate: 320000,
    durationMs: 290000,
  );

  const syncedLyricsTrack1 = TrackLyrics(
    id: 'lyric_1',
    trackId: 'track_1',
    source: LyricSource.embeddedSynced,
    isSynchronized: true,
    lines: [
      LyricLine(
        timestampMs: 0,
        text: 'First intro line',
        sequence: 0,
        words: [
          LyricWord(startMs: 0, endMs: 800, text: 'First', index: 0),
          LyricWord(startMs: 800, endMs: 1600, text: 'intro', index: 1),
          LyricWord(startMs: 1600, endMs: 2400, text: 'line', index: 2),
        ],
      ),
      LyricLine(
        timestampMs: 5000,
        text: 'Stay with me',
        sequence: 1,
        words: [
          LyricWord(startMs: 5000, endMs: 6000, text: 'Stay', index: 0),
          LyricWord(startMs: 6000, endMs: 7000, text: 'with', index: 1),
          LyricWord(startMs: 7000, endMs: 8500, text: 'me', index: 2),
        ],
      ),
      LyricLine(
        timestampMs: 10000,
        text: 'Mayonaka no door o tataki',
        sequence: 2,
        words: [], // Standard line-synced LRC without word timestamps
      ),
      LyricLine(
        timestampMs: 25000,
        text: 'Kaeranaide to naita',
        sequence: 3,
        words: [],
      ),
    ],
  );

  const plainLyricsTrack1 = TrackLyrics(
    id: 'lyric_plain_1',
    trackId: 'track_1',
    source: LyricSource.embeddedPlain,
    isSynchronized: false,
    rawText: 'Unsynchronized line 1\nUnsynchronized line 2',
    lines: [
      LyricLine(timestampMs: 0, text: 'Unsynchronized line 1', sequence: 0),
      LyricLine(timestampMs: 0, text: 'Unsynchronized line 2', sequence: 1),
    ],
  );

  group('Inline Synced Lyrics - Settings & Persistence', () {
    test(
      'default enabled is true in SettingsRepository and persists',
      () async {
        final defaultVal = await settingsRepo.getInlineLyricsEnabled();
        expect(defaultVal, isTrue);

        await settingsRepo.setInlineLyricsEnabled(false);
        final updatedVal = await settingsRepo.getInlineLyricsEnabled();
        expect(updatedVal, isFalse);

        await settingsRepo.setInlineLyricsEnabled(true);
        final restoredVal = await settingsRepo.getInlineLyricsEnabled();
        expect(restoredVal, isTrue);
      },
    );

    testWidgets(
      'SettingsPage renders Inline Synced Lyrics switch under LYRICS',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              settingsRepositoryProvider.overrideWithValue(settingsRepo),
              lastFmAccountProvider.overrideWith((ref) => Stream.value(null)),
            ],
            child: const CupertinoApp(home: SettingsPage()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('LYRICS'), findsOneWidget);
        expect(find.text('Inline Synced Lyrics'), findsOneWidget);
        expect(
          find.text('Show synchronized lyrics on the Now Playing screen'),
          findsOneWidget,
        );

        // Verify toggle switches setting
        final switchFinder = find.byType(CupertinoSwitch);
        expect(switchFinder, findsWidgets);

        // Find switch for Inline Synced Lyrics tile
        final inlineTile = find.ancestor(
          of: find.text('Inline Synced Lyrics'),
          matching: find.byType(CupertinoListTile),
        );
        final tileSwitch = find.descendant(
          of: inlineTile,
          matching: find.byType(CupertinoSwitch),
        );
        expect(tileSwitch, findsOneWidget);

        await tester.tap(tileSwitch);
        await tester.pumpAndSettle();

        final persisted = await settingsRepo.getInlineLyricsEnabled();
        expect(persisted, isFalse);
      },
    );
  });

  group('Inline Synced Lyrics - Presentation on Now Playing', () {
    testWidgets(
      'renders hero line, previous line, and next line when synchronized lyrics exist',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              settingsRepositoryProvider.overrideWithValue(settingsRepo),
              lastFmAccountProvider.overrideWith((ref) => Stream.value(null)),
              playerStateProvider.overrideWith(
                (ref) => Stream.value(
                  const PlayerStateSnapshot(
                    currentTrack: track1,
                    duration: Duration(milliseconds: 243000),
                    position: Duration(milliseconds: 5500),
                    isPlaying: true,
                  ),
                ),
              ),
              trackLyricsProvider('track_1')
                  .overrideWith((ref) => Stream.value(syncedLyricsTrack1)),
              isTrackFavoriteProvider('track_1')
                  .overrideWith((ref) => Stream.value(false)),
            ],
            child: const CupertinoApp(home: NowPlayingPage()),
          ),
        );
        await tester.pumpAndSettle();

        // Hero line (active line at 5500ms is line 1 with words: "Stay", "with", "me")
        expect(findCurrentLyricSemantics('Stay with me'), findsOneWidget);
        expect(find.text('Stay'), findsOneWidget);
        expect(find.text('with'), findsOneWidget);
        expect(find.text('me'), findsOneWidget);

        // Previous line (line 0: "First intro line")
        expect(find.text('First intro line'), findsOneWidget);

        // Next line (line 2: "Mayonaka no door o tataki")
        expect(find.text('Mayonaka no door o tataki'), findsOneWidget);
      },
    );

    testWidgets('advancing playback position smoothly updates active line', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final stateController = StreamController<PlayerStateSnapshot>();
      addTearDown(stateController.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
            lastFmAccountProvider.overrideWith((ref) => Stream.value(null)),
            playerStateProvider.overrideWith((ref) => stateController.stream),
            trackLyricsProvider('track_1')
                .overrideWith((ref) => Stream.value(syncedLyricsTrack1)),
            isTrackFavoriteProvider('track_1')
                .overrideWith((ref) => Stream.value(false)),
          ],
          child: const CupertinoApp(home: NowPlayingPage()),
        ),
      );

      // Initial state: position at 1000ms (line 0: word-synced "First intro line")
      stateController.add(
        const PlayerStateSnapshot(
          currentTrack: track1,
          duration: Duration(milliseconds: 243000),
          position: Duration(milliseconds: 1000),
          isPlaying: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(findCurrentLyricSemantics('First intro line'), findsOneWidget);

      // Advance position to 11000ms (line 2: standard line-synced "Mayonaka no door o tataki")
      stateController.add(
        const PlayerStateSnapshot(
          currentTrack: track1,
          duration: Duration(milliseconds: 243000),
          position: Duration(milliseconds: 11000),
          isPlaying: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mayonaka no door o tataki'), findsOneWidget);
      expect(find.text('Stay with me'), findsOneWidget); // now previous line
    });

    testWidgets(
      'cold-start mid-playback immediately selects correct active line',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Cold start directly at 12000ms
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              settingsRepositoryProvider.overrideWithValue(settingsRepo),
              lastFmAccountProvider.overrideWith((ref) => Stream.value(null)),
              playerStateProvider.overrideWith(
                (ref) => Stream.value(
                  const PlayerStateSnapshot(
                    currentTrack: track1,
                    duration: Duration(milliseconds: 243000),
                    position: Duration(milliseconds: 12000),
                    isPlaying: true,
                  ),
                ),
              ),
              trackLyricsProvider('track_1')
                  .overrideWith((ref) => Stream.value(syncedLyricsTrack1)),
              isTrackFavoriteProvider('track_1')
                  .overrideWith((ref) => Stream.value(false)),
            ],
            child: const CupertinoApp(home: NowPlayingPage()),
          ),
        );
        await tester.pumpAndSettle();

        // Should immediately show Line 2 as active without starting from Line 0
        expect(find.text('Mayonaka no door o tataki'), findsOneWidget);
        expect(find.text('Stay with me'), findsOneWidget); // line 1 as previous
      },
    );

    testWidgets('word-synced line highlights words progressively', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Position at 6500ms: word 0 ("Stay") completed, word 1 ("with") active, word 2 ("me") future
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
            lastFmAccountProvider.overrideWith((ref) => Stream.value(null)),
            playerStateProvider.overrideWith(
              (ref) => Stream.value(
                const PlayerStateSnapshot(
                  currentTrack: track1,
                  duration: Duration(milliseconds: 243000),
                  position: Duration(milliseconds: 6500),
                  isPlaying: true,
                ),
              ),
            ),
            trackLyricsProvider('track_1')
                .overrideWith((ref) => Stream.value(syncedLyricsTrack1)),
            isTrackFavoriteProvider('track_1')
                .overrideWith((ref) => Stream.value(false)),
          ],
          child: const CupertinoApp(home: NowPlayingPage()),
        ),
      );
      await tester.pumpAndSettle();

      // WordSyncedLyricText renders all words of the active line in a RichText
      expect(find.byType(WordSyncedLyricText), findsOneWidget);
      expect(find.text('Stay'), findsOneWidget);
      expect(find.text('with'), findsOneWidget);
      expect(find.text('me'), findsOneWidget);
    });

    testWidgets('toggling Inline Synced Lyrics OFF collapses lyric area', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          settingsRepositoryProvider.overrideWithValue(settingsRepo),
          lastFmAccountProvider.overrideWith((ref) => Stream.value(null)),
          playerStateProvider.overrideWith(
            (ref) => Stream.value(
              const PlayerStateSnapshot(
                currentTrack: track1,
                duration: Duration(milliseconds: 243000),
                position: Duration(milliseconds: 5500),
                isPlaying: true,
              ),
            ),
          ),
          trackLyricsProvider('track_1')
              .overrideWith((ref) => Stream.value(syncedLyricsTrack1)),
          isTrackFavoriteProvider('track_1')
              .overrideWith((ref) => Stream.value(false)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CupertinoApp(home: NowPlayingPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Currently visible
      expect(findCurrentLyricSemantics('Stay with me'), findsOneWidget);

      // Disable inline lyrics via notifier
      await container
          .read(inlineLyricsEnabledProvider.notifier)
          .setEnabled(false);
      await tester.pumpAndSettle();

      // Lyric line should no longer be visible (collapsed to 0 height)
      expect(findCurrentLyricSemantics('Stay with me'), findsNothing);

      // Re-enable inline lyrics
      await container
          .read(inlineLyricsEnabledProvider.notifier)
          .setEnabled(true);
      await tester.pumpAndSettle();

      expect(findCurrentLyricSemantics('Stay with me'), findsOneWidget);
    });

    testWidgets(
      'plain unsynchronized lyrics do not display inline and collapse',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              settingsRepositoryProvider.overrideWithValue(settingsRepo),
              lastFmAccountProvider.overrideWith((ref) => Stream.value(null)),
              playerStateProvider.overrideWith(
                (ref) => Stream.value(
                  const PlayerStateSnapshot(
                    currentTrack: track1,
                    duration: Duration(milliseconds: 243000),
                    position: Duration(milliseconds: 5500),
                    isPlaying: true,
                  ),
                ),
              ),
              trackLyricsProvider('track_1')
                  .overrideWith((ref) => Stream.value(plainLyricsTrack1)),
              isTrackFavoriteProvider('track_1')
                  .overrideWith((ref) => Stream.value(false)),
            ],
            child: const CupertinoApp(home: NowPlayingPage()),
          ),
        );
        await tester.pumpAndSettle();

        // Plain lyrics should NOT appear inline
        expect(find.text('Unsynchronized line 1'), findsNothing);
        expect(find.text('Unsynchronized line 2'), findsNothing);

        // Scrubber and controls remain intact
        expect(find.byIcon(CupertinoIcons.play_fill), findsNothing);
        expect(find.byIcon(CupertinoIcons.pause_fill), findsOneWidget);
      },
    );

    testWidgets(
      'no lyrics collapses gracefully without placeholder or fake text',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              settingsRepositoryProvider.overrideWithValue(settingsRepo),
              lastFmAccountProvider.overrideWith((ref) => Stream.value(null)),
              playerStateProvider.overrideWith(
                (ref) => Stream.value(
                  const PlayerStateSnapshot(
                    currentTrack: track1,
                    duration: Duration(milliseconds: 243000),
                    position: Duration(milliseconds: 5500),
                    isPlaying: true,
                  ),
                ),
              ),
              trackLyricsProvider('track_1')
                  .overrideWith((ref) => Stream.value(null)),
              isTrackFavoriteProvider('track_1')
                  .overrideWith((ref) => Stream.value(false)),
            ],
            child: const CupertinoApp(home: NowPlayingPage()),
          ),
        );
        await tester.pumpAndSettle();

        // No fake text
        expect(find.text('Instrumental'), findsNothing);
        expect(find.text('No lyrics'), findsNothing);
        expect(find.text('♪'), findsNothing);
      },
    );

    testWidgets('tapping inline lyric opens full LyricsSheet at active line', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
            lastFmAccountProvider.overrideWith((ref) => Stream.value(null)),
            playerStateProvider.overrideWith(
              (ref) => Stream.value(
                const PlayerStateSnapshot(
                  currentTrack: track1,
                  duration: Duration(milliseconds: 243000),
                  position: Duration(milliseconds: 5500),
                  isPlaying: true,
                ),
              ),
            ),
            trackLyricsProvider('track_1')
                .overrideWith((ref) => Stream.value(syncedLyricsTrack1)),
            isTrackFavoriteProvider('track_1')
                .overrideWith((ref) => Stream.value(false)),
          ],
          child: const CupertinoApp(home: NowPlayingPage()),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on the inline lyric area
      await tester.tap(find.byType(NowPlayingInlineLyrics));
      await tester.pumpAndSettle();

      // Full LyricsSheet should now be displayed
      expect(find.byType(LyricsSheet), findsOneWidget);
      expect(find.text('Lyrics'), findsOneWidget);
    });

    testWidgets('switching tracks never leaks previous track lyrics', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final stateController = StreamController<PlayerStateSnapshot>();
      addTearDown(stateController.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
            lastFmAccountProvider.overrideWith((ref) => Stream.value(null)),
            playerStateProvider.overrideWith((ref) => stateController.stream),
            trackLyricsProvider('track_1')
                .overrideWith((ref) => Stream.value(syncedLyricsTrack1)),
            trackLyricsProvider('track_2').overrideWith(
              (ref) => Stream.value(null),
            ), // track 2 has no lyrics
            isTrackFavoriteProvider('track_1')
                .overrideWith((ref) => Stream.value(false)),
            isTrackFavoriteProvider('track_2')
                .overrideWith((ref) => Stream.value(false)),
          ],
          child: const CupertinoApp(home: NowPlayingPage()),
        ),
      );

      // Track 1 playing with lyrics
      stateController.add(
        const PlayerStateSnapshot(
          currentTrack: track1,
          duration: Duration(milliseconds: 243000),
          position: Duration(milliseconds: 5500),
          isPlaying: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(findCurrentLyricSemantics('Stay with me'), findsOneWidget);

      // Switch to Track 2 (no lyrics)
      stateController.add(
        const PlayerStateSnapshot(
          currentTrack: track2,
          duration: Duration(milliseconds: 290000),
          position: Duration(milliseconds: 1000),
          isPlaying: true,
        ),
      );
      await tester.pumpAndSettle();

      // Track 1 lyrics must NOT leak into Track 2
      expect(findCurrentLyricSemantics('Stay with me'), findsNothing);
      expect(find.text('First intro line'), findsNothing);
      expect(find.text('Plastic Love'), findsOneWidget);
    });

    testWidgets(
      'instrumental section fades lyric opacity to let interface breathe',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final stateController = StreamController<PlayerStateSnapshot>();
        addTearDown(stateController.close);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              settingsRepositoryProvider.overrideWithValue(settingsRepo),
              lastFmAccountProvider.overrideWith((ref) => Stream.value(null)),
              playerStateProvider.overrideWith((ref) => stateController.stream),
              trackLyricsProvider('track_1')
                  .overrideWith((ref) => Stream.value(syncedLyricsTrack1)),
              isTrackFavoriteProvider('track_1')
                  .overrideWith((ref) => Stream.value(false)),
            ],
            child: const CupertinoApp(home: NowPlayingPage()),
          ),
        );

        // Line 2 active at 11000ms
        stateController.add(
          const PlayerStateSnapshot(
            currentTrack: track1,
            duration: Duration(milliseconds: 243000),
            position: Duration(milliseconds: 11000),
            isPlaying: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Mayonaka no door o tataki'), findsOneWidget);

        // Now advance to 18000ms (instrumental gap: line 2 ended, next line at 25000ms)
        stateController.add(
          const PlayerStateSnapshot(
            currentTrack: track1,
            duration: Duration(milliseconds: 243000),
            position: Duration(milliseconds: 18000),
            isPlaying: true,
          ),
        );
        await tester.pumpAndSettle();

        // Find the AnimatedOpacity for the hero lyric
        final opacityFinder = find.byWidgetPredicate(
          (w) => w is AnimatedOpacity && w.opacity == 0.0,
        );
        expect(opacityFinder, findsOneWidget);

        // Now reach Line 3 at 25500ms
        stateController.add(
          const PlayerStateSnapshot(
            currentTrack: track1,
            duration: Duration(milliseconds: 243000),
            position: Duration(milliseconds: 25500),
            isPlaying: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Kaeranaide to naita'), findsOneWidget);
      },
    );

    testWidgets('seeking updates line and word highlight immediately', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final stateController = StreamController<PlayerStateSnapshot>();
      addTearDown(stateController.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
            lastFmAccountProvider.overrideWith((ref) => Stream.value(null)),
            playerStateProvider.overrideWith((ref) => stateController.stream),
            trackLyricsProvider('track_1')
                .overrideWith((ref) => Stream.value(syncedLyricsTrack1)),
            isTrackFavoriteProvider('track_1')
                .overrideWith((ref) => Stream.value(false)),
          ],
          child: const CupertinoApp(home: NowPlayingPage()),
        ),
      );

      // Start at 500ms (Line 0)
      stateController.add(
        const PlayerStateSnapshot(
          currentTrack: track1,
          duration: Duration(milliseconds: 243000),
          position: Duration(milliseconds: 500),
          isPlaying: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(findCurrentLyricSemantics('First intro line'), findsOneWidget);

      // User seeks to 10500ms (Line 2)
      stateController.add(
        const PlayerStateSnapshot(
          currentTrack: track1,
          duration: Duration(milliseconds: 243000),
          position: Duration(milliseconds: 10500),
          isPlaying: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mayonaka no door o tataki'), findsOneWidget);
      expect(find.text('Stay with me'), findsOneWidget); // previous line
    });

    testWidgets('renders properly with Light theme', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
            lastFmAccountProvider.overrideWith((ref) => Stream.value(null)),
            playerStateProvider.overrideWith(
              (ref) => Stream.value(
                const PlayerStateSnapshot(
                  currentTrack: track1,
                  duration: Duration(milliseconds: 243000),
                  position: Duration(milliseconds: 5500),
                  isPlaying: true,
                ),
              ),
            ),
            trackLyricsProvider('track_1')
                .overrideWith((ref) => Stream.value(syncedLyricsTrack1)),
            isTrackFavoriteProvider('track_1')
                .overrideWith((ref) => Stream.value(false)),
          ],
          child: const CupertinoApp(
            theme: CupertinoThemeData(brightness: Brightness.light),
            home: NowPlayingPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(findCurrentLyricSemantics('Stay with me'), findsOneWidget);
      expect(find.text('Stay'), findsOneWidget);
      expect(find.text('with'), findsOneWidget);
      expect(find.text('me'), findsOneWidget);
    });

    testWidgets(
      'instrumental intro displays animated vocal dots and previews upcoming first line',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const introTrackLyrics = TrackLyrics(
          id: 'lyric_intro',
          trackId: 'track_1',
          source: LyricSource.embeddedSynced,
          isSynchronized: true,
          lines: [
            LyricLine(
              timestampMs: 15000,
              text: 'Midnight memories fade away',
              sequence: 0,
              words: [
                LyricWord(
                  startMs: 15000,
                  endMs: 16000,
                  text: 'Midnight',
                  index: 0,
                ),
                LyricWord(
                  startMs: 16000,
                  endMs: 17000,
                  text: 'memories',
                  index: 1,
                ),
              ],
            ),
          ],
        );

        final stateController = StreamController<PlayerStateSnapshot>();
        addTearDown(stateController.close);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              settingsRepositoryProvider.overrideWithValue(settingsRepo),
              lastFmAccountProvider.overrideWith((ref) => Stream.value(null)),
              playerStateProvider.overrideWith((ref) => stateController.stream),
              trackLyricsProvider('track_1')
                  .overrideWith((ref) => Stream.value(introTrackLyrics)),
              isTrackFavoriteProvider('track_1')
                  .overrideWith((ref) => Stream.value(false)),
            ],
            child: const CupertinoApp(home: NowPlayingPage()),
          ),
        );

        // Position at 2000ms: Instrumental intro
        stateController.add(
          const PlayerStateSnapshot(
            currentTrack: track1,
            duration: Duration(milliseconds: 243000),
            position: Duration(milliseconds: 2000),
            isPlaying: true,
          ),
        );
        await tester.pumpAndSettle();

        // Vocal dots are active in ambient breathing phase
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics && w.properties.label == 'Instrumental section',
          ),
          findsOneWidget,
        );
        // Upcoming first lyric is previewed in bottom slot
        expect(find.text('Midnight memories fade away'), findsOneWidget);

        // Advance to 12500ms (2.5s before vocals: countdown 3)
        stateController.add(
          const PlayerStateSnapshot(
            currentTrack: track1,
            duration: Duration(milliseconds: 243000),
            position: Duration(milliseconds: 12500),
            isPlaying: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Vocals start in 3',
          ),
          findsOneWidget,
        );

        // Advance to 13500ms (1.5s before vocals: countdown 2)
        stateController.add(
          const PlayerStateSnapshot(
            currentTrack: track1,
            duration: Duration(milliseconds: 243000),
            position: Duration(milliseconds: 13500),
            isPlaying: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Vocals start in 2',
          ),
          findsOneWidget,
        );

        // Advance to 14500ms (0.5s before vocals: countdown 1)
        stateController.add(
          const PlayerStateSnapshot(
            currentTrack: track1,
            duration: Duration(milliseconds: 243000),
            position: Duration(milliseconds: 14500),
            isPlaying: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Vocals start in 1',
          ),
          findsOneWidget,
        );

        // Vocals begin at 15500ms: Hero lyric active in center spotlight!
        stateController.add(
          const PlayerStateSnapshot(
            currentTrack: track1,
            duration: Duration(milliseconds: 243000),
            position: Duration(milliseconds: 15500),
            isPlaying: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          findCurrentLyricSemantics('Midnight memories fade away'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'mid-song solo triggers vocal dots countdown and previews next lyric',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const soloTrackLyrics = TrackLyrics(
          id: 'lyric_solo',
          trackId: 'track_1',
          source: LyricSource.embeddedSynced,
          isSynchronized: true,
          lines: [
            LyricLine(
              timestampMs: 0,
              text: 'Chorus line before guitar solo',
              sequence: 0,
              words: [
                LyricWord(
                  startMs: 0,
                  endMs: 3000,
                  text: 'Chorus line before guitar solo',
                  index: 0,
                ),
              ],
            ),
            LyricLine(
              timestampMs: 20000,
              text: 'Verse begins after solo',
              sequence: 1,
              words: [],
            ),
          ],
        );

        final stateController = StreamController<PlayerStateSnapshot>();
        addTearDown(stateController.close);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              settingsRepositoryProvider.overrideWithValue(settingsRepo),
              lastFmAccountProvider.overrideWith((ref) => Stream.value(null)),
              playerStateProvider.overrideWith((ref) => stateController.stream),
              trackLyricsProvider('track_1')
                  .overrideWith((ref) => Stream.value(soloTrackLyrics)),
              isTrackFavoriteProvider('track_1')
                  .overrideWith((ref) => Stream.value(false)),
            ],
            child: const CupertinoApp(home: NowPlayingPage()),
          ),
        );

        // 10000ms: deep in the 17-second solo
        stateController.add(
          const PlayerStateSnapshot(
            currentTrack: track1,
            duration: Duration(milliseconds: 243000),
            position: Duration(milliseconds: 10000),
            isPlaying: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics && w.properties.label == 'Instrumental section',
          ),
          findsOneWidget,
        );
        expect(find.text('Verse begins after solo'), findsOneWidget);

        // 18500ms (1.5s before verse: countdown 2)
        stateController.add(
          const PlayerStateSnapshot(
            currentTrack: track1,
            duration: Duration(milliseconds: 243000),
            position: Duration(milliseconds: 18500),
            isPlaying: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == 'Vocals start in 2',
          ),
          findsOneWidget,
        );

        // 20500ms: Verse starts
        stateController.add(
          const PlayerStateSnapshot(
            currentTrack: track1,
            duration: Duration(milliseconds: 243000),
            position: Duration(milliseconds: 20500),
            isPlaying: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          findCurrentLyricSemantics('Verse begins after solo'),
          findsOneWidget,
        );
      },
    );
  });
}
