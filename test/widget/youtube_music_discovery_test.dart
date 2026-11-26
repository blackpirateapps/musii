import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musii/app/bootstrap/providers.dart';
import 'package:musii/features/authentication/domain/entities/auth_user.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/library/presentation/pages/home_page.dart';
import 'package:musii/features/playback/domain/entities/playback_repository.dart';
import 'package:musii/features/playback/domain/entities/playback_state.dart';
import 'package:musii/features/search/presentation/pages/search_page.dart';
import 'package:musii/features/youtube_music/data/youtube_music_repository.dart';
import 'package:musii/features/youtube_music/domain/youtube_music_collection.dart';

class _Catalog extends Mock implements YouTubeMusicRepository {}

class _Playback extends Mock implements PlaybackRepository {}

const _first = Track(
  id: 'youtube_dQw4w9WgXcQ',
  youtubeVideoId: 'dQw4w9WgXcQ',
  sourceId: 'source_youtube_music',
  title: 'First song',
  normalizedTitle: 'first song',
);
const _second = Track(
  id: 'youtube_kJQP7kiw5Fk',
  youtubeVideoId: 'kJQP7kiw5Fk',
  sourceId: 'source_youtube_music',
  title: 'Second song',
  normalizedTitle: 'second song',
);

const YouTubeMusicCollection _playlist = (
  browseId: 'VLPLU_O2trV7TDCISxt7rHHlTKcAHyZ-DESd',
  category: YouTubeMusicCategory.playlists,
  title: 'Featured playlist',
  subtitle: 'YouTube Music',
  artworkUrl: null,
);

void main() {
  late _Catalog catalog;
  late _Playback playback;

  setUpAll(() => registerFallbackValue(_first));

  setUp(() {
    catalog = _Catalog();
    playback = _Playback();
    when(() => catalog.browseHome()).thenAnswer(
      (_) async => [
        (
          title: 'Quick picks',
          tracks: [_first, _second],
          collections: const <YouTubeMusicCollection>[],
        ),
      ],
    );
    when(() => catalog.saveTracks(any())).thenAnswer((_) async {});
    when(
      () => playback.playTrack(
        any(),
        queue: any(named: 'queue'),
        queueIndex: any(named: 'queueIndex'),
      ),
    ).thenAnswer((_) async {});
  });

  Widget home({AuthUser? user}) => ProviderScope(
    overrides: [
      youtubeMusicRepositoryProvider.overrideWithValue(catalog),
      playbackRepositoryProvider.overrideWithValue(playback),
      playerStateProvider.overrideWith(
        (ref) => Stream.value(const PlayerStateSnapshot()),
      ),
      currentUserProvider.overrideWith((ref) => Stream.value(user)),
      recentlyPlayedTracksProvider.overrideWith((ref) => Stream.value([])),
      favoriteTracksProvider.overrideWith((ref) => Stream.value([])),
      allTracksProvider('recent').overrideWith((ref) => Stream.value([])),
      allAlbumsProvider.overrideWith((ref) => Stream.value([])),
      allArtistsProvider.overrideWith((ref) => Stream.value([])),
      playlistsProvider.overrideWith((ref) => Stream.value([])),
    ],
    child: const CupertinoApp(home: HomePage()),
  );

  testWidgets(
    'signed-out Home shows YouTube Music and plays a recommendation',
    (tester) async {
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();

      expect(find.text('Google Drive'), findsNothing);
      expect(find.text('YouTube Music'), findsOneWidget);
      expect(find.text('Quick picks'), findsOneWidget);
      await tester.tap(find.text('Second song'));
      await tester.pumpAndSettle();
      verifyInOrder([
        () => catalog.saveTracks([_first, _second]),
        () => playback.playTrack(
          _second,
          queue: [_first, _second],
          queueIndex: 1,
        ),
      ]);
    },
  );

  testWidgets('connected Home can switch between Drive and YouTube Music', (
    tester,
  ) async {
    await tester.pumpWidget(
      home(
        user: const AuthUser(id: 'drive-id', email: 'owner@example.com'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.text('No Music Indexed Yet'), findsOneWidget);

    await tester.tap(find.text('YouTube Music'));
    await tester.pumpAndSettle();
    expect(find.text('Quick picks'), findsOneWidget);

    await tester.tap(find.text('Google Drive'));
    await tester.pumpAndSettle();
    expect(find.text('Quick picks'), findsNothing);
    expect(find.text('No Music Indexed Yet'), findsOneWidget);
  });

  testWidgets('Home playlist loads more songs and plays the visible queue', (
    tester,
  ) async {
    when(() => catalog.browseHome()).thenAnswer(
      (_) async => [
        (title: 'Featured', tracks: <Track>[], collections: [_playlist]),
      ],
    );
    when(() => catalog.browseCollection(_playlist.browseId)).thenAnswer(
      (_) async => (
        sections: [
          (
            title: '',
            tracks: [_first],
            collections: <YouTubeMusicCollection>[],
          ),
        ],
        nextPage: 'more',
      ),
    );
    when(() => catalog.browseCollection(_playlist.browseId, nextPage: 'more'))
        .thenAnswer(
          (_) async => (
            sections: [
              (
                title: '',
                tracks: [_second],
                collections: <YouTubeMusicCollection>[],
              ),
            ],
            nextPage: null,
          ),
        );
    await tester.pumpWidget(home());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playlists'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_playlist.title));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Load More'));
    await tester.tap(find.text('Load More'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Second song'));
    await tester.tap(find.text('Second song'));
    await tester.pumpAndSettle();
    verify(
      () =>
          playback.playTrack(_second, queue: [_first, _second], queueIndex: 1),
    ).called(1);
  });

  testWidgets(
    'search discards stale queries and queues paginated results once',
    (tester) async {
      final oldSearch = Completer<YouTubeMusicSearchPage>();
      when(() => catalog.searchSongs('old'))
          .thenAnswer((_) => oldSearch.future);
      when(() => catalog.searchSongs('new'))
          .thenAnswer((_) async => (tracks: [_first], nextPage: 'page-2'));
      when(() => catalog.searchSongs('new', nextPage: 'page-2'))
          .thenAnswer((_) async => (tracks: [_first, _second], nextPage: null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            youtubeMusicRepositoryProvider.overrideWithValue(catalog),
            playbackRepositoryProvider.overrideWithValue(playback),
            playerStateProvider.overrideWith(
              (ref) => Stream.value(const PlayerStateSnapshot()),
            ),
          ],
          child: const CupertinoApp(home: SearchPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('YouTube Music'));
      await tester.pumpAndSettle();
      final search = find.byType(CupertinoSearchTextField);
      await tester.enterText(search, 'old');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(search, 'new');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      oldSearch.complete((tracks: [_second], nextPage: null));
      await tester.pumpAndSettle();
      expect(find.text('Second song'), findsNothing);

      await tester.tap(find.text('Load More Songs'));
      await tester.pumpAndSettle();
      expect(find.text('First song'), findsOneWidget);
      expect(find.text('Second song'), findsOneWidget);
      await tester.tap(find.text('Second song'));
      await tester.pumpAndSettle();
      verify(
        () => playback.playTrack(
          _second,
          queue: [_first, _second],
          queueIndex: 1,
        ),
      ).called(1);
    },
  );
}
