import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/app/bootstrap/providers.dart';
import 'package:musii/core/database/app_database.dart';
import 'package:musii/core/filesystem/app_file_system.dart';
import 'package:musii/features/cache/data/repositories/cache_repository_impl.dart';
import 'package:musii/features/favorites/data/repositories/favorite_repository_impl.dart';
import 'package:musii/features/google_drive/data/repositories/google_drive_repository_impl.dart';
import 'package:musii/features/library/data/repositories/music_library_repository_impl.dart';
import 'package:musii/features/library/domain/entities/sync_progress.dart';
import 'package:musii/features/metadata/domain/entities/parsed_audio_metadata.dart';
import 'package:musii/features/playlists/data/repositories/playlist_repository_impl.dart';
import 'package:musii/features/recently_played/data/repositories/recently_played_repository_impl.dart';
import 'package:musii/features/search/data/repositories/search_repository_impl.dart';

import '../../test/integration/google_drive_sync_regression_test.dart'
    show
        AbortAwareClient,
        OfflineArtworkDownloader,
        audio,
        content,
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
  late SearchRepositoryImpl search;
  late PlaylistRepositoryImpl playlists;
  late FakeMetadataExtractor extractor;
  late MusicLibraryRepositoryImpl library;
  late CacheRepositoryImpl cache;
  late List<Map<String, Object>> listing;
  late Set<String> failingMedia;
  late List<String> mediaRequests;
  late List<int> listingOffsets;
  final timestamp = DateTime.utc(2026, 11, 26);

  TracksCompanion track(int index, {String? title}) => TracksCompanion.insert(
    id: 't$index',
    driveFileId: 'file$index',
    sourceId: 'source_gdrive',
    title: title ?? 'Stress Song $index',
    normalizedTitle: (title ?? 'Stress Song $index').toLowerCase(),
    durationMs: const Value(180000),
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('musii_library_probe_');
    await AppFileSystem.instance.initialize(baseDir: directory);
  });
  tearDownAll(() => directory.delete(recursive: true));

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    search = SearchRepositoryImpl(database: db);
    playlists = PlaylistRepositoryImpl(database: db);
    extractor = FakeMetadataExtractor();
    listing = [];
    failingMedia = {};
    mediaRequests = [];
    listingOffsets = [];
    final drive = GoogleDriveRepositoryImpl(
      authRepository: MockAuthRepository(),
      client: AbortAwareClient((request) async {
        final uri = request.url;
        if (uri.queryParameters['alt'] == 'media') {
          final id = uri.pathSegments.last;
          mediaRequests.add(id);
          return failingMedia.contains(id) ? unavailable() : content('abc');
        }
        final offset = int.parse(uri.queryParameters['pageToken'] ?? '0');
        listingOffsets.add(offset);
        final end = (offset + 100).clamp(0, listing.length);
        return page(
          listing.sublist(offset, end),
          next: end < listing.length ? '$end' : null,
        );
      }),
    );
    cache = CacheRepositoryImpl(database: db, driveRepository: drive);
    library = MusicLibraryRepositoryImpl(
      database: db,
      driveRepository: drive,
      metadataExtractor: extractor,
      artistArtworkDownloader: OfflineArtworkDownloader(db),
    );
  });
  tearDown(() => db.close());

  Future<void> sync() async {
    final result = await library.syncLibrary(
      rootFolderId: 'music',
      rootFolderName: 'Music',
    );
    expect(result.isSuccess, isTrue, reason: result.failureOrNull?.toString());
  }

  test('10,000-track browsing and broad search scale control', () async {
    const size = 10000;
    await db.batch((batch) {
      batch.insertAll(db.tracks, List.generate(size, track));
    });
    final watch = Stopwatch()..start();
    expect(await library.watchAllTracks().first, hasLength(size));
    final browseMs = watch.elapsedMilliseconds;
    watch.reset();
    final broad = (await search.search('stress song')).dataOrNull!;
    expect(broad.tracks, hasLength(size));
    final broadMs = watch.elapsedMilliseconds;
    watch.reset();
    final exact = (await search.search('stress song 42')).dataOrNull!;
    expect(exact.tracks.first.id, 't42');
    final exactMs = watch.elapsedMilliseconds;
    for (final query in ['%', '_']) {
      expect((await search.search(query)).dataOrNull!.tracks, hasLength(size));
    }
    debugPrintSynchronously(
      '10,000 tracks, browse ${browseMs}ms, broad ${broadMs}ms, exact ${exactMs}ms',
    );
  });

  test('sync 1,205 tracks then resume failed changes without pruning early', () async {
    const size = 1205;
    listing = List.generate(size, (index) => audio('a$index'));
    final watch = Stopwatch()..start();
    await sync();
    final initialMs = watch.elapsedMilliseconds;
    expect(listingOffsets, List.generate(13, (index) => index * 100));
    expect(mediaRequests, hasLength(size));
    expect(await library.watchAllTracks().first, hasLength(size));
    expect((await library.watchAllAlbums().first).single.trackCount, size);
    expect((await library.watchAllArtists().first).single.trackCount, size);

    watch.reset();
    mediaRequests.clear();
    listingOffsets.clear();
    await sync();
    final unchangedMs = watch.elapsedMilliseconds;
    expect(mediaRequests, isEmpty);
    expect(listingOffsets, hasLength(13));

    listing
      ..removeLast()
      ..[0] = audio('a0', checksum: 'changed')
      ..add(audio('new'));
    failingMedia.add('new');
    mediaRequests.clear();
    final failed = await library.syncLibrary(
      rootFolderId: 'music',
      rootFolderName: 'Music',
    );
    expect(failed.isFailure, isTrue);
    expect(mediaRequests, ['a0', 'new']);
    final interrupted = await library.getLastSyncSession();
    expect(interrupted?.phase, SyncPhase.failed);
    expect(
      (await library.getTrackByDriveFileId('a1204')).dataOrNull,
      isNotNull,
    );

    failingMedia.clear();
    listingOffsets.clear();
    mediaRequests.clear();
    expect((await library.resumeSync()).isSuccess, isTrue);
    expect(listingOffsets, List.generate(13, (index) => index * 100));
    expect(mediaRequests, ['new']);
    final resumed = await library.getLastSyncSession();
    expect(resumed?.phase, SyncPhase.complete);
    expect(resumed?.filesAdded, 1);
    expect(resumed?.filesUpdated, 1);
    expect(resumed?.filesRemoved, 1);
    expect(await library.watchAllTracks().first, hasLength(size));
    expect((await library.watchAllArtists().first).single.trackCount, size);
    debugPrintSynchronously(
      '1,205 tracks over 13 pages, initial ${initialMs}ms, unchanged ${unchangedMs}ms',
    );
  });

  test(
    'non-Latin albums and artists collapse and exact searches miss them',
    () async {
      listing = [audio('a'), audio('b'), audio('c')];
      extractor.customMetadata.addAll({
        'a.mp3': const ParsedAudioMetadata(
          title: '夜空',
          artist: '青葉市子',
          album: '檻髪',
          durationMs: 180000,
          format: 'MP3',
          fileSize: 3,
        ),
        'b.mp3': const ParsedAudioMetadata(
          title: '朝日',
          artist: '坂本龍一',
          album: '音楽図鑑',
          durationMs: 180000,
          format: 'MP3',
          fileSize: 3,
        ),
        'c.mp3': const ParsedAudioMetadata(
          title: "Don't Stop",
          artist: 'Control Artist',
          album: 'Control Album',
          durationMs: 180000,
          format: 'MP3',
          fileSize: 3,
        ),
      });
      await sync();
      final tracks = await library.watchAllTracks().first;
      final nonLatin = tracks.where((track) => track.id != 'track_c').toList();
      expect(nonLatin.map((track) => track.normalizedTitle).toSet(), {''});
      expect(nonLatin.map((track) => track.artistId).toSet(), {'artist_'});
      expect(nonLatin.map((track) => track.albumId).toSet(), {'album_::'});
      expect(await library.watchAllAlbums().first, hasLength(2));
      expect(await library.watchAllArtists().first, hasLength(2));
      expect((await search.search('夜空')).dataOrNull!.tracks, isEmpty);
      expect((await search.search('青葉市子')).dataOrNull!.artists, isEmpty);
      expect((await search.search('檻髪')).dataOrNull!.albums, isEmpty);
      expect((await search.search("Don't Stop")).dataOrNull!.tracks, isEmpty);
      expect(
        (await search.search('Dont Stop')).dataOrNull!.tracks.single.id,
        'track_c',
      );
    },
  );

  test(
    'untagged artists with a common prefix merge distinct same-title releases',
    () async {
      listing = [audio('a'), audio('b')];
      extractor.customMetadata.addAll({
        'a.mp3': const ParsedAudioMetadata(
          title: 'Alpha Song',
          artist: 'The Band',
          album: 'Live',
          durationMs: 180000,
          format: 'MP3',
          fileSize: 3,
        ),
        'b.mp3': const ParsedAudioMetadata(
          title: 'Beta Song',
          artist: 'The Bandits',
          album: 'Live',
          durationMs: 180000,
          format: 'MP3',
          fileSize: 3,
        ),
      });
      await sync();
      final album = (await library.watchAllAlbums().first).single;
      expect(album.trackCount, 2);
      expect(
        (await library.watchAlbum(album.id).first)!.tracks
            .map((t) => t.artistName)
            .toSet(),
        {'The Band', 'The Bandits'},
      );
    },
  );

  test(
    'a track-only change does not re-emit an open album or artist',
    () async {
      listing = [audio('a')];
      await sync();
      final album = (await library.watchAllAlbums().first).single;
      final artist = (await library.watchAllArtists().first).single;
      final albumStates = <bool>[];
      final artistStates = <bool>[];
      final albums = library.watchAlbum(album.id).listen((data) {
        albumStates.add(data!.tracks.single.isPinnedOffline);
      });
      final artists = library.watchArtist(artist.id).listen((data) {
        artistStates.add(data!.topTracks.single.isPinnedOffline);
      });
      addTearDown(albums.cancel);
      addTearDown(artists.cancel);
      for (
        var tries = 0;
        tries < 100 && (albumStates.isEmpty || artistStates.isEmpty);
        tries++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(albumStates, [false]);
      expect(artistStates, [false]);
      await (db.update(db.tracks)..where((row) => row.id.equals('track_a')))
          .write(const TracksCompanion(isPinnedOffline: Value(true)));
      expect(
        (await library.watchAllTracks().first).single.isPinnedOffline,
        isTrue,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(albumStates, [false]);
      expect(artistStates, [false]);
      expect(
        (await library.watchAlbum(album.id).first)!
            .tracks
            .single
            .isPinnedOffline,
        isTrue,
      );
    },
  );

  test(
    'a visited search remains stale after playlist creation and deletion',
    () async {
      final container = ProviderContainer(
        overrides: [searchRepositoryProvider.overrideWithValue(search)],
      );
      addTearDown(container.dispose);
      final query = container.read(searchQueryStateProvider.notifier);
      query.state = 'Stress Playlist';
      expect(
        (await container.read(searchResultsProvider.future)).playlists,
        isEmpty,
      );
      final playlist = (await playlists.createPlaylist('Stress Playlist'))
          .dataOrNull!;
      expect(
        (await search.search('Stress Playlist'))
            .dataOrNull!
            .playlists
            .single
            .id,
        playlist,
      );
      expect(
        (await container.read(searchResultsProvider.future)).playlists,
        isEmpty,
      );
      query.state = 'Stress Playlis';
      expect(
        (await container.read(searchResultsProvider.future))
            .playlists
            .single
            .id,
        playlist,
      );
      expect((await playlists.deletePlaylist(playlist)).isSuccess, isTrue);
      expect(
        (await container.read(searchResultsProvider.future))
            .playlists
            .single
            .id,
        playlist,
      );
      expect(
        (await search.search('Stress Playlis')).dataOrNull!.playlists,
        isEmpty,
      );
    },
  );

  test('playlist duplicate rows are all removed by a track removal', () async {
    await db.into(db.tracks).insert(track(0));
    final playlist = (await playlists.createPlaylist('Stress Playlist'))
        .dataOrNull!;
    final adds = await Future.wait(
      List.generate(24, (_) => playlists.addTrackToPlaylist(playlist, 't0')),
    );
    expect(adds.every((result) => result.isSuccess), isTrue);
    expect(await playlists.watchPlaylistTracks(playlist).first, hasLength(24));
    expect(
      (await playlists.removeTrackFromPlaylist(playlist, 't0')).isSuccess,
      isTrue,
    );
    expect(await playlists.watchPlaylistTracks(playlist).first, isEmpty);
  });

  test(
    'concurrent favorite toggles lose operations against the unique constraint',
    () async {
      await db.into(db.tracks).insert(track(0));
      final favorite = FavoriteRepositoryImpl(database: db);
      final results = await Future.wait(
        List.generate(20, (_) => favorite.toggleFavorite('t0')),
      );
      expect(results.where((result) => result.isSuccess), hasLength(1));
      expect(results.where((result) => result.isFailure), hasLength(19));
      expect(await favorite.watchIsFavorite('t0').first, isTrue);
    },
  );

  test('offline pin reports success although its download fails', () async {
    listing = [audio('a')];
    await sync();
    failingMedia.add('a');
    final failedEntry = db
        .select(db.cacheEntries)
        .watch()
        .firstWhere((rows) => rows.any((row) => row.state == 'failed'));
    expect((await cache.pinTrackOffline('track_a')).isSuccess, isTrue);
    expect(await failedEntry.timeout(const Duration(seconds: 3)), hasLength(1));
    expect(await cache.getCachedAudioFile('track_a'), isNull);
    expect(
      (await library.getTrackById('track_a')).dataOrNull!.isPinnedOffline,
      isTrue,
    );
    expect(
      (await library.getTrackById('track_a')).dataOrNull!.isCached,
      isFalse,
    );
  });

  test(
    'offline cache accepts same-size bytes with the wrong Drive checksum',
    () async {
      listing = [audio('a', checksum: 'd16fb36f0911f878998c136191af705e')];
      await sync();
      final indexed = (await library.getTrackById('track_a')).dataOrNull!;
      final cached = await cache.getOrDownloadTrack(indexed);
      expect(cached.isSuccess, isTrue);
      expect(await cached.dataOrNull!.readAsString(), 'abc');
      expect(await cache.isTrackCached(indexed.id), isTrue);
    },
  );

  test('30 replays hide older distinct recently played songs', () async {
    await db.batch((batch) {
      batch.insertAll(db.tracks, List.generate(12, track));
      batch.insertAll(db.recentlyPlayed, [
        for (var i = 0; i < 41; i++)
          RecentlyPlayedCompanion.insert(
            id: 'recent$i',
            trackId: 't${i < 11 ? i + 1 : 0}',
            playedAt: timestamp.add(Duration(seconds: i)),
          ),
      ]);
    });
    final history = RecentlyPlayedRepositoryImpl(database: db);
    expect((await history.watchRecentlyPlayed().first).map((t) => t.id), [
      't0',
    ]);
    expect(await history.watchRecentlyPlayed(limit: 41).first, hasLength(12));
  });
}
