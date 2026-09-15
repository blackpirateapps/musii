import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/app/bootstrap/providers.dart';
import 'package:musii/features/library/domain/entities/sync_progress.dart';
import 'package:musii/features/library/presentation/widgets/sync_progress_sheet.dart';

void main() {
  group('SyncProgressSheet Widget Tests', () {
    testWidgets('renders active sync with progress and Stop Sync button', (
      tester,
    ) async {
      const activeProgress = SyncProgress(
        phase: SyncPhase.extractingMetadata,
        filesDiscovered: 100,
        filesProcessed: 42,
        filesAdded: 40,
        filesUpdated: 2,
        progressPercent: 0.42,
        currentFile: 'Plastic Love.mp3',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            syncProgressProvider.overrideWith(
              (ref) => Stream.value(activeProgress),
            ),
          ],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(child: SyncProgressSheet()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Library Synchronization'), findsOneWidget);
      expect(find.text('Reading audio metadata...'), findsOneWidget);
      expect(find.text('Plastic Love.mp3'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('Stop Sync'), findsOneWidget);
      expect(find.text('Dismiss to Background'), findsOneWidget);
    });

    testWidgets('renders stopped sync state with Resume Sync button', (
      tester,
    ) async {
      const stoppedProgress = SyncProgress(
        phase: SyncPhase.stopped,
        filesDiscovered: 200,
        filesProcessed: 85,
        progressPercent: 0.425,
        isResumable: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            syncProgressProvider.overrideWith(
              (ref) => Stream.value(stoppedProgress),
            ),
          ],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(child: SyncProgressSheet()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Sync Stopped'), findsOneWidget);
      expect(find.text('85 of 200 completed'), findsOneWidget);
      expect(find.text('Resume Sync'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
    });

    testWidgets('renders complete sync state with Done button', (tester) async {
      const completedProgress = SyncProgress(
        phase: SyncPhase.complete,
        filesDiscovered: 50,
        filesProcessed: 50,
        filesAdded: 48,
        filesUpdated: 2,
        progressPercent: 1.0,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            syncProgressProvider.overrideWith(
              (ref) => Stream.value(completedProgress),
            ),
          ],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(child: SyncProgressSheet()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Library Synced'), findsOneWidget);
      expect(find.text('Synchronization complete'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });
  });
}
