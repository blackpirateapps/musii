import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import '../../../library/domain/entities/music_entities.dart';
import '../entities/last_fm_account.dart';
import '../entities/pending_scrobble.dart';
import '../entities/scrobble_history_item.dart';
import '../entities/scrobble_settings.dart';

abstract class LastFmRepository {
  /// Fetches an unauthorized request token from Last.fm to begin authentication.
  Future<Result<String, AppFailure>> getAuthToken();

  /// Constructs the Last.fm authorization URL where the user approves the application.
  Uri getAuthUrl(String token);

  /// Completes authentication by exchanging [token] for a 32-character session key
  /// and fetching the user's profile metadata.
  Future<Result<LastFmAccount, AppFailure>> completeAuthentication(String token);

  /// Disconnects the Last.fm account, clears sensitive session keys from secure storage,
  /// and marks the account as disconnected.
  Future<Result<void, AppFailure>> disconnect();

  /// Watches the current authenticated Last.fm account reactively.
  Stream<LastFmAccount?> watchAccount();

  /// Gets the current authenticated Last.fm account snapshot.
  Future<LastFmAccount?> getAccount();

  /// Checks if a valid session key is present in secure storage.
  Future<bool> hasSession();

  /// Watches the scrobbling and now playing settings.
  Stream<ScrobbleSettings> watchSettings();

  /// Gets current scrobbling settings.
  Future<ScrobbleSettings> getSettings();

  /// Toggles automatic scrobbling.
  Future<void> setScrobblingEnabled(bool enabled);

  /// Toggles real-time Now Playing broadcast.
  Future<void> setNowPlayingEnabled(bool enabled);

  /// Returns currently configured API key, if any.
  Future<String?> getApiKey();

  /// Configures custom Last.fm API Key and Shared Secret in secure storage.
  Future<void> setApiCredentials({
    required String apiKey,
    required String apiSecret,
  });

  /// Submits real-time "Now Playing" status to Last.fm.
  Future<Result<void, AppFailure>> updateNowPlaying(Track track);

  /// Records an eligible scrobble to the local queue and initiates synchronization if online.
  Future<Result<void, AppFailure>> recordScrobble(
    Track track,
    int startTimestampSeconds,
  );

  /// Processes and uploads pending scrobbles to Last.fm (supporting batching up to 50 tracks).
  /// Returns the count of successfully synced scrobbles.
  Future<Result<int, AppFailure>> syncPendingScrobbles();

  /// Watches the list of pending scrobbles in the local SQLite queue.
  Stream<List<PendingScrobble>> watchPendingScrobbles();

  /// Gets all pending scrobbles in the local queue.
  Future<List<PendingScrobble>> getPendingScrobbles();

  /// Gets the count of pending scrobbles in the local queue.
  Future<int> getPendingCount();

  /// Watches recent scrobbles successfully submitted from Musii.
  Stream<List<ScrobbleHistoryItem>> watchScrobbleHistory({int limit = 50});

  /// Gets total scrobbles successfully synced locally or from account.
  Future<int> getSyncedScrobbleCount();

  /// Gets timestamp of the last successful synchronization.
  Future<DateTime?> getLastSyncedAt();
}
