import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
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
import 'package:musii/features/metadata/domain/entities/parsed_audio_metadata.dart';

class FakeGoogleDriveRepository implements GoogleDriveRepository {
  List<DriveFileItem> filesToReturn = [];
  int downloadCallCount = 0;
  final List<String> downloadedFileIds = [];
  int listCallCount = 0;

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
    void Function(List<String> pendingFolders, Set<String> visitedFolders)?
    onFolderStateChanged,
    List<String>? initialFolderQueue,
    Set<String>? initialVisitedFolders,
    bool Function()? isCancelled,
    Map<String, String?>? folderParentMap,
  }) async {
    listCallCount++;
    if (isCancelled?.call() == true) {
      return const Result.success([]);
    }
    for (final f in filesToReturn) {
      if (isCancelled?.call() == true) break;
      onFileDiscovered?.call(f);
    }
    onProgress?.call(filesToReturn.where((f) => !f.isLrc).length);
    onFolderStateChanged?.call([], {rootFolderId});
    return Result.success(filesToReturn);
  }

  final Set<String> failingFileIds = {};

  @override
  Future<Result<File, AppFailure>> downloadFile({
    required String fileId,
    required File destinationFile,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    if (failingFileIds.contains(fileId)) {
      return const Result.failure(
        NetworkFailure('Simulated download failure'),
      );
    }
    downloadCallCount++;
    downloadedFileIds.add(fileId);
    // Write empty dummy file
    await destinationFile.create(recursive: true);
    await destinationFile.writeAsBytes([1, 2, 3]);
    onProgress?.call(3, 3);
    return Result.success(destinationFile);
  }

  @override
  Future<Result<String, AppFailure>> downloadTextFile(String fileId) async {
    return const Result.success('[00:10.00]Sidecar lyrics line');
  }

  @override
  Future<Result<List<int>, AppFailure>> readByteRange({
    required String fileId,
    required int start,
    required int end,
  }) async {
    return const Result.success([0, 1, 2]);
  }
}

class FakeMetadataExtractor extends MetadataExtractor {
  int extractCallCount = 0;
  final Map<String, ParsedAudioMetadata> customMetadata = {};

  @override
  Future<ParsedAudioMetadata> extractFromFile(
    File file, {
    String? fallbackName,
    int? knownFileSize,
  }) async {
    extractCallCount++;
    final name = fallbackName ?? 'Song';
    if (customMetadata.containsKey(name)) {
      return customMetadata[name]!;
    }
    return ParsedAudioMetadata(
      title: name.replaceAll('.mp3', '').replaceAll('.flac', ''),
      artist: 'Test Artist',
      album: 'Test Album',
      genre: 'City Pop',
      format: 'MP3',
      fileSize: knownFileSize ?? 3000000,
      durationMs: 210000,
      year: 1984,
      trackNumber: 1,
    );
  }
}

