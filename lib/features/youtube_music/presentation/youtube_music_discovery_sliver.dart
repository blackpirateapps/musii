import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../library/domain/entities/music_entities.dart';
import '../../library/presentation/widgets/empty_state.dart';
import '../../library/presentation/widgets/section_header.dart';
import '../domain/youtube_music_collection.dart';
import 'youtube_music_catalog_widgets.dart';

class YouTubeMusicDiscoverySliver extends ConsumerStatefulWidget {
  const YouTubeMusicDiscoverySliver({super.key, this.browse = false});

  final bool browse;

  @override
  ConsumerState<YouTubeMusicDiscoverySliver> createState() =>
      _YouTubeMusicDiscoverySliverState();
}

class _YouTubeMusicDiscoverySliverState
    extends ConsumerState<YouTubeMusicDiscoverySliver> {
  Timer? _debounce;
  String _query = '';
  List<Track> _results = const [];
  List<YouTubeMusicCollection> _collections = const [];
  YouTubeMusicCategory _category = YouTubeMusicCategory.songs;
  String? _nextPage;
  String? _error;
  bool _loading = false;
  int _searchGeneration = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _searchChanged(String value) {
    final query = value.trim();
    if (_query != query) _resetSearch(query, _category);
  }

  void _resetSearch(String query, YouTubeMusicCategory category) {
    _debounce?.cancel();
    _searchGeneration++;
    setState(() {
      _query = query;
      _category = category;
      _results = const [];
      _collections = const [];
      _nextPage = null;
      _error = null;
      _loading = query.isNotEmpty;
    });
    if (query.isNotEmpty) {
      _debounce = Timer(const Duration(milliseconds: 280), _requestPage);
    }
  }

  Future<void> _requestPage({String? nextPage}) async {
    final generation = ++_searchGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(youtubeMusicRepositoryProvider);
      if (_category == YouTubeMusicCategory.songs) {
        final page = await repository.searchSongs(_query, nextPage: nextPage);
        if (!mounted || generation != _searchGeneration) return;
        final seen = _results.map((song) => song.id).toSet();
        _results = [
          ..._results,
          ...page.tracks.where((song) => seen.add(song.id)),
        ];
        _nextPage = page.nextPage == nextPage ? null : page.nextPage;
      } else {
        final page = await repository.searchCollections(
          _query,
          _category,
          nextPage: nextPage,
        );
        if (!mounted || generation != _searchGeneration) return;
        final seen = _collections.map((item) => item.browseId).toSet();
        _collections = [
          ..._collections,
          ...page.collections.where((item) => seen.add(item.browseId)),
        ];
        _nextPage = page.nextPage == nextPage ? null : page.nextPage;
      }
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _error = youtubeMusicErrorMessage(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final showHome = widget.browse && _query.isEmpty;
    return SliverMainAxisGroup(
      slivers: [
        if (showHome)
          CupertinoSliverRefreshControl(
            onRefresh: () async {
              ref.invalidate(youtubeMusicHomeProvider);
              await ref
                  .read(youtubeMusicHomeProvider.future)
                  .then<void>((_) {}, onError: (Object _) {});
            },
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: CupertinoSearchTextField(
              placeholder: 'Search YouTube Music',
              onChanged: _searchChanged,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<YouTubeMusicCategory>(
                groupValue: _category,
                children: {
                  for (final category in YouTubeMusicCategory.values)
                    category: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(category.label),
                    ),
                },
                onValueChanged: (category) {
                  if (category != null && category != _category) {
                    _resetSearch(_query, category);
                  }
                },
              ),
            ),
          ),
        ),
        if (showHome) ..._home() else if (_query.isNotEmpty) ..._search(),
        const SliverToBoxAdapter(child: SizedBox(height: 110)),
      ],
    );
  }

  List<Widget> _home() {
    return ref
        .watch(youtubeMusicHomeProvider)
        .when(
          loading: () => [_progress()],
          error: (error, _) => [
            SliverToBoxAdapter(
              child: EmptyState(
                icon: CupertinoIcons.music_note_2,
                title: 'Could not load YouTube Music',
                subtitle: youtubeMusicErrorMessage(error),
                actionLabel: 'Retry',
                onAction: () => ref.invalidate(youtubeMusicHomeProvider),
              ),
            ),
          ],
          data: (sections) {
            final songs = _category == YouTubeMusicCategory.songs;
            final visible = sections.where(
              (section) => songs
                  ? section.tracks.isNotEmpty
                  : section.collections.any(
                      (item) => item.category == _category,
                    ),
            );
            return [
              if (visible.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: CupertinoIcons.music_note_2,
                    title: 'No recommendations available',
                    subtitle: 'Try searching YouTube Music.',
                  ),
                ),
              for (final section in visible) ...[
                if (section.title.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SectionHeader(title: section.title),
                  ),
                if (songs)
                  YouTubeMusicTrackSliver(tracks: section.tracks)
                else
                  YouTubeMusicCollectionSliver(
                    collections: section.collections
                        .where((item) => item.category == _category)
                        .toList(),
                  ),
              ],
            ];
          },
        );
  }

  List<Widget> _search() {
    final error = _error;
    final songs = _category == YouTubeMusicCategory.songs;
    return [
      if (songs)
        YouTubeMusicTrackSliver(tracks: _results)
      else
        YouTubeMusicCollectionSliver(collections: _collections),
      if (_loading)
        _progress()
      else if (error != null)
        SliverToBoxAdapter(
          child: EmptyState(
            icon: CupertinoIcons.exclamationmark_circle,
            title: 'Search unavailable',
            subtitle: error,
            actionLabel: 'Retry',
            onAction: () => _requestPage(nextPage: _nextPage),
          ),
        )
      else if (_nextPage != null)
        SliverToBoxAdapter(
          child: CupertinoButton(
            onPressed: () => _requestPage(nextPage: _nextPage),
            child: Text('Load More ${_category.label}'),
          ),
        )
      else if (songs ? _results.isEmpty : _collections.isEmpty)
        SliverToBoxAdapter(
          child: EmptyState(
            icon: CupertinoIcons.search,
            title: 'No ${_category.name} found',
            subtitle: 'Try a different search.',
          ),
        ),
    ];
  }

  Widget _progress() => const SliverToBoxAdapter(
    child: Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: Center(child: CupertinoActivityIndicator()),
    ),
  );
}
