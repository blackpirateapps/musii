import 'dart:async';

import 'package:flutter/services.dart';

import '../../../core/error/failures.dart';
import '../domain/youtube_music_collection.dart';

typedef YouTubeTrackInfo = ({
  String videoId,
  String title,
  String? artist,
  int durationMs,
  String? artworkUrl,
});

typedef YouTubeHomeShelf = ({
  String title,
  List<YouTubeTrackInfo> tracks,
  List<YouTubeMusicCollection> collections,
});
typedef YouTubeSongPage = ({List<YouTubeTrackInfo> tracks, String? nextPage});
typedef YouTubeCollectionSearchPage = ({
  List<YouTubeMusicCollection> collections,
  String? nextPage,
});

class YouTubeMusicClient {
  const YouTubeMusicClient([
    this._channel = const MethodChannel('musii/youtube_music'),
  ]);

  final MethodChannel _channel;
  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

  Future<YouTubeTrackInfo> getTrack(String videoId) async {
    final response = await _request('getTrack', {'videoId': videoId});
    final track = _trackInfo(response, videoId);
    if (track == null) {
      throw const PlaybackFailure('The YouTube track details are unavailable.');
    }
    return track;
  }

  Future<List<YouTubeHomeShelf>> getHome() async {
    final response = await _request('getHome', const {});
    return _sections(response['sections']);
  }

  Future<({List<YouTubeHomeShelf> sections, String? nextPage})> getCollection(
    String browseId, {
    String? nextPage,
  }) async {
    final response = await _request('getCollection', {
      'browseId': browseId,
      'nextPage': ?nextPage,
    });
    return (
      sections: _sections(response['sections']),
      nextPage: response['nextPage'] as String?,
    );
  }

  Future<YouTubeCollectionSearchPage> searchCollections(
    String query,
    YouTubeMusicCategory category, {
    String? nextPage,
  }) async {
    final response = await _request('searchCollections', {
      'query': query,
      'kind': category.name,
      'nextPage': ?nextPage,
    });
    return (
      collections: _collections(response['collections']),
      nextPage: response['nextPage'] as String?,
    );
  }

  Future<String?> getLyrics(String videoId) async {
    final response = await _request('getLyrics', {'videoId': videoId});
    return response['lyrics'] as String?;
  }

  List<YouTubeHomeShelf> _sections(Object? sections) {
    if (sections is! List) return [];
    return sections
        .whereType<Map>()
        .map((section) {
          final title = section['title'];
          return (
            title: title is String && title.isNotEmpty ? title : '',
            tracks: _tracks(section['tracks']),
            collections: _collections(section['collections']),
          );
        })
        .where(
          (section) =>
              section.tracks.isNotEmpty || section.collections.isNotEmpty,
        )
        .toList();
  }

  List<YouTubeMusicCollection> _collections(Object? items) {
    if (items is! List) return [];
    return items
        .whereType<Map>()
        .map((item) {
          final browseId = item['browseId'];
          final title = item['title'];
          final category = YouTubeMusicCategory.values
              .where((kind) => kind.name == item['kind'])
              .firstOrNull;
          if (browseId is! String ||
              browseId.isEmpty ||
              title is! String ||
              title.trim().isEmpty ||
              category == null ||
              category == YouTubeMusicCategory.songs) {
            return null;
          }
          final subtitle = item['subtitle'];
          return (
            browseId: browseId,
            category: category,
            title: title,
            subtitle: subtitle is String && subtitle.isNotEmpty
                ? subtitle
                : null,
            artworkUrl: _httpsUri(item['artworkUrl'])?.toString(),
          );
        })
        .nonNulls
        .toList();
  }

  Future<YouTubeSongPage> searchSongs(String query, {String? nextPage}) async {
    if (query.trim().isEmpty) {
      return (tracks: const <YouTubeTrackInfo>[], nextPage: null);
    }
    final response = await _request('searchSongs', {
      'query': query,
      'nextPage': ?nextPage,
    });
    return (
      tracks: _tracks(response['tracks']),
      nextPage: response['nextPage'] as String?,
    );
  }

  Future<Uri> resolveAudio(String videoId) async {
    final response = await _request('resolveAudio', {'videoId': videoId});
    final uri = _httpsUri(response['url']);
    if (uri == null) {
      throw const PlaybackFailure('The YouTube audio stream is unavailable.');
    }
    return uri;
  }

  List<YouTubeTrackInfo> _tracks(Object? items) {
    if (items is! List) return [];
    return items
        .whereType<Map>()
        .map((data) {
          final videoId = data['videoId'];
          return videoId is String ? _trackInfo(data, videoId) : null;
        })
        .nonNulls
        .toList();
  }

  YouTubeTrackInfo? _trackInfo(Map<Object?, Object?> data, String videoId) {
    final title = data['title'];
    if (!_videoId.hasMatch(videoId) ||
        title is! String ||
        title.trim().isEmpty) {
      return null;
    }
    final artist = data['artist'];
    final duration = data['durationMs'];
    return (
      videoId: videoId,
      title: title,
      artist: artist is String && artist.trim().isNotEmpty ? artist : null,
      durationMs: duration is int && duration > 0 ? duration : 0,
      artworkUrl: _httpsUri(data['artworkUrl'])?.toString(),
    );
  }

  Future<Map<String, Object?>> _request(
    String method,
    Map<String, String> arguments,
  ) async {
    try {
      final response = await _channel
          .invokeMapMethod<String, Object?>(method, arguments)
          .timeout(const Duration(seconds: 30));
      if (response != null) return response;
      throw const PlaybackFailure('YouTube Music returned no track data.');
    } on MissingPluginException {
      throw const PlaybackFailure('YouTube Music playback requires Android.');
    } on TimeoutException {
      throw const NetworkFailure('YouTube Music timed out. Try again.');
    } on PlatformException catch (error) {
      throw switch (error.code) {
        'unavailable' => const PlaybackFailure(
          'This YouTube track is unavailable for playback.',
        ),
        'network' => const NetworkFailure(
          'Could not reach YouTube Music. Check your connection and try again.',
        ),
        _ => const PlaybackFailure('Could not load YouTube Music. Try again.'),
      };
    }
  }

  Uri? _httpsUri(Object? value) {
    final uri = value is String ? Uri.tryParse(value) : null;
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
        ? uri
        : null;
  }
}
