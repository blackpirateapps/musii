import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../playlists/presentation/pages/playlist_detail_page.dart';
import '../widgets/album_artwork.dart';
import '../widgets/album_card.dart';
import '../widgets/artist_row.dart';
import '../widgets/empty_state.dart';
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

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final albumsAsync = ref.watch(allAlbumsProvider);
    final artistsAsync = ref.watch(allArtistsProvider);
    final songsAsync = ref.watch(allTracksProvider(null));
    final playlistsAsync = ref.watch(playlistsProvider);
    final playerState = ref.watch(playerStateProvider).value;

    return CupertinoPageScaffold(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        cacheExtent: 600.0,
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Library'),
            border: null,
            trailing: _selectedCategory == 3
                ? CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 0,
                    onPressed: _showNewPlaylistDialog,
                    child: const Icon(
                      CupertinoIcons.add,
                      color: CupertinoColors.systemPink,
                    ),
                  )
                : null,
          ),

          // Segmented Control Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<int>(
                  groupValue: _selectedCategory,
                  children: const {
                    0: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Albums'),
                    ),
                    1: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Artists'),
                    ),
                    2: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Songs'),
                    ),
                    3: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Playlists'),
                    ),
                  },
                  onValueChanged: (val) {
                    if (val != null) setState(() => _selectedCategory = val);
                  },
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
                final crossAxisCount = screenWidth > 600 ? 4 : 3;
                final itemWidth =
                    (screenWidth -
                        (AppSpacing.md * 2) -
                        ((crossAxisCount - 1) * AppSpacing.sm)) /
                    crossAxisCount;

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: AppSpacing.sm,
                      mainAxisSpacing: AppSpacing.md,
                      childAspectRatio: itemWidth / (itemWidth + 50),
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

                return SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final artist = artists[index];
                    return ArtistRow(
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
                    final isPlaying = playerState?.currentTrack?.id == track.id;
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

                return SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final pl = playlists[index];
                    return CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 0,
                      onPressed: () {
                        Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder: (_) =>
                                PlaylistDetailPage(playlistId: pl.id),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            AlbumArtwork(
                              artworkPath: pl.artworkPath,
                              title: pl.name,
                              size: 52,
                              borderRadius: AppRadii.card,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    pl.name,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? CupertinoColors.white
                                          : CupertinoColors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${pl.trackCount} ${pl.trackCount == 1 ? 'song' : 'songs'}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark
                                          ? CupertinoColors.systemGrey
                                          : CupertinoColors.secondaryLabel,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              CupertinoIcons.chevron_forward,
                              size: 18,
                              color: isDark
                                  ? CupertinoColors.systemGrey2
                                  : CupertinoColors.systemGrey3,
                            ),
                          ],
                        ),
                      ),
                    );
                  }, childCount: playlists.length),
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
