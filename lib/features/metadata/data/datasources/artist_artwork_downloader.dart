import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../../../../core/database/app_database.dart';
import '../../../../core/filesystem/app_file_system.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../library/domain/entities/music_entities.dart';

class ArtistArtworkDownloader {
  final http.Client _client;
  final AppFileSystem _fileSystem;
  final AppDatabase _database;

  ArtistArtworkDownloader({
    http.Client? client,
    required AppFileSystem fileSystem,
    required AppDatabase database,
  })  : _client = client ?? http.Client(),
        _fileSystem = fileSystem,
        _database = database;

  /// Fetches and saves an artist's official photo from Deezer's public API.
  /// Returns the local cached image file path if successful, or null on failure.
  Future<String?> downloadArtistArtwork(Artist artist) async {
    final artistName = artist.name.trim();
    if (artistName.isEmpty) return null;

    // 1. If artist already has an existing valid artwork file on disk, return it.
    if (artist.artworkPath != null && artist.artworkPath!.isNotEmpty) {
      final existingFile = File(artist.artworkPath!);
      if (existingFile.existsSync()) {
        return existingFile.path;
      }
    }

    // 2. Check if already cached in AppFileSystem
    final cacheFile = _fileSystem.getArtworkCacheFile('artist_${artist.normalizedName}');
    if (cacheFile.existsSync()) {
      await (_database.update(_database.artists)..where((tbl) => tbl.id.equals(artist.id)))
          .write(ArtistsCompanion(artworkPath: Value(cacheFile.path)));
      return cacheFile.path;
    }

    // 3. Query Deezer Public Search API (Zero API key needed)
    try {
      final uri = Uri.parse(
        'https://api.deezer.com/search/artist?q=${Uri.encodeComponent(artistName)}',
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        AppLogger.debug(
          LogCategory.metadata,
          'Deezer artist search returned status ${response.statusCode} for "$artistName"',
        );
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'] as List<dynamic>?;
      if (data == null || data.isEmpty) {
        AppLogger.debug(
          LogCategory.metadata,
          'No artist found on Deezer for "$artistName"',
        );
        return null;
      }

      // Pick first result
      final firstMatch = data.first as Map<String, dynamic>;
      final pictureUrl = (firstMatch['picture_big'] ??
              firstMatch['picture_medium'] ??
              firstMatch['picture']) as String?;

      if (pictureUrl == null || pictureUrl.isEmpty) {
        return null;
      }

      // 4. Download artist picture bytes
      final imgResponse = await _client
          .get(Uri.parse(pictureUrl))
          .timeout(const Duration(seconds: 15));

      if (imgResponse.statusCode == 200 && imgResponse.bodyBytes.isNotEmpty) {
        if (!cacheFile.parent.existsSync()) {
          await cacheFile.parent.create(recursive: true);
        }
        await cacheFile.writeAsBytes(imgResponse.bodyBytes, flush: true);

        // Update database record
        await (_database.update(_database.artists)..where((tbl) => tbl.id.equals(artist.id)))
            .write(ArtistsCompanion(artworkPath: Value(cacheFile.path)));

        AppLogger.info(
          LogCategory.metadata,
          'Successfully downloaded artist artwork for "$artistName" (${imgResponse.bodyBytes.length} bytes)',
        );
        return cacheFile.path;
      }
    } catch (e, st) {
      AppLogger.debug(
        LogCategory.metadata,
        'Failed to fetch artist artwork for "$artistName"',
        e,
        st,
      );
    }

    return null;
  }

  /// Downloads missing artist artworks in the background with small delays to avoid bursting.
  Future<void> downloadMissingArtworks(List<Artist> artists) async {
    for (final artist in artists) {
      final hasLocal = artist.artworkPath != null &&
          artist.artworkPath!.isNotEmpty &&
          File(artist.artworkPath!).existsSync();
      if (!hasLocal) {
        await downloadArtistArtwork(artist);
        // Small throttle between network requests
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }
  }
}
