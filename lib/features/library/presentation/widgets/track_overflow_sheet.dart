import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../lyrics/presentation/pages/lyrics_sheet.dart';
import '../../domain/entities/music_entities.dart';
import '../pages/album_detail_page.dart';
import '../pages/artist_detail_page.dart';
import 'audio_info_sheet.dart';

enum TrackActionContext {
  queue,
  nowPlaying,
  library,
  album,
  artist,
  playlist,
  search,
  favorites,
}

Future<void> showTrackActionSheet({
  required BuildContext context,
  required Track track,
  required WidgetRef ref,
  TrackActionContext trackContext = TrackActionContext.library,
  String? queueItemId,
  int? queueIndex,
  VoidCallback? onRemovedFromQueue,
}) async {
  final isFav = ref.read(isTrackFavoriteProvider(track.id)).value ?? false;

  if (!context.mounted) return;

  await showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: Text(
        track.title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      message: Text(
        '${track.artistName ?? 'Unknown Artist'} · ${track.albumName ?? 'Unknown Album'}',
      ),
      actions: [
        if (trackContext == TrackActionContext.queue) ...[
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              HapticFeedback.lightImpact();
              if (queueItemId != null) {
                ref
                    .read(playbackRepositoryProvider)
                    .skipToQueueItemById(queueItemId);
              } else if (queueIndex != null) {
                ref
                    .read(playbackRepositoryProvider)
                    .skipToQueueItem(queueIndex);
              } else {
                ref.read(playbackRepositoryProvider).playTrack(track);
              }
            },
            child: const Text('Play Now'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              HapticFeedback.lightImpact();
              ref.read(playbackRepositoryProvider).playNext(track);
            },
            child: const Text('Play Next'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              HapticFeedback.mediumImpact();
              if (queueItemId != null) {
                ref
                    .read(playbackRepositoryProvider)
                    .removeQueueItem(queueItemId);
              } else if (queueIndex != null) {
                ref
                    .read(playbackRepositoryProvider)
                    .removeFromQueue(queueIndex);
              }
              onRemovedFromQueue?.call();
            },
            child: const Text('Remove from Queue'),
          ),
        ] else if (trackContext == TrackActionContext.nowPlaying) ...[
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              HapticFeedback.lightImpact();
              ref.read(playbackRepositoryProvider).playNext(track);
            },
            child: const Text('Play Next'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              HapticFeedback.lightImpact();
              ref.read(playbackRepositoryProvider).playLast(track);
            },
            child: const Text('Add to Queue'),
          ),
        ] else ...[
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              HapticFeedback.lightImpact();
              ref.read(playbackRepositoryProvider).playTrack(track);
            },
            child: const Text('Play'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              HapticFeedback.lightImpact();
              ref.read(playbackRepositoryProvider).playNext(track);
            },
            child: const Text('Play Next'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              HapticFeedback.lightImpact();
              ref.read(playbackRepositoryProvider).playLast(track);
            },
            child: const Text('Add to Queue'),
          ),
        ],
        CupertinoActionSheetAction(
          onPressed: () async {
            Navigator.pop(ctx);
            await HapticFeedback.lightImpact();
            await ref
                .read(favoriteRepositoryProvider)
                .toggleFavorite(track.id);
          },
          child: Text(isFav ? 'Remove from Favorites' : 'Favorite'),
        ),
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(ctx);
            HapticFeedback.lightImpact();
            _showAddToPlaylistDialog(context, track, ref);
          },
          child: const Text('Add to Playlist...'),
        ),
        CupertinoActionSheetAction(
          onPressed: () async {
            Navigator.pop(ctx);
            await HapticFeedback.lightImpact();
            final cacheRepo = ref.read(cacheRepositoryProvider);
            if (track.isPinnedOffline) {
              await cacheRepo.unpinTrackOffline(track.id);
            } else {
              await cacheRepo.pinTrackOffline(track.id);
            }
          },
          child: Text(
            track.isPinnedOffline
                ? 'Remove Offline Download'
                : 'Download for Offline',
          ),
        ),
        if (track.albumId != null &&
            trackContext != TrackActionContext.album)
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                CupertinoPageRoute(
                  builder: (_) => AlbumDetailPage(albumId: track.albumId!),
                ),
              );
            },
            child: const Text('View Album'),
          ),
        if (track.artistId != null &&
            trackContext != TrackActionContext.artist)
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                CupertinoPageRoute(
                  builder: (_) => ArtistDetailPage(artistId: track.artistId!),
                ),
              );
            },
            child: const Text('View Artist'),
          ),
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(ctx);
            HapticFeedback.lightImpact();
            showLyricsSheet(context, track);
          },
          child: const Text('Lyrics'),
        ),
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(ctx);
            HapticFeedback.lightImpact();
            showAudioInfoSheet(context, track);
          },
          child: const Text('Audio Information'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Cancel'),
      ),
    ),
  );
}

void _showAddToPlaylistDialog(
  BuildContext context,
  Track track,
  WidgetRef ref,
) {
  final playlistsAsync = ref.read(playlistsProvider);
  playlistsAsync.whenData((playlists) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Add to Playlist'),
        message: const Text('Choose a destination playlist'),
        actions: [
          ...playlists.map(
            (pl) => CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(ctx);
                await HapticFeedback.lightImpact();
                await ref
                    .read(playlistRepositoryProvider)
                    .addTrackToPlaylist(pl.id, track.id);
              },
              child: Text(pl.name),
            ),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: false,
            onPressed: () {
              Navigator.pop(ctx);
              HapticFeedback.lightImpact();
              _showCreatePlaylistDialog(context, track, ref);
            },
            child: const Text('New Playlist...'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  });
}

void _showCreatePlaylistDialog(
  BuildContext context,
  Track track,
  WidgetRef ref,
) {
  final controller = TextEditingController();
  showCupertinoDialog<void>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: const Text('New Playlist'),
      content: Padding(
        padding: const EdgeInsets.only(top: 12.0),
        child: CupertinoTextField(
          controller: controller,
          placeholder: 'Playlist Name',
          autofocus: true,
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () async {
            final name = controller.text.trim();
            if (name.isNotEmpty) {
              Navigator.pop(ctx);
              await HapticFeedback.lightImpact();
              final createRes = await ref
                  .read(playlistRepositoryProvider)
                  .createPlaylist(name);
              if (createRes.isSuccess) {
                await ref
                    .read(playlistRepositoryProvider)
                    .addTrackToPlaylist(createRes.dataOrNull!, track.id);
              }
            }
          },
          child: const Text('Create'),
        ),
      ],
    ),
  );
}
