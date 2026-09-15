import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/filesystem/app_file_system.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/result/result.dart';
import '../../../google_drive/domain/entities/drive_item.dart';
import '../../../library/domain/entities/music_entities.dart';
import '../../domain/entities/cache_entry.dart';

class CacheRepositoryImpl implements CacheRepository {
  final AppDatabase _database;
  final GoogleDriveRepository _driveRepository;
  final AppFileSystem _fileSystem;

  String? _currentlyPlayingTrackId;
  final Map<String, StreamController<double?>> _progressControllers = {};
  final Map<String, Future<Result<File, AppFailure>>> _inFlightDownloads = {};

  CacheRepositoryImpl({
    required AppDatabase database,
    required GoogleDriveRepository driveRepository,
    AppFileSystem? fileSystem,
  }) : _database = database,
       _driveRepository = driveRepository,
       _fileSystem = fileSystem ?? AppFileSystem.instance;

  @override
  void setCurrentlyPlayingTrackId(String? trackId) {
    _currentlyPlayingTrackId = trackId;
  }

  @override
  Future<bool> isTrackCached(String trackId) async {
    final entry = await (_database.select(
      _database.cacheEntries,
    )..where((tbl) => tbl.trackId.equals(trackId))).getSingleOrNull();

    if (entry == null || entry.state != 'cached') return false;
    return File(entry.localPath).exists();
  }

  @override
  Future<File?> getCachedAudioFile(String trackId) async {
    final entry = await (_database.select(
      _database.cacheEntries,
    )..where((tbl) => tbl.trackId.equals(trackId))).getSingleOrNull();

    if (entry != null && entry.state == 'cached') {
      final file = File(entry.localPath);
      if (await file.exists()) {
        // Update last accessed
        await (_database.update(
          _database.cacheEntries,
        )..where((tbl) => tbl.trackId.equals(trackId))).write(
          CacheEntriesCompanion(lastAccessedAt: Value(DateTime.now())),
        );
        return file;
      }
    }
    return null;
  }

  @override
  Stream<double?> watchDownloadProgress(String trackId) {
    return _progressControllers
        .putIfAbsent(trackId, () => StreamController<double?>.broadcast())
        .stream;
  }

  void _emitProgress(String trackId, double? progress) {
    if (_progressControllers.containsKey(trackId)) {
      _progressControllers[trackId]!.add(progress);
    }
  }

  @override
  Future<Result<File, AppFailure>> getOrDownloadTrack(
    Track track, {
    void Function(double progress)? onProgress,
  }) async {
    final existingFuture = _inFlightDownloads[track.id];
    if (existingFuture != null) {
      return existingFuture;
    }

    final future = _executeGetOrDownloadTrack(track, onProgress: onProgress);
    _inFlightDownloads[track.id] = future;
    try {
      return await future;
    } finally {
      unawaited(_inFlightDownloads.remove(track.id));
    }
  }

