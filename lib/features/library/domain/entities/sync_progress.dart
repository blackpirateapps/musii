import 'package:flutter/foundation.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import 'music_entities.dart';

class SyncCancellationToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

enum SyncPhase {
  idle('Idle'),
  scanning('Scanning Google Drive...'),
  extractingMetadata('Reading audio metadata...'),
  updatingDatabase('Updating library database...'),
  stopping('Stopping synchronization...'),
  stopped('Synchronization stopped'),
  complete('Synchronization complete'),
  failed('Synchronization failed');

  final String displayMessage;
  const SyncPhase(this.displayMessage);
}

@immutable
class SyncProgress {
  final String? syncRunId;
  final SyncPhase phase;
  final int filesDiscovered;
  final int filesProcessed;
  final int filesAdded;
  final int filesUpdated;
  final int filesRemoved;
  final int errorsCount;
  final String? currentFile;
  final String? errorMessage;
  final double progressPercent;
  final DateTime? lastCheckpointAt;
  final bool isResumable;
  final String? rootFolderId;
  final String? rootFolderName;

  const SyncProgress({
    this.syncRunId,
    this.phase = SyncPhase.idle,
    this.filesDiscovered = 0,
    this.filesProcessed = 0,
    this.filesAdded = 0,
    this.filesUpdated = 0,
    this.filesRemoved = 0,
    this.errorsCount = 0,
    this.currentFile,
    this.errorMessage,
    this.progressPercent = 0.0,
    this.lastCheckpointAt,
    this.isResumable = false,
    this.rootFolderId,
    this.rootFolderName,
  });

  bool get isBusy =>
      phase == SyncPhase.scanning ||
      phase == SyncPhase.extractingMetadata ||
      phase == SyncPhase.updatingDatabase ||
      phase == SyncPhase.stopping;

  bool get isStopping => phase == SyncPhase.stopping;
  bool get isStopped => phase == SyncPhase.stopped;
  bool get isComplete => phase == SyncPhase.complete;
  bool get isFailed => phase == SyncPhase.failed;

  SyncProgress copyWith({
    String? syncRunId,
    SyncPhase? phase,
    int? filesDiscovered,
    int? filesProcessed,
    int? filesAdded,
    int? filesUpdated,
    int? filesRemoved,
    int? errorsCount,
    String? currentFile,
    String? errorMessage,
    double? progressPercent,
    DateTime? lastCheckpointAt,
    bool? isResumable,
    String? rootFolderId,
    String? rootFolderName,
  }) {
    return SyncProgress(
      syncRunId: syncRunId ?? this.syncRunId,
      phase: phase ?? this.phase,
      filesDiscovered: filesDiscovered ?? this.filesDiscovered,
      filesProcessed: filesProcessed ?? this.filesProcessed,
      filesAdded: filesAdded ?? this.filesAdded,
      filesUpdated: filesUpdated ?? this.filesUpdated,
      filesRemoved: filesRemoved ?? this.filesRemoved,
      errorsCount: errorsCount ?? this.errorsCount,
      currentFile: currentFile ?? this.currentFile,
      errorMessage: errorMessage ?? this.errorMessage,
      progressPercent: progressPercent ?? this.progressPercent,
      lastCheckpointAt: lastCheckpointAt ?? this.lastCheckpointAt,
      isResumable: isResumable ?? this.isResumable,
      rootFolderId: rootFolderId ?? this.rootFolderId,
      rootFolderName: rootFolderName ?? this.rootFolderName,
    );
  }
}

abstract class MusicLibraryRepository {
  Stream<List<Track>> watchAllTracks({String? sortBy});
  Stream<List<Album>> watchAllAlbums();
  Stream<List<Artist>> watchAllArtists();
  Stream<AlbumWithTracks?> watchAlbum(String albumId);
  Stream<ArtistWithAlbums?> watchArtist(String artistId);
  Future<Result<Track?, AppFailure>> getTrackById(String trackId);
  Future<Result<Track?, AppFailure>> getTrackByDriveFileId(String driveFileId);

  Future<Result<void, AppFailure>> syncLibrary({
    required String rootFolderId,
    required String rootFolderName,
    void Function(SyncProgress progress)? onProgress,
    bool isResume = false,
    bool forceSync = false,
    String? requestedSyncRunId,
  });

  Future<Result<void, AppFailure>> syncFromSavedFolder({
    bool forceSync = false,
  });
  Future<Result<void, AppFailure>> stopSync();
  Future<Result<void, AppFailure>> resumeSync();
  Future<void> recoverInterruptedSyncIfNeeded();
  Future<SyncProgress?> getLastSyncSession();

  Stream<SyncProgress> watchSyncProgress();
}
