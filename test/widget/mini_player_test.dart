import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/app/bootstrap/providers.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/playback/domain/entities/playback_state.dart';
import 'package:musii/features/playback/presentation/widgets/mini_player.dart';

void main() {
  const testTrack = Track(
    id: 'track_mini_1',
    driveFileId: 'drive_mini_1',
    sourceId: 'source_1',
    title: 'Plastic Love',
    normalizedTitle: 'plastic love',
    artistName: 'Mariya Takeuchi',
    durationMs: 290000,
  );

  testWidgets('MiniPlayer renders track title, artist, and playback controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerStateProvider.overrideWith(
            (ref) => Stream.value(
              const PlayerStateSnapshot(
                currentTrack: testTrack,
                duration: Duration(milliseconds: 290000),
                position: Duration(milliseconds: 90000),
                isPlaying: true,
              ),
            ),
          ),
        ],
        child: const CupertinoApp(
          home: CupertinoPageScaffold(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: MiniPlayer(),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Plastic Love'), findsOneWidget);
    expect(find.text('Mariya Takeuchi'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.pause_fill), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.forward_fill), findsOneWidget);
  });

  testWidgets('MiniPlayer renders nothing when no track is active', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerStateProvider.overrideWith(
            (ref) => Stream.value(const PlayerStateSnapshot()),
          ),
        ],
        child: const CupertinoApp(
          home: CupertinoPageScaffold(child: MiniPlayer()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(find.byType(CupertinoButton), findsNothing);
  });
}
