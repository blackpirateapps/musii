import 'package:url_launcher/url_launcher.dart' as url_launcher;

abstract class UrlLauncherService {
  Future<bool> launch(Uri uri);
}

class DefaultUrlLauncherService implements UrlLauncherService {
  const DefaultUrlLauncherService();

  @override
  Future<bool> launch(Uri uri) async {
    try {
      return await url_launcher.launchUrl(
        uri,
        mode: url_launcher.LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
