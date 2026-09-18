import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musii/core/error/failures.dart';
import 'package:musii/features/last_fm/data/datasources/last_fm_api_client.dart';
import 'package:musii/features/last_fm/domain/entities/pending_scrobble.dart';

void main() {
  group('LastFmApiClient', () {
    const testApiKey = 'test_api_key_123';
    const testApiSecret = 'test_api_secret_456';

    group('generateSignature', () {
      test('correctly orders keys alphabetically and computes MD5 hash', () {
        final params = {
          'method': 'auth.getSession',
          'api_key': 'abc',
          'token': 'xyz',
        };
        // Keys sorted: api_key, method, token
        // String: "api_keyabcmethodauth.getSessiontokenxyz" + testApiSecret
        const expectedString =
            'api_keyabcmethodauth.getSessiontokenxyz$testApiSecret';
        final expectedHash = md5
            .convert(utf8.encode(expectedString))
            .toString();

        final sig = LastFmApiClient.generateSignature(params, testApiSecret);
        expect(sig, equals(expectedHash));
      });

      test('excludes format, callback, and api_sig keys from signature calculation', () {
        final paramsWithExcluded = {
          'method': 'auth.getSession',
          'api_key': 'abc',
          'token': 'xyz',
          'format': 'json',
          'callback': 'http://example.com',
          'api_sig': 'should_be_ignored',
        };

        final cleanParams = {
          'method': 'auth.getSession',
          'api_key': 'abc',
          'token': 'xyz',
        };

        final sigWithExcluded = LastFmApiClient.generateSignature(
          paramsWithExcluded,
          testApiSecret,
        );
        final sigClean = LastFmApiClient.generateSignature(
          cleanParams,
          testApiSecret,
        );

        expect(sigWithExcluded, equals(sigClean));
      });

      test('properly encodes multi-byte UTF-8 characters', () {
        final params = {'track': 'プラスティック・ラヴ', 'artist': '竹内まりや'};
        const expectedString = 'artist竹内まりやtrackプラスティック・ラヴ$testApiSecret';
        final expectedHash = md5
            .convert(utf8.encode(expectedString))
            .toString();

        final sig = LastFmApiClient.generateSignature(params, testApiSecret);
        expect(sig, equals(expectedHash));
      });
    });

    group('cleanCredential', () {
      test('removes quotes, whitespace, and hidden unicode characters', () {
        expect(
          LastFmApiClient.cleanCredential(
            '" 979031f3a1b042ab166295f2b7bbfce3 "\n',
          ),
          equals('979031f3a1b042ab166295f2b7bbfce3'),
        );
      });

      test('preserves dashes in tokens', () {
        expect(
          LastFmApiClient.cleanCredential('l6hr-QpRjScViMEFhrmVZPteTgLFi-K7'),
          equals('l6hr-QpRjScViMEFhrmVZPteTgLFi-K7'),
        );
      });
    });

    group('buildAuthUrl', () {
      test('constructs canonical authorization URL with trailing slash', () {
        final uri = LastFmApiClient.buildAuthUrl(
          apiKey: '979031f3a1b042ab166295f2b7bbfce3',
          token: '25d3pyje5pk1kj6rzbyyrfbjqp2tzi01',
        );

        expect(uri.scheme, equals('https'));
        expect(uri.host, equals('www.last.fm'));
        expect(uri.path, equals('/api/auth/'));
        expect(
          uri.queryParameters['api_key'],
          equals('979031f3a1b042ab166295f2b7bbfce3'),
        );
        expect(
          uri.queryParameters['token'],
          equals('25d3pyje5pk1kj6rzbyyrfbjqp2tzi01'),
        );
        expect(uri.queryParameters.containsKey('cb'), isFalse);
      });

      test('throws ArgumentError when apiKey is empty', () {
        expect(
          () =>
              LastFmApiClient.buildAuthUrl(apiKey: '', token: 'validtoken123'),
          throwsArgumentError,
        );
      });

      test('constructs authorization URL with callback when provided', () {
        final uri = LastFmApiClient.buildAuthUrl(
          apiKey: '979031f3a1b042ab166295f2b7bbfce3',
          token: '25d3pyje5pk1kj6rzbyyrfbjqp2tzi01',
          callbackUrl: 'musii://auth-callback',
        );

        expect(uri.queryParameters['cb'], equals('musii://auth-callback'));
      });
    });

    group('getToken', () {
      test('returns token string on successful response', () async {
        final mockClient = MockClient((request) async {
          expect(
            request.url.queryParameters['method'],
            equals('auth.getToken'),
          );
          expect(request.url.queryParameters['api_key'], equals(testApiKey));
          expect(request.url.queryParameters['format'], equals('json'));

          return http.Response(
            jsonEncode({'token': 'sample_unauthorized_token_777'}),
            200,
          );
        });

        final client = LastFmApiClient(client: mockClient);
        final result = await client.getToken(apiKey: testApiKey);

        expect(result.isSuccess, isTrue);
        expect(result.dataOrNull, equals('sample_unauthorized_token_777'));
      });

      test('returns LastFmApiFailure when response contains error', () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({'error': 10, 'message': 'Invalid API key'}),
            200,
          );
        });

        final client = LastFmApiClient(client: mockClient);
        final result = await client.getToken(apiKey: testApiKey);

        expect(result.isFailure, isTrue);
        expect(result.failureOrNull, isA<LastFmApiFailure>());
        expect(result.failureOrNull?.message, contains('Invalid API key'));
      });

      test(
        'returns LastFmNetworkFailure on client error or socket exception',
        () async {
          final mockClient = MockClient((request) async {
            throw const SocketException('Connection failed');
          });

          final client = LastFmApiClient(client: mockClient);
          final result = await client.getToken(apiKey: testApiKey);

          expect(result.isFailure, isTrue);
          expect(result.failureOrNull, isA<LastFmNetworkFailure>());
        },
      );
    });

    group('getSession', () {
      test(
        'returns session map and verifies signed request parameters',
        () async {
          final mockClient = MockClient((request) async {
            expect(
              request.url.queryParameters['method'],
              equals('auth.getSession'),
            );
            expect(request.url.queryParameters['token'], equals('my_token'));
            expect(request.url.queryParameters.containsKey('api_sig'), isTrue);

            return http.Response(
              jsonEncode({
                'session': {
                  'name': 'tatsuro_fan',
                  'key': 'session_key_999',
                  'subscriber': 0,
                },
              }),
              200,
            );
          });

          final client = LastFmApiClient(client: mockClient);
          final result = await client.getSession(
            apiKey: testApiKey,
            apiSecret: testApiSecret,
            token: 'my_token',
          );

          expect(result.isSuccess, isTrue);
          final session = result.dataOrNull!;
          expect(session['name'], equals('tatsuro_fan'));
          expect(session['key'], equals('session_key_999'));
        },
      );

      test(
        'returns LastFmAuthenticationFailure when error is auth-related',
        () async {
          final mockClient = MockClient((request) async {
            return http.Response(
              jsonEncode({'error': 4, 'message': 'Authentication Failed'}),
              200,
            );
          });

          final client = LastFmApiClient(client: mockClient);
          final result = await client.getSession(
            apiKey: testApiKey,
            apiSecret: testApiSecret,
            token: 'invalid_token',
          );

          expect(result.isFailure, isTrue);
          expect(result.failureOrNull, isA<LastFmAuthenticationFailure>());
          final authFail = result.failureOrNull as LastFmAuthenticationFailure;
          expect(authFail.errorCode, equals(4));
        },
      );
    });

    group('getUserInfo', () {
      test('returns user information map', () async {
        final mockClient = MockClient((request) async {
          expect(request.url.queryParameters['method'], equals('user.getInfo'));
          expect(request.url.queryParameters['user'], equals('tatsuro_fan'));

          return http.Response(
            jsonEncode({
              'user': {
                'name': 'tatsuro_fan',
                'playcount': '1520',
                'image': [
                  {'#text': 'http://avatar.jpg', 'size': 'medium'},
                ],
              },
            }),
            200,
          );
        });

        final client = LastFmApiClient(client: mockClient);
        final result = await client.getUserInfo(
          apiKey: testApiKey,
          username: 'tatsuro_fan',
        );

        expect(result.isSuccess, isTrue);
        final user = result.dataOrNull!;
        expect(user['name'], equals('tatsuro_fan'));
        expect(user['playcount'], equals('1520'));
      });
    });

    group('updateNowPlaying', () {
      test('submits valid POST request with track and artist', () async {
        final mockClient = MockClient((request) async {
          expect(request.method, equals('POST'));
          expect(
            request.bodyFields['method'],
            equals('track.updateNowPlaying'),
          );
          expect(request.bodyFields['track'], equals('Sparkle'));
          expect(request.bodyFields['artist'], equals('Tatsuro Yamashita'));
          expect(request.bodyFields['album'], equals('For You'));
          expect(request.bodyFields['duration'], equals('250'));
          expect(request.bodyFields.containsKey('api_sig'), isTrue);

          return http.Response(
            jsonEncode({
              'nowplaying': {
                'track': {'#text': 'Sparkle'},
                'artist': {'#text': 'Tatsuro Yamashita'},
              },
            }),
            200,
          );
        });

        final client = LastFmApiClient(client: mockClient);
        final result = await client.updateNowPlaying(
          apiKey: testApiKey,
          apiSecret: testApiSecret,
          sessionKey: 'session_key_123',
          trackTitle: 'Sparkle',
          artistName: 'Tatsuro Yamashita',
          albumName: 'For You',
          durationSeconds: 250,
        );

        expect(result.isSuccess, isTrue);
      });
    });

    group('scrobbleBatch', () {
      PendingScrobble makePending({
        required String id,
        required String title,
        required String artist,
        String? album,
        int durationMs = 200000,
        required int timestamp,
      }) {
        return PendingScrobble(
          id: id,
          trackId: 't_$id',
          trackTitle: title,
          artistName: artist,
          albumName: album,
          durationMs: durationMs,
          timestamp: timestamp,
          createdAt: DateTime.now(),
        );
      }

      test(
        'returns immediately without HTTP call when list is empty',
        () async {
          var called = false;
          final mockClient = MockClient((request) async {
            called = true;
            return http.Response('{}', 200);
          });

          final client = LastFmApiClient(client: mockClient);
          final result = await client.scrobbleBatch(
            apiKey: testApiKey,
            apiSecret: testApiSecret,
            sessionKey: 'session_key_123',
            scrobbles: [],
          );

          expect(called, isFalse);
          expect(result.isSuccess, isTrue);
          expect(result.dataOrNull?.accepted, equals(0));
        },
      );

      test('submits single track using un-indexed parameters', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final pending = makePending(
          id: 'scrobble_1',
          title: 'Silent Screamer',
          artist: 'Tatsuro Yamashita',
          album: 'Moonglow',
          durationMs: 320000,
          timestamp: now,
        );

        final mockClient = MockClient((request) async {
          expect(request.method, equals('POST'));
          expect(request.bodyFields['track'], equals('Silent Screamer'));
          expect(request.bodyFields['artist'], equals('Tatsuro Yamashita'));
          expect(request.bodyFields['album'], equals('Moonglow'));
          expect(request.bodyFields['timestamp'], equals(now.toString()));
          // Single scrobble must NOT use indexed [0] keys
          expect(request.bodyFields.containsKey('track[0]'), isFalse);

          return http.Response(
            jsonEncode({
              'scrobbles': {
                '@attr': {'accepted': 1, 'ignored': 0},
                'scrobble': {
                  'track': {'#text': 'Silent Screamer'},
                  'ignoredMessage': {'code': '0', '#text': ''},
                },
              },
            }),
            200,
          );
        });

        final client = LastFmApiClient(client: mockClient);
        final result = await client.scrobbleBatch(
          apiKey: testApiKey,
          apiSecret: testApiSecret,
          sessionKey: 'session_key_123',
          scrobbles: [pending],
        );

        expect(result.isSuccess, isTrue);
        final batchResult = result.dataOrNull!;
        expect(batchResult.accepted, equals(1));
        expect(batchResult.ignored, equals(0));
        expect(batchResult.acceptedIds, contains('scrobble_1'));
      });

      test('submits multiple tracks using indexed parameters', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final scrobbles = <PendingScrobble>[
          makePending(
            id: 's_1',
            title: 'Track 1',
            artist: 'Artist 1',
            timestamp: now,
          ),
          makePending(
            id: 's_2',
            title: 'Track 2',
            artist: 'Artist 2',
            timestamp: now + 300,
          ),
        ];

        final mockClient = MockClient((request) async {
          expect(request.bodyFields['track[0]'], equals('Track 1'));
          expect(request.bodyFields['artist[0]'], equals('Artist 1'));
          expect(request.bodyFields['track[1]'], equals('Track 2'));
          expect(request.bodyFields['artist[1]'], equals('Artist 2'));

          return http.Response(
            jsonEncode({
              'scrobbles': {
                '@attr': {'accepted': 2, 'ignored': 0},
                'scrobble': [
                  {
                    'track': {'#text': 'Track 1'},
                    'ignoredMessage': {'code': '0', '#text': ''},
                  },
                  {
                    'track': {'#text': 'Track 2'},
                    'ignoredMessage': {'code': '0', '#text': ''},
                  },
                ],
              },
            }),
            200,
          );
        });

        final client = LastFmApiClient(client: mockClient);
        final result = await client.scrobbleBatch(
          apiKey: testApiKey,
          apiSecret: testApiSecret,
          sessionKey: 'session_key_123',
          scrobbles: scrobbles,
        );

        expect(result.isSuccess, isTrue);
        final batchResult = result.dataOrNull!;
        expect(batchResult.accepted, equals(2));
        expect(batchResult.acceptedIds, containsAll(['s_1', 's_2']));
      });

      test('handles rate limit error code 29', () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({'error': 29, 'message': 'Rate limit exceeded'}),
            200,
          );
        });

        final client = LastFmApiClient(client: mockClient);
        final result = await client.scrobbleBatch(
          apiKey: testApiKey,
          apiSecret: testApiSecret,
          sessionKey: 'session_key_123',
          scrobbles: [
            makePending(
              id: 's_1',
              title: 'Track 1',
              artist: 'Artist 1',
              timestamp: 1000,
            ),
          ],
        );

        expect(result.isFailure, isTrue);
        expect(result.failureOrNull, isA<LastFmRateLimitFailure>());
      });
    });
  });
}
