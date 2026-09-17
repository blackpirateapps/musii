import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/filesystem/app_file_system.dart';
import '../../core/services/connectivity_service.dart';
import '../../features/authentication/data/repositories/google_auth_repository.dart';
import '../../features/authentication/domain/entities/auth_user.dart';
import '../../features/cache/data/repositories/cache_repository_impl.dart';
import '../../features/cache/domain/entities/cache_entry.dart';
import '../../features/favorites/data/repositories/favorite_repository_impl.dart';
import '../../features/google_drive/data/repositories/google_drive_repository_impl.dart';
import '../../features/google_drive/domain/entities/drive_item.dart';
import '../../features/library/data/repositories/music_library_repository_impl.dart';
import '../../features/library/domain/entities/music_entities.dart';
import '../../features/library/domain/entities/sync_progress.dart';
import '../../features/metadata/data/datasources/artist_artwork_downloader.dart';
import '../../features/metadata/data/repositories/metadata_extractor_impl.dart';
import '../../features/lyrics/data/repositories/lyrics_repository_impl.dart';
import '../../features/lyrics/domain/entities/lyric_model.dart';
import '../../features/lyrics/domain/repositories/lyrics_repository.dart';
import '../../features/playback/data/repositories/playback_repository_impl.dart';
import '../../features/playback/domain/entities/playback_repository.dart';
import '../../features/playback/domain/entities/playback_state.dart';
import '../../features/playlists/domain/entities/playlist.dart';
import '../../features/playlists/domain/repositories/playlist_repository.dart';
import '../../features/playlists/data/repositories/playlist_repository_impl.dart';
import '../../features/recently_played/data/repositories/recently_played_repository_impl.dart';
import '../../features/search/data/repositories/search_repository_impl.dart';
import '../../features/settings/data/repositories/settings_repository_impl.dart';
import '../../features/settings/domain/entities/app_theme_mode.dart';
import '../../features/last_fm/presentation/providers/last_fm_providers.dart';

// Database & File System
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final appFileSystemProvider = Provider<AppFileSystem>((ref) {
  return AppFileSystem.instance;
});

// Authentication
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return GoogleAuthRepository(database: db);
});

final currentUserProvider = StreamProvider<AuthUser?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.watchCurrentUser();
});

// Google Drive
final googleDriveRepositoryProvider = Provider<GoogleDriveRepository>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  return GoogleDriveRepositoryImpl(authRepository: auth);
});

// Metadata
final metadataExtractorProvider = Provider<MetadataExtractor>((ref) {
  final fs = ref.watch(appFileSystemProvider);
  return MetadataExtractor(fileSystem: fs);
});

// Cache
final cacheRepositoryProvider = Provider<CacheRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final drive = ref.watch(googleDriveRepositoryProvider);
  final fs = ref.watch(appFileSystemProvider);
  return CacheRepositoryImpl(
    database: db,
    driveRepository: drive,
    fileSystem: fs,
  );
});

final cacheSizeProvider = StreamProvider<int>((ref) {
  final cache = ref.watch(cacheRepositoryProvider);
  return cache.watchCacheSize();
});

// Recently Played
final recentlyPlayedRepositoryProvider = Provider<RecentlyPlayedRepository>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  final fs = ref.watch(appFileSystemProvider);
  return RecentlyPlayedRepositoryImpl(database: db, fileSystem: fs);
});

final recentlyPlayedTracksProvider = StreamProvider<List<Track>>((ref) {
  final repo = ref.watch(recentlyPlayedRepositoryProvider);
  return repo.watchRecentlyPlayed();
});

// Favorites
final favoriteRepositoryProvider = Provider<FavoriteRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final fs = ref.watch(appFileSystemProvider);
  return FavoriteRepositoryImpl(database: db, fileSystem: fs);
});

final favoriteTracksProvider = StreamProvider<List<Track>>((ref) {
  final repo = ref.watch(favoriteRepositoryProvider);
  return repo.watchFavoriteTracks();
});

final isTrackFavoriteProvider = StreamProvider.family<bool, String>((
  ref,
  trackId,
) {
  final repo = ref.watch(favoriteRepositoryProvider);
  return repo.watchIsFavorite(trackId);
});

// Playlists
final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final fs = ref.watch(appFileSystemProvider);
  return PlaylistRepositoryImpl(database: db, fileSystem: fs);
});

final playlistsProvider = StreamProvider<List<Playlist>>((ref) {
  final repo = ref.watch(playlistRepositoryProvider);
  return repo.watchPlaylists();
});

final playlistTracksProvider = StreamProvider.family<List<Track>, String>((
  ref,
  playlistId,
) {
  final repo = ref.watch(playlistRepositoryProvider);
  return repo.watchPlaylistTracks(playlistId);
});

// Settings
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SettingsRepositoryImpl(database: db);
});

