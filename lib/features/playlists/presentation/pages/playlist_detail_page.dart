import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../library/domain/entities/music_entities.dart';
import '../../../library/presentation/widgets/album_artwork.dart';
import '../../../library/presentation/widgets/empty_state.dart';
import '../../../library/presentation/widgets/song_row.dart';
import '../../../library/presentation/widgets/track_overflow_sheet.dart';
import '../../domain/entities/playlist_entities.dart';

class PlaylistDetailPage extends ConsumerWidget {
  final String playlistId;

  const PlaylistDetailPage({super.key, required this.playlistId});

  void _showDeleteConfirm(BuildContext context, WidgetRef ref, String name) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text(
          'Are you sure you want to delete this playlist? Tracks will remain in your library.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete'),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref
                  .read(playlistRepositoryProvider)
                  .deletePlaylist(playlistId);
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final tracksAsync = ref.watch(playlistTracksProvider(playlistId));
    final playerState = ref.watch(playerStateProvider).value;
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    final playlists = playlistsAsync.value ?? <Playlist>[];
    final playlist =
        playlists.where((p) => p.id == playlistId).firstOrNull ??
        Playlist(
          id: '',
          name: 'Playlist',
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        );

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        previousPageTitle: 'Library',
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minSize: 0,
          onPressed: () {
            if (playlist.id.isNotEmpty) {
              _showDeleteConfirm(context, ref, playlist.name);
            }
          },
          child: const Icon(
            CupertinoIcons.trash,
            color: CupertinoColors.destructiveRed,
            size: 20,
          ),
        ),
      ),
      child: SafeArea(
        child: tracksAsync.when(
          loading: () =>
              const Center(child: CupertinoActivityIndicator(radius: 14)),
          error: (e, _) => EmptyState(
            icon: CupertinoIcons.exclamationmark_triangle,
            title: 'Error loading playlist',
            subtitle: e.toString(),
          ),
          data: (tracks) {
            final artworkSize = MediaQuery.of(context).size.width * 0.50;

            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      children: [
                        Center(
                          child: AlbumArtwork(
                            artworkPath: playlist.artworkPath,
                            title: playlist.name,
                            size: artworkSize,
                            borderRadius: AppRadii.card,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          playlist.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            color: isDark
                                ? CupertinoColors.white
                                : CupertinoColors.black,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'}',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? CupertinoColors.systemGrey
                                : CupertinoColors.secondaryLabel,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Play & Shuffle
                        if (tracks.isNotEmpty)
                          Row(
                            children: [
                              Expanded(
                                child: CupertinoButton.filled(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.card,
                                  ),
                                  onPressed: () => ref
                                      .read(playbackRepositoryProvider)
                                      .playTrack(tracks.first, queue: tracks),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(CupertinoIcons.play_fill, size: 18),
                                      SizedBox(width: 8),
                                      Text(
                                        'Play',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: CupertinoButton(
                                  color: isDark
                                      ? CupertinoColors.white.withOpacity(0.12)
                                      : CupertinoColors.black.withOpacity(0.06),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.card,
                                  ),
                                  onPressed: () {
                                    final shuffled = List<Track>.from(tracks)
                                      ..shuffle();
                                    ref
                                        .read(playbackRepositoryProvider)
                                        .playTrack(
                                          shuffled.first,
                                          queue: shuffled,
                                        );
                                  },
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        CupertinoIcons.shuffle,
                                        size: 18,
                                        color: isDark
                                            ? CupertinoColors.white
                                            : CupertinoColors.black,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Shuffle',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? CupertinoColors.white
                                              : CupertinoColors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ),
                  ),
                ),

                if (tracks.isEmpty)
                  const SliverFillRemaining(
                    child: EmptyState(
                      icon: CupertinoIcons.music_note_list,
                      title: 'Playlist is Empty',
                      subtitle: 'Add songs to this playlist from any track overflow menu.',
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final track = tracks[index];
                      final isPlaying =
                          playerState?.currentTrack?.id == track.id;
                      return SongRow(
                        track: track,
                        isPlaying: isPlaying,
                        trackNumber: index + 1,
                        onTap: () => ref
                            .read(playbackRepositoryProvider)
                            .playTrack(track, queue: tracks, queueIndex: index),
                        onMore: () => showTrackActionSheet(
                          context: context,
                          track: track,
                          ref: ref,
                        ),
                      );
                    }, childCount: tracks.length),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            );
          },
        ),
      ),
    );
  }
}
