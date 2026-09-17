import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
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
      backgroundColor: isDark
          ? CupertinoColors.black
          : CupertinoColors.systemBackground,
      navigationBar: CupertinoNavigationBar(
        previousPageTitle: 'Library',
        backgroundColor: CupertinoColors.transparent,
        border: null,
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minSize: 0,
          onPressed: () {
            if (playlist.id.isNotEmpty) {
              _showDeleteConfirm(context, ref, playlist.name);
            }
          },
          child: Icon(
            CupertinoIcons.trash,
            color: isDark
                ? CupertinoColors.white.withOpacity(0.5)
                : CupertinoColors.black.withOpacity(0.5),
            size: 22,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
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

            Widget artworkWidget;
            if (playlist.artworkPath != null &&
                playlist.artworkPath!.isNotEmpty) {
              artworkWidget = AlbumArtwork(
                artworkPath: playlist.artworkPath,
                size: artworkSize,
                borderRadius: 16.0,
              );
            } else {
              final distinctArts = <String>[];
              for (final t in tracks) {
                final p = t.artworkPath;
                if (p != null && p.isNotEmpty && !distinctArts.contains(p)) {
                  distinctArts.add(p);
                  if (distinctArts.length == 4) break;
                }
              }

              if (distinctArts.isEmpty) {
                artworkWidget = AlbumArtwork(
                  title: playlist.name,
                  size: artworkSize,
                  borderRadius: 16.0,
                );
              } else if (distinctArts.length < 4) {
                artworkWidget = AlbumArtwork(
                  artworkPath: distinctArts.first,
                  size: artworkSize,
                  borderRadius: 16.0,
                );
              } else {
                artworkWidget = SizedBox(
                  width: artworkSize,
                  height: artworkSize,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16.0),
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: AlbumArtwork(
                                  artworkPath: distinctArts[0],
                                  size: double.infinity,
                                  borderRadius: 0,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Expanded(
                                child: AlbumArtwork(
                                  artworkPath: distinctArts[1],
                                  size: double.infinity,
                                  borderRadius: 0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: AlbumArtwork(
                                  artworkPath: distinctArts[2],
                                  size: double.infinity,
                                  borderRadius: 0,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Expanded(
                                child: AlbumArtwork(
                                  artworkPath: distinctArts[3],
                                  size: double.infinity,
                                  borderRadius: 0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
            }

            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.lg,
                    ),
                    child: Column(
                      children: [
                        Center(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16.0),
                              boxShadow: [
                                BoxShadow(
                                  color: CupertinoColors.black.withOpacity(
                                    isDark ? 0.4 : 0.15,
                                  ),
                                  blurRadius: 24,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: artworkWidget,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          playlist.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: isDark
                                ? CupertinoColors.white
                                : CupertinoColors.black,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'}',
                          style: TextStyle(
                            fontSize: 15,
                            color: isDark
                                ? CupertinoColors.white.withOpacity(0.6)
                                : CupertinoColors.black.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Play
                        if (tracks.isNotEmpty)
                          Row(
                            children: [
                              Expanded(
                                child: CupertinoButton(
                                  color: CupertinoColors.systemPink,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  borderRadius: BorderRadius.circular(100),
                                  onPressed: () => ref
                                      .read(playbackRepositoryProvider)
                                      .playTrack(tracks.first, queue: tracks),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        CupertinoIcons.play_fill,
                                        size: 20,
                                        color: CupertinoColors.white,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Play',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                          color: CupertinoColors.white,
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

                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            );
          },
        ),
      ),
    );
  }
}
