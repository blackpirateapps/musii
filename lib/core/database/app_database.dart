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
    LastFmAccounts,
    PendingScrobbles,
    ScrobbleHistory,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 10;

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
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_pending_scrobbles_status ON pending_scrobbles(status, timestamp);',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_scrobble_history_time ON scrobble_history(scrobbled_at);',
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
          await m.alterTable(
            TableMigration(
              albums,
              columnTransformer: {albums.albumKey: albums.id},
            ),
          );
          await reconcileDuplicateAlbums();
        }
        if (from < 7) {
          await reconcileDuplicateAlbums();
        }
        if (from < 8) {
          await m.createTable(lastFmAccounts);
          await m.createTable(pendingScrobbles);
          await m.createTable(scrobbleHistory);
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_pending_scrobbles_status ON pending_scrobbles(status, timestamp);',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_scrobble_history_time ON scrobble_history(scrobbled_at);',
          );
        }
        if (from < 9) {
          await m.addColumn(discoveredFiles, discoveredFiles.isProcessed);
          await m.addColumn(discoveredFiles, discoveredFiles.processStatus);
          await m.addColumn(discoveredFiles, discoveredFiles.processedAt);
        }
        if (from < 10) {
          await m.addColumn(tracks, tracks.artworkPath);
          await customStatement('''
            UPDATE tracks 
            SET artwork_path = (
              SELECT albums.artwork_path 
              FROM albums 
              WHERE albums.id = tracks.album_id
            )
            WHERE tracks.album_id IS NOT NULL;
          ''');
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> reconcileDuplicateAlbums() async {
    final allAlbums = await select(albums).get();
    final Map<String, List<AlbumRow>> titleGroups = {};

    for (final album in allAlbums) {
      titleGroups.putIfAbsent(album.normalizedTitle, () => []).add(album);
    }

    for (final entry in titleGroups.entries) {
      final group = entry.value;

      if (group.length == 1) {
        final album = group.first;
        final tracksInAlbum = await (select(
          tracks,
        )..where((t) => t.albumId.equals(album.id))).get();

        if (tracksInAlbum.isEmpty) {
          await (delete(albums)..where((t) => t.id.equals(album.id))).go();
          continue;
        }

        String effectiveArtist = album.artistName ?? 'Unknown Artist';
        for (final track in tracksInAlbum) {
          if (track.albumArtist != null &&
              track.albumArtist!.trim().isNotEmpty) {
            effectiveArtist = track.albumArtist!;
            break;
          }
        }

        final canonicalKey = MetadataNormalizationService.computeAlbumKey(
          albumName: album.title,
          albumArtist: effectiveArtist,
          trackArtist: album.artistName ?? 'Unknown Artist',
        );

        final totalMs = tracksInAlbum.fold<int>(
          0,
          (sum, t) => sum + t.durationMs,
        );
        await (update(albums)..where((t) => t.id.equals(album.id))).write(
          AlbumsCompanion(
            albumKey: Value(canonicalKey),
            artistName: Value(effectiveArtist),
            trackCount: Value(tracksInAlbum.length),
            totalDurationMs: Value(totalMs),
          ),
        );

        final albumArt =
            album.artworkPath != null && album.artworkPath!.isNotEmpty
                ? album.artworkPath
                : null;

        await (update(tracks)..where((t) => t.albumId.equals(album.id))).write(
          TracksCompanion(
            albumArtist: Value(effectiveArtist),
            artworkPath:
                albumArt != null ? Value(albumArt) : const Value.absent(),
          ),
        );
        continue;
      }

      // group.length > 1: Multiple albums share the same normalizedTitle
      // Sort so base/shorter artists come first (e.g. "Daft Punk" before "Daft Punk feat. X")
      group.sort((a, b) {
        final aLen = (a.artistName ?? '').length;
        final bLen = (b.artistName ?? '').length;
        return aLen.compareTo(bLen);
      });

      final List<List<AlbumRow>> subGroups = [];

      for (final alb in group) {
        final albTracks = await (select(
          tracks,
        )..where((t) => t.albumId.equals(alb.id))).get();

        String? albAlbumArtist;
        for (final t in albTracks) {
          if (t.albumArtist != null && t.albumArtist!.trim().isNotEmpty) {
            albAlbumArtist = t.albumArtist!.trim();
            break;
          }
        }

        bool placed = false;
        for (final subGroup in subGroups) {
          // Check compatibility against any member in the subGroup
          for (final member in subGroup) {
            final memTracks = await (select(
              tracks,
            )..where((t) => t.albumId.equals(member.id))).get();

            String? memAlbumArtist;
            for (final t in memTracks) {
              if (t.albumArtist != null && t.albumArtist!.trim().isNotEmpty) {
                memAlbumArtist = t.albumArtist!.trim();
                break;
              }
            }

            if (_areAlbumArtistsCompatible(
              alb.artistName,
              member.artistName,
              albAlbumArtist: albAlbumArtist,
              repAlbumArtist: memAlbumArtist,
            )) {
              subGroup.add(alb);
              placed = true;
              break;
            }
          }
          if (placed) break;
        }

        if (!placed) {
          subGroups.add([alb]);
        }
      }

      // Reconcile each sub-group
      for (final subGroup in subGroups) {
        final List<TrackRow> allTracks = [];
        final Map<String, int> albumArtistCounts = {};
        final Map<String, int> trackArtistCounts = {};

        for (final alb in subGroup) {
          final tList = await (select(
            tracks,
          )..where((t) => t.albumId.equals(alb.id))).get();
          allTracks.addAll(tList);
          for (final t in tList) {
            if (t.albumArtist != null && t.albumArtist!.trim().isNotEmpty) {
              final aa = t.albumArtist!.trim();
              albumArtistCounts[aa] = (albumArtistCounts[aa] ?? 0) + 1;
            }
            if (t.artistName != null && t.artistName!.trim().isNotEmpty) {
              final ta = t.artistName!.trim();
              trackArtistCounts[ta] = (trackArtistCounts[ta] ?? 0) + 1;
            }
          }
        }

        if (allTracks.isEmpty) {
          for (final alb in subGroup) {
            await (delete(albums)..where((t) => t.id.equals(alb.id))).go();
          }
          continue;
        }

        // Determine winning canonical artist
        String winningArtist;
        if (albumArtistCounts.isNotEmpty) {
          winningArtist = albumArtistCounts.entries
              .reduce((a, b) => a.value >= b.value ? a : b)
              .key;
        } else {
          winningArtist = _findDominantOrBaseArtist(
            subGroup.map((a) => a.artistName ?? '').toList(),
            trackArtistCounts,
          );
        }

        // Sort to pick survivor: artworkPath != null > trackCount > id
        subGroup.sort((a, b) {
          if ((a.artworkPath != null) != (b.artworkPath != null)) {
            return a.artworkPath != null ? -1 : 1;
          }
          if (a.trackCount != b.trackCount) {
            return b.trackCount.compareTo(a.trackCount);
          }
          return a.id.compareTo(b.id);
        });

        final survivor = subGroup.first;
        final duplicates = subGroup.skip(1).toList();

        final canonicalKey = MetadataNormalizationService.computeAlbumKey(
          albumName: survivor.title,
          albumArtist: winningArtist,
          trackArtist: winningArtist,
        );

        final survivorArt =
            survivor.artworkPath != null && survivor.artworkPath!.isNotEmpty
                ? survivor.artworkPath
                : null;

        if (duplicates.isNotEmpty) {
          final dupIds = duplicates.map((d) => d.id).toList();
          await (update(tracks)..where((t) => t.albumId.isIn(dupIds))).write(
            TracksCompanion(
              albumId: Value(survivor.id),
              albumArtist: Value(winningArtist),
              artworkPath: survivorArt != null
                  ? Value(survivorArt)
                  : const Value.absent(),
            ),
          );
          await (delete(albums)..where((t) => t.id.isIn(dupIds))).go();
        }

        // Also ensure all tracks belonging to survivor inherit artworkPath if missing
        if (survivorArt != null) {
          await (update(tracks)..where(
                (t) => t.albumId.equals(survivor.id) & t.artworkPath.isNull(),
              ))
              .write(TracksCompanion(artworkPath: Value(survivorArt)));
        }

        final survivorTracks = await (select(
          tracks,
        )..where((t) => t.albumId.equals(survivor.id))).get();
        final totalMs = survivorTracks.fold<int>(
          0,
          (sum, t) => sum + t.durationMs,
        );

        await (update(albums)..where((t) => t.id.equals(survivor.id))).write(
          AlbumsCompanion(
            albumKey: Value(canonicalKey),
            artistName: Value(winningArtist),
            trackCount: Value(survivorTracks.length),
            totalDurationMs: Value(totalMs),
          ),
        );

        await (update(tracks)..where((t) => t.albumId.equals(survivor.id))).write(
          TracksCompanion(
            albumArtist: Value(winningArtist),
            artworkPath: survivorArt != null
                ? Value(survivorArt)
                : const Value.absent(),
          ),
        );
      }
    }

    // Clean up empty albums & orphan artists
    await customStatement(
      'DELETE FROM albums WHERE id NOT IN (SELECT DISTINCT album_id FROM tracks WHERE album_id IS NOT NULL);',
    );
    await customStatement(
      'DELETE FROM artists WHERE id NOT IN (SELECT DISTINCT artist_id FROM tracks WHERE artist_id IS NOT NULL) AND id NOT IN (SELECT DISTINCT artist_id FROM albums WHERE artist_id IS NOT NULL);',
    );
  }

  bool _areAlbumArtistsCompatible(
    String? a1,
    String? a2, {
    String? albAlbumArtist,
    String? repAlbumArtist,
  }) {
    if (albAlbumArtist != null &&
        repAlbumArtist != null &&
        albAlbumArtist.isNotEmpty &&
        repAlbumArtist.isNotEmpty) {
      return albAlbumArtist.toLowerCase().trim() ==
          repAlbumArtist.toLowerCase().trim();
    }

    final effective1 =
        (albAlbumArtist?.isNotEmpty == true ? albAlbumArtist : a1)
            ?.toLowerCase()
            .trim() ??
        '';
    final effective2 =
        (repAlbumArtist?.isNotEmpty == true ? repAlbumArtist : a2)
            ?.toLowerCase()
            .trim() ??
        '';

    if (effective1.isEmpty || effective2.isEmpty) return true;
    if (effective1 == effective2) return true;

    return effective1.startsWith(effective2) ||
        effective2.startsWith(effective1) ||
        effective1.contains(effective2) ||
        effective2.contains(effective1);
  }

  String _findDominantOrBaseArtist(
    List<String> albumArtistNames,
    Map<String, int> trackArtistCounts,
  ) {
    if (trackArtistCounts.isNotEmpty) {
      final mostCommon = trackArtistCounts.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
      return mostCommon;
    }
    for (final name in albumArtistNames) {
      if (name.trim().isNotEmpty) return name.trim();
    }
    return 'Unknown Artist';
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'musii.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
