import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/music_entities.dart';
import '../widgets/album_artwork.dart';
import '../widgets/empty_state.dart';
import '../widgets/song_row.dart';
import '../widgets/track_overflow_sheet.dart';

class AlbumDetailPage extends ConsumerWidget {
  final String albumId;

  const AlbumDetailPage({super.key, required this.albumId});

  String _formatTotalDuration(int ms) {
    final dur = Duration(milliseconds: ms);
    final hours = dur.inHours;
    final minutes = dur.inMinutes % 60;
    if (hours > 0) {
      return '$hours hr $minutes min';
    }
    return '$minutes min';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumWithTracksAsync = ref.watch(albumDetailProvider(albumId));
    final playerState = ref.watch(playerStateProvider).value;
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(previousPageTitle: 'Library'),
      child: SafeArea(
        child: albumWithTracksAsync.when(
          loading: () =>
              const Center(child: CupertinoActivityIndicator(radius: 14)),
          error: (e, _) => EmptyState(
            icon: CupertinoIcons.exclamationmark_triangle,
            title: 'Error loading album',
            subtitle: e.toString(),
          ),
          data: (data) {
            if (data == null) {
              return const EmptyState(
                icon: CupertinoIcons.music_albums,
                title: 'Album Not Found',
              );
            }

            final album = data.album;
            final tracks = data.tracks;
            final artworkSize = MediaQuery.of(context).size.width * 0.55;

            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      children: [
                        Center(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                AppRadii.artwork,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: CupertinoColors.black.withOpacity(
                                    0.18,
                                  ),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: AlbumArtwork(
                              artworkPath: album.artworkPath,
                              title: album.title,
                              artist: album.artistName,
                              size: artworkSize,
                              borderRadius: AppRadii.artwork,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          album.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            color: isDark
                                ? CupertinoColors.white
                                : CupertinoColors.black,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          album.artistName ?? 'Unknown Artist',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            color: CupertinoColors.systemPink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${album.trackCount} ${album.trackCount == 1 ? 'song' : 'songs'} · ${_formatTotalDuration(album.totalDurationMs)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? CupertinoColors.systemGrey
                                : CupertinoColors.secondaryLabel,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Action Buttons: Play & Shuffle
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
                                onPressed: tracks.isNotEmpty
                                    ? () => ref
                                          .read(playbackRepositoryProvider)
                                          .playAlbum(album, tracks)
                                    : null,
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
                                onPressed: tracks.isNotEmpty
                                    ? () {
                                        final shuffled = List<Track>.from(
                                          tracks,
                                        )..shuffle();
                                        ref
                                            .read(playbackRepositoryProvider)
                                            .playAlbum(album, shuffled);
                                      }
                                    : null,
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

                // Track List
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final track = tracks[index];
                    final isPlaying = playerState?.currentTrack?.id == track.id;

                    // Check for multi-disc separator
                    final showDiscHeader = index == 0
                        ? (track.discNumber != null && track.discNumber! > 1)
                        : (track.discNumber != null &&
                              track.discNumber != tracks[index - 1].discNumber);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showDiscHeader)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              AppSpacing.sm,
                              AppSpacing.md,
                              4,
                            ),
                            child: Text(
                              'DISC ${track.discNumber}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: isDark
                                    ? CupertinoColors.systemGrey
                                    : CupertinoColors.secondaryLabel,
                              ),
                            ),
                          ),
                        SongRow(
                          track: track,
                          isPlaying: isPlaying,
                          trackNumber: track.trackNumber ?? (index + 1),
                          onTap: () => ref
                              .read(playbackRepositoryProvider)
                              .playAlbum(album, tracks, startIndex: index),
                          onMore: () => showTrackActionSheet(
                            context: context,
                            track: track,
                            ref: ref,
                          ),
                        ),
                      ],
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
