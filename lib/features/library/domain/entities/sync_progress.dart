import 'package:flutter/foundation.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import 'music_entities.dart';

enum SyncPhase {
  idle('Idle'),
  scanning('Scanning Google Drive...'),
  extractingMetadata('Reading audio metadata...'),
  updatingDatabase('Updating library database...'),
  complete('Synchronization complete'),
  failed('Synchronization failed');

  final String displayMessage;
  const SyncPhase(this.displayMessage);
}

@immutable
class SyncProgress {
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

  const SyncProgress({
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
  });

  SyncProgress copyWith({
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
  }) {
    return SyncProgress(
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
  });

  Stream<SyncProgress> watchSyncProgress();
}
