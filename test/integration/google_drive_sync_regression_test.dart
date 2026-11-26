import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:musii/core/database/app_database.dart';
import 'package:musii/core/error/failures.dart';
import 'package:musii/core/result/result.dart';
import 'package:musii/features/authentication/domain/entities/auth_user.dart';
import 'package:musii/core/filesystem/app_file_system.dart';
import 'package:musii/features/cache/data/repositories/cache_repository_impl.dart';
import 'package:musii/features/google_drive/data/repositories/google_drive_repository_impl.dart';
import 'package:musii/features/library/data/repositories/music_library_repository_impl.dart';
import 'package:musii/features/library/domain/entities/sync_progress.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/lyrics/data/repositories/lyrics_repository_impl.dart';
import 'package:musii/features/metadata/data/datasources/artist_artwork_downloader.dart';

import 'library_sync_optimization_and_recovery_test.dart'
    show FakeMetadataExtractor;
import '../unit/google_drive_repository_impl_test.dart' show MockAuthRepository;

Map<String, Object> audio(String id, {String? name, String checksum = 'old'}) =>
    {
      'id': id,
      'name': name ?? '$id.mp3',
      'mimeType': 'audio/mpeg',
      'size': '3',
      'modifiedTime': '2026-09-15T12:00:00Z',
      'md5Checksum': checksum,
    };

Map<String, Object> folder(String id) => {
  'id': id,
  'name': id,
  'mimeType': 'application/vnd.google-apps.folder',
};

Map<String, Object> lrc(String id, {String checksum = 'original'}) => {
  'id': id,
  'name': 'a.lrc',
  'md5Checksum': checksum,
  'mimeType': 'text/plain',
};

Map<String, Object> cover(String id) => {
  'id': id,
  'name': 'cover.jpg',
  'mimeType': 'image/jpeg',
};

http.Response page(
  List<Map<String, Object>> files, {
  String? next,
  bool? incomplete,
}) => http.Response(
  jsonEncode({
    'files': files,
    'nextPageToken': ?next,
    'incompleteSearch': ?incomplete,
  }),
  200,
  headers: {'content-type': 'application/json'},
);

http.Response content(String body) => http.Response(
  body,
  200,
  headers: {'content-type': 'application/octet-stream'},
);

http.Response unavailable([int status = 503]) => http.Response(
  '{"error":{"message":"fixture error"}}',
  status,
  headers: {'content-type': 'application/json'},
);

class AbortAwareClient extends http.BaseClient {
  final Future<http.Response> Function(http.BaseRequest) respond;

  AbortAwareClient(this.respond);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final pending = respond(request);
    final abort = request is http.AbortableRequest
        ? request.abortTrigger
        : null;
    final response = abort == null
        ? await pending
        : await Future.any([
            pending,
            abort.then<http.Response>(
              (_) => throw http.RequestAbortedException(request.url),
            ),
          ]);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

class SwitchingAuthRepository extends MockAuthRepository {
  final changes = StreamController<AuthUser?>.broadcast();
  AuthUser? user;

  void switchTo(String? id) {
    user = id == null ? null : AuthUser(id: id, email: '$id@example.test');
    changes.add(user);
  }

  @override
  Future<Result<AuthUser?, AppFailure>> getCurrentUser() async =>
      Result.success(user);

  @override
  Stream<AuthUser?> watchCurrentUser() => changes.stream;
}

class OfflineArtworkDownloader extends ArtistArtworkDownloader {
  OfflineArtworkDownloader(AppDatabase db)
    : super(database: db, fileSystem: AppFileSystem.instance);

