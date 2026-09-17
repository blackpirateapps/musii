import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/core/database/app_database.dart';
import 'package:musii/core/error/failures.dart';
import 'package:musii/core/filesystem/app_file_system.dart';
import 'package:musii/core/result/result.dart';
import 'package:musii/features/google_drive/domain/entities/drive_item.dart';
import 'package:musii/features/library/data/repositories/music_library_repository_impl.dart';
import 'package:musii/features/lyrics/data/repositories/lyrics_repository_impl.dart';
import 'package:musii/features/metadata/data/repositories/metadata_extractor_impl.dart';
import 'package:musii/features/metadata/domain/entities/parsed_audio_metadata.dart';
import 'package:musii/features/metadata/domain/services/metadata_normalization_service.dart';

class FakeDriveRepo implements GoogleDriveRepository {
  List<DriveFileItem> files = [];
  Map<String, String?> parentMap = {};
  final List<String> downloadedFileIds = [];

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
    if (folderParentMap != null) {
      folderParentMap.addAll(parentMap);
    }
    for (final f in files) {
      onFileDiscovered?.call(f);
    }
    onProgress?.call(files.where((f) => !f.isLrc && !f.isImage).length);
    return Result.success(files);
  }

  @override
  Future<Result<File, AppFailure>> downloadFile({
    required String fileId,
    required File destinationFile,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    downloadedFileIds.add(fileId);
    await destinationFile.create(recursive: true);
    await destinationFile.writeAsBytes([
      0xFF,
      0xD8,
      0xFF,
      0xE0,
    ]); // fake JPEG header
    return Result.success(destinationFile);
  }

  @override
  Future<Result<String, AppFailure>> downloadTextFile(String fileId) async {
    return const Result.success('');
  }

  @override
  Future<Result<List<int>, AppFailure>> readByteRange({
    required String fileId,
    required int start,
    required int end,
  }) async {
    return const Result.success([]);
  }
}

class FakeExtractor extends MetadataExtractor {
  final Map<String, ParsedAudioMetadata> customMetadata = {};

