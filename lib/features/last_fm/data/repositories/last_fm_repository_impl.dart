import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;

import '../../../../core/database/app_database.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/result/result.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/storage/secure_credential_store.dart';
import '../../../library/domain/entities/music_entities.dart';
import '../../domain/entities/last_fm_account.dart';
import '../../domain/entities/pending_scrobble.dart';
import '../../domain/entities/scrobble_history_item.dart';
import '../../domain/entities/scrobble_settings.dart';
import '../../domain/repositories/last_fm_repository.dart';
import '../datasources/last_fm_api_client.dart';

class LastFmRepositoryImpl implements LastFmRepository {
  static const String sessionKeyStorageKey = 'lastfm_session_key';
  static const String customApiKeyStorageKey = 'lastfm_custom_api_key';
  static const String customApiSecretStorageKey = 'lastfm_custom_api_secret';

  static const String scrobblingSettingKey = 'lastfm_scrobbling_enabled';
  static const String nowPlayingSettingKey = 'lastfm_now_playing_enabled';

  // Environment defines (injected at build time via --dart-define)
  static const String envApiKey = String.fromEnvironment('LASTFM_API_KEY');
  static const String envApiSecret = String.fromEnvironment(
    'LASTFM_SHARED_SECRET',
  );

  final AppDatabase _database;
  final SecureCredentialStore _credentialStore;
  final LastFmApiClient _apiClient;
  final ConnectivityService _connectivity;

  LastFmRepositoryImpl({
    required AppDatabase database,
    required SecureCredentialStore credentialStore,
    LastFmApiClient? apiClient,
    ConnectivityService? connectivity,
  }) : _database = database,
       _credentialStore = credentialStore,
       _apiClient = apiClient ?? LastFmApiClient(),
       _connectivity = connectivity ?? ConnectivityService();

  Future<String?> _getEffectiveApiKey() async {
    if (envApiKey.isNotEmpty) return LastFmApiClient.cleanCredential(envApiKey);
    final custom = await _credentialStore.read(customApiKeyStorageKey);
    if (custom == null) return null;
    final cleaned = LastFmApiClient.cleanCredential(custom);
    return cleaned.isNotEmpty ? cleaned : null;
  }

  Future<String?> _getEffectiveApiSecret() async {
    if (envApiSecret.isNotEmpty) {
      return LastFmApiClient.cleanCredential(envApiSecret);
    }
    final custom = await _credentialStore.read(customApiSecretStorageKey);
    if (custom == null) return null;
    final cleaned = LastFmApiClient.cleanCredential(custom);
    return cleaned.isNotEmpty ? cleaned : null;
  }

  @override
  Future<String?> getApiKey() => _getEffectiveApiKey();

  @override
  Future<String?> getApiSecret() => _getEffectiveApiSecret();

  @override
  Future<void> setApiCredentials({
    required String apiKey,
    required String apiSecret,
  }) async {
    final cleanKey = LastFmApiClient.cleanCredential(apiKey);
    final cleanSecret = LastFmApiClient.cleanCredential(apiSecret);
    await _credentialStore.write(customApiKeyStorageKey, cleanKey);
    await _credentialStore.write(customApiSecretStorageKey, cleanSecret);
  }

