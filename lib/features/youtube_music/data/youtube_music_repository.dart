import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/error/failures.dart';
import '../../../core/result/result.dart';
import '../../library/domain/entities/music_entities.dart';
import '../../metadata/domain/services/metadata_normalization_service.dart';
import '../domain/youtube_music_link.dart';
import 'youtube_music_client.dart';

class YouTubeMusicRepository {
  const YouTubeMusicRepository(this._database, this._client);

  final AppDatabase _database;
  final YouTubeMusicClient _client;

  Future<Result<Track, AppFailure>> importLink(String link) async {
    final videoId = youtubeVideoIdFromLink(link);
    if (videoId == null) {
      return const Result.failure(
        ValidationFailure('Paste a YouTube Music or YouTube song link.'),
      );
    }

    try {
      final id = 'youtube_$videoId';
      const sourceId = 'source_youtube_music';
      final details = await _client.getTrack(videoId);
      final normalizedTitle = MetadataNormalizationService.searchKey(
        details.title,
      );
      final now = DateTime.now();
      await _database
          .into(_database.tracks)
          .insert(
            TracksCompanion.insert(
              id: id,
              youtubeVideoId: Value(videoId),
              sourceId: sourceId,
              title: details.title,
              normalizedTitle: normalizedTitle,
              artistName: Value(details.artist),
              durationMs: Value(details.durationMs),
              artworkUrl: Value(details.artworkUrl),
              createdAt: now,
              updatedAt: now,
            ),
            onConflict: DoUpdate(
              (_) => TracksCompanion(
                title: Value(details.title),
                normalizedTitle: Value(normalizedTitle),
                artistName: Value(details.artist),
                durationMs: Value(details.durationMs),
                artworkUrl: Value(details.artworkUrl),
                updatedAt: Value(now),
              ),
            ),
          );
      return Result.success(
        Track(
          id: id,
          youtubeVideoId: videoId,
          sourceId: sourceId,
          title: details.title,
          normalizedTitle: normalizedTitle,
          artistName: details.artist,
          durationMs: details.durationMs,
          artworkUrl: details.artworkUrl,
        ),
      );
    } on AppFailure catch (failure) {
      return Result.failure(failure);
    } catch (error) {
      return Result.failure(
        DatabaseFailure('Could not save the YouTube track.', cause: error),
      );
    }
  }
}
