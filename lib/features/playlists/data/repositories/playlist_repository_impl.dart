import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/filesystem/app_file_system.dart';
import '../../../../core/result/result.dart';
import '../../../library/domain/entities/music_entities.dart';
import '../../../metadata/domain/services/metadata_normalization_service.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/repositories/playlist_repository.dart';

class PlaylistRepositoryImpl implements PlaylistRepository {
  final AppDatabase _database;
  final AppFileSystem _fileSystem;

  PlaylistRepositoryImpl({
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
      artworkPath: _resolveArtworkPath(row.albumName, row.artistName),
    );
  }

  @override
  Stream<List<Playlist>> watchPlaylists() {
    return (_database.select(_database.playlists)
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)]))
        .watch()
        .map((rows) {
          return rows
              .map(
                (r) => Playlist(
                  id: r.id,
                  name: r.name,
                  description: r.description,
                  artworkPath: r.artworkPath,
                  trackCount: r.trackCount,
                  createdAt: r.createdAt,
                  updatedAt: r.updatedAt,
                ),
              )
              .toList();
        });
  }

  @override
  Stream<List<Track>> watchPlaylistTracks(String playlistId) {
    final query =
        _database.select(_database.playlistTracks).join([
            innerJoin(
              _database.tracks,
              _database.tracks.id.equalsExp(_database.playlistTracks.trackId),
            ),
          ])
          ..where(_database.playlistTracks.playlistId.equals(playlistId))
          ..orderBy([OrderingTerm.asc(_database.playlistTracks.sortOrder)]);

    return query.watch().map((rows) {
      return rows
          .map((r) => _mapDbTrackToEntity(r.readTable(_database.tracks)))
          .toList();
    });
  }

  @override
  Future<Result<String, AppFailure>> createPlaylist(
    String name, {
    String? description,
  }) async {
    try {
      final id = 'pl_${DateTime.now().millisecondsSinceEpoch}';
      await _database
          .into(_database.playlists)
          .insert(
            PlaylistsCompanion(
              id: Value(id),
              name: Value(name.trim()),
              description: Value(description?.trim()),
              trackCount: const Value(0),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );
      return Result.success(id);
    } catch (e) {
      return Result.failure(
        DatabaseFailure('Failed to create playlist', cause: e),
      );
    }
  }

  @override
  Future<Result<void, AppFailure>> renamePlaylist(
    String playlistId,
    String newName,
  ) async {
    try {
      await (_database.update(
        _database.playlists,
      )..where((tbl) => tbl.id.equals(playlistId))).write(
        PlaylistsCompanion(
          name: Value(newName.trim()),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return const Result.success(null);
    } catch (e) {
      return Result.failure(
        DatabaseFailure('Failed to rename playlist', cause: e),
      );
    }
  }

  @override
  Future<Result<void, AppFailure>> deletePlaylist(String playlistId) async {
    try {
      await _database.transaction(() async {
        await (_database.delete(
          _database.playlistTracks,
        )..where((tbl) => tbl.playlistId.equals(playlistId))).go();
        await (_database.delete(
          _database.playlists,
        )..where((tbl) => tbl.id.equals(playlistId))).go();
      });
      return const Result.success(null);
    } catch (e) {
      return Result.failure(
        DatabaseFailure('Failed to delete playlist', cause: e),
      );
    }
  }

  @override
  Future<Result<void, AppFailure>> addTrackToPlaylist(
    String playlistId,
    String trackId,
  ) async {
    try {
      await _database.transaction(() async {
        final existingTracks = await (_database.select(
          _database.playlistTracks,
        )..where((tbl) => tbl.playlistId.equals(playlistId))).get();

        final nextOrder = existingTracks.length;

        await _database
            .into(_database.playlistTracks)
            .insert(
              PlaylistTracksCompanion(
                id: Value('plt_${DateTime.now().microsecondsSinceEpoch}'),
                playlistId: Value(playlistId),
                trackId: Value(trackId),
                sortOrder: Value(nextOrder),
                addedAt: Value(DateTime.now()),
              ),
            );

        await (_database.update(
          _database.playlists,
        )..where((tbl) => tbl.id.equals(playlistId))).write(
          PlaylistsCompanion(
            trackCount: Value(nextOrder + 1),
            updatedAt: Value(DateTime.now()),
          ),
        );
      });
      return const Result.success(null);
    } catch (e) {
      return Result.failure(
        DatabaseFailure('Failed to add track to playlist', cause: e),
      );
    }
  }

  @override
  Future<Result<void, AppFailure>> removeTrackFromPlaylist(
    String playlistId,
    String trackId,
  ) async {
    try {
      await _database.transaction(() async {
        await (_database.delete(_database.playlistTracks)..where(
              (tbl) =>
                  tbl.playlistId.equals(playlistId) &
                  tbl.trackId.equals(trackId),
            ))
            .go();

        // Re-index sort order
        final remaining =
            await (_database.select(_database.playlistTracks)
                  ..where((tbl) => tbl.playlistId.equals(playlistId))
                  ..orderBy([(tbl) => OrderingTerm.asc(tbl.sortOrder)]))
                .get();

        for (int i = 0; i < remaining.length; i++) {
          await (_database.update(_database.playlistTracks)
                ..where((tbl) => tbl.id.equals(remaining[i].id)))
              .write(PlaylistTracksCompanion(sortOrder: Value(i)));
        }

        await (_database.update(
          _database.playlists,
        )..where((tbl) => tbl.id.equals(playlistId))).write(
          PlaylistsCompanion(
            trackCount: Value(remaining.length),
            updatedAt: Value(DateTime.now()),
          ),
        );
      });
      return const Result.success(null);
    } catch (e) {
      return Result.failure(
        DatabaseFailure('Failed to remove track from playlist', cause: e),
      );
    }
  }

  @override
  Future<Result<void, AppFailure>> reorderPlaylistTracks(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    try {
      await _database.transaction(() async {
        final items =
            await (_database.select(_database.playlistTracks)
                  ..where((tbl) => tbl.playlistId.equals(playlistId))
                  ..orderBy([(tbl) => OrderingTerm.asc(tbl.sortOrder)]))
                .get();

        if (oldIndex < 0 ||
            oldIndex >= items.length ||
            newIndex < 0 ||
            newIndex >= items.length) {
          return;
        }

        final mutableList = List<PlaylistTrack>.from(items);
        final item = mutableList.removeAt(oldIndex);
        mutableList.insert(newIndex, item);

        for (int i = 0; i < mutableList.length; i++) {
          await (_database.update(_database.playlistTracks)
                ..where((tbl) => tbl.id.equals(mutableList[i].id)))
              .write(PlaylistTracksCompanion(sortOrder: Value(i)));
        }

        await (_database.update(_database.playlists)
              ..where((tbl) => tbl.id.equals(playlistId)))
            .write(PlaylistsCompanion(updatedAt: Value(DateTime.now())));
      });
      return const Result.success(null);
    } catch (e) {
      return Result.failure(
        DatabaseFailure('Failed to reorder playlist', cause: e),
      );
    }
  }
}
