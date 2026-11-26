import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:drift/drift.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/filesystem/app_file_system.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/result/result.dart';
import '../../../authentication/domain/entities/auth_user.dart';
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
  final AuthRepository? _authRepository;
  StreamSubscription<AuthUser?>? _authSubscription;
  String? _activeSourceId;
  String? _visibleSourceId;
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
    AuthRepository? authRepository,
    MetadataExtractor? metadataExtractor,
    LyricsRepository? lyricsRepository,
    AppFileSystem? fileSystem,
    ArtistArtworkDownloader? artistArtworkDownloader,
  }) : _database = database,
       _driveRepository = driveRepository,
       _authRepository = authRepository,
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
    if (authRepository == null) {
      _visibleSourceId = 'source_gdrive';
      unawaited(_hydrateInitialState('source_gdrive'));
    } else {
      _authSubscription = authRepository.watchCurrentUser().listen((user) {
        final sourceId = user == null ? null : _sourceIdFor(user);
        if (sourceId == _visibleSourceId) return;
        _visibleSourceId = sourceId;
        if (_isSyncRunning && _activeSourceId != sourceId) {
          _currentCancellationToken?.cancel();
          _syncProgressController.add(const SyncProgress());
        } else if (!_isSyncRunning) {
          _updateProgress(const SyncProgress());
          if (sourceId != null) unawaited(_hydrateInitialState(sourceId));
        }
      });
    }
  }

  String _sourceIdFor(AuthUser user) => 'source_gdrive_${user.id}';

  Future<({String id, String email})?> _syncAccount() async {
    final auth = _authRepository;
    if (auth == null) return (id: 'source_gdrive', email: 'primary');
    final user = (await auth.getCurrentUser()).dataOrNull;
    return user == null ? null : (id: _sourceIdFor(user), email: user.email);
  }

  Future<SyncRunRow?> _latestRun(String sourceId) =>
      (_database.select(_database.syncRuns)
            ..where(
              (row) =>
                  row.sourceId.equals(sourceId) &
                  row.status.isNotValue('superseded'),
            )
            ..orderBy([
              (row) => OrderingTerm.desc(row.startedAt),
              (row) => OrderingTerm.desc(row.id),
            ])
            ..limit(1))
          .getSingleOrNull();

  Future<MusicSource?> _musicSource(String sourceId) => (_database.select(
    _database.musicSources,
  )..where((row) => row.id.equals(sourceId))).getSingleOrNull();

  void dispose() {
    _currentCancellationToken?.cancel();
    unawaited(_authSubscription?.cancel());
  }

  Future<void> _hydrateInitialState(String sourceId) async {
    try {
      final latest = await _latestRun(sourceId);
      if (latest != null &&
          !_isSyncRunning &&
          _visibleSourceId == sourceId &&
          _currentProgress.syncRunId == null) {
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
  Stream<SyncProgress> watchSyncProgress() => Stream.multi((listener) {
    final subscription = _syncProgressController.stream.listen(
      listener.addSync,
      onError: listener.addErrorSync,
      onDone: listener.closeSync,
    );
    listener.onCancel = subscription.cancel;
    listener.addSync(
      _activeSourceId == null || _activeSourceId == _visibleSourceId
          ? _currentProgress
          : const SyncProgress(),
    );
  });

  void _updateProgress(SyncProgress progress) {
    _currentProgress = progress;
    if (_activeSourceId == null || _activeSourceId == _visibleSourceId) {
      _syncProgressController.add(progress);
    }
  }

  @override
  Future<SyncProgress?> getLastSyncSession() async {
    try {
      final account = await _syncAccount();
      final latest = account == null ? null : await _latestRun(account.id);

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
        isResumable: const {
          'stopped',
          'running',
          'stopping',
          'failed',
        }.contains(latest.status),
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
      final account = await _syncAccount();
      final latest = account == null ? null : await _latestRun(account.id);

      if (latest != null &&
          (latest.status == 'running' || latest.status == 'stopping')) {
        AppLogger.info(
          LogCategory.sync,
          'Detected interrupted sync session: ${latest.id} with status ${latest.status}. Initiating automatic resume...',
        );

        final folderId = latest.rootFolderId;
        if (folderId != null && account != null) {
          unawaited(
            _syncLibrary(
              rootFolderId: folderId,
              rootFolderName: latest.rootFolderName ?? 'Music',
              isResume: true,
              requestedSyncRunId: latest.id,
              expectedSourceId: account.id,
            ),
          );
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
    if (!_isSyncRunning ||
        _currentCancellationToken == null ||
        !_currentProgress.isBusy) {
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

    final account = await _syncAccount();
    if (account == null) {
      return const Result.failure(
        AuthenticationFailure('Connect Google Drive to resume sync.'),
      );
    }
    final latest = await _latestRun(account.id);
    final source = latest?.rootFolderId == null
        ? await _musicSource(account.id)
        : null;
    final folderId = latest?.rootFolderId ?? source?.rootFolderId;
    final folderName = latest?.rootFolderName ?? source?.rootFolderName;
    if (folderId == null ||
        latest == null ||
        !const {
          'running',
          'stopping',
          'stopped',
          'failed',
        }.contains(latest.status)) {
      return const Result.failure(
        DriveApiFailure('No resumable sync was found for this Google account.'),
      );
    }

    return _syncLibrary(
      expectedSourceId: account.id,
      rootFolderId: folderId,
      rootFolderName: folderName ?? 'Music',
      isResume: true,
      requestedSyncRunId: latest.id,
    );
  }

  @override
  Future<Result<void, AppFailure>> syncFromSavedFolder({
    bool forceSync = false,
  }) async {
    if (_isSyncRunning) {
      return const Result.success(null);
    }

    final account = await _syncAccount();
    if (account == null) {
      return const Result.failure(
        AuthenticationFailure('Connect Google Drive to sync.'),
      );
    }
    final source = await _musicSource(account.id);
    final latest = source?.rootFolderId == null
        ? await _latestRun(account.id)
        : null;
    final folderId = source?.rootFolderId ?? latest?.rootFolderId;
    final folderName = source?.rootFolderName ?? latest?.rootFolderName;

    if (folderId == null) {
      const failure = DriveApiFailure(
        'No music folder configured. Please select a folder first.',
      );
      _updateProgress(
        _currentProgress.copyWith(
          phase: SyncPhase.failed,
          errorMessage: failure.message,
          isResumable: false,
        ),
      );
      return const Result.failure(failure);
    }

    return _syncLibrary(
      expectedSourceId: account.id,
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
      artworkPath:
          (row.artworkPath != null &&
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

  TrackSyncAction _classifyTrack(
    DriveFileItem remote,
    TrackRow? local,
    AlbumRow? album,
  ) {
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

    if (_needsUnicodeMetadataRepair(local, album)) {
      return TrackSyncAction.repairIncomplete;
    }

    if (!isMetadataComplete) {
      return TrackSyncAction.repairIncomplete;
    }

    return _audioChanged(remote, local)
        ? TrackSyncAction.updateModified
        : TrackSyncAction.unchangedComplete;
  }

  bool _needsUnicodeMetadataRepair(TrackRow track, AlbumRow? album) {
    bool legacyKey(String? display, String? storedKey) {
      if (display == null) return false;
      final key = MetadataNormalizationService.searchKey(display);
      return key != storedKey && key.contains(RegExp(r'[^\x00-\x7F]'));
    }

    return legacyKey(track.title, track.normalizedTitle) ||
        legacyKey(
          track.artistName,
          track.artistId?.replaceFirst('artist_', ''),
        ) ||
        legacyKey(album?.title, album?.normalizedTitle) ||
        legacyKey(
          album?.artistName,
          album?.artistId?.replaceFirst('artist_', ''),
        );
  }

  bool _audioChanged(DriveFileItem remote, TrackRow local) {
    final remoteTime = remote.modifiedTime?.millisecondsSinceEpoch;
    final localTime = local.driveModifiedAt?.millisecondsSinceEpoch;
    return (remoteTime != null &&
            remoteTime ~/ 1000 > (localTime ?? 0) ~/ 1000) ||
        (remote.md5Checksum != null &&
            remote.md5Checksum != local.driveMd5Checksum) ||
        (remote.size > 0 &&
            local.fileSize > 0 &&
            remote.size != local.fileSize);
  }

  @override
  Future<Result<void, AppFailure>> syncLibrary({
    required String rootFolderId,
    required String rootFolderName,
    void Function(SyncProgress progress)? onProgress,
    bool isResume = false,
    bool forceSync = false,
    String? requestedSyncRunId,
  }) => _syncLibrary(
    rootFolderId: rootFolderId,
    rootFolderName: rootFolderName,
    onProgress: onProgress,
    isResume: isResume,
    forceSync: forceSync,
    requestedSyncRunId: requestedSyncRunId,
  );

  Future<Result<void, AppFailure>> _syncLibrary({
    required String rootFolderId,
    required String rootFolderName,
    void Function(SyncProgress progress)? onProgress,
    bool isResume = false,
    bool forceSync = false,
    String? requestedSyncRunId,
    String? expectedSourceId,
  }) async {
    final int mySeq = ++_syncSequenceNumber;
    final account = await _syncAccount();
    if (mySeq != _syncSequenceNumber) return const Result.success(null);
    if (account == null) {
      const failure = AuthenticationFailure('Connect Google Drive to sync.');
      _updateProgress(
        const SyncProgress(
          phase: SyncPhase.failed,
          errorMessage: 'Connect Google Drive to sync.',
        ),
      );
      return const Result.failure(failure);
    }

    if (expectedSourceId != null && account.id != expectedSourceId) {
      return const Result.failure(
        AuthenticationFailure('Google account changed. Start sync again.'),
      );
    }

    while (_isSyncRunning) {
      _currentCancellationToken?.cancel();
      _updateProgress(_currentProgress.copyWith(phase: SyncPhase.stopping));
      await _activeSyncCompleter?.future;
      if (mySeq != _syncSequenceNumber) return const Result.success(null);
    }

    final sourceId = account.id;
    final confirmedAccount = _authRepository == null
        ? account
        : await _syncAccount();
    if (mySeq != _syncSequenceNumber) return const Result.success(null);
    if (confirmedAccount?.id != sourceId) {
      return const Result.failure(
        AuthenticationFailure('Google account changed. Start sync again.'),
      );
    }
    _activeSourceId = sourceId;
    _visibleSourceId = sourceId;
    _isSyncRunning = true;
    _activeSyncCompleter = Completer<void>();
    final cancellationToken = SyncCancellationToken();
    _currentCancellationToken = cancellationToken;

    final syncRunId =
        (isResume ? requestedSyncRunId : null) ??
        'sync_${DateTime.now().microsecondsSinceEpoch}';

    AppLogger.info(
      LogCategory.sync,
      '${isResume ? "Resuming" : "Starting"} library sync (Run ID: $syncRunId, Folder: $rootFolderName [$rootFolderId])',
    );

    _updateProgress(
      _currentProgress.copyWith(
        syncRunId: syncRunId,
        phase: SyncPhase.scanning,
        rootFolderId: rootFolderId,
        rootFolderName: rootFolderName,
        filesDiscovered: isResume ? _currentProgress.filesDiscovered : 0,
        filesProcessed: isResume ? _currentProgress.filesProcessed : 0,
        filesAdded: isResume ? _currentProgress.filesAdded : 0,
        filesUpdated: isResume ? _currentProgress.filesUpdated : 0,
        filesRemoved: isResume ? _currentProgress.filesRemoved : 0,
        errorsCount: isResume ? _currentProgress.errorsCount : 0,
        progressPercent: isResume ? _currentProgress.progressPercent : 0.0,
        errorMessage: null,
        currentFile: null,
        isResumable: false,
      ),
    );
    var runRecorded = false;
    try {
      onProgress?.call(_currentProgress);
      Future<void> verifyAccount() async {
        if (_authRepository != null && (await _syncAccount())?.id != sourceId) {
          cancellationToken.cancel();
          throw const AuthenticationFailure(
            'Google account changed during sync.',
          );
        }
      }

      await verifyAccount();
      // Fetch existing sync run record if resuming
      SyncRunRow? existingRun;
      if (isResume) {
        existingRun =
            await (_database.select(_database.syncRuns)..where(
                  (tbl) =>
                      tbl.id.equals(syncRunId) &
                      tbl.sourceId.equals(sourceId) &
                      tbl.rootFolderId.equals(rootFolderId) &
                      tbl.status.isIn(const [
                        'running',
                        'stopping',
                        'stopped',
                        'failed',
                      ]),
                ))
                .getSingleOrNull();
        if (requestedSyncRunId != null && existingRun == null) {
          throw const DriveApiFailure(
            'This sync run is no longer available for the selected folder and Google account.',
          );
        }
      }

      final effectiveForceSync = existingRun?.forceSync ?? forceSync;

      await _database.transaction(() async {
        if (existingRun == null) {
          final oldRuns = _database.selectOnly(_database.syncRuns)
            ..addColumns([_database.syncRuns.id])
            ..where(_database.syncRuns.sourceId.equals(sourceId));
          await (_database.delete(
            _database.driveFolders,
          )..where((row) => row.sourceId.isInQuery(oldRuns))).go();
          await (_database.delete(
            _database.discoveredFiles,
          )..where((row) => row.syncRunId.isInQuery(oldRuns))).go();
          await (_database.update(_database.syncRuns)..where(
                (row) =>
                    row.sourceId.equals(sourceId) &
                    row.status.isNotValue('completed'),
              ))
              .write(const SyncRunsCompanion(status: Value('superseded')));
        }

        final now = DateTime.now();
        await _database
            .into(_database.syncRuns)
            .insertOnConflictUpdate(
              SyncRunsCompanion.insert(
                id: syncRunId,
                sourceId: sourceId,
                rootFolderId: Value(rootFolderId),
                rootFolderName: Value(rootFolderName),
                startedAt: existingRun?.startedAt ?? now,
                updatedAt: Value(now),
                lastCheckpointAt: Value(now),
                status: 'running',
                forceSync: Value(effectiveForceSync),
                errorMessage: const Value(null),
                currentFile: const Value(null),
                phase: const Value('scanning'),
                filesDiscovered: Value(existingRun?.filesDiscovered ?? 0),
                filesProcessed: Value(existingRun?.filesProcessed ?? 0),
                filesAdded: Value(existingRun?.filesAdded ?? 0),
                filesUpdated: Value(existingRun?.filesUpdated ?? 0),
                filesRemoved: Value(existingRun?.filesRemoved ?? 0),
                errorsCount: Value(existingRun?.errorsCount ?? 0),
                progressPercent: Value(existingRun?.progressPercent ?? 0),
                discoveryCompleted: Value(
                  existingRun?.discoveryCompleted ?? false,
                ),
                pendingFoldersJson: Value(existingRun?.pendingFoldersJson),
                visitedFoldersJson: Value(existingRun?.visitedFoldersJson),
              ),
            );

        final source = await _musicSource(sourceId);
        await _database
            .into(_database.musicSources)
            .insertOnConflictUpdate(
              MusicSourcesCompanion.insert(
                id: sourceId,
                type: 'google_drive',
                accountEmail: account.email,
                rootFolderId: Value(rootFolderId),
                rootFolderName: Value(rootFolderName),
                createdAt: source?.createdAt ?? now,
              ),
            );
      });

      runRecorded = true;

      // Each fully listed folder and its queue transition share one commit.
      final discoveredById = <String, DriveFileItem>{};
      final alreadyProcessedDriveIds = <String>{};
      final failedDriveIds = <String>{};
      final folderParentMap = <String, String?>{};
      var discoveryAlreadyComplete = existingRun?.discoveryCompleted == true;
      var pendingFolders = <String>[rootFolderId];
      var visitedFolders = <String>{};

      if (existingRun != null) {
        final rows = await (_database.select(
          _database.discoveredFiles,
        )..where((row) => row.syncRunId.equals(syncRunId))).get();
        for (final row in rows) {
          discoveredById[row.driveFileId] = DriveFileItem(
            id: row.driveFileId,
            name: row.name,
            mimeType: row.mimeType,
            size: row.size,
            modifiedTime: row.modifiedTime.millisecondsSinceEpoch == 0
                ? null
                : row.modifiedTime,
            md5Checksum: row.md5Checksum,
            parentFolderId: row.parentFolderId,
            isLrc: row.isLrc,
            isImage: AppImageConstants.isImageFile(row.name, row.mimeType),
          );
          if (row.isProcessed) alreadyProcessedDriveIds.add(row.driveFileId);
          if (row.processStatus == 'failed') {
            failedDriveIds.add(row.driveFileId);
          }
        }
        final savedFolders = await (_database.select(
          _database.driveFolders,
        )..where((row) => row.sourceId.equals(syncRunId))).get();
        for (final folder in savedFolders) {
          folderParentMap[folder.folderId] = folder.parentFolderId;
        }
        if (existingRun.pendingFoldersJson case final pending?) {
          pendingFolders = (jsonDecode(pending) as List).cast<String>();
        }
        if (existingRun.visitedFoldersJson case final visited?) {
          visitedFolders = (jsonDecode(visited) as List).cast<String>().toSet();
        }
      }

      final restoredAudioCount = discoveredById.values
          .where((file) => !file.isLrc && !file.isImage)
          .length;
      if (discoveryAlreadyComplete &&
          restoredAudioCount != existingRun!.filesDiscovered) {
        // An incomplete saved snapshot can never authorize local removals.
        await _database.transaction(() async {
          await (_database.delete(
            _database.discoveredFiles,
          )..where((row) => row.syncRunId.equals(syncRunId))).go();
          await (_database.delete(
            _database.driveFolders,
          )..where((row) => row.sourceId.equals(syncRunId))).go();
          await (_database.update(
            _database.syncRuns,
          )..where((row) => row.id.equals(syncRunId))).write(
            const SyncRunsCompanion(
              discoveryCompleted: Value(false),
              pendingFoldersJson: Value(null),
              visitedFoldersJson: Value(null),
              filesDiscovered: Value(0),
              filesProcessed: Value(0),
              filesAdded: Value(0),
              filesUpdated: Value(0),
              filesRemoved: Value(0),
              errorsCount: Value(0),
              progressPercent: Value(0),
            ),
          );
        });
        discoveredById.clear();
        folderParentMap.clear();
        alreadyProcessedDriveIds.clear();
        failedDriveIds.clear();
        pendingFolders = [rootFolderId];
        visitedFolders.clear();
        discoveryAlreadyComplete = false;
        existingRun = null;
      }

      if (!discoveryAlreadyComplete) {
        var audioDiscovered = discoveredById.values
            .where((file) => !file.isLrc && !file.isImage)
            .length;
        final stagedFiles = <String, DriveFileItem>{};
        final stagedFolders = <String, String>{};

        Future<void> saveFolder(
          List<String> pending,
          Set<String> visited,
        ) async {
          await verifyAccount();
          final addedAudio = stagedFiles.values
              .where((file) => !file.isLrc && !file.isImage)
              .length;
          await _database.transaction(() async {
            await _database.batch((batch) {
              batch.insertAllOnConflictUpdate(
                _database.discoveredFiles,
                stagedFiles.values.map(
                  (file) => DiscoveredFilesCompanion(
                    id: Value('${syncRunId}_${file.id}'),
                    syncRunId: Value(syncRunId),
                    driveFileId: Value(file.id),
                    name: Value(file.name),
                    mimeType: Value(file.mimeType),
                    size: Value(file.size),
                    modifiedTime: Value(
                      file.modifiedTime ??
                          DateTime.fromMillisecondsSinceEpoch(0),
                    ),
                    md5Checksum: Value(file.md5Checksum),
                    parentFolderId: Value(file.parentFolderId),
                    isLrc: Value(file.isLrc),
                  ),
                ),
              );
              batch.insertAllOnConflictUpdate(
                _database.driveFolders,
                stagedFolders.entries.map(
                  (folder) => DriveFoldersCompanion.insert(
                    id: '${syncRunId}_${folder.key}',
                    sourceId: syncRunId,
                    folderId: folder.key,
                    name: folder.key,
                    parentFolderId: Value(folder.value),
                    path: '',
                  ),
                ),
              );
            });
            await (_database.update(
              _database.syncRuns,
            )..where((row) => row.id.equals(syncRunId))).write(
              SyncRunsCompanion(
                pendingFoldersJson: Value(jsonEncode(pending)),
                visitedFoldersJson: Value(jsonEncode(visited.toList())),
                filesDiscovered: Value(audioDiscovered + addedAudio),
                updatedAt: Value(DateTime.now()),
                lastCheckpointAt: Value(DateTime.now()),
              ),
            );
          });
          discoveredById.addAll(stagedFiles);
          stagedFiles.clear();
          stagedFolders.clear();
          audioDiscovered += addedAudio;
          pendingFolders = List.of(pending);
          visitedFolders = Set.of(visited);
          _updateProgress(
            _currentProgress.copyWith(filesDiscovered: audioDiscovered),
          );
          onProgress?.call(_currentProgress);
        }

        final scanResult = await _driveRepository.listAudioFilesRecursively(
          rootFolderId,
          initialFolderQueue: pendingFolders,
          initialVisitedFolders: visitedFolders,
          folderParentMap: folderParentMap,
          onFolderDiscovered: (id, parent) => stagedFolders[id] = parent,
          onFileDiscovered: (file) {
            if (!discoveredById.containsKey(file.id)) {
              stagedFiles[file.id] = file;
            }
          },
          onFolderStateChanged: saveFolder,
          isCancelled: () => cancellationToken.isCancelled,
          abortTrigger: cancellationToken.whenCancelled,
        );

        if (cancellationToken.isCancelled) {
          await _persistSessionStopped(
            syncRunId: syncRunId,
            filesDiscovered: audioDiscovered,
            discoveryCompleted: false,
            pendingFolders: pendingFolders,
            visitedFolders: visitedFolders,
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
          final error = scanResult.failureOrNull!;
          await _persistSessionFailed(
            syncRunId: syncRunId,
            error: error.message,
          );
          _updateProgress(
            _currentProgress.copyWith(
              phase: SyncPhase.failed,
              errorMessage: error.message,
              isResumable: true,
            ),
          );
          onProgress?.call(_currentProgress);
          return Result.failure(error);
        }

        // Repositories may return a listing without streaming folder callbacks.
        for (final file in scanResult.dataOrNull!) {
          if (!discoveredById.containsKey(file.id)) stagedFiles[file.id] = file;
        }
        if (stagedFiles.isNotEmpty || stagedFolders.isNotEmpty) {
          await saveFolder(const [], visitedFolders);
        }
        await (_database.update(
          _database.syncRuns,
        )..where((row) => row.id.equals(syncRunId))).write(
          SyncRunsCompanion(
            discoveryCompleted: const Value(true),
            pendingFoldersJson: const Value(null),
            visitedFoldersJson: const Value(null),
            filesDiscovered: Value(audioDiscovered),
            updatedAt: Value(DateTime.now()),
            lastCheckpointAt: Value(DateTime.now()),
          ),
        );
      }

      final allDriveFiles = discoveredById.values;
      final driveAudioFiles = allDriveFiles
          .where((f) => !f.isLrc && !f.isImage)
          .toList();
      final driveLrcFiles = allDriveFiles.where((f) => f.isLrc).toList();
      final driveImageFiles = allDriveFiles.where((f) => f.isImage).toList();

      // Build map of sidecar LRC files keyed by folder and base filename
      final lrcMap = <(String, String), DriveFileItem>{};
      for (final lrc in driveLrcFiles) {
        final folder = lrc.parentFolderId ?? '';
        final base = _cleanBaseName(lrc.name);
        lrcMap[(folder, base)] = lrc;
      }

      // Build map of folder image files keyed by parentFolderId
      final Map<String, List<DriveFileItem>> folderImagesMap = {};
      for (final img in driveImageFiles) {
        final folder = img.parentFolderId ?? '';
        folderImagesMap.putIfAbsent(folder, () => []).add(img);
      }

      final driveFileMap = {for (final f in driveAudioFiles) f.id: f};

      // 3. Load existing indexed tracks
      final allIndexedTracks = await _database.select(_database.tracks).get();
      final sourcesByTrack = <String, Set<String>>{};
      for (final membership
          in await _database.select(_database.trackSources).get()) {
        sourcesByTrack
            .putIfAbsent(membership.trackId, () => {})
            .add(membership.sourceId);
      }
      final existingTracks = allIndexedTracks.where(
        (track) =>
            sourcesByTrack[track.id]?.contains(sourceId) ??
            track.sourceId == sourceId,
      );
      final existingMap = {
        for (final track in allIndexedTracks) track.driveFileId: track,
      };

      final albumsById = {
        for (final album in await _database.select(_database.albums).get())
          album.id: album,
      };

      // 4. Classify each audio file
      final existingLyrics = {
        for (final row in await _database.select(_database.lyrics).get())
          row.trackId: row.source,
      };
      final sidecarOnly = <String>{};
      final List<DriveFileItem> toProcess = [];
      final List<DriveFileItem> unchangedComplete = [];
      var processedCount = 0;

      for (final df in driveAudioFiles) {
        // Check if this file was already processed and added in this sync run
        if (isResume && alreadyProcessedDriveIds.contains(df.id)) {
          processedCount++;
          continue;
        }

        if (effectiveForceSync) {
          toProcess.add(df);
          continue;
        }

        final existing = existingMap[df.id];
        final action = _classifyTrack(
          df,
          existing,
          albumsById[existing?.albumId],
        );
        switch (action) {
          case TrackSyncAction.unchangedComplete:
            final sidecar = _sidecarFor(df, lrcMap);
            final lyricSource = existingLyrics[existing!.id];
            final hasEmbeddedLyrics =
                lyricSource == LyricSource.embeddedSynced.value ||
                lyricSource == LyricSource.embeddedPlain.value;
            if (!hasEmbeddedLyrics &&
                (existing.sidecarFingerprint != _fileFingerprint(sidecar) ||
                    (sidecar == null &&
                        lyricSource == LyricSource.sidecarLrc.value))) {
              sidecarOnly.add(df.id);
              toProcess.add(df);
            } else if (failedDriveIds.contains(df.id)) {
              toProcess.add(df);
            } else {
              unchangedComplete.add(df);
            }
            break;
          case TrackSyncAction.updateModified:
          case TrackSyncAction.processNew:
          case TrackSyncAction.repairIncomplete:
            toProcess.add(df);
            break;
        }
      }

      // Each batch stays below SQLite's lowest supported variable limit.
      for (var offset = 0; offset < unchangedComplete.length; offset += 500) {
        final unchangedRowIds = unchangedComplete
            .skip(offset)
            .take(500)
            .map((file) => '${syncRunId}_${file.id}');
        await (_database.update(
          _database.discoveredFiles,
        )..where((tbl) => tbl.id.isIn(unchangedRowIds))).write(
          DiscoveredFilesCompanion(
            isProcessed: const Value(true),
            processStatus: const Value('unchanged'),
            processedAt: Value(DateTime.now()),
          ),
        );
      }

      final totalDiscovered = driveAudioFiles.length;
      processedCount += unchangedComplete.length;
      int addedCount = isResume ? (existingRun?.filesAdded ?? 0) : 0;
      int updatedCount = isResume ? (existingRun?.filesUpdated ?? 0) : 0;
      var errorsCount = 0;

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
          errorsCount: errorsCount,
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
          errorsCount: Value(errorsCount),
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
          await verifyAccount();
          final existing = existingMap[driveFile.id];
          final trackId = existing?.id ?? 'track_${driveFile.id}';
          final sidecar = _sidecarFor(driveFile, lrcMap);
          ParsedAudioMetadata? parsedMeta;
          NormalizedMetadata? normalized;
          String? embeddedArtworkPath;
          if (!sidecarOnly.contains(driveFile.id)) {
            final extension = driveFile.name
                .split('.')
                .last
                .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
            tempFile = _fileSystem.getTempMetadataFile(
              'temp_${Uri.encodeComponent(driveFile.id)}.${extension.substring(0, extension.length.clamp(0, 12))}',
            );
            final downloaded = await _driveRepository.downloadFile(
              fileId: driveFile.id,
              destinationFile: tempFile,
              abortTrigger: cancellationToken.whenCancelled,
            );
            if (downloaded.isFailure) throw downloaded.failureOrNull!;
            if (!await AppFileSystem.matchesMd5(
              tempFile,
              driveFile.md5Checksum,
            )) {
              throw const DriveApiFailure(
                'Downloaded audio failed its checksum.',
              );
            }
            parsedMeta = await _metadataExtractor.extractFromFile(
              tempFile,
              fallbackName: driveFile.name,
              knownFileSize: driveFile.size > 0 ? driveFile.size : null,
            );
            normalized = MetadataNormalizationService.normalize(
              parsedMeta,
              filenameFallback: driveFile.name,
            );
            final artwork = parsedMeta.artworkBytes;
            if (artwork != null && artwork.isNotEmpty) {
              final file = _fileSystem.getArtworkCacheFile(
                'embedded_${sha256.convert(artwork)}',
              );
              if (!await file.exists()) {
                final staged = File('${file.path}.partial');
                await file.parent.create(recursive: true);
                try {
                  await staged.writeAsBytes(artwork, flush: true);
                  await staged.rename(file.path);
                } finally {
                  if (await staged.exists()) await staged.delete();
                }
              }
              embeddedArtworkPath = file.path;
            }
          }

          // Fetch sidecars before opening the SQLite transaction.
          final lyrics = await _readLyrics(
            parsedMeta,
            sidecar,
            cancellationToken,
          );
          await verifyAccount();
          final currentAdded = existing == null ? addedCount + 1 : addedCount;
          final currentUpdated = existing == null
              ? updatedCount
              : updatedCount + 1;
          final currentProcessed = processedCount + 1;

          await _database.transaction(() async {
            if (normalized != null) {
              await _upsertTrackAndRelationsInTx(
                sourceId: existing?.sourceId ?? sourceId,
                driveFile: driveFile,
                meta: normalized,
                previous: existing,
                rawJson: jsonEncode(parsedMeta?.rawMetadata ?? {}),
                embeddedArtworkPath: embeddedArtworkPath,
              );
              if (existing != null &&
                  (effectiveForceSync || _audioChanged(driveFile, existing))) {
                await _refreshAudioCache(trackId, tempFile!);
              }
            }
            if (lyrics == null) {
              await _lyricsRepository.deleteLyricsForTrack(trackId);
            } else {
              final (source, parsed) = lyrics;
              await _lyricsRepository.saveLyrics(
                trackId: trackId,
                source: source,
                isSynchronized: parsed.isSynchronized,
                rawText: parsed.rawText,
                offsetMs: parsed.offsetMs,
                lines: parsed.lines,
              );
            }
            await (_database.update(
              _database.tracks,
            )..where((row) => row.id.equals(trackId))).write(
              TracksCompanion(
                sidecarFingerprint: Value(_fileFingerprint(sidecar)),
              ),
            );
            await (_database.update(_database.discoveredFiles)..where(
                  (row) => row.id.equals('${syncRunId}_${driveFile.id}'),
                ))
                .write(
                  DiscoveredFilesCompanion(
                    isProcessed: const Value(true),
                    processStatus: Value(
                      existing == null ? 'added' : 'updated',
                    ),
                    processedAt: Value(DateTime.now()),
                  ),
                );
            await (_database.update(
              _database.syncRuns,
            )..where((row) => row.id.equals(syncRunId))).write(
              SyncRunsCompanion(
                filesProcessed: Value(currentProcessed),
                filesAdded: Value(currentAdded),
                filesUpdated: Value(currentUpdated),
                errorsCount: Value(errorsCount),
                progressPercent: Value(currentProcessed / totalDiscovered),
                currentFile: Value(driveFile.name),
                lastCheckpointAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            );
          });
          processedCount = currentProcessed;
          addedCount = currentAdded;
          updatedCount = currentUpdated;
        } catch (error, stackTrace) {
          if (cancellationToken.isCancelled) break;
          errorsCount++;
          AppLogger.warning(
            LogCategory.sync,
            'Error processing audio metadata: ${driveFile.name}',
            error,
            stackTrace,
          );
          await _recordSyncErrorAndCheckpoint(
            syncRunId: syncRunId,
            file: driveFile,
            message: error is AppFailure ? error.message : error.toString(),
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

      if (errorsCount > 0) {
        final error = DriveApiFailure(
          'Could not synchronize $errorsCount of $totalDiscovered tracks. Resume to retry them.',
        );
        await _persistSessionFailed(syncRunId: syncRunId, error: error.message);
        _updateProgress(
          _currentProgress.copyWith(
            phase: SyncPhase.failed,
            errorMessage: error.message,
            isResumable: true,
            currentFile: null,
          ),
        );
        onProgress?.call(_currentProgress);
        return Result.failure(error);
      }

      // Fetch artwork before the transaction that prunes the local library.
      final folderArtwork = await _prepareFolderArtwork(
        driveFileMap,
        folderImagesMap,
        folderParentMap,
        force: effectiveForceSync,
        cancellation: cancellationToken,
      );
      _updateProgress(
        _currentProgress.copyWith(
          phase: SyncPhase.updatingDatabase,
          currentFile: null,
        ),
      );
      onProgress?.call(_currentProgress);

      await verifyAccount();
      final missingTracks = existingTracks
          .where((track) => !driveFileMap.containsKey(track.driveFileId))
          .toList();
      if (isResume && missingTracks.isNotEmpty) {
        // A checkpoint can outlive a file move. Confirm absences with a fresh
        // listing before deleting tracks and their local relationships.
        final liveListing = await _driveRepository.listAudioFilesRecursively(
          rootFolderId,
          isCancelled: () => cancellationToken.isCancelled,
          abortTrigger: cancellationToken.whenCancelled,
        );
        cancellationToken.throwIfCancelled();
        if (liveListing.isFailure) throw liveListing.failureOrNull!;
        final presentIds = liveListing.dataOrNull!
            .where((file) => !file.isLrc && !file.isImage)
            .map((file) => file.id)
            .toSet();
        missingTracks.removeWhere(
          (track) => presentIds.contains(track.driveFileId),
        );
        await verifyAccount();
      }
      final removedTracks = <TrackRow>[];
      await _database.transaction(() async {
        cancellationToken.throwIfCancelled();
        final affectedPlaylists = <String>{};
        for (final track in missingTracks) {
          cancellationToken.throwIfCancelled();
          final otherSources = sourcesByTrack[track.id]?.difference({sourceId});
          if (otherSources != null && otherSources.isNotEmpty) {
            await (_database.delete(_database.trackSources)..where(
                  (row) =>
                      row.sourceId.equals(sourceId) &
                      row.trackId.equals(track.id),
                ))
                .go();
            if (track.sourceId == sourceId) {
              await (_database.update(_database.tracks)
                    ..where((row) => row.id.equals(track.id)))
                  .write(TracksCompanion(sourceId: Value(otherSources.first)));
            }
            continue;
          }
          affectedPlaylists.addAll(await _deleteTrack(track.id));
          removedTracks.add(track);
        }
        for (final playlistId in affectedPlaylists) {
          final remaining =
              await (_database.select(_database.playlistTracks)
                    ..where((row) => row.playlistId.equals(playlistId))
                    ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
                  .get();
          await _database.batch((batch) {
            for (final (order, entry) in remaining.indexed) {
              batch.update(
                _database.playlistTracks,
                PlaylistTracksCompanion(sortOrder: Value(order)),
                where: (row) => row.id.equals(entry.id),
              );
            }
          });
          await (_database.update(
            _database.playlists,
          )..where((row) => row.id.equals(playlistId))).write(
            PlaylistsCompanion(
              trackCount: Value(remaining.length),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }

        if (_authRepository != null) {
          final legacyIds = allIndexedTracks
              .where(
                (track) =>
                    track.sourceId == 'source_gdrive' &&
                    driveFileMap.containsKey(track.driveFileId),
              )
              .map((track) => track.id)
              .toList();
          for (var offset = 0; offset < legacyIds.length; offset += 500) {
            await (_database.update(_database.tracks)..where(
                  (row) =>
                      row.id.isIn(legacyIds.skip(offset).take(500)) &
                      row.sourceId.equals('source_gdrive'),
                ))
                .write(TracksCompanion(sourceId: Value(sourceId)));
            await (_database.delete(_database.trackSources)..where(
                  (row) =>
                      row.sourceId.equals('source_gdrive') &
                      row.trackId.isIn(legacyIds.skip(offset).take(500)),
                ))
                .go();
          }
        }
        await _database.customStatement(
          '''
          INSERT OR IGNORE INTO track_sources (source_id, track_id)
          SELECT ?, track.id FROM tracks AS track
          JOIN discovered_files AS file ON file.drive_file_id = track.drive_file_id
          WHERE file.sync_run_id = ? AND file.is_lrc = 0
        ''',
          [sourceId, syncRunId],
        );

        await _database.reconcileDuplicateAlbums();
        await _recomputeLibraryAggregates(
          folderArtwork: folderArtwork,
          driveFileMap: driveFileMap,
        );
        cancellationToken.throwIfCancelled();

        await (_database.update(
          _database.syncRuns,
        )..where((row) => row.id.equals(syncRunId))).write(
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
            filesRemoved: Value(removedTracks.length),
            errorsCount: const Value(0),
            progressPercent: const Value(1.0),
            currentFile: const Value(null),
            errorMessage: const Value(null),
          ),
        );

        await (_database.update(_database.musicSources)
              ..where((row) => row.id.equals(sourceId)))
            .write(MusicSourcesCompanion(lastSyncedAt: Value(DateTime.now())));
        cancellationToken.throwIfCancelled();
      });

      _updateProgress(
        _currentProgress.copyWith(
          phase: SyncPhase.complete,
          filesDiscovered: totalDiscovered,
          filesProcessed: totalDiscovered,
          filesAdded: addedCount,
          filesUpdated: updatedCount,
          filesRemoved: removedTracks.length,
          errorsCount: errorsCount,
          progressPercent: 1.0,
          currentFile: null,
          isResumable: false,
        ),
      );
      onProgress?.call(_currentProgress);

      AppLogger.info(
        LogCategory.sync,
        'Sync completed successfully! Discovered: $totalDiscovered, Unchanged: ${unchangedComplete.length}, Added: $addedCount, Updated: $updatedCount, Removed: ${removedTracks.length}, Errors: $errorsCount',
      );

      // Trigger background download of missing artist artwork
      unawaited(_triggerArtistArtworkDownload());

      return const Result.success(null);
    } catch (e, st) {
      if (cancellationToken.isCancelled) {
        if (runRecorded) await _persistSessionStopped(syncRunId: syncRunId);
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
      AppLogger.error(LogCategory.sync, 'Fatal error during sync', e, st);
      final message = e is AppFailure ? e.message : e.toString();
      if (runRecorded) {
        await _persistSessionFailed(syncRunId: syncRunId, error: message);
      }
      _updateProgress(
        _currentProgress.copyWith(
          phase: SyncPhase.failed,
          errorMessage: message,
          isResumable: true,
        ),
      );
      onProgress?.call(_currentProgress);

      return Result.failure(
        e is AppFailure ? e : DatabaseFailure('Sync failed', cause: e),
      );
    } finally {
      try {
        await _database.transaction(() async {
          final entries = await _database.select(_database.cacheEntries).get();
          await _fileSystem.removeUnreferencedAudio(
            entries.map((entry) => entry.localPath).toSet(),
          );
        });
      } catch (e) {
        AppLogger.warning(
          LogCategory.cache,
          'Could not remove stale sync audio',
          e,
        );
      }
      _isSyncRunning = false;
      _activeSourceId = null;
      if (_visibleSourceId != sourceId) {
        _updateProgress(const SyncProgress());
        final visibleSourceId = _visibleSourceId;
        if (visibleSourceId != null) {
          unawaited(_hydrateInitialState(visibleSourceId));
        }
      }
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

        await (_database.update(
          _database.discoveredFiles,
        )..where((tbl) => tbl.id.equals('${syncRunId}_${file.id}'))).write(
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
    required TrackRow? previous,
    required String rawJson,
    String? embeddedArtworkPath,
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
    final effectiveArtwork =
        embeddedArtworkPath ??
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
            driveModifiedAt: Value(
              driveFile.modifiedTime ?? previous?.driveModifiedAt,
            ),
            driveMd5Checksum: Value(
              driveFile.md5Checksum ?? previous?.driveMd5Checksum,
            ),
            artworkPath: effectiveArtwork != null
                ? Value(effectiveArtwork)
                : const Value(null),
            rawMetadataJson: Value(rawJson),
            embeddedArtworkPath: Value(embeddedArtworkPath),
            createdAt: Value(previous?.createdAt ?? DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> _refreshAudioCache(String trackId, File downloaded) async {
    final track = await (_database.select(
      _database.tracks,
    )..where((row) => row.id.equals(trackId))).getSingle();
    if (!track.isPinnedOffline) {
      await (_database.delete(
        _database.cacheEntries,
      )..where((row) => row.trackId.equals(trackId))).go();
      await (_database.update(
        _database.tracks,
      )..where((row) => row.id.equals(trackId))).write(
        const TracksCompanion(isCached: Value(false), localPath: Value(null)),
      );
      return;
    }

    // Use a new path so the previous pin survives transaction rollback.
    final digest = sha256.convert(utf8.encode(track.driveAudioVersion));
    final file = _fileSystem.getAudioCacheFile(
      '${track.id}_$digest',
      track.format?.toLowerCase() ?? 'mp3',
    );
    final staging = File('${file.path}.partial');
    await file.parent.create(recursive: true);
    try {
      await downloaded.copy(staging.path);
      await staging.rename(file.path);
    } finally {
      if (await staging.exists()) await staging.delete();
    }
    final now = DateTime.now();
    await _database
        .into(_database.cacheEntries)
        .insertOnConflictUpdate(
          CacheEntriesCompanion.insert(
            id: track.id,
            trackId: track.id,
            driveFileId: track.driveFileId,
            localPath: file.path,
            fileSize: await file.length(),
            state: 'cached',
            isPinnedOffline: const Value(true),
            driveVersion: Value(track.driveAudioVersion),
            downloadedAt: Value(now),
            lastAccessedAt: now,
          ),
        );
    await (_database.update(
      _database.tracks,
    )..where((row) => row.id.equals(trackId))).write(
      TracksCompanion(isCached: const Value(true), localPath: Value(file.path)),
    );
  }

  Future<Set<String>> _deleteTrack(String trackId) async {
    final memberships = await (_database.select(
      _database.playlistTracks,
    )..where((row) => row.trackId.equals(trackId))).get();
    await (_database.delete(
      _database.playlistTracks,
    )..where((row) => row.trackId.equals(trackId))).go();
    await (_database.delete(
      _database.favorites,
    )..where((row) => row.trackId.equals(trackId))).go();
    await (_database.delete(
      _database.recentlyPlayed,
    )..where((row) => row.trackId.equals(trackId))).go();
    await (_database.delete(
      _database.playbackQueue,
    )..where((row) => row.trackId.equals(trackId))).go();
    await (_database.update(
      _database.playbackStates,
    )..where((row) => row.currentTrackId.equals(trackId))).write(
      const PlaybackStatesCompanion(
        currentTrackId: Value(null),
        positionMs: Value(0),
        durationMs: Value(0),
        isPlaying: Value(false),
      ),
    );
    await (_database.delete(
      _database.cacheEntries,
    )..where((row) => row.trackId.equals(trackId))).go();
    await _lyricsRepository.deleteLyricsForTrack(trackId);
    await (_database.delete(
      _database.tracks,
    )..where((row) => row.id.equals(trackId))).go();
    return memberships.map((row) => row.playlistId).toSet();
  }

  Future<Map<String, (String, String)>> _prepareFolderArtwork(
    Map<String, DriveFileItem> driveFiles,
    Map<String, List<DriveFileItem>> folderImages,
    Map<String, String?> folderParents, {
    required bool force,
    required SyncCancellationToken cancellation,
  }) async {
    final byTrack = <String, (String, String)>{};
    final filesByFingerprint = <String, File>{};
    final tracksByAlbum = <String?, List<TrackRow>>{};
    for (final track in await _database.select(_database.tracks).get()) {
      tracksByAlbum.putIfAbsent(track.albumId, () => []).add(track);
    }
    for (final tracks in tracksByAlbum.values) {
      if (tracks.any(
        (track) => _existingFile(track.embeddedArtworkPath) != null,
      )) {
        continue;
      }
      for (final track in tracks) {
        cancellation.throwIfCancelled();
        final candidate = FolderArtworkResolver.resolveCandidate(
          folderId: driveFiles[track.driveFileId]?.parentFolderId,
          folderImages: folderImages,
          folderParentMap: folderParents,
        );
        final fingerprint = _fileFingerprint(candidate);
        if (candidate == null || fingerprint == null) continue;
        var file = filesByFingerprint[fingerprint];
        if (file == null) {
          final digest = sha256.convert(utf8.encode(fingerprint));
          file = _fileSystem.getArtworkCacheFile('drive_$digest');
          if (force || !await file.exists()) {
            await file.parent.create(recursive: true);
            final staging = File('${file.path}.partial');
            try {
              final result = await _driveRepository.downloadFile(
                fileId: candidate.id,
                destinationFile: staging,
                abortTrigger: cancellation.whenCancelled,
              );
              if (result.isFailure) throw result.failureOrNull!;
              await staging.rename(file.path);
            } finally {
              if (await staging.exists()) await staging.delete();
            }
          }
          filesByFingerprint[fingerprint] = file;
        }
        byTrack[track.driveFileId] = (fingerprint, file.path);
        break;
      }
    }
    return byTrack;
  }

  String? _existingFile(String? path) =>
      path != null && path.isNotEmpty && File(path).existsSync() ? path : null;

  Future<void> _recomputeLibraryAggregates({
    required Map<String, (String, String)> folderArtwork,
    required Map<String, DriveFileItem> driveFileMap,
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

      final belongsToSync = tracks.any(
        (track) => driveFileMap.containsKey(track.driveFileId),
      );
      final embeddedArtwork = tracks
          .map((track) => _existingFile(track.embeddedArtworkPath))
          .nonNulls
          .firstOrNull;
      final remoteArtwork = tracks
          .map((track) => folderArtwork[track.driveFileId])
          .nonNulls
          .firstOrNull;
      final previousArtwork = _existingFile(alb.artworkPath);
      final isLegacyArtwork =
          alb.driveArtworkFingerprint == null &&
          !(previousArtwork
                  ?.split(Platform.pathSeparator)
                  .last
                  .startsWith('embedded_') ??
              false);
      final currentArtwork =
          embeddedArtwork ??
          remoteArtwork?.$2 ??
          (!belongsToSync || isLegacyArtwork ? previousArtwork : null);

      await (_database.update(
        _database.albums,
      )..where((tbl) => tbl.id.equals(alb.id))).write(
        AlbumsCompanion(
          trackCount: Value(tracks.length),
          totalDurationMs: Value(totalMs),
          artworkPath: Value(currentArtwork),
          driveArtworkFingerprint: belongsToSync
              ? Value(embeddedArtwork == null ? remoteArtwork?.$1 : null)
              : const Value.absent(),
        ),
      );

      await (_database.update(_database.tracks)
            ..where((tbl) => tbl.albumId.equals(alb.id)))
          .write(TracksCompanion(artworkPath: Value(currentArtwork)));
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

  DriveFileItem? _sidecarFor(
    DriveFileItem audio,
    Map<(String, String), DriveFileItem> sidecars,
  ) => sidecars[(audio.parentFolderId ?? '', _cleanBaseName(audio.name))];

  String? _fileFingerprint(DriveFileItem? file) {
    if (file == null) return null;
    return jsonEncode([
      file.id,
      file.name,
      file.md5Checksum,
      (file.modifiedTime?.millisecondsSinceEpoch ?? 0) ~/ 1000,
      file.size,
    ]);
  }

  Future<(LyricSource, ParsedLyricsResult)?> _readLyrics(
    ParsedAudioMetadata? audio,
    DriveFileItem? sidecar,
    SyncCancellationToken cancellation,
  ) async {
    final embedded = audio?.lyrics;
    if (embedded != null && embedded.trim().isNotEmpty) {
      final parsed = LrcParser.parse(embedded);
      if (parsed.lines.isNotEmpty) {
        return (
          parsed.isSynchronized
              ? LyricSource.embeddedSynced
              : LyricSource.embeddedPlain,
          parsed,
        );
      }
    }
    if (sidecar == null) return null;
    final result = await _driveRepository.downloadTextFile(
      sidecar.id,
      abortTrigger: cancellation.whenCancelled,
    );
    if (result.isFailure) throw result.failureOrNull!;
    final parsed = LrcParser.parse(result.dataOrNull!);
    return parsed.lines.isEmpty ? null : (LyricSource.sidecarLrc, parsed);
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
