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
    test(
      'existing duplicates are merged, tracks reassigned, and is idempotent',
      () async {
        // Seed duplicates
        await db
            .into(db.albums)
            .insert(
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

        await db
            .into(db.albums)
            .insert(
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
        await db
            .into(db.tracks)
            .insert(
              TracksCompanion.insert(
                id: 'track_1',
                driveFileId: 'df1',
                sourceId: 'src',
                title: 'T1',
                normalizedTitle: 't1',
                albumId: const Value('album_1'),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
        await db
            .into(db.tracks)
            .insert(
              TracksCompanion.insert(
                id: 'track_2',
                driveFileId: 'df2',
                sourceId: 'src',
                title: 'T2',
                normalizedTitle: 't2',
                albumId: const Value('album_2'),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );

        // Run reconciliation
        await db.reconcileDuplicateAlbums();

        // Verify one album remains
        final albums = await db.select(db.albums).get();
        expect(albums.length, equals(1));

        final survivor = albums.first;
        expect(
          survivor.id,
          equals('album_1'),
        ); // Preferred because it has artwork
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
      },
    );

    test(
      'compilation album tracks are merged correctly based on album artist',
      () async {
        // Seed tracks for a compilation album
        await db
            .into(db.tracks)
            .insert(
              TracksCompanion.insert(
                id: 't1',
                driveFileId: 'df1',
                sourceId: 'src',
                title: 'T1',
                normalizedTitle: 't1',
                albumId: const Value('a1'),
                albumArtist: const Value('Various Artists'),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
        await db
            .into(db.tracks)
            .insert(
              TracksCompanion.insert(
                id: 't2',
                driveFileId: 'df2',
                sourceId: 'src',
                title: 'T2',
                normalizedTitle: 't2',
                albumId: const Value('a2'),
                albumArtist: const Value('Various Artists'),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );

        // Seed multiple albums for the same compilation (happens when artists differ)
        await db
            .into(db.albums)
            .insert(
              AlbumsCompanion.insert(
                id: 'a1',
                albumKey: 'k1',
                title: 'Hits',
                normalizedTitle: 'hits',
                artistName: const Value('Artist A'),
              ),
            );
        await db
            .into(db.albums)
            .insert(
              AlbumsCompanion.insert(
                id: 'a2',
                albumKey: 'k2',
                title: 'Hits',
                normalizedTitle: 'hits',
                artistName: const Value('Artist B'),
              ),
            );

        await db.reconcileDuplicateAlbums();

        final albums = await db.select(db.albums).get();
        expect(albums.length, equals(1)); // Merged into one
        expect(albums.first.albumKey, equals('hits::various artists'));

        final tracks = await db.select(db.tracks).get();
        expect(tracks.every((t) => t.albumId == albums.first.id), isTrue);
      },
    );

    test('tracks with featured artists are merged under main album artist even if albumArtist was missing on some tracks', () async {
      // Seed tracks for an album with featured artist splits
      await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              id: 'ram_t1',
              driveFileId: 'df_ram_1',
              sourceId: 'src',
              title: 'Get Lucky',
              normalizedTitle: 'get lucky',
              artistName: const Value('Daft Punk feat. Pharrell Williams'),
              albumId: const Value('album_ram_pharrell'),
              // albumArtist was null on this track due to old parser
              albumArtist: const Value(null),
              durationMs: const Value(240000),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              id: 'ram_t2',
              driveFileId: 'df_ram_2',
              sourceId: 'src',
              title: 'Giorgio by Moroder',
              normalizedTitle: 'giorgio by moroder',
              artistName: const Value('Daft Punk'),
              albumId: const Value('album_ram_main'),
              albumArtist: const Value('Daft Punk'),
              durationMs: const Value(540000),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              id: 'ram_t3',
              driveFileId: 'df_ram_3',
              sourceId: 'src',
              title: 'Instant Crush',
              normalizedTitle: 'instant crush',
              artistName: const Value('Daft Punk feat. Julian Casablancas'),
              albumId: const Value('album_ram_julian'),
              albumArtist: const Value(null),
              durationMs: const Value(330000),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      // Seed 3 separate duplicate albums created by song artist variations
      await db
          .into(db.albums)
          .insert(
            AlbumsCompanion.insert(
              id: 'album_ram_pharrell',
              albumKey: 'ram::daft punk feat pharrell williams',
              title: 'Random Access Memories',
              normalizedTitle: 'random access memories',
              artistName: const Value('Daft Punk feat. Pharrell Williams'),
            ),
          );
      await db
          .into(db.albums)
          .insert(
            AlbumsCompanion.insert(
              id: 'album_ram_main',
              albumKey: 'ram::daft punk',
              title: 'Random Access Memories',
              normalizedTitle: 'random access memories',
              artistName: const Value('Daft Punk'),
              artworkPath: const Value('artwork/ram.jpg'),
            ),
          );
      await db
          .into(db.albums)
          .insert(
            AlbumsCompanion.insert(
              id: 'album_ram_julian',
              albumKey: 'ram::daft punk feat julian casablancas',
              title: 'Random Access Memories',
              normalizedTitle: 'random access memories',
              artistName: const Value('Daft Punk feat. Julian Casablancas'),
            ),
          );

      await db.reconcileDuplicateAlbums();

      final albums = await db.select(db.albums).get();
      expect(albums.length, equals(1)); // Merged into single canonical album

      final canonical = albums.first;
      expect(
        canonical.id,
        equals('album_ram_main'),
      ); // Preferred due to artwork
      expect(canonical.artistName, equals('Daft Punk'));
      expect(canonical.trackCount, equals(3));
      expect(canonical.totalDurationMs, equals(1110000));

      final tracks = await db.select(db.tracks).get();
      expect(tracks.length, equals(3));
      expect(tracks.every((t) => t.albumId == canonical.id), isTrue);
      // All tracks now have their albumArtist set to canonical artist
      expect(tracks.every((t) => t.albumArtist == 'Daft Punk'), isTrue);
      // Song artists remain intact
      expect(tracks[0].artistName, equals('Daft Punk feat. Pharrell Williams'));
      expect(
        tracks[2].artistName,
        equals('Daft Punk feat. Julian Casablancas'),
      );
    });

    test('genuinely distinct albums with same title by different artists stay separate', () async {
      await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              id: 'q1',
              driveFileId: 'df_q1',
              sourceId: 'src',
              title: 'Bohemian Rhapsody',
              normalizedTitle: 'bohemian rhapsody',
              artistName: const Value('Queen'),
              albumId: const Value('alb_queen'),
              albumArtist: const Value('Queen'),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      await db
          .into(db.tracks)
          .insert(
            TracksCompanion.insert(
              id: 'a1',
              driveFileId: 'df_a1',
              sourceId: 'src',
              title: 'Dancing Queen',
              normalizedTitle: 'dancing queen',
              artistName: const Value('ABBA'),
              albumId: const Value('alb_abba'),
              albumArtist: const Value('ABBA'),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      await db
          .into(db.albums)
          .insert(
            AlbumsCompanion.insert(
              id: 'alb_queen',
              albumKey: 'greatest hits::queen',
              title: 'Greatest Hits',
              normalizedTitle: 'greatest hits',
              artistName: const Value('Queen'),
            ),
          );
      await db
          .into(db.albums)
          .insert(
            AlbumsCompanion.insert(
              id: 'alb_abba',
              albumKey: 'greatest hits::abba',
              title: 'Greatest Hits',
              normalizedTitle: 'greatest hits',
              artistName: const Value('ABBA'),
            ),
          );

      await db.reconcileDuplicateAlbums();

      final albums = await db.select(db.albums).get();
      expect(albums.length, equals(2)); // Both albums preserved!
    });

    test(
      'empty albums and orphaned artists are cleaned up during reconciliation',
      () async {
        // Create an empty album with no tracks
        await db
            .into(db.albums)
            .insert(
              AlbumsCompanion.insert(
                id: 'empty_alb',
                albumKey: 'empty::artist',
                title: 'Ghost Album',
                normalizedTitle: 'ghost album',
                artistName: const Value('Ghost Artist'),
              ),
            );
        // Create an orphaned artist
        await db
            .into(db.artists)
            .insert(
              ArtistsCompanion.insert(
                id: 'ghost_artist',
                name: 'Ghost Artist',
                normalizedName: 'ghost artist',
              ),
            );

        await db.reconcileDuplicateAlbums();

        final albums = await db.select(db.albums).get();
        expect(albums.isEmpty, isTrue);

        final artists = await db.select(db.artists).get();
        expect(artists.isEmpty, isTrue);
      },
    );
  });
}
