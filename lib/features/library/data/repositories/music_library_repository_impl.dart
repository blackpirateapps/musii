import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/filesystem/app_file_system.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/result/result.dart';
import '../../../google_drive/domain/entities/drive_item.dart';
import '../../../metadata/data/repositories/metadata_extractor_impl.dart';
import '../../../metadata/domain/entities/parsed_audio_metadata.dart';
import '../../../lyrics/data/repositories/lyrics_repository_impl.dart';
import '../../../lyrics/domain/entities/lyric_model.dart';
import '../../../lyrics/domain/repositories/lyrics_repository.dart';
import '../../../lyrics/domain/services/lrc_parser.dart';
import '../../../metadata/domain/services/metadata_normalization_service.dart';
import '../../domain/entities/music_entities.dart';
import '../../domain/entities/sync_progress.dart';

class MusicLibraryRepositoryImpl implements MusicLibraryRepository {
  final AppDatabase _database;
  final GoogleDriveRepository _driveRepository;
  final MetadataExtractor _metadataExtractor;
  final LyricsRepository _lyricsRepository;
  final AppFileSystem _fileSystem;

  final StreamController<SyncProgress> _syncProgressController =
      StreamController<SyncProgress>.broadcast();

  SyncProgress _currentProgress = const SyncProgress();

  MusicLibraryRepositoryImpl({
    required AppDatabase database,
    required GoogleDriveRepository driveRepository,
    MetadataExtractor? metadataExtractor,
    LyricsRepository? lyricsRepository,
    AppFileSystem? fileSystem,
  }) : _database = database,
       _driveRepository = driveRepository,
       _metadataExtractor = metadataExtractor ?? MetadataExtractor(),
       _lyricsRepository =
           lyricsRepository ?? LyricsRepositoryImpl(database: database),
       _fileSystem = fileSystem ?? AppFileSystem.instance;

  @override
  Stream<SyncProgress> watchSyncProgress() => _syncProgressController.stream;

