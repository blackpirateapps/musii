import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:musii/app/bootstrap/providers.dart';
import 'package:musii/core/constants/app_constants.dart';
import 'package:musii/core/database/app_database.dart';
import 'package:musii/core/error/failures.dart';
import 'package:musii/core/filesystem/app_file_system.dart';
import 'package:musii/features/cache/data/repositories/cache_repository_impl.dart';
import 'package:musii/features/favorites/data/repositories/favorite_repository_impl.dart';
import 'package:musii/features/google_drive/data/repositories/google_drive_repository_impl.dart';
import 'package:musii/features/library/data/repositories/music_library_repository_impl.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/library/domain/entities/sync_progress.dart';
import 'package:musii/features/library/presentation/pages/artist_detail_page.dart';
import 'package:musii/features/library/presentation/widgets/song_row.dart';
import 'package:musii/features/metadata/domain/entities/parsed_audio_metadata.dart';
import 'package:musii/features/playback/domain/entities/playback_state.dart';
import 'package:musii/features/playlists/data/repositories/playlist_repository_impl.dart';
import 'package:musii/features/search/data/repositories/search_repository_impl.dart';
import 'package:musii/features/settings/data/repositories/settings_repository_impl.dart';

import '../../test/integration/google_drive_sync_regression_test.dart'
    show
        AbortAwareClient,
        OfflineArtworkDownloader,
        SwitchingAuthRepository,
        audio,
        content,
        cover,
        page,
        unavailable;
import '../../test/integration/library_sync_optimization_and_recovery_test.dart'
    show FakeMetadataExtractor;
import '../../test/unit/google_drive_repository_impl_test.dart'
    show MockAuthRepository;

