import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/core/error/failures.dart';
import 'package:musii/core/result/result.dart';
import 'package:musii/features/last_fm/domain/entities/last_fm_account.dart';
import 'package:musii/features/last_fm/domain/entities/pending_scrobble.dart';
import 'package:musii/features/last_fm/domain/entities/scrobble_history_item.dart';
import 'package:musii/features/last_fm/domain/entities/scrobble_settings.dart';
import 'package:musii/features/last_fm/domain/repositories/last_fm_repository.dart';
import 'package:musii/features/last_fm/presentation/pages/pending_scrobbles_page.dart';
import 'package:musii/features/last_fm/presentation/providers/last_fm_providers.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';

class MockLastFmRepository implements LastFmRepository {
  int syncCallCount = 0;

  @override
  Future<Result<int, AppFailure>> syncPendingScrobbles() async {
    syncCallCount++;
    return const Success(1);
  }

  @override
  Future<Result<LastFmAccount, AppFailure>> completeAuthentication(String token) async =>
      throw UnimplementedError();

  @override
  Future<Result<void, AppFailure>> disconnect() async => throw UnimplementedError();

  @override
  Future<LastFmAccount?> getAccount() async => null;

  @override
  Future<String?> getApiKey() async => null;

  @override
  Future<Result<String, AppFailure>> getAuthToken() async =>
      throw UnimplementedError();

  @override
  Future<Uri> getAuthUrl(String token) async => Uri.parse('https://example.com');

  @override
  Future<String?> getApiSecret() async => null;

  @override
  Future<DateTime?> getLastSyncedAt() async => null;

  @override
  Future<int> getPendingCount() async => 0;

  @override
  Future<List<PendingScrobble>> getPendingScrobbles() async => [];

  @override
  Future<ScrobbleSettings> getSettings() async => const ScrobbleSettings();

  @override
  Future<int> getSyncedScrobbleCount() async => 0;

  @override
  Future<bool> hasSession() async => true;

  @override
  Future<Result<void, AppFailure>> recordScrobble(Track track, int startTimestampSeconds) async =>
      const Success(null);

  @override
  Future<void> setApiCredentials({required String apiKey, required String apiSecret}) async {}

  @override
  Future<void> setNowPlayingEnabled(bool enabled) async {}

  @override
  Future<void> setScrobblingEnabled(bool enabled) async {}

  @override
  Future<Result<void, AppFailure>> updateNowPlaying(Track track) async =>
      const Success(null);

  @override
  Stream<LastFmAccount?> watchAccount() => Stream.value(null);

  @override
  Stream<List<PendingScrobble>> watchPendingScrobbles() => Stream.value([]);

  @override
  Stream<List<ScrobbleHistoryItem>> watchScrobbleHistory({int limit = 50}) =>
      Stream.value([]);

  @override
  Stream<ScrobbleSettings> watchSettings() => Stream.value(const ScrobbleSettings());
}

void main() {
  group('PendingScrobblesPage', () {
    testWidgets('renders empty state when no scrobbles are pending', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lastFmPendingScrobblesProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const CupertinoApp(home: PendingScrobblesPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Offline Scrobbles'), findsOneWidget);
      expect(find.text('All Scrobbles Synced'), findsOneWidget);
      expect(
        find.text('There are no pending scrobbles waiting in the offline queue.'),
        findsOneWidget,
      );
      // No Sync Now button in empty state
      expect(find.text('Sync Now'), findsNothing);
    });

    testWidgets('renders pending tracks list with badges and triggers manual sync', (
      tester,
    ) async {
      final mockRepo = MockLastFmRepository();

      final pendingItems = [
        PendingScrobble(
          id: 'ps_1',
          trackId: 't_1',
          trackTitle: 'Plastic Love',
          artistName: 'Mariya Takeuchi',
          albumName: 'Variety',
          durationMs: 290000,
          timestamp: 1700000000,
          status: ScrobbleStatus.pending,
          createdAt: DateTime.now(),
        ),
        PendingScrobble(
          id: 'ps_2',
          trackId: 't_2',
          trackTitle: 'Ride on Time',
          artistName: 'Tatsuro Yamashita',
          albumName: 'Ride on Time',
          durationMs: 310000,
          timestamp: 1700000300,
          status: ScrobbleStatus.failedRetryable,
          attempts: 2,
          errorMessage: 'Connection reset',
          createdAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lastFmRepositoryProvider.overrideWithValue(mockRepo),
            lastFmPendingScrobblesProvider.overrideWith(
              (ref) => Stream.value(pendingItems),
            ),
          ],
          child: const CupertinoApp(home: PendingScrobblesPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Offline Scrobbles'), findsOneWidget);
      expect(find.text('2 tracks waiting to sync'), findsOneWidget);

      // Track titles and artists
      expect(find.text('Plastic Love'), findsOneWidget);
      expect(find.text('Mariya Takeuchi · Variety'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);

      expect(find.text('Ride on Time'), findsOneWidget);
      expect(find.text('Tatsuro Yamashita · Ride on Time'), findsOneWidget);
      expect(find.text('Retry scheduled'), findsOneWidget);

      // Tap Sync Now
      expect(find.text('Sync Now'), findsOneWidget);
      await tester.tap(find.text('Sync Now'));
      await tester.pumpAndSettle();

      expect(mockRepo.syncCallCount, equals(1));
    });
  });
}
