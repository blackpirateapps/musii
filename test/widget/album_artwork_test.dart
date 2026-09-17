import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/features/library/presentation/widgets/album_artwork.dart';

void main() {
  late Directory tempDir;
  late File testImageFile;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('musii_album_art_test_');
    testImageFile = File('${tempDir.path}/test_art.jpg');
    // 1x1 transparent GIF / JPEG mock bytes
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

  group('AlbumArtwork', () {
    testWidgets('renders fallback initials with finite size', (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: Center(
            child: AlbumArtwork(
              title: 'Discovery',
              artist: 'Daft Punk',
              size: 56.0,
            ),
          ),
        ),
      );

      expect(find.text('D'), findsOneWidget);
    });

    testWidgets(
      'renders fallback initials with size: double.infinity without asserting on fontSize',
      (tester) async {
        await tester.pumpWidget(
          const CupertinoApp(
            home: Center(
              child: SizedBox(
                width: 150,
                height: 200,
                child: AlbumArtwork(
                  title: 'Random Access Memories',
                  artist: 'Daft Punk',
                  size: double.infinity,
                ),
              ),
            ),
          ),
        );

        expect(find.text('R'), findsOneWidget);
      },
    );

    testWidgets(
      'renders image file with size: double.infinity without UnsupportedError on round()',
      (tester) async {
        await tester.pumpWidget(
          CupertinoApp(
            home: Center(
              child: SizedBox(
                width: 160,
                height: 160,
                child: AlbumArtwork(
                  artworkPath: testImageFile.path,
                  title: 'Test Album',
                  artist: 'Test Artist',
                  size: double.infinity,
                ),
              ),
            ),
          ),
        );

        expect(find.byType(Image), findsOneWidget);
      },
    );

    testWidgets('renders image file with finite size normally', (tester) async {
      await tester.pumpWidget(
        CupertinoApp(
          home: Center(
            child: AlbumArtwork(
              artworkPath: testImageFile.path,
              title: 'Test Album',
              artist: 'Test Artist',
              size: 80.0,
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
    });
  });
}
