import '../../../library/domain/entities/music_entities.dart';
import '../../../playlists/domain/entities/playlist_entities.dart';
import 'playback_state.dart';

abstract class PlaybackRepository {
  PlayerStateSnapshot get currentState;
  Stream<PlayerStateSnapshot> watchPlayerState();

  Future<void> playTrack(Track track, {List<Track>? queue, int? queueIndex});
  Future<void> playAlbum(Album album, List<Track> tracks, {int startIndex = 0});
  Future<void> playPlaylist(
    Playlist playlist,
    List<Track> tracks, {
    int startIndex = 0,
  });

  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> skipToNext();
  Future<void> skipToPrevious();

  Future<void> toggleShuffle();
  Future<void> cycleRepeatMode();

  Future<void> playNext(Track track);
  Future<void> playLast(Track track);
  Future<void> reorderQueue(int oldIndex, int newIndex);
  Future<void> moveQueueItem(String queueItemId, int destinationIndex);
  Future<void> removeFromQueue(int index);
  Future<void> removeQueueItem(String queueItemId);
  Future<void> clearQueue();
  Future<void> clearUpNext();
  Future<void> skipToQueueItem(int index);
  Future<void> skipToQueueItemById(String queueItemId);

  Future<void> restoreSavedState();
}
