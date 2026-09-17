import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../widgets/album_artwork.dart';
import '../widgets/album_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_header.dart';
import '../widgets/song_row.dart';
import '../widgets/track_overflow_sheet.dart';
import 'album_detail_page.dart';

class ArtistDetailPage extends ConsumerWidget {
  final String artistId;

  const ArtistDetailPage({super.key, required this.artistId});

  @override
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistWithAlbumsAsync = ref.watch(artistDetailProvider(artistId));
    final playerState = ref.watch(playerStateProvider).value;
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoPageScaffold(
      backgroundColor: isDark ? CupertinoColors.black : CupertinoColors.systemBackground,
      navigationBar: const CupertinoNavigationBar(previousPageTitle: 'Library', backgroundColor: CupertinoColors.transparent, border: null),
      child: artistWithAlbumsAsync.when(
        loading: () => const Center(child: CupertinoActivityIndicator(radius: 14)),
        error: (e, _) => EmptyState(
          icon: CupertinoIcons.exclamationmark_triangle,
          title: 'Error loading artist',
          subtitle: e.toString(),
        ),
        data: (data) {
          if (data == null) {
            return const EmptyState(
              icon: CupertinoIcons.person,
              title: 'Artist Not Found',
            );
          }

          final artist = data.artist;
          final albums = data.albums;
          final tracks = data.topTracks;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, 16, AppSpacing.md, AppSpacing.lg),
                  child: Column(
                    children: [
                      // Immersive Image
                      AspectRatio(
                        aspectRatio: 1.0,
                        child: AlbumArtwork(
                          artworkPath: artist.artworkPath,
                          title: artist.name,
                          artist: artist.name,
                          size: double.infinity,
                          borderRadius: 24.0,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        artist.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: isDark ? CupertinoColors.white : CupertinoColors.black,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${artist.trackCount} ${artist.trackCount == 1 ? 'song' : 'songs'}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: isDark ? CupertinoColors.white.withOpacity(0.6) : CupertinoColors.black.withOpacity(0.6),
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
                                        .playTrack(tracks.first, queue: tracks, queueIndex: 0)
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

              // Songs List (Popular)
              if (tracks.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: SectionHeader(title: 'Popular'),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final track = tracks[index];
                    final isPlaying = playerState?.currentTrack?.id == track.id;
                    return SongRow(
                      track: track,
                      isPlaying: isPlaying,
                      trackNumber: index + 1, // Clean ranked list
                      onTap: () => ref
                          .read(playbackRepositoryProvider)
                          .playTrack(track, queue: tracks, queueIndex: index),
                      onMore: () => showTrackActionSheet(
                        context: context,
                        track: track,
                        ref: ref,
                      ),
                    );
                  }, childCount: tracks.length > 5 ? 5 : tracks.length),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
              ],

              // Albums Grid
              if (albums.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: SectionHeader(title: 'Albums'),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                      crossAxisSpacing: AppSpacing.md,
                      mainAxisSpacing: 24.0,
                      childAspectRatio: (MediaQuery.of(context).size.width - AppSpacing.md * 3) / 2 / ((MediaQuery.of(context).size.width - AppSpacing.md * 3) / 2 + 60),
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final album = albums[index];
                      return AlbumCard(
                        album: album,
                        onTap: () {
                          Navigator.of(context).push(
                            CupertinoPageRoute(
                              builder: (_) => AlbumDetailPage(albumId: album.id),
                            ),
                          );
                        },
                      );
                    }, childCount: albums.length),
                  ),
                ),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          );
        },
      ),
    );
  }
}
