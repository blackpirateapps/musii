import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../google_drive/presentation/pages/drive_connect_page.dart';
import '../../../playback/presentation/pages/now_playing_page.dart';
import '../../../playlists/presentation/pages/playlist_detail_page.dart';
import '../../domain/entities/music_entities.dart';
import '../widgets/account_info_sheet.dart';
import '../widgets/album_artwork.dart';
import '../widgets/continue_listening_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/home_artwork_card.dart';
import '../widgets/section_header.dart';
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
    final recentTracksAsync = ref.watch(allTracksProvider('recent'));
    final currentPlayingTrack = ref.watch(
      playerStateProvider.select((s) => s.value?.currentTrack),
    );

    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.value;

    final recentlyPlayed = recentlyPlayedAsync.value ?? [];
    final favorites = favoritesAsync.value ?? [];
    final albums = albumsAsync.value ?? [];
    final artists = artistsAsync.value ?? [];
    final playlists = playlistsAsync.value ?? [];
    final recentTracks = recentTracksAsync.value ?? [];

    // Derive track for Continue Listening:
    // 1. Currently active track
    // 2. Most recent track from recently played
    // 3. First track from recent tracks if available
    Track? continueListeningTrack = currentPlayingTrack;
    if (continueListeningTrack == null && recentlyPlayed.isNotEmpty) {
      continueListeningTrack = recentlyPlayed.first;
    } else if (continueListeningTrack == null && recentTracks.isNotEmpty) {
      continueListeningTrack = recentTracks.first;
    }

    final hasAnyData =
        recentlyPlayed.isNotEmpty ||
        favorites.isNotEmpty ||
        albums.isNotEmpty ||
        artists.isNotEmpty ||
        playlists.isNotEmpty ||
        recentTracks.isNotEmpty;

    return CupertinoPageScaffold(
      backgroundColor: isDark
          ? const Color(0xFF0C0D12)
          : CupertinoColors.systemBackground,
      child: Stack(
        children: [
          // 1. Subtle Atmospheric Twilight / Sunset Glow Backdrop
          if (isDark)
            Positioned(
              top: -60,
              left: -40,
              right: -40,
              height: 380,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-0.4, -0.6),
                      radius: 1.1,
                      colors: [
                        Color(0x3AE67E51), // Warm sunset twilight glow
                        Color(0x283A5376), // Rich twilight navy
                        CupertinoColors.transparent,
                      ],
                      stops: [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
            ),

          // 2. Main Scrollable Content
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            cacheExtent: 600.0,
            slivers: [
              // Top Safe Area & Custom Atmospheric Header
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      AppSpacing.xs,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Greeting and Subtitle
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                greeting,
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.6,
                                  color: isDark
                                      ? CupertinoColors.white
                                      : CupertinoColors.black,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Your music, your way.',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: -0.2,
                                  color: isDark
                                      ? CupertinoColors.white.withOpacity(0.60)
                                      : CupertinoColors.secondaryLabel,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Subtle Upper-Right Profile Avatar Control
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 0,
                          onPressed: () {
                            if (user != null) {
                              showAccountInfoSheet(context, user, ref);
                            } else {
                              Navigator.of(context).push(
                                CupertinoPageRoute(
                                  builder: (_) => const DriveConnectPage(),
                                ),
                              );
                            }
                          },
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark
                                  ? const Color(0xFF2C2C2E)
                                  : CupertinoColors.systemGrey5,
                              border: Border.all(
                                color: isDark
                                    ? CupertinoColors.white.withOpacity(0.20)
                                    : CupertinoColors.black.withOpacity(0.10),
                                width: 1.2,
                              ),
                            ),
                            child: ClipOval(
                              child:
                                  (user?.photoUrl != null &&
                                      user!.photoUrl!.isNotEmpty)
                                  ? Image.network(
                                      user.photoUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Center(
                                        child: Text(
                                          (user.displayName?.isNotEmpty == true)
                                              ? user.displayName![0]
                                                    .toUpperCase()
                                              : 'U',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: CupertinoColors.systemPink,
                                          ),
                                        ),
                                      ),
                                    )
                                  : Center(
                                      child: Icon(
                                        user != null
                                            ? CupertinoIcons.person_fill
                                            : CupertinoIcons.cloud,
                                        size: 20,
                                        color: isDark
                                            ? CupertinoColors.white
                                            : CupertinoColors.black,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
                    actionLabel: user == null
                        ? 'Connect Drive'
                        : 'Go to Settings',
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
                    // 1. Continue Listening Section
                    if (continueListeningTrack != null) ...[
                      SectionHeader(
                        title: 'Continue Listening',
                        showTitleChevron: true,
                        onTitleTap: () {
                          Navigator.of(context, rootNavigator: true).push(
                            CupertinoPageRoute(
                              fullscreenDialog: true,
                              builder: (_) => const NowPlayingPage(),
                            ),
                          );
                        },
                      ),
                      ContinueListeningCard(track: continueListeningTrack),
                    ],

                    // 2. Favorites Horizontal Carousel
                    if (favorites.isNotEmpty) ...[
                      SectionHeader(
                        title: 'Favorites',
                        onSeeAll: () {
                          // Navigate to Library
                        },
                      ),
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
                            return HomeArtworkCard.fromTrack(
                              track: track,
                              onTap: () {
                                ref
                                    .read(playbackRepositoryProvider)
                                    .playTrack(
                                      track,
                                      queue: favorites,
                                      queueIndex: index,
                                    );
                              },
                            );
                          },
                        ),
                      ),
                    ],

                    // 3. Recently Played Horizontal Carousel
                    if (recentlyPlayed.isNotEmpty) ...[
                      SectionHeader(
                        title: 'Recently Played',
                        onSeeAll: () {
                          // Navigate to Library
                        },
                      ),
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
                            return HomeArtworkCard.fromTrack(
                              track: track,
                              onTap: () {
                                ref
                                    .read(playbackRepositoryProvider)
                                    .playTrack(
                                      track,
                                      queue: recentlyPlayed,
                                      queueIndex: index,
                                    );
                              },
                            );
                          },
                        ),
                      ),
                    ],

                    // 4. Recently Added Horizontal Carousel
                    if (recentTracks.isNotEmpty) ...[
                      SectionHeader(
                        title: 'Recently Added',
                        onSeeAll: () {
                          // Navigate to Library
                        },
                      ),
                      SizedBox(
                        height: 195,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: recentTracks.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: AppSpacing.md),
                          itemBuilder: (context, index) {
                            final track = recentTracks[index];
                            return HomeArtworkCard.fromTrack(
                              track: track,
                              onTap: () {
                                ref
                                    .read(playbackRepositoryProvider)
                                    .playTrack(
                                      track,
                                      queue: recentTracks,
                                      queueIndex: index,
                                    );
                              },
                            );
                          },
                        ),
                      ),
                    ],

                    // 5. Albums Horizontal Carousel
                    if (albums.isNotEmpty) ...[
                      SectionHeader(
                        title: 'Albums',
                        onSeeAll: () {
                          // Navigate to Library Albums
                        },
                      ),
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
                            return HomeArtworkCard.fromAlbum(
                              album: album,
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
                    ],

                    // 6. Artists Horizontal Carousel
                    if (artists.isNotEmpty) ...[
                      SectionHeader(
                        title: 'Artists',
                        onSeeAll: () {
                          // Navigate to Library Artists
                        },
                      ),
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
                                    size: 80,
                                    borderRadius: AppRadii.circular,
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    width: 88,
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
                    ],

                    // 7. Playlists Horizontal Carousel
                    if (playlists.isNotEmpty) ...[
                      SectionHeader(
                        title: 'Playlists',
                        onSeeAll: () {
                          // Navigate to Library Playlists
                        },
                      ),
                      SizedBox(
                        height: 195,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: playlists.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: AppSpacing.md),
                          itemBuilder: (context, index) {
                            final pl = playlists[index];
                            return HomeArtworkCard(
                              title: pl.name,
                              subtitle:
                                  '${pl.trackCount} ${pl.trackCount == 1 ? 'song' : 'songs'}',
                              artworkPath: pl.artworkPath,
                              onTap: () {
                                Navigator.of(context).push(
                                  CupertinoPageRoute(
                                    builder: (_) =>
                                        PlaylistDetailPage(playlistId: pl.id),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],

                    // Bottom padding for docked mini-player
                    const SizedBox(height: 110),
                  ]),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
