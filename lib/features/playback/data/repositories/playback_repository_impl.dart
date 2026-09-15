import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:drift/drift.dart' as drift;
import 'package:just_audio/just_audio.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../cache/domain/entities/cache_entry.dart';
import '../../../library/domain/entities/music_entities.dart';
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

  List<Track> _currentQueue = [];
  int _currentIndex = 0;
  AudioRepeatMode _repeatMode = AudioRepeatMode.off;
  bool _shuffleMode = false;
  List<Track> _unshuffledQueue = [];

  final StreamController<PlayerStateSnapshot> _stateController =
      StreamController<PlayerStateSnapshot>.broadcast();

  PlayerStateSnapshot _snapshot = const PlayerStateSnapshot();

  MusiiAudioHandler({
    required CacheRepository cacheRepository,
    required RecentlyPlayedRepository recentlyPlayedRepository,
    required AppDatabase database,
  }) : _cacheRepository = cacheRepository,
       _recentlyPlayedRepository = recentlyPlayedRepository,
       _database = database {
    _initAudioSession();
    _listenToPlayerEvents();
  }

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
    );
  }

  void _syncMediaQueue() {
    queue.add(_currentQueue.map(_toMediaItem).toList());
  }

  void _listenToPlayerEvents() {
    _player.playbackEventStream.listen((PlaybackEvent event) {
      final isPlaying = _player.playing;
      final processing = _player.processingState;

      playbackState.add(
        playbackState.value.copyWith(
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
          processingState: switch (processing) {
            ProcessingState.idle => AudioProcessingState.idle,
            ProcessingState.loading => AudioProcessingState.loading,
            ProcessingState.buffering => AudioProcessingState.buffering,
            ProcessingState.ready => AudioProcessingState.ready,
            ProcessingState.completed => AudioProcessingState.completed,
          },
          playing: isPlaying,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
          queueIndex: _currentIndex,
        ),
      );

      _emitSnapshot(
        _snapshot.copyWith(
          position: _player.position,
          duration: _player.duration ?? _snapshot.duration,
          isPlaying: isPlaying,
          isBuffering:
              processing == ProcessingState.buffering ||
              processing == ProcessingState.loading,
        ),
      );
    });

    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _onTrackCompleted();
      }
    });

    _player.positionStream.listen((pos) {
      _emitSnapshot(_snapshot.copyWith(position: pos));
    });

    _player.durationStream.listen((dur) {
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
      await _recentlyPlayedRepository.recordPlayback(
        current.id,
        _player.position.inMilliseconds,
        true,
      );
    }

    if (_repeatMode == AudioRepeatMode.one) {
      await seek(Duration.zero);
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
      ? _currentQueue[_currentIndex]
      : null;

  Future<void> loadAndPlayTrack(
    Track track, {
    List<Track>? queue,
    int? queueIndex,
  }) async {
    if (queue != null) {
      _currentQueue = List.from(queue);
      _unshuffledQueue = List.from(queue);
      _currentIndex =
          queueIndex ?? _currentQueue.indexWhere((t) => t.id == track.id);
      if (_currentIndex == -1) _currentIndex = 0;
    } else if (!_currentQueue.any((t) => t.id == track.id)) {
      _currentQueue = [track];
      _unshuffledQueue = [track];
      _currentIndex = 0;
    } else {
      _currentIndex = _currentQueue.indexWhere((t) => t.id == track.id);
    }

    final targetTrack = _currentTrack ?? track;
    _cacheRepository.setCurrentlyPlayingTrackId(targetTrack.id);

    // Sync media session queue
    _syncMediaQueue();

    // Emit loading state immediately
    _emitSnapshot(
      _snapshot.copyWith(
        currentTrack: targetTrack,
        isBuffering: true,
        queue: _currentQueue,
        queueIndex: _currentIndex,
        position: Duration.zero,
        duration: Duration(milliseconds: targetTrack.durationMs),
      ),
    );

    // Update MediaItem for system notification
    mediaItem.add(_toMediaItem(targetTrack));

    try {
      AppLogger.info(
        LogCategory.playback,
        'Fetching audio for: ${targetTrack.title}',
      );
      final fileResult = await _cacheRepository.getOrDownloadTrack(targetTrack);

      if (fileResult.isFailure) {
        AppLogger.error(
          LogCategory.playback,
          'Failed to obtain audio file: ${fileResult.failureOrNull?.message}',
        );
        _emitSnapshot(_snapshot.copyWith(isBuffering: false, isPlaying: false));
        return;
      }

      final file = fileResult.dataOrNull!;
      await _player.setFilePath(file.path);
      await _player.play();

      await _persistState();
      await _persistQueue();
    } catch (e, st) {
      AppLogger.error(
        LogCategory.playback,
        'Playback error for ${targetTrack.title}',
        e,
        st,
      );
      _emitSnapshot(_snapshot.copyWith(isBuffering: false, isPlaying: false));
    }
  }

  @override
  Future<void> play() async {
    if (_player.processingState == ProcessingState.completed) {
      await seek(Duration.zero);
    }
    await _player.play();
    await _persistState();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
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
    _cacheRepository.setCurrentlyPlayingTrackId(null);
    _emitSnapshot(_snapshot.copyWith(isPlaying: false, isBuffering: false));
    await _persistState();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    if (_currentQueue.isEmpty) return;

    if (_currentIndex < _currentQueue.length - 1) {
      _currentIndex++;
      await loadAndPlayTrack(_currentQueue[_currentIndex]);
    } else if (_repeatMode == AudioRepeatMode.all) {
      _currentIndex = 0;
      await loadAndPlayTrack(_currentQueue[_currentIndex]);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    if (_currentIndex > 0) {
      _currentIndex--;
      await loadAndPlayTrack(_currentQueue[_currentIndex]);
    } else {
      await seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < _currentQueue.length) {
      _currentIndex = index;
      await loadAndPlayTrack(_currentQueue[_currentIndex]);
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
      final current = _currentTrack;
      final copy = List<Track>.from(_unshuffledQueue);
      if (current != null) copy.remove(current);
      copy.shuffle();
      if (current != null) copy.insert(0, current);
      _currentQueue = copy;
      _currentIndex = 0;
    } else {
      final current = _currentTrack;
      _currentQueue = List.from(_unshuffledQueue);
      if (current != null) {
        _currentIndex = _currentQueue.indexWhere((t) => t.id == current.id);
        if (_currentIndex == -1) _currentIndex = 0;
      }
    }
    _syncMediaQueue();
    _emitSnapshot(
      _snapshot.copyWith(
        shuffleMode: _shuffleMode,
        queue: _currentQueue,
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
    if (_currentQueue.isEmpty) {
      loadAndPlayTrack(track);
      return;
    }
    _currentQueue.insert(_currentIndex + 1, track);
    _unshuffledQueue.add(track);
    _syncMediaQueue();
    _emitSnapshot(_snapshot.copyWith(queue: _currentQueue));
    unawaited(_persistQueue());
  }

  void playLast(Track track) {
    _currentQueue.add(track);
    _unshuffledQueue.add(track);
    _syncMediaQueue();
    _emitSnapshot(_snapshot.copyWith(queue: _currentQueue));
    unawaited(_persistQueue());
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _currentQueue.length ||
        newIndex < 0 ||
        newIndex > _currentQueue.length) {
      return;
    }
    final current = _currentTrack;
    final item = _currentQueue.removeAt(oldIndex);
    final insertAt = (oldIndex < newIndex) ? newIndex - 1 : newIndex;
    _currentQueue.insert(insertAt, item);

    if (current != null) {
      _currentIndex = _currentQueue.indexWhere((t) => t.id == current.id);
      if (_currentIndex == -1) _currentIndex = 0;
    }

    _syncMediaQueue();
    _emitSnapshot(
      _snapshot.copyWith(queue: _currentQueue, queueIndex: _currentIndex),
    );
    unawaited(_persistQueue());
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _currentQueue.length) return;
    final isCurrent = index == _currentIndex;
    _currentQueue.removeAt(index);

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
        loadAndPlayTrack(_currentQueue[_currentIndex]);
      } else if (index < _currentIndex) {
        _currentIndex--;
        _emitSnapshot(
          _snapshot.copyWith(queue: _currentQueue, queueIndex: _currentIndex),
        );
      } else {
        _emitSnapshot(_snapshot.copyWith(queue: _currentQueue));
      }
    }
    unawaited(_persistQueue());
  }

  void clearQueue() {
    stop();
    _currentQueue.clear();
    _unshuffledQueue.clear();
    _currentIndex = 0;
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
          await _database
              .into(_database.playbackQueue)
              .insert(
                PlaybackQueueCompanion(
                  id: drift.Value('q_${i}_${_currentQueue[i].id}'),
                  trackId: drift.Value(_currentQueue[i].id),
                  sortOrder: drift.Value(i),
                  addedAt: drift.Value(DateTime.now()),
                ),
              );
        }
      });
    } catch (_) {}
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
        final restoredTracks = queueEntries.map((row) {
          final t = row.readTable(_database.tracks);
          return Track(
            id: t.id,
            driveFileId: t.driveFileId,
            sourceId: t.sourceId,
            title: t.title,
            normalizedTitle: t.normalizedTitle,
            artistId: t.artistId,
            artistName: t.artistName,
            albumId: t.albumId,
            albumName: t.albumName,
            format: t.format,
            durationMs: t.durationMs,
            fileSize: t.fileSize,
            isCached: t.isCached,
            localPath: t.localPath,
          );
        }).toList();

        _currentQueue = restoredTracks;
        _unshuffledQueue = List.from(restoredTracks);
        _currentIndex = savedState?.queueIndex ?? 0;
        if (_currentIndex >= _currentQueue.length) _currentIndex = 0;

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
              queue: _currentQueue,
              queueIndex: _currentIndex,
            ),
          );
        }
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
  Future<void> removeFromQueue(int index) async =>
      _audioHandler.removeFromQueue(index);

  @override
  Future<void> clearQueue() async => _audioHandler.clearQueue();

  @override
  Future<void> restoreSavedState() => _audioHandler.restoreSavedState();
}
