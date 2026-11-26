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

  Future<TrackRow?> _findTrack(String trackId) => (_database.select(
    _database.tracks,
  )..where((row) => row.id.equals(trackId))).getSingleOrNull();

  @override
  Future<bool> isTrackCached(String trackId) async =>
      await _cachedAudioFile(trackId, touch: false) != null;

  @override
  Future<File?> getCachedAudioFile(String trackId) =>
      _cachedAudioFile(trackId, touch: true);

  Future<File?> _cachedAudioFile(String trackId, {required bool touch}) =>
      _database.transaction(() async {
        final track = await _findTrack(trackId);
        if (track == null) return null;
        final entry = await (_database.select(
          _database.cacheEntries,
        )..where((row) => row.trackId.equals(trackId))).getSingleOrNull();
        if (entry == null ||
            entry.state != 'cached' ||
            (entry.driveVersion != null &&
                entry.driveVersion != track.driveAudioVersion)) {
          return null;
        }
        final file = File(entry.localPath);
        if (!await file.exists()) return null;
        if (touch) {
          await (_database.update(
            _database.cacheEntries,
          )..where((row) => row.trackId.equals(trackId))).write(
            CacheEntriesCompanion(lastAccessedAt: Value(DateTime.now())),
          );
        }
        return file;
      });

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
    File? partialFile;
    try {
      final existing = await getCachedAudioFile(track.id);
      if (existing != null) return Result.success(existing);
      await evictLruCache();

      final reservation = await _database.transaction(() async {
        final latest = await _findTrack(track.id);
        if (latest == null) return null;
        final extension = latest.format?.toLowerCase() ?? 'mp3';
        final target = _fileSystem.getAudioCacheFile(track.id, extension);
        final version = latest.driveAudioVersion;
        await _database
            .into(_database.cacheEntries)
            .insertOnConflictUpdate(
              CacheEntriesCompanion.insert(
                id: track.id,
                trackId: track.id,
                driveFileId: latest.driveFileId,
                localPath: target.path,
                fileSize: latest.fileSize,
                state: 'downloading',
                lastAccessedAt: DateTime.now(),
                driveVersion: Value(version),
                isPinnedOffline: Value(latest.isPinnedOffline),
              ),
            );
        return (latest.driveFileId, target, version, latest.driveMd5Checksum);
      });
      if (reservation == null) {
        return const Result.failure(
          CacheFailure('Track is no longer in the library.'),
        );
      }
      final (driveId, target, version, checksum) = reservation;
      final staging = File(
        '${target.path}.${DateTime.now().microsecondsSinceEpoch}.partial',
      );
      partialFile = staging;

      _emitProgress(track.id, 0);
      final download = await _driveRepository.downloadFile(
        fileId: driveId,
        destinationFile: staging,
        onProgress: (received, total) {
          final progress = total > 0 ? received / total : 0.0;
          onProgress?.call(progress);
          _emitProgress(track.id, progress);
        },
      );
      var failure = download.failureOrNull;
      if (failure == null &&
          !await AppFileSystem.matchesMd5(staging, checksum)) {
        failure = const CacheFailure(
          'Downloaded audio failed its checksum. Try again.',
        );
      }
      if (failure != null) {
        await (_database.update(_database.cacheEntries)..where(
              (row) =>
                  row.trackId.equals(track.id) &
                  row.driveVersion.equals(version) &
                  row.state.equals('downloading'),
            ))
            .write(
              const CacheEntriesCompanion(
                fileSize: Value(0),
                state: Value('failed'),
              ),
            );
        return Result.failure(failure);
      }

      final committed = await _database.transaction(() async {
        final latest = await _findTrack(track.id);
        if (latest == null || latest.driveAudioVersion != version) return false;
        final entry =
            await (_database.select(_database.cacheEntries)..where(
                  (row) =>
                      row.trackId.equals(track.id) &
                      row.driveVersion.equals(version),
                ))
                .getSingleOrNull();
        if (entry == null) return false;
        final size = await staging.length();
        await staging.rename(target.path);
        await (_database.update(
          _database.cacheEntries,
        )..where((row) => row.trackId.equals(track.id))).write(
          CacheEntriesCompanion(
            fileSize: Value(size),
            state: const Value('cached'),
            downloadedAt: Value(DateTime.now()),
            lastAccessedAt: Value(DateTime.now()),
            isPinnedOffline: Value(latest.isPinnedOffline),
          ),
        );
        await (_database.update(
          _database.tracks,
        )..where((row) => row.id.equals(track.id))).write(
          TracksCompanion(
            isCached: const Value(true),
            localPath: Value(target.path),
          ),
        );
        return true;
      });
      if (!committed) {
        return const Result.failure(
          CacheFailure('Track changed while downloading. Try again.'),
        );
      }
      _emitProgress(track.id, 1.0);
      return Result.success(target);
    } catch (e, st) {
      AppLogger.error(
        LogCategory.cache,
        'Error caching track ${track.id}',
        e,
        st,
      );
      return Result.failure(
        CacheFailure('Failed to cache track: ${track.title}', cause: e),
      );
    } finally {
      _emitProgress(track.id, null);
      if (partialFile != null) {
        try {
          if (await partialFile.exists()) await partialFile.delete();
        } on FileSystemException catch (error) {
          AppLogger.warning(
            LogCategory.cache,
            'Could not remove partial audio',
            error,
          );
        }
      }
    }
  }

  Future<void> _removeUnreferencedAudio() => _database.transaction(() async {
    final entries = await _database.select(_database.cacheEntries).get();
    await _fileSystem.removeUnreferencedAudio(
      entries.map((entry) => entry.localPath).toSet(),
    );
  });

  @override
  Future<Result<void, AppFailure>> pinTrackOffline(String trackId) async {
    try {
      final row = await _findTrack(trackId);
      if (row == null) {
        return const Result.failure(
          CacheFailure('Track is no longer in the library.'),
        );
      }
      final downloaded = await getOrDownloadTrack(
        Track(
          id: row.id,
          driveFileId: row.driveFileId,
          sourceId: row.sourceId,
          title: row.title,
          normalizedTitle: row.normalizedTitle,
          format: row.format,
          fileSize: row.fileSize,
        ),
      );
      if (downloaded.isFailure)
        return Result.failure(downloaded.failureOrNull!);
      return await _database.transaction(() async {
        if (await _cachedAudioFile(trackId, touch: false) == null) {
          return const Result.failure(
            CacheFailure('Offline audio is unavailable. Try again.'),
          );
        }
        await _setPinned(trackId, true);
        return const Result.success(null);
      });
    } catch (e) {
      return Result.failure(
        CacheFailure('Failed to pin track offline', cause: e),
      );
    }
  }

  @override
  Future<Result<void, AppFailure>> unpinTrackOffline(String trackId) async {
    try {
      await _database.transaction(() => _setPinned(trackId, false));
      return const Result.success(null);
    } catch (e) {
      return Result.failure(
        CacheFailure('Failed to unpin track offline', cause: e),
      );
    }
  }

  Future<void> _setPinned(String trackId, bool pinned) async {
    await (_database.update(_database.tracks)
          ..where((tbl) => tbl.id.equals(trackId)))
        .write(TracksCompanion(isPinnedOffline: Value(pinned)));
    await (_database.update(_database.cacheEntries)
          ..where((tbl) => tbl.trackId.equals(trackId)))
        .write(CacheEntriesCompanion(isPinnedOffline: Value(pinned)));
  }

  @override
  Future<Result<void, AppFailure>> evictLruCache({int? targetSizeBytes}) async {
    try {
      await _database.transaction(() async {
        await _removeUnreferencedAudio();
        final maxAllowedBytes =
            targetSizeBytes ?? AppAudioConstants.defaultCacheSizeBytes;
        int currentTotal = await getTotalCacheSize();

        if (currentTotal <= maxAllowedBytes) {
          return;
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
            currentTotal -= await file.length();
          }

          // Update database
          await (_database.delete(
            _database.cacheEntries,
          )..where((tbl) => tbl.id.equals(entry.id))).go();

          await (_database.update(
            _database.tracks,
          )..where((tbl) => tbl.id.equals(entry.trackId))).write(
            const TracksCompanion(
              isCached: Value(false),
              localPath: Value(null),
            ),
          );

          if (currentTotal <= (maxAllowedBytes * 0.90)) {
            break; // Safely below watermark
          }
        }
      });
      await _removeUnreferencedAudio();
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
      await _database.transaction(() async {
        await _removeUnreferencedAudio();
        var query = _database.select(_database.cacheEntries);
        if (!includePinned) {
          query = query..where((tbl) => tbl.isPinnedOffline.equals(false));
        }

        final entries = await query.get();
        for (final entry in entries) {
          if (entry.trackId == _currentlyPlayingTrackId) continue;

          await (_database.delete(
            _database.cacheEntries,
          )..where((tbl) => tbl.id.equals(entry.id))).go();

          await (_database.update(
            _database.tracks,
          )..where((tbl) => tbl.id.equals(entry.trackId))).write(
            const TracksCompanion(
              isCached: Value(false),
              localPath: Value(null),
            ),
          );
        }
      });
      await _removeUnreferencedAudio();
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