  void _updateProgress(SyncProgress progress) {
    _currentProgress = progress;
    _syncProgressController.add(progress);
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

  String? _resolveArtworkPath(String? album, String? artist) {
    if (album == null && artist == null) return null;
    final key = MetadataNormalizationService.computeArtworkKey(album, artist);
    final file = _fileSystem.getArtworkCacheFile(key);
    return file.existsSync() ? file.path : null;
  }

  Album _mapDbAlbumToEntity(AlbumRow row) {
    return Album(
      id: row.id,
      title: row.title,
      normalizedTitle: row.normalizedTitle,
      artistId: row.artistId,
      artistName: row.artistName,
      year: row.year,
      artworkPath:
          row.artworkPath ?? _resolveArtworkPath(row.title, row.artistName),
      trackCount: row.trackCount,
      totalDurationMs: row.totalDurationMs,
    );
  }

  Artist _mapDbArtistToEntity(ArtistRow row) {
    return Artist(
      id: row.id,
      name: row.name,
      normalizedName: row.normalizedName,
      artworkPath: row.artworkPath,
      trackCount: row.trackCount,
      albumCount: row.albumCount,
    );
  }

  @override
  Stream<List<Track>> watchAllTracks({String? sortBy}) {
    final query = _database.select(_database.tracks);
    switch (sortBy) {
      case 'artist':
        query.orderBy([
          (tbl) => OrderingTerm.asc(tbl.artistName),
          (tbl) => OrderingTerm.asc(tbl.normalizedTitle),
        ]);
        break;
      case 'recent':
        query.orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]);
        break;
      case 'title':
      default:
        query.orderBy([(tbl) => OrderingTerm.asc(tbl.normalizedTitle)]);
    }
    return query.watch().map((rows) => rows.map(_mapDbTrackToEntity).toList());
  }

  @override
  Stream<List<Album>> watchAllAlbums() {
    return (_database.select(_database.albums)
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.normalizedTitle)]))
        .watch()
        .map((rows) => rows.map(_mapDbAlbumToEntity).toList());
  }

  @override
  Stream<List<Artist>> watchAllArtists() {
    return (_database.select(_database.artists)
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.normalizedName)]))
        .watch()
        .map((rows) => rows.map(_mapDbArtistToEntity).toList());
  }

  @override
  Stream<AlbumWithTracks?> watchAlbum(String albumId) {
    final albumStream = (_database.select(
      _database.albums,
    )..where((tbl) => tbl.id.equals(albumId))).watchSingleOrNull();

    final tracksStream =
        (_database.select(_database.tracks)
              ..where((tbl) => tbl.albumId.equals(albumId))
              ..orderBy([
                (tbl) => OrderingTerm.asc(tbl.discNumber),
                (tbl) => OrderingTerm.asc(tbl.trackNumber),
                (tbl) => OrderingTerm.asc(tbl.normalizedTitle),
              ]))
            .watch();

    return albumStream.asyncMap((albumData) async {
      if (albumData == null) return null;
      final tracks = await tracksStream.first;
      return AlbumWithTracks(
        album: _mapDbAlbumToEntity(albumData),
        tracks: tracks.map(_mapDbTrackToEntity).toList(),
      );
    });
  }

  @override
  Stream<ArtistWithAlbums?> watchArtist(String artistId) {
    final artistStream = (_database.select(
      _database.artists,
    )..where((tbl) => tbl.id.equals(artistId))).watchSingleOrNull();

    final albumsStream =
        (_database.select(_database.albums)
              ..where((tbl) => tbl.artistId.equals(artistId))
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.normalizedTitle)]))
            .watch();

    final tracksStream =
        (_database.select(_database.tracks)
              ..where((tbl) => tbl.artistId.equals(artistId))
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.normalizedTitle)]))
            .watch();

    return artistStream.asyncMap((artistData) async {
      if (artistData == null) return null;
      final albums = await albumsStream.first;
      final tracks = await tracksStream.first;
      return ArtistWithAlbums(
        artist: _mapDbArtistToEntity(artistData),
        albums: albums.map(_mapDbAlbumToEntity).toList(),
        topTracks: tracks.map(_mapDbTrackToEntity).toList(),
      );
    });
  }

  @override
  Future<Result<Track?, AppFailure>> getTrackById(String trackId) async {
    try {
      final row = await (_database.select(
        _database.tracks,
      )..where((tbl) => tbl.id.equals(trackId))).getSingleOrNull();
      return Result.success(row != null ? _mapDbTrackToEntity(row) : null);
    } catch (e) {
      return Result.failure(DatabaseFailure('Error reading track', cause: e));
    }
  }

  @override
  Future<Result<Track?, AppFailure>> getTrackByDriveFileId(
    String driveFileId,
  ) async {
    try {
      final row = await (_database.select(
        _database.tracks,
      )..where((tbl) => tbl.driveFileId.equals(driveFileId))).getSingleOrNull();
      return Result.success(row != null ? _mapDbTrackToEntity(row) : null);
    } catch (e) {
      return Result.failure(
        DatabaseFailure('Error reading track by Drive ID', cause: e),
      );
    }
  }

  @override
  Future<Result<void, AppFailure>> syncLibrary({
    required String rootFolderId,
    required String rootFolderName,
    void Function(SyncProgress progress)? onProgress,
  }) async {
    final syncRunId = 'sync_${DateTime.now().millisecondsSinceEpoch}';
    const sourceId = 'source_gdrive';

    AppLogger.info(
      LogCategory.sync,
      'Starting library sync for folder: $rootFolderName ($rootFolderId)',
    );

    _updateProgress(
      _currentProgress.copyWith(
        phase: SyncPhase.scanning,
        filesDiscovered: 0,
        filesProcessed: 0,
        errorMessage: null,
      ),
    );
    onProgress?.call(_currentProgress);

    try {
      // 1. Record sync run
      await _database
          .into(_database.syncRuns)
          .insert(
            SyncRunsCompanion(
              id: Value(syncRunId),
              sourceId: const Value(sourceId),
              startedAt: Value(DateTime.now()),
              status: const Value('running'),
            ),
          );

      // Save/update music source
      await _database
          .into(_database.musicSources)
          .insertOnConflictUpdate(
            MusicSourcesCompanion(
              id: const Value(sourceId),
              type: const Value('google_drive'),
              accountEmail: const Value('primary'),
              rootFolderId: Value(rootFolderId),
              rootFolderName: Value(rootFolderName),
              createdAt: Value(DateTime.now()),
            ),
          );

      // 2. Discover audio files recursively from Drive
      final scanResult = await _driveRepository.listAudioFilesRecursively(
        rootFolderId,
        onProgress: (count) {
          _updateProgress(_currentProgress.copyWith(filesDiscovered: count));
          onProgress?.call(_currentProgress);
        },
      );

      if (scanResult.isFailure) {
        final err = scanResult.failureOrNull!;
        _updateProgress(
          _currentProgress.copyWith(
            phase: SyncPhase.failed,
            errorMessage: err.message,
          ),
        );
        onProgress?.call(_currentProgress);
        return Result.failure(err);
      }

      final allDriveFiles = scanResult.dataOrNull ?? [];
      final driveAudioFiles = allDriveFiles.where((f) => !f.isLrc).toList();
      final driveLrcFiles = allDriveFiles.where((f) => f.isLrc).toList();

      // Build map of sidecar LRC files keyed by folder and base filename
      final Map<String, DriveFileItem> lrcMap = {};
      for (final lrc in driveLrcFiles) {
        final folder = lrc.parentFolderId ?? '';
        final base = _cleanBaseName(lrc.name);
        lrcMap['${folder}_$base'] = lrc;
      }

      final driveFileMap = {for (final f in driveAudioFiles) f.id: f};

      // 3. Load existing indexed tracks
      final existingTracks = await (_database.select(
        _database.tracks,
      )..where((tbl) => tbl.sourceId.equals(sourceId))).get();
      final existingMap = {for (final t in existingTracks) t.driveFileId: t};

      // 4. Determine diff: added, modified, removed
      final toAddOrUpdate = <DriveFileItem>[];
      for (final df in driveAudioFiles) {
        final existing = existingMap[df.id];
        if (existing == null) {
          toAddOrUpdate.add(df);
        } else if (df.modifiedTime != null &&
            existing.driveModifiedAt != null &&
            df.modifiedTime!.isAfter(existing.driveModifiedAt!)) {
          toAddOrUpdate.add(df);
        }
      }

      final removedDriveIds = existingMap.keys
          .where((id) => !driveFileMap.containsKey(id))
          .toList();

      AppLogger.info(
        LogCategory.sync,
        'Sync Diff: ${toAddOrUpdate.length} to index/update, ${removedDriveIds.length} removed from remote',
      );

      _updateProgress(
        _currentProgress.copyWith(
          phase: SyncPhase.extractingMetadata,
          filesDiscovered: driveAudioFiles.length,
          filesProcessed: 0,
        ),
      );
      onProgress?.call(_currentProgress);

      int processed = 0;
      int addedCount = 0;
      int updatedCount = 0;
      int errorsCount = 0;

      // 5. Process files: download to temporary file, extract metadata, delete temp file immediately
      for (final driveFile in toAddOrUpdate) {
        processed++;
        _updateProgress(
          _currentProgress.copyWith(
            currentFile: driveFile.name,
            filesProcessed: processed,
            progressPercent: toAddOrUpdate.isNotEmpty
                ? (processed / toAddOrUpdate.length)
                : 1.0,
          ),
        );
        onProgress?.call(_currentProgress);

        File? tempFile;
        try {
          tempFile = _fileSystem.getTempMetadataFile(
            'temp_${driveFile.id}_${driveFile.name}',
          );
          final downloadRes = await _driveRepository.downloadFile(
            fileId: driveFile.id,
            destinationFile: tempFile,
          );

          if (downloadRes.isSuccess) {
            final parsedMeta = await _metadataExtractor.extractFromFile(
              tempFile,
              fallbackName: driveFile.name,
              knownFileSize: driveFile.size,
            );

            final normalized = MetadataNormalizationService.normalize(
              parsedMeta,
              filenameFallback: driveFile.name,
            );

            await _upsertTrackAndRelations(
              sourceId: sourceId,
              driveFile: driveFile,
              meta: normalized,
              rawJson: jsonEncode(parsedMeta.rawMetadata ?? {}),
            );

            // Extract & associate lyrics with deterministic priority
            final trackId = 'track_${driveFile.id}';
            await _processLyricsForTrack(
              trackId: trackId,
              driveFile: driveFile,
              parsedMeta: parsedMeta,
              lrcMap: lrcMap,
            );

            if (existingMap.containsKey(driveFile.id)) {
              updatedCount++;
            } else {
              addedCount++;
            }
          } else {
            errorsCount++;
            await _recordSyncError(
              syncRunId,
              driveFile,
              downloadRes.failureOrNull?.message ?? 'Download failed',
            );
          }
        } catch (e) {
          errorsCount++;
          AppLogger.warning(
            LogCategory.sync,
            'Failed processing metadata for ${driveFile.name}',
            e,
          );
          await _recordSyncError(syncRunId, driveFile, e.toString());
        } finally {
          // Immediately delete temporary file!
          if (tempFile != null && await tempFile.exists()) {
            try {
              await tempFile.delete();
            } catch (_) {}
          }
        }
      }

      // 6. Handle removed tracks
      _updateProgress(
        _currentProgress.copyWith(phase: SyncPhase.updatingDatabase),
      );
      onProgress?.call(_currentProgress);

      if (removedDriveIds.isNotEmpty) {
        for (final remId in removedDriveIds) {
          final track = existingMap[remId];
          if (track != null) {
            await (_database.delete(
              _database.tracks,
            )..where((tbl) => tbl.id.equals(track.id))).go();
            await (_database.delete(
              _database.cacheEntries,
            )..where((tbl) => tbl.trackId.equals(track.id))).go();
            await _lyricsRepository.deleteLyricsForTrack(track.id);
          }
        }
      }

      // 7. Recompute album and artist counts and clean empty albums/artists
      await _recomputeLibraryAggregates();

      // 8. Finalize sync run record
      await (_database.update(
        _database.syncRuns,
      )..where((tbl) => tbl.id.equals(syncRunId))).write(
        SyncRunsCompanion(
          completedAt: Value(DateTime.now()),
          status: const Value('completed'),
          filesDiscovered: Value(driveAudioFiles.length),
          filesProcessed: Value(processed),
          filesAdded: Value(addedCount),
          filesUpdated: Value(updatedCount),
          filesRemoved: Value(removedDriveIds.length),
          errorsCount: Value(errorsCount),
        ),
      );

      await (_database.update(_database.musicSources)
            ..where((tbl) => tbl.id.equals(sourceId)))
          .write(MusicSourcesCompanion(lastSyncedAt: Value(DateTime.now())));

      _updateProgress(
        _currentProgress.copyWith(
          phase: SyncPhase.complete,
          filesAdded: addedCount,
          filesUpdated: updatedCount,
          filesRemoved: removedDriveIds.length,
          errorsCount: errorsCount,
          progressPercent: 1.0,
        ),
      );
      onProgress?.call(_currentProgress);

      AppLogger.info(
        LogCategory.sync,
        'Sync completed successfully! Added: $addedCount, Updated: $updatedCount, Removed: ${removedDriveIds.length}, Errors: $errorsCount',
      );

      return const Result.success(null);
    } catch (e, st) {
      AppLogger.error(LogCategory.sync, 'Fatal sync error', e, st);
      _updateProgress(
        _currentProgress.copyWith(
          phase: SyncPhase.failed,
          errorMessage: e.toString(),
        ),
      );
      onProgress?.call(_currentProgress);

      await (_database.update(
        _database.syncRuns,
      )..where((tbl) => tbl.id.equals(syncRunId))).write(
        SyncRunsCompanion(
          completedAt: Value(DateTime.now()),
          status: const Value('failed'),
        ),
      );

      return Result.failure(DatabaseFailure('Sync failed', cause: e));
    }
  }

  Future<void> _recordSyncError(
    String syncRunId,
    DriveFileItem file,
    String message,
  ) async {
    try {
      await _database
          .into(_database.syncErrors)
          .insert(
            SyncErrorsCompanion(
              id: Value('err_${DateTime.now().microsecondsSinceEpoch}'),
              syncRunId: Value(syncRunId),
              fileId: Value(file.id),
              fileName: Value(file.name),
              errorMessage: Value(message),
              errorType: const Value('metadata_extraction'),
              occurredAt: Value(DateTime.now()),
            ),
          );
    } catch (_) {}
  }

  Future<void> _upsertTrackAndRelations({
    required String sourceId,
    required DriveFileItem driveFile,
    required NormalizedMetadata meta,
    required String rawJson,
  }) async {
    await _database.transaction(() async {
      // 1. Artist
      final artistId = 'artist_${meta.normalizedArtist}';
      await _database
          .into(_database.artists)
          .insertOnConflictUpdate(
            ArtistsCompanion(
              id: Value(artistId),
              name: Value(meta.artist),
              normalizedName: Value(meta.normalizedArtist),
            ),
          );

      // 2. Album
      final albumId = 'album_${meta.normalizedArtist}_${meta.normalizedAlbum}';
      final artworkKey = MetadataNormalizationService.computeArtworkKey(
        meta.album,
        meta.artist,
      );
      final artworkFile = _fileSystem.getArtworkCacheFile(artworkKey);

      await _database
          .into(_database.albums)
          .insertOnConflictUpdate(
            AlbumsCompanion(
              id: Value(albumId),
              title: Value(meta.album),
              normalizedTitle: Value(meta.normalizedAlbum),
              artistId: Value(artistId),
              artistName: Value(meta.artist),
              year: Value(meta.year),
              artworkPath: artworkFile.existsSync()
                  ? Value(artworkFile.path)
                  : const Value(null),
            ),
          );

      // 3. Genre
      if (meta.genre != null && meta.normalizedGenre != null) {
        final genreId = 'genre_${meta.normalizedGenre}';
        await _database
            .into(_database.genres)
            .insertOnConflictUpdate(
              GenresCompanion(
                id: Value(genreId),
                name: Value(meta.genre!),
                normalizedName: Value(meta.normalizedGenre!),
              ),
            );
      }

      // 4. Track
      final trackId = 'track_${driveFile.id}';
      await _database
          .into(_database.tracks)
          .insertOnConflictUpdate(
            TracksCompanion(
              id: Value(trackId),
              driveFileId: Value(driveFile.id),
              sourceId: Value(sourceId),
              title: Value(meta.title),
              normalizedTitle: Value(meta.normalizedTitle),
              artistId: Value(artistId),
              artistName: Value(meta.artist),
              albumId: Value(albumId),
              albumName: Value(meta.album),
              albumArtist: Value(meta.albumArtist),
              genre: Value(meta.genre),
              trackNumber: Value(meta.trackNumber),
              discNumber: Value(meta.discNumber),
              year: Value(meta.year),
              durationMs: Value(meta.durationMs),
              bitrate: Value(meta.bitrate),
              sampleRate: Value(meta.sampleRate),
              bitDepth: Value(meta.bitDepth),
              channels: Value(meta.channels),
              format: Value(meta.format),
              fileSize: Value(meta.fileSize),
              mimeType: Value(driveFile.mimeType),
              driveModifiedAt: Value(driveFile.modifiedTime),
              driveMd5Checksum: Value(driveFile.md5Checksum),
              rawMetadataJson: Value(rawJson),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );
    });
  }

  Future<void> _recomputeLibraryAggregates() async {
    final albums = await _database.select(_database.albums).get();
    for (final alb in albums) {
      final tracks = await (_database.select(
        _database.tracks,
      )..where((tbl) => tbl.albumId.equals(alb.id))).get();
      final totalMs = tracks.fold<int>(0, (sum, t) => sum + t.durationMs);
      await (_database.update(
        _database.albums,
      )..where((tbl) => tbl.id.equals(alb.id))).write(
        AlbumsCompanion(
          trackCount: Value(tracks.length),
          totalDurationMs: Value(totalMs),
        ),
      );
    }

    final artists = await _database.select(_database.artists).get();
    for (final art in artists) {
      final tracks = await (_database.select(
        _database.tracks,
      )..where((tbl) => tbl.artistId.equals(art.id))).get();
      final albums = await (_database.select(
        _database.albums,
      )..where((tbl) => tbl.artistId.equals(art.id))).get();
      await (_database.update(
        _database.artists,
      )..where((tbl) => tbl.id.equals(art.id))).write(
        ArtistsCompanion(
          trackCount: Value(tracks.length),
          albumCount: Value(albums.length),
        ),
      );
    }
  }

  String _cleanBaseName(String filename) {
    final withoutExt = filename.contains('.')
        ? filename.substring(0, filename.lastIndexOf('.'))
        : filename;
    return withoutExt.trim().toLowerCase();
  }

  Future<void> _processLyricsForTrack({
    required String trackId,
    required DriveFileItem driveFile,
    required ParsedAudioMetadata parsedMeta,
    required Map<String, DriveFileItem> lrcMap,
  }) async {
    try {
      final folder = driveFile.parentFolderId ?? '';
      final base = _cleanBaseName(driveFile.name);
      final matchingLrc = lrcMap['${folder}_$base'];

      final embedded = parsedMeta.lyrics;
      final bool hasEmbedded = embedded != null && embedded.trim().isNotEmpty;

      if (hasEmbedded) {
        final parsedEmbedded = LrcParser.parse(embedded);
        if (parsedEmbedded.isSynchronized && parsedEmbedded.lines.isNotEmpty) {
          // 1. Embedded synchronized
          await _lyricsRepository.saveLyrics(
            trackId: trackId,
            source: LyricSource.embeddedSynced,
            isSynchronized: true,
            rawText: parsedEmbedded.rawText,
            offsetMs: parsedEmbedded.offsetMs,
            lines: parsedEmbedded.lines,
          );
          return;
        } else if (parsedEmbedded.lines.isNotEmpty) {
          // 2. Embedded unsynchronized / plain
          await _lyricsRepository.saveLyrics(
            trackId: trackId,
            source: LyricSource.embeddedPlain,
            isSynchronized: false,
            rawText: parsedEmbedded.rawText,
            offsetMs: 0,
            lines: parsedEmbedded.lines,
          );
          return;
        } else if (matchingLrc != null) {
          // Fall back to matching LRC if embedded was empty or malformed
          await _fetchAndSaveSidecarLrc(trackId, matchingLrc);
          return;
        }
      } else if (matchingLrc != null) {
        // 3. Matching external .lrc file
        await _fetchAndSaveSidecarLrc(trackId, matchingLrc);
        return;
      }
    } catch (e, st) {
      AppLogger.warning(
        LogCategory.metadata,
        'Error indexing lyrics for track $trackId',
        e,
        st,
      );
    }
  }

  Future<void> _fetchAndSaveSidecarLrc(
    String trackId,
    DriveFileItem lrcFile,
  ) async {
    try {
      final lrcRes = await _driveRepository.downloadTextFile(lrcFile.id);
      if (lrcRes.isSuccess) {
        final text = lrcRes.dataOrNull ?? '';
        final parsed = LrcParser.parse(text);
        if (parsed.lines.isNotEmpty) {
          await _lyricsRepository.saveLyrics(
            trackId: trackId,
            source: LyricSource.sidecarLrc,
            isSynchronized: parsed.isSynchronized,
            rawText: parsed.rawText,
            offsetMs: parsed.offsetMs,
            lines: parsed.lines,
          );
        }
      }
    } catch (e) {
      AppLogger.warning(
        LogCategory.metadata,
        'Failed to fetch sidecar LRC for $trackId',
        e,
      );
    }
  }
}