class ThemeModeNotifier extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() {
    final settings = ref.watch(settingsRepositoryProvider);
    settings.getThemeMode().then((mode) {
      state = mode;
    });
    return AppThemeMode.system;
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = mode;
    final settings = ref.read(settingsRepositoryProvider);
    await settings.setThemeMode(mode);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, AppThemeMode>(
  ThemeModeNotifier.new,
);

// Connectivity
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService();
});

// Playback & AudioHandler
final musiiAudioHandlerProvider = Provider<MusiiAudioHandler>((ref) {
  final cache = ref.watch(cacheRepositoryProvider);
  final recents = ref.watch(recentlyPlayedRepositoryProvider);
  final db = ref.watch(appDatabaseProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final lastFmCoordinator = ref.watch(lastFmPlaybackCoordinatorProvider);

  final handler = MusiiAudioHandler(
    cacheRepository: cache,
    recentlyPlayedRepository: recents,
    database: db,
    connectivityService: connectivity,
    lastFmCoordinator: lastFmCoordinator,
  );
  return handler;
});

final playbackRepositoryProvider = Provider<PlaybackRepository>((ref) {
  final handler = ref.watch(musiiAudioHandlerProvider);
  return PlaybackRepositoryImpl(audioHandler: handler);
});

final playerStateProvider = StreamProvider<PlayerStateSnapshot>((ref) {
  final repo = ref.watch(playbackRepositoryProvider);
  return repo.watchPlayerState();
});

// Lyrics
final lyricsRepositoryProvider = Provider<LyricsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return LyricsRepositoryImpl(database: db);
});

final trackLyricsProvider = StreamProvider.family<TrackLyrics?, String>((
  ref,
  trackId,
) {
  final repo = ref.watch(lyricsRepositoryProvider);
  return repo.watchLyricsForTrack(trackId);
});

final currentTrackLyricsProvider = StreamProvider<TrackLyrics?>((ref) {
  final playerSnapshot = ref.watch(playerStateProvider).value;
  final track = playerSnapshot?.currentTrack;
  if (track == null) return Stream.value(null);
  final repo = ref.watch(lyricsRepositoryProvider);
  return repo.watchLyricsForTrack(track.id);
});

// Artist Artwork Downloader
final artistArtworkDownloaderProvider = Provider<ArtistArtworkDownloader>((
  ref,
) {
  final fs = ref.watch(appFileSystemProvider);
  final db = ref.watch(appDatabaseProvider);
  return ArtistArtworkDownloader(fileSystem: fs, database: db);
});

// Library
final musicLibraryRepositoryProvider = Provider<MusicLibraryRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final drive = ref.watch(googleDriveRepositoryProvider);
  final extractor = ref.watch(metadataExtractorProvider);
  final lyrics = ref.watch(lyricsRepositoryProvider);
  final fs = ref.watch(appFileSystemProvider);
  final downloader = ref.watch(artistArtworkDownloaderProvider);

  return MusicLibraryRepositoryImpl(
    database: db,
    driveRepository: drive,
    metadataExtractor: extractor,
    lyricsRepository: lyrics,
    fileSystem: fs,
    artistArtworkDownloader: downloader,
  );
});

final allTracksProvider = StreamProvider.family<List<Track>, String?>((
  ref,
  sortBy,
) {
  final repo = ref.watch(musicLibraryRepositoryProvider);
  return repo.watchAllTracks(sortBy: sortBy);
});

final allAlbumsProvider = StreamProvider<List<Album>>((ref) {
  final repo = ref.watch(musicLibraryRepositoryProvider);
  return repo.watchAllAlbums();
});

final allArtistsProvider = StreamProvider<List<Artist>>((ref) {
  final repo = ref.watch(musicLibraryRepositoryProvider);
  return repo.watchAllArtists();
});

final albumDetailProvider = StreamProvider.family<AlbumWithTracks?, String>((
  ref,
  albumId,
) {
  final repo = ref.watch(musicLibraryRepositoryProvider);
  return repo.watchAlbum(albumId);
});

final artistDetailProvider = StreamProvider.family<ArtistWithAlbums?, String>((
  ref,
  artistId,
) {
  final repo = ref.watch(musicLibraryRepositoryProvider);
  return repo.watchArtist(artistId);
});

final syncProgressProvider = StreamProvider<SyncProgress>((ref) {
  final repo = ref.watch(musicLibraryRepositoryProvider);
  return repo.watchSyncProgress();
});

// Search
final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final fs = ref.watch(appFileSystemProvider);
  return SearchRepositoryImpl(database: db, fileSystem: fs);
});

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  @override
  set state(String value) => super.state = value;
}

final searchQueryStateProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

final searchResultsProvider = FutureProvider<SearchResults>((ref) async {
  final query = ref.watch(searchQueryStateProvider);
  final repo = ref.watch(searchRepositoryProvider);
  if (query.trim().isEmpty) return const SearchResults();
  final result = await repo.search(query);
  return result.dataOrNull ?? const SearchResults();
});