// Audit probes assert the behavior observed on the audited revision.
void main() {
  late Directory directory;
  late AppDatabase db;
  late AppFileSystem fs;
  late GoogleDriveRepositoryImpl drive;
  late CacheRepositoryImpl cache;
  late MusicLibraryRepositoryImpl library;
  late FakeMetadataExtractor extractor;
  late List<Map<String, Object>> files;
  late List<Uri> listingRequests;
  late List<String> mediaRequests;
  late FutureOr<http.Response> Function(Uri) listing;
  late FutureOr<http.Response> Function(String) media;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('musii_round_two_');
    fs = AppFileSystem.instance;
    await fs.initialize(baseDir: directory);
  });
  tearDownAll(() => directory.delete(recursive: true));

  setUp(() async {
    for (final folder in [fs.audioCacheDir, fs.artworkCacheDir, fs.tempDir]) {
      await for (final entry in folder.list()) {
        await entry.delete(recursive: true);
      }
    }
    db = AppDatabase(NativeDatabase.memory());
    files = [audio('a'), audio('b')];
    listingRequests = [];
    mediaRequests = [];
    listing = (_) => page(files);
    media = (_) => content('abc');
    drive = GoogleDriveRepositoryImpl(
      authRepository: MockAuthRepository(),
      client: AbortAwareClient((request) async {
        final uri = request.url;
        if (uri.queryParameters['alt'] == 'media') {
          final id = uri.pathSegments.last;
          mediaRequests.add(id);
          return await media(id);
        }
        listingRequests.add(uri);
        return await listing(uri);
      }),
    );
    cache = CacheRepositoryImpl(database: db, driveRepository: drive);
    extractor = FakeMetadataExtractor();
    library = MusicLibraryRepositoryImpl(
      database: db,
      driveRepository: drive,
      metadataExtractor: extractor,
      artistArtworkDownloader: OfflineArtworkDownloader(db),
    );
  });
  tearDown(() async {
    library.dispose();
    await db.close();
  });

  Future<void> sync({
    MusicLibraryRepositoryImpl? repository,
    String root = 'music',
    void Function(SyncProgress)? onProgress,
  }) async {
    final result = await (repository ?? library).syncLibrary(
      rootFolderId: root,
      rootFolderName: root,
      onProgress: onProgress,
    );
    expect(result.isSuccess, isTrue, reason: result.failureOrNull?.toString());
  }

  Future<Track> track(String id) async =>
      (await library.getTrackByDriveFileId(id)).dataOrNull!;

  test(
    'a valid extensionless WAV downloads on every incremental sync',
    () async {
      const samples = 8000;
      final wav = ByteData(44 + 2 * samples);
      void tag(int offset, String value) {
        wav.buffer.asUint8List().setAll(offset, value.codeUnits);
      }

      tag(0, 'RIFF');
      wav.setUint32(4, wav.lengthInBytes - 8, Endian.little);
      tag(8, 'WAVEfmt ');
      wav.setUint32(16, 16, Endian.little);
      wav.setUint16(20, 1, Endian.little);
      wav.setUint16(22, 1, Endian.little);
      wav.setUint32(24, samples, Endian.little);
      wav.setUint32(28, 2 * samples, Endian.little);
      wav.setUint16(32, 2, Endian.little);
      wav.setUint16(34, 16, Endian.little);
      tag(36, 'data');
      wav.setUint32(40, 2 * samples, Endian.little);
      files = [
        {
          ...audio('a', name: 'Extensionless'),
          'mimeType': 'audio/wav',
          'size': '${wav.lengthInBytes}',
        },
        {
          ...audio('b', name: 'Control.wav'),
          'mimeType': 'audio/wav',
          'size': '${wav.lengthInBytes}',
        },
      ];
      media = (_) => http.Response.bytes(
        wav.buffer.asUint8List(),
        200,
        headers: {'content-type': 'audio/wav'},
      );
      final realMetadataLibrary = MusicLibraryRepositoryImpl(
        database: db,
        driveRepository: drive,
        artistArtworkDownloader: OfflineArtworkDownloader(db),
      );
      addTearDown(realMetadataLibrary.dispose);
      await sync(repository: realMetadataLibrary);
      expect((await track('a')).format, isEmpty);
      expect((await track('b')).format, 'WAV');
      for (var repeat = 0; repeat < 3; repeat++) {
        mediaRequests.clear();
        await sync(repository: realMetadataLibrary);
        expect(mediaRequests, ['a']);
        expect((await track('a')).format, isEmpty);
      }
    },
  );

  test('search exposes a SQLite failure to its error state', () async {
    await sync();
    final search = SearchRepositoryImpl(database: db);
    expect(
      (await search.search('Test Artist')).dataOrNull!.tracks,
      hasLength(2),
    );
    await db.customStatement('DROP TABLE tracks');
    expect((await search.search('Test Artist')).isFailure, isTrue);
    final container = ProviderContainer(
      overrides: [searchRepositoryProvider.overrideWithValue(search)],
    );
    addTearDown(container.dispose);
    container.read(searchQueryStateProvider.notifier).state = 'Test Artist';
    await expectLater(
      container.read(searchResultsProvider.future),
      throwsA(isA<DatabaseFailure>()),
    );
  });

  testWidgets('artist details expose only five of seven guest tracks', (
    tester,
  ) async {
    const artist = Artist(
      id: 'guest',
      name: 'Guest Artist',
      normalizedName: 'guest artist',
      trackCount: 7,
      artworkPath: '/fixture/artist_guest.jpg',
    );
    final tracks = List.generate(
      7,
      (index) => Track(
        id: 'guest-$index',
        driveFileId: 'drive-$index',
        sourceId: 'fixture',
        title: 'Guest Track ${index + 1}',
        normalizedTitle: 'guest track ${index + 1}',
      ),
    );
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          artistDetailProvider(artist.id).overrideWith(
            (ref) => Stream.value(
              ArtistWithAlbums(
                artist: artist,
                albums: const [],
                topTracks: tracks,
              ),
            ),
          ),
          playerStateProvider.overrideWith(
            (ref) => Stream.value(const PlayerStateSnapshot()),
          ),
        ],
        child: const CupertinoApp(home: ArtistDetailPage(artistId: 'guest')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('7 songs'), findsOneWidget);
    expect(find.byType(SongRow), findsNWidgets(5));
    expect(find.text('See All'), findsNothing);
    expect(find.text('Guest Track 6'), findsNothing);
    expect(find.text('Guest Track 7'), findsNothing);
  });

  test(
    'resume retains a track that returned to Drive after discovery stopped',
    () async {
      await sync();
      final favorites = FavoriteRepositoryImpl(database: db);
      final playlists = PlaylistRepositoryImpl(database: db);
      final playlist = (await playlists.createPlaylist('Keep')).dataOrNull!;
      expect((await favorites.toggleFavorite('track_b')).isSuccess, isTrue);
      expect(
        (await playlists.addTrackToPlaylist(playlist, 'track_b')).isSuccess,
        isTrue,
      );
      expect((await cache.pinTrackOffline('track_b')).isSuccess, isTrue);
      expect(
        (await cache.getOrDownloadTrack(await track('b'))).isSuccess,
        isTrue,
      );

      files = [audio('a')];
      await sync(
        onProgress: (progress) {
          if (progress.phase == SyncPhase.updatingDatabase) {
            unawaited(library.stopSync());
          }
        },
      );
      expect((await library.getLastSyncSession())?.phase, SyncPhase.stopped);
      expect(await cache.isTrackCached('track_b'), isTrue);
      expect(await favorites.watchIsFavorite('track_b').first, isTrue);

      files = [audio('a'), audio('b')];
      listingRequests.clear();
      listing = (_) => unavailable();
      expect((await library.resumeSync()).isFailure, isTrue);
      expect(await cache.isTrackCached('track_b'), isTrue);
      expect(await favorites.watchIsFavorite('track_b').first, isTrue);

      listing = (_) => page(files);
      expect((await library.resumeSync()).isSuccess, isTrue);
      expect(listingRequests, hasLength(2));
      expect((await library.getLastSyncSession())?.filesRemoved, 0);
      expect((await track('b')).isPinnedOffline, isTrue);
      expect(await favorites.watchIsFavorite('track_b').first, isTrue);
      expect(
        (await playlists.watchPlaylistTracks(playlist).first).single.id,
        'track_b',
      );
      expect(await cache.isTrackCached('track_b'), isTrue);
    },
  );

  test(
    'one account cannot prune a shared file another account indexed',
    () async {
      final auth = SwitchingAuthRepository();
      addTearDown(auth.changes.close);
      final accountLibrary = MusicLibraryRepositoryImpl(
        database: db,
        driveRepository: drive,
        authRepository: auth,
        metadataExtractor: extractor,
        artistArtworkDownloader: OfflineArtworkDownloader(db),
      );
      addTearDown(accountLibrary.dispose);
      var bobFiles = [audio('a')];
      listing = (uri) {
        final query = uri.queryParameters['q']!;
        expect(query.contains("'alice'") || query.contains("'bob'"), isTrue);
        return page(query.contains("'bob'") ? bobFiles : files);
      };
      files = [audio('a')];
      auth.switchTo('alice');
      await sync(repository: accountLibrary, root: 'alice');
      auth.switchTo('bob');
      await sync(repository: accountLibrary, root: 'bob');
      expect((await track('a')).sourceId, 'source_gdrive_alice');
      final favorite = FavoriteRepositoryImpl(database: db);
      expect((await favorite.toggleFavorite('track_a')).isSuccess, isTrue);

      auth.switchTo('alice');
      files = [];
      expect((await accountLibrary.syncFromSavedFolder()).isSuccess, isTrue);
      expect((await accountLibrary.getLastSyncSession())?.filesRemoved, 0);
      expect((await track('a')).sourceId, 'source_gdrive_bob');
      auth.switchTo('bob');
      expect(
        (await accountLibrary.getLastSyncSession())?.phase,
        SyncPhase.complete,
      );
      expect(await favorite.watchIsFavorite('track_a').first, isTrue);
      bobFiles = [];
      expect((await accountLibrary.syncFromSavedFolder()).isSuccess, isTrue);
      expect((await accountLibrary.getLastSyncSession())?.filesRemoved, 1);
      expect(
        (await accountLibrary.getTrackByDriveFileId('a')).dataOrNull,
        isNull,
      );
      expect(await favorite.watchIsFavorite('track_a').first, isFalse);
    },
  );

  test('failed folder switch overwrites the last working saved root', () async {
    await sync(root: 'working');
    final working = await db.select(db.musicSources).getSingle();
    expect(working.lastSyncedAt, isNotNull);
    listing = (uri) => uri.queryParameters['q']!.contains("'broken'")
        ? unavailable()
        : page(files);
    final failed = await library.syncLibrary(
      rootFolderId: 'broken',
      rootFolderName: 'Broken',
    );
    expect(failed.isFailure, isTrue);
    final source = await db.select(db.musicSources).getSingle();
    expect(source.rootFolderId, 'broken');
    expect(source.lastSyncedAt, working.lastSyncedAt);
    listingRequests.clear();
    expect((await library.syncFromSavedFolder()).isFailure, isTrue);
    expect(listingRequests.single.queryParameters['q'], contains("'broken'"));
    expect(await library.watchAllTracks().first, hasLength(2));
  });

  test('removing the last embedded cover hides available folder art until a second sync', () async {
    files = [audio('a'), audio('b'), cover('cover')];
    extractor.customMetadata['a.mp3'] = ParsedAudioMetadata(
      title: 'A',
      artist: 'Test Artist',
      album: 'Test Album',
      durationMs: 180000,
      format: 'MP3',
      fileSize: 3,
      artworkBytes: Uint8List.fromList([1, 2, 3]),
    );
    await sync();
    final initial = (await library.watchAllAlbums().first).single;
    expect(initial.artworkPath, contains('embedded_'));
    expect(mediaRequests, ['a', 'b']);
    files.removeAt(0);
    mediaRequests.clear();
    await sync();
    expect(mediaRequests, isEmpty);
    expect((await library.watchAllAlbums().first).single.artworkPath, isNull);
    expect((await track('b')).artworkPath, isNull);
    await sync();
    expect(mediaRequests, ['cover']);
    expect(
      (await library.watchAllAlbums().first).single.artworkPath,
      contains('drive_'),
    );
  });

  test('successive folder cover versions accumulate outside audio cache management', () async {
    for (var version = 0; version < 12; version++) {
      files = [
        audio('a'),
        {...cover('cover'), 'md5Checksum': 'cover-$version'},
      ];
      await sync();
    }
    files = [audio('a')];
    await sync();
    expect((await library.watchAllAlbums().first).single.artworkPath, isNull);
    expect(await fs.artworkCacheDir.list().toList(), hasLength(12));
    expect(await cache.getTotalCacheSize(), 0);
    expect((await cache.clearCache(includePinned: true)).isSuccess, isTrue);
    expect((await cache.evictLruCache(targetSizeBytes: 0)).isSuccess, isTrue);
    expect(await fs.artworkCacheDir.list().toList(), hasLength(12));
  });

  test(
    'download ignores saved cache setting and can exceed the reported default',
    () async {
      await sync();
      final settings = SettingsRepositoryImpl(database: db);
      await settings.setCacheLimitBytes(AppAudioConstants.minCacheSizeBytes);
      final saved = await settings.getCacheLimitBytes();
      expect(saved, lessThan(AppAudioConstants.defaultCacheSizeBytes));
      final file = (await cache.getOrDownloadTrack(await track('a')))
          .dataOrNull!;
      final handle = await file.open(mode: FileMode.append);
      await handle.truncate(AppAudioConstants.defaultCacheSizeBytes - 1);
      await handle.close();

      expect(
        (await cache.getOrDownloadTrack(await track('b'))).isSuccess,
        isTrue,
      );
      expect(await cache.isTrackCached('track_a'), isTrue);
      expect(
        await cache.getTotalCacheSize(),
        AppAudioConstants.defaultCacheSizeBytes + 2,
      );
    },
  );

  test(
    'failed clear rolls back SQLite but cannot restore its deleted audio files',
    () async {
      await sync();
      final a = (await cache.getOrDownloadTrack(await track('a'))).dataOrNull!;
      final b = (await cache.getOrDownloadTrack(await track('b'))).dataOrNull!;
      await db.customStatement("""
      CREATE TRIGGER fail_track_flag_update BEFORE UPDATE OF is_cached ON tracks
      WHEN OLD.is_cached = 1 AND NEW.is_cached = 0
      BEGIN SELECT RAISE(ABORT, 'fixture write error'); END
    """);
      expect((await cache.clearCache()).isFailure, isTrue);
      expect(await db.select(db.cacheEntries).get(), hasLength(2));
      expect((await track('a')).isCached, isTrue);
      expect((await track('b')).isCached, isTrue);
      final filesOnDisk = [await a.exists(), await b.exists()];
      expect(filesOnDisk, unorderedEquals([true, false]));
      final missingTrackId = filesOnDisk.first ? 'track_b' : 'track_a';
      expect(await cache.getCachedAudioFile(missingTrackId), isNull);
    },
  );

  test(
    'same-track coalescing and LRU pinned and playing exclusions hold',
    () async {
      files = [...files, audio('c')];
      await sync();
      mediaRequests.clear();
      final a = await track('a');
      final downloads = await Future.wait(
        List.generate(30, (_) => cache.getOrDownloadTrack(a)),
      );
      expect(downloads.every((result) => result.isSuccess), isTrue);
      expect(mediaRequests, ['a']);
      expect((await cache.pinTrackOffline('track_a')).isSuccess, isTrue);
      expect(
        (await cache.getOrDownloadTrack(await track('b'))).isSuccess,
        isTrue,
      );
      expect(
        (await cache.getOrDownloadTrack(await track('c'))).isSuccess,
        isTrue,
      );
      cache.setCurrentlyPlayingTrackId('track_b');
      expect((await cache.evictLruCache(targetSizeBytes: 0)).isSuccess, isTrue);
      expect(await cache.isTrackCached('track_a'), isTrue);
      expect(await cache.isTrackCached('track_b'), isTrue);
      expect(await cache.isTrackCached('track_c'), isFalse);
      expect(await cache.getTotalCacheSize(), 6);
    },
  );
}
