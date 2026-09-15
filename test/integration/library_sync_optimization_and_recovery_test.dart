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
    bool Function()? isCancelled,
  }) async {
    listCallCount++;
    if (isCancelled?.call() == true) {
      return const Result.success([]);
    }
    onProgress?.call(filesToReturn.where((f) => !f.isLrc).length);
    return Result.success(filesToReturn);
  }

  @override
  Future<Result<File, AppFailure>> downloadFile({
    required String fileId,
    required File destinationFile,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
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
      await Future<void>.delayed(const Duration(milliseconds: 50));

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
  });
}
