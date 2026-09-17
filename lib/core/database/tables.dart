import 'package:drift/drift.dart';

class Users extends Table {
  TextColumn get id => text()();
  TextColumn get email => text()();
  TextColumn get displayName => text().nullable()();
  TextColumn get photoUrl => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class MusicSources extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()(); // e.g. 'google_drive'
  TextColumn get accountEmail => text()();
  TextColumn get rootFolderId => text().nullable()();
  TextColumn get rootFolderName => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class DriveFolders extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId => text()();
  TextColumn get folderId => text()();
  TextColumn get name => text()();
  TextColumn get parentFolderId => text().nullable()();
  TextColumn get path => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ArtistRow')
class Artists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get normalizedName => text()();
  TextColumn get artworkPath => text().nullable()();
  IntColumn get trackCount => integer().withDefault(const Constant(0))();
  IntColumn get albumCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AlbumRow')
class Albums extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get normalizedTitle => text()();
  TextColumn get artistId => text().nullable()();
  TextColumn get artistName => text().nullable()();
  IntColumn get year => integer().nullable()();
  TextColumn get artworkPath => text().nullable()();
  IntColumn get trackCount => integer().withDefault(const Constant(0))();
  IntColumn get totalDurationMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('GenreRow')
class Genres extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get normalizedName => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TrackRow')
class Tracks extends Table {
  TextColumn get id => text()();
  TextColumn get driveFileId => text().unique()();
  TextColumn get sourceId => text()();
  TextColumn get title => text()();
  TextColumn get normalizedTitle => text()();
  TextColumn get artistId => text().nullable()();
  TextColumn get artistName => text().nullable()();
  TextColumn get albumId => text().nullable()();
  TextColumn get albumName => text().nullable()();
  TextColumn get albumArtist => text().nullable()();
  TextColumn get genre => text().nullable()();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get discNumber => integer().nullable()();
  IntColumn get year => integer().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  IntColumn get bitrate => integer().nullable()();
  IntColumn get sampleRate => integer().nullable()();
  IntColumn get bitDepth => integer().nullable()();
  IntColumn get channels => integer().nullable()();
  TextColumn get format => text().nullable()(); // 'MP3', 'FLAC', etc.
  IntColumn get fileSize => integer().withDefault(const Constant(0))();
  TextColumn get mimeType => text().nullable()();
  DateTimeColumn get driveModifiedAt => dateTime().nullable()();
  TextColumn get driveMd5Checksum => text().nullable()();
  TextColumn get localPath => text().nullable()();
  BoolColumn get isCached => boolean().withDefault(const Constant(false))();
  BoolColumn get isPinnedOffline =>
      boolean().withDefault(const Constant(false))();
  TextColumn get rawMetadataJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PlaylistRow')
class Playlists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get artworkPath => text().nullable()();
  IntColumn get trackCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class PlaylistTracks extends Table {
  TextColumn get id => text()();
  TextColumn get playlistId => text()();
  TextColumn get trackId => text()();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Favorites extends Table {
  TextColumn get id => text()();
  TextColumn get trackId => text().unique()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class RecentlyPlayed extends Table {
  TextColumn get id => text()();
  TextColumn get trackId => text()();
  DateTimeColumn get playedAt => dateTime()();
  IntColumn get playbackDurationMs =>
      integer().withDefault(const Constant(0))();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class PlaybackQueue extends Table {
  TextColumn get id => text()();
  TextColumn get trackId => text()();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class CacheEntries extends Table {
  TextColumn get id => text()();
  TextColumn get trackId => text().unique()();
  TextColumn get driveFileId => text()();
  TextColumn get localPath => text()();
  IntColumn get fileSize => integer()();
  TextColumn get state =>
      text()(); // 'not_cached', 'downloading', 'cached', 'failed'
  BoolColumn get isPinnedOffline =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get downloadedAt => dateTime().nullable()();
  DateTimeColumn get lastAccessedAt => dateTime()();
  TextColumn get checksum => text().nullable()();
  TextColumn get driveVersion => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SyncRunRow')
class SyncRuns extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId => text()();
  TextColumn get rootFolderId => text().nullable()();
  TextColumn get rootFolderName => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get lastCheckpointAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get status => text()(); // 'running', 'stopping', 'stopped', 'completed', 'failed', 'interrupted'
  TextColumn get phase => text().nullable()(); // 'scanning', 'extractingMetadata', 'updatingDatabase', 'complete', 'failed', 'stopped'
  TextColumn get currentFile => text().nullable()();
  TextColumn get errorMessage => text().nullable()();
  RealColumn get progressPercent => real().withDefault(const Constant(0.0))();
  IntColumn get filesDiscovered => integer().withDefault(const Constant(0))();
  IntColumn get filesProcessed => integer().withDefault(const Constant(0))();
  IntColumn get filesAdded => integer().withDefault(const Constant(0))();
  IntColumn get filesUpdated => integer().withDefault(const Constant(0))();
  IntColumn get filesRemoved => integer().withDefault(const Constant(0))();
  IntColumn get errorsCount => integer().withDefault(const Constant(0))();
  BoolColumn get discoveryCompleted =>
      boolean().withDefault(const Constant(false))();
  TextColumn get pendingFoldersJson => text().nullable()();
  TextColumn get visitedFoldersJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DiscoveredFileRow')
class DiscoveredFiles extends Table {
  TextColumn get id => text()(); // '${syncRunId}_${driveFileId}'
  TextColumn get syncRunId => text()();
  TextColumn get driveFileId => text()();
  TextColumn get name => text()();
  TextColumn get mimeType => text()();
  IntColumn get size => integer().withDefault(const Constant(0))();
  DateTimeColumn get modifiedTime => dateTime()();
  TextColumn get md5Checksum => text().nullable()();
  TextColumn get parentFolderId => text().nullable()();
  BoolColumn get isLrc => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncErrors extends Table {
  TextColumn get id => text()();
  TextColumn get syncRunId => text()();
  TextColumn get fileId => text().nullable()();
  TextColumn get fileName => text().nullable()();
  TextColumn get errorMessage => text()();
  TextColumn get errorType => text()();
  DateTimeColumn get occurredAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Artworks extends Table {
  TextColumn get id => text()();
  TextColumn get artworkKey => text().unique()();
  TextColumn get localPath => text()();
  TextColumn get mimeType => text().nullable()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  TextColumn get dominantColorHex => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class PlaybackStates extends Table {
  TextColumn get id => text()(); // 'current'
  TextColumn get currentTrackId => text().nullable()();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  BoolColumn get isPlaying => boolean().withDefault(const Constant(false))();
  BoolColumn get shuffleMode => boolean().withDefault(const Constant(false))();
  TextColumn get repeatMode => text().withDefault(const Constant('off'))();
  IntColumn get queueIndex => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('LyricRow')
class Lyrics extends Table {
  TextColumn get id => text()();
  TextColumn get trackId => text().unique()();
  TextColumn get source =>
      text()(); // 'embedded_synced', 'embedded_plain', 'sidecar_lrc', 'none'
  BoolColumn get isSynchronized =>
      boolean().withDefault(const Constant(false))();
  TextColumn get rawText => text().nullable()();
  IntColumn get offsetMs => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('LyricLineRow')
class LyricLines extends Table {
  TextColumn get id => text()();
  TextColumn get lyricsId => text()();
  IntColumn get timestampMs => integer()();
  TextColumn get content => text().named('text')();
  IntColumn get sequence => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('LyricWordRow')
class LyricWords extends Table {
  TextColumn get id => text()();
  TextColumn get lineId => text()();
  IntColumn get wordIndex => integer()();
  TextColumn get content => text().named('text')();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
