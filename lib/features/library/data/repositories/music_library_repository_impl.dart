import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../../../../core/constants/app_constants.dart';
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
import '../../../metadata/data/datasources/artist_artwork_downloader.dart';
import '../../../metadata/data/repositories/metadata_extractor_impl.dart';
import '../../../metadata/domain/entities/parsed_audio_metadata.dart';
import '../../../metadata/domain/services/folder_artwork_resolver.dart';
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
  final ArtistArtworkDownloader? _artistArtworkDownloader;

  final StreamController<SyncProgress> _syncProgressController =
      StreamController<SyncProgress>.broadcast();

  SyncProgress _currentProgress = const SyncProgress();
  bool _isSyncRunning = false;
  SyncCancellationToken? _currentCancellationToken;
  Completer<void>? _activeSyncCompleter;
  int _syncSequenceNumber = 0;

  MusicLibraryRepositoryImpl({
    required AppDatabase database,
    required GoogleDriveRepository driveRepository,
    MetadataExtractor? metadataExtractor,
    LyricsRepository? lyricsRepository,
    AppFileSystem? fileSystem,
    ArtistArtworkDownloader? artistArtworkDownloader,
  }) : _database = database,
       _driveRepository = driveRepository,
       _metadataExtractor = metadataExtractor ?? MetadataExtractor(),
       _lyricsRepository =
           lyricsRepository ?? LyricsRepositoryImpl(database: database),
       _fileSystem = fileSystem ?? AppFileSystem.instance,
       _artistArtworkDownloader =
           artistArtworkDownloader ??
           ArtistArtworkDownloader(
             fileSystem: fileSystem ?? AppFileSystem.instance,
             database: database,
           ) {
    unawaited(_hydrateInitialState());
  }

  Future<void> _hydrateInitialState() async {
    try {
      final latest =
          await (_database.select(_database.syncRuns)
                ..orderBy([
                  (tbl) => OrderingTerm.desc(tbl.startedAt),
                  (tbl) => OrderingTerm.desc(tbl.id),
                ])
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
                ..orderBy([
                  (tbl) => OrderingTerm.desc(tbl.startedAt),
                  (tbl) => OrderingTerm.desc(tbl.id),
                ])
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
                ..orderBy([
                  (tbl) => OrderingTerm.desc(tbl.startedAt),
                  (tbl) => OrderingTerm.desc(tbl.id),
                ])
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
    String? targetRunId = _currentProgress.syncRunId;

    if (folderId == null || targetRunId == null) {
      final latest =
          await (_database.select(_database.syncRuns)
                ..orderBy([
                  (tbl) => OrderingTerm.desc(tbl.startedAt),
                  (tbl) => OrderingTerm.desc(tbl.id),
                ])
                ..limit(1))
              .getSingleOrNull();
      if (latest != null) {
        folderId ??= latest.rootFolderId;
        folderName ??= latest.rootFolderName;
        targetRunId ??= latest.id;
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
      requestedSyncRunId: targetRunId,
    );
  }

  @override
  Future<Result<void, AppFailure>> syncFromSavedFolder({
    bool forceSync = false,
  }) async {
    if (_isSyncRunning) {
      return const Result.success(null);
    }

    // Try in-memory progress first
    String? folderId = _currentProgress.rootFolderId;
    String? folderName = _currentProgress.rootFolderName;

    // Fall back to MusicSources table
    if (folderId == null) {
      final source = await (_database.select(
        _database.musicSources,
      )..where((tbl) => tbl.id.equals('source_gdrive'))).getSingleOrNull();
      if (source != null && source.rootFolderId != null) {
        folderId = source.rootFolderId;
        folderName = source.rootFolderName;
      }
    }

    // Fall back to latest SyncRun
    if (folderId == null) {
      final latest =
          await (_database.select(_database.syncRuns)
                ..orderBy([
                  (tbl) => OrderingTerm.desc(tbl.startedAt),
                  (tbl) => OrderingTerm.desc(tbl.id),
                ])
                ..limit(1))
              .getSingleOrNull();
      if (latest != null) {
        folderId = latest.rootFolderId;
        folderName = latest.rootFolderName;
      }
    }

    if (folderId == null) {
      return const Result.failure(
        DriveApiFailure(
          'No music folder configured. Please select a folder first.',
        ),
      );
    }

    return syncLibrary(
      rootFolderId: folderId,
      rootFolderName: folderName ?? 'Music',
      forceSync: forceSync,
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
      artworkPath: (row.artworkPath != null &&
              row.artworkPath!.isNotEmpty &&
              File(row.artworkPath!).existsSync())
          ? row.artworkPath
          : (_resolveArtworkPath(row.albumName, row.albumArtist) ??
              _resolveArtworkPath(row.albumName, row.artistName)),
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
      artworkPath: _resolveArtistArtworkPath(row),
      trackCount: row.trackCount,
      albumCount: row.albumCount,
    );
  }

  String? _resolveArtistArtworkPath(ArtistRow row) {
    if (row.artworkPath != null && row.artworkPath!.isNotEmpty) {
      final file = File(row.artworkPath!);
      if (file.existsSync()) return row.artworkPath;
    }
    final cachedFile = _fileSystem.getArtworkCacheFile(
      'artist_${row.normalizedName}',
    );
    if (cachedFile.existsSync()) {
      return cachedFile.path;
    }
    return null;
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
      var artistEntity = _mapDbArtistToEntity(artistData);
      if (artistEntity.artworkPath == null && albums.isNotEmpty) {
        final albumArt = albums
            .map(
              (a) =>
                  a.artworkPath ?? _resolveArtworkPath(a.title, a.artistName),
            )
            .where((p) => p != null && p.isNotEmpty && File(p).existsSync())
            .firstOrNull;
        if (albumArt != null) {
          artistEntity = artistEntity.copyWith(artworkPath: albumArt);
        }
      }
      return ArtistWithAlbums(
        artist: artistEntity,
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

    // Metadata completeness — only checks core metadata fields, not file size.
    // File size mismatch is a change detection signal, not a completeness indicator.
    final isMetadataComplete =
        local.title.trim().isNotEmpty &&
        local.normalizedTitle.trim().isNotEmpty &&
        local.format != null &&
        local.format!.isNotEmpty;

    if (!isMetadataComplete) {
      return TrackSyncAction.repairIncomplete;
    }

    // Change detection via modified timestamp (second precision to prevent sub-second Drift/SQLite truncation false-positives)
    if (remote.modifiedTime != null && local.driveModifiedAt != null) {
      final remoteSec =
          remote.modifiedTime!.toUtc().millisecondsSinceEpoch ~/ 1000;
      final localSec =
          local.driveModifiedAt!.toUtc().millisecondsSinceEpoch ~/ 1000;
      if (remoteSec > localSec) {
        return TrackSyncAction.updateModified;
      }
    }

    // Change detection via checksum
    if (remote.md5Checksum != null && local.driveMd5Checksum != null) {
      if (remote.md5Checksum != local.driveMd5Checksum) {
        return TrackSyncAction.updateModified;
      }
    }

    // Change detection via file size (only if local has a stored size)
    if (local.fileSize > 0 && remote.size != local.fileSize) {
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
    bool forceSync = false,
    String? requestedSyncRunId,
  }) async {
    final int mySeq = ++_syncSequenceNumber;

    while (_isSyncRunning) {
      AppLogger.info(
        LogCategory.sync,
        'Active sync in progress. Requesting graceful stop to start sync for $rootFolderName (seq: $mySeq)...',
      );
      _currentCancellationToken?.cancel();
      _updateProgress(_currentProgress.copyWith(phase: SyncPhase.stopping));

      if (_activeSyncCompleter != null) {
        try {
          await _activeSyncCompleter!.future;
        } catch (_) {}
      }
    }

    if (mySeq != _syncSequenceNumber) {
      AppLogger.info(
        LogCategory.sync,
        'Sync request (seq: $mySeq, folder: $rootFolderName) was superseded by newer request (seq: $_syncSequenceNumber); aborting.',
      );
      return const Result.success(null);
    }

    _isSyncRunning = true;
    _activeSyncCompleter = Completer<void>();
    final cancellationToken = SyncCancellationToken();
    _currentCancellationToken = cancellationToken;

    String? targetSyncRunId = requestedSyncRunId;
    if (targetSyncRunId == null && isResume && _currentProgress.syncRunId != null) {
      targetSyncRunId = _currentProgress.syncRunId;
    }
    if (targetSyncRunId == null && isResume) {
      final latest = await (_database.select(_database.syncRuns)
            ..where((tbl) => tbl.rootFolderId.equals(rootFolderId))
            ..orderBy([
              (tbl) => OrderingTerm.desc(tbl.startedAt),
              (tbl) => OrderingTerm.desc(tbl.id),
            ])
            ..limit(1))
          .getSingleOrNull();
      if (latest != null) {
        targetSyncRunId = latest.id;
      }
    }
    final syncRunId =
        targetSyncRunId ?? 'sync_${DateTime.now().millisecondsSinceEpoch}';
    const sourceId = 'source_gdrive';

    AppLogger.info(
      LogCategory.sync,
      '${isResume ? "Resuming" : "Starting"} library sync (Run ID: $syncRunId, Folder: $rootFolderName [$rootFolderId])',
    );

    try {
      // If fresh sync, clean up obsolete discovered files from previous sync runs
      if (!isResume) {
        await (_database.delete(
          _database.discoveredFiles,
        )..where((tbl) => tbl.syncRunId.equals(syncRunId).not())).go();
      }

      // Fetch existing sync run record if resuming
      SyncRunRow? existingRun;
      if (isResume) {
        existingRun = await (_database.select(
          _database.syncRuns,
        )..where((tbl) => tbl.id.equals(syncRunId))).getSingleOrNull();
      }

      // 1. Record / update sync run in database
      await _database
          .into(_database.syncRuns)
          .insertOnConflictUpdate(
            SyncRunsCompanion(
              id: Value(syncRunId),
              sourceId: const Value(sourceId),
              rootFolderId: Value(rootFolderId),
              rootFolderName: Value(rootFolderName),
              startedAt: Value(existingRun?.startedAt ?? DateTime.now()),
              updatedAt: Value(DateTime.now()),
              lastCheckpointAt: Value(DateTime.now()),
              status: const Value('running'),
              phase: const Value('scanning'),
              filesDiscovered: Value(
                isResume
                    ? (existingRun?.filesDiscovered ??
                        _currentProgress.filesDiscovered)
                    : 0,
              ),
              filesProcessed: Value(
                isResume
                    ? (existingRun?.filesProcessed ??
                        _currentProgress.filesProcessed)
                    : 0,
              ),
              filesAdded: Value(
                isResume
                    ? (existingRun?.filesAdded ?? _currentProgress.filesAdded)
                    : 0,
              ),
              filesUpdated: Value(
                isResume
                    ? (existingRun?.filesUpdated ??
                        _currentProgress.filesUpdated)
                    : 0,
              ),
              filesRemoved: Value(
                isResume
                    ? (existingRun?.filesRemoved ??
                        _currentProgress.filesRemoved)
                    : 0,
              ),
              errorsCount: Value(
                isResume
                    ? (existingRun?.errorsCount ?? _currentProgress.errorsCount)
                    : 0,
              ),
              progressPercent: Value(
                isResume
                    ? (existingRun?.progressPercent ??
                        _currentProgress.progressPercent)
                    : 0.0,
              ),
              discoveryCompleted: Value(
                isResume ? (existingRun?.discoveryCompleted ?? false) : false,
              ),
              pendingFoldersJson: Value(
                isResume ? existingRun?.pendingFoldersJson : null,
              ),
              visitedFoldersJson: Value(
                isResume ? existingRun?.visitedFoldersJson : null,
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

      // 2. Discover audio files recursively from Drive or restore from DB
      final List<DriveFileItem> allDriveFiles = [];
      final Set<String> alreadyProcessedDriveIds = {};
      bool discoveryAlreadyComplete = false;
      List<String>? initialPendingFolders;
      Set<String>? initialVisitedFolders;

      if (isResume && existingRun != null) {
        if (existingRun.discoveryCompleted) {
          discoveryAlreadyComplete = true;
          final rows = await (_database.select(
            _database.discoveredFiles,
          )..where((tbl) => tbl.syncRunId.equals(syncRunId))).get();

          for (final r in rows) {
            allDriveFiles.add(
              DriveFileItem(
                id: r.driveFileId,
                name: r.name,
                mimeType: r.mimeType,
                size: r.size,
                modifiedTime: r.modifiedTime,
                md5Checksum: r.md5Checksum,
                parentFolderId: r.parentFolderId,
                isLrc: r.isLrc,
                isImage: AppImageConstants.isImageFile(r.name, r.mimeType),
              ),
            );
            if (r.isProcessed) {
              alreadyProcessedDriveIds.add(r.driveFileId);
            }
          }

          AppLogger.info(
            LogCategory.sync,
            'Resuming sync: Discovery already complete ($syncRunId). Restored ${allDriveFiles.length} files from DB (${alreadyProcessedDriveIds.length} already processed); skipping Drive scan.',
          );
        } else {
          if (existingRun.pendingFoldersJson != null) {
            try {
              final list =
                  jsonDecode(existingRun.pendingFoldersJson!) as List<dynamic>;
              initialPendingFolders = list.map((e) => e.toString()).toList();
            } catch (_) {}
          }
          if (existingRun.visitedFoldersJson != null) {
            try {
              final list =
                  jsonDecode(existingRun.visitedFoldersJson!) as List<dynamic>;
              initialVisitedFolders = list.map((e) => e.toString()).toSet();
            } catch (_) {}
          }

          final rows = await (_database.select(
            _database.discoveredFiles,
          )..where((tbl) => tbl.syncRunId.equals(syncRunId))).get();

          for (final r in rows) {
            allDriveFiles.add(
              DriveFileItem(
                id: r.driveFileId,
                name: r.name,
                mimeType: r.mimeType,
                size: r.size,
                modifiedTime: r.modifiedTime,
                md5Checksum: r.md5Checksum,
                parentFolderId: r.parentFolderId,
                isLrc: r.isLrc,
                isImage: AppImageConstants.isImageFile(r.name, r.mimeType),
              ),
            );
            if (r.isProcessed) {
              alreadyProcessedDriveIds.add(r.driveFileId);
            }
          }
        }
      }

      final Map<String, String?> folderParentMap = {};

      if (discoveryAlreadyComplete) {
        final savedFolders = await (_database.select(_database.driveFolders)
              ..where((tbl) => tbl.sourceId.equals(sourceId)))
            .get();
        for (final df in savedFolders) {
          folderParentMap[df.folderId] = df.parentFolderId;
        }
      }

      if (!discoveryAlreadyComplete) {
        _updateProgress(
          _currentProgress.copyWith(
            syncRunId: syncRunId,
            phase: SyncPhase.scanning,
            rootFolderId: rootFolderId,
            rootFolderName: rootFolderName,
            filesDiscovered: allDriveFiles
                .where((f) => !f.isLrc && !f.isImage)
                .length,
            filesProcessed: isResume ? _currentProgress.filesProcessed : 0,
            filesAdded: isResume ? _currentProgress.filesAdded : 0,
            filesUpdated: isResume ? _currentProgress.filesUpdated : 0,
            filesRemoved: isResume ? _currentProgress.filesRemoved : 0,
            errorsCount: isResume ? _currentProgress.errorsCount : 0,
            progressPercent: isResume ? _currentProgress.progressPercent : 0.0,
            errorMessage: null,
            isResumable: false,
          ),
        );
        onProgress?.call(_currentProgress);

        List<String> lastPendingFolders =
            initialPendingFolders ?? [rootFolderId];
        Set<String> lastVisitedFolders = initialVisitedFolders ?? {};

        final scanResult = await _driveRepository.listAudioFilesRecursively(
          rootFolderId,
          initialFolderQueue: initialPendingFolders,
          initialVisitedFolders: initialVisitedFolders,
          folderParentMap: folderParentMap,
          onProgress: (count) {
            final totalDiscovered =
                allDriveFiles.where((f) => !f.isLrc && !f.isImage).length +
                count;
            _updateProgress(
              _currentProgress.copyWith(filesDiscovered: totalDiscovered),
            );
            onProgress?.call(_currentProgress);
          },
          onFileDiscovered: (file) async {
            if (!allDriveFiles.any((f) => f.id == file.id)) {
              allDriveFiles.add(file);
            }
            await _database
                .into(_database.discoveredFiles)
                .insertOnConflictUpdate(
                  DiscoveredFilesCompanion(
                    id: Value('${syncRunId}_${file.id}'),
                    syncRunId: Value(syncRunId),
                    driveFileId: Value(file.id),
                    name: Value(file.name),
                    mimeType: Value(file.mimeType),
                    size: Value(file.size),
                    modifiedTime: Value(file.modifiedTime ?? DateTime.now()),
                    md5Checksum: Value(file.md5Checksum),
                    parentFolderId: Value(file.parentFolderId),
                    isLrc: Value(file.isLrc),
                    isProcessed: const Value(false),
                  ),
                );
          },
          onFolderStateChanged: (pending, visited) {
            lastPendingFolders = List<String>.from(pending);
            lastVisitedFolders = Set<String>.from(visited);
          },
          isCancelled: () => cancellationToken.isCancelled,
        );

        if (cancellationToken.isCancelled) {
          await _persistSessionStopped(
            syncRunId: syncRunId,
            filesDiscovered: _currentProgress.filesDiscovered,
            filesProcessed: _currentProgress.filesProcessed,
            discoveryCompleted: false,
            pendingFolders: lastPendingFolders,
            visitedFolders: lastVisitedFolders,
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

        // Discovery completed! Mark discoveryCompleted = true
        await (_database.update(
          _database.syncRuns,
        )..where((tbl) => tbl.id.equals(syncRunId))).write(
          SyncRunsCompanion(
            discoveryCompleted: const Value(true),
            pendingFoldersJson: const Value(null),
            visitedFoldersJson: const Value(null),
            filesDiscovered: Value(
              allDriveFiles.where((f) => !f.isLrc && !f.isImage).length,
            ),
            updatedAt: Value(DateTime.now()),
            lastCheckpointAt: Value(DateTime.now()),
          ),
        );
      }

      final driveAudioFiles = allDriveFiles
          .where((f) => !f.isLrc && !f.isImage)
          .toList();
      final driveLrcFiles = allDriveFiles.where((f) => f.isLrc).toList();
      final driveImageFiles = allDriveFiles.where((f) => f.isImage).toList();

      // Build map of sidecar LRC files keyed by folder and base filename
      final Map<String, DriveFileItem> lrcMap = {};
      for (final lrc in driveLrcFiles) {
        final folder = lrc.parentFolderId ?? '';
        final base = _cleanBaseName(lrc.name);
        lrcMap['${folder}_$base'] = lrc;
      }

      // Build map of folder image files keyed by parentFolderId
      final Map<String, List<DriveFileItem>> folderImagesMap = {};
      for (final img in driveImageFiles) {
        final folder = img.parentFolderId ?? '';
        folderImagesMap.putIfAbsent(folder, () => []).add(img);
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
        if (forceSync) {
          toProcess.add(df);
          continue;
        }

        // Check if this file was already processed and added in this sync run
        if (isResume && alreadyProcessedDriveIds.contains(df.id)) {
          unchangedComplete.add(df);
          continue;
        }

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

      // Mark all unchangedComplete files as processed in DiscoveredFiles
      if (unchangedComplete.isNotEmpty) {
        final unchangedRowIds = unchangedComplete
            .map((f) => '${syncRunId}_${f.id}')
            .toList();
        await (_database.update(_database.discoveredFiles)
              ..where((tbl) => tbl.id.isIn(unchangedRowIds)))
            .write(
              DiscoveredFilesCompanion(
                isProcessed: const Value(true),
                processStatus: const Value('unchanged'),
                processedAt: Value(DateTime.now()),
              ),
            );
      }

      final totalDiscovered = driveAudioFiles.length;
      int processedCount = unchangedComplete.length;
      int addedCount = isResume
          ? (existingRun?.filesAdded ?? _currentProgress.filesAdded)
          : 0;
      int updatedCount = isResume
          ? (existingRun?.filesUpdated ?? _currentProgress.filesUpdated)
          : 0;
      int errorsCount = isResume
          ? (existingRun?.errorsCount ?? _currentProgress.errorsCount)
          : 0;

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
            discoveryCompleted: true,
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

            // Ensure album artwork is downloaded (from folder if embedded is missing)
            final resolvedArtworkPath = await _ensureAlbumArtwork(
              meta: normalized,
              driveFile: driveFile,
              folderImagesMap: folderImagesMap,
              folderParentMap: folderParentMap,
            );

            // Atomically commit track, lyrics, and sync checkpoint
            await _database.transaction(() async {
              await _upsertTrackAndRelationsInTx(
                sourceId: sourceId,
                driveFile: driveFile,
                meta: normalized,
                rawJson: jsonEncode(parsedMeta.rawMetadata ?? {}),
                resolvedArtworkPath: resolvedArtworkPath,
              );

              final trackId = 'track_${driveFile.id}';
              await _processLyricsForTrack(
                trackId: trackId,
                driveFile: driveFile,
                parsedMeta: parsedMeta,
                lrcMap: lrcMap,
              );

              await (_database.update(_database.discoveredFiles)
                    ..where((tbl) =>
                        tbl.id.equals('${syncRunId}_${driveFile.id}')))
                  .write(
                    DiscoveredFilesCompanion(
                      isProcessed: const Value(true),
                      processStatus: Value(isExisting ? 'updated' : 'added'),
                      processedAt: Value(DateTime.now()),
                    ),
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
            final err = downloadRes.failureOrNull!;
            AppLogger.warning(
              LogCategory.sync,
              'Failed to download audio for metadata extraction: ${driveFile.name}',
              err,
            );
            await _recordSyncErrorAndCheckpoint(
              syncRunId: syncRunId,
              file: driveFile,
              message: err.message,
              filesDiscovered: totalDiscovered,
              filesProcessed: ++processedCount,
              errorsCount: errorsCount,
            );
          }
        } catch (e, st) {
          errorsCount++;
          AppLogger.warning(
            LogCategory.sync,
            'Error processing audio metadata: ${driveFile.name}',
            e,
            st,
          );
          await _recordSyncErrorAndCheckpoint(
            syncRunId: syncRunId,
            file: driveFile,
            message: e.toString(),
            filesDiscovered: totalDiscovered,
            filesProcessed: ++processedCount,
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
          discoveryCompleted: true,
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

      // 7. Reconcile duplicate albums and recompute library aggregates
      await _database.reconcileDuplicateAlbums();
      await _recomputeLibraryAggregates(
        folderImagesMap: folderImagesMap,
        folderParentMap: folderParentMap,
        driveFileMap: driveFileMap,
      );

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

      // Trigger background download of missing artist artwork
      unawaited(_triggerArtistArtworkDownload());

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
      _activeSyncCompleter?.complete();
      _activeSyncCompleter = null;
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
    bool? discoveryCompleted,
    List<String>? pendingFolders,
    Set<String>? visitedFolders,
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
          discoveryCompleted: discoveryCompleted != null
              ? Value(discoveryCompleted)
              : const Value.absent(),
          pendingFoldersJson: pendingFolders != null
              ? Value(jsonEncode(pendingFolders))
              : const Value.absent(),
          visitedFoldersJson: visitedFolders != null
              ? Value(jsonEncode(visitedFolders.toList()))
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

        await (_database.update(_database.discoveredFiles)
              ..where((tbl) => tbl.id.equals('${syncRunId}_${file.id}')))
            .write(
              const DiscoveredFilesCompanion(
                isProcessed: Value(false),
                processStatus: Value('failed'),
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
    String? resolvedArtworkPath,
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
    final effectiveAlbumArtist =
        (meta.albumArtist != null && meta.albumArtist!.trim().isNotEmpty)
        ? meta.albumArtist!
        : meta.artist;

    final canonicalAlbumKey = MetadataNormalizationService.computeAlbumKey(
      albumName: meta.album,
      albumArtist: meta.albumArtist,
      trackArtist: meta.artist,
    );

    final artworkKey = MetadataNormalizationService.computeArtworkKey(
      meta.album,
      effectiveAlbumArtist,
    );
    final artworkFile = _fileSystem.getArtworkCacheFile(artworkKey);

    var existingAlbum =
        await (_database.select(_database.albums)
              ..where((tbl) => tbl.albumKey.equals(canonicalAlbumKey)))
            .getSingleOrNull();

    // If not found and meta.albumArtist was not explicitly tagged:
    // Check if an existing album with the same normalizedTitle already exists
    // whose artist is compatible with meta.artist (e.g. prefix / substring match)
    if (existingAlbum == null && meta.albumArtist == null) {
      final titleCandidates =
          await (_database.select(_database.albums)..where(
                (tbl) => tbl.normalizedTitle.equals(meta.normalizedAlbum),
              ))
              .get();
      for (final candidate in titleCandidates) {
        final candArtist = (candidate.artistName ?? '').toLowerCase().trim();
        final trackArtist = meta.artist.toLowerCase().trim();
        if (candArtist.isNotEmpty &&
            (candArtist == trackArtist ||
                trackArtist.startsWith(candArtist) ||
                candArtist.startsWith(trackArtist) ||
                trackArtist.contains(candArtist))) {
          existingAlbum = candidate;
          break;
        }
      }
    }

    final existingArt = existingAlbum?.artworkPath;
    final effectiveArtwork = resolvedArtworkPath ??
        (artworkFile.existsSync()
            ? artworkFile.path
            : (existingArt != null &&
                    existingArt.isNotEmpty &&
                    File(existingArt).existsSync()
                ? existingArt
                : null));

    final String albumId;
    if (existingAlbum != null) {
      albumId = existingAlbum.id;

      // If the incoming track has an explicit albumArtist that the existing album lacks,
      // upgrade the existing album's artistName, artistId, and albumKey.
      if (meta.albumArtist != null &&
          meta.albumArtist!.trim().isNotEmpty &&
          existingAlbum.artistName != meta.albumArtist) {
        final albumArtistId = 'artist_${canonicalAlbumKey.split("::").last}';
        await _database
            .into(_database.artists)
            .insertOnConflictUpdate(
              ArtistsCompanion(
                id: Value(albumArtistId),
                name: Value(meta.albumArtist!),
                normalizedName: Value(canonicalAlbumKey.split("::").last),
              ),
            );
        await (_database.update(
          _database.albums,
        )..where((tbl) => tbl.id.equals(albumId))).write(
          AlbumsCompanion(
            artistId: Value(albumArtistId),
            artistName: Value(meta.albumArtist!),
            albumKey: Value(canonicalAlbumKey),
          ),
        );
      }

      if (existingAlbum.artworkPath == null && effectiveArtwork != null) {
        await (_database.update(_database.albums)
              ..where((tbl) => tbl.id.equals(albumId)))
            .write(AlbumsCompanion(artworkPath: Value(effectiveArtwork)));
      }
    } else {
      albumId = 'album_$canonicalAlbumKey';

      // Ensure the album artist exists in Artists table
      final albumArtistId = 'artist_${canonicalAlbumKey.split("::").last}';
      if (albumArtistId != artistId) {
        await _database
            .into(_database.artists)
            .insertOnConflictUpdate(
              ArtistsCompanion(
                id: Value(albumArtistId),
                name: Value(effectiveAlbumArtist),
                normalizedName: Value(canonicalAlbumKey.split("::").last),
              ),
            );
      }

      await _database
          .into(_database.albums)
          .insert(
            AlbumsCompanion(
              id: Value(albumId),
              albumKey: Value(canonicalAlbumKey),
              title: Value(meta.album),
              normalizedTitle: Value(meta.normalizedAlbum),
              artistId: Value(albumArtistId),
              artistName: Value(effectiveAlbumArtist),
              year: Value(meta.year),
              artworkPath: effectiveArtwork != null
                  ? Value(effectiveArtwork)
                  : const Value(null),
            ),
          );
    }

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
            albumArtist: Value(meta.albumArtist ?? effectiveAlbumArtist),
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
            artworkPath: effectiveArtwork != null
                ? Value(effectiveArtwork)
                : const Value(null),
            rawMetadataJson: Value(rawJson),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<String?> _ensureAlbumArtwork({
    required NormalizedMetadata meta,
    required DriveFileItem driveFile,
    required Map<String, List<DriveFileItem>> folderImagesMap,
    required Map<String, String?> folderParentMap,
  }) async {
    try {
      final effectiveAlbumArtist =
          (meta.albumArtist != null && meta.albumArtist!.trim().isNotEmpty)
          ? meta.albumArtist!
          : meta.artist;
      final artworkKey = MetadataNormalizationService.computeArtworkKey(
        meta.album,
        effectiveAlbumArtist,
      );
      final artworkFile = _fileSystem.getArtworkCacheFile(artworkKey);
      if (artworkFile.existsSync()) return artworkFile.path;

      final candidate = FolderArtworkResolver.resolveCandidate(
        folderId: driveFile.parentFolderId,
        folderImages: folderImagesMap,
        folderParentMap: folderParentMap,
      );

      if (candidate != null) {
        final dlRes = await _driveRepository.downloadFile(
          fileId: candidate.id,
          destinationFile: artworkFile,
        );
        if (dlRes.isSuccess && artworkFile.existsSync()) {
          AppLogger.info(
            LogCategory.metadata,
            'Downloaded folder artwork for "${meta.album}" from "${candidate.name}" (${artworkFile.lengthSync()} bytes)',
          );
          return artworkFile.path;
        }
      }
      return null;
    } catch (e, st) {
      AppLogger.warning(
        LogCategory.metadata,
        'Failed to resolve/download folder artwork for ${meta.album}',
        e,
        st,
      );
      return null;
    }
  }

  Future<void> _recomputeLibraryAggregates({
    Map<String, List<DriveFileItem>>? folderImagesMap,
    Map<String, String?>? folderParentMap,
    Map<String, DriveFileItem>? driveFileMap,
  }) async {
    final albums = await _database.select(_database.albums).get();
    for (final alb in albums) {
      final tracks = await (_database.select(
        _database.tracks,
      )..where((tbl) => tbl.albumId.equals(alb.id))).get();

      if (tracks.isEmpty) {
        await (_database.delete(
          _database.albums,
        )..where((tbl) => tbl.id.equals(alb.id))).go();
        continue;
      }

      final totalMs = tracks.fold<int>(0, (sum, t) => sum + t.durationMs);

      String? currentArtwork = alb.artworkPath;
      if (currentArtwork == null ||
          currentArtwork.isEmpty ||
          !File(currentArtwork).existsSync()) {
        final key = MetadataNormalizationService.computeArtworkKey(
          alb.title,
          alb.artistName,
        );
        final file = _fileSystem.getArtworkCacheFile(key);
        if (file.existsSync()) {
          currentArtwork = file.path;
        } else if (folderImagesMap != null && driveFileMap != null) {
          for (final track in tracks) {
            final df = driveFileMap[track.driveFileId];
            if (df?.parentFolderId != null) {
              final candidate = FolderArtworkResolver.resolveCandidate(
                folderId: df!.parentFolderId,
                folderImages: folderImagesMap,
                folderParentMap: folderParentMap,
              );
              if (candidate != null) {
                try {
                  final dlRes = await _driveRepository.downloadFile(
                    fileId: candidate.id,
                    destinationFile: file,
                  );
                  if (dlRes.isSuccess && file.existsSync()) {
                    currentArtwork = file.path;
                    break;
                  }
                } catch (_) {}
              }
            }
          }
        }
      }

      await (_database.update(
        _database.albums,
      )..where((tbl) => tbl.id.equals(alb.id))).write(
        AlbumsCompanion(
          trackCount: Value(tracks.length),
          totalDurationMs: Value(totalMs),
          artworkPath: currentArtwork != null
              ? Value(currentArtwork)
              : const Value.absent(),
        ),
      );

      if (currentArtwork != null &&
          currentArtwork.isNotEmpty &&
          File(currentArtwork).existsSync()) {
        await (_database.update(
          _database.tracks,
        )..where((tbl) => tbl.albumId.equals(alb.id))).write(
          TracksCompanion(
            artworkPath: Value(currentArtwork),
          ),
        );
      }
    }

    final artists = await _database.select(_database.artists).get();
    for (final art in artists) {
      final tracks = await (_database.select(
        _database.tracks,
      )..where((tbl) => tbl.artistId.equals(art.id))).get();
      final albums = await (_database.select(
        _database.albums,
      )..where((tbl) => tbl.artistId.equals(art.id))).get();

      if (tracks.isEmpty && albums.isEmpty) {
        await (_database.delete(
          _database.artists,
        )..where((tbl) => tbl.id.equals(art.id))).go();
        continue;
      }

      String? resolvedArtwork = art.artworkPath;
      if (resolvedArtwork == null ||
          resolvedArtwork.isEmpty ||
          !File(resolvedArtwork).existsSync()) {
        final artistCache = _fileSystem.getArtworkCacheFile(
          'artist_${art.normalizedName}',
        );
        if (artistCache.existsSync()) {
          resolvedArtwork = artistCache.path;
        } else {
          final albumWithArt = albums.where((a) {
            final p =
                a.artworkPath ?? _resolveArtworkPath(a.title, a.artistName);
            return p != null && p.isNotEmpty && File(p).existsSync();
          }).firstOrNull;
          if (albumWithArt != null) {
            resolvedArtwork =
                albumWithArt.artworkPath ??
                _resolveArtworkPath(
                  albumWithArt.title,
                  albumWithArt.artistName,
                );
          }
        }
      }

      await (_database.update(
        _database.artists,
      )..where((tbl) => tbl.id.equals(art.id))).write(
        ArtistsCompanion(
          trackCount: Value(tracks.length),
          albumCount: Value(albums.length),
          artworkPath: resolvedArtwork != null
              ? Value(resolvedArtwork)
              : const Value.absent(),
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

  Future<void> _triggerArtistArtworkDownload() async {
    try {
      final allArtists = await (_database.select(_database.artists)).get();
      final entities = allArtists.map(_mapDbArtistToEntity).toList();
      await _artistArtworkDownloader?.downloadMissingArtworks(entities);
    } catch (e, st) {
      AppLogger.debug(
        LogCategory.metadata,
        'Background artist artwork download error',
        e,
        st,
      );
    }
  }
}
