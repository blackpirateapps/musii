import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/library/presentation/widgets/artist_card.dart';

void main() {
  late Directory tempDir;
  late File testImageFile;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('musii_artist_card_test_');
    testImageFile = File('${tempDir.path}/artist_daft_punk.jpg');
    testImageFile.writeAsBytesSync([
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
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ArtistCard', () {
    testWidgets('renders fallback initials, artist name, and track count', (
      tester,
    ) async {
      const artist = Artist(
        id: 'art_1',
        name: 'Justice',
        normalizedName: 'justice',
        trackCount: 12,
        albumCount: 2,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: CupertinoApp(
            home: Center(
              child: SizedBox(
                width: 160,
                child: ArtistCard(artist: artist, onTap: () {}),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Justice'), findsOneWidget);
      expect(find.text('12 songs'), findsOneWidget);
      expect(find.text('J'), findsOneWidget);
    });

    testWidgets('renders official artist portrait image without error', (
      tester,
    ) async {
      final artist = Artist(
        id: 'art_daft_punk',
        name: 'Daft Punk',
        normalizedName: 'daft punk',
        artworkPath: testImageFile.path,
        trackCount: 24,
        albumCount: 4,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: CupertinoApp(
            home: Center(
              child: SizedBox(
                width: 160,
                child: ArtistCard(artist: artist, onTap: () {}),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Daft Punk'), findsOneWidget);
      expect(find.text('24 songs'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
