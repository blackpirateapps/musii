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
import '../../../lyrics/data/repositories/lyrics_repository_impl.dart';
import '../../../lyrics/domain/entities/lyric_model.dart';
import '../../../lyrics/domain/repositories/lyrics_repository.dart';
import '../../../lyrics/domain/services/lrc_parser.dart';
import '../../../metadata/data/repositories/metadata_extractor_impl.dart';
import '../../../metadata/domain/entities/parsed_audio_metadata.dart';
import '../../../metadata/domain/services/metadata_normalization_service.dart';
import '../../domain/entities/music_entities.dart';
import '../../domain/entities/sync_progress.dart';

enum TrackSyncAction {
  unchangedComplete,
  updateModified,
  processNew,
  repairIncomplete,
}

class MusicLibraryRepositoryImpl implements MusicLibraryRepository {
  final AppDatabase _database;
  final GoogleDriveRepository _driveRepository;
  final MetadataExtractor _metadataExtractor;
  final LyricsRepository _lyricsRepository;
  final AppFileSystem _fileSystem;

  final StreamController<SyncProgress> _syncProgressController =
      StreamController<SyncProgress>.broadcast();

  SyncProgress _currentProgress = const SyncProgress();
  bool _isSyncRunning = false;
  SyncCancellationToken? _currentCancellationToken;

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
       _fileSystem = fileSystem ?? AppFileSystem.instance {
    unawaited(_hydrateInitialState());
  }

  Future<void> _hydrateInitialState() async {
    try {
      final latest =
          await (_database.select(_database.syncRuns)
                ..orderBy([(tbl) => OrderingTerm.desc(tbl.startedAt)])
                ..limit(1))
              .getSingleOrNull();

      if (latest != null) {
        SyncPhase phase;
        bool isResumable = false;

        switch (latest.status) {
          case 'running':
          case 'stopping':
            // Stale unclosed session from process termination -> interrupted and resumable
            phase = SyncPhase.stopped;
            isResumable = true;
            break;
          case 'stopped':
            phase = SyncPhase.stopped;
            isResumable = true;
            break;
          case 'completed':
            phase = SyncPhase.complete;
            isResumable = false;
            break;
          case 'failed':
            phase = SyncPhase.failed;
            isResumable = true;
            break;
          default:
            phase = SyncPhase.idle;
        }

        _currentProgress = SyncProgress(
          syncRunId: latest.id,
          phase: phase,
          filesDiscovered: latest.filesDiscovered,
          filesProcessed: latest.filesProcessed,
          filesAdded: latest.filesAdded,
          filesUpdated: latest.filesUpdated,
          filesRemoved: latest.filesRemoved,
          errorsCount: latest.errorsCount,
          currentFile: latest.currentFile,
          errorMessage: latest.errorMessage,
          progressPercent: latest.progressPercent,
          lastCheckpointAt: latest.lastCheckpointAt ?? latest.updatedAt,
          isResumable: isResumable,
          rootFolderId: latest.rootFolderId,
          rootFolderName: latest.rootFolderName,
        );
        _syncProgressController.add(_currentProgress);
      }
    } catch (e) {
      AppLogger.warning(
        LogCategory.sync,
        'Error hydrating initial sync state from database',
        e,
      );
    }
  }

  @override
  Stream<SyncProgress> watchSyncProgress() => _syncProgressController.stream;

  void _updateProgress(SyncProgress progress) {
    _currentProgress = progress;
    _syncProgressController.add(progress);
  }

  @override
  Future<SyncProgress?> getLastSyncSession() async {
    try {
      final latest =
          await (_database.select(_database.syncRuns)
                ..orderBy([(tbl) => OrderingTerm.desc(tbl.startedAt)])
                ..limit(1))
              .getSingleOrNull();

      if (latest == null) return null;

      return SyncProgress(
        syncRunId: latest.id,
        phase: _parsePhase(latest.phase, latest.status),
        filesDiscovered: latest.filesDiscovered,
        filesProcessed: latest.filesProcessed,
        filesAdded: latest.filesAdded,
        filesUpdated: latest.filesUpdated,
        filesRemoved: latest.filesRemoved,
        errorsCount: latest.errorsCount,
        currentFile: latest.currentFile,
        errorMessage: latest.errorMessage,
        progressPercent: latest.progressPercent,
        lastCheckpointAt: latest.lastCheckpointAt ?? latest.updatedAt,
        isResumable: latest.status == 'stopped' || latest.status == 'running',
        rootFolderId: latest.rootFolderId,
        rootFolderName: latest.rootFolderName,
      );
    } catch (e) {
      return null;
    }
  }

