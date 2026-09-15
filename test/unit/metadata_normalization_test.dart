import 'package:flutter_test/flutter_test.dart';
import 'package:musii/features/metadata/domain/entities/parsed_audio_metadata.dart';
import 'package:musii/features/metadata/domain/services/metadata_normalization_service.dart';

void main() {
  group('MetadataNormalizationService', () {
    test(
      'normalizes track title by stripping track numbers and file noise',
      () {
        const raw = ParsedAudioMetadata(
          title: '01 - Bohemian Rhapsody',
          artist: 'Queen',
          album: 'A Night at the Opera',
          format: 'FLAC',
          fileSize: 45000000,
          durationMs: 354000,
        );

        final normalized = MetadataNormalizationService.normalize(
          raw,
          filenameFallback: '01 - Bohemian Rhapsody.flac',
        );

        expect(normalized.title, equals('Bohemian Rhapsody'));
        expect(normalized.normalizedTitle, equals('bohemian rhapsody'));
        expect(normalized.artist, equals('Queen'));
        expect(normalized.album, equals('A Night at the Opera'));
      },
    );

    test('falls back gracefully to filename when raw title is empty', () {
      const raw = ParsedAudioMetadata(
        title: '',
        format: 'MP3',
        fileSize: 5000000,
      );

      final normalized = MetadataNormalizationService.normalize(
        raw,
        filenameFallback: '04_hotel_california.mp3',
      );

      expect(normalized.title, equals('hotel california'));
      expect(
        normalized.artist,
        equals(MetadataNormalizationService.unknownArtist),
      );
      expect(
        normalized.album,
        equals(MetadataNormalizationService.unknownAlbum),
      );
    });

    test('normalizes various artist aliases', () {
      const raw = ParsedAudioMetadata(
        title: 'Song',
        artist: 'Various Artists',
        album: 'Greatest Hits',
        format: 'MP3',
        fileSize: 3000000,
      );

      final normalized = MetadataNormalizationService.normalize(
        raw,
        filenameFallback: 'track.mp3',
      );

      expect(
        normalized.artist,
        equals(MetadataNormalizationService.variousArtists),
      );
    });

    test(
      'computes deterministic artwork keys for identical album + artist',
      () {
        final key1 = MetadataNormalizationService.computeArtworkKey(
          'Abbey Road',
          'The Beatles',
        );
        final key2 = MetadataNormalizationService.computeArtworkKey(
          'abbey road',
          'THE BEATLES',
        );
        final key3 = MetadataNormalizationService.computeArtworkKey(
          'Revolver',
          'The Beatles',
        );

        expect(key1, equals(key2));
        expect(key1, isNot(equals(key3)));
      },
    );
  });
}
