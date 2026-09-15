import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/core/database/app_database.dart';
import 'package:musii/features/favorites/data/repositories/favorite_repository_impl.dart';
import 'package:musii/features/lyrics/data/repositories/lyrics_repository_impl.dart';
import 'package:musii/features/lyrics/domain/entities/lyric_model.dart';
import 'package:musii/features/playlists/data/repositories/playlist_repository_impl.dart';
import 'package:musii/features/recently_played/data/repositories/recently_played_repository_impl.dart';

void main() {
  late AppDatabase db;
  late LyricsRepositoryImpl lyricsRepo;
  late FavoriteRepositoryImpl favRepo;
  late PlaylistRepositoryImpl playlistRepo;
  late RecentlyPlayedRepositoryImpl recentsRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    lyricsRepo = LyricsRepositoryImpl(database: db);
    favRepo = FavoriteRepositoryImpl(database: db);
    playlistRepo = PlaylistRepositoryImpl(database: db);
    recentsRepo = RecentlyPlayedRepositoryImpl(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Library, Lyrics, and User Activity Flow', () {
    test('inserts tracks, saves synchronized lyrics, and retrieves them in sequence', () async {
      // 1. Insert track into Drift database
      await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              id: 'track_test_101',
              driveFileId: 'drive_file_101',
              sourceId: 'source_gdrive',
              title: 'Mayonaka no Door',
              normalizedTitle: 'mayonaka no door',
              artistName: const Value('Miki Matsubara'),
              albumName: const Value('Pocket Park'),
              durationMs: const Value(243000),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      // 2. Save synchronized lyrics with lines
      await lyricsRepo.saveLyrics(
        trackId: 'track_test_101',
        source: LyricSource.embeddedSynced,
        isSynchronized: true,
        rawText: '[00:10.00]Line 1\n[00:20.00]Line 2',
        offsetMs: 0,
        lines: const [
          LyricLine(
            timestampMs: 10000,
            text: 'To you, yes, my love to you',
            sequence: 0,
          ),
          LyricLine(
            timestampMs: 20000,
            text: 'Watashi wa watashi anata wa anata to',
            sequence: 1,
          ),
        ],
      );

      // 3. Retrieve lyrics
      final retrieved = await lyricsRepo.getLyricsForTrack('track_test_101');
      expect(retrieved, isNotNull);
      expect(retrieved!.isSynchronized, isTrue);
      expect(retrieved.source, equals(LyricSource.embeddedSynced));
      expect(retrieved.lines.length, equals(2));
      expect(retrieved.lines[0].text, equals('To you, yes, my love to you'));
      expect(retrieved.lines[1].timestampMs, equals(20000));
    });

    test(
      'saves and retrieves word-synchronized lyrics with LyricWords table',
      () async {
        await db
            .into(db.tracks)
            .insert(
              TracksCompanion.insert(
                id: 'track_words_102',
                driveFileId: 'df_words_102',
                sourceId: 'source_gdrive',
                title: 'Look In My Eyes',
                normalizedTitle: 'look in my eyes',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );

        const word0 = LyricWord(
          index: 0,
          text: 'Look',
          startMs: 18812,
          endMs: 19063,
        );
        const word1 = LyricWord(
          index: 1,
          text: 'in',
          startMs: 19063,
          endMs: 19228,
        );
        const word2 = LyricWord(
          index: 2,
          text: 'my',
          startMs: 19228,
          endMs: 19413,
        );
        const word3 = LyricWord(
          index: 3,
          text: 'eyes',
          startMs: 19413,
          endMs: 20185,
        );

        await lyricsRepo.saveLyrics(
          trackId: 'track_words_102',
          source: LyricSource.embeddedSynced,
          isSynchronized: true,
          rawText: 'v1:<00:18.812>Look <00:19.063>in <00:19.228>my <00:19.413>eyes <00:20.185>',
          offsetMs: 0,
          lines: const [
            LyricLine(
              timestampMs: 18812,
              text: 'Look in my eyes',
              sequence: 0,
              words: [word0, word1, word2, word3],
            ),
          ],
        );

        final retrieved = await lyricsRepo.getLyricsForTrack('track_words_102');
        expect(retrieved, isNotNull);
        expect(retrieved!.hasWordTiming, isTrue);
        expect(retrieved.lines.first.hasWords, isTrue);
        expect(retrieved.lines.first.words.length, equals(4));
        expect(retrieved.lines.first.words[0].text, equals('Look'));
        expect(retrieved.lines.first.words[0].startMs, equals(18812));
        expect(retrieved.lines.first.words[3].text, equals('eyes'));
        expect(retrieved.lines.first.words[3].endMs, equals(20185));
      },
    );

    test('favorites toggling flow persists and updates correctly', () async {
      const trackId = 'track_fav_1';

      // Insert track
      await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              id: trackId,
              driveFileId: 'drive_fav_1',
              sourceId: 'source_gdrive',
              title: 'Favorite Song',
              normalizedTitle: 'favorite song',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      // Initially not favorite
      final initialFav = await favRepo.watchIsFavorite(trackId).first;
      expect(initialFav, isFalse);

      // Toggle to favorite
      final res1 = await favRepo.toggleFavorite(trackId);
      expect(res1.isSuccess, isTrue);
      final isFavAfter = await favRepo.watchIsFavorite(trackId).first;
      expect(isFavAfter, isTrue);

      // Toggle off
      final res2 = await favRepo.toggleFavorite(trackId);
      expect(res2.isSuccess, isTrue);
      final isFavFinal = await favRepo.watchIsFavorite(trackId).first;
      expect(isFavFinal, isFalse);
    });

    test('playlist creation, track addition, and reordering flow', () async {
      // Create playlist
      final plResult = await playlistRepo.createPlaylist('City Pop Essentials');
      expect(plResult.isSuccess, isTrue);
      final plId = plResult.dataOrNull!;

      // Insert tracks
      await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              id: 't1',
              driveFileId: 'df1',
              sourceId: 'src',
              title: 'Track 1',
              normalizedTitle: 'track 1',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              id: 't2',
              driveFileId: 'df2',
              sourceId: 'src',
              title: 'Track 2',
              normalizedTitle: 'track 2',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      // Add tracks
      await playlistRepo.addTrackToPlaylist(plId, 't1');
      await playlistRepo.addTrackToPlaylist(plId, 't2');

      final tracks = await playlistRepo.watchPlaylistTracks(plId).first;
      expect(tracks.length, equals(2));
      expect(tracks[0].id, equals('t1'));
      expect(tracks[1].id, equals('t2'));

      // Reorder
      await playlistRepo.reorderPlaylistTracks(plId, 0, 1);
      final reordered = await playlistRepo.watchPlaylistTracks(plId).first;
      expect(reordered[0].id, equals('t2'));
      expect(reordered[1].id, equals('t1'));
    });

    test('recently played records actual playback above threshold', () async {
      const trackId = 't_recent';
      await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              id: trackId,
              driveFileId: 'df_recent',
              sourceId: 'src',
              title: 'Recent Song',
              normalizedTitle: 'recent song',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      // Record playback below threshold (e.g. 5 seconds)
      await recentsRepo.recordPlayback(trackId, 5000, false);
      final listBefore = await recentsRepo.watchRecentlyPlayed().first;
      expect(listBefore, isEmpty);

      // Record playback above threshold (e.g. 35 seconds)
      await recentsRepo.recordPlayback(trackId, 35000, false);
      final listAfter = await recentsRepo.watchRecentlyPlayed().first;
      expect(listAfter.length, equals(1));
      expect(listAfter.first.id, equals(trackId));
    });
  });
}