  @override
  Future<void> downloadMissingArtworks(List<Artist> artists) async {}
}

void main() {
  late AppDatabase db;
  late GoogleDriveRepositoryImpl drive;
  late MusicLibraryRepositoryImpl library;
  late LyricsRepositoryImpl lyrics;
  late List<Uri> listings;
  late List<String> downloads;
  late FutureOr<http.Response> Function(Uri) list;
  late FutureOr<http.Response> Function(String) media;
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('musii_audit_');
    await AppFileSystem.instance.initialize(baseDir: directory);
  });
  tearDownAll(() => directory.delete(recursive: true));

  setUp(() async {
    for (final dir in [
      AppFileSystem.instance.audioCacheDir,
      AppFileSystem.instance.artworkCacheDir,
    ]) {
      await for (final entry in dir.list()) {
        await entry.delete(recursive: true);
      }
    }
    db = AppDatabase(NativeDatabase.memory());
    listings = [];
    downloads = [];
    list = (_) => page([audio('a'), audio('b')]);
    media = (_) => content('old');
    drive = GoogleDriveRepositoryImpl(
      authRepository: MockAuthRepository(),
      client: AbortAwareClient((request) async {
        final uri = request.url;
        if (uri.queryParameters['alt'] == 'media') {
          final id = uri.pathSegments.last;
          downloads.add(id);
          return await media(id);
        }
        listings.add(uri);
        if (uri.path.endsWith('/drives')) {
          return http.Response(
            jsonEncode({
              'drives': [
                {'id': 'shared', 'name': 'Shared Music'},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return await list(uri);
      }),
    );
    lyrics = LyricsRepositoryImpl(database: db);
    library = MusicLibraryRepositoryImpl(
      database: db,
      driveRepository: drive,
      metadataExtractor: FakeMetadataExtractor(),
      artistArtworkDownloader: OfflineArtworkDownloader(db),
    );
  });
  tearDown(() => db.close());

  Future<Set<String>> trackIds() async =>
      (await db.select(db.tracks).get()).map((row) => row.driveFileId).nonNulls.toSet();

  Future<void> seed() async {
    expect(
      (await library.syncLibrary(
        rootFolderId: 'music',
        rootFolderName: 'Music',
      )).isSuccess,
      isTrue,
    );
    expect(await trackIds(), {'a', 'b'});
  }

  test('folder picker follows all pages and lists shared drives', () async {
    list = (uri) => uri.queryParameters.containsKey('pageToken')
        ? page([folder('later')])
        : page(List.generate(100, (index) => folder('f$index')), next: 'p2');
    final result = await drive.listFolders();
    expect(result.dataOrNull?.length, 102);
    expect(
      result.dataOrNull?.map((row) => row.id),
      containsAll(['later', 'shared']),
    );
    expect(listings, hasLength(3));
    expect(listings.first.queryParameters['fields'], contains('nextPageToken'));
  });

  test(
    'recursive paging handles an empty initial page with a next token',
    () async {
      list = (uri) => uri.queryParameters['pageToken'] == 'p2'
          ? page([audio('a'), audio('b')])
          : page([], next: 'p2');
      await seed();
      expect(listings.map((uri) => uri.queryParameters['pageToken']), [
        null,
        'p2',
      ]);
    },
  );

  test(
    'stop between pages and resume retries the folder before pruning',
    () async {
      await seed();
      final firstPageRequested = Completer<void>();
      final releaseFirstPage = Completer<http.Response>();
      list = (uri) {
        if (uri.queryParameters['pageToken'] == 'p2') return page([audio('b')]);
        firstPageRequested.complete();
        return releaseFirstPage.future;
      };
      listings.clear();
      final stopping = library.syncLibrary(
        rootFolderId: 'music',
        rootFolderName: 'Music',
      );
      await firstPageRequested.future;
      await library.stopSync();
      releaseFirstPage.complete(page([audio('a')], next: 'p2'));
      expect((await stopping).isSuccess, isTrue);
      final stopped = await library.getLastSyncSession();
      expect(stopped?.phase, SyncPhase.stopped);
      expect(await trackIds(), {'a', 'b'});
      final run = await (db.select(
        db.syncRuns,
      )..where((t) => t.id.equals(stopped!.syncRunId!))).getSingle();
      expect(run.pendingFoldersJson, '["music"]');
      expect(run.visitedFoldersJson, '[]');
      list = (uri) => uri.queryParameters['pageToken'] == 'p2'
          ? page([audio('b')])
          : page([audio('a')], next: 'p2');
      expect((await library.resumeSync()).isSuccess, isTrue);
      expect(listings, hasLength(3));
      expect(await trackIds(), {'a', 'b'});
      expect((await library.getLastSyncSession())?.filesRemoved, 0);
    },
  );

  test('incompleteSearch prevents deletion reconciliation', () async {
    await seed();
    list = (_) => page([audio('a')], incomplete: true);
    expect((await library.syncFromSavedFolder()).isFailure, isTrue);
    expect(await trackIds(), {'a', 'b'});
    expect(
      listings.last.queryParameters['fields'],
      contains('incompleteSearch'),
    );
  });

  test(
    'retry after an incomplete folder discards its stale first-page items',
    () async {
      await seed();
      list = (uri) => uri.queryParameters['pageToken'] == 'p2'
          ? unavailable()
          : page([audio('b')], next: 'p2');
      expect((await library.syncFromSavedFolder()).isFailure, isTrue);
      expect(await trackIds(), {'a', 'b'});
      list = (_) => page([audio('a')]);
      expect((await library.resumeSync()).isSuccess, isTrue);
      expect(await trackIds(), {'a'});
      expect((await library.getLastSyncSession())?.filesDiscovered, 1);
    },
  );

  test(
    'force resume processes remaining tracks and keeps completed status',
    () async {
      await seed();
      downloads.clear();
      var requestedStop = false;
      final forced = await library.syncLibrary(
        rootFolderId: 'music',
        rootFolderName: 'Music',
        forceSync: true,
        onProgress: (progress) {
          if (!requestedStop &&
              progress.phase == SyncPhase.extractingMetadata &&
              progress.filesProcessed == 1) {
            requestedStop = true;
            unawaited(library.stopSync());
          }
        },
      );
      expect(forced.isSuccess, isTrue);
      expect(requestedStop, isTrue);
      expect((await library.getLastSyncSession())?.phase, SyncPhase.stopped);
      expect((await library.resumeSync()).isSuccess, isTrue);
      expect(downloads, ['a', 'b']);
      expect((await library.getLastSyncSession())?.filesUpdated, 2);
      final completed = await library.getLastSyncSession();
      final rows = await (db.select(
        db.discoveredFiles,
      )..where((row) => row.syncRunId.equals(completed!.syncRunId!))).get();
      expect(rows.map((row) => row.processStatus), everyElement('updated'));
    },
  );

  test('scanner reports each unique audio file exactly once', () async {
    final progress = <SyncProgress>[];
    expect(
      (await library.syncLibrary(
        rootFolderId: 'music',
        rootFolderName: 'Music',
        onProgress: progress.add,
      )).isSuccess,
      isTrue,
    );
    expect(
      progress
          .where((p) => p.phase == SyncPhase.scanning)
          .map((p) => p.filesDiscovered),
      [0, 2],
    );
    expect(progress.last.filesDiscovered, 2);
  });

  test(
    'successful retry clears the failure message in live progress and SQLite',
    () async {
      list = (_) => unavailable();
      expect(
        (await library.syncLibrary(
          rootFolderId: 'music',
          rootFolderName: 'Music',
        )).isFailure,
        isTrue,
      );
      final oldMessage = (await library.getLastSyncSession())!.errorMessage;
      expect(oldMessage, isNotNull);
      list = (_) => page([audio('a')]);
      expect((await library.resumeSync()).isSuccess, isTrue);
      expect((await library.getLastSyncSession())?.errorMessage, isNull);
      expect((await library.watchSyncProgress().first).errorMessage, isNull);
    },
  );

  test('all audio downloads failing leaves a resumable run and preserves last-sync time', () async {
    media = (_) => unavailable(429);
    final result = await library.syncLibrary(
      rootFolderId: 'music',
      rootFolderName: 'Music',
    );
    expect(result.isFailure, isTrue);
    expect(await trackIds(), isEmpty);
    final progress = (await library.getLastSyncSession())!;
    expect(progress.phase, SyncPhase.failed);
    expect(progress.filesProcessed, 2);
    expect(progress.errorsCount, 2);
    expect(progress.isResumable, isTrue);
    expect((await db.select(db.musicSources).getSingle()).lastSyncedAt, isNull);
  });

  test(
    'sidecar-only edits and removals update lyrics without downloading audio',
    () async {
      list = (_) => page([audio('a'), lrc('lyric')]);
      media = (id) =>
          content(id == 'lyric' ? '[00:01.00]Original lyric' : 'old');
      expect(
        (await library.syncLibrary(
          rootFolderId: 'music',
          rootFolderName: 'Music',
        )).isSuccess,
        isTrue,
      );
      expect(
        (await lyrics.getLyricsForTrack('track_a'))?.rawText,
        contains('Original lyric'),
      );
      downloads.clear();
      list = (_) => page([audio('a'), lrc('lyric', checksum: 'edited')]);
      media = (id) => content(id == 'lyric' ? '[00:01.00]Edited lyric' : 'old');
      expect((await library.syncFromSavedFolder()).isSuccess, isTrue);
      expect(downloads, ['lyric']);
      expect(
        (await lyrics.getLyricsForTrack('track_a'))?.rawText,
        contains('Edited lyric'),
      );
      list = (_) => page([audio('a')]);
      downloads.clear();
      expect((await library.syncFromSavedFolder()).isSuccess, isTrue);
      expect(await lyrics.getLyricsForTrack('track_a'), isNull);
      expect(downloads, isEmpty);
    },
  );

  test('sidecar failure leaves a resumable work item', () async {
    list = (_) => page([audio('a')]);
    expect(
      (await library.syncLibrary(
        rootFolderId: 'music',
        rootFolderName: 'Music',
      )).isSuccess,
      isTrue,
    );
    list = (_) => page([audio('a'), lrc('lyric')]);
    media = (_) => unavailable();
    downloads.clear();
    expect((await library.syncFromSavedFolder()).isFailure, isTrue);
    expect((await library.getLastSyncSession())?.errorsCount, 1);
    expect(await lyrics.getLyricsForTrack('track_a'), isNull);
    expect(downloads, ['lyric']);
    media = (_) => content('[00:01.00]Recovered lyric');
    downloads.clear();
    expect((await library.resumeSync()).isSuccess, isTrue);
    expect(downloads, ['lyric']);
    expect(
      (await lyrics.getLyricsForTrack('track_a'))?.rawText,
      contains('Recovered lyric'),
    );
  });

  test(
    'Drive filename containing a slash imports through safe staging',
    () async {
      list = (_) => page([audio('a', name: 'Artist / Song.mp3')]);
      expect(
        (await library.syncLibrary(
          rootFolderId: 'music',
          rootFolderName: 'Music',
        )).isSuccess,
        isTrue,
      );
      expect(await trackIds(), {'a'});
      expect((await library.getLastSyncSession())?.errorsCount, 0);
    },
  );

  test('paused progress subscriber receives the new run', () async {
    await seed();
    final values = StreamIterator(library.watchSyncProgress());
    expect(await values.moveNext(), isTrue);
    final firstRun = values.current.syncRunId;
    expect((await library.syncFromSavedFolder()).isSuccess, isTrue);
    expect((await library.getLastSyncSession())!.syncRunId, isNot(firstRun));
    SyncProgress? completed;
    while (await values.moveNext().timeout(const Duration(seconds: 2))) {
      if (values.current.isComplete && values.current.syncRunId != firstRun) {
        completed = values.current;
        break;
      }
    }
    expect(completed?.phase, SyncPhase.complete);
    await values.cancel();
  });

  test(
    'pinned media refreshes with new bytes and remote removal cleans disk',
    () async {
      await seed();
      final cache = CacheRepositoryImpl(database: db, driveRepository: drive);
      final initialTrack = (await library.getTrackByDriveFileId('a'))
          .dataOrNull!;
      expect((await cache.getOrDownloadTrack(initialTrack)).isSuccess, isTrue);
      expect((await cache.pinTrackOffline('track_a')).isSuccess, isTrue);
      final cached = await cache.getCachedAudioFile('track_a');
      expect(await cached?.readAsString(), 'old');
      expect(await cache.getTotalCacheSize(), 3);
      list = (_) => page([audio('a', checksum: 'new'), audio('b')]);
      media = (_) => content('new');
      expect((await library.syncFromSavedFolder()).isSuccess, isTrue);
      final track = (await library.getTrackByDriveFileId('a')).dataOrNull!;
      expect(
        (await (db.select(
              db.tracks,
            )..where((row) => row.driveFileId.equals("a"))).getSingle())
            .driveMd5Checksum,
        'new',
      );
      expect(track.isPinnedOffline, isTrue);
      final playbackFile = await cache.getOrDownloadTrack(track);
      expect(await playbackFile.dataOrNull?.readAsString(), 'new');
      expect(await cached?.exists(), isFalse);
      list = (_) => page([audio('b')]);
      expect((await library.syncFromSavedFolder()).isSuccess, isTrue);
      expect(await trackIds(), {'b'});
      expect(await db.select(db.cacheEntries).get(), isEmpty);
      expect(await cache.getTotalCacheSize(), 0);
      expect(await playbackFile.dataOrNull?.exists(), isFalse);
    },
  );

  test(
    'stopping before database reconciliation preserves existing tracks',
    () async {
      await seed();
      list = (_) => page([audio('a')]);
      Future<void>? requestedStop;
      final phases = <SyncPhase>[];
      expect(
        (await library.syncLibrary(
          rootFolderId: 'music',
          rootFolderName: 'Music',
          onProgress: (p) {
            phases.add(p.phase);
            if (p.phase == SyncPhase.updatingDatabase) {
              requestedStop = library.stopSync();
            }
          },
        )).isSuccess,
        isTrue,
      );
      expect(requestedStop, isNotNull);
      await requestedStop;
      expect(phases.last, SyncPhase.stopped);
      expect(await trackIds(), {'a', 'b'});
    },
  );

  test(
    'complete-discovery resume uses persisted parent-folder artwork',
    () async {
      list = (uri) => uri.queryParameters['q']!.startsWith("'disc'")
          ? page([audio('a')])
          : page([cover('parent-cover'), folder('disc')]);
      Future<void>? requestedStop;
      final first = await library.syncLibrary(
        rootFolderId: 'music',
        rootFolderName: 'Music',
        onProgress: (p) {
          if (p.phase == SyncPhase.extractingMetadata &&
              requestedStop == null) {
            requestedStop = library.stopSync();
          }
        },
      );
      expect(first.isSuccess, isTrue);
      expect(requestedStop, isNotNull);
      await requestedStop;
      expect((await library.getLastSyncSession())?.phase, SyncPhase.stopped);
      expect(
        (await db.select(db.driveFolders).getSingle()).parentFolderId,
        'music',
      );
      listings.clear();
      expect((await library.resumeSync()).isSuccess, isTrue);
      expect(listings, isEmpty);
      expect(downloads, ['a', 'parent-cover']);
      expect((await db.select(db.tracks).getSingle()).artworkPath, isNotNull);
    },
  );

  test('force scan refreshes folder artwork bytes', () async {
    list = (_) => page([audio('a'), cover('cover')]);
    expect(
      (await library.syncLibrary(
        rootFolderId: 'music',
        rootFolderName: 'Music',
      )).isSuccess,
      isTrue,
    );
    final track = await db.select(db.tracks).getSingle();
    expect(await File(track.artworkPath!).readAsString(), 'old');
    downloads.clear();
    media = (_) => content('new');
    expect(
      (await library.syncFromSavedFolder(forceSync: true)).isSuccess,
      isTrue,
    );
    expect(downloads, ['a', 'cover']);
    expect(await File(track.artworkPath!).readAsString(), 'new');
  });

  test(
    'discovered-file write failure prevents completion and local pruning',
    () async {
      await seed();
      await db.customStatement(
        "CREATE TRIGGER reject_discovery BEFORE INSERT ON discovered_files "
        "BEGIN SELECT RAISE(ABORT, 'audit checkpoint failure'); END",
      );
      list = (_) => page([audio('a')]);
      final outcome = await library.syncFromSavedFolder();
      expect(outcome.isFailure, isTrue);
      final progress = (await library.getLastSyncSession())!;
      final run = await (db.select(
        db.syncRuns,
      )..where((row) => row.id.equals(progress.syncRunId!))).getSingle();
      expect(run.discoveryCompleted, isFalse);
      expect(await db.select(db.discoveredFiles).get(), isEmpty);
      expect(await trackIds(), {'a', 'b'});
    },
  );

  test('startup recovery resumes at the first unfinished folder', () async {
    final requested = Completer<void>();
    final release = Completer<http.Response>();
    list = (uri) {
      if (uri.queryParameters['q']!.startsWith("'disc'")) {
        requested.complete();
        return release.future;
      }
      return page([audio('a'), folder('disc')]);
    };
    final syncing = library.syncLibrary(
      rootFolderId: 'music',
      rootFolderName: 'Music',
    );
    await requested.future;
    final run = await db.select(db.syncRuns).getSingle();
    expect(run.status, 'running');
    expect(run.pendingFoldersJson, '["disc"]');
    expect(run.visitedFoldersJson, '["music"]');
    expect(
      (await db.select(db.discoveredFiles).get()).map((row) => row.driveFileId),
      ['a'],
    );
    final snapshot = File('${directory.path}/crash.sqlite');
    await db.customStatement("VACUUM INTO '${snapshot.path}'");
    await library.stopSync();
    release.complete(page([audio('b')]));
    expect((await syncing).isSuccess, isTrue);

    final restoredDb = AppDatabase(NativeDatabase(snapshot));
    try {
      final restored = MusicLibraryRepositoryImpl(
        database: restoredDb,
        driveRepository: drive,
        metadataExtractor: FakeMetadataExtractor(),
        artistArtworkDownloader: OfflineArtworkDownloader(restoredDb),
      );
      listings.clear();
      list = (_) => page([audio('b')]);
      final completed = restored.watchSyncProgress().firstWhere(
        (p) => p.isComplete,
      );
      await restored.recoverInterruptedSyncIfNeeded();
      expect(
        (await completed.timeout(const Duration(seconds: 2))).filesDiscovered,
        2,
      );
      expect(
        listings.single.queryParameters['q'],
        contains("'disc' in parents"),
      );
    } finally {
      await restoredDb.close();
    }
  });

  test('stop aborts in-flight media and a new folder can start', () async {
    final entered = Completer<void>();
    final release = Completer<http.Response>();
    media = (id) {
      if (id == 'a') {
        entered.complete();
        return release.future;
      }
      return content('old');
    };
    final current = library.syncLibrary(
      rootFolderId: 'music',
      rootFolderName: 'Music',
    );
    await entered.future;
    await library.stopSync();
    list = (_) => page([audio('b')]);
    final next = library.syncLibrary(
      rootFolderId: 'other',
      rootFolderName: 'Other',
    );
    expect(
      (await current.timeout(const Duration(seconds: 2))).isSuccess,
      isTrue,
    );
    expect((await next.timeout(const Duration(seconds: 2))).isSuccess, isTrue);
    expect(listings.last.queryParameters['q'], contains("'other' in parents"));
    expect(await trackIds(), {'b'});
    release.complete(content('old'));
  });

  test(
    'account switch isolates roots, interrupted runs, and deletion',
    () async {
      final auth = SwitchingAuthRepository();
      addTearDown(auth.changes.close);
      final accountLibrary = MusicLibraryRepositoryImpl(
        database: db,
        driveRepository: drive,
        authRepository: auth,
        metadataExtractor: FakeMetadataExtractor(),
        artistArtworkDownloader: OfflineArtworkDownloader(db),
      );
      addTearDown(accountLibrary.dispose);
      auth.switchTo('alice');
      list = (_) => page([audio('a')]);
      expect(
        (await accountLibrary.syncLibrary(
          rootFolderId: 'alice-folder',
          rootFolderName: 'Alice',
        )).isSuccess,
        isTrue,
      );

      final requested = Completer<void>();
      final response = Completer<http.Response>();
      list = (_) {
        requested.complete();
        return response.future;
      };
      final interrupted = accountLibrary.syncFromSavedFolder();
      await requested.future;
      auth.switchTo('bob');
      expect(
        (await interrupted.timeout(const Duration(seconds: 2))).isSuccess,
        isTrue,
      );
      expect(await accountLibrary.getLastSyncSession(), isNull);
      final listCount = listings.length;
      expect((await accountLibrary.syncFromSavedFolder()).isFailure, isTrue);
      expect((await accountLibrary.resumeSync()).isFailure, isTrue);
      await accountLibrary.recoverInterruptedSyncIfNeeded();
      expect(listings, hasLength(listCount));

      list = (_) => page([audio('b')]);
      expect(
        (await accountLibrary.syncLibrary(
          rootFolderId: 'bob-folder',
          rootFolderName: 'Bob',
        )).isSuccess,
        isTrue,
      );
      expect(
        (await accountLibrary.getLastSyncSession())?.rootFolderId,
        'bob-folder',
      );
      expect(await trackIds(), {'a', 'b'});
      expect(
        (await db.select(db.musicSources).get()).map((row) => row.accountEmail),
        unorderedEquals(['alice@example.test', 'bob@example.test']),
      );
      auth.switchTo(null);
      expect(await accountLibrary.getLastSyncSession(), isNull);
      expect((await accountLibrary.syncFromSavedFolder()).isFailure, isTrue);
      response.complete(page([]));
    },
  );

  test('remote deletion rolls back relationships on failure and removes them on resume', () async {
    list = (_) => page([audio('a'), audio('b'), lrc('lyric')]);
    media = (id) => content(id == 'lyric' ? '[00:01.00]A lyric' : 'old');
    await seed();
    final now = DateTime.now();
    await db.batch((batch) {
      batch.insert(
        db.playlists,
        PlaylistsCompanion.insert(
          id: 'playlist',
          name: 'Music',
          trackCount: const Value(2),
          createdAt: now,
          updatedAt: now,
        ),
      );
      batch.insertAll(db.playlistTracks, [
        PlaylistTracksCompanion.insert(
          id: 'member-a',
          playlistId: 'playlist',
          trackId: 'track_a',
          sortOrder: 0,
          addedAt: now,
        ),
        PlaylistTracksCompanion.insert(
          id: 'member-b',
          playlistId: 'playlist',
          trackId: 'track_b',
          sortOrder: 1,
          addedAt: now,
        ),
      ]);
      batch.insert(
        db.favorites,
        FavoritesCompanion.insert(
          id: 'favorite',
          trackId: 'track_a',
          addedAt: now,
        ),
      );
      batch.insert(
        db.recentlyPlayed,
        RecentlyPlayedCompanion.insert(
          id: 'history',
          trackId: 'track_a',
          playedAt: now,
        ),
      );
      batch.insert(
        db.playbackQueue,
        PlaybackQueueCompanion.insert(
          id: 'queued',
          trackId: 'track_a',
          sortOrder: 0,
          addedAt: now,
        ),
      );
      batch.insert(
        db.playbackStates,
        PlaybackStatesCompanion.insert(
          id: 'current',
          currentTrackId: const Value('track_a'),
          updatedAt: now,
        ),
      );
    });
    await db.customStatement("""
      CREATE TRIGGER reject_prune BEFORE DELETE ON tracks
      WHEN OLD.id = 'track_a'
      BEGIN SELECT RAISE(ABORT, 'simulated prune failure'); END
    """);
    list = (_) => page([audio('b')]);
    expect((await library.syncFromSavedFolder()).isFailure, isTrue);
    expect(await trackIds(), {'a', 'b'});
    expect(await db.select(db.playlistTracks).get(), hasLength(2));
    expect(await db.select(db.favorites).get(), hasLength(1));
    expect(await lyrics.getLyricsForTrack('track_a'), isNotNull);
    await db.customStatement('DROP TRIGGER reject_prune');

    expect((await library.resumeSync()).isSuccess, isTrue);
    expect(await trackIds(), {'b'});
    expect((await db.select(db.playlists).getSingle()).trackCount, 1);
    final membership = await db.select(db.playlistTracks).getSingle();
    expect(membership.trackId, 'track_b');
    expect(membership.sortOrder, 0);
    expect(await db.select(db.favorites).get(), isEmpty);
    expect(await db.select(db.recentlyPlayed).get(), isEmpty);
    expect(await db.select(db.playbackQueue).get(), isEmpty);
    expect(
      (await db.select(db.playbackStates).getSingle()).currentTrackId,
      isNull,
    );
    expect(await lyrics.getLyricsForTrack('track_a'), isNull);
  });

  test(
    'shared-drive traversal follows shortcut targets and avoids folder cycles',
    () async {
      Map<String, Object> shortcut(String id, String target, String mime) => {
        'id': id,
        'name': id,
        'mimeType': 'application/vnd.google-apps.shortcut',
        'shortcutDetails': {'targetId': target, 'targetMimeType': mime},
      };
      list = (uri) {
        expect(uri.queryParameters['supportsAllDrives'], 'true');
        if (uri.path.endsWith('/shared-audio')) {
          return http.Response(
            jsonEncode(audio('shared-audio')),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        expect(uri.queryParameters['includeItemsFromAllDrives'], 'true');
        final query = uri.queryParameters['q']!;
        return query.startsWith("'shared'")
            ? page([
                shortcut(
                  'Open music',
                  'disc',
                  'application/vnd.google-apps.folder',
                ),
              ])
            : page([
                shortcut(
                  'Back',
                  'shared',
                  'application/vnd.google-apps.folder',
                ),
                shortcut('Song.mp3', 'shared-audio', 'audio/mpeg'),
              ]);
      };
      expect(
        (await library.syncLibrary(
          rootFolderId: 'shared',
          rootFolderName: 'Shared',
        )).isSuccess,
        isTrue,
      );
      expect(listings, hasLength(3));
      expect(await trackIds(), {'shared-audio'});
      expect(downloads, ['shared-audio']);
    },
  );

  test(
    'large unchanged folder batches status writes and skips audio downloads',
    () async {
      const count = 1001;
      final ids = List.generate(count, (index) => 'large-$index');
      final now = DateTime.utc(2026, 9, 15, 12);
      await db.batch((batch) {
        batch.insertAll(
          db.tracks,
          ids.map(
            (id) => TracksCompanion.insert(
              id: 'track_$id',
              driveFileId: Value(id),
              sourceId: 'source_gdrive',
              title: id,
              normalizedTitle: id,
              format: const Value('MP3'),
              fileSize: const Value(3),
              driveModifiedAt: Value(now),
              driveMd5Checksum: const Value('old'),
              createdAt: now,
              updatedAt: now,
            ),
          ),
        );
      });
      list = (uri) {
        final offset = int.parse(uri.queryParameters['pageToken'] ?? '0');
        return page(
          ids.skip(offset).take(100).map(audio).toList(),
          next: offset + 100 < count ? '${offset + 100}' : null,
        );
      };
      expect(
        (await library.syncLibrary(
          rootFolderId: 'music',
          rootFolderName: 'Music',
        )).isSuccess,
        isTrue,
      );
      expect((await library.getLastSyncSession())?.filesProcessed, count);
      expect(
        (await db.select(db.discoveredFiles).get()).every(
          (row) => row.isProcessed,
        ),
        isTrue,
      );
      expect(downloads, isEmpty);
    },
  );

  test(
    'an in-flight old cache download cannot publish after a newer sync',
    () async {
      await seed();
      final cache = CacheRepositoryImpl(database: db, driveRepository: drive);
      final track = (await library.getTrackByDriveFileId('a')).dataOrNull!;
      final requested = Completer<void>();
      final oldMedia = Completer<http.Response>();
      media = (id) {
        requested.complete();
        return oldMedia.future;
      };
      final downloading = cache.getOrDownloadTrack(track);
      await requested.future;
      list = (_) => page([audio('a', checksum: 'new'), audio('b')]);
      media = (_) => content('new');
      expect((await library.syncFromSavedFolder()).isSuccess, isTrue);
      oldMedia.complete(content('old'));
      expect((await downloading).isFailure, isTrue);
      expect(await cache.getCachedAudioFile(track.id), isNull);
      expect(
        await (await cache.getOrDownloadTrack(track)).dataOrNull
            ?.readAsString(),
        'new',
      );
    },
  );
}
