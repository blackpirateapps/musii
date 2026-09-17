import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

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
  int get schemaVersion => 5;

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
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'musii.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
