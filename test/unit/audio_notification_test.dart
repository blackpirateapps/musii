import 'package:audio_service/audio_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/core/database/app_database.dart';
import 'package:musii/core/services/notification_permission_service.dart';
import 'package:musii/features/cache/domain/entities/cache_entry.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/playback/data/repositories/playback_repository_impl.dart';
import 'package:musii/features/playback/domain/entities/playback_state.dart';
import 'package:musii/features/recently_played/data/repositories/recently_played_repository_impl.dart';
import 'package:mocktail/mocktail.dart';

import 'package:musii/core/services/connectivity_service.dart';
import 'package:musii/core/error/failures.dart';
import 'package:musii/core/result/result.dart';

class MockCacheRepository extends Mock implements CacheRepository {}

class MockRecentlyPlayedRepository extends Mock
    implements RecentlyPlayedRepository {}

class MockConnectivityService extends Mock implements ConnectivityService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(
      const Track(
        id: 'dummy',
        driveFileId: '',
        sourceId: '',
        title: '',
        normalizedTitle: '',
      ),
    );
  });

  group('NotificationPermissionService', () {
    test('isNotificationPermissionGranted returns bool without error', () async {
      final result =
          await NotificationPermissionService.isNotificationPermissionGranted();
      expect(result, isA<bool>());
    });

    test('requestNotificationPermissionIfNeeded completes safely', () async {
      final result =
          await NotificationPermissionService.requestNotificationPermissionIfNeeded();
      expect(result, isA<bool>());
    });
  });

  group('MusiiAudioHandler MediaSession & Queue Integration', () {
    late AppDatabase db;
    late MockCacheRepository mockCache;
    late MockRecentlyPlayedRepository mockRecents;
    late MockConnectivityService mockConnectivity;
    late MusiiAudioHandler handler;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      mockCache = MockCacheRepository();
      mockRecents = MockRecentlyPlayedRepository();
      mockConnectivity = MockConnectivityService();
      when(() => mockCache.setCurrentlyPlayingTrackId(any())).thenReturn(null);
      when(() => mockCache.getOrDownloadTrack(any())).thenAnswer(
        (_) async => const Result.failure(CacheFailure('mock test failure')),
      );
      when(() => mockCache.isTrackCached(any())).thenAnswer((_) async => false);
      when(() => mockConnectivity.isWifiConnected())
          .thenAnswer((_) async => true);
      handler = MusiiAudioHandler(
        cacheRepository: mockCache,
        recentlyPlayedRepository: mockRecents,
        database: db,
        connectivityService: mockConnectivity,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'playNext, playLast, and queue mutations update queue stream',
      () async {
        const track1 = Track(
          id: 't1',
          driveFileId: 'df1',
          sourceId: 's1',
          title: 'Track One',
          normalizedTitle: 'track one',
          artistName: 'Artist A',
          albumName: 'Album A',
          durationMs: 180000,
        );
        const track2 = Track(
          id: 't2',
          driveFileId: 'df2',
          sourceId: 's1',
          title: 'Track Two',
          normalizedTitle: 'track two',
          artistName: 'Artist B',
          albumName: 'Album B',
          durationMs: 200000,
        );

        handler.playNext(track1);
        expect(handler.queue.value.length, equals(1));
        expect(handler.queue.value.first.id, equals('t1'));
        expect(handler.queue.value.first.title, equals('Track One'));

        handler.playLast(track2);
        expect(handler.queue.value.length, equals(2));
        expect(handler.queue.value[1].id, equals('t2'));
        expect(handler.queue.value[1].title, equals('Track Two'));

        handler.reorderQueue(0, 2);
        expect(handler.queue.value[0].id, equals('t2'));
        expect(handler.queue.value[1].id, equals('t1'));

        handler.removeFromQueue(0);
        expect(handler.queue.value.length, equals(1));
        expect(handler.queue.value.first.id, equals('t1'));

        handler.clearQueue();
        expect(handler.queue.value, isEmpty);
      },
    );

    test('setRepeatMode updates repeat mode state snapshot', () async {
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      expect(handler.currentSnapshot.repeatMode, equals(AudioRepeatMode.one));

      await handler.setRepeatMode(AudioServiceRepeatMode.all);
      expect(handler.currentSnapshot.repeatMode, equals(AudioRepeatMode.all));

      await handler.setRepeatMode(AudioServiceRepeatMode.none);
      expect(handler.currentSnapshot.repeatMode, equals(AudioRepeatMode.off));
    });

    test('setShuffleMode toggles shuffle mode', () async {
      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      expect(handler.currentSnapshot.shuffleMode, isTrue);

      await handler.setShuffleMode(AudioServiceShuffleMode.none);
      expect(handler.currentSnapshot.shuffleMode, isFalse);
    });

    test(
      'loadAndPlayTrack sets current track and initiates audio retrieval',
      () async {
        const testTrack = Track(
          id: 'track_1',
          driveFileId: 'df1',
          sourceId: 's1',
          title: 'Song Title',
          normalizedTitle: 'song title',
          durationMs: 210000,
        );

        await handler.loadAndPlayTrack(testTrack);

        expect(handler.currentSnapshot.currentTrack?.id, equals('track_1'));
        expect(
          handler.currentSnapshot.currentTrack?.title,
          equals('Song Title'),
        );
        verify(() => mockCache.setCurrentlyPlayingTrackId('track_1')).called(1);
        verify(() => mockCache.getOrDownloadTrack(any())).called(1);
      },
    );

    test('play() initiates loadAndPlayTrack for current track if not yet loaded in player', () async {
      const testTrack = Track(
        id: 'track_unloaded',
        driveFileId: 'df_unloaded',
        sourceId: 's1',
        title: 'Unloaded Song',
        normalizedTitle: 'unloaded song',
        durationMs: 150000,
      );

      // Populate queue without loading audio
      handler.playNext(testTrack);
      expect(
        handler.currentSnapshot.currentTrack?.id,
        equals('track_unloaded'),
      );

      // Calling play() must load and play the displayed track
      await handler.play();

      expect(
        handler.currentSnapshot.currentTrack?.id,
        equals('track_unloaded'),
      );
      verify(() => mockCache.setCurrentlyPlayingTrackId('track_unloaded'))
          .called(1);
      verify(() => mockCache.getOrDownloadTrack(any())).called(1);
    });

    test(
      'play() does nothing safely when no track is in queue or snapshot',
      () async {
        handler.clearQueue();
        await handler.play();
        expect(handler.currentSnapshot.currentTrack, isNull);
      },
    );

    test(
      'PlaybackRepositoryImpl.playAlbum propagates album artwork to tracks lacking artwork',
      () async {
        final repo = PlaybackRepositoryImpl(audioHandler: handler);
        const album = Album(
          id: 'alb_1',
          title: 'Album With Art',
          normalizedTitle: 'album with art',
          artworkPath: '/path/to/folder_art.jpg',
        );
        const trackWithoutArt = Track(
          id: 't_no_art',
          driveFileId: 'df1',
          sourceId: 's1',
          title: 'Track Without Art',
          normalizedTitle: 'track without art',
          durationMs: 120000,
          artworkPath: null,
        );
        const trackWithArt = Track(
          id: 't_has_art',
          driveFileId: 'df2',
          sourceId: 's1',
          title: 'Track With Art',
          normalizedTitle: 'track with art',
          durationMs: 140000,
          artworkPath: '/path/to/embedded.jpg',
        );

        await repo.playAlbum(album, [trackWithoutArt, trackWithArt]);

        final queue = handler.currentSnapshot.queueItems;
        expect(queue.length, equals(2));
        expect(queue[0].track.artworkPath, equals('/path/to/folder_art.jpg'));
        expect(queue[1].track.artworkPath, equals('/path/to/embedded.jpg'));
        expect(
          handler.currentSnapshot.currentTrack?.artworkPath,
          equals('/path/to/folder_art.jpg'),
        );
        await pumpEventQueue();
      },
    );
  });
}
