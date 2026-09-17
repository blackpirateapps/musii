import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../../../core/error/failures.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/pending_scrobble.dart';

class LastFmScrobbleBatchResult {
  final int accepted;
  final int ignored;
  final List<String> acceptedIds;
  final Map<String, String> ignoredReasons; // id -> reason

  const LastFmScrobbleBatchResult({
    required this.accepted,
    required this.ignored,
    required this.acceptedIds,
    this.ignoredReasons = const {},
  });
}

class LastFmApiClient {
  static const String baseUrl = 'https://ws.audioscrobbler.com/2.0/';
  static const String authBaseUrl = 'https://www.last.fm/api/auth/';
  static const Duration defaultTimeout = Duration(seconds: 15);

  final http.Client _client;

  LastFmApiClient({http.Client? client}) : _client = client ?? http.Client();

  /// Sanitizes a credential or token string by stripping quotes,
  /// leading/trailing whitespace, newlines, and hidden unicode characters.
  static String cleanCredential(String input) => input
      .replaceAll('"', '')
      .replaceAll("'", '')
      .replaceAll(RegExp(r'[\s\u200B\uFEFF\u00A0]'), '');

  /// Computes Last.fm API signature (api_sig) according to official spec:
  /// 1. Parameters sorted alphabetically by key (excluding 'format' and 'callback').
  /// 2. Concatenate key and value without separators.
  /// 3. Append shared secret.
  /// 4. MD5 hex digest in lowercase.
  static String generateSignature(
    Map<String, String> params,
    String apiSecret,
  ) {
    final filteredKeys =
        params.keys
            .where((k) => k != 'format' && k != 'callback' && k != 'api_sig')
            .toList()
          ..sort();

    final buffer = StringBuffer();
    for (final key in filteredKeys) {
      buffer.write(key);
      buffer.write(params[key]);
    }
    buffer.write(apiSecret);

    final digest = md5.convert(utf8.encode(buffer.toString()));
    return digest.toString();
  }

  /// Builds the canonical authorization URL for browser login.
  static Uri buildAuthUrl({
    required String apiKey,
    required String token,
    String? callbackUrl,
  }) {
    final cleanKey = cleanCredential(apiKey);
    final cleanTok = cleanCredential(token);
    if (cleanKey.isEmpty) {
      throw ArgumentError.value(
        apiKey,
        'apiKey',
        'Last.fm API key must not be empty.',
      );
    }

    final queryParams = <String, String>{
      'api_key': cleanKey,
      if (cleanTok.isNotEmpty) 'token': cleanTok,
      if (callbackUrl != null && callbackUrl.isNotEmpty) 'cb': callbackUrl,
    };
    return Uri.https('www.last.fm', '/api/auth/', queryParams);
  }

  /// Requests an unauthorized request token (auth.getToken).
  Future<Result<String, AppFailure>> getToken({required String apiKey}) async {
    final uri = Uri.parse(baseUrl).replace(
      queryParameters: {
        'method': 'auth.getToken',
        'api_key': apiKey,
        'format': 'json',
      },
    );

    try {
      AppLogger.debug(LogCategory.lastFm, 'Requesting Last.fm auth token');
      final response = await _client.get(uri).timeout(defaultTimeout);
      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (json.containsKey('error')) {
        return Failure(_mapApiError(json));
      }

      final token = json['token'] as String?;
      if (token == null || token.isEmpty) {
        return const Failure(
          LastFmApiFailure('Missing token in Last.fm response'),
        );
      }
      return Success(token);
    } on SocketException catch (e) {
      return Failure(LastFmNetworkFailure('No internet connection', cause: e));
    } on TimeoutException catch (e) {
      return Failure(
        LastFmNetworkFailure('Last.fm request timed out', cause: e),
      );
    } catch (e, st) {
      AppLogger.warning(
        LogCategory.lastFm,
        'Failed to get Last.fm token',
        e,
        st,
      );
      return Failure(
        LastFmNetworkFailure('Network failure while fetching token', cause: e),
      );
    }
  }