  @override
  Future<ParsedAudioMetadata> extractFromFile(
    File file, {
    String? fallbackName,
    int? knownFileSize,
  }) async {
    final name = fallbackName ?? 'track.mp3';
    return customMetadata[name] ??
        ParsedAudioMetadata(
          title: name,
          artist: 'Test Artist',
          album: 'Test Album',
          format: 'MP3',
          fileSize: 1000,
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory tempDir;
  late AppFileSystem fs;
  late FakeDriveRepo fakeDrive;
  late FakeExtractor fakeExtractor;
  late LyricsRepositoryImpl lyricsRepo;
  late MusicLibraryRepositoryImpl libraryRepo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('musii_folder_art_test_');
    fs = AppFileSystem.instance;
    await fs.initialize(baseDir: tempDir);

    fakeDrive = FakeDriveRepo();
    fakeExtractor = FakeExtractor();
    lyricsRepo = LyricsRepositoryImpl(database: db);

    libraryRepo = MusicLibraryRepositoryImpl(
      database: db,
      driveRepository: fakeDrive,
      metadataExtractor: fakeExtractor,
      lyricsRepository: lyricsRepo,
      fileSystem: fs,
    );
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test(
    'downloads and sets folder artwork when album has no embedded artwork',
    () async {
      fakeDrive.files = [
        const DriveFileItem(
          id: 'audio_1',
          name: 'Track 1.mp3',
          mimeType: 'audio/mpeg',
          size: 1000,
          parentFolderId: 'folder_album',
        ),
        const DriveFileItem(
          id: 'art_cover',
          name: 'Cover.jpg',
          mimeType: 'image/jpeg',
          size: 5000,
          parentFolderId: 'folder_album',
          isImage: true,
        ),
      ];

      fakeExtractor.customMetadata['Track 1.mp3'] = const ParsedAudioMetadata(
        title: 'Track 1',
        artist: 'Abbey Artists',
        album: 'Abbey Road',
        format: 'MP3',
        fileSize: 1000,
        artworkBytes: null, // No embedded artwork
      );

      final res = await libraryRepo.syncLibrary(
        rootFolderId: 'root',
        rootFolderName: 'Music',
      );

      expect(res.isSuccess, isTrue);
      expect(fakeDrive.downloadedFileIds, contains('art_cover'));

      final albums = await libraryRepo.watchAllAlbums().first;
      expect(albums, hasLength(1));
      final album = albums.first;
      expect(album.title, equals('Abbey Road'));
      expect(album.artworkPath, isNotNull);
      expect(File(album.artworkPath!).existsSync(), isTrue);

      final albumWithTracks = await libraryRepo.watchAlbum(album.id).first;
      expect(albumWithTracks, isNotNull);
      expect(albumWithTracks!.tracks, hasLength(1));
      expect(albumWithTracks.tracks.first.artworkPath, isNotNull);
      expect(
        File(albumWithTracks.tracks.first.artworkPath!).existsSync(),
        isTrue,
      );
    },
  );

  test('preserves embedded artwork when audio file contains it', () async {
    fakeDrive.files = [
      const DriveFileItem(
        id: 'audio_2',
        name: 'Track 2.mp3',
        mimeType: 'audio/mpeg',
        size: 1000,
        parentFolderId: 'folder_embedded',
      ),
      const DriveFileItem(
        id: 'folder_art',
        name: 'folder.png',
        mimeType: 'image/png',
        size: 5000,
        parentFolderId: 'folder_embedded',
        isImage: true,
      ),
    ];

    final embeddedBytes = Uint8List.fromList([1, 2, 3, 4]);
    fakeExtractor.customMetadata['Track 2.mp3'] = ParsedAudioMetadata(
      title: 'Track 2',
      artist: 'Self Titled Artist',
      album: 'Self Titled Album',
      format: 'MP3',
      fileSize: 1000,
      artworkBytes: embeddedBytes,
    );

    // Save embedded artwork to cache directory ahead of sync (simulating MetadataExtractor._saveArtworkIfNew)
    final key = MetadataNormalizationService.computeArtworkKey(
      'Self Titled Album',
      'Self Titled Artist',
    );
    final cacheFile = fs.getArtworkCacheFile(key);
    await cacheFile.create(recursive: true);
    await cacheFile.writeAsBytes(embeddedBytes);

    final res = await libraryRepo.syncLibrary(
      rootFolderId: 'root',
      rootFolderName: 'Music',
    );

    expect(res.isSuccess, isTrue);
    // Should NOT have downloaded the folder art because artwork file already existed from embedded tags
    expect(fakeDrive.downloadedFileIds, isNot(contains('folder_art')));

    final albums = await libraryRepo.watchAllAlbums().first;
    final album = albums.firstWhere((a) => a.title == 'Self Titled Album');
    expect(album.artworkPath, equals(cacheFile.path));
  });

  test('resolves artwork from parent folder in multi-disc layout', () async {
    fakeDrive.parentMap = {'folder_cd1': 'folder_parent_album'};

    fakeDrive.files = [
      const DriveFileItem(
        id: 'audio_cd1_1',
        name: 'CD1_Track1.mp3',
        mimeType: 'audio/mpeg',
        size: 1000,
        parentFolderId: 'folder_cd1',
      ),
      const DriveFileItem(
        id: 'art_parent_cover',
        name: 'cover.png',
        mimeType: 'image/png',
        size: 5000,
        parentFolderId: 'folder_parent_album',
        isImage: true,
      ),
    ];

    fakeExtractor.customMetadata['CD1_Track1.mp3'] = const ParsedAudioMetadata(
      title: 'CD1 Track 1',
      artist: 'Pink Floyd',
      album: 'The Wall',
      format: 'MP3',
      fileSize: 1000,
      artworkBytes: null,
    );

    final res = await libraryRepo.syncLibrary(
      rootFolderId: 'root',
      rootFolderName: 'Music',
    );

    expect(res.isSuccess, isTrue);
    expect(fakeDrive.downloadedFileIds, contains('art_parent_cover'));

    final albums = await libraryRepo.watchAllAlbums().first;
    expect(albums, hasLength(1));
    expect(albums.first.title, equals('The Wall'));
    expect(albums.first.artworkPath, isNotNull);
    expect(File(albums.first.artworkPath!).existsSync(), isTrue);
  });

  test(
    'falls back to non-standard image name when standard names absent',
    () async {
      fakeDrive.files = [
        const DriveFileItem(
          id: 'audio_special',
          name: 'Song.mp3',
          mimeType: 'audio/mpeg',
          size: 1000,
          parentFolderId: 'folder_special',
        ),
        const DriveFileItem(
          id: 'art_custom',
          name: 'sleeve_scan.webp',
          mimeType: 'image/webp',
          size: 5000,
          parentFolderId: 'folder_special',
          isImage: true,
        ),
      ];

      fakeExtractor.customMetadata['Song.mp3'] = const ParsedAudioMetadata(
        title: 'Song',
        artist: 'Indie Artist',
        album: 'Indie Release',
        format: 'MP3',
        fileSize: 1000,
        artworkBytes: null,
      );

      final res = await libraryRepo.syncLibrary(
        rootFolderId: 'root',
        rootFolderName: 'Music',
      );

      expect(res.isSuccess, isTrue);
      expect(fakeDrive.downloadedFileIds, contains('art_custom'));

      final albums = await libraryRepo.watchAllAlbums().first;
      expect(albums, hasLength(1));
      expect(albums.first.artworkPath, isNotNull);
      expect(File(albums.first.artworkPath!).existsSync(), isTrue);
    },
  );
}
