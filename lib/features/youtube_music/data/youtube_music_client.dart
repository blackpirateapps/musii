import 'dart:async';

import 'package:flutter/services.dart';

import '../../../core/error/failures.dart';

typedef YouTubeTrackInfo = ({
  String title,
  String? artist,
  int durationMs,
  String? artworkUrl,
});

class YouTubeMusicClient {
  const YouTubeMusicClient([
    this._channel = const MethodChannel('musii/youtube_music'),
  ]);

  final MethodChannel _channel;

  Future<YouTubeTrackInfo> getTrack(String videoId) async {
    final response = await _request('getTrack', videoId);
    final title = response['title'];
    if (title is! String || title.trim().isEmpty) {
      throw const PlaybackFailure('The YouTube track details are unavailable.');
    }
    return (
      title: title,
      artist: response['artist'] as String?,
      durationMs: response['durationMs'] as int? ?? 0,
      artworkUrl: _httpsUri(response['artworkUrl'])?.toString(),
    );
  }

  Future<Uri> resolveAudio(String videoId) async {
    final response = await _request('resolveAudio', videoId);
    final uri = _httpsUri(response['url']);
    if (uri == null) {
      throw const PlaybackFailure('The YouTube audio stream is unavailable.');
    }
    return uri;
  }

  Future<Map<String, Object?>> _request(String method, String videoId) async {
    try {
      final response = await _channel
          .invokeMapMethod<String, Object?>(method, {'videoId': videoId})
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
        _ => const PlaybackFailure('Could not load the YouTube track.'),
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
