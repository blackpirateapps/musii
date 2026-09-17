import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:musii/core/error/failures.dart';
import 'package:musii/core/result/result.dart';
import 'package:musii/features/last_fm/data/services/last_fm_playback_coordinator.dart';
import 'package:musii/features/last_fm/domain/entities/last_fm_account.dart';
import 'package:musii/features/last_fm/domain/entities/pending_scrobble.dart';
import 'package:musii/features/last_fm/domain/entities/scrobble_history_item.dart';
import 'package:musii/features/last_fm/domain/entities/scrobble_settings.dart';
import 'package:musii/features/last_fm/domain/repositories/last_fm_repository.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';

class FakeLastFmRepository implements LastFmRepository {
  final List<Track> nowPlayingCalls = [];
  final List<(Track track, int startTime)> scrobbleCalls = [];

  @override
  Future<Result<void, AppFailure>> updateNowPlaying(Track track) async {
    nowPlayingCalls.add(track);
    return const Success(null);
  }

  @override
  Future<Result<void, AppFailure>> recordScrobble(
    Track track,
    int startTimestampSeconds,
  ) async {
    scrobbleCalls.add((track, startTimestampSeconds));
    return const Success(null);
  }

  @override
  Future<Result<LastFmAccount, AppFailure>> completeAuthentication(String token) async {
    throw UnimplementedError();
  }

  @override
  Future<Result<void, AppFailure>> disconnect() async {
    throw UnimplementedError();
  }

  @override
  Future<LastFmAccount?> getAccount() async => null;

  @override
  Future<String?> getApiKey() async => null;

  @override
  Future<Result<String, AppFailure>> getAuthToken() async {
    throw UnimplementedError();
  }

  @override
  Future<Uri> getAuthUrl(String token) async => Uri.parse('https://example.com');

  @override
  Future<String?> getApiSecret() async => null;

  @override
  Future<int> getPendingCount() async => 0;

  @override
  Future<ScrobbleSettings> getSettings() async {
    return const ScrobbleSettings(
      scrobblingEnabled: true,
      nowPlayingEnabled: true,
    );
  }

  @override
  Future<bool> hasSession() async => true;

  @override
  Future<void> setApiCredentials({
    required String apiKey,
    required String apiSecret,
  }) async {}

  @override
  Future<void> setNowPlayingEnabled(bool enabled) async {}

  @override
  Future<void> setScrobblingEnabled(bool enabled) async {}

  @override
  Future<Result<int, AppFailure>> syncPendingScrobbles() async => const Success(0);

  @override
  Stream<LastFmAccount?> watchAccount() => Stream.value(null);

  @override
  Future<DateTime?> getLastSyncedAt() async => null;

  @override
  Future<List<PendingScrobble>> getPendingScrobbles() async => [];

  @override
  Future<int> getSyncedScrobbleCount() async => 0;

  @override
  Stream<List<PendingScrobble>> watchPendingScrobbles() => Stream.value([]);

  @override
  Stream<List<ScrobbleHistoryItem>> watchScrobbleHistory({int limit = 50}) =>
      Stream.value([]);

  @override
  Stream<ScrobbleSettings> watchSettings() => Stream.value(
        const ScrobbleSettings(scrobblingEnabled: true, nowPlayingEnabled: true),
      );
}