  /// Exchanges unauthorized request token for session key (auth.getSession).
  Future<Result<Map<String, dynamic>, AppFailure>> getSession({
    required String apiKey,
    required String apiSecret,
    required String token,
  }) async {
    final params = <String, String>{
      'method': 'auth.getSession',
      'api_key': apiKey,
      'token': token,
    };
    params['api_sig'] = generateSignature(params, apiSecret);
    params['format'] = 'json';

    final uri = Uri.parse(baseUrl).replace(queryParameters: params);

    try {
      AppLogger.debug(
        LogCategory.lastFm,
        'Exchanging Last.fm token for session',
      );
      final response = await _client.get(uri).timeout(defaultTimeout);
      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (json.containsKey('error')) {
        return Failure(_mapApiError(json));
      }

      final session = json['session'] as Map<String, dynamic>?;
      if (session == null) {
        return const Failure(
          LastFmApiFailure('Missing session object in Last.fm response'),
        );
      }
      return Success(session);
    } on SocketException catch (e) {
      return Failure(LastFmNetworkFailure('No internet connection', cause: e));
    } on TimeoutException catch (e) {
      return Failure(
        LastFmNetworkFailure('Last.fm session request timed out', cause: e),
      );
    } catch (e, st) {
      AppLogger.warning(
        LogCategory.lastFm,
        'Failed to exchange Last.fm session',
        e,
        st,
      );
      return Failure(
        LastFmNetworkFailure(
          'Network failure during session exchange',
          cause: e,
        ),
      );
    }
  }

  /// Fetches public profile information for a user (user.getInfo).
  Future<Result<Map<String, dynamic>, AppFailure>> getUserInfo({
    required String apiKey,
    required String username,
  }) async {
    final uri = Uri.parse(baseUrl).replace(
      queryParameters: {
        'method': 'user.getInfo',
        'api_key': apiKey,
        'user': username,
        'format': 'json',
      },
    );

    try {
      AppLogger.debug(
        LogCategory.lastFm,
        'Fetching Last.fm user info for $username',
      );
      final response = await _client.get(uri).timeout(defaultTimeout);
      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (json.containsKey('error')) {
        return Failure(_mapApiError(json));
      }

      final user = json['user'] as Map<String, dynamic>?;
      if (user == null) {
        return const Failure(
          LastFmApiFailure('Missing user object in Last.fm response'),
        );
      }
      return Success(user);
    } on SocketException catch (e) {
      return Failure(LastFmNetworkFailure('No internet connection', cause: e));
    } on TimeoutException catch (e) {
      return Failure(
        LastFmNetworkFailure('Last.fm user.getInfo timed out', cause: e),
      );
    } catch (e, st) {
      AppLogger.warning(
        LogCategory.lastFm,
        'Failed to get Last.fm user info',
        e,
        st,
      );
      return Failure(
        LastFmNetworkFailure('Network failure fetching user info', cause: e),
      );
    }
  }

