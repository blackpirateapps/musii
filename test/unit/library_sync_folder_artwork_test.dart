import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/core/database/app_database.dart';
import 'package:musii/core/error/failures.dart';
import 'package:musii/core/filesystem/app_file_system.dart';
import 'package:musii/core/result/result.dart';
import 'package:musii/features/favorites/data/repositories/favorite_repository_impl.dart';
import 'package:musii/features/google_drive/domain/entities/drive_item.dart';
import 'package:musii/features/library/data/repositories/music_library_repository_impl.dart';
import 'package:musii/features/lyrics/data/repositories/lyrics_repository_impl.dart';
import 'package:musii/features/metadata/data/repositories/metadata_extractor_impl.dart';
import 'package:musii/features/metadata/domain/entities/parsed_audio_metadata.dart';
import 'package:musii/features/metadata/domain/services/metadata_normalization_service.dart';
import 'package:musii/features/playlists/data/repositories/playlist_repository_impl.dart';
import 'package:musii/features/recently_played/data/repositories/recently_played_repository_impl.dart';
import 'package:musii/features/search/data/repositories/search_repository_impl.dart';

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

  test('persists folder artwork on tracks and resolves in watchAllTracks and other repositories even with differing artist and albumArtist', () async {
    fakeDrive.files = [
      const DriveFileItem(
        id: 'audio_feat',
        name: 'CollabSong.mp3',
        mimeType: 'audio/mpeg',
        size: 1000,
        parentFolderId: 'folder_collab',
      ),
      const DriveFileItem(
        id: 'art_collab',
        name: 'folder.jpg',
        mimeType: 'image/jpeg',
        size: 5000,
        parentFolderId: 'folder_collab',
        isImage: true,
      ),
    ];

    fakeExtractor.customMetadata['CollabSong.mp3'] = const ParsedAudioMetadata(
      title: 'Collab Song',
      artist: 'Main Artist feat. Guest',
      albumArtist: 'Main Artist',
      album: 'Collab Album',
      format: 'MP3',
      fileSize: 1000,
      artworkBytes: null,
    );

    final res = await libraryRepo.syncLibrary(
      rootFolderId: 'root',
      rootFolderName: 'Music',
    );

    expect(res.isSuccess, isTrue);
    expect(fakeDrive.downloadedFileIds, contains('art_collab'));

    // 1. Verify track in database has artwork_path persisted
    final dbTracks = await db.select(db.tracks).get();
    expect(dbTracks, hasLength(1));
    expect(dbTracks.first.artworkPath, isNotNull);
    expect(File(dbTracks.first.artworkPath!).existsSync(), isTrue);

    // 2. Verify watchAllTracks (used in Home, Songs tab, Queue) resolves artworkPath
    final allTracks = await libraryRepo.watchAllTracks().first;
    expect(allTracks, hasLength(1));
    expect(allTracks.first.artworkPath, equals(dbTracks.first.artworkPath));

    // 3. Verify watchAlbum resolves artworkPath
    final albums = await libraryRepo.watchAllAlbums().first;
    expect(albums, hasLength(1));
    final albumWithTracks = await libraryRepo.watchAlbum(albums.first.id).first;
    expect(
      albumWithTracks!.tracks.first.artworkPath,
      equals(dbTracks.first.artworkPath),
    );

    // 4. Verify search repository resolves track artworkPath
    final searchRepo = SearchRepositoryImpl(database: db, fileSystem: fs);
    final searchRes = await searchRepo.search('Collab');
    expect(searchRes.isSuccess, isTrue);
    expect(searchRes.dataOrNull!.tracks, hasLength(1));
    expect(
      searchRes.dataOrNull!.tracks.first.artworkPath,
      equals(dbTracks.first.artworkPath),
    );

    // 5. Verify favorites repository resolves track artworkPath
    final favRepo = FavoriteRepositoryImpl(database: db, fileSystem: fs);
    await favRepo.toggleFavorite(allTracks.first.id);
    final favTracks = await favRepo.watchFavoriteTracks().first;
    expect(favTracks, hasLength(1));
    expect(favTracks.first.artworkPath, equals(dbTracks.first.artworkPath));

    // 6. Verify recently played repository resolves track artworkPath
    final recentRepo = RecentlyPlayedRepositoryImpl(
      database: db,
      fileSystem: fs,
    );
    await recentRepo.recordPlayback(allTracks.first.id, 1000, true);
    final recentTracks = await recentRepo.watchRecentlyPlayed().first;
    expect(recentTracks, hasLength(1));
    expect(recentTracks.first.artworkPath, equals(dbTracks.first.artworkPath));

    // 7. Verify playlist repository resolves track artworkPath
    final playlistRepo = PlaylistRepositoryImpl(database: db, fileSystem: fs);
    final createPlRes = await playlistRepo.createPlaylist('Favorites List');
    expect(createPlRes.isSuccess, isTrue);
    await playlistRepo.addTrackToPlaylist(
      createPlRes.dataOrNull!,
      allTracks.first.id,
    );
    final plTracks = await playlistRepo
        .watchPlaylistTracks(createPlRes.dataOrNull!)
        .first;
    expect(plTracks, hasLength(1));
    expect(plTracks.first.artworkPath, equals(dbTracks.first.artworkPath));
  });

  test('schema v10 backfills artwork_path from albums to tracks', () async {
    await db
        .into(db.albums)
        .insert(
          AlbumsCompanion.insert(
            id: 'album_v10',
            albumKey: 'v10_album::test',
            title: 'V10 Album',
            normalizedTitle: 'v10 album',
            artistName: const Value('Test Artist'),
            trackCount: const Value(1),
            artworkPath: const Value('/path/to/v10_art.jpg'),
          ),
        );

    await db
        .into(db.tracks)
        .insert(
          TracksCompanion.insert(
            id: 'track_v10',
            driveFileId: 'df_v10',
            sourceId: 'src_v10',
            title: 'V10 Track',
            normalizedTitle: 'v10 track',
            albumId: const Value('album_v10'),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

    var track = (await (db.select(
      db.tracks,
    )..where((t) => t.id.equals('track_v10'))).getSingle());
    expect(track.artworkPath, isNull);

    // Run the migration statement
    await db.customStatement('''
      UPDATE tracks 
      SET artwork_path = (SELECT albums.artwork_path FROM albums WHERE albums.id = tracks.album_id)
      WHERE tracks.album_id IS NOT NULL;
    ''');

    track = (await (db.select(
      db.tracks,
    )..where((t) => t.id.equals('track_v10'))).getSingle());
    expect(track.artworkPath, equals('/path/to/v10_art.jpg'));
  });

  test(
    'reconcileDuplicateAlbums propagates artwork_path to all tracks',
    () async {
      // Seed two duplicate albums, one with artworkPath
      await db
          .into(db.albums)
          .insert(
            AlbumsCompanion.insert(
              id: 'album_dup_1',
              albumKey: 'dup_key_1',
              title: 'Duplicate Album',
              normalizedTitle: 'duplicate album',
              artistName: const Value('Artist A'),
              artworkPath: const Value('/path/to/dup_art.png'),
            ),
          );
      await db
          .into(db.albums)
          .insert(
            AlbumsCompanion.insert(
              id: 'album_dup_2',
              albumKey: 'dup_key_2',
              title: 'Duplicate Album',
              normalizedTitle: 'duplicate album',
              artistName: const Value('Artist A'),
            ),
          );

      // Track 1 points to album 1 (with null artwork on track)
      await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              id: 'track_dup_1',
              driveFileId: 'df_dup_1',
              sourceId: 'src_dup',
              title: 'Track 1',
              normalizedTitle: 'track 1',
              albumId: const Value('album_dup_1'),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      // Track 2 points to album 2 (with null artwork on track)
      await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              id: 'track_dup_2',
              driveFileId: 'df_dup_2',
              sourceId: 'src_dup',
              title: 'Track 2',
              normalizedTitle: 'track 2',
              albumId: const Value('album_dup_2'),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      // Reconcile
      await db.reconcileDuplicateAlbums();

      // Verify both tracks now have artworkPath = /path/to/dup_art.png
      final t1 = await (db.select(
        db.tracks,
      )..where((t) => t.id.equals('track_dup_1'))).getSingle();
      final t2 = await (db.select(
        db.tracks,
      )..where((t) => t.id.equals('track_dup_2'))).getSingle();
      expect(t1.artworkPath, equals('/path/to/dup_art.png'));
      expect(t2.artworkPath, equals('/path/to/dup_art.png'));
    },
  );
}
