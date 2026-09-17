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
import 'package:musii/features/last_fm/presentation/pages/last_fm_settings_page.dart';
import 'package:musii/features/last_fm/presentation/providers/last_fm_providers.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';

class MockLastFmRepository implements LastFmRepository {
  @override
  Future<Result<int, AppFailure>> syncPendingScrobbles() async =>
      const Success(0);

  @override
  Future<Result<LastFmAccount, AppFailure>> completeAuthentication(
    String token,
  ) async => throw UnimplementedError();

  String? mockApiKey;
  String? mockToken;

  @override
  Future<Result<void, AppFailure>> disconnect() async => const Success(null);

  @override
  Future<LastFmAccount?> getAccount() async => null;

  @override
  Future<String?> getApiKey() async => mockApiKey;

  @override
  Future<Result<String, AppFailure>> getAuthToken() async =>
      Success(mockToken ?? 'mock_token_123');

  @override
  Future<Uri> getAuthUrl(String token) async => Uri.parse(
    'https://www.last.fm/api/auth/?api_key=${mockApiKey ?? "979031f3a1b042ab166295f2b7bbfce3"}&token=$token',
  );

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
  Future<Result<void, AppFailure>> recordScrobble(
    Track track,
    int startTimestampSeconds,
  ) async => const Success(null);

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
  Stream<ScrobbleSettings> watchSettings() =>
      Stream.value(const ScrobbleSettings());
}

void main() {
  group('LastFmSettingsPage', () {
    testWidgets(
      'renders disconnected view with Connect button and API credentials dialog',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockRepo = MockLastFmRepository();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              lastFmRepositoryProvider.overrideWithValue(mockRepo),
              lastFmAccountProvider.overrideWith((ref) => Stream.value(null)),
              lastFmSettingsProvider.overrideWith(
                (ref) => Stream.value(const ScrobbleSettings()),
              ),
              lastFmPendingScrobblesProvider.overrideWith(
                (ref) => Stream.value([]),
              ),
            ],
            child: const CupertinoApp(home: LastFmSettingsPage()),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Last.fm'), findsOneWidget);
        expect(
          find.text('Keep your listening\nhistory in sync.'),
          findsOneWidget,
        );
        expect(find.text('Connect Last.fm'), findsOneWidget);

        // Tap gear icon to open credentials dialog
        await tester.tap(find.byIcon(CupertinoIcons.gear_alt));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('Last.fm API Credentials'), findsOneWidget);
        expect(find.text('API Key'), findsOneWidget);
        expect(find.text('Shared Secret'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Save'), findsOneWidget);

        // Tap Cancel to dismiss dialog
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.text('Last.fm API Credentials'), findsNothing);
      },
    );

    testWidgets('renders connected view with profile, switches, and sections', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final connectedAccount = LastFmAccount(
        username: 'citypop_lover',
        realName: 'Tatsuro Fan',
        profileUrl: 'https://www.last.fm/user/citypop_lover',
        scrobbleCount: 1420,
        status: LastFmAccountStatus.connected,
        lastSyncedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lastFmAccountProvider.overrideWith(
              (ref) => Stream.value(connectedAccount),
            ),
            lastFmSettingsProvider.overrideWith(
              (ref) => Stream.value(
                const ScrobbleSettings(
                  scrobblingEnabled: true,
                  nowPlayingEnabled: true,
                ),
              ),
            ),
            lastFmPendingScrobblesProvider.overrideWith(
              (ref) => Stream.value([]),
            ),
          ],
          child: const CupertinoApp(home: LastFmSettingsPage()),
        ),
      );

      await tester.pumpAndSettle();

      // Account info
      expect(find.text('@citypop_lover'), findsOneWidget);
      expect(find.text('Tatsuro Fan'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);

      // Settings sections
      expect(find.text('LISTENING'), findsOneWidget);
      expect(find.text('Scrobble automatically'), findsOneWidget);
      expect(find.text('Now Playing'), findsOneWidget);

      // Offline queue section
      expect(find.text('OFFLINE SCROBBLES'), findsOneWidget);
      expect(find.text('0 tracks waiting to sync'), findsOneWidget);

      // Scrobble Activity section
      expect(find.text('SCROBBLE ACTIVITY'), findsOneWidget);
      expect(find.text('Scrobbles synced'), findsOneWidget);
      expect(find.text('1420'), findsOneWidget);
      expect(find.text('Recent Scrobbles'), findsOneWidget);

      // Account Section
      expect(find.text('ACCOUNT'), findsOneWidget);
      expect(find.text('Open Last.fm profile'), findsOneWidget);
      expect(find.text('Disconnect Last.fm'), findsOneWidget);

      // Tap Disconnect Last.fm
      await tester.tap(find.text('Disconnect Last.fm'));
      await tester.pumpAndSettle();

      expect(find.text('Disconnect Last.fm?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Disconnect Last.fm?'), findsNothing);
    });

    testWidgets(
      'renders reauth needed banner when account status is reauthRequired',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final reauthAccount = LastFmAccount(
          username: 'citypop_lover',
          profileUrl: 'https://www.last.fm/user/citypop_lover',
          scrobbleCount: 1420,
          status: LastFmAccountStatus.reauthRequired,
          lastSyncedAt: DateTime.now(),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              lastFmAccountProvider.overrideWith(
                (ref) => Stream.value(reauthAccount),
              ),
              lastFmSettingsProvider.overrideWith(
                (ref) => Stream.value(const ScrobbleSettings()),
              ),
              lastFmPendingScrobblesProvider.overrideWith(
                (ref) => Stream.value([]),
              ),
            ],
            child: const CupertinoApp(home: LastFmSettingsPage()),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Reconnect needed'), findsOneWidget);
        expect(find.text('Last.fm needs you to reconnect.'), findsOneWidget);
        expect(find.text('Reconnect'), findsOneWidget);
      },
    );

    testWidgets(
      'renders authorizing in browser view with copy auth link and re-open browser',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockRepo = MockLastFmRepository()
          ..mockApiKey = '979031f3a1b042ab166295f2b7bbfce3'
          ..mockToken = 'test_token_456';

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              lastFmRepositoryProvider.overrideWithValue(mockRepo),
              lastFmAccountProvider.overrideWith((ref) => Stream.value(null)),
              lastFmSettingsProvider.overrideWith(
                (ref) => Stream.value(const ScrobbleSettings()),
              ),
              lastFmPendingScrobblesProvider.overrideWith(
                (ref) => Stream.value([]),
              ),
            ],
            child: const CupertinoApp(home: LastFmSettingsPage()),
          ),
        );

        await tester.pumpAndSettle();

        // Tap Connect Last.fm
        await tester.tap(find.text('Connect Last.fm'));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('Authorizing in browser...'), findsOneWidget);
        expect(find.text('Copy'), findsOneWidget);
        expect(find.text('Re-open Browser'), findsOneWidget);
        expect(find.text('Complete Connection'), findsOneWidget);

        // Tap Copy link button
        await tester.tap(find.text('Copy'));
        await tester.pump();
        expect(find.text('Copied'), findsOneWidget);

        // Tap Cancel to dismiss
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.text('Authorizing in browser...'), findsNothing);
        expect(find.text('Connect Last.fm'), findsOneWidget);
      },
    );
  });
}
