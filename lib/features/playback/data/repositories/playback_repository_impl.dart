import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:drift/drift.dart' as drift;
import 'package:just_audio/just_audio.dart';

import '../../../../core/database/app_database.dart' hide PlaybackState;
import '../../../../core/filesystem/app_file_system.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../cache/domain/entities/cache_entry.dart';
import '../../../library/domain/entities/music_entities.dart';
import '../../../last_fm/data/services/last_fm_playback_coordinator.dart';
import '../../../metadata/domain/services/metadata_normalization_service.dart';
import '../../../playlists/domain/entities/playlist_entities.dart';
import '../../../recently_played/data/repositories/recently_played_repository_impl.dart';
import '../../domain/entities/playback_repository.dart';
import '../../domain/entities/playback_state.dart';

class MusiiAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final CacheRepository _cacheRepository;
  final RecentlyPlayedRepository _recentlyPlayedRepository;
  final AppDatabase _database;
  final ConnectivityService _connectivityService;
  LastFmPlaybackCoordinator? _lastFmCoordinator;

  List<QueueItem> _currentQueue = [];
  int _currentIndex = 0;
  AudioRepeatMode _repeatMode = AudioRepeatMode.off;
  bool _shuffleMode = false;
  List<QueueItem> _unshuffledQueue = [];
  int _playNextCount = 0;
  int _loadGeneration = 0;
  String? _loadedTrackId;
  String? _loadingTrackId;

  final StreamController<PlayerStateSnapshot> _stateController =
      StreamController<PlayerStateSnapshot>.broadcast();

  PlayerStateSnapshot _snapshot = const PlayerStateSnapshot();

  MusiiAudioHandler({
    required CacheRepository cacheRepository,
    required RecentlyPlayedRepository recentlyPlayedRepository,
    required AppDatabase database,
    ConnectivityService? connectivityService,
    LastFmPlaybackCoordinator? lastFmCoordinator,
  }) : _cacheRepository = cacheRepository,
       _recentlyPlayedRepository = recentlyPlayedRepository,
       _database = database,
       _connectivityService = connectivityService ?? ConnectivityService(),
       _lastFmCoordinator = lastFmCoordinator {
    _initAudioSession();
    _listenToPlayerEvents();
  }

  set lastFmCoordinator(LastFmPlaybackCoordinator? coordinator) =>
      _lastFmCoordinator = coordinator;

  PlayerStateSnapshot get currentSnapshot => _snapshot;
  Stream<PlayerStateSnapshot> get snapshotStream => _stateController.stream;

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      session.becomingNoisyEventStream.listen((_) {
        pause();
      });
    } catch (e) {
      AppLogger.warning(
        LogCategory.playback,
        'Failed to configure AudioSession',
        e,
      );
    }
  }

  MediaItem _toMediaItem(Track track) {
    Uri? artUri;
    if (track.artworkPath != null && track.artworkPath!.isNotEmpty) {
      final file = File(track.artworkPath!);
      if (file.existsSync()) {
        artUri = Uri.file(file.path);
      }
    }

    return MediaItem(
      id: track.id,
      album: track.albumName ?? 'Unknown Album',
      title: track.title,
      artist: track.artistName ?? 'Unknown Artist',
      duration: Duration(milliseconds: track.durationMs),
      artUri: artUri,
      displayTitle: track.title,
      displaySubtitle: track.artistName ?? 'Unknown Artist',
      displayDescription: track.albumName ?? 'Unknown Album',
    );
  }

  String? _resolveArtworkPath(String? album, String? artist) {
    if (album == null && artist == null) return null;
    final key = MetadataNormalizationService.computeArtworkKey(album, artist);
    final file = AppFileSystem.instance.getArtworkCacheFile(key);
    return file.existsSync() ? file.path : null;
  }

  void _syncMediaQueue() {
    queue.add(_currentQueue.map((item) => _toMediaItem(item.track)).toList());
  }

  void _broadcastPlaybackState({
    bool isRestore = false,
    bool jumpStart = false,
  }) {
    if (_loadingTrackId != null) return;
    final isPlaying = jumpStart ? true : _player.playing;
    final processing = _player.processingState;

    final audioProcessing = switch (processing) {
      ProcessingState.idle =>
        isRestore ? AudioProcessingState.ready : AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
          MediaAction.skipToQueueItem,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: audioProcessing,
        playing: isPlaying,
        updatePosition: isRestore ? _snapshot.position : _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _currentIndex,
        updateTime: DateTime.now(),
      ),
    );
  }

  void _listenToPlayerEvents() {
    _player.playbackEventStream.listen((PlaybackEvent event) {
      if (_loadingTrackId != null || _loadedTrackId != _currentTrack?.id) {
        return;
      }
      _broadcastPlaybackState();
      _emitSnapshot(
        _snapshot.copyWith(
          position: _player.position,
          duration: _player.duration ?? _snapshot.duration,
          isPlaying: _player.playing,
          isBuffering:
              _player.processingState == ProcessingState.buffering ||
              _player.processingState == ProcessingState.loading,
        ),
      );
    });

    _player.playerStateStream.listen((state) {
      if (_loadingTrackId != null || _loadedTrackId != _currentTrack?.id) {
        return;
      }
      if (state.playing && _currentTrack != null) {
        _lastFmCoordinator?.onTrackStarted(_currentTrack!);
      }
      _broadcastPlaybackState();
      _emitSnapshot(
        _snapshot.copyWith(
          isPlaying: state.playing,
          isBuffering:
              state.processingState == ProcessingState.buffering ||
              state.processingState == ProcessingState.loading,
        ),
      );
      if (state.processingState == ProcessingState.completed) {
        _onTrackCompleted();
      }
    });

    _player.positionStream.listen((pos) {
      if (_loadingTrackId != null || _loadedTrackId != _currentTrack?.id) {
        return;
      }
      _lastFmCoordinator?.onPositionUpdated(pos, _player.duration);
      _emitSnapshot(_snapshot.copyWith(position: pos));
    });

    _player.durationStream.listen((dur) {
      if (_loadingTrackId != null || _loadedTrackId != _currentTrack?.id) {
        return;
      }
      if (dur != null) {
        _emitSnapshot(_snapshot.copyWith(duration: dur));
      }
    });
  }

  void _emitSnapshot(PlayerStateSnapshot snapshot) {
    _snapshot = snapshot;
    _stateController.add(_snapshot);
  }

  Future<void> _onTrackCompleted() async {
    final current = _snapshot.currentTrack;
    if (current != null) {
      _lastFmCoordinator?.onTrackCompleted();
      await _recentlyPlayedRepository.recordPlayback(
        current.id,
        _player.position.inMilliseconds,
        true,
      );
    }

    if (_repeatMode == AudioRepeatMode.one) {
      await seek(Duration.zero);
      if (current != null) {
        _lastFmCoordinator?.onTrackReplayed(current);
      }
      await play();
    } else if (_repeatMode == AudioRepeatMode.all ||
        _currentIndex < _currentQueue.length - 1) {
      await skipToNext();
    } else {
      await stop();
    }
  }

  Track? get _currentTrack =>
      (_currentQueue.isNotEmpty &&
          _currentIndex >= 0 &&
          _currentIndex < _currentQueue.length)
      ? _currentQueue[_currentIndex].track
      : null;

  QueueItem? get _currentQueueItem =>
      (_currentQueue.isNotEmpty &&
          _currentIndex >= 0 &&
          _currentIndex < _currentQueue.length)
      ? _currentQueue[_currentIndex]
      : null;

  Future<void> loadAndPlayTrack(
    Track track, {
    List<Track>? queue,
    List<QueueItem>? queueItems,
    int? queueIndex,
  }) async {
    if (queueItems != null) {
      _currentQueue = List.from(queueItems);
      _unshuffledQueue = List.from(queueItems);
      _currentIndex =
          queueIndex ?? _currentQueue.indexWhere((q) => q.track.id == track.id);
      if (_currentIndex == -1) _currentIndex = 0;
      _playNextCount = 0;
    } else if (queue != null) {
      _currentQueue = queue
          .asMap()
          .entries
          .map((e) => QueueItem(id: 'q_${e.key}_${e.value.id}', track: e.value))
          .toList();
      _unshuffledQueue = List.from(_currentQueue);
      _currentIndex =
          queueIndex ?? _currentQueue.indexWhere((q) => q.track.id == track.id);
      if (_currentIndex == -1) _currentIndex = 0;
      _playNextCount = 0;
    } else if (!_currentQueue.any((q) => q.track.id == track.id)) {
      final item = QueueItem.fromTrack(track);
      _currentQueue = [item];
      _unshuffledQueue = [item];
      _currentIndex = 0;
      _playNextCount = 0;
    } else {
      _currentIndex = _currentQueue.indexWhere((q) => q.track.id == track.id);
      if (_currentIndex == -1) _currentIndex = 0;
      _playNextCount = 0;
    }

    final targetTrack = _currentTrack ?? track;
    _cacheRepository.setCurrentlyPlayingTrackId(targetTrack.id);

    // Sync media session queue immediately
    _syncMediaQueue();
    unawaited(_persistQueue());
    unawaited(_persistState());

    _loadingTrackId = targetTrack.id;

    // Emit loading state immediately
    _emitSnapshot(
      _snapshot.copyWith(
        currentTrack: targetTrack,
        isBuffering: true,
        isPlaying: false,
        queueItems: _currentQueue,
        queueIndex: _currentIndex,
        position: Duration.zero,
        duration: Duration(milliseconds: targetTrack.durationMs),
      ),
    );

    // Update MediaItem for system notification
    mediaItem.add(_toMediaItem(targetTrack));

    // Immediately post loading playback state with active notification controls
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          MediaControl.pause,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
          MediaAction.skipToQueueItem,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.loading,
        playing: true,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
        queueIndex: _currentIndex,
        updateTime: DateTime.now(),
      ),
    );

    final currentGen = ++_loadGeneration;

    // Pause audio without dropping the Android foreground service
    await _player.pause();

    try {
      AppLogger.info(
        LogCategory.playback,
        'Fetching audio for: ${targetTrack.title}',
      );
      final fileResult = await _cacheRepository.getOrDownloadTrack(targetTrack);

      // Check if a newer track load request was initiated while downloading
      if (currentGen != _loadGeneration) {
        AppLogger.debug(
          LogCategory.playback,
          'Discarding stale load for ${targetTrack.title}',
        );
        return;
      }

      if (fileResult.isFailure) {
        AppLogger.error(
          LogCategory.playback,
          'Failed to obtain audio file: ${fileResult.failureOrNull?.message}',
        );
        _loadingTrackId = null;
        _emitSnapshot(_snapshot.copyWith(isBuffering: false, isPlaying: false));
        return;
      }

      final file = fileResult.dataOrNull!;
      if (currentGen != _loadGeneration) return;

      await _player.setFilePath(file.path);
      if (currentGen != _loadGeneration) return;

      _loadedTrackId = targetTrack.id;
      _loadingTrackId = null;

      await _player.play();

      _lastFmCoordinator?.onTrackStarted(targetTrack);

      await _persistState();
      await _persistQueue();

      // Trigger automatic background Wi-Fi pre-caching for upcoming tracks
      unawaited(_precacheUpcomingWifiTracks());
    } catch (e, st) {
      if (currentGen == _loadGeneration) {
        AppLogger.error(
          LogCategory.playback,
          'Playback error for ${targetTrack.title}',
          e,
          st,
        );
        _loadingTrackId = null;
        _emitSnapshot(_snapshot.copyWith(isBuffering: false, isPlaying: false));
      }
    }
  }

  Future<void> _precacheUpcomingWifiTracks() async {
    try {
      final isWifi = await _connectivityService.isWifiConnected();
      if (!isWifi) return;

      final nextTracks = _currentQueue
          .skip(_currentIndex + 1)
          .take(3)
          .map((item) => item.track)
          .toList();

      for (final track in nextTracks) {
        if (!await _cacheRepository.isTrackCached(track.id)) {
          AppLogger.debug(
            LogCategory.cache,
            'Wi-Fi pre-caching upcoming track: ${track.title} (${track.id})',
          );
          await _cacheRepository.getOrDownloadTrack(track);
        }
      }
    } catch (e) {
      AppLogger.warning(
        LogCategory.cache,
        'Wi-Fi pre-caching encountered an issue',
        e,
      );
    }
  }

  @override
  Future<void> play() async {
    final target = _currentTrack ?? _snapshot.currentTrack;
    if (target == null) return;

    if (_loadedTrackId == target.id &&
        _loadingTrackId == null &&
        _player.processingState != ProcessingState.idle) {
      if (_player.processingState == ProcessingState.completed) {
        await seek(Duration.zero);
      }
      await _player.play();
      _broadcastPlaybackState();
      await _persistState();
    } else if (_loadingTrackId == target.id) {
      // Already loading target track; it will automatically play when ready.
      return;
    } else {
      // Target track is not loaded in player; load and play it now.
      await loadAndPlayTrack(target);
    }
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _broadcastPlaybackState();
    final current = _snapshot.currentTrack;
    if (current != null) {
      await _recentlyPlayedRepository.recordPlayback(
        current.id,
        _player.position.inMilliseconds,
        false,
      );
    }
    await _persistState();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _loadedTrackId = null;
    _loadingTrackId = null;
    _cacheRepository.setCurrentlyPlayingTrackId(null);
    _broadcastPlaybackState();
    _emitSnapshot(_snapshot.copyWith(isPlaying: false, isBuffering: false));
    await _persistState();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _lastFmCoordinator?.onPositionUpdated(position, _player.duration);
    _broadcastPlaybackState();
  }

  @override
  Future<void> skipToNext() async {
    _playNextCount = 0;
    if (_currentQueue.isEmpty) return;

    if (_currentIndex < _currentQueue.length - 1) {
      _currentIndex++;
      await loadAndPlayTrack(_currentQueue[_currentIndex].track);
    } else if (_repeatMode == AudioRepeatMode.all) {
      _currentIndex = 0;
      await loadAndPlayTrack(_currentQueue[_currentIndex].track);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    _playNextCount = 0;
    if (_player.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    if (_currentIndex > 0) {
      _currentIndex--;
      await loadAndPlayTrack(_currentQueue[_currentIndex].track);
    } else {
      await seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    _playNextCount = 0;
    if (index >= 0 && index < _currentQueue.length) {
      _currentIndex = index;
      await loadAndPlayTrack(_currentQueue[_currentIndex].track);
    }
  }

  Future<void> skipToQueueItemById(String queueItemId) async {
    _playNextCount = 0;
    final index = _currentQueue.indexWhere((q) => q.id == queueItemId);
    if (index != -1) {
      await skipToQueueItem(index);
    }
  }

  @override
  Future<void> fastForward([
    Duration interval = const Duration(seconds: 10),
  ]) async {
    final target = _player.position + interval;
    final duration = _player.duration ?? _snapshot.duration;
    await seek(target > duration ? duration : target);
  }

  @override
  Future<void> rewind([Duration interval = const Duration(seconds: 10)]) async {
    final target = _player.position - interval;
    await seek(target < Duration.zero ? Duration.zero : target);
  }

  @override
  Future<void> onNotificationDeleted() async {
    await stop();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enable =
        shuffleMode == AudioServiceShuffleMode.all ||
        shuffleMode == AudioServiceShuffleMode.group;
    if (_shuffleMode != enable) {
      toggleShuffle();
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final target = switch (repeatMode) {
      AudioServiceRepeatMode.none => AudioRepeatMode.off,
      AudioServiceRepeatMode.all => AudioRepeatMode.all,
      AudioServiceRepeatMode.one => AudioRepeatMode.one,
      AudioServiceRepeatMode.group => AudioRepeatMode.all,
    };
    if (_repeatMode != target) {
      _repeatMode = target;
      _emitSnapshot(_snapshot.copyWith(repeatMode: _repeatMode));
      unawaited(_persistState());
    }
  }

  void toggleShuffle() {
    _shuffleMode = !_shuffleMode;
    if (_shuffleMode) {
      final current = _currentQueueItem;
      final copy = List<QueueItem>.from(_unshuffledQueue);
      if (current != null) copy.removeWhere((q) => q.id == current.id);
      copy.shuffle();
      if (current != null) copy.insert(0, current);
      _currentQueue = copy;
      _currentIndex = 0;
    } else {
      final current = _currentQueueItem;
      _currentQueue = List.from(_unshuffledQueue);
      if (current != null) {
        _currentIndex = _currentQueue.indexWhere((q) => q.id == current.id);
        if (_currentIndex == -1) _currentIndex = 0;
      }
    }
    _playNextCount = 0;
    _syncMediaQueue();
    _emitSnapshot(
      _snapshot.copyWith(
        shuffleMode: _shuffleMode,
        queueItems: _currentQueue,
        queueIndex: _currentIndex,
      ),
    );
    unawaited(_persistState());
    unawaited(_persistQueue());
  }

  void cycleRepeatMode() {
    switch (_repeatMode) {
      case AudioRepeatMode.off:
        _repeatMode = AudioRepeatMode.all;
        break;
      case AudioRepeatMode.all:
        _repeatMode = AudioRepeatMode.one;
        break;
      case AudioRepeatMode.one:
        _repeatMode = AudioRepeatMode.off;
        break;
    }
    _emitSnapshot(_snapshot.copyWith(repeatMode: _repeatMode));
    unawaited(_persistState());
  }

  void playNext(Track track) {
    AppLogger.info(LogCategory.playback, 'Queue play next: ${track.title}');
    if (_currentQueue.isEmpty) {
      loadAndPlayTrack(track);
      return;
    }
    final item = QueueItem.fromTrack(track);
    final insertIndex = (_currentIndex + 1 + _playNextCount).clamp(
      0,
      _currentQueue.length,
    );
    _currentQueue.insert(insertIndex, item);
    _unshuffledQueue.add(item);
    _playNextCount++;
    _syncMediaQueue();
    _emitSnapshot(
      _snapshot.copyWith(queueItems: _currentQueue, queueIndex: _currentIndex),
    );
    unawaited(_persistQueue());
  }

  void playLast(Track track) {
    AppLogger.info(LogCategory.playback, 'Queue add to end: ${track.title}');
    if (_currentQueue.isEmpty) {
      loadAndPlayTrack(track);
      return;
    }
    final item = QueueItem.fromTrack(track);
    _currentQueue.add(item);
    _unshuffledQueue.add(item);
    _syncMediaQueue();
    _emitSnapshot(
      _snapshot.copyWith(queueItems: _currentQueue, queueIndex: _currentIndex),
    );
    unawaited(_persistQueue());
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _currentQueue.length ||
        newIndex < 0 ||
        newIndex > _currentQueue.length) {
      return;
    }
    final currentItem = _currentQueueItem;
    final item = _currentQueue.removeAt(oldIndex);
    final insertAt = (oldIndex < newIndex) ? newIndex - 1 : newIndex;
    _currentQueue.insert(insertAt, item);

    if (currentItem != null) {
      final idx = _currentQueue.indexWhere((q) => q.id == currentItem.id);
      if (idx != -1) _currentIndex = idx;
    }

    _playNextCount = 0;
    _syncMediaQueue();
    _emitSnapshot(
      _snapshot.copyWith(queueItems: _currentQueue, queueIndex: _currentIndex),
    );
    unawaited(_persistQueue());
    AppLogger.debug(
      LogCategory.playback,
      'Queue reordered: $oldIndex -> $newIndex',
    );
  }

  void moveQueueItem(String queueItemId, int destinationIndex) {
    final oldIndex = _currentQueue.indexWhere((q) => q.id == queueItemId);
    if (oldIndex == -1) return;
    reorderQueue(oldIndex, destinationIndex);
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _currentQueue.length) return;
    final isCurrent = index == _currentIndex;
    final removedItem = _currentQueue.removeAt(index);
    _unshuffledQueue.removeWhere((q) => q.id == removedItem.id);
    _playNextCount = 0;

    AppLogger.info(
      LogCategory.playback,
      'Queue item removed: ${removedItem.track.title}',
    );

    if (_currentQueue.isEmpty) {
      stop();
      _syncMediaQueue();
      _emitSnapshot(const PlayerStateSnapshot());
    } else {
      _syncMediaQueue();
      if (isCurrent) {
        if (_currentIndex >= _currentQueue.length) {
          _currentIndex = _currentQueue.length - 1;
        }
        loadAndPlayTrack(_currentQueue[_currentIndex].track);
      } else if (index < _currentIndex) {
        _currentIndex--;
        _emitSnapshot(
          _snapshot.copyWith(
            queueItems: _currentQueue,
            queueIndex: _currentIndex,
          ),
        );
      } else {
        _emitSnapshot(
          _snapshot.copyWith(
            queueItems: _currentQueue,
            queueIndex: _currentIndex,
          ),
        );
      }
    }
    unawaited(_persistQueue());
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    removeQueueItemById(mediaItem.id);
  }

  void removeQueueItemById(String queueItemId) {
    final index = _currentQueue.indexWhere((q) => q.id == queueItemId);
    if (index != -1) {
      removeFromQueue(index);
    }
  }

  void clearUpNext() {
    if (_currentQueue.isEmpty || _currentIndex >= _currentQueue.length - 1) {
      return;
    }
    final removedItems = _currentQueue.sublist(_currentIndex + 1);
    final removedIds = removedItems.map((q) => q.id).toSet();
    _currentQueue = _currentQueue.sublist(0, _currentIndex + 1);
    _unshuffledQueue.removeWhere((q) => removedIds.contains(q.id));
    _playNextCount = 0;

    AppLogger.info(
      LogCategory.playback,
      'Cleared up next queue, remaining: ${_currentQueue.length}',
    );

    _syncMediaQueue();
    _emitSnapshot(
      _snapshot.copyWith(queueItems: _currentQueue, queueIndex: _currentIndex),
    );
    unawaited(_persistQueue());
  }

  void clearQueue() {
    stop();
    _currentQueue.clear();
    _unshuffledQueue.clear();
    _currentIndex = 0;
    _playNextCount = 0;
    _syncMediaQueue();
    _emitSnapshot(const PlayerStateSnapshot());
    unawaited(_persistQueue());
  }

  Future<void> _persistState() async {
    try {
      await _database
          .into(_database.playbackStates)
          .insertOnConflictUpdate(
            PlaybackStatesCompanion(
              id: const drift.Value('current'),
              currentTrackId: drift.Value(_currentTrack?.id),
              positionMs: drift.Value(_player.position.inMilliseconds),
              durationMs: drift.Value(_player.duration?.inMilliseconds ?? 0),
              isPlaying: drift.Value(_player.playing),
              shuffleMode: drift.Value(_shuffleMode),
              repeatMode: drift.Value(_repeatMode.value),
              queueIndex: drift.Value(_currentIndex),
              updatedAt: drift.Value(DateTime.now()),
            ),
          );
    } catch (_) {}
  }

  Future<void> _persistQueue() async {
    try {
      await _database.transaction(() async {
        await _database.delete(_database.playbackQueue).go();
        for (int i = 0; i < _currentQueue.length; i++) {
          final item = _currentQueue[i];
          await _database
              .into(_database.playbackQueue)
              .insert(
                PlaybackQueueCompanion(
                  id: drift.Value(item.id),
                  trackId: drift.Value(item.track.id),
                  sortOrder: drift.Value(i),
                  addedAt: drift.Value(DateTime.now()),
                ),
              );
        }
      });
    } catch (e) {
      AppLogger.warning(LogCategory.playback, 'Failed to persist queue', e);
    }
  }

  Future<void> restoreSavedState() async {
    try {
      final savedState = await (_database.select(
        _database.playbackStates,
      )..where((tbl) => tbl.id.equals('current'))).getSingleOrNull();

      final queueEntries =
          await (_database.select(_database.playbackQueue).join([
                drift.innerJoin(
                  _database.tracks,
                  _database.tracks.id.equalsExp(
                    _database.playbackQueue.trackId,
                  ),
                ),
              ])..orderBy([
                drift.OrderingTerm.asc(_database.playbackQueue.sortOrder),
              ]))
              .get();

      if (queueEntries.isNotEmpty) {
        final restoredItems = queueEntries.map((row) {
          final qRow = row.readTable(_database.playbackQueue);
          final t = row.readTable(_database.tracks);
          final track = Track(
            id: t.id,
            driveFileId: t.driveFileId,
            sourceId: t.sourceId,
            title: t.title,
            normalizedTitle: t.normalizedTitle,
            artistId: t.artistId,
            artistName: t.artistName,
            albumId: t.albumId,
            albumName: t.albumName,
            albumArtist: t.albumArtist,
            genre: t.genre,
            trackNumber: t.trackNumber,
            discNumber: t.discNumber,
            year: t.year,
            format: t.format,
            durationMs: t.durationMs,
            bitrate: t.bitrate,
            sampleRate: t.sampleRate,
            bitDepth: t.bitDepth,
            channels: t.channels,
            fileSize: t.fileSize,
            mimeType: t.mimeType,
            driveModifiedAt: t.driveModifiedAt,
            isCached: t.isCached,
            isPinnedOffline: t.isPinnedOffline,
            localPath: t.localPath,
            artworkPath: _resolveArtworkPath(t.albumName, t.artistName),
          );
          return QueueItem(id: qRow.id, track: track);
        }).toList();

        _currentQueue = restoredItems;
        _unshuffledQueue = List.from(restoredItems);
        _currentIndex = savedState?.queueIndex ?? 0;
        if (_currentIndex >= _currentQueue.length) _currentIndex = 0;
        _playNextCount = 0;

        _shuffleMode = savedState?.shuffleMode ?? false;
        _repeatMode = AudioRepeatMode.fromString(
          savedState?.repeatMode ?? 'off',
        );

        _syncMediaQueue();

        final current = _currentTrack;
        if (current != null) {
          mediaItem.add(_toMediaItem(current));
          _emitSnapshot(
            PlayerStateSnapshot(
              currentTrack: current,
              position: Duration(milliseconds: savedState?.positionMs ?? 0),
              duration: Duration(milliseconds: current.durationMs),
              isPlaying: false,
              shuffleMode: _shuffleMode,
              repeatMode: _repeatMode,
              queueItems: _currentQueue,
              queueIndex: _currentIndex,
            ),
          );
        }

        _broadcastPlaybackState(isRestore: true, jumpStart: true);
        Future.delayed(const Duration(milliseconds: 150), () {
          _broadcastPlaybackState(isRestore: true, jumpStart: false);
        });
      }
    } catch (e) {
      AppLogger.warning(
        LogCategory.playback,
        'Could not restore saved playback state',
        e,
      );
    }
  }
}

class PlaybackRepositoryImpl implements PlaybackRepository {
  final MusiiAudioHandler _audioHandler;

  PlaybackRepositoryImpl({required MusiiAudioHandler audioHandler})
    : _audioHandler = audioHandler;

  @override
  PlayerStateSnapshot get currentState => _audioHandler.currentSnapshot;

  @override
  Stream<PlayerStateSnapshot> watchPlayerState() =>
      _audioHandler.snapshotStream;

  @override
  Future<void> playTrack(Track track, {List<Track>? queue, int? queueIndex}) {
    return _audioHandler.loadAndPlayTrack(
      track,
      queue: queue,
      queueIndex: queueIndex,
    );
  }

  @override
  Future<void> playAlbum(
    Album album,
    List<Track> tracks, {
    int startIndex = 0,
  }) {
    if (tracks.isEmpty) return Future.value();
    final startTrack = (startIndex >= 0 && startIndex < tracks.length)
        ? tracks[startIndex]
        : tracks.first;
    return _audioHandler.loadAndPlayTrack(
      startTrack,
      queue: tracks,
      queueIndex: startIndex,
    );
  }

  @override
  Future<void> playPlaylist(
    Playlist playlist,
    List<Track> tracks, {
    int startIndex = 0,
  }) {
    if (tracks.isEmpty) return Future.value();
    final startTrack = (startIndex >= 0 && startIndex < tracks.length)
        ? tracks[startIndex]
        : tracks.first;
    return _audioHandler.loadAndPlayTrack(
      startTrack,
      queue: tracks,
      queueIndex: startIndex,
    );
  }

  @override
  Future<void> pause() => _audioHandler.pause();

  @override
  Future<void> resume() => _audioHandler.play();

  @override
  Future<void> seek(Duration position) => _audioHandler.seek(position);

  @override
  Future<void> skipToNext() => _audioHandler.skipToNext();

  @override
  Future<void> skipToPrevious() => _audioHandler.skipToPrevious();

  @override
  Future<void> toggleShuffle() async => _audioHandler.toggleShuffle();

  @override
  Future<void> cycleRepeatMode() async => _audioHandler.cycleRepeatMode();

  @override
  Future<void> playNext(Track track) async => _audioHandler.playNext(track);

  @override
  Future<void> playLast(Track track) async => _audioHandler.playLast(track);

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) async =>
      _audioHandler.reorderQueue(oldIndex, newIndex);

  @override
  Future<void> moveQueueItem(String queueItemId, int destinationIndex) async =>
      _audioHandler.moveQueueItem(queueItemId, destinationIndex);

  @override
  Future<void> removeFromQueue(int index) async =>
      _audioHandler.removeFromQueue(index);

  @override
  Future<void> removeQueueItem(String queueItemId) async =>
      _audioHandler.removeQueueItemById(queueItemId);

  @override
  Future<void> clearQueue() async => _audioHandler.clearQueue();

  @override
  Future<void> clearUpNext() async => _audioHandler.clearUpNext();

  @override
  Future<void> skipToQueueItem(int index) async =>
      _audioHandler.skipToQueueItem(index);

  @override
  Future<void> skipToQueueItemById(String queueItemId) async =>
      _audioHandler.skipToQueueItemById(queueItemId);

  @override
  Future<void> restoreSavedState() => _audioHandler.restoreSavedState();
}
