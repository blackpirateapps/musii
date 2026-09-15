import 'package:flutter/foundation.dart';

@immutable
class Track {
  final String id;
  final String driveFileId;
  final String sourceId;
  final String title;
  final String normalizedTitle;
  final String? artistId;
  final String? artistName;
  final String? albumId;
  final String? albumName;
  final String? albumArtist;
  final String? genre;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final int durationMs;
  final int? bitrate;
  final int? sampleRate;
  final int? bitDepth;
  final int? channels;
  final String? format;
  final int fileSize;
  final String? mimeType;
  final DateTime? driveModifiedAt;
  final String? localPath;
  final bool isCached;
  final bool isPinnedOffline;
  final String? artworkPath;

  const Track({
    required this.id,
    required this.driveFileId,
    required this.sourceId,
    required this.title,
    required this.normalizedTitle,
    this.artistId,
    this.artistName,
    this.albumId,
    this.albumName,
    this.albumArtist,
    this.genre,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.durationMs = 0,
    this.bitrate,
    this.sampleRate,
    this.bitDepth,
    this.channels,
    this.format,
    this.fileSize = 0,
    this.mimeType,
    this.driveModifiedAt,
    this.localPath,
    this.isCached = false,
    this.isPinnedOffline = false,
    this.artworkPath,
  });

  Track copyWith({
    String? id,
    String? driveFileId,
    String? sourceId,
    String? title,
    String? normalizedTitle,
    String? artistId,
    String? artistName,
    String? albumId,
    String? albumName,
    String? albumArtist,
    String? genre,
    int? trackNumber,
    int? discNumber,
    int? year,
    int? durationMs,
    int? bitrate,
    int? sampleRate,
    int? bitDepth,
    int? channels,
    String? format,
    int? fileSize,
    String? mimeType,
    DateTime? driveModifiedAt,
    String? localPath,
    bool? isCached,
    bool? isPinnedOffline,
    String? artworkPath,
  }) {
    return Track(
      id: id ?? this.id,
      driveFileId: driveFileId ?? this.driveFileId,
      sourceId: sourceId ?? this.sourceId,
      title: title ?? this.title,
      normalizedTitle: normalizedTitle ?? this.normalizedTitle,
      artistId: artistId ?? this.artistId,
      artistName: artistName ?? this.artistName,
      albumId: albumId ?? this.albumId,
      albumName: albumName ?? this.albumName,
      albumArtist: albumArtist ?? this.albumArtist,
      genre: genre ?? this.genre,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      year: year ?? this.year,
      durationMs: durationMs ?? this.durationMs,
      bitrate: bitrate ?? this.bitrate,
      sampleRate: sampleRate ?? this.sampleRate,
      bitDepth: bitDepth ?? this.bitDepth,
      channels: channels ?? this.channels,
      format: format ?? this.format,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      driveModifiedAt: driveModifiedAt ?? this.driveModifiedAt,
      localPath: localPath ?? this.localPath,
      isCached: isCached ?? this.isCached,
      isPinnedOffline: isPinnedOffline ?? this.isPinnedOffline,
      artworkPath: artworkPath ?? this.artworkPath,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Track && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Track(id: $id, title: $title, artist: $artistName)';
}

@immutable
class Album {
  final String id;
  final String title;
  final String normalizedTitle;
  final String? artistId;
  final String? artistName;
  final int? year;
  final String? artworkPath;
  final int trackCount;
  final int totalDurationMs;

  const Album({
    required this.id,
    required this.title,
    required this.normalizedTitle,
    this.artistId,
    this.artistName,
    this.year,
    this.artworkPath,
    this.trackCount = 0,
    this.totalDurationMs = 0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Album && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Album(id: $id, title: $title, artist: $artistName)';
}

@immutable
class Artist {
  final String id;
  final String name;
  final String normalizedName;
  final String? artworkPath;
  final int trackCount;
  final int albumCount;

  const Artist({
    required this.id,
    required this.name,
    required this.normalizedName,
    this.artworkPath,
    this.trackCount = 0,
    this.albumCount = 0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Artist && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Artist(id: $id, name: $name)';
}

@immutable
class Genre {
  final String id;
  final String name;
  final String normalizedName;

  const Genre({
    required this.id,
    required this.name,
    required this.normalizedName,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Genre && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

@immutable
class AlbumWithTracks {
  final Album album;
  final List<Track> tracks;

  const AlbumWithTracks({required this.album, required this.tracks});
}

@immutable
class ArtistWithAlbums {
  final Artist artist;
  final List<Album> albums;
  final List<Track> topTracks;

  const ArtistWithAlbums({
    required this.artist,
    required this.albums,
    required this.topTracks,
  });
}
