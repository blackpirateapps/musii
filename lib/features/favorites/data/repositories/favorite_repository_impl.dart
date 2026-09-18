import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/filesystem/app_file_system.dart';
import '../../../../core/result/result.dart';
import '../../../library/domain/entities/music_entities.dart';
import '../../../metadata/domain/services/metadata_normalization_service.dart';

abstract class FavoriteRepository {
  Stream<List<Track>> watchFavoriteTracks();
  Stream<bool> watchIsFavorite(String trackId);
  Future<Result<bool, AppFailure>> toggleFavorite(String trackId);
}

class FavoriteRepositoryImpl implements FavoriteRepository {
  final AppDatabase _database;
  final AppFileSystem _fileSystem;

  FavoriteRepositoryImpl({
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
  Stream<List<Track>> watchFavoriteTracks() {
    final query = _database.select(_database.favorites).join([
      innerJoin(
        _database.tracks,
        _database.tracks.id.equalsExp(_database.favorites.trackId),
      ),
    ])..orderBy([OrderingTerm.desc(_database.favorites.addedAt)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        final trackData = row.readTable(_database.tracks);
        return _mapDbTrackToEntity(trackData);
      }).toList();
    });
  }

  @override
  Stream<bool> watchIsFavorite(String trackId) {
    return (_database.select(_database.favorites)
          ..where((tbl) => tbl.trackId.equals(trackId)))
        .watch()
        .map((rows) => rows.isNotEmpty);
  }

  @override
  Future<Result<bool, AppFailure>> toggleFavorite(String trackId) async {
    try {
      final existing = await (_database.select(
        _database.favorites,
      )..where((tbl) => tbl.trackId.equals(trackId))).getSingleOrNull();

      if (existing != null) {
        await (_database.delete(
          _database.favorites,
        )..where((tbl) => tbl.trackId.equals(trackId))).go();
        return const Result.success(false);
      } else {
        await _database
            .into(_database.favorites)
            .insert(
              FavoritesCompanion(
                id: Value('fav_${DateTime.now().microsecondsSinceEpoch}'),
                trackId: Value(trackId),
                addedAt: Value(DateTime.now()),
              ),
            );
        return const Result.success(true);
      }
    } catch (e) {
      return Result.failure(
        DatabaseFailure('Failed to toggle favorite', cause: e),
      );
    }
  }
}
