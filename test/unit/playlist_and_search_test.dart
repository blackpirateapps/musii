import 'package:flutter_test/flutter_test.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/playlists/domain/entities/playlist.dart';
import 'package:musii/features/search/data/repositories/search_repository_impl.dart';

void main() {
  group('Playlist & Search Entities', () {
    test('Playlist copyWith updates properties accurately', () {
      final now = DateTime.now();
      final playlist = Playlist(
        id: 'pl_1',
        name: 'Chill Vibes',
        description: 'Mellow tunes',
        trackCount: 5,
        createdAt: now,
        updatedAt: now,
      );

      final updated = playlist.copyWith(
        name: 'Super Chill Vibes',
        trackCount: 6,
      );

      expect(updated.id, equals('pl_1'));
      expect(updated.name, equals('Super Chill Vibes'));
      expect(updated.description, equals('Mellow tunes'));
      expect(updated.trackCount, equals(6));
    });

    test('SearchResults isEmpty and isNotEmpty behave as expected', () {
      const empty = SearchResults();
      expect(empty.isEmpty, isTrue);
      expect(empty.isNotEmpty, isFalse);

      const track = Track(
        id: 't1',
        driveFileId: 'df1',
        sourceId: 's1',
        title: 'Song A',
        normalizedTitle: 'song a',
      );

      const populated = SearchResults(tracks: [track]);
      expect(populated.isEmpty, isFalse);
      expect(populated.isNotEmpty, isTrue);
      expect(populated.tracks.length, equals(1));
    });
  });
}