  SyncPhase _parsePhase(String? phaseStr, String status) {
    if (status == 'completed') return SyncPhase.complete;
    if (status == 'stopped') return SyncPhase.stopped;
    if (status == 'failed') return SyncPhase.failed;
    switch (phaseStr) {
      case 'scanning':
        return SyncPhase.scanning;
      case 'extractingMetadata':
        return SyncPhase.extractingMetadata;
      case 'updatingDatabase':
        return SyncPhase.updatingDatabase;
      case 'stopping':
        return SyncPhase.stopping;
      case 'stopped':
        return SyncPhase.stopped;
      case 'complete':
        return SyncPhase.complete;
      case 'failed':
        return SyncPhase.failed;
      default:
        return SyncPhase.idle;
    }
  }

  @override
  Future<void> recoverInterruptedSyncIfNeeded() async {
    try {
      final latest =
          await (_database.select(_database.syncRuns)
                ..orderBy([(tbl) => OrderingTerm.desc(tbl.startedAt)])
                ..limit(1))
              .getSingleOrNull();

      if (latest != null &&
          (latest.status == 'running' || latest.status == 'stopping')) {
        AppLogger.info(
          LogCategory.sync,
          'Detected interrupted sync session: ${latest.id} with status ${latest.status}. Initiating automatic resume...',
        );

        final folderId = latest.rootFolderId;

        if (folderId != null) {
          unawaited(resumeSync());
        }
      }
    } catch (e, st) {
      AppLogger.warning(
        LogCategory.sync,
        'Failed to check for interrupted sync during startup',
        e,
        st,
      );
    }
  }

  @override
  Future<Result<void, AppFailure>> stopSync() async {
    if (!_isSyncRunning || _currentCancellationToken == null) {
      AppLogger.info(
        LogCategory.sync,
        'stopSync called but no active synchronization is running',
      );
      return const Result.success(null);
    }

    AppLogger.info(LogCategory.sync, 'User requested graceful stopSync');
    _currentCancellationToken?.cancel();
    _updateProgress(_currentProgress.copyWith(phase: SyncPhase.stopping));
    return const Result.success(null);
  }

