import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/app/bootstrap/providers.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/library/presentation/widgets/playlist_card.dart';
import 'package:musii/features/playlists/domain/entities/playlist.dart';

void main() {
  late Directory tempDir;
  late List<File> testArtFiles;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('musii_playlist_card_test_');
    testArtFiles = List.generate(4, (i) {
      final f = File('${tempDir.path}/art_$i.jpg');
      f.writeAsBytesSync([
        0x47,
        0x49,
        0x46,
        0x38,
        0x39,
        0x61,
        0x01,
        0x00,
        0x01,
        0x00,
        0x80,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0xff,
        0xff,
        0xff,
        0x21,
        0xf9,
        0x04,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x2c,
        0x00,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x01,
        0x00,
        0x00,
        0x02,
        0x01,
        0x44,
        0x00,
        0x3b,
      ]);
      return f;
    });
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  final samplePlaylist = Playlist(
    id: 'pl_favorites',
    name: 'French Touch',
    trackCount: 4,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  group('PlaylistCard', () {
    testWidgets('renders fallback initials when playlist has 0 tracks', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playlistTracksProvider('pl_favorites')
                .overrideWith((ref) => Stream.value([])),
          ],
          child: CupertinoApp(
            home: Center(
              child: SizedBox(
                width: 160,
                child: PlaylistCard(
                  playlist: samplePlaylist.copyWith(trackCount: 0),
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('French Touch'), findsOneWidget);
      expect(find.text('0 songs'), findsOneWidget);
      expect(find.text('F'), findsOneWidget);
    });

    testWidgets(
      'renders single artwork when playlist has 1-3 distinct tracks',
      (tester) async {
        final track1 = Track(
          id: 't_1',
          driveFileId: 'df_1',
          sourceId: 'src_1',
          title: 'Genesis',
          normalizedTitle: 'genesis',
          artworkPath: testArtFiles[0].path,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playlistTracksProvider('pl_favorites')
                  .overrideWith((ref) => Stream.value([track1])),
            ],
            child: CupertinoApp(
              home: Center(
                child: SizedBox(
                  width: 160,
                  child: PlaylistCard(
                    playlist: samplePlaylist.copyWith(trackCount: 1),
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('French Touch'), findsOneWidget);
        expect(find.text('1 song'), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
      },
    );

    testWidgets('renders 2x2 collage when playlist has 4+ distinct tracks', (
      tester,
    ) async {
      final tracks = List.generate(
        4,
        (i) => Track(
          id: 't_$i',
          driveFileId: 'df_$i',
          sourceId: 'src_1',
          title: 'Track $i',
          normalizedTitle: 'track $i',
          artworkPath: testArtFiles[i].path,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playlistTracksProvider('pl_favorites')
                .overrideWith((ref) => Stream.value(tracks)),
          ],
          child: CupertinoApp(
            home: Center(
              child: SizedBox(
                width: 160,
                child: PlaylistCard(
                  playlist: samplePlaylist.copyWith(trackCount: 4),
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('French Touch'), findsOneWidget);
      expect(find.text('4 songs'), findsOneWidget);
      // 4 quadrant Image widgets
      expect(find.byType(Image), findsNWidgets(4));
    });
  });
}
