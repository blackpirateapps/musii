import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../domain/entities/music_entities.dart';
import 'audio_info_sheet.dart';

void showTrackActionSheet({
  required BuildContext context,
  required Track track,
  required WidgetRef ref,
}) async {
  final isFav = await ref.read(isTrackFavoriteProvider(track.id).future);

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
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(ctx);
            ref.read(playbackRepositoryProvider).playTrack(track);
          },
          child: const Text('Play'),
        ),
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(ctx);
            ref.read(playbackRepositoryProvider).playNext(track);
          },
          child: const Text('Play Next'),
        ),
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(ctx);
            ref.read(playbackRepositoryProvider).playLast(track);
          },
          child: const Text('Add to Queue'),
        ),
        CupertinoActionSheetAction(
          onPressed: () async {
            Navigator.pop(ctx);
            final res = await ref
                .read(favoriteRepositoryProvider)
                .toggleFavorite(track.id);
            if (context.mounted && res.isSuccess) {
              // Updated reactively
            }
          },
          child: Text(isFav ? 'Remove from Favorites' : 'Favorite'),
        ),
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(ctx);
            _showAddToPlaylistDialog(context, track, ref);
          },
          child: const Text('Add to Playlist...'),
        ),
        CupertinoActionSheetAction(
          onPressed: () async {
            Navigator.pop(ctx);
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
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(ctx);
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
