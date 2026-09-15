import '../../../../core/error/failures.dart';
import '../../../../core/result/result.dart';
import '../../../library/domain/entities/music_entities.dart';
import '../entities/playlist.dart';

abstract class PlaylistRepository {
  Stream<List<Playlist>> watchPlaylists();
  Stream<List<Track>> watchPlaylistTracks(String playlistId);
  Future<Result<String, AppFailure>> createPlaylist(
    String name, {
    String? description,
  });
  Future<Result<void, AppFailure>> renamePlaylist(
    String playlistId,
    String newName,
  );
  Future<Result<void, AppFailure>> deletePlaylist(String playlistId);
  Future<Result<void, AppFailure>> addTrackToPlaylist(
    String playlistId,
    String trackId,
  );
  Future<Result<void, AppFailure>> removeTrackFromPlaylist(
    String playlistId,
    String trackId,
  );
  Future<Result<void, AppFailure>> reorderPlaylistTracks(
    String playlistId,
    int oldIndex,
    int newIndex,
  );
}
