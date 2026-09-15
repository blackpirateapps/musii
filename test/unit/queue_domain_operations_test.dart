import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musii/core/database/app_database.dart';
import 'package:musii/core/error/failures.dart';
import 'package:musii/core/result/result.dart';
import 'package:musii/features/cache/domain/entities/cache_entry.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/playback/data/repositories/playback_repository_impl.dart';
import 'package:musii/features/playback/domain/entities/playback_state.dart';
import 'package:musii/features/recently_played/data/repositories/recently_played_repository_impl.dart';

class MockCacheRepository extends Mock implements CacheRepository {}
class MockRecentlyPlayedRepository extends Mock implements RecentlyPlayedRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const trackA = Track(
    id: 'track_a',
    driveFileId: 'df_a',
    sourceId: 's1',
    title: 'Song A',
    normalizedTitle: 'song a',
    artistName: 'Artist A',
    albumName: 'Album A',
    durationMs: 180000,
  );

  const trackB = Track(
    id: 'track_b',
    driveFileId: 'df_b',
    sourceId: 's1',
    title: 'Song B',
    normalizedTitle: 'song b',
    artistName: 'Artist B',
    albumName: 'Album B',
    durationMs: 200000,
  );

  const trackC = Track(
    id: 'track_c',
    driveFileId: 'df_c',
    sourceId: 's1',
    title: 'Song C',
    normalizedTitle: 'song c',
    artistName: 'Artist C',
    albumName: 'Album C',
    durationMs: 210000,
  );

  const trackD = Track(
    id: 'track_d',
    driveFileId: 'df_d',
    sourceId: 's1',
    title: 'Song D',
    normalizedTitle: 'song d',
    artistName: 'Artist D',
    albumName: 'Album D',
    durationMs: 220000,
  );

  const trackE = Track(
    id: 'track_e',
    driveFileId: 'df_e',
    sourceId: 's1',
    title: 'Song E',
    normalizedTitle: 'song e',
    artistName: 'Artist E',
    albumName: 'Album E',
    durationMs: 230000,
  );

  const trackF = Track(
    id: 'track_f',
    driveFileId: 'df_f',
    sourceId: 's1',
    title: 'Song F',
    normalizedTitle: 'song f',
    artistName: 'Artist F',
    albumName: 'Album F',
    durationMs: 240000,
  );

  group('QueueItem & PlayerStateSnapshot Domain Logic', () {
    test('QueueItem equality, identity, and factory creation', () {
      final item1 = QueueItem.fromTrack(trackA, 'qi_1');
      final item2 = QueueItem.fromTrack(trackA, 'qi_1');
      final item3 = QueueItem.fromTrack(trackA, 'qi_2');
      final item4 = QueueItem.fromTrack(trackA);

      expect(item1, equals(item2));
      expect(item1.hashCode, equals(item2.hashCode));
      expect(item1, isNot(equals(item3)));
      expect(item4.id, startsWith('qi_'));
      expect(item4.track.title, equals('Song A'));
    });

    test('PlayerStateSnapshot derives effectiveQueueItems and upNextItems', () {
      const itemA = QueueItem(id: 'qa', track: trackA);
      const itemB = QueueItem(id: 'qb', track: trackB);
      const itemC = QueueItem(id: 'qc', track: trackC);

      const snapshot = PlayerStateSnapshot(
        currentTrack: trackA,
        queueItems: [itemA, itemB, itemC],
        queueIndex: 0,
      );

      expect(snapshot.currentQueueItem?.id, equals('qa'));
      expect(snapshot.upNextItems.length, equals(2));
      expect(snapshot.upNextItems[0].track.title, equals('Song B'));
      expect(snapshot.upNextItems[1].track.title, equals('Song C'));
      expect(snapshot.upNextTracks.map((t) => t.title), equals(['Song B', 'Song C']));
      expect(snapshot.hasNext, isTrue);
      expect(snapshot.hasPrevious, isFalse);
    });

    test('PlayerStateSnapshot copyWith preserves queueItems correctly', () {
      const itemA = QueueItem(id: 'qa', track: trackA);
      const itemB = QueueItem(id: 'qb', track: trackB);

      const snapshot = PlayerStateSnapshot(
        currentTrack: trackA,
        queueItems: [itemA, itemB],
        queueIndex: 0,
      );

      final updated = snapshot.copyWith(queueIndex: 1, currentTrack: trackB);
      expect(updated.queueIndex, equals(1));
      expect(updated.currentTrack?.title, equals('Song B'));
      expect(updated.currentQueueItem?.id, equals('qb'));
      expect(updated.upNextItems.isEmpty, isTrue);
    });
  });

  group('MusiiAudioHandler Play Next, Add to Queue & Reordering Semantics', () {
    late AppDatabase db;
    late MusiiAudioHandler handler;
    late MockCacheRepository mockCache;
    late MockRecentlyPlayedRepository mockRecentlyPlayed;

    setUpAll(() {
      registerFallbackValue(trackA);
    });

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      mockCache = MockCacheRepository();
      mockRecentlyPlayed = MockRecentlyPlayedRepository();

      when(() => mockCache.setCurrentlyPlayingTrackId(any())).thenReturn(null);
      when(() => mockCache.isTrackCached(any())).thenAnswer((_) async => false);
      when(() => mockCache.getOrDownloadTrack(any())).thenAnswer(
        (_) async => const Result.failure(CacheFailure('mock test failure')),
      );
      when(() => mockRecentlyPlayed.recordPlayback(any(), any(), any()))
          .thenAnswer((_) async {});

      handler = MusiiAudioHandler(
        cacheRepository: mockCache,
        recentlyPlayedRepository: mockRecentlyPlayed,
        database: db,
      );
    });

    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await db.close();
    });

    test('Play Next preserves sequential requested order (A -> D -> E -> B -> C)', () async {
      // 1. Initialize queue with A (playing), B, C
      await handler.loadAndPlayTrack(
        trackA,
        queue: [trackA, trackB, trackC],
        queueIndex: 0,
      );

      expect(handler.currentSnapshot.queue.map((t) => t.title).toList(),
          equals(['Song A', 'Song B', 'Song C']));

      // 2. Play Next D -> [A, D, B, C]
      handler.playNext(trackD);
      expect(handler.currentSnapshot.queue.map((t) => t.title).toList(),
          equals(['Song A', 'Song D', 'Song B', 'Song C']));

      // 3. Play Next E -> [A, D, E, B, C]
      handler.playNext(trackE);
      expect(handler.currentSnapshot.queue.map((t) => t.title).toList(),
          equals(['Song A', 'Song D', 'Song E', 'Song B', 'Song C']));

      // 4. Play Next F -> [A, D, E, F, B, C]
      handler.playNext(trackF);
      expect(handler.currentSnapshot.queue.map((t) => t.title).toList(),
          equals(['Song A', 'Song D', 'Song E', 'Song F', 'Song B', 'Song C']));
    });

    test('Add to Queue (playLast) appends items to the end', () async {
      await handler.loadAndPlayTrack(
        trackA,
        queue: [trackA, trackB],
        queueIndex: 0,
      );

      handler.playLast(trackC);
      handler.playLast(trackD);

      expect(handler.currentSnapshot.queue.map((t) => t.title).toList(),
          equals(['Song A', 'Song B', 'Song C', 'Song D']));
    });

    test('Reorder queue moves item and preserves current playing track', () async {
      await handler.loadAndPlayTrack(
        trackA,
        queue: [trackA, trackB, trackC, trackD, trackE],
        queueIndex: 0,
      );

      // Move D (oldIndex = 3) above B (newIndex = 1) -> [A, D, B, C, E]
      handler.reorderQueue(3, 1);

      expect(handler.currentSnapshot.queue.map((t) => t.title).toList(),
          equals(['Song A', 'Song D', 'Song B', 'Song C', 'Song E']));
      expect(handler.currentSnapshot.currentTrack?.title, equals('Song A'));
      expect(handler.currentSnapshot.queueIndex, equals(0));
    });

    test('Move queue item by queueItemId', () async {
      const itemA = QueueItem(id: 'item_a', track: trackA);
      const itemB = QueueItem(id: 'item_b', track: trackB);
      const itemC = QueueItem(id: 'item_c', track: trackC);
      const itemD = QueueItem(id: 'item_d', track: trackD);

      await handler.loadAndPlayTrack(
        trackA,
        queueItems: [itemA, itemB, itemC, itemD],
        queueIndex: 0,
      );

      handler.moveQueueItem('item_d', 1);

      expect(handler.currentSnapshot.queueItems.map((q) => q.id).toList(),
          equals(['item_a', 'item_d', 'item_b', 'item_c']));
    });

    test('Duplicate tracks in queue can be distinguished and removed individually', () async {
      const itemA1 = QueueItem(id: 'item_a1', track: trackA);
      const itemB = QueueItem(id: 'item_b', track: trackB);
      const itemA2 = QueueItem(id: 'item_a2', track: trackA);
      const itemC = QueueItem(id: 'item_c', track: trackC);

      // Queue: [A (item_a1), B (item_b), A (item_a2), C (item_c)]
      await handler.loadAndPlayTrack(
        trackA,
        queueItems: [itemA1, itemB, itemA2, itemC],
        queueIndex: 0,
      );

      expect(handler.currentSnapshot.queueItems.length, equals(4));

      // Remove second occurrence of A (item_a2)
      handler.removeQueueItemById('item_a2');

      final remaining = handler.currentSnapshot.queueItems;
      expect(remaining.length, equals(3));
      expect(remaining.map((q) => q.id).toList(),
          equals(['item_a1', 'item_b', 'item_c']));
      expect(remaining.map((q) => q.track.title).toList(),
          equals(['Song A', 'Song B', 'Song C']));
    });

    test('Clear Up Next removes only upcoming tracks and keeps current track playing', () async {
      await handler.loadAndPlayTrack(
        trackA,
        queue: [trackA, trackB, trackC, trackD],
        queueIndex: 0,
      );

      expect(handler.currentSnapshot.upNextItems.length, equals(3));

      handler.clearUpNext();

      expect(handler.currentSnapshot.queue.length, equals(1));
      expect(handler.currentSnapshot.currentTrack?.title, equals('Song A'));
      expect(handler.currentSnapshot.upNextItems.isEmpty, isTrue);
    });

    test('Shuffle and un-shuffle preserve current track and restore original order', () async {
      await handler.loadAndPlayTrack(
        trackA,
        queue: [trackA, trackB, trackC, trackD, trackE],
        queueIndex: 0,
      );

      // Enable shuffle
      handler.toggleShuffle();
      expect(handler.currentSnapshot.shuffleMode, isTrue);
      expect(handler.currentSnapshot.currentTrack?.title, equals('Song A'));
      expect(handler.currentSnapshot.queue.length, equals(5));

      // Disable shuffle -> restores exact original unshuffled queue
      handler.toggleShuffle();
      expect(handler.currentSnapshot.shuffleMode, isFalse);
      expect(handler.currentSnapshot.queue.map((t) => t.title).toList(),
          equals(['Song A', 'Song B', 'Song C', 'Song D', 'Song E']));
    });

    test('Queue persistence and restoration across restarts', () async {
      // 1. Populate tracks in database
      for (final t in [trackA, trackB, trackC, trackD]) {
        await db.into(db.tracks).insertOnConflictUpdate(
              TracksCompanion(
                id: Value(t.id),
                driveFileId: Value(t.driveFileId),
                sourceId: Value(t.sourceId),
                title: Value(t.title),
                normalizedTitle: Value(t.normalizedTitle),
                artistName: Value(t.artistName),
                albumName: Value(t.albumName),
                durationMs: Value(t.durationMs),
                createdAt: Value(DateTime.now()),
                updatedAt: Value(DateTime.now()),
              ),
            );
      }

      // 2. Play A with queue [A, B, A, C] (testing duplicates in persistence)
      const itemA1 = QueueItem(id: 'q_pers_a1', track: trackA);
      const itemB = QueueItem(id: 'q_pers_b', track: trackB);
      const itemA2 = QueueItem(id: 'q_pers_a2', track: trackA);
      const itemC = QueueItem(id: 'q_pers_c', track: trackC);

      await handler.loadAndPlayTrack(
        trackA,
        queueItems: [itemA1, itemB, itemA2, itemC],
        queueIndex: 0,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 3. Create a fresh handler representing app cold start
      final newHandler = MusiiAudioHandler(
        cacheRepository: mockCache,
        recentlyPlayedRepository: mockRecentlyPlayed,
        database: db,
      );

      await newHandler.restoreSavedState();

      final restored = newHandler.currentSnapshot;
      expect(restored.queueItems.length, equals(4));
      expect(restored.queueItems.map((q) => q.id).toList(),
          equals(['q_pers_a1', 'q_pers_b', 'q_pers_a2', 'q_pers_c']));
      expect(restored.queueItems.map((q) => q.track.title).toList(),
          equals(['Song A', 'Song B', 'Song A', 'Song C']));
      expect(restored.currentTrack?.title, equals('Song A'));
      expect(restored.queueIndex, equals(0));
    });
  });
}
