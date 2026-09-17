import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musii/core/database/app_database.dart';
import 'package:musii/core/error/failures.dart';
import 'package:musii/core/services/connectivity_service.dart';
import 'package:musii/core/storage/secure_credential_store.dart';
import 'package:musii/features/last_fm/data/datasources/last_fm_api_client.dart';
import 'package:musii/features/last_fm/data/repositories/last_fm_repository_impl.dart';
import 'package:musii/features/last_fm/domain/entities/last_fm_account.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';

class FakeConnectivityService extends ConnectivityService {
  bool online;
  FakeConnectivityService({this.online = true});

  @override
  Future<bool> isOnline() async => online;
}

void main() {
  group('LastFmRepositoryImpl', () {
    late AppDatabase db;
    late InMemoryCredentialStore credentialStore;
    late FakeConnectivityService connectivity;

    const sampleApiKey = 'api_key_sample';
    const sampleApiSecret = 'api_secret_sample';
    const sampleSessionKey = 'session_key_sample';

    const testTrack = Track(
      id: 't_repo_1',
      driveFileId: 'df_1',
      sourceId: 'src_1',
      title: 'Daydream',
      normalizedTitle: 'daydream',
      artistName: 'Tatsuro Yamashita',
      albumName: 'Ride on Time',
      durationMs: 270000,
    );

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      credentialStore = InMemoryCredentialStore();
      connectivity = FakeConnectivityService(online: true);
    });

    tearDown(() async {
      await db.close();
    });

    LastFmRepositoryImpl createRepo({http.Client? client}) {
      final apiClient = LastFmApiClient(
        client:
            client ?? MockClient((request) async => http.Response('{}', 200)),
      );
      return LastFmRepositoryImpl(
        database: db,
        credentialStore: credentialStore,
        apiClient: apiClient,
        connectivity: connectivity,
      );
    }

    group('Credentials Management', () {
      test('stores and reads custom API credentials securely', () async {
        final repo = createRepo();

        await repo.setApiCredentials(
          apiKey: 'my_custom_key',
          apiSecret: 'my_custom_secret',
        );

        final storedKey = await repo.getApiKey();
        expect(storedKey, equals('my_custom_key'));

        final rawSecret = await credentialStore.read(
          LastFmRepositoryImpl.customApiSecretStorageKey,
        );
        expect(rawSecret, equals('my_custom_secret'));
      });

      test('getAuthToken fails with LastFmConfigurationFailure when no API key configured', () async {
        final repo = createRepo();

        final result = await repo.getAuthToken();
        expect(result.isFailure, isTrue);
        expect(result.failureOrNull, isA<LastFmConfigurationFailure>());
      });

      test('getAuthToken returns token when API key is configured', () async {
        final mockClient = MockClient((request) async {
          return http.Response(jsonEncode({'token': 'token_abc_123'}), 200);
        });
        final repo = createRepo(client: mockClient);

        await repo.setApiCredentials(
          apiKey: sampleApiKey,
          apiSecret: sampleApiSecret,
        );

        final result = await repo.getAuthToken();
        expect(result.isSuccess, isTrue);
        expect(result.dataOrNull, equals('token_abc_123'));
      });

      test(
        'getAuthUrl uses effective custom API key configured in credentials',
        () async {
          final repo = createRepo();
          await repo.setApiCredentials(
            apiKey: '979031f3a1b042ab166295f2b7bbfce3',
            apiSecret: 'c0ffee1234567890abcdef1234567890',
          );

          final authUrl = await repo.getAuthUrl('sampletokenxyz123456');
          expect(
            authUrl.queryParameters['api_key'],
            equals('979031f3a1b042ab166295f2b7bbfce3'),
          );
          expect(authUrl.queryParameters['token'], equals('sampletokenxyz123456'));

          final secret = await repo.getApiSecret();
          expect(secret, equals('c0ffee1234567890abcdef1234567890'));
        },
      );

      test('getAuthUrl throws LastFmConfigurationFailure when key is not configured', () async {
        final repo = createRepo();
        expect(
          () => repo.getAuthUrl('sampletokenxyz123456'),
          throwsA(isA<LastFmConfigurationFailure>()),
        );
      });
    });

    group('Authentication Flow', () {
      test('completeAuthentication successfully exchanges token and persists session', () async {
        final mockClient = MockClient((request) async {
          final method = request.url.queryParameters['method'];
          if (method == 'auth.getSession') {
            return http.Response(
              jsonEncode({
                'session': {
                  'name': 'city_pop_listener',
                  'key': sampleSessionKey,
                  'subscriber': 0,
                },
              }),
              200,
            );
          } else if (method == 'user.getInfo') {
            return http.Response(
              jsonEncode({
                'user': {
                  'name': 'city_pop_listener',
                  'realname': 'Tatsuro Fan',
                  'playcount': '250',
                  'url': 'https://www.last.fm/user/city_pop_listener',
                  'image': [
                    {
                      '#text': 'https://lastfm.freetls.fastly.net/avatar.png',
                      'size': 'medium',
                    },
                  ],
                },
              }),
              200,
            );
          }
          return http.Response('{}', 200);
        });

        final repo = createRepo(client: mockClient);
        await repo.setApiCredentials(
          apiKey: sampleApiKey,
          apiSecret: sampleApiSecret,
        );

        final result = await repo.completeAuthentication('temp_token_123');
        expect(result.isSuccess, isTrue);

        final account = result.dataOrNull!;
        expect(account.username, equals('city_pop_listener'));
        expect(account.realName, equals('Tatsuro Fan'));
        expect(account.scrobbleCount, equals(250));
        expect(account.status, equals(LastFmAccountStatus.connected));

        // Verify session key is encrypted/stored
        final storedSessionKey = await credentialStore.read(
          LastFmRepositoryImpl.sessionKeyStorageKey,
        );
        expect(storedSessionKey, equals(sampleSessionKey));

        // Verify persisted account in SQLite
        final persistedAccount = await repo.getAccount();
        expect(persistedAccount, isNotNull);
        expect(persistedAccount!.username, equals('city_pop_listener'));
        expect(persistedAccount.status, equals(LastFmAccountStatus.connected));
      });

      test(
        'disconnect clears session key and marks account disconnected',
        () async {
          final repo = createRepo();

          // Seed account
          await credentialStore.write(
            LastFmRepositoryImpl.sessionKeyStorageKey,
            sampleSessionKey,
          );
          await db
              .into(db.lastFmAccounts)
              .insert(
                LastFmAccountsCompanion.insert(
                  id: 'current',
                  username: 'listener_1',
                  profileUrl: 'https://www.last.fm/user/listener_1',
                  scrobbleCount: const Value(10),
                  status: LastFmAccountStatus.connected.toDbString(),
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ),
              );

          final disconnectResult = await repo.disconnect();
          expect(disconnectResult.isSuccess, isTrue);

          // Session key removed
          final key = await credentialStore.read(
            LastFmRepositoryImpl.sessionKeyStorageKey,
          );
          expect(key, isNull);

          // Status updated to disconnected
          final account = await repo.getAccount();
          expect(account?.status, equals(LastFmAccountStatus.disconnected));
        },
      );
    });

    group('Settings Persistence', () {
      test('defaults to enabled and persists toggles in AppSettings', () async {
        final repo = createRepo();

        final initial = await repo.getSettings();
        expect(initial.scrobblingEnabled, isTrue);
        expect(initial.nowPlayingEnabled, isTrue);

        await repo.setScrobblingEnabled(false);
        final afterScrobbleDisable = await repo.getSettings();
        expect(afterScrobbleDisable.scrobblingEnabled, isFalse);
        expect(afterScrobbleDisable.nowPlayingEnabled, isTrue);

        await repo.setNowPlayingEnabled(false);
        final afterBothDisable = await repo.getSettings();
        expect(afterBothDisable.scrobblingEnabled, isFalse);
        expect(afterBothDisable.nowPlayingEnabled, isFalse);
      });
    });

    group('Scrobbling and Offline Queue', () {
      setUp(() async {
        // Setup connected account and session key
        await credentialStore.write(
          LastFmRepositoryImpl.sessionKeyStorageKey,
          sampleSessionKey,
        );
        await credentialStore.write(
          LastFmRepositoryImpl.customApiKeyStorageKey,
          sampleApiKey,
        );
        await credentialStore.write(
          LastFmRepositoryImpl.customApiSecretStorageKey,
          sampleApiSecret,
        );
        await db
            .into(db.lastFmAccounts)
            .insert(
              LastFmAccountsCompanion.insert(
                id: 'current',
                username: 'listener_1',
                profileUrl: 'https://www.last.fm/user/listener_1',
                scrobbleCount: const Value(50),
                status: LastFmAccountStatus.connected.toDbString(),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
      });

      test('recordScrobble queues to database when offline', () async {
        connectivity.online = false;
        final repo = createRepo();

        final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final result = await repo.recordScrobble(testTrack, timestamp);

        expect(result.isSuccess, isTrue);
        final pendingCount = await repo.getPendingCount();
        expect(pendingCount, equals(1));

        final pendingItems = await repo.watchPendingScrobbles().first;
        expect(pendingItems.first.trackTitle, equals('Daydream'));
        expect(pendingItems.first.artistName, equals('Tatsuro Yamashita'));
      });

      test(
        'recordScrobble does nothing when scrobbling setting is disabled',
        () async {
          final repo = createRepo();
          await repo.setScrobblingEnabled(false);

          final result = await repo.recordScrobble(testTrack, 123456);
          expect(result.isSuccess, isTrue);

          final pendingCount = await repo.getPendingCount();
          expect(pendingCount, equals(0));
        },
      );

      test('syncPendingScrobbles moves accepted tracks to ScrobbleHistory and increments count', () async {
        final mockClient = MockClient((request) async {
          expect(request.bodyFields['method'], equals('track.scrobble'));
          return http.Response(
            jsonEncode({
              'scrobbles': {
                '@attr': {'accepted': 1, 'ignored': 0},
                'scrobble': {
                  'track': {'#text': 'Daydream'},
                  'ignoredMessage': {'code': '0', '#text': ''},
                },
              },
            }),
            200,
          );
        });

        final repo = createRepo(client: mockClient);
        connectivity.online = false; // Queue offline first
        await repo.recordScrobble(testTrack, 1700000000);

        expect(await repo.getPendingCount(), equals(1));

        // Bring back online and sync
        connectivity.online = true;
        final syncResult = await repo.syncPendingScrobbles();

        expect(syncResult.isSuccess, isTrue);
        expect(syncResult.dataOrNull, equals(1));

        // Pending queue should now be empty
        expect(await repo.getPendingCount(), equals(0));

        // ScrobbleHistory should have the track
        final history = await repo.watchScrobbleHistory().first;
        expect(history.length, equals(1));
        expect(history.first.trackTitle, equals('Daydream'));

        // Account scrobble count incremented from 50 to 51
        final account = await repo.getAccount();
        expect(account?.scrobbleCount, equals(51));
      });

      test(
        'syncPendingScrobbles marks reauth_required on authentication failure',
        () async {
          final mockClient = MockClient((request) async {
            return http.Response(
              jsonEncode({
                'error': 9,
                'message': 'Invalid session key - Please re-authenticate',
              }),
              200,
            );
          });

          final repo = createRepo(client: mockClient);
          connectivity.online = false;
          await repo.recordScrobble(testTrack, 1700000000);

          connectivity.online = true;
          final syncResult = await repo.syncPendingScrobbles();

          expect(syncResult.isFailure, isTrue);
          expect(syncResult.failureOrNull, isA<LastFmAuthenticationFailure>());

          final account = await repo.getAccount();
          expect(account?.status, equals(LastFmAccountStatus.reauthRequired));

          final pendingItems = await repo.watchPendingScrobbles().first;
          expect(
            pendingItems.first.status.toDbString(),
            equals('failed_reauth'),
          );
        },
      );
    });

    group('Now Playing Updates', () {
      setUp(() async {
        await credentialStore.write(
          LastFmRepositoryImpl.sessionKeyStorageKey,
          sampleSessionKey,
        );
        await credentialStore.write(
          LastFmRepositoryImpl.customApiKeyStorageKey,
          sampleApiKey,
        );
        await credentialStore.write(
          LastFmRepositoryImpl.customApiSecretStorageKey,
          sampleApiSecret,
        );
        await db
            .into(db.lastFmAccounts)
            .insert(
              LastFmAccountsCompanion.insert(
                id: 'current',
                username: 'listener_1',
                profileUrl: 'https://www.last.fm/user/listener_1',
                status: LastFmAccountStatus.connected.toDbString(),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
      });

      test('updateNowPlaying sends track when enabled and connected', () async {
        var called = false;
        final mockClient = MockClient((request) async {
          expect(
            request.bodyFields['method'],
            equals('track.updateNowPlaying'),
          );
          expect(request.bodyFields['track'], equals('Daydream'));
          called = true;
          return http.Response(
            jsonEncode({
              'nowplaying': {
                'track': {'#text': 'Daydream'},
                'artist': {'#text': 'Tatsuro Yamashita'},
              },
            }),
            200,
          );
        });

        final repo = createRepo(client: mockClient);
        final result = await repo.updateNowPlaying(testTrack);

        expect(called, isTrue);
        expect(result.isSuccess, isTrue);
      });

      test('updateNowPlaying skips when setting is disabled', () async {
        var called = false;
        final mockClient = MockClient((request) async {
          called = true;
          return http.Response('{}', 200);
        });

        final repo = createRepo(client: mockClient);
        await repo.setNowPlayingEnabled(false);

        final result = await repo.updateNowPlaying(testTrack);

        expect(called, isFalse);
        expect(result.isSuccess, isTrue);
      });
    });
  });
}