  @override
  Future<Result<String, AppFailure>> getAuthToken() async {
    final apiKey = await _getEffectiveApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return const Failure(
        LastFmConfigurationFailure(
          'Last.fm API key not configured. Please provide your API key in settings.',
        ),
      );
    }
    return _apiClient.getToken(apiKey: apiKey);
  }

  @override
  Future<Uri> getAuthUrl(String token) async {
    final apiKey = await _getEffectiveApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw const LastFmConfigurationFailure(
        'Last.fm API key not configured. Please provide your API key in settings.',
      );
    }
    return LastFmApiClient.buildAuthUrl(apiKey: apiKey, token: token);
  }

  @override
  Future<Result<LastFmAccount, AppFailure>> completeAuthentication(
    String token,
  ) async {
    final apiKey = await _getEffectiveApiKey();
    final apiSecret = await _getEffectiveApiSecret();

    if (apiKey == null ||
        apiKey.isEmpty ||
        apiSecret == null ||
        apiSecret.isEmpty) {
      return const Failure(
        LastFmConfigurationFailure(
          'Last.fm credentials not configured. Please supply API key and secret.',
        ),
      );
    }

    final sessionResult = await _apiClient.getSession(
      apiKey: apiKey,
      apiSecret: apiSecret,
      token: token,
    );

    if (sessionResult.isFailure) {
      return Failure(sessionResult.failureOrNull!);
    }

    final session = sessionResult.dataOrNull!;
    final username = session['name'] as String;
    final sessionKey = session['key'] as String;

    // Securely persist session key
    await _credentialStore.write(sessionKeyStorageKey, sessionKey);

    // Fetch user profile info
    String? realName;
    String? avatarUrl;
    String profileUrl = 'https://www.last.fm/user/$username';
    int scrobbleCount = 0;

    final infoResult = await _apiClient.getUserInfo(
      apiKey: apiKey,
      username: username,
    );

    if (infoResult.isSuccess) {
      final user = infoResult.dataOrNull!;
      realName = user['realname'] as String?;
      profileUrl = user['url'] as String? ?? profileUrl;
      scrobbleCount = int.tryParse('${user['playcount']}') ?? 0;

      final images = user['image'];
      if (images is List) {
        for (final img in images.reversed) {
          final url = img['#text'] as String?;
          if (url != null && url.isNotEmpty) {
            avatarUrl = url;
            break;
          }
        }
      }
    }

    final now = DateTime.now();
    await _database
        .into(_database.lastFmAccounts)
        .insertOnConflictUpdate(
          LastFmAccountsCompanion(
            id: const Value('current'),
            username: Value(username),
            realName: Value(realName),
            avatarUrl: Value(avatarUrl),
            profileUrl: Value(profileUrl),
            scrobbleCount: Value(scrobbleCount),
            status: Value(LastFmAccountStatus.connected.toDbString()),
            lastSyncedAt: Value(now),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    AppLogger.info(
      LogCategory.lastFm,
      'Successfully authenticated Last.fm account: @$username',
    );

    final account = LastFmAccount(
      username: username,
      realName: realName,
      avatarUrl: avatarUrl,
      profileUrl: profileUrl,
      scrobbleCount: scrobbleCount,
      status: LastFmAccountStatus.connected,
      lastSyncedAt: now,
    );

    return Success(account);
  }

  @override
  Future<Result<void, AppFailure>> disconnect() async {
    try {
      await _credentialStore.delete(sessionKeyStorageKey);

      final existing = await (_database.select(
        _database.lastFmAccounts,
      )..where((tbl) => tbl.id.equals('current'))).getSingleOrNull();

      if (existing != null) {
        await (_database.update(
          _database.lastFmAccounts,
        )..where((tbl) => tbl.id.equals('current'))).write(
          LastFmAccountsCompanion(
            status: Value(LastFmAccountStatus.disconnected.toDbString()),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      AppLogger.info(LogCategory.lastFm, 'Last.fm disconnected successfully');
      return const Success(null);
    } catch (e, st) {
      AppLogger.error(
        LogCategory.lastFm,
        'Failed to disconnect Last.fm',
        e,
        st,
      );
      return Failure(DatabaseFailure('Could not disconnect Last.fm', cause: e));
    }
  }

  @override
  Stream<LastFmAccount?> watchAccount() {
    return (_database.select(_database.lastFmAccounts)
          ..where((tbl) => tbl.id.equals('current')))
        .watchSingleOrNull()
        .map(_mapAccountRow);
  }

  @override
  Future<LastFmAccount?> getAccount() async {
    final row = await (_database.select(
      _database.lastFmAccounts,
    )..where((tbl) => tbl.id.equals('current'))).getSingleOrNull();
    return _mapAccountRow(row);
  }

  LastFmAccount? _mapAccountRow(LastFmAccountRow? row) {
    if (row == null) return null;
    return LastFmAccount(
      username: row.username,
      realName: row.realName,
      avatarUrl: row.avatarUrl,
      profileUrl: row.profileUrl,
      scrobbleCount: row.scrobbleCount,
      status: LastFmAccountStatus.fromString(row.status),
      lastSyncedAt: row.lastSyncedAt,
    );
  }

  @override
  Future<bool> hasSession() async {
    final sk = await _credentialStore.read(sessionKeyStorageKey);
    return sk != null && sk.trim().isNotEmpty;
  }

  @override
  Stream<ScrobbleSettings> watchSettings() {
    return (_database.select(_database.appSettings)..where(
          (tbl) => tbl.key.isIn([scrobblingSettingKey, nowPlayingSettingKey]),
        ))
        .watch()
        .map((rows) {
          bool scrobbling = true;
          bool nowPlaying = true;
          for (final r in rows) {
            if (r.key == scrobblingSettingKey) {
              scrobbling = r.value != 'false';
            } else if (r.key == nowPlayingSettingKey) {
              nowPlaying = r.value != 'false';
            }
          }
          return ScrobbleSettings(
            scrobblingEnabled: scrobbling,
            nowPlayingEnabled: nowPlaying,
          );
        });
  }

  @override
  Future<ScrobbleSettings> getSettings() async {
    final rows =
        await (_database.select(_database.appSettings)..where(
              (tbl) =>
                  tbl.key.isIn([scrobblingSettingKey, nowPlayingSettingKey]),
            ))
            .get();

    bool scrobbling = true;
    bool nowPlaying = true;
    for (final r in rows) {
      if (r.key == scrobblingSettingKey) {
        scrobbling = r.value != 'false';
      } else if (r.key == nowPlayingSettingKey) {
        nowPlaying = r.value != 'false';
      }
    }
    return ScrobbleSettings(
      scrobblingEnabled: scrobbling,
      nowPlayingEnabled: nowPlaying,
    );
  }

  @override
  Future<void> setScrobblingEnabled(bool enabled) async {
    await _database
        .into(_database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion(
            key: const Value(scrobblingSettingKey),
            value: Value(enabled.toString()),
          ),
        );
  }

  @override
  Future<void> setNowPlayingEnabled(bool enabled) async {
    await _database
        .into(_database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion(
            key: const Value(nowPlayingSettingKey),
            value: Value(enabled.toString()),
          ),
        );
  }

  @override
  Future<Result<void, AppFailure>> updateNowPlaying(Track track) async {
    final settings = await getSettings();
    if (!settings.nowPlayingEnabled) return const Success(null);

    final account = await getAccount();
    if (account == null || !account.isConnected) return const Success(null);

    final sessionKey = await _credentialStore.read(sessionKeyStorageKey);
    if (sessionKey == null || sessionKey.isEmpty) return const Success(null);

    final apiKey = await _getEffectiveApiKey();
    final apiSecret = await _getEffectiveApiSecret();
    if (apiKey == null || apiSecret == null) return const Success(null);

    final result = await _apiClient.updateNowPlaying(
      apiKey: apiKey,
      apiSecret: apiSecret,
      sessionKey: sessionKey,
      trackTitle: track.title,
      artistName: track.artistName ?? 'Unknown Artist',
      albumName: track.albumName,
      albumArtist: track.albumArtist,
      durationSeconds: track.durationMs > 0 ? track.durationMs ~/ 1000 : null,
      trackNumber: track.trackNumber,
    );

    if (result.isFailure &&
        result.failureOrNull is LastFmAuthenticationFailure) {
      await _handleReauthRequired(result.failureOrNull!.message);
    }

    return result;
  }

  @override
  Future<Result<void, AppFailure>> recordScrobble(
    Track track,
    int startTimestampSeconds,
  ) async {
    final settings = await getSettings();
    if (!settings.scrobblingEnabled) {
      AppLogger.debug(
        LogCategory.lastFm,
        'Scrobbling is disabled; skipping track ${track.title}',
      );
      return const Success(null);
    }

    final account = await getAccount();
    if (account == null || account.status == LastFmAccountStatus.disconnected) {
      AppLogger.debug(
        LogCategory.lastFm,
        'Last.fm disconnected; skipping scrobble record',
      );
      return const Success(null);
    }

    final scrobbleId =
        'scrobble_${DateTime.now().millisecondsSinceEpoch}_${track.id}';
    final now = DateTime.now();

    final pending = PendingScrobblesCompanion(
      id: Value(scrobbleId),
      trackId: Value(track.id),
      trackTitle: Value(track.title),
      artistName: Value(track.artistName ?? 'Unknown Artist'),
      albumName: Value(track.albumName),
      albumArtist: Value(track.albumArtist),
      durationMs: Value(track.durationMs),
      timestamp: Value(startTimestampSeconds),
      status: Value(ScrobbleStatus.pending.toDbString()),
      attempts: const Value(0),
      createdAt: Value(now),
    );

    await _database.into(_database.pendingScrobbles).insert(pending);

    AppLogger.info(
      LogCategory.lastFm,
      'Queued scrobble for "${track.title}" by "${track.artistName}" ($scrobbleId)',
    );

    // If online, immediately trigger upload
    final isOnline = await _connectivity.isOnline();
    if (isOnline && account.isConnected) {
      unawaited(syncPendingScrobbles());
    }

    return const Success(null);
  }

  @override
  Future<Result<int, AppFailure>> syncPendingScrobbles() async {
    final isOnline = await _connectivity.isOnline();
    if (!isOnline) {
      AppLogger.debug(
        LogCategory.lastFm,
        'Device is offline; scrobbles remain safely queued',
      );
      return const Success(0);
    }

    final account = await getAccount();
    if (account == null || account.status == LastFmAccountStatus.disconnected) {
      return const Success(0);
    }

    if (account.requiresReauth) {
      AppLogger.debug(
        LogCategory.lastFm,
        'Sync paused: Last.fm requires re-authentication',
      );
      return const Failure(
        LastFmAuthenticationFailure(
          'Last.fm needs you to reconnect before syncing',
        ),
      );
    }

    final sessionKey = await _credentialStore.read(sessionKeyStorageKey);
    if (sessionKey == null || sessionKey.isEmpty) {
      await _handleReauthRequired('Missing session key');
      return const Failure(
        LastFmAuthenticationFailure('Missing session key, please reconnect'),
      );
    }

    final apiKey = await _getEffectiveApiKey();
    final apiSecret = await _getEffectiveApiSecret();
    if (apiKey == null || apiSecret == null) {
      return const Failure(
        LastFmConfigurationFailure('Last.fm credentials not configured'),
      );
    }

    // Fetch pending scrobbles (batch of up to 50)
    final pendingRows =
        await (_database.select(_database.pendingScrobbles)
              ..where((tbl) => tbl.status.isNotValue('failed_reauth'))
              ..orderBy([(t) => OrderingTerm.asc(t.timestamp)])
              ..limit(50))
            .get();

    if (pendingRows.isEmpty) {
      return const Success(0);
    }

    final pendingList = pendingRows.map(_mapPendingRow).toList();

    // Mark as sending
    final ids = pendingList.map((p) => p.id).toList();
    await (_database.update(
      _database.pendingScrobbles,
    )..where((tbl) => tbl.id.isIn(ids))).write(
      PendingScrobblesCompanion(
        status: Value(ScrobbleStatus.sending.toDbString()),
        lastAttemptAt: Value(DateTime.now()),
      ),
    );

    final batchResult = await _apiClient.scrobbleBatch(
      apiKey: apiKey,
      apiSecret: apiSecret,
      sessionKey: sessionKey,
      scrobbles: pendingList,
    );

    if (batchResult.isFailure) {
      final failure = batchResult.failureOrNull!;
      if (failure is LastFmAuthenticationFailure) {
        await _handleReauthRequired(failure.message);
        // Mark all as failed_reauth to avoid retry loops
        await (_database.update(
          _database.pendingScrobbles,
        )..where((tbl) => tbl.id.isIn(ids))).write(
          PendingScrobblesCompanion(
            status: Value(ScrobbleStatus.failedReauth.toDbString()),
            errorMessage: Value(failure.message),
          ),
        );
        return Failure(failure);
      }

      // Transient failure: increment attempt count and mark retryable
      for (final p in pendingList) {
        await (_database.update(
          _database.pendingScrobbles,
        )..where((tbl) => tbl.id.equals(p.id))).write(
          PendingScrobblesCompanion(
            status: Value(ScrobbleStatus.failedRetryable.toDbString()),
            attempts: Value(p.attempts + 1),
            errorMessage: Value(failure.message),
          ),
        );
      }
      return Failure(failure);
    }

    final result = batchResult.dataOrNull!;
    final acceptedSet = result.acceptedIds.toSet();
    final now = DateTime.now();

    // Process accepted records: move to ScrobbleHistory and remove from PendingScrobbles
    for (final p in pendingList) {
      if (acceptedSet.contains(p.id)) {
        await _database
            .into(_database.scrobbleHistory)
            .insert(
              ScrobbleHistoryCompanion(
                id: Value(p.id),
                trackId: Value(p.trackId),
                trackTitle: Value(p.trackTitle),
                artistName: Value(p.artistName),
                albumName: Value(p.albumName),
                timestamp: Value(p.timestamp),
                scrobbledAt: Value(now),
              ),
            );

        await (_database.delete(
          _database.pendingScrobbles,
        )..where((tbl) => tbl.id.equals(p.id))).go();
      } else {
        // Track was ignored by Last.fm (e.g. timestamp too old)
        final reason =
            result.ignoredReasons[p.id] ?? 'Track ignored by Last.fm';
        // Remove permanently invalid scrobbles to not block queue
        await (_database.delete(
          _database.pendingScrobbles,
        )..where((tbl) => tbl.id.equals(p.id))).go();
        AppLogger.warning(
          LogCategory.lastFm,
          'Scrobble ignored by Last.fm ($reason): ${p.trackTitle}',
        );
      }
    }

    // Update account stats
    if (result.accepted > 0) {
      await (_database.update(
        _database.lastFmAccounts,
      )..where((tbl) => tbl.id.equals('current'))).write(
        LastFmAccountsCompanion(
          scrobbleCount: Value(account.scrobbleCount + result.accepted),
          lastSyncedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      AppLogger.info(
        LogCategory.lastFm,
        'Successfully synced ${result.accepted} scrobble(s) to Last.fm',
      );
    }

    // If there are more pending tracks, trigger next batch
    final remainingCount = await getPendingCount();
    if (remainingCount > 0) {
      unawaited(syncPendingScrobbles());
    }

    return Success(result.accepted);
  }

  Future<void> _handleReauthRequired(String reason) async {
    AppLogger.warning(
      LogCategory.lastFm,
      'Last.fm authentication expired or invalid: $reason',
    );
    await (_database.update(
      _database.lastFmAccounts,
    )..where((tbl) => tbl.id.equals('current'))).write(
      LastFmAccountsCompanion(
        status: Value(LastFmAccountStatus.reauthRequired.toDbString()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Stream<List<PendingScrobble>> watchPendingScrobbles() {
    return (_database.select(_database.pendingScrobbles)
          ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]))
        .watch()
        .map((rows) => rows.map(_mapPendingRow).toList());
  }

  @override
  Future<List<PendingScrobble>> getPendingScrobbles() async {
    final rows = await (_database.select(
      _database.pendingScrobbles,
    )..orderBy([(t) => OrderingTerm.asc(t.timestamp)])).get();
    return rows.map(_mapPendingRow).toList();
  }

  @override
  Future<int> getPendingCount() async {
    final count = _database.pendingScrobbles.id.count();
    final query = _database.selectOnly(_database.pendingScrobbles)
      ..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  @override
  Stream<List<ScrobbleHistoryItem>> watchScrobbleHistory({int limit = 50}) {
    return (_database.select(_database.scrobbleHistory)
          ..orderBy([(t) => OrderingTerm.desc(t.scrobbledAt)])
          ..limit(limit))
        .watch()
        .map((rows) => rows.map(_mapHistoryRow).toList());
  }

  @override
  Future<int> getSyncedScrobbleCount() async {
    final account = await getAccount();
    if (account != null && account.scrobbleCount > 0) {
      return account.scrobbleCount;
    }
    final count = _database.scrobbleHistory.id.count();
    final query = _database.selectOnly(_database.scrobbleHistory)
      ..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  @override
  Future<DateTime?> getLastSyncedAt() async {
    final account = await getAccount();
    return account?.lastSyncedAt;
  }

  PendingScrobble _mapPendingRow(PendingScrobbleRow row) {
    return PendingScrobble(
      id: row.id,
      trackId: row.trackId,
      trackTitle: row.trackTitle,
      artistName: row.artistName,
      albumName: row.albumName,
      albumArtist: row.albumArtist,
      durationMs: row.durationMs,
      timestamp: row.timestamp,
      status: ScrobbleStatus.fromString(row.status),
      attempts: row.attempts,
      lastAttemptAt: row.lastAttemptAt,
      errorMessage: row.errorMessage,
      createdAt: row.createdAt,
    );
  }

  ScrobbleHistoryItem _mapHistoryRow(ScrobbleHistoryRow row) {
    return ScrobbleHistoryItem(
      id: row.id,
      trackId: row.trackId,
      trackTitle: row.trackTitle,
      artistName: row.artistName,
      albumName: row.albumName,
      timestamp: row.timestamp,
      scrobbledAt: row.scrobbledAt,
    );
  }
}
