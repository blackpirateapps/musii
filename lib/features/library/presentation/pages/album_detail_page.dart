import "dart:io";
import "dart:ui";
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
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
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumWithTracksAsync = ref.watch(albumDetailProvider(albumId));
    final playerState = ref.watch(playerStateProvider).value;
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoPageScaffold(
      backgroundColor: isDark ? const Color(0xFF0C0D12) : CupertinoColors.systemBackground,
      navigationBar: const CupertinoNavigationBar(
        previousPageTitle: 'Library', 
        backgroundColor: CupertinoColors.transparent, 
        border: null
      ),
      child: albumWithTracksAsync.when(
        loading: () => const Center(child: CupertinoActivityIndicator(radius: 14)),
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
          final artworkSize = MediaQuery.of(context).size.width * 0.65;

          return Stack(
            children: [
              // Atmospheric Background
              if (album.artworkPath != null && album.artworkPath!.isNotEmpty)
                Positioned(
                  top: -100,
                  left: -50,
                  right: -50,
                  height: MediaQuery.of(context).size.width + 100,
                  child: Opacity(
                    opacity: isDark ? 0.35 : 0.15,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 80.0, sigmaY: 80.0),
                      child: Image.file(
                        File(album.artworkPath!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              // Content
              SafeArea(
                bottom: false,
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.lg),
                        child: Column(
                          children: [
                            Center(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16.0),
                                  boxShadow: [
                                    BoxShadow(
                                      color: CupertinoColors.black.withOpacity(isDark ? 0.4 : 0.15),
                                      blurRadius: 24,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: AlbumArtwork(
                                  artworkPath: album.artworkPath,
                                  title: album.title,
                                  artist: album.artistName,
                                  size: artworkSize,
                                  borderRadius: 16.0,
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            Text(
                              album.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                                color: isDark ? CupertinoColors.white : CupertinoColors.black,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              album.artistName ?? 'Unknown Artist',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w400,
                                color: isDark ? CupertinoColors.white.withOpacity(0.8) : CupertinoColors.black.withOpacity(0.8),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${album.trackCount} ${album.trackCount == 1 ? 'song' : 'songs'} · ${_formatTotalDuration(album.totalDurationMs)}',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? CupertinoColors.white.withOpacity(0.5) : CupertinoColors.black.withOpacity(0.5),
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Action Buttons: Play
                            Row(
                              children: [
                                Expanded(
                                  child: CupertinoButton(
                                    color: CupertinoColors.systemPink,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    borderRadius: BorderRadius.circular(100),
                                    onPressed: tracks.isNotEmpty
                                        ? () => ref
                                              .read(playbackRepositoryProvider)
                                              .playAlbum(album, tracks)
                                        : null,
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(CupertinoIcons.play_fill, size: 20, color: CupertinoColors.white),
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
                            const SizedBox(height: AppSpacing.lg),
                          ],
                        ),
                      ),
                    ),

                    // Track List
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final track = tracks[index];
                        final isPlaying = playerState?.currentTrack?.id == track.id;

                        final showDiscHeader = index == 0
                            ? (track.discNumber != null && track.discNumber! > 1)
                            : (track.discNumber != null &&
                                  track.discNumber != tracks[index - 1].discNumber);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showDiscHeader)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 4),
                                child: Text(
                                  'DISC ${track.discNumber}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                    color: isDark ? CupertinoColors.white.withOpacity(0.5) : CupertinoColors.black.withOpacity(0.5),
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

                    const SliverToBoxAdapter(child: SizedBox(height: 120)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
