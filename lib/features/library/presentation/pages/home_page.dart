import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../google_drive/presentation/pages/drive_connect_page.dart';
import '../widgets/album_artwork.dart';
import '../widgets/album_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_header.dart';
import '../widgets/song_row.dart';
import '../widgets/track_overflow_sheet.dart';
import 'album_detail_page.dart';
import 'artist_detail_page.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final greeting = AppGreeting.getGreeting();
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    final recentlyPlayedAsync = ref.watch(recentlyPlayedTracksProvider);
    final favoritesAsync = ref.watch(favoriteTracksProvider);
    final albumsAsync = ref.watch(allAlbumsProvider);
    final artistsAsync = ref.watch(allArtistsProvider);
    final playlistsAsync = ref.watch(playlistsProvider);
    final allTracksAsync = ref.watch(allTracksProvider('recent'));

    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.value;

    final recentlyPlayed = recentlyPlayedAsync.value ?? [];
    final favorites = favoritesAsync.value ?? [];
    final albums = albumsAsync.value ?? [];
    final artists = artistsAsync.value ?? [];
    final playlists = playlistsAsync.value ?? [];
    final recentTracks = allTracksAsync.value ?? [];

    final hasAnyData =
        recentlyPlayed.isNotEmpty ||
        favorites.isNotEmpty ||
        albums.isNotEmpty ||
        artists.isNotEmpty ||
        playlists.isNotEmpty ||
        recentTracks.isNotEmpty;

    return CupertinoPageScaffold(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        cacheExtent: 600.0,
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(greeting),
            border: null,
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: () {
                if (user == null) {
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (_) => const DriveConnectPage(),
                    ),
                  );
                }
              },
              child: Icon(
                user != null
                    ? CupertinoIcons.person_crop_circle_fill
                    : CupertinoIcons.cloud,
                color: CupertinoColors.systemPink,
                size: 26,
              ),
            ),
          ),
          if (!hasAnyData)
            SliverFillRemaining(
              child: EmptyState(
                icon: CupertinoIcons.music_albums,
                title: user == null
                    ? 'Connect Google Drive'
                    : 'No Music Indexed Yet',
                subtitle: user == null
                    ? 'Connect your Google Drive to build your personal music library.'
                    : 'Select your music folder in Settings or sync your library to start listening.',
                actionLabel: user == null ? 'Connect Drive' : 'Go to Settings',
                onAction: () {
                  if (user == null) {
                    Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => const DriveConnectPage(),
                      ),
                    );
                  }
                },
              ),
            )
          else
            SliverList(
              delegate: SliverChildListDelegate([
                // 1. Recently Played Section
                if (recentlyPlayed.isNotEmpty) ...[
                  const SectionHeader(title: 'Recently Played'),
                  SizedBox(
                    height: 195,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: recentlyPlayed.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: AppSpacing.md),
                      itemBuilder: (context, index) {
                        final track = recentlyPlayed[index];
                        return CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 0,
                          onPressed: () {
                            ref
                                .read(playbackRepositoryProvider)
                                .playTrack(track);
                          },
                          child: SizedBox(
                            width: 135,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AlbumArtwork(
                                  artworkPath: track.artworkPath,
                                  title: track.title,
                                  artist: track.artistName,
                                  size: 135,
                                  borderRadius: AppRadii.artwork,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? CupertinoColors.white
                                        : CupertinoColors.black,
                                  ),
                                ),
                                Text(
                                  track.artistName ?? 'Unknown Artist',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? CupertinoColors.systemGrey
                                        : CupertinoColors.secondaryLabel,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // 2. Favorites Section
                if (favorites.isNotEmpty) ...[
                  const SectionHeader(title: 'Favorites'),
                  SizedBox(
                    height: 195,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: favorites.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: AppSpacing.md),
                      itemBuilder: (context, index) {
                        final track = favorites[index];
                        return CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 0,
                          onPressed: () {
                            ref
                                .read(playbackRepositoryProvider)
                                .playTrack(track, queue: favorites);
                          },
                          child: SizedBox(
                            width: 135,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AlbumArtwork(
                                  artworkPath: track.artworkPath,
                                  title: track.title,
                                  artist: track.artistName,
                                  size: 135,
                                  borderRadius: AppRadii.card,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: isDark
                                        ? CupertinoColors.white
                                        : CupertinoColors.black,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  track.artistName ?? 'Unknown Artist',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: CupertinoColors.secondaryLabel,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // 3. Recently Added Songs
                if (recentTracks.isNotEmpty) ...[
                  const SectionHeader(title: 'Recently Added'),
                  ...recentTracks
                      .take(4)
                      .map(
                        (t) => SongRow(
                          track: t,
                          onTap: () => ref
                              .read(playbackRepositoryProvider)
                              .playTrack(t, queue: recentTracks),
                          onMore: () => showTrackActionSheet(
                            context: context,
                            track: t,
                            ref: ref,
                          ),
                        ),
                      ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // 4. Albums
                if (albums.isNotEmpty) ...[
                  const SectionHeader(title: 'Albums'),
                  SizedBox(
                    height: 200,
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

                // 5. Artists
                if (artists.isNotEmpty) ...[
                  const SectionHeader(title: 'Artists'),
                  SizedBox(
                    height: 135,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: artists.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: AppSpacing.md),
                      itemBuilder: (context, index) {
                        final artist = artists[index];
                        return CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 0,
                          onPressed: () {
                            Navigator.of(context).push(
                              CupertinoPageRoute(
                                builder: (_) =>
                                    ArtistDetailPage(artistId: artist.id),
                              ),
                            );
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AlbumArtwork(
                                artworkPath: artist.artworkPath,
                                title: artist.name,
                                artist: artist.name,
                                size: 84,
                                borderRadius: AppRadii.circular,
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: 90,
                                child: Text(
                                  artist.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? CupertinoColors.white
                                        : CupertinoColors.black,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // Padding at bottom for mini player
                const SizedBox(height: 100),
              ]),
            ),
        ],
      ),
    );
  }
}
