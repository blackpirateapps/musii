import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musii/core/database/app_database.dart';
import 'package:musii/core/result/result.dart';
import 'package:musii/core/services/connectivity_service.dart';
import 'package:musii/features/cache/domain/entities/cache_entry.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/playback/data/repositories/playback_repository_impl.dart';
import 'package:musii/features/recently_played/data/repositories/recently_played_repository_impl.dart';
import 'package:musii/features/youtube_music/data/youtube_music_client.dart';
import 'package:musii/features/youtube_music/data/youtube_music_repository.dart';
import 'package:musii/features/youtube_music/domain/youtube_music_link.dart';

class _Player extends Mock implements AudioPlayer {}

class _DriveCache extends Mock implements CacheRepository {}

class _Recents extends Mock implements RecentlyPlayedRepository {}

class _Connectivity extends Mock implements ConnectivityService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const videoId = 'dQw4w9WgXcQ';
  const link = 'https://music.youtube.com/watch?v=$videoId';
  const channel = MethodChannel('musii/youtube_music_test');

  test('song links must use an allowed host and a valid video ID', () {
    expect(youtubeVideoIdFromLink('$link&list=playlist'), videoId);
    expect(youtubeVideoIdFromLink('https://youtu.be/$videoId'), videoId);
    expect(
      youtubeVideoIdFromLink('https://www.youtube.com/watch?v=$videoId'),
      videoId,
    );
    expect(
      youtubeVideoIdFromLink('https://music.youtube.com/playlist?list=abc'),
      isNull,
    );
    expect(
      youtubeVideoIdFromLink(
        'https://music.youtube.com.example/watch?v=$videoId',
      ),
      isNull,
    );
    expect(youtubeVideoIdFromLink('https://youtu.be/invalid'), isNull);
  });

  test(
    'mixed queue restores and ignores a stream resolved after skipping',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      const client = YouTubeMusicClient(channel);
      final repository = YouTubeMusicRepository(database, client);
      final lateStream = Completer<Map<String, String>>();
      final resolving = Completer<void>();
      var resolves = 0;
      const freshUrl = 'https://example.com/fresh';
      const retryUrl = 'https://example.com/refreshed';
      const lateUrl = 'https://example.com/stale';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.arguments, {'videoId': videoId});
        if (call.method == 'getTrack') {
          return {
            'title': 'YouTube Song',
            'artist': 'Artist',
            'durationMs': 23000,
          };
        }
        expect(call.method, 'resolveAudio');
        resolves++;
        if (resolves == 1) {
          resolving.complete();
          return lateStream.future;
        }
        return {'url': resolves == 2 ? freshUrl : retryUrl};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final imported = (await repository.importLink(link)).dataOrNull!;
      final again = (await repository.importLink('https://youtu.be/$videoId'))
          .dataOrNull!;
      expect(again.id, imported.id);
      expect(await database.select(database.tracks).get(), hasLength(1));
      for (final id in ['a', 'b']) {
        await database.customStatement(
          '''
        INSERT INTO tracks
          (id, drive_file_id, source_id, title, normalized_title, created_at, updated_at)
        VALUES (?, ?, 'source_gdrive', ?, ?, 1, 1)
      ''',
          [id, id, id, id],
        );
      }
      const first = Track(
        id: 'a',
        driveFileId: 'a',
        sourceId: 'source_gdrive',
        title: 'a',
        normalizedTitle: 'a',
      );
      const last = Track(
        id: 'b',
        driveFileId: 'b',
        sourceId: 'source_gdrive',
        title: 'b',
        normalizedTitle: 'b',
      );

      final player = _Player();
      final errors = StreamController<PlayerException>.broadcast(sync: true);
      final positions = StreamController<Duration>.broadcast(sync: true);
      addTearDown(errors.close);
      addTearDown(positions.close);
      when(() => player.errorStream).thenAnswer((_) => errors.stream);
      when(() => player.playbackEventStream)
          .thenAnswer((_) => const Stream.empty());
      when(() => player.playerStateStream)
          .thenAnswer((_) => const Stream.empty());
      when(() => player.positionStream).thenAnswer((_) => positions.stream);
      when(() => player.durationStream).thenAnswer((_) => const Stream.empty());
      when(() => player.pause()).thenAnswer((_) async {});
      when(() => player.play()).thenAnswer((_) async {});
      when(() => player.position).thenReturn(Duration.zero);
      when(() => player.duration).thenReturn(const Duration(seconds: 23));
      when(() => player.playing).thenReturn(true);
      when(() => player.speed).thenReturn(1);
      when(() => player.bufferedPosition).thenReturn(Duration.zero);
      when(() => player.processingState).thenReturn(ProcessingState.ready);
      when(
        () => player.setFilePath(
          any(),
          initialPosition: any(named: 'initialPosition'),
        ),
      ).thenAnswer((_) async => const Duration(seconds: 23));
      when(
        () => player.setUrl(
          any(),
          initialPosition: any(named: 'initialPosition'),
        ),
      ).thenAnswer((_) async => const Duration(seconds: 23));

      final cache = _DriveCache();
      final connectivity = _Connectivity();
      registerFallbackValue(first);
      when(() => cache.getOrDownloadTrack(any())).thenAnswer((call) async {
        final track = call.positionalArguments.single as Track;
        expect(track.driveFileId, isNotNull);
        return Result.success(File('/${track.id}.mp3'));
      });
      when(() => connectivity.isWifiConnected()).thenAnswer((_) async => false);
      MusiiAudioHandler handler() => MusiiAudioHandler(
        cacheRepository: cache,
        recentlyPlayedRepository: _Recents(),
        database: database,
        connectivityService: connectivity,
        youtubeMusic: client,
        player: player,
      );
      final playback = handler();
      await playback.loadAndPlayTrack(
        first,
        queue: [first, imported, last, imported],
      );
      final skippedLoad = playback.skipToNext();
      await resolving.future;
      await playback.skipToNext();
      lateStream.complete({'url': lateUrl});
      await skippedLoad;
      verifyNever(
        () => player.setUrl(
          lateUrl,
          initialPosition: any(named: 'initialPosition'),
        ),
      );
      expect(playback.currentSnapshot.currentTrack?.id, last.id);

      await playback.skipToNext();
      expect(playback.currentSnapshot.queueIndex, 3);
      expect(playback.currentSnapshot.currentTrack?.youtubeVideoId, videoId);
      verify(() => player.setUrl(freshUrl, initialPosition: Duration.zero))
          .called(1);

      const resumePosition = Duration(seconds: 9);
      positions.add(resumePosition);
      final recovered = playback.snapshotStream.firstWhere(
        (snapshot) =>
            !snapshot.isLoadingTrack && snapshot.position == resumePosition,
      );
      errors.add(PlayerException(0, 'Source error', 0));
      await recovered;
      verify(() => player.setUrl(retryUrl, initialPosition: resumePosition))
          .called(1);

      final restored = handler();
      await restored.restoreSavedState();
      expect(restored.currentSnapshot.queue.map((track) => track.id), [
        first.id,
        imported.id,
        last.id,
        imported.id,
      ]);
      expect(restored.currentSnapshot.queueIndex, 3);
      expect(restored.currentSnapshot.currentTrack?.youtubeVideoId, videoId);
      expect(restored.currentSnapshot.isPlaying, isFalse);
    },
  );
}
