import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../library/presentation/pages/album_detail_page.dart';
import '../../../library/presentation/pages/artist_detail_page.dart';
import '../../../library/presentation/widgets/album_artwork.dart';
import '../../../library/presentation/widgets/album_card.dart';
import '../../../library/presentation/widgets/artist_card.dart';
import '../../../library/presentation/widgets/empty_state.dart';
import '../../../library/presentation/widgets/section_header.dart';
import '../../../library/presentation/widgets/song_row.dart';
import '../../../library/presentation/widgets/track_overflow_sheet.dart';
import '../../../playlists/presentation/pages/playlist_detail_page.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      ref.read(searchQueryStateProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryStateProvider);
    final searchResultsAsync = ref.watch(searchResultsProvider);
    final currentTrackId = ref.watch(
      playerStateProvider.select((s) => s.value?.currentTrack?.id),
    );
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoPageScaffold(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        cacheExtent: 600.0,
        slivers: [
          const CupertinoSliverNavigationBar(
            largeTitle: Text('Search'),
            border: null,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: CupertinoSearchTextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                placeholder: 'Songs, Albums, Artists, Playlists',
              ),
            ),
          ),
          if (query.trim().isEmpty)
            const SliverFillRemaining(
              child: EmptyState(
                icon: CupertinoIcons.search,
                title: 'Search your Library',
                subtitle: 'Find songs, artists, albums, and playlists from your indexed music.',
              ),
            )
          else
            searchResultsAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CupertinoActivityIndicator()),
              ),
              error: (e, _) => SliverFillRemaining(
                child: EmptyState(
                  icon: CupertinoIcons.exclamationmark_triangle,
                  title: 'Search Error',
                  subtitle: e.toString(),
                ),
              ),
              data: (results) {
                if (results.isEmpty) {
                  return SliverFillRemaining(
                    child: EmptyState(
                      icon: CupertinoIcons.search,
                      title: 'No Results',
                      subtitle: 'No matches found for "$query".',
                    ),
                  );
                }

                return SliverList(
                  delegate: SliverChildListDelegate([
                    // 1. Songs Results
                    if (results.tracks.isNotEmpty) ...[
                      const SectionHeader(title: 'Songs'),
                      ...results.tracks.map(
                        (track) => SongRow(
                          track: track,
                          isPlaying: currentTrackId == track.id,
                          onTap: () => ref
                              .read(playbackRepositoryProvider)
                              .playTrack(track, queue: results.tracks),
                          onMore: () => showTrackActionSheet(
                            context: context,
                            track: track,
                            ref: ref,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // 2. Albums Results
                    if (results.albums.isNotEmpty) ...[
                      const SectionHeader(title: 'Albums'),
                      SizedBox(
                        height: 195,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: results.albums.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: AppSpacing.md),
                          itemBuilder: (context, index) {
                            final album = results.albums[index];
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

                    // 3. Artists Results
                    if (results.artists.isNotEmpty) ...[
                      const SectionHeader(title: 'Artists'),
                      SizedBox(
                        height: 200,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: results.artists.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: AppSpacing.md),
                          itemBuilder: (context, index) {
                            final artist = results.artists[index];
                            return SizedBox(
                              width: 120,
                              child: ArtistCard(
                                artist: artist,
                                onTap: () {
                                  Navigator.of(context).push(
                                    CupertinoPageRoute(
                                      builder: (_) =>
                                          ArtistDetailPage(artistId: artist.id),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // 4. Playlists Results
                    if (results.playlists.isNotEmpty) ...[
                      const SectionHeader(title: 'Playlists'),
                      ...results.playlists.map(
                        (pl) => CupertinoListTile(
                          leading: AlbumArtwork(
                            artworkPath: pl.artworkPath,
                            title: pl.name,
                            size: 40,
                            borderRadius: AppRadii.small,
                          ),
                          title: Text(
                            pl.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? CupertinoColors.white
                                  : CupertinoColors.black,
                            ),
                          ),
                          trailing: const Icon(
                            CupertinoIcons.chevron_forward,
                            size: 18,
                          ),
                          onTap: () {
                            Navigator.of(context).push(
                              CupertinoPageRoute(
                                builder: (_) =>
                                    PlaylistDetailPage(playlistId: pl.id),
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    const SizedBox(height: 100),
                  ]),
                );
              },
            ),
        ],
      ),
    );
  }
}
