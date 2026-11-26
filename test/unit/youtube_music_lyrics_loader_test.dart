import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musii/core/database/app_database.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/lyrics/data/repositories/lyrics_repository_impl.dart';
import 'package:musii/features/lyrics/data/youtube_music_lyrics_loader.dart';
import 'package:musii/features/lyrics/domain/entities/lyric_model.dart';
import 'package:musii/features/youtube_music/data/youtube_music_client.dart';

const _track = Track(
  id: 'youtube_dQw4w9WgXcQ',
  sourceId: 'source_youtube_music',
  youtubeVideoId: 'dQw4w9WgXcQ',
  title: 'Example Song',
  normalizedTitle: 'example song',
  artistName: 'Example Artist - Topic',
  durationMs: 190000,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('musii/youtube_music_lyrics_test');
  const youtube = YouTubeMusicClient(channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late AppDatabase db;
  late LyricsRepositoryImpl repository;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = LyricsRepositoryImpl(database: db);
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await db.close();
  });

  test('stores synced LRCLIB lyrics and reuses the local copy', () async {
    var requests = 0;
    final loader = YouTubeMusicLyricsLoader(
      lyrics: repository,
      youtube: youtube,
      httpClient: MockClient((request) async {
        requests++;
        expect(request.url.host, 'lrclib.net');
        expect(request.url.queryParameters['artist_name'], 'Example Artist');
        expect(request.url.queryParameters['duration'], '200');
        return http.Response(
          jsonEncode({
            'syncedLyrics': '[00:02.00]An example timed line',
            'plainLyrics': 'An example plain line',
          }),
          200,
        );
      }),
    );

    await Future.wait([
      loader.load(_track, playbackDuration: const Duration(seconds: 200)),
      loader.load(_track, playbackDuration: const Duration(seconds: 200)),
    ]);
    final loaded = await repository.getLyricsForTrack(_track.id);
    expect(loaded?.isSynchronized, isTrue);
    expect(loaded?.source, LyricSource.lrclib);
    expect(loaded?.lines.single.timestampMs, 2000);
    await loader.load(_track);
    expect(requests, 1);
  });

  test('stores plain YouTube Music lyrics when LRCLIB has no match', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getLyrics');
      expect(call.arguments, {'videoId': _track.youtubeVideoId});
      return {'lyrics': 'Example first line\nExample second line'};
    });
    final loader = YouTubeMusicLyricsLoader(
      lyrics: repository,
      youtube: youtube,
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    );

    await loader.load(_track);
    final loaded = await repository.getLyricsForTrack(_track.id);
    expect(loaded?.isSynchronized, isFalse);
    expect(loaded?.source, LyricSource.youtubeMusic);
    expect(loaded?.lines.length, 2);
  });
}
