import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/app/bootstrap/providers.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/lyrics/domain/entities/lyric_model.dart';
import 'package:musii/features/lyrics/presentation/pages/lyrics_sheet.dart';
import 'package:musii/features/playback/domain/entities/playback_repository.dart';
import 'package:musii/features/playback/domain/entities/playback_state.dart';
import 'package:musii/features/playlists/domain/entities/playlist_entities.dart';

class FakePlaybackRepository implements PlaybackRepository {
  Duration? lastSeekPosition;

  @override
  PlayerStateSnapshot get currentState => const PlayerStateSnapshot();

  @override
  Stream<PlayerStateSnapshot> watchPlayerState() => const Stream.empty();

  @override
  Future<void> seek(Duration position) async {
    lastSeekPosition = position;
  }

  @override
  Future<void> playTrack(
    Track track, {
    List<Track>? queue,
    int? queueIndex,
  }) async {}

  @override
  Future<void> playAlbum(
    Album album,
    List<Track> tracks, {
    int startIndex = 0,
  }) async {}

  @override
  Future<void> playPlaylist(
    Playlist playlist,
    List<Track> tracks, {
    int startIndex = 0,
  }) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> skipToNext() async {}

  @override
  Future<void> skipToPrevious() async {}

  @override
  Future<void> toggleShuffle() async {}

  @override
  Future<void> cycleRepeatMode() async {}

  @override
  Future<void> playNext(Track track) async {}

  @override
  Future<void> playLast(Track track) async {}

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) async {}

  @override
  Future<void> removeFromQueue(int index) async {}

  @override
  Future<void> clearQueue() async {}

  @override
  Future<void> restoreSavedState() async {}
}

