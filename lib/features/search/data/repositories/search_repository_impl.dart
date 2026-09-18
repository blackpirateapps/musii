import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/filesystem/app_file_system.dart';
import '../../../../core/result/result.dart';
import '../../../library/domain/entities/music_entities.dart';
import '../../../metadata/domain/services/metadata_normalization_service.dart';
import '../../../playlists/domain/entities/playlist_entities.dart';

@immutable
class SearchResults {
  final List<Track> tracks;
  final List<Album> albums;
  final List<Artist> artists;
  final List<Playlist> playlists;

  const SearchResults({
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
  });

  bool get isEmpty =>
      tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;

  bool get isNotEmpty => !isEmpty;
}

abstract class SearchRepository {
  Future<Result<SearchResults, AppFailure>> search(String query);
}

class SearchRepositoryImpl implements SearchRepository {
  final AppDatabase _database;
  final AppFileSystem _fileSystem;

  SearchRepositoryImpl({
    required AppDatabase database,
    AppFileSystem? fileSystem,
  }) : _database = database,
       _fileSystem = fileSystem ?? AppFileSystem.instance;

  String? _resolveArtworkPath(String? album, String? artist) {
    if (album == null && artist == null) return null;
    final key = MetadataNormalizationService.computeArtworkKey(album, artist);
    final file = _fileSystem.getArtworkCacheFile(key);
    return file.existsSync() ? file.path : null;
  }

  Track _mapDbTrackToEntity(TrackRow row) {
    return Track(
      id: row.id,
      driveFileId: row.driveFileId,
      sourceId: row.sourceId,
      title: row.title,
      normalizedTitle: row.normalizedTitle,
      artistId: row.artistId,
      artistName: row.artistName,
      albumId: row.albumId,
      albumName: row.albumName,
      albumArtist: row.albumArtist,
      genre: row.genre,
      trackNumber: row.trackNumber,
      discNumber: row.discNumber,
      year: row.year,
      durationMs: row.durationMs,
      bitrate: row.bitrate,
      sampleRate: row.sampleRate,
      bitDepth: row.bitDepth,
      channels: row.channels,
      format: row.format,
      fileSize: row.fileSize,
      mimeType: row.mimeType,
      driveModifiedAt: row.driveModifiedAt,
      localPath: row.localPath,
      isCached: row.isCached,
      isPinnedOffline: row.isPinnedOffline,
      artworkPath:
          row.artworkPath ??
          _resolveArtworkPath(row.albumName, row.albumArtist) ??
          _resolveArtworkPath(row.albumName, row.artistName),
    );
  }

  @override
  Future<Result<SearchResults, AppFailure>> search(String query) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) {
      return const Result.success(SearchResults());
    }

    try {
      final likePattern = '%$cleanQuery%';

      // 1. Search Tracks
      final trackRows =
          await (_database.select(_database.tracks)..where(
                (tbl) =>
                    tbl.normalizedTitle.like(likePattern) |
                    tbl.artistName.like(likePattern) |
                    tbl.albumName.like(likePattern) |
                    tbl.genre.like(likePattern),
              ))
              .get();

      // Rank exact matches first
      final tracks = trackRows.map(_mapDbTrackToEntity).toList()
        ..sort((a, b) {
          final aExact =
              a.normalizedTitle == cleanQuery ||
              a.title.toLowerCase() == cleanQuery;
          final bExact =
              b.normalizedTitle == cleanQuery ||
              b.title.toLowerCase() == cleanQuery;
          if (aExact && !bExact) return -1;
          if (!aExact && bExact) return 1;
          return a.normalizedTitle.compareTo(b.normalizedTitle);
        });

      // 2. Search Albums
      final albumRows =
          await (_database.select(_database.albums)..where(
                (tbl) =>
                    tbl.normalizedTitle.like(likePattern) |
                    tbl.artistName.like(likePattern),
              ))
              .get();

      final albums =
          albumRows
              .map(
                (r) => Album(
                  id: r.id,
                  title: r.title,
                  normalizedTitle: r.normalizedTitle,
                  artistId: r.artistId,
                  artistName: r.artistName,
                  year: r.year,
                  artworkPath:
                      r.artworkPath ??
                      _resolveArtworkPath(r.title, r.artistName),
                  trackCount: r.trackCount,
                  totalDurationMs: r.totalDurationMs,
                ),
              )
              .toList()
            ..sort((a, b) {
              final aExact = a.normalizedTitle == cleanQuery;
              final bExact = b.normalizedTitle == cleanQuery;
              if (aExact && !bExact) return -1;
              if (!aExact && bExact) return 1;
              return a.normalizedTitle.compareTo(b.normalizedTitle);
            });

      // 3. Search Artists
      final artistRows = await (_database.select(
        _database.artists,
      )..where((tbl) => tbl.normalizedName.like(likePattern))).get();

      final artists = artistRows
          .map(
            (r) => Artist(
              id: r.id,
              name: r.name,
              normalizedName: r.normalizedName,
              artworkPath: r.artworkPath,
              trackCount: r.trackCount,
              albumCount: r.albumCount,
            ),
          )
          .toList();

      // 4. Search Playlists
      final playlistRows = await (_database.select(
        _database.playlists,
      )..where((tbl) => tbl.name.like(likePattern))).get();

      final playlists = playlistRows
          .map(
            (r) => Playlist(
              id: r.id,
              name: r.name,
              description: r.description,
              artworkPath: r.artworkPath,
              trackCount: r.trackCount,
              createdAt: r.createdAt,
              updatedAt: r.updatedAt,
            ),
          )
          .toList();

      return Result.success(
        SearchResults(
          tracks: tracks,
          albums: albums,
          artists: artists,
          playlists: playlists,
        ),
      );
    } catch (e) {
      return Result.failure(DatabaseFailure('Search failed', cause: e));
    }
  }
}
