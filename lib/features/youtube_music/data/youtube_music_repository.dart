import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/error/failures.dart';
import '../../../core/result/result.dart';
import '../../library/domain/entities/music_entities.dart';
import '../../metadata/domain/services/metadata_normalization_service.dart';
import '../domain/youtube_music_collection.dart';
import '../domain/youtube_music_link.dart';
import 'youtube_music_client.dart';

typedef YouTubeMusicSection = ({
  String title,
  List<Track> tracks,
  List<YouTubeMusicCollection> collections,
});
typedef YouTubeMusicSearchPage = ({List<Track> tracks, String? nextPage});

class YouTubeMusicRepository {
  const YouTubeMusicRepository(this._database, this._client);

  final AppDatabase _database;
  final YouTubeMusicClient _client;

  Future<List<YouTubeMusicSection>> browseHome() async {
    final shelves = await _client.getHome();
    return shelves.map(_toSection).toList();
  }

  Future<({List<YouTubeMusicSection> sections, String? nextPage})>
  browseCollection(String browseId, {String? nextPage}) async {
    final page = await _client.getCollection(browseId, nextPage: nextPage);
    return (
      sections: page.sections.map(_toSection).toList(),
      nextPage: page.nextPage,
    );
  }

  Future<YouTubeCollectionSearchPage> searchCollections(
    String query,
    YouTubeMusicCategory category, {
    String? nextPage,
  }) => _client.searchCollections(query, category, nextPage: nextPage);

  Future<YouTubeMusicSearchPage> searchSongs(
    String query, {
    String? nextPage,
  }) async {
    final page = await _client.searchSongs(query, nextPage: nextPage);
    return (
      tracks: page.tracks.map(_toTrack).toList(),
      nextPage: page.nextPage,
    );
  }

  Future<Result<Track, AppFailure>> importLink(String link) async {
    final videoId = youtubeVideoIdFromLink(link);
    if (videoId == null) {
      return const Result.failure(
        ValidationFailure('Paste a YouTube Music or YouTube song link.'),
      );
    }

    try {
      final track = _toTrack(await _client.getTrack(videoId));
      await saveTracks([track]);
      return Result.success(track);
    } on AppFailure catch (failure) {
      return Result.failure(failure);
    }
  }

  Future<void> saveTracks(List<Track> tracks) async {
    final now = DateTime.now();
    try {
      await _database.batch((batch) {
        for (final track in tracks) {
          final artist = track.artistName == null
              ? const Value<String?>.absent()
              : Value(track.artistName);
          final duration = track.durationMs == 0
              ? const Value<int>.absent()
              : Value(track.durationMs);
          final artwork = track.artworkUrl == null
              ? const Value<String?>.absent()
              : Value(track.artworkUrl);
          batch.insert(
            _database.tracks,
            TracksCompanion.insert(
              id: track.id,
              sourceId: track.sourceId,
              youtubeVideoId: Value(track.youtubeVideoId),
              title: track.title,
              normalizedTitle: track.normalizedTitle,
              artistName: artist,
              durationMs: duration,
              artworkUrl: artwork,
              createdAt: now,
              updatedAt: now,
            ),
            onConflict: DoUpdate(
              (_) => TracksCompanion(
                title: Value(track.title),
                normalizedTitle: Value(track.normalizedTitle),
                artistName: artist,
                durationMs: duration,
                artworkUrl: artwork,
                updatedAt: Value(now),
              ),
            ),
          );
        }
      });
    } catch (error) {
      throw DatabaseFailure('Could not save the YouTube tracks.', cause: error);
    }
  }

  Track _toTrack(YouTubeTrackInfo details) => Track(
    id: 'youtube_${details.videoId}',
    sourceId: 'source_youtube_music',
    youtubeVideoId: details.videoId,
    title: details.title,
    normalizedTitle: MetadataNormalizationService.searchKey(details.title),
    artistName: details.artist,
    durationMs: details.durationMs,
    artworkUrl: details.artworkUrl,
  );

  YouTubeMusicSection _toSection(YouTubeHomeShelf shelf) => (
    title: shelf.title,
    tracks: shelf.tracks.map(_toTrack).toList(),
    collections: shelf.collections,
  );
}
