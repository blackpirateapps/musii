import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musii/core/database/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('musii_mig_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  File createDbFile(String name) {
    return File(p.join(tempDir.path, name));
  }

  void seedV1Tables(raw_sqlite.Database db) {
    db.execute('''
      CREATE TABLE users (
        id TEXT NOT NULL PRIMARY KEY,
        email TEXT NOT NULL,
        display_name TEXT,
        photo_url TEXT,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE music_sources (
        id TEXT NOT NULL PRIMARY KEY,
        type TEXT NOT NULL,
        account_email TEXT NOT NULL,
        root_folder_id TEXT,
        root_folder_name TEXT,
        created_at INTEGER NOT NULL,
        last_synced_at INTEGER
      );
      CREATE TABLE drive_folders (
        id TEXT NOT NULL PRIMARY KEY,
        source_id TEXT NOT NULL,
        folder_id TEXT NOT NULL,
        name TEXT NOT NULL,
        parent_folder_id TEXT,
        path TEXT NOT NULL
      );
      CREATE TABLE artists (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        normalized_name TEXT NOT NULL,
        artwork_path TEXT,
        track_count INTEGER NOT NULL DEFAULT 0,
        album_count INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE albums (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL,
        normalized_title TEXT NOT NULL,
        artist_id TEXT,
        artist_name TEXT,
        year INTEGER,
        artwork_path TEXT,
        track_count INTEGER NOT NULL DEFAULT 0,
        total_duration_ms INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE genres (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        normalized_name TEXT NOT NULL
      );
      CREATE TABLE tracks (
        id TEXT NOT NULL PRIMARY KEY,
        drive_file_id TEXT NOT NULL UNIQUE,
        source_id TEXT NOT NULL,
        title TEXT NOT NULL,
        normalized_title TEXT NOT NULL,
        artist_id TEXT,
        artist_name TEXT,
        album_id TEXT,
        album_name TEXT,
        album_artist TEXT,
        genre TEXT,
        track_number INTEGER,
        disc_number INTEGER,
        year INTEGER,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        bitrate INTEGER,
        sample_rate INTEGER,
        bit_depth INTEGER,
        channels INTEGER,
        format TEXT,
        file_size INTEGER NOT NULL DEFAULT 0,
        mime_type TEXT,
        drive_modified_at INTEGER,
        drive_md5_checksum TEXT,
        local_path TEXT,
        is_cached INTEGER NOT NULL DEFAULT 0 CHECK (is_cached IN (0, 1)),
        is_pinned_offline INTEGER NOT NULL DEFAULT 0 CHECK (is_pinned_offline IN (0, 1)),
        raw_metadata_json TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE playlists (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        artwork_path TEXT,
        track_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE playlist_tracks (
        id TEXT NOT NULL PRIMARY KEY,
        playlist_id TEXT NOT NULL,
        track_id TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        added_at INTEGER NOT NULL
      );
      CREATE TABLE favorites (
        id TEXT NOT NULL PRIMARY KEY,
        track_id TEXT NOT NULL UNIQUE,
        added_at INTEGER NOT NULL
      );
      CREATE TABLE recently_played (
        id TEXT NOT NULL PRIMARY KEY,
        track_id TEXT NOT NULL,
        played_at INTEGER NOT NULL,
        playback_duration_ms INTEGER NOT NULL DEFAULT 0,
        completed INTEGER NOT NULL DEFAULT 0 CHECK (completed IN (0, 1))
      );
      CREATE TABLE playback_queue (
        id TEXT NOT NULL PRIMARY KEY,
        track_id TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        added_at INTEGER NOT NULL
      );
      CREATE TABLE cache_entries (
        id TEXT NOT NULL PRIMARY KEY,
        track_id TEXT NOT NULL UNIQUE,
        drive_file_id TEXT NOT NULL,
        local_path TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        state TEXT NOT NULL,
        is_pinned_offline INTEGER NOT NULL DEFAULT 0 CHECK (is_pinned_offline IN (0, 1)),
        downloaded_at INTEGER,
        last_accessed_at INTEGER NOT NULL,
        checksum TEXT,
        drive_version TEXT
      );
      CREATE TABLE sync_runs (
        id TEXT NOT NULL PRIMARY KEY,
        source_id TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        completed_at INTEGER,
        status TEXT NOT NULL,
        files_discovered INTEGER NOT NULL DEFAULT 0,
        files_processed INTEGER NOT NULL DEFAULT 0,
        files_added INTEGER NOT NULL DEFAULT 0,
        files_updated INTEGER NOT NULL DEFAULT 0,
        files_removed INTEGER NOT NULL DEFAULT 0,
        errors_count INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE sync_errors (
        id TEXT NOT NULL PRIMARY KEY,
        sync_run_id TEXT NOT NULL,
        file_id TEXT,
        file_name TEXT,
        error_message TEXT NOT NULL,
        error_type TEXT NOT NULL
      );
      CREATE TABLE artworks (
        key TEXT NOT NULL PRIMARY KEY,
        local_path TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        last_accessed_at INTEGER NOT NULL
      );
      CREATE TABLE app_settings (
        key TEXT NOT NULL PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE playback_states (
        id TEXT NOT NULL PRIMARY KEY,
        current_track_id TEXT,
        position_ms INTEGER NOT NULL DEFAULT 0,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        is_playing INTEGER NOT NULL DEFAULT 0 CHECK (is_playing IN (0, 1)),
        shuffle_mode INTEGER NOT NULL DEFAULT 0 CHECK (shuffle_mode IN (0, 1)),
        repeat_mode TEXT NOT NULL DEFAULT 'off',
        queue_index INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      );
    ''');
  }

  void seedV2V3Lyrics(raw_sqlite.Database db) {
    db.execute('''
      CREATE TABLE lyrics (
        id TEXT NOT NULL PRIMARY KEY,
        track_id TEXT NOT NULL UNIQUE,
        source TEXT NOT NULL,
        is_synchronized INTEGER NOT NULL DEFAULT 0 CHECK (is_synchronized IN (0, 1)),
        raw_text TEXT,
        offset_ms INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE lyric_lines (
        id TEXT NOT NULL PRIMARY KEY,
        lyrics_id TEXT NOT NULL,
        timestamp_ms INTEGER NOT NULL,
        text TEXT NOT NULL,
        sequence INTEGER NOT NULL
      );
      CREATE TABLE lyric_words (
        id TEXT NOT NULL PRIMARY KEY,
        line_id TEXT NOT NULL,
        word_index INTEGER NOT NULL,
        text TEXT NOT NULL,
        start_ms INTEGER NOT NULL,
        end_ms INTEGER NOT NULL
      );
    ''');
  }

  void seedV4SyncRunColumns(raw_sqlite.Database db) {
    db.execute('''
      ALTER TABLE sync_runs ADD COLUMN root_folder_id TEXT;
      ALTER TABLE sync_runs ADD COLUMN root_folder_name TEXT;
      ALTER TABLE sync_runs ADD COLUMN updated_at INTEGER;
      ALTER TABLE sync_runs ADD COLUMN last_checkpoint_at INTEGER;
      ALTER TABLE sync_runs ADD COLUMN phase TEXT;
      ALTER TABLE sync_runs ADD COLUMN current_file TEXT;
      ALTER TABLE sync_runs ADD COLUMN error_message TEXT;
      ALTER TABLE sync_runs ADD COLUMN progress_percent REAL NOT NULL DEFAULT 0.0;
    ''');
  }

  void seedV5DiscoveredFilesLegacy(raw_sqlite.Database db) {
    db.execute('''
      CREATE TABLE discovered_files (
        id TEXT NOT NULL PRIMARY KEY,
        sync_run_id TEXT NOT NULL,
        drive_file_id TEXT NOT NULL,
        name TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        size INTEGER NOT NULL DEFAULT 0,
        modified_time INTEGER NOT NULL,
        md5_checksum TEXT,
        parent_folder_id TEXT,
        is_lrc INTEGER NOT NULL DEFAULT 0 CHECK (is_lrc IN (0, 1))
      );
      ALTER TABLE sync_runs ADD COLUMN discovery_completed INTEGER NOT NULL DEFAULT 0 CHECK (discovery_completed IN (0, 1));
      ALTER TABLE sync_runs ADD COLUMN pending_folders_json TEXT;
      ALTER TABLE sync_runs ADD COLUMN visited_folders_json TEXT;
    ''');
  }

  group('Database Migration Suite', () {
    test('fresh database creation initializes at schemaVersion 10 with all tables', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final syncRuns = await db.select(db.syncRuns).get();
      expect(syncRuns, isEmpty);

      final discoveredFiles = await db.select(db.discoveredFiles).get();
      expect(discoveredFiles, isEmpty);

      final userVersionResult =
          await db.customSelect('PRAGMA user_version;').getSingle();
      expect(userVersionResult.read<int>('user_version'), 10);
    });

    test('reproduction: migration from schema v4 to v10 succeeds without duplicate column error', () async {
      final dbFile = createDbFile('v4_to_v10.sqlite');

      final rawDb = raw_sqlite.sqlite3.open(dbFile.path);
      seedV1Tables(rawDb);
      seedV2V3Lyrics(rawDb);
      seedV4SyncRunColumns(rawDb);
      rawDb.execute('PRAGMA user_version = 4;');
      rawDb.dispose();

      final db = AppDatabase(NativeDatabase(dbFile));
      addTearDown(db.close);

      // Prior to our fix, this threw:
      // SqliteException(1): duplicate column name: is_processed
      final discoveredList = await db.select(db.discoveredFiles).get();
      expect(discoveredList, isEmpty);

      final uvResult =
          await db.customSelect('PRAGMA user_version;').getSingle();
      expect(uvResult.read<int>('user_version'), 10);

      // Verify columns in discovered_files exist and can be inserted/selected
      final now = DateTime.now();
      await db.into(db.discoveredFiles).insert(
            DiscoveredFilesCompanion.insert(
              id: 'sync1_file1',
              syncRunId: 'sync1',
              driveFileId: 'drive1',
              name: 'song.mp3',
              mimeType: 'audio/mpeg',
              modifiedTime: now,
              isProcessed: const Value(true),
              processStatus: const Value('added'),
              processedAt: Value(now),
            ),
          );

      final inserted = await (db.select(db.discoveredFiles)
            ..where((tbl) => tbl.id.equals('sync1_file1')))
          .getSingle();
      expect(inserted.isProcessed, isTrue);
      expect(inserted.processStatus, 'added');
      expect(inserted.processedAt, isNotNull);

      // Verify sync_runs has v5 columns
      await db.into(db.syncRuns).insert(
            SyncRunsCompanion.insert(
              id: 'sync1',
              sourceId: 'gdrive',
              startedAt: now,
              status: 'running',
              discoveryCompleted: const Value(true),
              pendingFoldersJson: const Value('[]'),
              visitedFoldersJson: const Value('["root"]'),
            ),
          );
      final run = await (db.select(db.syncRuns)
            ..where((tbl) => tbl.id.equals('sync1')))
          .getSingle();
      expect(run.discoveryCompleted, isTrue);

      // Verify tracks has v10 artworkPath column
      await db.into(db.tracks).insert(
            TracksCompanion.insert(
              id: 'track1',
              driveFileId: 'df1',
              sourceId: 'gdrive',
              title: 'Song',
              normalizedTitle: 'song',
              artworkPath: const Value('/path/to/art.jpg'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final track = await (db.select(db.tracks)
            ..where((tbl) => tbl.id.equals('track1')))
          .getSingle();
      expect(track.artworkPath, '/path/to/art.jpg');
    });

    test('migration from schema v1 to v10 succeeds seamlessly', () async {
      final dbFile = createDbFile('v1_to_v10.sqlite');

      final rawDb = raw_sqlite.sqlite3.open(dbFile.path);
      seedV1Tables(rawDb);
      rawDb.execute('PRAGMA user_version = 1;');
      rawDb.dispose();

      final db = AppDatabase(NativeDatabase(dbFile));
      addTearDown(db.close);

      final discoveredList = await db.select(db.discoveredFiles).get();
      expect(discoveredList, isEmpty);

      final uvResult =
          await db.customSelect('PRAGMA user_version;').getSingle();
      expect(uvResult.read<int>('user_version'), 10);
    });

    test('migration from schema v5 (with legacy discovered_files without is_processed) to v10', () async {
      final dbFile = createDbFile('v5_to_v10.sqlite');

      final rawDb = raw_sqlite.sqlite3.open(dbFile.path);
      seedV1Tables(rawDb);
      seedV2V3Lyrics(rawDb);
      seedV4SyncRunColumns(rawDb);
      seedV5DiscoveredFilesLegacy(rawDb);
      rawDb.execute('PRAGMA user_version = 5;');
      rawDb.dispose();

      final db = AppDatabase(NativeDatabase(dbFile));
      addTearDown(db.close);

      // Migration must add is_processed, process_status, processed_at
      final discoveredList = await db.select(db.discoveredFiles).get();
      expect(discoveredList, isEmpty);

      final uvResult =
          await db.customSelect('PRAGMA user_version;').getSingle();
      expect(uvResult.read<int>('user_version'), 10);

      // Ensure newly added columns can be written and read
      final now = DateTime.now();
      await db.into(db.discoveredFiles).insert(
            DiscoveredFilesCompanion.insert(
              id: 'sync5_file1',
              syncRunId: 'sync5',
              driveFileId: 'df5',
              name: 'test.flac',
              mimeType: 'audio/flac',
              modifiedTime: now,
              isProcessed: const Value(true),
              processStatus: const Value('updated'),
            ),
          );

      final row = await (db.select(db.discoveredFiles)
            ..where((tbl) => tbl.id.equals('sync5_file1')))
          .getSingle();
      expect(row.isProcessed, isTrue);
      expect(row.processStatus, 'updated');
    });

    test('migration from schema v9 to v10 adds tracks.artwork_path and backfills from albums', () async {
      final dbFile = createDbFile('v9_to_v10.sqlite');

      final rawDb = raw_sqlite.sqlite3.open(dbFile.path);
      seedV1Tables(rawDb);
      seedV2V3Lyrics(rawDb);
      seedV4SyncRunColumns(rawDb);
      seedV5DiscoveredFilesLegacy(rawDb);

      // Add v6 album_key to albums
      rawDb.execute('ALTER TABLE albums ADD COLUMN album_key TEXT;');

      // Add v9 columns to discovered_files
      rawDb.execute('''
        ALTER TABLE discovered_files ADD COLUMN is_processed INTEGER NOT NULL DEFAULT 0 CHECK (is_processed IN (0, 1));
        ALTER TABLE discovered_files ADD COLUMN process_status TEXT;
        ALTER TABLE discovered_files ADD COLUMN processed_at INTEGER;
      ''');

      // Insert album with artwork and track without artwork
      rawDb.execute('''
        INSERT INTO albums (id, album_key, title, normalized_title, artwork_path)
        VALUES ('alb1', 'key1', 'Album 1', 'album 1', '/cache/artworks/alb1.jpg');

        INSERT INTO tracks (id, drive_file_id, source_id, title, normalized_title, album_id, duration_ms, file_size, created_at, updated_at)
        VALUES ('t1', 'df1', 'src1', 'Track 1', 'track 1', 'alb1', 200000, 5000000, 1000, 1000);
      ''');

      rawDb.execute('PRAGMA user_version = 9;');
      rawDb.dispose();

      final db = AppDatabase(NativeDatabase(dbFile));
      addTearDown(db.close);

      final track = await (db.select(db.tracks)
            ..where((tbl) => tbl.id.equals('t1')))
          .getSingle();

      expect(track.artworkPath, '/cache/artworks/alb1.jpg');

      final uvResult =
          await db.customSelect('PRAGMA user_version;').getSingle();
      expect(uvResult.read<int>('user_version'), 10);
    });

    test('idempotency: re-running onUpgrade with existing tables/columns does not error', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // First run: onCreate to v10
      await db.select(db.tracks).get();

      // Manually invoke onUpgrade from 1 to 10 on the already fully formed database
      final migrator = db.createMigrator();
      await expectLater(
        db.migration.onUpgrade(migrator, 1, 10),
        completes,
      );

      // Verify database still operates normally
      final tracks = await db.select(db.tracks).get();
      expect(tracks, isEmpty);
    });
  });
}
