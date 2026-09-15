import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import '../../../library/domain/entities/music_entities.dart';

enum CacheState {
  notCached('not_cached'),
  downloading('downloading'),
  cached('cached'),
  failed('failed');

  final String value;
  const CacheState(this.value);

  static CacheState fromString(String val) {
    return CacheState.values.firstWhere(
      (e) => e.value == val,
      orElse: () => CacheState.notCached,
    );
  }
}

@immutable
class CacheEntry {
  final String trackId;
  final String driveFileId;
  final String localPath;
  final int fileSize;
  final CacheState state;
  final bool isPinnedOffline;
  final DateTime? downloadedAt;
  final DateTime lastAccessedAt;

  const CacheEntry({
    required this.trackId,
    required this.driveFileId,
    required this.localPath,
    required this.fileSize,
    required this.state,
    this.isPinnedOffline = false,
    this.downloadedAt,
    required this.lastAccessedAt,
  });
}

abstract class CacheRepository {
  Future<Result<File, AppFailure>> getOrDownloadTrack(
    Track track, {
    void Function(double progress)? onProgress,
  });

  Future<Result<void, AppFailure>> pinTrackOffline(String trackId);
  Future<Result<void, AppFailure>> unpinTrackOffline(String trackId);
  Future<Result<void, AppFailure>> evictLruCache({int? targetSizeBytes});
  Future<Result<void, AppFailure>> clearCache({bool includePinned = false});
  Future<int> getTotalCacheSize();
  Future<int> getOfflinePinnedCount();
  Stream<int> watchCacheSize();
  Stream<double?> watchDownloadProgress(String trackId);
  Future<bool> isTrackCached(String trackId);
  Future<File?> getCachedAudioFile(String trackId);
  void setCurrentlyPlayingTrackId(String? trackId);
}
