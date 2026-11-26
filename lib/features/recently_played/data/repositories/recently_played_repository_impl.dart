import 'package:drift/drift.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/filesystem/app_file_system.dart';
import '../../../library/domain/entities/music_entities.dart';
import '../../../metadata/domain/services/metadata_normalization_service.dart';

abstract class RecentlyPlayedRepository {
  Stream<List<Track>> watchRecentlyPlayed({int limit = 30});
  Future<void> recordPlayback(
    String trackId,
    int durationPlayedMs,
    bool completed,
  );
}

class RecentlyPlayedRepositoryImpl implements RecentlyPlayedRepository {
  final AppDatabase _database;
  final AppFileSystem _fileSystem;

  RecentlyPlayedRepositoryImpl({
    required AppDatabase database,
    AppFileSystem? fileSystem,
  }) : _database = database,
       _fileSystem = fileSystem ?? AppFileSystem.instance;

  String? _resolveArtworkPath(String? album, String? artist) {
    if (album == null && artist == null) return null;
    final key = MetadataNormalizationService.computeArtworkKey(album, artist);
    final file = _fileSystem.getArtworkCacheFile(key);
    return file.existsSync() ? file.path : null;
  }

  Track _mapDbTrackToEntity(TrackRow row) {
    return Track(
      id: row.id,
      driveFileId: row.driveFileId,
      sourceId: row.sourceId,
      title: row.title,
      normalizedTitle: row.normalizedTitle,
      artistId: row.artistId,
      artistName: row.artistName,
      albumId: row.albumId,
      albumName: row.albumName,
      albumArtist: row.albumArtist,
      genre: row.genre,
      trackNumber: row.trackNumber,
      discNumber: row.discNumber,
      year: row.year,
      durationMs: row.durationMs,
      bitrate: row.bitrate,
      sampleRate: row.sampleRate,
      bitDepth: row.bitDepth,
      channels: row.channels,
      format: row.format,
      fileSize: row.fileSize,
      mimeType: row.mimeType,
      driveModifiedAt: row.driveModifiedAt,
      localPath: row.localPath,
      isCached: row.isCached,
      isPinnedOffline: row.isPinnedOffline,
      artworkPath:
          row.artworkPath ??
          _resolveArtworkPath(row.albumName, row.albumArtist) ??
          _resolveArtworkPath(row.albumName, row.artistName),
    );
  }

  @override
  Stream<List<Track>> watchRecentlyPlayed({int limit = 30}) {
    return _database
        .customSelect(
          """
      WITH latest AS (
        SELECT track_id, played_at, id,
          ROW_NUMBER() OVER (PARTITION BY track_id ORDER BY played_at DESC, id DESC) AS rank
        FROM recently_played
      )
      SELECT tracks.* FROM latest JOIN tracks ON tracks.id = latest.track_id
      WHERE latest.rank = 1
      ORDER BY latest.played_at DESC, latest.id DESC
      LIMIT ?
      """,
          variables: [Variable.withInt(limit)],
          readsFrom: {_database.tracks, _database.recentlyPlayed},
        )
        .watch()
        .map(
          (rows) => rows
              .map((row) => _mapDbTrackToEntity(_database.tracks.map(row.data)))
              .toList(),
        );
  }

  @override
  Future<void> recordPlayback(
    String trackId,
    int durationPlayedMs,
    bool completed,
  ) async {
    final track = await (_database.select(
      _database.tracks,
    )..where((tbl) => tbl.id.equals(trackId))).getSingleOrNull();

    if (track == null) return;

    final thresholdMs = (track.durationMs > 0)
        ? (track.durationMs * AppAudioConstants.minPlayRatioForHistory).toInt()
        : (AppAudioConstants.minPlaySecondsForHistory * 1000);

    // Only record if meaningful threshold exceeded or track finished
    if (completed || durationPlayedMs >= thresholdMs) {
      await _database
          .into(_database.recentlyPlayed)
          .insert(
            RecentlyPlayedCompanion(
              id: Value('rec_${DateTime.now().microsecondsSinceEpoch}'),
              trackId: Value(trackId),
              playedAt: Value(DateTime.now()),
              playbackDurationMs: Value(durationPlayedMs),
              completed: Value(completed),
            ),
          );
    }
  }
}
