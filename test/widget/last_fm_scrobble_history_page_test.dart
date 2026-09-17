import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/features/last_fm/domain/entities/scrobble_history_item.dart';
import 'package:musii/features/last_fm/presentation/pages/scrobble_history_page.dart';
import 'package:musii/features/last_fm/presentation/providers/last_fm_providers.dart';

void main() {
  group('ScrobbleHistoryPage', () {
    testWidgets('renders empty state when history is empty', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lastFmScrobbleHistoryProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const CupertinoApp(home: ScrobbleHistoryPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Recent Scrobbles'), findsOneWidget);
      expect(find.text('No Scrobbles Yet'), findsOneWidget);
      expect(
        find.text(
          'Songs you listen to in Musii will appear here once submitted to Last.fm.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders scrobbled history list with track details', (tester) async {
      final now = DateTime.now();
      final historyItems = [
        ScrobbleHistoryItem(
          id: 'sh_1',
          trackId: 't_1',
          trackTitle: 'Sparkle',
          artistName: 'Tatsuro Yamashita',
          albumName: 'For You',
          timestamp: now.millisecondsSinceEpoch ~/ 1000,
          scrobbledAt: now,
        ),
        ScrobbleHistoryItem(
          id: 'sh_2',
          trackId: 't_2',
          trackTitle: 'Stay With Me',
          artistName: 'Miki Matsubara',
          albumName: 'Pocket Park',
          timestamp: (now.millisecondsSinceEpoch ~/ 1000) - 600,
          scrobbledAt: now.subtract(const Duration(minutes: 10)),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lastFmScrobbleHistoryProvider.overrideWith(
              (ref) => Stream.value(historyItems),
            ),
          ],
          child: const CupertinoApp(home: ScrobbleHistoryPage()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Recent Scrobbles'), findsOneWidget);
      expect(find.text('Sparkle'), findsOneWidget);
      expect(find.text('Tatsuro Yamashita · For You'), findsOneWidget);

      expect(find.text('Stay With Me'), findsOneWidget);
      expect(find.text('Miki Matsubara · Pocket Park'), findsOneWidget);
    });
  });
}