void main() {
  group('LastFmPlaybackCoordinator', () {
    late FakeLastFmRepository fakeRepo;
    late LastFmPlaybackCoordinator coordinator;

    const track1 = Track(
      id: 't_coord_1',
      driveFileId: 'df_1',
      sourceId: 'src_1',
      title: 'Loveland, Island',
      normalizedTitle: 'loveland island',
      artistName: 'Tatsuro Yamashita',
      albumName: 'For You',
      durationMs: 240000, // 4 mins (240s) -> threshold 120s (120,000 ms)
    );

    const track2 = Track(
      id: 't_coord_2',
      driveFileId: 'df_2',
      sourceId: 'src_2',
      title: 'Sparkle',
      normalizedTitle: 'sparkle',
      artistName: 'Tatsuro Yamashita',
      albumName: 'For You',
      durationMs: 300000, // 5 mins (300s) -> threshold 150s (150,000 ms)
    );

    setUp(() {
      fakeRepo = FakeLastFmRepository();
      coordinator = LastFmPlaybackCoordinator(repository: fakeRepo);
    });

    tearDown(() {
      coordinator.dispose();
    });

    test('onTrackStarted dispatches Now Playing and updates currentTrack', () async {
      coordinator.onTrackStarted(track1);

      expect(coordinator.currentTrack, equals(track1));
      // Give unawaited future a tick to execute
      await Future<void>.delayed(Duration.zero);

      expect(fakeRepo.nowPlayingCalls.length, equals(1));
      expect(fakeRepo.nowPlayingCalls.first.title, equals('Loveland, Island'));
    });

    test('onPositionUpdated does not scrobble before threshold', () async {
      coordinator.onTrackStarted(track1);
      await Future<void>.delayed(Duration.zero);

      // Threshold is 120,000 ms. Send 60,000 ms (halfway to threshold)
      coordinator.onPositionUpdated(
        const Duration(seconds: 60),
        const Duration(seconds: 240),
      );
      await Future<void>.delayed(Duration.zero);

      expect(fakeRepo.scrobbleCalls, isEmpty);
    });

    test('onPositionUpdated scrobbles once threshold is reached and emits on stream', () async {
      coordinator.onTrackStarted(track1);
      await Future<void>.delayed(Duration.zero);

      Track? emittedTrack;
      final sub = coordinator.onScrobbleSuccess.listen((t) => emittedTrack = t);
      addTearDown(sub.cancel);

      // Threshold is 120,000 ms. Send 120,000 ms
      coordinator.onPositionUpdated(
        const Duration(seconds: 120),
        const Duration(seconds: 240),
      );
      await Future<void>.delayed(Duration.zero);

      expect(fakeRepo.scrobbleCalls.length, equals(1));
      expect(fakeRepo.scrobbleCalls.first.$1.title, equals('Loveland, Island'));
      expect(emittedTrack?.title, equals('Loveland, Island'));
    });

    test('does not duplicate scrobble within the same listening session', () async {
      coordinator.onTrackStarted(track1);
      await Future<void>.delayed(Duration.zero);

      // Hit threshold
      coordinator.onPositionUpdated(
        const Duration(seconds: 120),
        const Duration(seconds: 240),
      );
      await Future<void>.delayed(Duration.zero);
      expect(fakeRepo.scrobbleCalls.length, equals(1));

      // Continue playback further into track
      coordinator.onPositionUpdated(
        const Duration(seconds: 130),
        const Duration(seconds: 240),
      );
      coordinator.onPositionUpdated(
        const Duration(seconds: 180),
        const Duration(seconds: 240),
      );
      coordinator.onPositionUpdated(
        const Duration(seconds: 239),
        const Duration(seconds: 240),
      );
      await Future<void>.delayed(Duration.zero);

      // Still only 1 scrobble recorded
      expect(fakeRepo.scrobbleCalls.length, equals(1));
    });

    test('detects replay jump back to start and enables a new scrobble', () async {
      coordinator.onTrackStarted(track1);
      await Future<void>.delayed(Duration.zero);

      // Play past threshold (120s)
      coordinator.onPositionUpdated(
        const Duration(seconds: 130),
        const Duration(seconds: 240),
      );
      await Future<void>.delayed(Duration.zero);
      expect(fakeRepo.scrobbleCalls.length, equals(1));

      // User scrubs / restarts track to 1s
      coordinator.onPositionUpdated(
        const Duration(seconds: 1),
        const Duration(seconds: 240),
      );
      await Future<void>.delayed(Duration.zero);

      // Now Playing dispatched for new session
      expect(fakeRepo.nowPlayingCalls.length, equals(2));

      // Play to threshold again in new session
      coordinator.onPositionUpdated(
        const Duration(seconds: 120),
        const Duration(seconds: 240),
      );
      await Future<void>.delayed(Duration.zero);

      // Second valid scrobble recorded
      expect(fakeRepo.scrobbleCalls.length, equals(2));
    });

    test('switching tracks cleanly starts new session', () async {
      coordinator.onTrackStarted(track1);
      await Future<void>.delayed(Duration.zero);
      expect(fakeRepo.nowPlayingCalls.length, equals(1));

      coordinator.onTrackStarted(track2);
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.currentTrack, equals(track2));
      expect(fakeRepo.nowPlayingCalls.length, equals(2));
      expect(fakeRepo.nowPlayingCalls.last.title, equals('Sparkle'));

      // Threshold for track2 (300s) is 150s
      coordinator.onPositionUpdated(
        const Duration(seconds: 150),
        const Duration(seconds: 300),
      );
      await Future<void>.delayed(Duration.zero);

      expect(fakeRepo.scrobbleCalls.length, equals(1));
      expect(fakeRepo.scrobbleCalls.first.$1.title, equals('Sparkle'));
    });
  });
}