void main() {
  late AppDatabase db;
  late FakeGoogleDriveRepository fakeDrive;
  late FakeMetadataExtractor fakeExtractor;
  late LyricsRepositoryImpl lyricsRepo;
  late MusicLibraryRepositoryImpl libraryRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    fakeDrive = FakeGoogleDriveRepository();
    fakeExtractor = FakeMetadataExtractor();
    lyricsRepo = LyricsRepositoryImpl(database: db);
    libraryRepo = MusicLibraryRepositoryImpl(
      database: db,
      driveRepository: fakeDrive,
      metadataExtractor: fakeExtractor,
      lyricsRepository: lyricsRepo,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Library Sync Optimization & Crash-Safe Checkpointing Flow', () {
    test('FIRST SYNC: indexes all files, saves metadata, relations, and completed checkpoint', () async {
      final now = DateTime(2026, 9, 15, 12, 0);
      fakeDrive.filesToReturn = [
        DriveFileItem(
          id: 'df_1',
          name: 'Stay With Me.mp3',
          mimeType: 'audio/mpeg',
          size: 5000000,
          modifiedTime: now,
          md5Checksum: 'md5_1',
          parentFolderId: 'folder_root',
        ),
        DriveFileItem(
          id: 'df_2',
          name: 'Flyday Chinatown.mp3',
          mimeType: 'audio/mpeg',
          size: 6000000,
          modifiedTime: now,
          md5Checksum: 'md5_2',
          parentFolderId: 'folder_root',
        ),
        DriveFileItem(
          id: 'df_3',
          name: 'Plastic Love.mp3',
          mimeType: 'audio/mpeg',
          size: 7000000,
          modifiedTime: now,
          md5Checksum: 'md5_3',
          parentFolderId: 'folder_root',
        ),
      ];

      final result = await libraryRepo.syncLibrary(
        rootFolderId: 'folder_root',
        rootFolderName: 'Music',
      );

      expect(result.isSuccess, isTrue);
      expect(fakeDrive.downloadCallCount, equals(3));
      expect(fakeExtractor.extractCallCount, equals(3));

      // Verify tracks stored in database
      final allTracks = await libraryRepo.watchAllTracks().first;
      expect(allTracks.length, equals(3));
      expect(
        allTracks.map((t) => t.driveFileId),
        containsAll(['df_1', 'df_2', 'df_3']),
      );

      // Verify SyncRun completed
      final syncRun = await (db.select(db.syncRuns)).getSingle();
      expect(syncRun.status, equals('completed'));
      expect(syncRun.filesDiscovered, equals(3));
      expect(syncRun.filesProcessed, equals(3));
      expect(syncRun.filesAdded, equals(3));
      expect(syncRun.errorsCount, equals(0));
      expect(syncRun.progressPercent, equals(1.0));
    });

    test('METADATA REUSE: subsequent sync with unchanged remote files performs ZERO downloads and ZERO metadata extractions', () async {
      final modTime = DateTime(2026, 9, 15, 12, 0);
      fakeDrive.filesToReturn = [
        DriveFileItem(
          id: 'df_1',
          name: 'Stay With Me.mp3',
          mimeType: 'audio/mpeg',
          size: 5000000,
          modifiedTime: modTime,
          md5Checksum: 'md5_1',
          parentFolderId: 'folder_root',
        ),
        DriveFileItem(
          id: 'df_2',
          name: 'Flyday Chinatown.mp3',
          mimeType: 'audio/mpeg',
          size: 6000000,
          modifiedTime: modTime,
          md5Checksum: 'md5_2',
          parentFolderId: 'folder_root',
        ),
      ];

      // 1. First sync
      await libraryRepo.syncLibrary(
        rootFolderId: 'folder_root',
        rootFolderName: 'Music',
      );
      expect(fakeDrive.downloadCallCount, equals(2));
      expect(fakeExtractor.extractCallCount, equals(2));

      // Reset counters
      fakeDrive.downloadCallCount = 0;
      fakeDrive.downloadedFileIds.clear();
      fakeExtractor.extractCallCount = 0;

      // 2. Second sync with identical unchanged remote files
      final sync2Result = await libraryRepo.syncLibrary(
        rootFolderId: 'folder_root',
        rootFolderName: 'Music',
      );

      expect(sync2Result.isSuccess, isTrue);
      // CRITICAL CHECK: No downloads and no metadata extraction for unchanged files!
      expect(fakeDrive.downloadCallCount, equals(0));
      expect(fakeExtractor.extractCallCount, equals(0));

      final tracksAfter = await libraryRepo.watchAllTracks().first;
      expect(tracksAfter.length, equals(2));
    });

    test('CHANGED TRACK DETECTION: refreshes only modified file while reusing unchanged files', () async {
      final t1 = DateTime(2026, 9, 15, 12, 0);
      fakeDrive.filesToReturn = [
        DriveFileItem(
          id: 'df_1',
          name: 'Stay With Me.mp3',
          mimeType: 'audio/mpeg',
          size: 5000000,
          modifiedTime: t1,
          md5Checksum: 'md5_1',
          parentFolderId: 'folder_root',
        ),
        DriveFileItem(
          id: 'df_2',
          name: 'Flyday Chinatown.mp3',
          mimeType: 'audio/mpeg',
          size: 6000000,
          modifiedTime: t1,
          md5Checksum: 'md5_2',
          parentFolderId: 'folder_root',
        ),
      ];

      // First sync
      await libraryRepo.syncLibrary(
        rootFolderId: 'folder_root',
        rootFolderName: 'Music',
      );

      // Reset counters
      fakeDrive.downloadCallCount = 0;
      fakeDrive.downloadedFileIds.clear();
      fakeExtractor.extractCallCount = 0;

      // Simulate df_2 updated on Google Drive with newer timestamp and new size
      final t2 = DateTime(2026, 9, 15, 15, 30);
      fakeDrive.filesToReturn = [
        DriveFileItem(
          id: 'df_1',
          name: 'Stay With Me.mp3',
          mimeType: 'audio/mpeg',
          size: 5000000,
          modifiedTime: t1,
          md5Checksum: 'md5_1',
          parentFolderId: 'folder_root',
        ),
        DriveFileItem(
          id: 'df_2',
          name: 'Flyday Chinatown.mp3',
          mimeType: 'audio/mpeg',
          size: 6500000,
          modifiedTime: t2,
          md5Checksum: 'md5_2_modified',
          parentFolderId: 'folder_root',
        ),
      ];

      // Sync again
      await libraryRepo.syncLibrary(
        rootFolderId: 'folder_root',
        rootFolderName: 'Music',
      );

      // CRITICAL CHECK: only df_2 was downloaded and parsed!
      expect(fakeDrive.downloadCallCount, equals(1));
      expect(fakeDrive.downloadedFileIds, equals(['df_2']));
      expect(fakeExtractor.extractCallCount, equals(1));

      // Verify updated track in DB has new size and modified timestamp
      final track2 = await libraryRepo.getTrackByDriveFileId('df_2');
      expect(track2.dataOrNull?.fileSize, equals(6500000));
      expect(track2.dataOrNull?.driveModifiedAt, equals(t2));
    });

    test(
      'REMOVED FILES: removes stale tracks from database when deleted remotely',
      () async {
        final now = DateTime(2026, 9, 15, 12, 0);
        fakeDrive.filesToReturn = [
          DriveFileItem(
            id: 'df_1',
            name: 'Stay With Me.mp3',
            mimeType: 'audio/mpeg',
            size: 5000000,
            modifiedTime: now,
            parentFolderId: 'folder_root',
          ),
          DriveFileItem(
            id: 'df_2',
            name: 'Flyday Chinatown.mp3',
            mimeType: 'audio/mpeg',
            size: 6000000,
            modifiedTime: now,
            parentFolderId: 'folder_root',
          ),
        ];

        await libraryRepo.syncLibrary(
          rootFolderId: 'folder_root',
          rootFolderName: 'Music',
        );
        expect((await libraryRepo.watchAllTracks().first).length, equals(2));

        // df_2 deleted on Drive
        fakeDrive.filesToReturn = [
          DriveFileItem(
            id: 'df_1',
            name: 'Stay With Me.mp3',
            mimeType: 'audio/mpeg',
            size: 5000000,
            modifiedTime: now,
            parentFolderId: 'folder_root',
          ),
        ];

        await libraryRepo.syncLibrary(
          rootFolderId: 'folder_root',
          rootFolderName: 'Music',
        );

        final tracksAfter = await libraryRepo.watchAllTracks().first;
        expect(tracksAfter.length, equals(1));
        expect(tracksAfter.first.driveFileId, equals('df_1'));
      },
    );

    test('STOP AND RESUME: stopSync preserves completed items and resumeSync continues from checkpoint', () async {
      final now = DateTime(2026, 9, 15, 12, 0);
      fakeDrive.filesToReturn = [
        DriveFileItem(
          id: 'df_1',
          name: 'Track 1.mp3',
          mimeType: 'audio/mpeg',
          size: 1000,
          modifiedTime: now,
          parentFolderId: 'root',
        ),
        DriveFileItem(
          id: 'df_2',
          name: 'Track 2.mp3',
          mimeType: 'audio/mpeg',
          size: 2000,
          modifiedTime: now,
          parentFolderId: 'root',
        ),
        DriveFileItem(
          id: 'df_3',
          name: 'Track 3.mp3',
          mimeType: 'audio/mpeg',
          size: 3000,
          modifiedTime: now,
          parentFolderId: 'root',
        ),
        DriveFileItem(
          id: 'df_4',
          name: 'Track 4.mp3',
          mimeType: 'audio/mpeg',
          size: 4000,
          modifiedTime: now,
          parentFolderId: 'root',
        ),
      ];

      // Request stop after 2 items are processed
      int callbackCount = 0;
      final syncFuture = libraryRepo.syncLibrary(
        rootFolderId: 'root',
        rootFolderName: 'Music',
        onProgress: (p) {
          if (p.filesProcessed == 2 && callbackCount == 0) {
            callbackCount++;
            libraryRepo.stopSync();
          }
        },
      );

      final result = await syncFuture;
      expect(result.isSuccess, isTrue);

      // Verify stopped state in DB
      final lastSession = await libraryRepo.getLastSyncSession();
      expect(lastSession, isNotNull);
      expect(lastSession!.phase, equals(SyncPhase.stopped));
      expect(lastSession.isResumable, isTrue);
      expect(lastSession.filesProcessed, greaterThanOrEqualTo(2));

      final initialDownloadedCount = fakeDrive.downloadCallCount;
      expect(initialDownloadedCount, greaterThanOrEqualTo(2));

      // Reset download log
      fakeDrive.downloadedFileIds.clear();
      fakeDrive.downloadCallCount = 0;

      // Resume sync
      final resumeResult = await libraryRepo.resumeSync();
      expect(resumeResult.isSuccess, isTrue);

      // Verify that already completed tracks (df_1, df_2) were SKIPPED on resume!
      expect(fakeDrive.downloadedFileIds, isNot(contains('df_1')));
      expect(fakeDrive.downloadedFileIds, isNot(contains('df_2')));
      expect(fakeDrive.downloadedFileIds, containsAll(['df_3', 'df_4']));

      final allTracks = await libraryRepo.watchAllTracks().first;
      expect(allTracks.length, equals(4));
    });

    test('FORCE-CLOSE RECOVERY: interrupted running session auto-resumes on startup without restarting from zero', () async {
      final now = DateTime(2026, 9, 15, 12, 0);
      fakeDrive.filesToReturn = [
        DriveFileItem(
          id: 'df_1',
          name: 'Song A.mp3',
          mimeType: 'audio/mpeg',
          size: 1000,
          modifiedTime: now,
          parentFolderId: 'root',
        ),
        DriveFileItem(
          id: 'df_2',
          name: 'Song B.mp3',
          mimeType: 'audio/mpeg',
          size: 2000,
          modifiedTime: now,
          parentFolderId: 'root',
        ),
        DriveFileItem(
          id: 'df_3',
          name: 'Song C.mp3',
          mimeType: 'audio/mpeg',
          size: 3000,
          modifiedTime: now,
          parentFolderId: 'root',
        ),
      ];

      // 1. Manually simulate state where app was killed mid-sync after 1 track committed
      await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              id: 'track_df_1',
              driveFileId: 'df_1',
              sourceId: 'source_gdrive',
              title: 'Song A',
              normalizedTitle: 'song a',
              format: const Value('MP3'),
              fileSize: const Value(1000),
              durationMs: const Value(200000),
              driveModifiedAt: Value(now),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await db
          .into(db.syncRuns)
          .insert(
            SyncRunsCompanion.insert(
              id: 'sync_interrupted_1',
              sourceId: 'source_gdrive',
              rootFolderId: const Value('root'),
              rootFolderName: const Value('Music'),
              startedAt: now,
              status: 'running', // App died while running
              phase: const Value('extractingMetadata'),
              filesDiscovered: const Value(3),
              filesProcessed: const Value(1),
              progressPercent: const Value(0.33),
            ),
          );

      // 2. Instantiate new repository simulating app restart
      final newLibraryRepo = MusicLibraryRepositoryImpl(
        database: db,
        driveRepository: fakeDrive,
        metadataExtractor: fakeExtractor,
        lyricsRepository: lyricsRepo,
      );

      // 3. Call startup recovery
      await newLibraryRepo.recoverInterruptedSyncIfNeeded();

      // Allow background async resume to complete
      for (int i = 0; i < 50; i++) {
        if (fakeDrive.downloadedFileIds.contains('df_3')) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      // df_1 was already in database -> should have been skipped!
      expect(fakeDrive.downloadedFileIds, isNot(contains('df_1')));
      expect(fakeDrive.downloadedFileIds, containsAll(['df_2', 'df_3']));

      final tracks = await newLibraryRepo.watchAllTracks().first;
      expect(tracks.length, equals(3));
    });

    test('IDEMPOTENCE & DUPLICATE PREVENTION: repeated syncs produce exact single records', () async {
      final now = DateTime(2026, 9, 15, 12, 0);
      fakeDrive.filesToReturn = [
        DriveFileItem(
          id: 'df_1',
          name: 'Track 1.mp3',
          mimeType: 'audio/mpeg',
          size: 1000,
          modifiedTime: now,
          parentFolderId: 'root',
        ),
      ];

      // Run sync 3 times in a row
      await libraryRepo.syncLibrary(
        rootFolderId: 'root',
        rootFolderName: 'Music',
      );
      await libraryRepo.syncLibrary(
        rootFolderId: 'root',
        rootFolderName: 'Music',
      );
      await libraryRepo.syncLibrary(
        rootFolderId: 'root',
        rootFolderName: 'Music',
      );

      final tracks = await db.select(db.tracks).get();
      final albums = await db.select(db.albums).get();
      final artists = await db.select(db.artists).get();

      expect(tracks.length, equals(1));
      expect(albums.length, equals(1));
      expect(artists.length, equals(1));
    });

    test(
      'SYNC FROM SAVED FOLDER: returns failure when no folder is configured',
      () async {
        final result = await libraryRepo.syncFromSavedFolder();
        expect(result.isFailure, isTrue);
        expect(
          result.failureOrNull?.message,
          contains('No music folder configured'),
        );
      },
    );

    test(
      'SYNC FROM SAVED FOLDER: triggers sync using folder from MusicSources',
      () async {
        final now = DateTime(2026, 9, 16, 12, 0);
        fakeDrive.filesToReturn = [
          DriveFileItem(
            id: 'df_1',
            name: 'Track 1.mp3',
            mimeType: 'audio/mpeg',
            size: 1000,
            modifiedTime: now,
            parentFolderId: 'saved_root',
          ),
        ];

        // Pre-populate MusicSources with a saved folder
        await db
            .into(db.musicSources)
            .insertOnConflictUpdate(
              MusicSourcesCompanion(
                id: const Value('source_gdrive'),
                type: const Value('google_drive'),
                accountEmail: const Value('test@example.com'),
                rootFolderId: const Value('saved_root'),
                rootFolderName: const Value('My Music'),
                createdAt: Value(now),
              ),
            );

        final result = await libraryRepo.syncFromSavedFolder();
        expect(result.isSuccess, isTrue);

        final tracks = await libraryRepo.watchAllTracks().first;
        expect(tracks.length, equals(1));
        expect(tracks.first.driveFileId, equals('df_1'));
      },
    );

    test('FORCE SYNC: re-processes all files even when unchanged', () async {
      final now = DateTime(2026, 9, 16, 12, 0);
      fakeDrive.filesToReturn = [
        DriveFileItem(
          id: 'df_1',
          name: 'Track 1.mp3',
          mimeType: 'audio/mpeg',
          size: 1000,
          modifiedTime: now,
          md5Checksum: 'md5_1',
          parentFolderId: 'root',
        ),
        DriveFileItem(
          id: 'df_2',
          name: 'Track 2.mp3',
          mimeType: 'audio/mpeg',
          size: 2000,
          modifiedTime: now,
          md5Checksum: 'md5_2',
          parentFolderId: 'root',
        ),
      ];

      // 1. First sync — processes everything
      await libraryRepo.syncLibrary(
        rootFolderId: 'root',
        rootFolderName: 'Music',
      );
      expect(fakeDrive.downloadCallCount, equals(2));

      // Reset counters
      fakeDrive.downloadCallCount = 0;
      fakeExtractor.extractCallCount = 0;

      // 2. Normal re-sync — skips everything (unchanged)
      await libraryRepo.syncLibrary(
        rootFolderId: 'root',
        rootFolderName: 'Music',
      );
      expect(fakeDrive.downloadCallCount, equals(0));
      expect(fakeExtractor.extractCallCount, equals(0));

      // Reset counters
      fakeDrive.downloadCallCount = 0;
      fakeExtractor.extractCallCount = 0;

      // 3. Force sync — re-processes everything despite being unchanged
      await libraryRepo.syncLibrary(
        rootFolderId: 'root',
        rootFolderName: 'Music',
        forceSync: true,
      );
      expect(fakeDrive.downloadCallCount, equals(2));
      expect(fakeExtractor.extractCallCount, equals(2));

      // Still only 2 tracks in DB (no duplicates)
      final tracks = await libraryRepo.watchAllTracks().first;
      expect(tracks.length, equals(2));
    });

    test('CLASSIFICATION FIX: track with fileSize 0 and complete metadata is classified as unchangedComplete', () async {
      final now = DateTime(2026, 9, 16, 12, 0);
      fakeDrive.filesToReturn = [
        DriveFileItem(
          id: 'df_1',
          name: 'Track 1.mp3',
          mimeType: 'audio/mpeg',
          size: 5000,
          modifiedTime: now,
          md5Checksum: 'md5_1',
          parentFolderId: 'root',
        ),
      ];

      // Insert a track directly with fileSize=0 but complete metadata
      await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              id: 'track_df_1',
              driveFileId: 'df_1',
              sourceId: 'source_gdrive',
              title: 'Track 1',
              normalizedTitle: 'track 1',
              format: const Value('MP3'),
              fileSize: const Value(
                0,
              ), // fileSize is 0 (not matching remote.size=5000)
              durationMs: const Value(200000),
              driveModifiedAt: Value(now),
              driveMd5Checksum: const Value('md5_1'),
              createdAt: now,
              updatedAt: now,
            ),
          );

      // Sync should skip this track because fileSize=0 means no meaningful
      // size was stored, so size comparison is skipped
      final result = await libraryRepo.syncLibrary(
        rootFolderId: 'root',
        rootFolderName: 'Music',
      );

      expect(result.isSuccess, isTrue);
      // Should NOT have downloaded the file since metadata is complete
      // and fileSize=0 skips size comparison
      expect(fakeDrive.downloadCallCount, equals(0));
    });

    test('ZERO RESCAN ON RESUME: sync stopped after discovery restores discovered files from DB and makes 0 Drive list calls on resume', () async {
      final now = DateTime(2026, 9, 17, 12, 0);
      fakeDrive.filesToReturn = [
        DriveFileItem(
          id: 'df_1',
          name: 'Song 1.mp3',
          mimeType: 'audio/mpeg',
          size: 1000,
          modifiedTime: now,
          parentFolderId: 'root',
        ),
        DriveFileItem(
          id: 'df_2',
          name: 'Song 2.mp3',
          mimeType: 'audio/mpeg',
          size: 2000,
          modifiedTime: now,
          parentFolderId: 'root',
        ),
        DriveFileItem(
          id: 'df_3',
          name: 'Song 3.mp3',
          mimeType: 'audio/mpeg',
          size: 3000,
          modifiedTime: now,
          parentFolderId: 'root',
        ),
      ];

      // 1. Start sync and stop it after 1 track is processed
      int processedCallbackCount = 0;
      await libraryRepo.syncLibrary(
        rootFolderId: 'root',
        rootFolderName: 'Music',
        onProgress: (p) {
          if (p.filesProcessed == 1 && processedCallbackCount == 0) {
            processedCallbackCount++;
            libraryRepo.stopSync();
          }
        },
      );

      // Verify discovery was completed and 1 track was processed
      final lastSession = await libraryRepo.getLastSyncSession();
      expect(lastSession, isNotNull);
      expect(lastSession!.phase, equals(SyncPhase.stopped));
      expect(lastSession.filesDiscovered, equals(3));
      expect(fakeDrive.listCallCount, equals(1));

      // Reset drive call counters
      fakeDrive.listCallCount = 0;
      fakeDrive.downloadCallCount = 0;
      fakeDrive.downloadedFileIds.clear();

      // 2. Resume sync — MUST NOT call listAudioFilesRecursively again!
      final resumeResult = await libraryRepo.resumeSync();
      expect(resumeResult.isSuccess, isTrue);

      // ZERO Drive list calls on resume!
      expect(fakeDrive.listCallCount, equals(0));

      // Remaining tracks (df_2, df_3) were processed
      expect(fakeDrive.downloadedFileIds, containsAll(['df_2', 'df_3']));
      expect(fakeDrive.downloadedFileIds, isNot(contains('df_1')));

      final allTracks = await libraryRepo.watchAllTracks().first;
      expect(allTracks.length, equals(3));
    });

    test('FOLDER SWITCH DURING ACTIVE SCANNING: selecting new folder stops active scan and syncs only new folder', () async {
      final now = DateTime(2026, 9, 17, 12, 0);

      final folderAFiles = [
        DriveFileItem(
          id: 'df_a1',
          name: 'Track A1.mp3',
          mimeType: 'audio/mpeg',
          size: 1000,
          modifiedTime: now,
          parentFolderId: 'folder_a',
        ),
        DriveFileItem(
          id: 'df_a2',
          name: 'Track A2.mp3',
          mimeType: 'audio/mpeg',
          size: 2000,
          modifiedTime: now,
          parentFolderId: 'folder_a',
        ),
      ];

      final folderBFiles = [
        DriveFileItem(
          id: 'df_b1',
          name: 'Track B1.mp3',
          mimeType: 'audio/mpeg',
          size: 1000,
          modifiedTime: now,
          parentFolderId: 'folder_b',
        ),
      ];

      fakeDrive.filesToReturn = folderAFiles;

      // Start sync for Folder A
      final syncFutureA = libraryRepo.syncLibrary(
        rootFolderId: 'folder_a',
        rootFolderName: 'Folder A',
      );

      // While Folder A sync is in progress, switch to Folder B
      fakeDrive.filesToReturn = folderBFiles;
      final syncFutureB = libraryRepo.syncLibrary(
        rootFolderId: 'folder_b',
        rootFolderName: 'Folder B',
      );

      final results = await Future.wait([syncFutureA, syncFutureB]);
      expect(results[0].isSuccess, isTrue);
      expect(results[1].isSuccess, isTrue);

      // Library should contain ONLY tracks from Folder B!
      final allTracks = await libraryRepo.watchAllTracks().first;
      expect(allTracks.length, equals(1));
      expect(allTracks.first.driveFileId, equals('df_b1'));

      // Music source should point to Folder B
      final source = await (db.select(db.musicSources)).getSingle();
      expect(source.rootFolderId, equals('folder_b'));
      expect(source.rootFolderName, equals('Folder B'));
    });

    test('FOLDER SWITCH DURING METADATA EXTRACTION: halts old sync, prunes old tracks, and syncs new folder', () async {
      final now = DateTime(2026, 9, 17, 12, 0);

      final folderAFiles = [
        DriveFileItem(
          id: 'df_a1',
          name: 'Track A1.mp3',
          mimeType: 'audio/mpeg',
          size: 1000,
          modifiedTime: now,
          parentFolderId: 'folder_a',
        ),
        DriveFileItem(
          id: 'df_a2',
          name: 'Track A2.mp3',
          mimeType: 'audio/mpeg',
          size: 2000,
          modifiedTime: now,
          parentFolderId: 'folder_a',
        ),
        DriveFileItem(
          id: 'df_a3',
          name: 'Track A3.mp3',
          mimeType: 'audio/mpeg',
          size: 3000,
          modifiedTime: now,
          parentFolderId: 'folder_a',
        ),
      ];

      final folderBFiles = [
        DriveFileItem(
          id: 'df_b1',
          name: 'Track B1.mp3',
          mimeType: 'audio/mpeg',
          size: 1000,
          modifiedTime: now,
          parentFolderId: 'folder_b',
        ),
        DriveFileItem(
          id: 'df_b2',
          name: 'Track B2.mp3',
          mimeType: 'audio/mpeg',
          size: 2000,
          modifiedTime: now,
          parentFolderId: 'folder_b',
        ),
      ];

      fakeDrive.filesToReturn = folderAFiles;

      int folderASwitchTriggered = 0;
      Future<Result<void, AppFailure>>? syncFutureB;

      await libraryRepo.syncLibrary(
        rootFolderId: 'folder_a',
        rootFolderName: 'Folder A',
        onProgress: (p) {
          if (p.filesProcessed == 1 && folderASwitchTriggered == 0) {
            folderASwitchTriggered++;
            fakeDrive.filesToReturn = folderBFiles;
            syncFutureB = libraryRepo.syncLibrary(
              rootFolderId: 'folder_b',
              rootFolderName: 'Folder B',
            );
          }
        },
      );

      if (syncFutureB != null) {
        final resB = await syncFutureB!;
        expect(resB.isSuccess, isTrue);
      }

      // Library must contain only Folder B tracks!
      final allTracks = await libraryRepo.watchAllTracks().first;
      expect(allTracks.length, equals(2));
      expect(
        allTracks.map((t) => t.driveFileId),
        containsAll(['df_b1', 'df_b2']),
      );
      expect(allTracks.map((t) => t.driveFileId), isNot(contains('df_a1')));
    });

    test('RAPID MULTI-FOLDER SWITCHING: executing Folder A -> B -> C in rapid succession runs only Folder C', () async {
      final now = DateTime(2026, 9, 17, 12, 0);

      fakeDrive.filesToReturn = [
        DriveFileItem(
          id: 'df_c1',
          name: 'Track C1.mp3',
          mimeType: 'audio/mpeg',
          size: 1000,
          modifiedTime: now,
          parentFolderId: 'folder_c',
        ),
      ];

      final futureA = libraryRepo.syncLibrary(
        rootFolderId: 'folder_a',
        rootFolderName: 'Folder A',
      );
      final futureB = libraryRepo.syncLibrary(
        rootFolderId: 'folder_b',
        rootFolderName: 'Folder B',
      );
      final futureC = libraryRepo.syncLibrary(
        rootFolderId: 'folder_c',
        rootFolderName: 'Folder C',
      );

      await Future.wait([futureA, futureB, futureC]);

      final allTracks = await libraryRepo.watchAllTracks().first;
      expect(allTracks.length, equals(1));
      expect(allTracks.first.driveFileId, equals('df_c1'));

      final source = await (db.select(db.musicSources)).getSingle();
      expect(source.rootFolderId, equals('folder_c'));
    });

    test('NEW SYNC AFTER COMPLETION RESCANS DRIVE: subsequent sync after completion performs fresh scan', () async {
      final now = DateTime(2026, 9, 17, 12, 0);

      fakeDrive.filesToReturn = [
        DriveFileItem(
          id: 'df_1',
          name: 'Track 1.mp3',
          mimeType: 'audio/mpeg',
          size: 1000,
          modifiedTime: now,
          parentFolderId: 'root',
        ),
      ];

      // 1. Complete initial sync
      final res1 = await libraryRepo.syncLibrary(
        rootFolderId: 'root',
        rootFolderName: 'Music',
      );
      expect(res1.isSuccess, isTrue);
      expect(fakeDrive.listCallCount, equals(1));

      // 2. Complete subsequent sync (isResume: false)
      fakeDrive.listCallCount = 0;
      final res2 = await libraryRepo.syncFromSavedFolder();
      expect(res2.isSuccess, isTrue);

      // A new sync (not resume) MUST rescan Drive!
      expect(fakeDrive.listCallCount, equals(1));
    });

    test('PERSISTED PROCESSED STATUS: tracks marked isProcessed=true in DiscoveredFiles are not re-extracted on resume', () async {
      final now = DateTime(2026, 9, 15, 12, 0);
      fakeDrive.filesToReturn = [
        DriveFileItem(
          id: 'df_p1',
          name: 'Track 1.mp3',
          mimeType: 'audio/mpeg',
          size: 1000,
          modifiedTime: now,
          parentFolderId: 'root_p',
        ),
        DriveFileItem(
          id: 'df_p2',
          name: 'Track 2.mp3',
          mimeType: 'audio/mpeg',
          size: 2000,
          modifiedTime: now,
          parentFolderId: 'root_p',
        ),
        DriveFileItem(
          id: 'df_p3',
          name: 'Track 3.mp3',
          mimeType: 'audio/mpeg',
          size: 3000,
          modifiedTime: now,
          parentFolderId: 'root_p',
        ),
      ];

      int stoppedOnce = 0;
      await libraryRepo.syncLibrary(
        rootFolderId: 'root_p',
        rootFolderName: 'Music P',
        onProgress: (p) {
          if (p.filesProcessed == 1 && stoppedOnce == 0) {
            stoppedOnce++;
            libraryRepo.stopSync();
          }
        },
      );

      // Check DiscoveredFiles in DB for the stopped sync run
      final lastSession = await libraryRepo.getLastSyncSession();
      expect(lastSession, isNotNull);
      final runId = lastSession!.syncRunId!;

      final discoveredRows = await (db.select(db.discoveredFiles)
            ..where((tbl) => tbl.syncRunId.equals(runId)))
          .get();
      expect(discoveredRows.length, equals(3));

      final df1 = discoveredRows.firstWhere((r) => r.driveFileId == 'df_p1');
      expect(df1.isProcessed, isTrue);
      expect(df1.processStatus, equals('added'));
      expect(df1.processedAt, isNotNull);

      final df2 = discoveredRows.firstWhere((r) => r.driveFileId == 'df_p2');
      expect(df2.isProcessed, isFalse);
      expect(df2.processStatus, isNull);

      final df3 = discoveredRows.firstWhere((r) => r.driveFileId == 'df_p3');
      expect(df3.isProcessed, isFalse);
      expect(df3.processStatus, isNull);

      // Reset download log
      fakeDrive.downloadedFileIds.clear();
      fakeDrive.downloadCallCount = 0;
      fakeExtractor.extractCallCount = 0;

      // Resume
      final resumeRes = await libraryRepo.resumeSync();
      expect(resumeRes.isSuccess, isTrue);

      // df_p1 should NOT have been downloaded or extracted again
      expect(fakeDrive.downloadedFileIds, isNot(contains('df_p1')));
      expect(fakeDrive.downloadedFileIds, containsAll(['df_p2', 'df_p3']));
      expect(fakeDrive.downloadCallCount, equals(2));
      expect(fakeExtractor.extractCallCount, equals(2));

      // After resume completion, all files must be marked isProcessed == true
      final completedRows = await (db.select(db.discoveredFiles)
            ..where((tbl) => tbl.syncRunId.equals(runId)))
          .get();
      expect(completedRows.every((r) => r.isProcessed), isTrue);
      expect(
        completedRows.map((r) => r.processStatus),
        everyElement(anyOf('added', 'unchanged', 'updated')),
      );
    });

    test('RETRY FAILED TRACKS ON RESUME: failed tracks have isProcessed=false, processStatus=failed and are retried on resume', () async {
      final now = DateTime(2026, 9, 15, 12, 0);
      fakeDrive.filesToReturn = [
        DriveFileItem(
          id: 'df_fail',
          name: 'Broken Track.mp3',
          mimeType: 'audio/mpeg',
          size: 1000,
          modifiedTime: now,
          parentFolderId: 'root_f',
        ),
        DriveFileItem(
          id: 'df_ok',
          name: 'Good Track.mp3',
          mimeType: 'audio/mpeg',
          size: 2000,
          modifiedTime: now,
          parentFolderId: 'root_f',
        ),
      ];

      // Fail df_fail
      fakeDrive.failingFileIds.add('df_fail');

      final firstRes = await libraryRepo.syncLibrary(
        rootFolderId: 'root_f',
        rootFolderName: 'Music F',
      );
      expect(firstRes.isSuccess, isTrue);

      final lastSession = await libraryRepo.getLastSyncSession();
      expect(lastSession, isNotNull);
      final runId = lastSession!.syncRunId!;

      final rows = await (db.select(db.discoveredFiles)
            ..where((tbl) => tbl.syncRunId.equals(runId)))
          .get();
      final failRow = rows.firstWhere((r) => r.driveFileId == 'df_fail');
      expect(failRow.isProcessed, isFalse);
      expect(failRow.processStatus, equals('failed'));

      final okRow = rows.firstWhere((r) => r.driveFileId == 'df_ok');
      expect(okRow.isProcessed, isTrue);
      expect(okRow.processStatus, equals('added'));

      // Now resolve the failure and resume sync
      fakeDrive.failingFileIds.clear();
      fakeDrive.downloadedFileIds.clear();
      fakeDrive.downloadCallCount = 0;

      final resumeRes = await libraryRepo.resumeSync();
      expect(resumeRes.isSuccess, isTrue);

      // Only df_fail should be downloaded
      expect(fakeDrive.downloadedFileIds, equals(['df_fail']));
      expect(fakeDrive.downloadCallCount, equals(1));

      // Check DB: df_fail is now processed
      final rowsAfter = await (db.select(db.discoveredFiles)
            ..where((tbl) => tbl.syncRunId.equals(runId)))
          .get();
      final retryRow = rowsAfter.firstWhere((r) => r.driveFileId == 'df_fail');
      expect(retryRow.isProcessed, isTrue);
      expect(retryRow.processStatus, equals('added'));
    });

    test('SUB-SECOND MODIFIED TIMESTAMP TOLERANCE: avoids false-positive re-downloads when remote timestamp has sub-second precision', () async {
      // Remote initial timestamp with millisecond precision
      final remoteInitial = DateTime.utc(2026, 9, 15, 12, 0, 0, 456);
      fakeDrive.filesToReturn = [
        DriveFileItem(
          id: 'df_subsecond',
          name: 'Timestamp Test.mp3',
          mimeType: 'audio/mpeg',
          size: 5000000,
          modifiedTime: remoteInitial,
          parentFolderId: 'root_ts',
        ),
      ];

      // Initial sync: downloads and records track in DB
      final res1 = await libraryRepo.syncLibrary(
        rootFolderId: 'root_ts',
        rootFolderName: 'Music TS',
      );
      expect(res1.isSuccess, isTrue);
      expect(fakeDrive.downloadCallCount, equals(1));

      // Reset download log
      fakeDrive.downloadedFileIds.clear();
      fakeDrive.downloadCallCount = 0;

      // Second sync: remote modifiedTime still has sub-second precision (same second)
      // SQLite truncates to seconds, so local driveModifiedAt will have 0ms or second precision.
      final res2 = await libraryRepo.syncFromSavedFolder();
      expect(res2.isSuccess, isTrue);

      // Must NOT re-download because the second-precision timestamps match!
      expect(fakeDrive.downloadCallCount, equals(0));
      expect(fakeDrive.downloadedFileIds, isEmpty);

      // Verified as unchanged in discovered_files
      final lastSession = await libraryRepo.getLastSyncSession();

      final rows = await (db.select(db.discoveredFiles)
            ..where((tbl) => tbl.syncRunId.equals(lastSession!.syncRunId!)))
          .get();
      final row = rows.firstWhere((r) => r.driveFileId == 'df_subsecond');
      expect(row.isProcessed, isTrue);
      expect(row.processStatus, equals('unchanged'));
    });
  });
}