  /// Sends real-time currently playing track notification (track.updateNowPlaying).
  Future<Result<void, AppFailure>> updateNowPlaying({
    required String apiKey,
    required String apiSecret,
    required String sessionKey,
    required String trackTitle,
    required String artistName,
    String? albumName,
    String? albumArtist,
    int? durationSeconds,
    int? trackNumber,
  }) async {
    final params = <String, String>{
      'method': 'track.updateNowPlaying',
      'api_key': apiKey,
      'sk': sessionKey,
      'track': trackTitle,
      'artist': artistName,
      if (albumName != null && albumName.isNotEmpty) 'album': albumName,
      if (albumArtist != null && albumArtist.isNotEmpty)
        'albumArtist': albumArtist,
      if (durationSeconds != null && durationSeconds > 0)
        'duration': durationSeconds.toString(),
      if (trackNumber != null && trackNumber > 0)
        'trackNumber': trackNumber.toString(),
    };
    params['api_sig'] = generateSignature(params, apiSecret);
    params['format'] = 'json';

    try {
      AppLogger.debug(
        LogCategory.lastFm,
        'Updating Last.fm Now Playing: $trackTitle - $artistName',
      );
      final response = await _client
          .post(
            Uri.parse(baseUrl),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: params,
          )
          .timeout(defaultTimeout);

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json.containsKey('error')) {
        return Failure(_mapApiError(json));
      }

      return const Success(null);
    } on SocketException catch (e) {
      return Failure(LastFmNetworkFailure('No internet connection', cause: e));
    } on TimeoutException catch (e) {
      return Failure(
        LastFmNetworkFailure('Now Playing update timed out', cause: e),
      );
    } catch (e, st) {
      AppLogger.warning(
        LogCategory.lastFm,
        'Failed to update Last.fm Now Playing',
        e,
        st,
      );
      return Failure(
        LastFmNetworkFailure('Network failure updating Now Playing', cause: e),
      );
    }
  }

  /// Submits a batch of pending scrobbles (up to 50 tracks) to Last.fm (track.scrobble).
  Future<Result<LastFmScrobbleBatchResult, AppFailure>> scrobbleBatch({
    required String apiKey,
    required String apiSecret,
    required String sessionKey,
    required List<PendingScrobble> scrobbles,
  }) async {
    if (scrobbles.isEmpty) {
      return const Success(
        LastFmScrobbleBatchResult(accepted: 0, ignored: 0, acceptedIds: []),
      );
    }

    // Last.fm allows max 50 tracks per batch
    final batch = scrobbles.take(50).toList();
    final params = <String, String>{
      'method': 'track.scrobble',
      'api_key': apiKey,
      'sk': sessionKey,
    };

    for (int i = 0; i < batch.length; i++) {
      final s = batch[i];
      final prefix = batch.length == 1 ? '' : '[$i]';
      params['track$prefix'] = s.trackTitle;
      params['artist$prefix'] = s.artistName;
      params['timestamp$prefix'] = s.timestamp.toString();
      if (s.albumName != null && s.albumName!.isNotEmpty) {
        params['album$prefix'] = s.albumName!;
      }
      if (s.albumArtist != null && s.albumArtist!.isNotEmpty) {
        params['albumArtist$prefix'] = s.albumArtist!;
      }
      if (s.durationMs > 0) {
        params['duration$prefix'] = (s.durationMs ~/ 1000).toString();
      }
    }

    params['api_sig'] = generateSignature(params, apiSecret);
    params['format'] = 'json';

    try {
      AppLogger.debug(
        LogCategory.lastFm,
        'Submitting batch of ${batch.length} scrobble(s) to Last.fm',
      );
      final response = await _client
          .post(
            Uri.parse(baseUrl),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: params,
          )
          .timeout(defaultTimeout);

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json.containsKey('error')) {
        return Failure(_mapApiError(json));
      }

      final scrobblesJson = json['scrobbles'] as Map<String, dynamic>?;
      final attr = scrobblesJson?['@attr'] as Map<String, dynamic>?;
      final acceptedCount =
          int.tryParse('${attr?['accepted']}') ?? batch.length;
      final ignoredCount = int.tryParse('${attr?['ignored']}') ?? 0;

      final acceptedIds = <String>[];
      final ignoredReasons = <String, String>{};

      final scrobbleEntries = scrobblesJson?['scrobble'];
      if (scrobbleEntries is List) {
        for (int i = 0; i < scrobbleEntries.length && i < batch.length; i++) {
          final entry = scrobbleEntries[i] as Map<String, dynamic>;
          final ignoredMessage =
              entry['ignoredMessage'] as Map<String, dynamic>?;
          final code = int.tryParse('${ignoredMessage?['code']}') ?? 0;
          if (code == 0) {
            acceptedIds.add(batch[i].id);
          } else {
            ignoredReasons[batch[i].id] =
                ignoredMessage?['#text'] as String? ??
                'Track ignored (code: $code)';
          }
        }
      } else if (scrobbleEntries is Map<String, dynamic> && batch.isNotEmpty) {
        final ignoredMessage =
            scrobbleEntries['ignoredMessage'] as Map<String, dynamic>?;
        final code = int.tryParse('${ignoredMessage?['code']}') ?? 0;
        if (code == 0) {
          acceptedIds.add(batch.first.id);
        } else {
          ignoredReasons[batch.first.id] =
              ignoredMessage?['#text'] as String? ??
              'Track ignored (code: $code)';
        }
      } else {
        // Fallback if list structure isn't populated
        for (final item in batch) {
          acceptedIds.add(item.id);
        }
      }

      return Success(
        LastFmScrobbleBatchResult(
          accepted: acceptedCount,
          ignored: ignoredCount,
          acceptedIds: acceptedIds,
          ignoredReasons: ignoredReasons,
        ),
      );
    } on SocketException catch (e) {
      return Failure(LastFmNetworkFailure('No internet connection', cause: e));
    } on TimeoutException catch (e) {
      return Failure(
        LastFmNetworkFailure('Scrobble batch timed out', cause: e),
      );
    } catch (e, st) {
      AppLogger.warning(
        LogCategory.lastFm,
        'Failed to submit scrobble batch',
        e,
        st,
      );
      return Failure(
        LastFmNetworkFailure(
          'Network failure submitting scrobble batch',
          cause: e,
        ),
      );
    }
  }

  AppFailure _mapApiError(Map<String, dynamic> json) {
    final code = json['error'] as int? ?? 0;
    final message = json['message'] as String? ?? 'Unknown Last.fm error';

    AppLogger.warning(LogCategory.lastFm, 'Last.fm API error $code: $message');

    return switch (code) {
      4 || 9 || 14 => LastFmAuthenticationFailure(message, errorCode: code),
      29 => LastFmRateLimitFailure(message),
      11 || 16 => LastFmNetworkFailure(message),
      _ => LastFmApiFailure(message, errorCode: code),
    };
  }
}
