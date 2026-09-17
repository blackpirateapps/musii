import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';
import '../../features/metadata/domain/services/metadata_normalization_service.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Users,
    MusicSources,
    DriveFolders,
    Artists,
    Albums,
    Genres,
    Tracks,
    Playlists,
    PlaylistTracks,
    Favorites,
    RecentlyPlayed,
    PlaybackQueue,
    CacheEntries,
    SyncRuns,
    DiscoveredFiles,
    SyncErrors,
    Artworks,
    AppSettings,
    PlaybackStates,
    Lyrics,
    LyricLines,
    LyricWords,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        // Create indexes for fast search and relations
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_tracks_search ON tracks(normalized_title, artist_name, album_name);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_tracks_album ON tracks(album_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_tracks_drive ON tracks(drive_file_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_albums_artist ON albums(artist_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_lyrics_track ON lyrics(track_id);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_lyric_lines_lyrics ON lyric_lines(lyrics_id, sequence);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_lyric_words_line ON lyric_words(line_id, word_index);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sync_runs_status ON sync_runs(status, started_at);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_discovered_files_sync ON discovered_files(sync_run_id);',
        );
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.createTable(lyrics);
          await m.createTable(lyricLines);
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_lyrics_track ON lyrics(track_id);',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_lyric_lines_lyrics ON lyric_lines(lyrics_id, sequence);',
          );
        }
        if (from < 3) {
          await m.createTable(lyricWords);
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_lyric_words_line ON lyric_words(line_id, word_index);',
          );
        }
        if (from < 4) {
          await m.addColumn(syncRuns, syncRuns.rootFolderId);
          await m.addColumn(syncRuns, syncRuns.rootFolderName);
          await m.addColumn(syncRuns, syncRuns.updatedAt);
          await m.addColumn(syncRuns, syncRuns.lastCheckpointAt);
          await m.addColumn(syncRuns, syncRuns.phase);
          await m.addColumn(syncRuns, syncRuns.currentFile);
          await m.addColumn(syncRuns, syncRuns.errorMessage);
          await m.addColumn(syncRuns, syncRuns.progressPercent);
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_sync_runs_status ON sync_runs(status, started_at);',
          );
        }
        if (from < 5) {
          await m.createTable(discoveredFiles);
          await m.addColumn(syncRuns, syncRuns.discoveryCompleted);
          await m.addColumn(syncRuns, syncRuns.pendingFoldersJson);
          await m.addColumn(syncRuns, syncRuns.visitedFoldersJson);
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_discovered_files_sync ON discovered_files(sync_run_id);',
          );
        }
        if (from < 6) {
          await m.alterTable(TableMigration(
            albums,
            columnTransformer: {
              albums.albumKey: albums.id,
            },
          ));
          await reconcileDuplicateAlbums();
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> reconcileDuplicateAlbums() async {
    final allAlbums = await select(albums).get();
    final Map<String, List<AlbumRow>> groupedAlbums = {};

    for (final album in allAlbums) {
      final tracksInAlbum =
          await (select(tracks)..where((t) => t.albumId.equals(album.id))).get();
      String effectiveArtist = album.artistName ?? 'Unknown Artist';
      for (final track in tracksInAlbum) {
        if (track.albumArtist != null && track.albumArtist!.trim().isNotEmpty) {
          effectiveArtist = track.albumArtist!;
          break;
        }
      }

      final canonicalKey = MetadataNormalizationService.computeAlbumKey(
        albumName: album.title,
        albumArtist: effectiveArtist,
        trackArtist: album.artistName ?? 'Unknown Artist',
      );

      groupedAlbums.putIfAbsent(canonicalKey, () => []).add(album);
    }

    for (final entry in groupedAlbums.entries) {
      final key = entry.key;
      final group = entry.value;

      if (group.length == 1) {
        await (update(albums)..where((t) => t.id.equals(group.first.id)))
            .write(AlbumsCompanion(albumKey: Value(key)));
        continue;
      }

      group.sort((a, b) {
        if ((a.artworkPath != null) != (b.artworkPath != null)) {
          return a.artworkPath != null ? -1 : 1;
        }
        if (a.trackCount != b.trackCount) {
          return b.trackCount.compareTo(a.trackCount);
        }
        return a.id.compareTo(b.id);
      });

      final survivor = group.first;
      final duplicates = group.skip(1).toList();

      for (final dup in duplicates) {
        await (update(tracks)..where((t) => t.albumId.equals(dup.id)))
            .write(TracksCompanion(albumId: Value(survivor.id)));
        await (delete(albums)..where((t) => t.id.equals(dup.id))).go();
      }

      await (update(albums)..where((t) => t.id.equals(survivor.id)))
          .write(AlbumsCompanion(albumKey: Value(key)));

      final survivorTracks =
          await (select(tracks)..where((t) => t.albumId.equals(survivor.id)))
              .get();
      final totalMs =
          survivorTracks.fold<int>(0, (sum, t) => sum + t.durationMs);
      await (update(albums)..where((t) => t.id.equals(survivor.id))).write(
        AlbumsCompanion(
          trackCount: Value(survivorTracks.length),
          totalDurationMs: Value(totalMs),
        ),
      );
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'musii.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
