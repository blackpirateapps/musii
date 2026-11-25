import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/core/database/app_database.dart';
import 'package:musii/core/error/failures.dart';
import 'package:musii/core/result/result.dart';
import 'package:musii/features/google_drive/domain/entities/drive_item.dart';
import 'package:musii/features/library/data/repositories/music_library_repository_impl.dart';
import 'package:musii/features/library/domain/entities/sync_progress.dart';
import 'package:musii/features/lyrics/data/repositories/lyrics_repository_impl.dart';
import 'package:musii/features/metadata/data/repositories/metadata_extractor_impl.dart';

class StubGoogleDriveRepository implements GoogleDriveRepository {
  @override
  Future<Result<List<DriveFolderItem>, AppFailure>> listFolders({
    String? parentFolderId,
  }) async {
    return const Result.success([]);
  }

  @override
  Future<Result<List<DriveFileItem>, AppFailure>> listAudioFilesRecursively(
    String rootFolderId, {
    void Function(int discoveredCount)? onProgress,
    void Function(DriveFileItem file)? onFileDiscovered,
    FutureOr<void> Function(
      List<String> pendingFolders,
      Set<String> visitedFolders,
    )?
    onFolderStateChanged,
    List<String>? initialFolderQueue,
    Set<String>? initialVisitedFolders,
    bool Function()? isCancelled,
    Map<String, String?>? folderParentMap,
    void Function(String folderId, String parentId)? onFolderDiscovered,
    Future<void>? abortTrigger,
  }) async {
    return const Result.success([]);
  }

  @override
  Future<Result<File, AppFailure>> downloadFile({
    required String fileId,
    required File destinationFile,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    Future<void>? abortTrigger,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Result<String, AppFailure>> downloadTextFile(
    String fileId, {
    Future<void>? abortTrigger,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Result<List<int>, AppFailure>> readByteRange({
    required String fileId,
    required int start,
    required int end,
  }) async {
    throw UnimplementedError();
  }
}

void main() {
  late AppDatabase db;
  late StubGoogleDriveRepository fakeDrive;
  late MusicLibraryRepositoryImpl libraryRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    fakeDrive = StubGoogleDriveRepository();
    libraryRepo = MusicLibraryRepositoryImpl(
      database: db,
      driveRepository: fakeDrive,
      metadataExtractor: MetadataExtractor(),
      lyricsRepository: LyricsRepositoryImpl(database: db),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Sync Progress Cold-Start & Failure Emission', () {
    test(
      'watchSyncProgress yields initial progress immediately upon subscription',
      () async {
        // Upon immediate subscription without calling any sync methods,
        // watchSyncProgress must emit the current progress (idle state) without delay.
        final initial = await libraryRepo.watchSyncProgress().first;
        expect(initial.phase, equals(SyncPhase.idle));
        expect(initial.filesDiscovered, equals(0));
        expect(initial.filesProcessed, equals(0));
      },
    );

    test('syncFromSavedFolder emits SyncPhase.failed and updates progress when no folder configured', () async {
      final emittedPhases = <SyncPhase>[];
      final subscription = libraryRepo.watchSyncProgress().listen((p) {
        emittedPhases.add(p.phase);
      });
      addTearDown(subscription.cancel);

      final result = await libraryRepo.syncFromSavedFolder();

      expect(result.isFailure, isTrue);
      expect(
        result.failureOrNull?.message,
        contains('No music folder configured'),
      );

      // Verify that progress was updated to failed with error message
      final latestProgress = await libraryRepo.watchSyncProgress().first;
      expect(latestProgress.phase, equals(SyncPhase.failed));
      expect(
        latestProgress.errorMessage,
        contains('No music folder configured'),
      );
      expect(emittedPhases, contains(SyncPhase.failed));
    });

    test(
      'syncLibrary immediately emits SyncPhase.scanning at the start of sync',
      () async {
        final emittedPhases = <SyncPhase>[];
        final subscription = libraryRepo.watchSyncProgress().listen((p) {
          emittedPhases.add(p.phase);
        });
        addTearDown(subscription.cancel);

        await libraryRepo.syncLibrary(
          rootFolderId: 'test_folder',
          rootFolderName: 'Music',
        );
        await pumpEventQueue();

        expect(emittedPhases, contains(SyncPhase.scanning));
        expect(emittedPhases, contains(SyncPhase.complete));
      },
    );
  });
}