  @override
  Future<Result<void, AppFailure>> resumeSync() async {
    if (_isSyncRunning) {
      AppLogger.warning(
        LogCategory.sync,
        'resumeSync called but sync is already active',
      );
      return const Result.success(null);
    }

    String? folderId = _currentProgress.rootFolderId;
    String? folderName = _currentProgress.rootFolderName;

    if (folderId == null) {
      final latest =
          await (_database.select(_database.syncRuns)
                ..orderBy([(tbl) => OrderingTerm.desc(tbl.startedAt)])
                ..limit(1))
              .getSingleOrNull();
      if (latest != null) {
        folderId = latest.rootFolderId;
        folderName = latest.rootFolderName;
      }
    }

    if (folderId == null) {
      final source = await (_database.select(
        _database.musicSources,
      )..where((tbl) => tbl.id.equals('source_gdrive'))).getSingleOrNull();
      if (source != null && source.rootFolderId != null) {
        folderId = source.rootFolderId;
        folderName = source.rootFolderName;
      }
    }

    if (folderId == null) {
      return const Result.failure(
        DriveApiFailure('No previous folder found to resume sync'),
      );
    }

    return syncLibrary(
      rootFolderId: folderId,
      rootFolderName: folderName ?? 'Music',
      isResume: true,
    );
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

  TrackSyncAction _classifyTrack(DriveFileItem remote, TrackRow? local) {
    if (local == null) {
      return TrackSyncAction.processNew;
    }

    final isMetadataComplete =
        local.title.trim().isNotEmpty &&
        local.normalizedTitle.trim().isNotEmpty &&
        local.format != null &&
        local.format!.isNotEmpty &&
        local.fileSize == remote.size;

    if (!isMetadataComplete) {
      return TrackSyncAction.repairIncomplete;
    }

    // Change detection via modified timestamp
    if (remote.modifiedTime != null && local.driveModifiedAt != null) {
      if (remote.modifiedTime!.isAfter(local.driveModifiedAt!)) {
        return TrackSyncAction.updateModified;
      }
    }

    // Change detection via checksum
    if (remote.md5Checksum != null && local.driveMd5Checksum != null) {
      if (remote.md5Checksum != local.driveMd5Checksum) {
        return TrackSyncAction.updateModified;
      }
    }

    // Change detection via file size
    if (remote.size != local.fileSize) {
      return TrackSyncAction.updateModified;
    }

    return TrackSyncAction.unchangedComplete;
  }

  @override
  Future<Result<void, AppFailure>> syncLibrary({
    required String rootFolderId,
    required String rootFolderName,
    void Function(SyncProgress progress)? onProgress,
    bool isResume = false,
  }) async {
    if (_isSyncRunning) {
      AppLogger.warning(
        LogCategory.sync,
        'Sync already in progress; rejecting concurrent sync request',
      );
      return const Result.failure(
        DriveApiFailure('Synchronization is already in progress'),
      );
    }

    _isSyncRunning = true;
    final cancellationToken = SyncCancellationToken();
    _currentCancellationToken = cancellationToken;

    final syncRunId = (isResume && _currentProgress.syncRunId != null)
        ? _currentProgress.syncRunId!
        : 'sync_${DateTime.now().millisecondsSinceEpoch}';
    const sourceId = 'source_gdrive';

    AppLogger.info(
      LogCategory.sync,
      '${isResume ? "Resuming" : "Starting"} library sync (Run ID: $syncRunId, Folder: $rootFolderName [$rootFolderId])',
    );

    try {
      // 1. Record / update sync run in database
      await _database
          .into(_database.syncRuns)
          .insertOnConflictUpdate(
            SyncRunsCompanion(
              id: Value(syncRunId),
              sourceId: const Value(sourceId),
              rootFolderId: Value(rootFolderId),
              rootFolderName: Value(rootFolderName),
              startedAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
              lastCheckpointAt: Value(DateTime.now()),
              status: const Value('running'),
              phase: const Value('scanning'),
              filesDiscovered: Value(_currentProgress.filesDiscovered),
              filesProcessed: Value(
                isResume ? _currentProgress.filesProcessed : 0,
              ),
              filesAdded: Value(isResume ? _currentProgress.filesAdded : 0),
              filesUpdated: Value(isResume ? _currentProgress.filesUpdated : 0),
              filesRemoved: Value(isResume ? _currentProgress.filesRemoved : 0),
              errorsCount: Value(isResume ? _currentProgress.errorsCount : 0),
              progressPercent: Value(
                isResume ? _currentProgress.progressPercent : 0.0,
              ),
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
      _updateProgress(
        _currentProgress.copyWith(
          syncRunId: syncRunId,
          phase: SyncPhase.scanning,
          rootFolderId: rootFolderId,
          rootFolderName: rootFolderName,
          errorMessage: null,
          isResumable: false,
        ),
      );
      onProgress?.call(_currentProgress);

      final scanResult = await _driveRepository.listAudioFilesRecursively(
        rootFolderId,
        onProgress: (count) {
          _updateProgress(_currentProgress.copyWith(filesDiscovered: count));
          onProgress?.call(_currentProgress);
        },
        isCancelled: () => cancellationToken.isCancelled,
      );

      if (cancellationToken.isCancelled) {
        await _persistSessionStopped(
          syncRunId: syncRunId,
          filesDiscovered: _currentProgress.filesDiscovered,
          filesProcessed: _currentProgress.filesProcessed,
        );
        _updateProgress(
          _currentProgress.copyWith(
            phase: SyncPhase.stopped,
            isResumable: true,
            currentFile: null,
          ),
        );
        onProgress?.call(_currentProgress);
        return const Result.success(null);
      }

      if (scanResult.isFailure) {
        final err = scanResult.failureOrNull!;
        await _persistSessionFailed(syncRunId: syncRunId, error: err.message);
        _updateProgress(
          _currentProgress.copyWith(
            phase: SyncPhase.failed,
            errorMessage: err.message,
            isResumable: true,
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

      // 4. Classify each audio file
      final List<DriveFileItem> toProcess = [];
      final List<DriveFileItem> unchangedComplete = [];

      for (final df in driveAudioFiles) {
        final existing = existingMap[df.id];
        final action = _classifyTrack(df, existing);
        switch (action) {
          case TrackSyncAction.unchangedComplete:
            unchangedComplete.add(df);
            break;
          case TrackSyncAction.updateModified:
          case TrackSyncAction.processNew:
          case TrackSyncAction.repairIncomplete:
            toProcess.add(df);
            break;
        }
      }

      final totalDiscovered = driveAudioFiles.length;
      int processedCount = unchangedComplete.length;
      int addedCount = 0;
      int updatedCount = 0;
      int errorsCount = 0;

      final initialPercent = totalDiscovered > 0
          ? (processedCount / totalDiscovered)
          : 1.0;

      AppLogger.info(
        LogCategory.sync,
        'Sync Classification: Total discovered=$totalDiscovered, Unchanged complete=${unchangedComplete.length} (Skipping downloads), To process=${toProcess.length}',
      );

      _updateProgress(
        _currentProgress.copyWith(
          phase: SyncPhase.extractingMetadata,
          filesDiscovered: totalDiscovered,
          filesProcessed: processedCount,
          progressPercent: initialPercent,
        ),
      );
      onProgress?.call(_currentProgress);

      // Checkpoint the classified baseline
      await (_database.update(
        _database.syncRuns,
      )..where((tbl) => tbl.id.equals(syncRunId))).write(
        SyncRunsCompanion(
          phase: const Value('extractingMetadata'),
          filesDiscovered: Value(totalDiscovered),
          filesProcessed: Value(processedCount),
          progressPercent: Value(initialPercent),
          lastCheckpointAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // 5. Process files that need new or updated metadata
      for (final driveFile in toProcess) {
        if (cancellationToken.isCancelled) {
          AppLogger.info(
            LogCategory.sync,
            'Sync stopping requested; persisting checkpoint and stopping loop gracefully',
          );
          await _persistSessionStopped(
            syncRunId: syncRunId,
            filesDiscovered: totalDiscovered,
            filesProcessed: processedCount,
            filesAdded: addedCount,
            filesUpdated: updatedCount,
            errorsCount: errorsCount,
            progressPercent: totalDiscovered > 0
                ? (processedCount / totalDiscovered)
                : 1.0,
          );
          _updateProgress(
            _currentProgress.copyWith(
              phase: SyncPhase.stopped,
              isResumable: true,
              currentFile: null,
            ),
          );
          onProgress?.call(_currentProgress);
          return const Result.success(null);
        }

        _updateProgress(
          _currentProgress.copyWith(
            currentFile: driveFile.name,
            filesProcessed: processedCount,
            progressPercent: totalDiscovered > 0
                ? (processedCount / totalDiscovered)
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

            final isExisting = existingMap.containsKey(driveFile.id);
            final currentAdded = isExisting ? addedCount : addedCount + 1;
            final currentUpdated = isExisting ? updatedCount + 1 : updatedCount;
            final currentProcessed = processedCount + 1;
            final currentProgressPercent = totalDiscovered > 0
                ? (currentProcessed / totalDiscovered)
                : 1.0;

            // Atomically commit track, lyrics, and sync checkpoint
            await _database.transaction(() async {
              await _upsertTrackAndRelationsInTx(
                sourceId: sourceId,
                driveFile: driveFile,
                meta: normalized,
                rawJson: jsonEncode(parsedMeta.rawMetadata ?? {}),
              );

              final trackId = 'track_${driveFile.id}';
              await _processLyricsForTrack(
                trackId: trackId,
                driveFile: driveFile,
                parsedMeta: parsedMeta,
                lrcMap: lrcMap,
              );

              await (_database.update(
                _database.syncRuns,
              )..where((tbl) => tbl.id.equals(syncRunId))).write(
                SyncRunsCompanion(
                  filesProcessed: Value(currentProcessed),
                  filesAdded: Value(currentAdded),
                  filesUpdated: Value(currentUpdated),
                  errorsCount: Value(errorsCount),
                  progressPercent: Value(currentProgressPercent),
                  currentFile: Value(driveFile.name),
                  lastCheckpointAt: Value(DateTime.now()),
                  updatedAt: Value(DateTime.now()),
                ),
              );
            });

            processedCount = currentProcessed;
            if (isExisting) {
              updatedCount = currentUpdated;
            } else {
              addedCount = currentAdded;
            }

            AppLogger.debug(
              LogCategory.sync,
              'Processed & checkpointed track: ${driveFile.name} ($processedCount/$totalDiscovered)',
            );
          } else {
            errorsCount++;
            processedCount++;
            await _recordSyncErrorAndCheckpoint(
              syncRunId: syncRunId,
              file: driveFile,
              message: downloadRes.failureOrNull?.message ?? 'Download failed',
              filesDiscovered: totalDiscovered,
              filesProcessed: processedCount,
              errorsCount: errorsCount,
            );
          }
        } catch (e, st) {
          errorsCount++;
          processedCount++;
          AppLogger.warning(
            LogCategory.sync,
            'Failed processing metadata for ${driveFile.name}',
            e,
            st,
          );
          await _recordSyncErrorAndCheckpoint(
            syncRunId: syncRunId,
            file: driveFile,
            message: e.toString(),
            filesDiscovered: totalDiscovered,
            filesProcessed: processedCount,
            errorsCount: errorsCount,
          );
        } finally {
          if (tempFile != null && await tempFile.exists()) {
            try {
              await tempFile.delete();
            } catch (_) {}
          }
        }

        _updateProgress(
          _currentProgress.copyWith(
            filesProcessed: processedCount,
            filesAdded: addedCount,
            filesUpdated: updatedCount,
            errorsCount: errorsCount,
            progressPercent: totalDiscovered > 0
                ? (processedCount / totalDiscovered)
                : 1.0,
          ),
        );
        onProgress?.call(_currentProgress);
      }

      if (cancellationToken.isCancelled) {
        await _persistSessionStopped(
          syncRunId: syncRunId,
          filesDiscovered: totalDiscovered,
          filesProcessed: processedCount,
          filesAdded: addedCount,
          filesUpdated: updatedCount,
          errorsCount: errorsCount,
          progressPercent: totalDiscovered > 0
              ? (processedCount / totalDiscovered)
              : 1.0,
        );
        _updateProgress(
          _currentProgress.copyWith(
            phase: SyncPhase.stopped,
            isResumable: true,
            currentFile: null,
          ),
        );
        onProgress?.call(_currentProgress);
        return const Result.success(null);
      }

      // 6. Handle remote deletions
      _updateProgress(
        _currentProgress.copyWith(
          phase: SyncPhase.updatingDatabase,
          currentFile: null,
        ),
      );
      onProgress?.call(_currentProgress);

      final removedDriveIds = existingMap.keys
          .where((id) => !driveFileMap.containsKey(id))
          .toList();

      if (removedDriveIds.isNotEmpty) {
        AppLogger.info(
          LogCategory.sync,
          'Reconciling removed tracks: ${removedDriveIds.length} tracks deleted on Google Drive',
        );
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

      // 7. Recompute library aggregates
      await _recomputeLibraryAggregates();

      // 8. Finalize sync run record
      await (_database.update(
        _database.syncRuns,
      )..where((tbl) => tbl.id.equals(syncRunId))).write(
        SyncRunsCompanion(
          completedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
          lastCheckpointAt: Value(DateTime.now()),
          status: const Value('completed'),
          phase: const Value('complete'),
          filesDiscovered: Value(totalDiscovered),
          filesProcessed: Value(totalDiscovered),
          filesAdded: Value(addedCount),
          filesUpdated: Value(updatedCount),
          filesRemoved: Value(removedDriveIds.length),
          errorsCount: Value(errorsCount),
          progressPercent: const Value(1.0),
          currentFile: const Value(null),
        ),
      );

      await (_database.update(_database.musicSources)
            ..where((tbl) => tbl.id.equals(sourceId)))
          .write(MusicSourcesCompanion(lastSyncedAt: Value(DateTime.now())));

      _updateProgress(
        _currentProgress.copyWith(
          phase: SyncPhase.complete,
          filesDiscovered: totalDiscovered,
          filesProcessed: totalDiscovered,
          filesAdded: addedCount,
          filesUpdated: updatedCount,
          filesRemoved: removedDriveIds.length,
          errorsCount: errorsCount,
          progressPercent: 1.0,
          currentFile: null,
          isResumable: false,
        ),
      );
      onProgress?.call(_currentProgress);

      AppLogger.info(
        LogCategory.sync,
        'Sync completed successfully! Discovered: $totalDiscovered, Unchanged: ${unchangedComplete.length}, Added: $addedCount, Updated: $updatedCount, Removed: ${removedDriveIds.length}, Errors: $errorsCount',
      );

      return const Result.success(null);
    } catch (e, st) {
      AppLogger.error(LogCategory.sync, 'Fatal error during sync', e, st);
      await _persistSessionFailed(syncRunId: syncRunId, error: e.toString());
      _updateProgress(
        _currentProgress.copyWith(
          phase: SyncPhase.failed,
          errorMessage: e.toString(),
          isResumable: true,
        ),
      );
      onProgress?.call(_currentProgress);

      return Result.failure(DatabaseFailure('Sync failed', cause: e));
    } finally {
      _isSyncRunning = false;
      _currentCancellationToken = null;
    }
  }

  Future<void> _persistSessionStopped({
    required String syncRunId,
    int? filesDiscovered,
    int? filesProcessed,
    int? filesAdded,
    int? filesUpdated,
    int? errorsCount,
    double? progressPercent,
  }) async {
    try {
      await (_database.update(
        _database.syncRuns,
      )..where((tbl) => tbl.id.equals(syncRunId))).write(
        SyncRunsCompanion(
          status: const Value('stopped'),
          phase: const Value('stopped'),
          updatedAt: Value(DateTime.now()),
          lastCheckpointAt: Value(DateTime.now()),
          currentFile: const Value(null),
          filesDiscovered: filesDiscovered != null
              ? Value(filesDiscovered)
              : const Value.absent(),
          filesProcessed: filesProcessed != null
              ? Value(filesProcessed)
              : const Value.absent(),
          filesAdded: filesAdded != null
              ? Value(filesAdded)
              : const Value.absent(),
          filesUpdated: filesUpdated != null
              ? Value(filesUpdated)
              : const Value.absent(),
          errorsCount: errorsCount != null
              ? Value(errorsCount)
              : const Value.absent(),
          progressPercent: progressPercent != null
              ? Value(progressPercent)
              : const Value.absent(),
        ),
      );
    } catch (_) {}
  }

  Future<void> _persistSessionFailed({
    required String syncRunId,
    required String error,
  }) async {
    try {
      await (_database.update(
        _database.syncRuns,
      )..where((tbl) => tbl.id.equals(syncRunId))).write(
        SyncRunsCompanion(
          status: const Value('failed'),
          phase: const Value('failed'),
          errorMessage: Value(error),
          updatedAt: Value(DateTime.now()),
          lastCheckpointAt: Value(DateTime.now()),
        ),
      );
    } catch (_) {}
  }

  Future<void> _recordSyncErrorAndCheckpoint({
    required String syncRunId,
    required DriveFileItem file,
    required String message,
    required int filesDiscovered,
    required int filesProcessed,
    required int errorsCount,
  }) async {
    try {
      await _database.transaction(() async {
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

        await (_database.update(
          _database.syncRuns,
        )..where((tbl) => tbl.id.equals(syncRunId))).write(
          SyncRunsCompanion(
            filesProcessed: Value(filesProcessed),
            errorsCount: Value(errorsCount),
            progressPercent: Value(
              filesDiscovered > 0 ? (filesProcessed / filesDiscovered) : 1.0,
            ),
            lastCheckpointAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );
      });
    } catch (_) {}
  }

  Future<void> _upsertTrackAndRelationsInTx({
    required String sourceId,
    required DriveFileItem driveFile,
    required NormalizedMetadata meta,
    required String rawJson,
  }) async {
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
