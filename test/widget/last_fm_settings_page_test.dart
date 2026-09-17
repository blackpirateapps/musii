import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/features/last_fm/domain/entities/last_fm_account.dart';
import 'package:musii/features/last_fm/domain/entities/scrobble_settings.dart';
import 'package:musii/features/last_fm/presentation/pages/last_fm_settings_page.dart';
import 'package:musii/features/last_fm/presentation/providers/last_fm_providers.dart';

void main() {
  group('LastFmSettingsPage', () {
    testWidgets('renders disconnected view with Connect button and API credentials dialog', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lastFmAccountProvider.overrideWith((ref) => Stream.value(null)),
            lastFmSettingsProvider.overrideWith(
              (ref) => Stream.value(const ScrobbleSettings()),
            ),
            lastFmPendingScrobblesProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const CupertinoApp(home: LastFmSettingsPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Last.fm'), findsOneWidget);
      expect(find.text('Keep your listening\nhistory in sync.'), findsOneWidget);
      expect(find.text('Connect Last.fm'), findsOneWidget);

      // Tap gear icon to open credentials dialog
      await tester.tap(find.byIcon(CupertinoIcons.gear_alt));
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
    });

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
              (ref) => Stream.value(const ScrobbleSettings(
                scrobblingEnabled: true,
                nowPlayingEnabled: true,
              )),
            ),
            lastFmPendingScrobblesProvider.overrideWith((ref) => Stream.value([])),
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

    testWidgets('renders reauth needed banner when account status is reauthRequired', (
      tester,
    ) async {
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
            lastFmPendingScrobblesProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const CupertinoApp(home: LastFmSettingsPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Reconnect needed'), findsOneWidget);
      expect(find.text('Last.fm needs you to reconnect.'), findsOneWidget);
      expect(find.text('Reconnect'), findsOneWidget);
    });
  });
}
