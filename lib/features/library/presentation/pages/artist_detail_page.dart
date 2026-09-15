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
  Widget build(BuildContext context, WidgetRef ref) {
    final artistWithAlbumsAsync = ref.watch(artistDetailProvider(artistId));
    final playerState = ref.watch(playerStateProvider).value;
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(previousPageTitle: 'Artists'),
      child: SafeArea(
        child: artistWithAlbumsAsync.when(
          loading: () =>
              const Center(child: CupertinoActivityIndicator(radius: 14)),
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
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      children: [
                        AlbumArtwork(
                          artworkPath: artist.artworkPath,
                          title: artist.name,
                          artist: artist.name,
                          size: 130,
                          borderRadius: AppRadii.circular,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          artist.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            color: isDark
                                ? CupertinoColors.white
                                : CupertinoColors.black,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${artist.albumCount} ${artist.albumCount == 1 ? 'album' : 'albums'} · ${artist.trackCount} ${artist.trackCount == 1 ? 'song' : 'songs'}',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? CupertinoColors.systemGrey
                                : CupertinoColors.secondaryLabel,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                    ),
                  ),
                ),

                // Albums Horizontal List
                if (albums.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(title: 'Albums'),
                        SizedBox(
                          height: 195,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            itemCount: albums.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(width: AppSpacing.md),
                            itemBuilder: (context, index) {
                              final album = albums[index];
                              return AlbumCard(
                                album: album,
                                width: 140,
                                onTap: () {
                                  Navigator.of(context).push(
                                    CupertinoPageRoute(
                                      builder: (_) =>
                                          AlbumDetailPage(albumId: album.id),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ),
                  ),
                ],

                // Songs List
                if (tracks.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: SectionHeader(title: 'Songs'),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final track = tracks[index];
                      final isPlaying =
                          playerState?.currentTrack?.id == track.id;
                      return SongRow(
                        track: track,
                        isPlaying: isPlaying,
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
                ],

                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            );
          },
        ),
      ),
    );
  }
}
