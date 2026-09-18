import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../playlists/presentation/pages/playlist_detail_page.dart';
import '../widgets/album_card.dart';
import '../widgets/artist_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/playlist_card.dart';
import '../widgets/song_row.dart';
import '../widgets/track_overflow_sheet.dart';
import 'album_detail_page.dart';
import 'artist_detail_page.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  int _selectedCategory = 0; // 0: Albums, 1: Artists, 2: Songs, 3: Playlists

  void _showNewPlaylistDialog() {
    final controller = TextEditingController();
    showCupertinoDialog(
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
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Create'),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx);
                await ref.read(playlistRepositoryProvider).createPlaylist(name);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String title, int index, bool isDark) {
    final isSelected = _selectedCategory == index;
    return GestureDetector(
      onTap: () {
        if (_selectedCategory != index) {
          setState(() => _selectedCategory = index);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(right: 24.0, bottom: 8.0, top: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                letterSpacing: -0.2,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                    : (isDark
                          ? CupertinoColors.white.withOpacity(0.5)
                          : CupertinoColors.black.withOpacity(0.5)),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              height: 2,
              width: isSelected ? 24 : 0,
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                    : CupertinoColors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final albumsAsync = ref.watch(allAlbumsProvider);
    final artistsAsync = ref.watch(allArtistsProvider);
    final songsAsync = ref.watch(allTracksProvider(null));
    final playlistsAsync = ref.watch(playlistsProvider);
    final currentTrackId = ref.watch(
      playerStateProvider.select((s) => s.value?.currentTrack?.id),
    );

    return CupertinoPageScaffold(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        cacheExtent: 600.0,
        slivers: [
          // Custom Quiet Header & Tabs
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Library',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.0,
                            color: isDark
                                ? CupertinoColors.white
                                : CupertinoColors.black,
                          ),
                        ),
                        if (_selectedCategory == 3)
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            minSize: 0,
                            onPressed: _showNewPlaylistDialog,
                            child: Icon(
                              CupertinoIcons.add,
                              size: 24,
                              color: isDark
                                  ? CupertinoColors.white
                                  : CupertinoColors.black,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildTab('Albums', 0, isDark),
                          _buildTab('Artists', 1, isDark),
                          _buildTab('Songs', 2, isDark),
                          _buildTab('Playlists', 3, isDark),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Content based on Selected Category
          switch (_selectedCategory) {
            // 0: Albums Grid
            0 => albumsAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CupertinoActivityIndicator()),
              ),
              error: (e, _) => SliverFillRemaining(
                child: EmptyState(
                  icon: CupertinoIcons.exclamationmark_triangle,
                  title: 'Error loading albums',
                  subtitle: e.toString(),
                ),
              ),
              data: (albums) {
                if (albums.isEmpty) {
                  return const SliverFillRemaining(
                    child: EmptyState(
                      icon: CupertinoIcons.music_albums,
                      title: 'No Albums Found',
                      subtitle: 'Audio albums indexed from Google Drive will appear here.',
                    ),
                  );
                }

                final screenWidth = MediaQuery.of(context).size.width;
                final crossAxisCount = screenWidth > 600 ? 4 : 2;
                final itemWidth =
                    (screenWidth -
                        (AppSpacing.md * 2) -
                        ((crossAxisCount - 1) * AppSpacing.md)) /
                    crossAxisCount;

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: AppSpacing.md,
                      mainAxisSpacing: 24.0,
                      childAspectRatio: itemWidth / (itemWidth + 60),
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final album = albums[index];
                      return AlbumCard(
                        album: album,
                        width: itemWidth,
                        onTap: () {
                          Navigator.of(context).push(
                            CupertinoPageRoute(
                              builder: (_) =>
                                  AlbumDetailPage(albumId: album.id),
                            ),
                          );
                        },
                      );
                    }, childCount: albums.length),
                  ),
                );
              },
            ),

            // 1: Artists List
            1 => artistsAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CupertinoActivityIndicator()),
              ),
              error: (e, _) => SliverFillRemaining(
                child: EmptyState(
                  icon: CupertinoIcons.exclamationmark_triangle,
                  title: 'Error loading artists',
                  subtitle: e.toString(),
                ),
              ),
              data: (artists) {
                if (artists.isEmpty) {
                  return const SliverFillRemaining(
                    child: EmptyState(
                      icon: CupertinoIcons.person_2,
                      title: 'No Artists Found',
                      subtitle:
                          'Artists found in your music tags will appear here.',
                    ),
                  );
                }

                final screenWidth = MediaQuery.of(context).size.width;
                final crossAxisCount = screenWidth > 600 ? 4 : 2;
                final itemWidth =
                    (screenWidth -
                        (AppSpacing.md * 2) -
                        ((crossAxisCount - 1) * AppSpacing.md)) /
                    crossAxisCount;

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: AppSpacing.md,
                      mainAxisSpacing: 24.0,
                      childAspectRatio: itemWidth / (itemWidth * (4 / 3) + 50),
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final artist = artists[index];
                      return ArtistCard(
                        artist: artist,
                        onTap: () {
                          Navigator.of(context).push(
                            CupertinoPageRoute(
                              builder: (_) =>
                                  ArtistDetailPage(artistId: artist.id),
                            ),
                          );
                        },
                      );
                    }, childCount: artists.length),
                  ),
                );
              },
            ),

            // 2: Songs List
            2 => songsAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CupertinoActivityIndicator()),
              ),
              error: (e, _) => SliverFillRemaining(
                child: EmptyState(
                  icon: CupertinoIcons.exclamationmark_triangle,
                  title: 'Error loading songs',
                  subtitle: e.toString(),
                ),
              ),
              data: (songs) {
                if (songs.isEmpty) {
                  return const SliverFillRemaining(
                    child: EmptyState(
                      icon: CupertinoIcons.music_note,
                      title: 'No Songs Found',
                      subtitle:
                          'Tracks synced from Google Drive will appear here.',
                    ),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final track = songs[index];
                    final isPlaying = currentTrackId == track.id;
                    return SongRow(
                      track: track,
                      isPlaying: isPlaying,
                      onTap: () => ref
                          .read(playbackRepositoryProvider)
                          .playTrack(track, queue: songs, queueIndex: index),
                      onMore: () => showTrackActionSheet(
                        context: context,
                        track: track,
                        ref: ref,
                      ),
                    );
                  }, childCount: songs.length),
                );
              },
            ),

            // 3: Playlists List
            3 => playlistsAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CupertinoActivityIndicator()),
              ),
              error: (e, _) => SliverFillRemaining(
                child: EmptyState(
                  icon: CupertinoIcons.exclamationmark_triangle,
                  title: 'Error loading playlists',
                  subtitle: e.toString(),
                ),
              ),
              data: (playlists) {
                if (playlists.isEmpty) {
                  return SliverFillRemaining(
                    child: EmptyState(
                      icon: CupertinoIcons.music_note_list,
                      title: 'No Playlists Yet',
                      subtitle:
                          'Create a playlist to organize your favorite songs.',
                      actionLabel: 'Create Playlist',
                      onAction: _showNewPlaylistDialog,
                    ),
                  );
                }

                final screenWidth = MediaQuery.of(context).size.width;
                final crossAxisCount = screenWidth > 600 ? 4 : 2;
                final itemWidth =
                    (screenWidth -
                        (AppSpacing.md * 2) -
                        ((crossAxisCount - 1) * AppSpacing.md)) /
                    crossAxisCount;

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: AppSpacing.md,
                      mainAxisSpacing: 24.0,
                      childAspectRatio: itemWidth / (itemWidth + 60),
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final pl = playlists[index];
                      return PlaylistCard(
                        playlist: pl,
                        onTap: () {
                          Navigator.of(context).push(
                            CupertinoPageRoute(
                              builder: (_) =>
                                  PlaylistDetailPage(playlistId: pl.id),
                            ),
                          );
                        },
                      );
                    }, childCount: playlists.length),
                  ),
                );
              },
            ),
            _ => const SliverToBoxAdapter(child: SizedBox.shrink()),
          },

          // Bottom padding for mini-player
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}
