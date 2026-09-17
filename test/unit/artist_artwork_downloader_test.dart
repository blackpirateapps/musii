import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:musii/core/database/app_database.dart';
import 'package:musii/core/filesystem/app_file_system.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/metadata/data/datasources/artist_artwork_downloader.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri());
  });

  late AppDatabase db;
  late Directory tempDir;
  late AppFileSystem fs;
  late MockHttpClient mockClient;
  late ArtistArtworkDownloader downloader;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('musii_art_test_');
    fs = AppFileSystem.instance;
    fs.artworkCacheDir.createSync(recursive: true);
    mockClient = MockHttpClient();
    downloader = ArtistArtworkDownloader(
      client: mockClient,
      fileSystem: fs,
      database: db,
    );
  });

  tearDown(() async {
    await db.close();
    if (fs.artworkCacheDir.existsSync()) {
      fs.artworkCacheDir.deleteSync(recursive: true);
    }
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  const testArtist = Artist(
    id: 'artist_daft_punk',
    name: 'Daft Punk',
    normalizedName: 'daft punk',
  );

  group('ArtistArtworkDownloader', () {
    test('returns null when artist name is empty', () async {
      const emptyArtist = Artist(
        id: 'artist_empty',
        name: '   ',
        normalizedName: '',
      );
      final result = await downloader.downloadArtistArtwork(emptyArtist);
      expect(result, isNull);
      verifyZeroInteractions(mockClient);
    });

    test('returns existing artwork path if file already exists', () async {
      final existingFile = File('${tempDir.path}/custom_artist.jpg');
      await existingFile.writeAsString('fake_image_data');

      final artistWithArt = testArtist.copyWith(artworkPath: existingFile.path);
      final result = await downloader.downloadArtistArtwork(artistWithArt);

      expect(result, equals(existingFile.path));
      verifyZeroInteractions(mockClient);
    });

    test(
      'returns cached file and updates DB if file exists in cache dir',
      () async {
        // Seed artist in database
        await db
            .into(db.artists)
            .insert(
              ArtistsCompanion.insert(
                id: testArtist.id,
                name: testArtist.name,
                normalizedName: testArtist.normalizedName,
              ),
            );

        final cacheFile = fs.getArtworkCacheFile(
          'artist_${testArtist.normalizedName}',
        );
        await cacheFile.writeAsString('cached_bytes');

        final result = await downloader.downloadArtistArtwork(testArtist);
        expect(result, equals(cacheFile.path));

        final row = await (db.select(
          db.artists,
        )..where((tbl) => tbl.id.equals(testArtist.id))).getSingle();
        expect(row.artworkPath, equals(cacheFile.path));
        verifyZeroInteractions(mockClient);
      },
    );

    test('fetches from Deezer, downloads bytes, saves to cache, and updates database', () async {
      await db
          .into(db.artists)
          .insert(
            ArtistsCompanion.insert(
              id: testArtist.id,
              name: testArtist.name,
              normalizedName: testArtist.normalizedName,
            ),
          );

      final searchJson = jsonEncode({
        'data': [
          {
            'id': 27,
            'name': 'Daft Punk',
            'picture_big': 'https://example.com/daft_punk_big.jpg',
          },
        ],
      });

      final fakeImageBytes = [0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02];

      when(
        () => mockClient.get(
          Uri.parse('https://api.deezer.com/search/artist?q=Daft%20Punk'),
        ),
      ).thenAnswer((_) async => http.Response(searchJson, 200));

      when(
        () =>
            mockClient.get(Uri.parse('https://example.com/daft_punk_big.jpg')),
      ).thenAnswer((_) async => http.Response.bytes(fakeImageBytes, 200));

      final result = await downloader.downloadArtistArtwork(testArtist);

      final expectedFile = fs.getArtworkCacheFile(
        'artist_${testArtist.normalizedName}',
      );
      expect(result, equals(expectedFile.path));
      expect(expectedFile.existsSync(), isTrue);
      expect(expectedFile.readAsBytesSync(), equals(fakeImageBytes));

      final row = await (db.select(
        db.artists,
      )..where((tbl) => tbl.id.equals(testArtist.id))).getSingle();
      expect(row.artworkPath, equals(expectedFile.path));
    });

    test('handles 404/error gracefully without throwing', () async {
      when(() => mockClient.get(any()))
          .thenAnswer((_) async => http.Response('Not Found', 404));

      final result = await downloader.downloadArtistArtwork(testArtist);
      expect(result, isNull);
    });

    test('handles network exceptions gracefully', () async {
      when(() => mockClient.get(any()))
          .thenThrow(const SocketException('No network'));

      final result = await downloader.downloadArtistArtwork(testArtist);
      expect(result, isNull);
    });
  });
}
