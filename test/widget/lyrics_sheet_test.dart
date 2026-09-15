import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/app/bootstrap/providers.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/lyrics/domain/entities/lyric_model.dart';
import 'package:musii/features/lyrics/presentation/pages/lyrics_sheet.dart';
import 'package:musii/features/playback/domain/entities/playback_state.dart';

void main() {
  const testTrack = Track(
    id: 'track_1',
    driveFileId: 'drive_1',
    sourceId: 'source_1',
    title: 'Stay With Me',
    normalizedTitle: 'stay with me',
    artistName: 'Miki Matsubara',
  );

  testWidgets(
    'LyricsSheet displays synchronized lyrics and highlights active line',
    (tester) async {
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
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackLyricsProvider('track_1')
                .overrideWith((ref) => Stream.value(testLyrics)),
            playerStateProvider.overrideWith(
              (ref) => Stream.value(
                const PlayerStateSnapshot(
                  position: Duration(
                    milliseconds: 6000,
                  ), // Should highlight line 1 ("Stay with me...")
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
    },
  );

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
}
