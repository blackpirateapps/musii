import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musii/app/bootstrap/providers.dart';
import 'package:musii/features/favorites/data/repositories/favorite_repository_impl.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/playback/domain/entities/playback_repository.dart';
import 'package:musii/features/playback/domain/entities/playback_state.dart';
import 'package:musii/features/playback/presentation/pages/queue_page.dart';
import 'package:musii/features/playlists/domain/entities/playlist.dart';

class MockPlaybackRepository extends Mock implements PlaybackRepository {}
class MockFavoriteRepository extends Mock implements FavoriteRepository {}

void main() {
  const trackA = Track(
    id: 'track_a',
    driveFileId: 'df_a',
    sourceId: 's1',
    title: 'Song A',
    normalizedTitle: 'song a',
    artistName: 'Artist A',
    albumName: 'Album A',
    durationMs: 180000,
  );

  const trackB = Track(
    id: 'track_b',
    driveFileId: 'df_b',
    sourceId: 's1',
    title: 'Song B',
    normalizedTitle: 'song b',
    artistName: 'Artist B',
    albumName: 'Album B',
    durationMs: 200000,
  );

  const trackC = Track(
    id: 'track_c',
    driveFileId: 'df_c',
    sourceId: 's1',
    title: 'Song C',
    normalizedTitle: 'song c',
    artistName: 'Artist C',
    albumName: 'Album C',
    durationMs: 210000,
  );

  const itemA = QueueItem(id: 'qa', track: trackA);
  const itemB = QueueItem(id: 'qb', track: trackB);
  const itemC = QueueItem(id: 'qc', track: trackC);

  late MockPlaybackRepository mockPlayback;
  late MockFavoriteRepository mockFavorite;

  setUp(() {
    registerFallbackValue(trackA);
    mockPlayback = MockPlaybackRepository();
    mockFavorite = MockFavoriteRepository();
    when(() => mockFavorite.watchIsFavorite(any())).thenAnswer((_) => Stream.value(false));
  });

  Widget buildTestWidget({required PlayerStateSnapshot snapshot}) {
    return ProviderScope(
      overrides: [
        playerStateProvider.overrideWith((ref) => Stream.value(snapshot)),
        playbackRepositoryProvider.overrideWithValue(mockPlayback),
        favoriteRepositoryProvider.overrideWithValue(mockFavorite),
        playlistsProvider.overrideWith((ref) => Stream.value(<Playlist>[])),
      ],
      child: const CupertinoApp(
        localizationsDelegates: [
          DefaultMaterialLocalizations.delegate,
          DefaultCupertinoLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        home: CupertinoPageScaffold(
          child: QueuePage(),
        ),
      ),
    );
  }

  testWidgets('QueuePage renders NOW PLAYING and UP NEXT sections with track counts', (tester) async {
    const snapshot = PlayerStateSnapshot(
      currentTrack: trackA,
      queueItems: [itemA, itemB, itemC],
      queueIndex: 0,
      isPlaying: true,
    );

    await tester.pumpWidget(buildTestWidget(snapshot: snapshot));
    await tester.pumpAndSettle();

    expect(find.text('Playing Next'), findsOneWidget);
    expect(find.text('2 songs up next'), findsOneWidget);
    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(find.text('Song A'), findsOneWidget);
    expect(find.text('UP NEXT'), findsOneWidget);
    expect(find.text('Song B'), findsOneWidget);
    expect(find.text('Song C'), findsOneWidget);
  });

  testWidgets('QueuePage renders empty state when no tracks in Up Next', (tester) async {
    const snapshot = PlayerStateSnapshot(
      currentTrack: trackA,
      queueItems: [itemA],
      queueIndex: 0,
      isPlaying: true,
    );

    await tester.pumpWidget(buildTestWidget(snapshot: snapshot));
    await tester.pumpAndSettle();

    expect(find.text('0 songs up next'), findsOneWidget);
    expect(find.text('Queue is empty'), findsOneWidget);
    expect(find.text('Tracks you add will appear here.'), findsOneWidget);
  });

  testWidgets('Tapping Clear button calls clearUpNext', (tester) async {
    when(() => mockPlayback.clearUpNext()).thenAnswer((_) async {});

    const snapshot = PlayerStateSnapshot(
      currentTrack: trackA,
      queueItems: [itemA, itemB, itemC],
      queueIndex: 0,
      isPlaying: true,
    );

    await tester.pumpWidget(buildTestWidget(snapshot: snapshot));
    await tester.pumpAndSettle();

    final clearBtn = find.text('Clear');
    expect(clearBtn, findsOneWidget);

    await tester.tap(clearBtn);
    await tester.pumpAndSettle();

    verify(() => mockPlayback.clearUpNext()).called(1);
  });

  testWidgets('Tapping overflow options presents Clear Up Next and Shuffle', (tester) async {
    when(() => mockPlayback.clearUpNext()).thenAnswer((_) async {});

    const snapshot = PlayerStateSnapshot(
      currentTrack: trackA,
      queueItems: [itemA, itemB],
      queueIndex: 0,
      isPlaying: true,
    );

    await tester.pumpWidget(buildTestWidget(snapshot: snapshot));
    await tester.pumpAndSettle();

    final overflowBtn = find.byIcon(CupertinoIcons.ellipsis_circle);
    expect(overflowBtn, findsOneWidget);

    await tester.tap(overflowBtn);
    await tester.pumpAndSettle();

    expect(find.text('Queue Options'), findsOneWidget);
    expect(find.text('Clear Up Next'), findsOneWidget);
    expect(find.text('Shuffle Queue'), findsOneWidget);

    await tester.tap(find.text('Clear Up Next'));
    await tester.pumpAndSettle();

    verify(() => mockPlayback.clearUpNext()).called(1);
  });

  testWidgets('Long pressing an up-next track opens queue track action sheet with Remove from Queue', (tester) async {
    const snapshot = PlayerStateSnapshot(
      currentTrack: trackA,
      queueItems: [itemA, itemB],
      queueIndex: 0,
      isPlaying: true,
    );

    await tester.pumpWidget(buildTestWidget(snapshot: snapshot));
    await tester.pumpAndSettle();

    final songBTile = find.text('Song B');
    expect(songBTile, findsOneWidget);

    await tester.longPress(songBTile);
    await tester.pumpAndSettle();

    expect(find.text('Play Now'), findsOneWidget);
    expect(find.text('Play Next'), findsOneWidget);
    expect(find.text('Remove from Queue'), findsOneWidget);
    expect(find.text('Add to Playlist...'), findsOneWidget);
    expect(find.text('Favorite'), findsOneWidget);
  });

  testWidgets('Long pressing now playing track opens action sheet without Remove from Queue', (tester) async {
    const snapshot = PlayerStateSnapshot(
      currentTrack: trackA,
      queueItems: [itemA, itemB],
      queueIndex: 0,
      isPlaying: true,
    );

    await tester.pumpWidget(buildTestWidget(snapshot: snapshot));
    await tester.pumpAndSettle();

    final nowPlayingTile = find.text('Song A');
    expect(nowPlayingTile, findsOneWidget);

    await tester.longPress(nowPlayingTile);
    await tester.pumpAndSettle();

    expect(find.text('Play Next'), findsOneWidget);
    expect(find.text('Add to Queue'), findsOneWidget);
    expect(find.text('Remove from Queue'), findsNothing);
    expect(find.text('Favorite'), findsOneWidget);
  });

  testWidgets('Swiping an up-next track left removes it from the queue', (tester) async {
    when(() => mockPlayback.removeQueueItem('qb')).thenAnswer((_) async {});

    const snapshot = PlayerStateSnapshot(
      currentTrack: trackA,
      queueItems: [itemA, itemB],
      queueIndex: 0,
      isPlaying: true,
    );

    await tester.pumpWidget(buildTestWidget(snapshot: snapshot));
    await tester.pumpAndSettle();

    // Find the dismissible for Song B and drag left
    final dismissible = find.byKey(const ValueKey('dismiss_qb'));
    expect(dismissible, findsOneWidget);

    await tester.drag(dismissible, const Offset(-500, 0));
    await tester.pumpAndSettle();

    verify(() => mockPlayback.removeQueueItem('qb')).called(1);
  });
}