  Future<Result<File, AppFailure>> _executeGetOrDownloadTrack(
    Track track, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      // 1. Check if already cached
      final existingFile = await getCachedAudioFile(track.id);
      if (existingFile != null) {
        AppLogger.debug(
          LogCategory.cache,
          'Track ${track.id} already cached at ${existingFile.path}',
        );
        return Result.success(existingFile);
      }

      // 2. Ensure cache storage limit before downloading
      await evictLruCache();

      // 3. Prepare partial and destination files
      final ext = track.format?.toLowerCase() ?? 'mp3';
      final partialFile = _fileSystem.getPartialAudioCacheFile(track.id, ext);
      final targetFile = _fileSystem.getAudioCacheFile(track.id, ext);

      // Record downloading state
      await _database
          .into(_database.cacheEntries)
          .insertOnConflictUpdate(
            CacheEntriesCompanion(
              id: Value(track.id),
              trackId: Value(track.id),
              driveFileId: Value(track.driveFileId),
              localPath: Value(targetFile.path),
              fileSize: Value(track.fileSize),
              state: const Value('downloading'),
              lastAccessedAt: Value(DateTime.now()),
            ),
          );

      _emitProgress(track.id, 0.0);

      // 4. Download from Drive to partial file
      final downloadResult = await _driveRepository.downloadFile(
        fileId: track.driveFileId,
        destinationFile: partialFile,
        onProgress: (received, total) {
          final progress = total > 0 ? (received / total) : 0.0;
          onProgress?.call(progress);
          _emitProgress(track.id, progress);
        },
      );

      if (downloadResult.isFailure) {
        await _database
            .into(_database.cacheEntries)
            .insertOnConflictUpdate(
              CacheEntriesCompanion(
                id: Value(track.id),
                trackId: Value(track.id),
                driveFileId: Value(track.driveFileId),
                localPath: Value(targetFile.path),
                fileSize: const Value(0),
                state: const Value('failed'),
                lastAccessedAt: Value(DateTime.now()),
              ),
            );
        _emitProgress(track.id, null);
        return Result.failure(downloadResult.failureOrNull!);
      }

      // 5. Atomic commit
      final committedFile = await _fileSystem.atomicCommitFile(
        partialFile,
        targetFile,
      );
      final finalSize = await committedFile.length();

      // 6. Update database record to cached
      await _database
          .into(_database.cacheEntries)
          .insertOnConflictUpdate(
            CacheEntriesCompanion(
              id: Value(track.id),
              trackId: Value(track.id),
              driveFileId: Value(track.driveFileId),
              localPath: Value(committedFile.path),
              fileSize: Value(finalSize),
              state: const Value('cached'),
              downloadedAt: Value(DateTime.now()),
              lastAccessedAt: Value(DateTime.now()),
            ),
          );

      await (_database.update(
        _database.tracks,
      )..where((tbl) => tbl.id.equals(track.id))).write(
        TracksCompanion(
          isCached: const Value(true),
          localPath: Value(committedFile.path),
        ),
      );

      _emitProgress(track.id, 1.0);
      _emitProgress(track.id, null);

      AppLogger.info(
        LogCategory.cache,
        'Successfully cached track ${track.title} (${track.id})',
      );

      return Result.success(committedFile);
    } catch (e, st) {
      AppLogger.error(
        LogCategory.cache,
        'Error caching track ${track.id}',
        e,
        st,
      );
      _emitProgress(track.id, null);
      return Result.failure(
        CacheFailure('Failed to cache track: ${track.title}', cause: e),
      );
    }
  }

  @override
  Future<Result<void, AppFailure>> pinTrackOffline(String trackId) async {
    try {
      await (_database.update(_database.tracks)
            ..where((tbl) => tbl.id.equals(trackId)))
          .write(const TracksCompanion(isPinnedOffline: Value(true)));

      await (_database.update(_database.cacheEntries)
            ..where((tbl) => tbl.trackId.equals(trackId)))
          .write(const CacheEntriesCompanion(isPinnedOffline: Value(true)));

      // Trigger download if not cached
      final isCached = await isTrackCached(trackId);
      if (!isCached) {
        final trackRecord = await (_database.select(
          _database.tracks,
        )..where((tbl) => tbl.id.equals(trackId))).getSingleOrNull();
        if (trackRecord != null) {
          final track = Track(
            id: trackRecord.id,
            driveFileId: trackRecord.driveFileId,
            sourceId: trackRecord.sourceId,
            title: trackRecord.title,
            normalizedTitle: trackRecord.normalizedTitle,
            format: trackRecord.format,
            fileSize: trackRecord.fileSize,
          );
          unawaited(getOrDownloadTrack(track));
        }
      }

      return const Result.success(null);
    } catch (e) {
      return Result.failure(
        CacheFailure('Failed to pin track offline', cause: e),
      );
    }
  }

  @override
  Future<Result<void, AppFailure>> unpinTrackOffline(String trackId) async {
    try {
      await (_database.update(_database.tracks)
            ..where((tbl) => tbl.id.equals(trackId)))
          .write(const TracksCompanion(isPinnedOffline: Value(false)));

      await (_database.update(_database.cacheEntries)
            ..where((tbl) => tbl.trackId.equals(trackId)))
          .write(const CacheEntriesCompanion(isPinnedOffline: Value(false)));

      return const Result.success(null);
    } catch (e) {
      return Result.failure(
        CacheFailure('Failed to unpin track offline', cause: e),
      );
    }
  }

  @override
  Future<Result<void, AppFailure>> evictLruCache({int? targetSizeBytes}) async {
    try {
      final maxAllowedBytes =
          targetSizeBytes ?? AppAudioConstants.defaultCacheSizeBytes;
      int currentTotal = await getTotalCacheSize();

      if (currentTotal <= maxAllowedBytes) {
        return const Result.success(null);
      }

      AppLogger.info(
        LogCategory.cache,
        'Cache exceeds threshold ($currentTotal > $maxAllowedBytes). Starting LRU eviction.',
      );

      // Query LRU non-pinned tracks
      final candidates =
          await (_database.select(_database.cacheEntries)
                ..where(
                  (tbl) =>
                      tbl.isPinnedOffline.equals(false) &
                      tbl.state.equals('cached'),
                )
                ..orderBy([(tbl) => OrderingTerm.asc(tbl.lastAccessedAt)]))
              .get();

      for (final entry in candidates) {
        if (entry.trackId == _currentlyPlayingTrackId) continue;

        final file = File(entry.localPath);
        if (await file.exists()) {
          final size = await file.length();
          await file.delete();
          currentTotal -= size;
        }

        // Update database
        await (_database.delete(
          _database.cacheEntries,
        )..where((tbl) => tbl.id.equals(entry.id))).go();

        await (_database.update(
          _database.tracks,
        )..where((tbl) => tbl.id.equals(entry.trackId))).write(
          const TracksCompanion(isCached: Value(false), localPath: Value(null)),
        );

        if (currentTotal <= (maxAllowedBytes * 0.90)) {
          break; // Safely below watermark
        }
      }

      return const Result.success(null);
    } catch (e) {
      AppLogger.error(LogCategory.cache, 'Error during LRU eviction', e);
      return Result.failure(
        CacheFailure('Cache eviction encountered an error', cause: e),
      );
    }
  }

  @override
  Future<Result<void, AppFailure>> clearCache({
    bool includePinned = false,
  }) async {
    try {
      var query = _database.select(_database.cacheEntries);
      if (!includePinned) {
        query = query..where((tbl) => tbl.isPinnedOffline.equals(false));
      }

      final entries = await query.get();
      for (final entry in entries) {
        if (entry.trackId == _currentlyPlayingTrackId) continue;

        final file = File(entry.localPath);
        if (await file.exists()) {
          await file.delete();
        }

        await (_database.delete(
          _database.cacheEntries,
        )..where((tbl) => tbl.id.equals(entry.id))).go();

        await (_database.update(
          _database.tracks,
        )..where((tbl) => tbl.id.equals(entry.trackId))).write(
          const TracksCompanion(isCached: Value(false), localPath: Value(null)),
        );
      }

      return const Result.success(null);
    } catch (e) {
      return Result.failure(CacheFailure('Failed to clear cache', cause: e));
    }
  }

  @override
  Future<int> getTotalCacheSize() async {
    return _fileSystem.getAudioCacheSizeBytes();
  }

  @override
  Future<int> getOfflinePinnedCount() async {
    final count = await (_database.select(
      _database.tracks,
    )..where((tbl) => tbl.isPinnedOffline.equals(true))).get();
    return count.length;
  }

  @override
  Stream<int> watchCacheSize() async* {
    yield await getTotalCacheSize();
    yield* _database
        .select(_database.cacheEntries)
        .watch()
        .asyncMap((_) => getTotalCacheSize());
  }
}
