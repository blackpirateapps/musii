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
    SyncErrors,
    Artworks,
    AppSettings,
    PlaybackStates,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 1;

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
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Migration logic for future versions
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