void main() {
  const testTrack = Track(
    id: 'track_1',
    driveFileId: 'drive_1',
    sourceId: 'source_1',
    title: 'Stay With Me',
    normalizedTitle: 'stay with me',
    artistName: 'Miki Matsubara',
  );

  const testLyrics = TrackLyrics(
    id: 'lyric_1',
    trackId: 'track_1',
    source: LyricSource.embeddedSynced,
    isSynchronized: true,
    lines: [
      LyricLine(timestampMs: 0, text: 'First intro line', sequence: 0),
      LyricLine(timestampMs: 5000, text: 'Stay with me...', sequence: 1),
      LyricLine(
        timestampMs: 10000,
        text: 'Mayonaka no door o tataki',
        sequence: 2,
      ),
      LyricLine(timestampMs: 15000, text: 'Kaeranaide to naita', sequence: 3),
      LyricLine(
        timestampMs: 20000,
        text: 'Ano kisetsu ga ima me no mae',
        sequence: 4,
      ),
      LyricLine(
        timestampMs: 25000,
        text: 'Stay with me... chorus end',
        sequence: 5,
      ),
    ],
  );

  testWidgets(
    'LyricsSheet displays synchronized lyrics and highlights active line',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackLyricsProvider('track_1')
                .overrideWith((ref) => Stream.value(testLyrics)),
            playerStateProvider.overrideWith(
              (ref) => Stream.value(
                const PlayerStateSnapshot(
                  position: Duration(milliseconds: 6000),
                ),
              ),
            ),
          ],
          child: const CupertinoApp(home: LyricsSheet(track: testTrack)),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Lyrics'), findsOneWidget);
      expect(find.text('Stay With Me'), findsOneWidget);
      expect(find.text('First intro line'), findsOneWidget);
      expect(find.text('Stay with me...'), findsOneWidget);
      expect(find.text('Mayonaka no door o tataki'), findsOneWidget);

      final rowFinder = find.byType(LyricLineRow);
      expect(rowFinder, findsWidgets);

      // Verify line 1 is active
      final activeRow = tester.widget<LyricLineRow>(rowFinder.at(1));
      expect(activeRow.isActive, isTrue);

      final inactiveRow = tester.widget<LyricLineRow>(rowFinder.at(0));
      expect(inactiveRow.isActive, isFalse);
    },
  );

  testWidgets(
    'LyricsSheet initial positioning renders the active line when opened mid-playback',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackLyricsProvider('track_1')
                .overrideWith((ref) => Stream.value(testLyrics)),
            playerStateProvider.overrideWith(
              (ref) => Stream.value(
                const PlayerStateSnapshot(
                  position: Duration(milliseconds: 21000),
                ),
              ),
            ),
          ],
          child: const CupertinoApp(home: LyricsSheet(track: testTrack)),
        ),
      );

      await tester.pumpAndSettle();

      final rowFinder = find.byType(LyricLineRow);
      expect(rowFinder, findsWidgets);

      // Line 4 ("Ano kisetsu ga ima me no mae") should be active
      final activeRow = tester.widget<LyricLineRow>(rowFinder.at(4));
      expect(activeRow.isActive, isTrue);
      expect(activeRow.line.text, equals('Ano kisetsu ga ima me no mae'));
    },
  );

  testWidgets(
    'LyricsSheet transitions active line styling when playback position advances',
    (tester) async {
      final playerController =
          StreamController<PlayerStateSnapshot>.broadcast();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackLyricsProvider('track_1')
                .overrideWith((ref) => Stream.value(testLyrics)),
            playerStateProvider.overrideWith((ref) => playerController.stream),
          ],
          child: const CupertinoApp(home: LyricsSheet(track: testTrack)),
        ),
      );

      // Initial tick at 2 seconds (Line 0 active)
      playerController.add(
        const PlayerStateSnapshot(position: Duration(milliseconds: 2000)),
      );
      await tester.pumpAndSettle();

      var rows = find.byType(LyricLineRow);
      expect(tester.widget<LyricLineRow>(rows.at(0)).isActive, isTrue);
      expect(tester.widget<LyricLineRow>(rows.at(1)).isActive, isFalse);

      // Advance playback to 7 seconds (Line 1 active)
      playerController.add(
        const PlayerStateSnapshot(position: Duration(milliseconds: 7000)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      rows = find.byType(LyricLineRow);
      expect(tester.widget<LyricLineRow>(rows.at(0)).isActive, isFalse);
      expect(tester.widget<LyricLineRow>(rows.at(1)).isActive, isTrue);

      await playerController.close();
    },
  );

  testWidgets(
    'LyricsSheet manual scrolling reveals Return to current line button and pauses auto-scrolling',
    (tester) async {
      final playerController =
          StreamController<PlayerStateSnapshot>.broadcast();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackLyricsProvider('track_1')
                .overrideWith((ref) => Stream.value(testLyrics)),
            playerStateProvider.overrideWith((ref) => playerController.stream),
          ],
          child: const CupertinoApp(home: LyricsSheet(track: testTrack)),
        ),
      );

      playerController.add(
        const PlayerStateSnapshot(position: Duration(milliseconds: 1000)),
      );
      await tester.pumpAndSettle();

      // Initially, "Current line" floating button should not be visible
      expect(find.text('Current line'), findsNothing);

      // Perform a drag gesture on the ListView to trigger user manual scroll
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      // "Current line" floating button should now be visible
      expect(find.text('Current line'), findsOneWidget);

      // Advance playback to line 2 while user is scrolled away
      playerController.add(
        const PlayerStateSnapshot(position: Duration(milliseconds: 11000)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Active state updates internally
      final rows = find.byType(LyricLineRow);
      expect(tester.widget<LyricLineRow>(rows.at(2)).isActive, isTrue);

      // Button is still visible since user has not returned
      expect(find.text('Current line'), findsOneWidget);

      // Tap "Current line" button to resume auto-following
      await tester.tap(find.text('Current line'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Button should now be dismissed / hidden
      expect(find.text('Current line'), findsNothing);

      await playerController.close();
    },
  );

  testWidgets('LyricsSheet tapping a lyric line seeks playback to timestamp', (
    tester,
  ) async {
    final fakePlayback = FakePlaybackRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackLyricsProvider('track_1')
              .overrideWith((ref) => Stream.value(testLyrics)),
          playerStateProvider.overrideWith(
            (ref) => Stream.value(
              const PlayerStateSnapshot(position: Duration(milliseconds: 0)),
            ),
          ),
          playbackRepositoryProvider.overrideWithValue(fakePlayback),
        ],
        child: const CupertinoApp(home: LyricsSheet(track: testTrack)),
      ),
    );

    await tester.pumpAndSettle();

    // Tap line 2: 'Mayonaka no door o tataki' (timestamp: 10000ms)
    await tester.tap(find.text('Mayonaka no door o tataki'));
    await tester.pumpAndSettle();

    expect(
      fakePlayback.lastSeekPosition,
      equals(const Duration(milliseconds: 10000)),
    );
  });

  testWidgets('LyricsSheet renders plain unsynchronized lyrics correctly', (
    tester,
  ) async {
    const plainLyrics = TrackLyrics(
      id: 'lyric_plain',
      trackId: 'track_1',
      source: LyricSource.embeddedPlain,
      isSynchronized: false,
      lines: [
        LyricLine(timestampMs: 0, text: 'First unsynced line', sequence: 0),
        LyricLine(timestampMs: 0, text: 'Second unsynced line', sequence: 1),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackLyricsProvider('track_1')
              .overrideWith((ref) => Stream.value(plainLyrics)),
          playerStateProvider.overrideWith(
            (ref) => Stream.value(const PlayerStateSnapshot()),
          ),
        ],
        child: const CupertinoApp(home: LyricsSheet(track: testTrack)),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('First unsynced line'), findsOneWidget);
    expect(find.text('Second unsynced line'), findsOneWidget);
    // Plain lyrics should not render LyricLineRow widgets
    expect(find.byType(LyricLineRow), findsNothing);
  });

  testWidgets(
    'LyricsSheet shows clean empty state when no lyrics are available',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackLyricsProvider('track_1')
                .overrideWith((ref) => Stream.value(null)),
            playerStateProvider.overrideWith(
              (ref) => Stream.value(const PlayerStateSnapshot()),
            ),
          ],
          child: const CupertinoApp(home: LyricsSheet(track: testTrack)),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.text("Lyrics aren't available for this song."),
        findsOneWidget,
      );
      expect(find.byIcon(CupertinoIcons.quote_bubble), findsOneWidget);
    },
  );

  testWidgets(
    'LyricsSheet pause does not trigger unnecessary scrolling and resume continues sync',
    (tester) async {
      final playerController =
          StreamController<PlayerStateSnapshot>.broadcast();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackLyricsProvider('track_1')
                .overrideWith((ref) => Stream.value(testLyrics)),
            playerStateProvider.overrideWith((ref) => playerController.stream),
          ],
          child: const CupertinoApp(home: LyricsSheet(track: testTrack)),
        ),
      );

      // Playback active at 5.5 seconds (line 1 active)
      playerController.add(
        const PlayerStateSnapshot(
          isPlaying: true,
          position: Duration(milliseconds: 5500),
        ),
      );
      await tester.pumpAndSettle();

      var rows = find.byType(LyricLineRow);
      expect(tester.widget<LyricLineRow>(rows.at(1)).isActive, isTrue);

      // Playback paused at 5.5 seconds (line 1 remains active)
      playerController.add(
        const PlayerStateSnapshot(
          isPlaying: false,
          position: Duration(milliseconds: 5500),
        ),
      );
      await tester.pumpAndSettle();

      rows = find.byType(LyricLineRow);
      expect(tester.widget<LyricLineRow>(rows.at(1)).isActive, isTrue);

      // Playback resumed and advances to 10.5 seconds (line 2 active)
      playerController.add(
        const PlayerStateSnapshot(
          isPlaying: true,
          position: Duration(milliseconds: 10500),
        ),
      );
      await tester.pumpAndSettle();

      rows = find.byType(LyricLineRow);
      expect(tester.widget<LyricLineRow>(rows.at(1)).isActive, isFalse);
      expect(tester.widget<LyricLineRow>(rows.at(2)).isActive, isTrue);

      await playerController.close();
    },
  );
}
