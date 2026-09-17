import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Album Reconciliation & Uniqueness', () {
    test('existing duplicates are merged, tracks reassigned, and is idempotent', () async {
      // Seed duplicates
      await db.into(db.albums).insert(
        AlbumsCompanion.insert(
          id: 'album_1',
          albumKey: 'temp_key_1',
          title: 'Discovery',
          normalizedTitle: 'discovery',
          artistName: const Value('Daft Punk'),
          trackCount: const Value(2),
          artworkPath: const Value('path/to/artwork'),
        ),
      );
      
      await db.into(db.albums).insert(
        AlbumsCompanion.insert(
          id: 'album_2',
          albumKey: 'temp_key_2',
          title: ' discovery ',
          normalizedTitle: 'discovery',
          artistName: const Value('daft punk'),
          trackCount: const Value(2),
        ),
      );

      // Seed tracks pointing to these albums
      await db.into(db.tracks).insert(
        TracksCompanion.insert(
          id: 'track_1', driveFileId: 'df1', sourceId: 'src', title: 'T1', normalizedTitle: 't1', albumId: const Value('album_1'), createdAt: DateTime.now(), updatedAt: DateTime.now()
        )
      );
      await db.into(db.tracks).insert(
        TracksCompanion.insert(
          id: 'track_2', driveFileId: 'df2', sourceId: 'src', title: 'T2', normalizedTitle: 't2', albumId: const Value('album_2'), createdAt: DateTime.now(), updatedAt: DateTime.now()
        )
      );

      // Run reconciliation
      await db.reconcileDuplicateAlbums();

      // Verify one album remains
      final albums = await db.select(db.albums).get();
      expect(albums.length, equals(1));
      
      final survivor = albums.first;
      expect(survivor.id, equals('album_1')); // Preferred because it has artwork
      expect(survivor.albumKey, equals('discovery::daft punk'));

      // Verify all tracks point to survivor
      final tracks = await db.select(db.tracks).get();
      expect(tracks.length, equals(2));
      expect(tracks[0].albumId, equals(survivor.id));
      expect(tracks[1].albumId, equals(survivor.id));

      // Idempotency: run again
      await db.reconcileDuplicateAlbums();
      final albumsAgain = await db.select(db.albums).get();
      expect(albumsAgain.length, equals(1));
    });

    test('compilation album tracks are merged correctly based on album artist', () async {
      // Seed tracks for a compilation album
      await db.into(db.tracks).insert(
        TracksCompanion.insert(
          id: 't1', driveFileId: 'df1', sourceId: 'src', title: 'T1', normalizedTitle: 't1', 
          albumId: const Value('a1'), albumArtist: const Value('Various Artists'), 
          createdAt: DateTime.now(), updatedAt: DateTime.now()
        )
      );
      await db.into(db.tracks).insert(
        TracksCompanion.insert(
          id: 't2', driveFileId: 'df2', sourceId: 'src', title: 'T2', normalizedTitle: 't2', 
          albumId: const Value('a2'), albumArtist: const Value('Various Artists'), 
          createdAt: DateTime.now(), updatedAt: DateTime.now()
        )
      );

      // Seed multiple albums for the same compilation (happens when artists differ)
      await db.into(db.albums).insert(
        AlbumsCompanion.insert(
          id: 'a1', albumKey: 'k1', title: 'Hits', normalizedTitle: 'hits', artistName: const Value('Artist A')
        )
      );
      await db.into(db.albums).insert(
        AlbumsCompanion.insert(
          id: 'a2', albumKey: 'k2', title: 'Hits', normalizedTitle: 'hits', artistName: const Value('Artist B')
        )
      );

      await db.reconcileDuplicateAlbums();

      final albums = await db.select(db.albums).get();
      expect(albums.length, equals(1)); // Merged into one
      expect(albums.first.albumKey, equals('hits::various artists'));

      final tracks = await db.select(db.tracks).get();
      expect(tracks.every((t) => t.albumId == albums.first.id), isTrue);
    });
  });
}
