import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/error/failures.dart';
import '../../library/domain/entities/music_entities.dart';
import '../../library/presentation/widgets/empty_state.dart';
import '../../library/presentation/widgets/section_header.dart';
import '../../library/presentation/widgets/song_row.dart';
import '../../library/presentation/widgets/track_overflow_sheet.dart';

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
  String? _nextPage;
  String? _error;
  bool _loading = false;
  int _searchGeneration = 0;
  int _playGeneration = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _searchChanged(String value) {
    final query = value.trim();
    if (_query == query) return;
    _debounce?.cancel();
    _searchGeneration++;
    setState(() {
      _query = query;
      _results = const [];
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
      final page = await ref
          .read(youtubeMusicRepositoryProvider)
          .searchSongs(_query, nextPage: nextPage);
      if (!mounted || generation != _searchGeneration) return;
      final seen = _results.map((song) => song.id).toSet();
      setState(() {
        _results = [
          ..._results,
          ...page.tracks.where((song) => seen.add(song.id)),
        ];
        _nextPage = page.nextPage == nextPage ? null : page.nextPage;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _error = _message(error);
        _loading = false;
      });
    }
  }

  Future<void> _play(List<Track> tracks, int index) async {
    final generation = ++_playGeneration;
    try {
      await ref.read(youtubeMusicRepositoryProvider).saveTracks(tracks);
      if (!mounted || generation != _playGeneration) return;
      await ref
          .read(playbackRepositoryProvider)
          .playTrack(tracks[index], queue: tracks, queueIndex: index);
    } catch (error) {
      if (mounted && generation == _playGeneration) _showError(error);
    }
  }

  Future<void> _options(Track track) async {
    try {
      await ref.read(youtubeMusicRepositoryProvider).saveTracks([track]);
      if (!mounted) return;
      await showTrackActionSheet(
        context: context,
        track: track,
        ref: ref,
        trackContext: TrackActionContext.search,
      );
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _showError(Object error) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        content: Text(_message(error)),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _message(Object error) => error is AppFailure
      ? error.message
      : 'Could not load YouTube Music. Try again.';

  @override
  Widget build(BuildContext context) {
    final currentId = ref.watch(
      playerStateProvider.select((state) => state.value?.currentTrack?.id),
    );
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
        if (showHome)
          ..._home(currentId)
        else if (_query.isNotEmpty)
          ..._search(currentId),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
      ],
    );
  }

  List<Widget> _home(String? currentId) {
    return ref
        .watch(youtubeMusicHomeProvider)
        .when(
          loading: () => [_progress()],
          error: (error, _) => [
            SliverToBoxAdapter(
              child: EmptyState(
                icon: CupertinoIcons.music_note_2,
                title: 'Could not load YouTube Music',
                subtitle: _message(error),
                actionLabel: 'Retry',
                onAction: () => ref.invalidate(youtubeMusicHomeProvider),
              ),
            ),
          ],
          data: (sections) => [
            if (sections.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  icon: CupertinoIcons.music_note_2,
                  title: 'No recommendations available',
                  subtitle: 'Search YouTube Music to find a song.',
                ),
              ),
            for (final section in sections) ...[
              SliverToBoxAdapter(child: SectionHeader(title: section.title)),
              _songList(section.tracks, currentId),
            ],
          ],
        );
  }

  List<Widget> _search(String? currentId) {
    final error = _error;
    return [
      _songList(_results, currentId),
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
            child: const Text('Load More Songs'),
          ),
        )
      else if (_results.isEmpty)
        const SliverToBoxAdapter(
          child: EmptyState(
            icon: CupertinoIcons.search,
            title: 'No songs found',
            subtitle: 'Try another song title or artist.',
          ),
        ),
    ];
  }

  Widget _songList(List<Track> tracks, String? currentId) => SliverList.builder(
    itemCount: tracks.length,
    itemBuilder: (context, index) {
      final track = tracks[index];
      return SongRow(
        track: track,
        isPlaying: track.id == currentId,
        onTap: () => _play(tracks, index),
        onMore: () => _options(track),
      );
    },
  );

  Widget _progress() => const SliverToBoxAdapter(
    child: Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: Center(child: CupertinoActivityIndicator()),
    ),
  );
}
