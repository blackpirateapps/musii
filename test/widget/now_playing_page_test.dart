import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/app/bootstrap/providers.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/playback/domain/entities/playback_state.dart';
import 'package:musii/features/playback/presentation/pages/now_playing_page.dart';

void main() {
  const testTrack = Track(
    id: 'track_test_1',
    driveFileId: 'drive_1',
    sourceId: 'source_1',
    title: 'Mayonaka no Door / Stay With Me',
    normalizedTitle: 'mayonaka no door stay with me',
    artistName: 'Miki Matsubara',
    albumName: 'Miki Matsubara Best Collection',
    format: 'FLAC',
    bitrate: 706000,
    durationMs: 243000,
    fileSize: 21500000,
  );

  testWidgets('NowPlayingPage renders complete visual authority components', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerStateProvider.overrideWith(
            (ref) => Stream.value(
              const PlayerStateSnapshot(
                currentTrack: testTrack,
                duration: Duration(milliseconds: 243000),
                position: Duration(milliseconds: 103000),
                isPlaying: true,
              ),
            ),
          ),
          isTrackFavoriteProvider('track_test_1').overrideWith(
            (ref) => Stream.value(false),
          ),
        ],
        child: const CupertinoApp(
          home: NowPlayingPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Top Navigation Bar
    expect(find.text('Now Playing'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.chevron_down), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.music_note_list), findsOneWidget);

    // Track Metadata
    expect(find.text('Mayonaka no Door / Stay With Me'), findsOneWidget);
    expect(find.text('Miki Matsubara'), findsOneWidget);
    expect(find.text('Miki Matsubara Best Collection'), findsOneWidget);

    // Technical Badge (FLAC · 706 kbps)
    expect(find.text('FLAC · 706 kbps'), findsOneWidget);

    // Visible More Button (...)
    expect(find.byIcon(CupertinoIcons.ellipsis), findsOneWidget);

    // Scrubber & Times (1:43 and -2:20)
    expect(find.byType(CupertinoSlider), findsOneWidget);
    expect(find.text('1:43'), findsOneWidget);
    expect(find.text('-2:20'), findsOneWidget);

    // Primary Controls
    expect(find.byIcon(CupertinoIcons.shuffle), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.backward_fill), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.pause_fill), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.forward_fill), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.repeat), findsOneWidget);

    // Bottom Secondary Controls (Favorite, Lyrics, Queue)
    expect(find.byIcon(CupertinoIcons.heart), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.quote_bubble), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.list_bullet), findsOneWidget);
  });

  testWidgets('Tapping More button opens action sheet with all actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerStateProvider.overrideWith(
            (ref) => Stream.value(
              const PlayerStateSnapshot(
                currentTrack: testTrack,
                duration: Duration(milliseconds: 243000),
                position: Duration(milliseconds: 103000),
                isPlaying: true,
              ),
            ),
          ),
          isTrackFavoriteProvider('track_test_1').overrideWith(
            (ref) => Stream.value(false),
          ),
        ],
        child: const CupertinoApp(
          home: NowPlayingPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap More button
    await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
    await tester.pumpAndSettle();

    // Verify Action Sheet items
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(find.text('Play Next'), findsOneWidget);
    expect(find.text('Add to Queue'), findsOneWidget);
    expect(find.text('Add to Playlist...'), findsOneWidget);
    expect(find.text('Favorite'), findsOneWidget);
    expect(find.text('Download for Offline'), findsOneWidget);
    expect(find.text('Lyrics'), findsOneWidget);
    expect(find.text('Audio Information'), findsOneWidget);
  });
}
