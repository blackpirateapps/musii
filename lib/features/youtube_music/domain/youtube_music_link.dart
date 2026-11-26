final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

String? youtubeVideoIdFromLink(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort) {
    return null;
  }

  final segments = uri.pathSegments;
  String? id;
  switch (uri.host) {
    case 'youtu.be':
      if (segments.length == 1) id = segments.first;
    case 'music.youtube.com':
    case 'www.youtube.com':
    case 'm.youtube.com':
    case 'youtube.com':
      if (segments.length == 1 && segments.first == 'watch') {
        id = uri.queryParameters['v'];
      }
  }
  return id != null && _videoId.hasMatch(id) ? id : null;
}
