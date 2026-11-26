import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/error/failures.dart';
import '../../library/domain/entities/music_entities.dart';
import '../../library/presentation/widgets/album_artwork.dart';
import '../../library/presentation/widgets/empty_state.dart';
import '../../library/presentation/widgets/section_header.dart';
import '../../library/presentation/widgets/song_row.dart';
import '../../library/presentation/widgets/track_overflow_sheet.dart';
import '../data/youtube_music_repository.dart';
import '../domain/youtube_music_collection.dart';

String youtubeMusicErrorMessage(Object error) => error is AppFailure
    ? error.message
    : 'Could not load YouTube Music. Try again.';

class YouTubeMusicTrackSliver extends ConsumerStatefulWidget {
  const YouTubeMusicTrackSliver({
    super.key,
    required this.tracks,
    this.showPlayButton = false,
  });

  final List<Track> tracks;
  final bool showPlayButton;

  @override
  ConsumerState<YouTubeMusicTrackSliver> createState() =>
      _YouTubeMusicTrackSliverState();
}

class _YouTubeMusicTrackSliverState
    extends ConsumerState<YouTubeMusicTrackSliver> {
  int _playGeneration = 0;

  Future<void> _play(int index) async {
    final tracks = widget.tracks;
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
        content: Text(youtubeMusicErrorMessage(error)),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentId = ref.watch(
      playerStateProvider.select((state) => state.value?.currentTrack?.id),
    );
    return SliverMainAxisGroup(
      slivers: [
        if (widget.showPlayButton && widget.tracks.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: CupertinoButton.filled(
                onPressed: () => _play(0),
                child: const Text('Play'),
              ),
            ),
          ),
        SliverList.builder(
          itemCount: widget.tracks.length,
          itemBuilder: (context, index) {
            final track = widget.tracks[index];
            return SongRow(
              track: track,
              isPlaying: track.id == currentId,
              onTap: () => _play(index),
              onMore: () => _options(track),
            );
          },
        ),
      ],
    );
  }
}

class YouTubeMusicCollectionSliver extends StatelessWidget {
  const YouTubeMusicCollectionSliver({super.key, required this.collections});

  final List<YouTubeMusicCollection> collections;

  @override
  Widget build(BuildContext context) {
    return SliverList.builder(
      itemCount: collections.length,
      itemBuilder: (context, index) {
        final collection = collections[index];
        final subtitle = collection.subtitle;
        return CupertinoListTile(
          leadingSize: 52,
          leading: AlbumArtwork(
            artworkUrl: collection.artworkUrl,
            title: collection.title,
            size: 52,
            borderRadius: collection.category == YouTubeMusicCategory.artists
                ? 26
                : 8,
          ),
          title: Text(collection.title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const CupertinoListTileChevron(),
          onTap: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (_) =>
                  _YouTubeMusicCollectionPage(collection: collection),
            ),
          ),
        );
      },
    );
  }
}

class _YouTubeMusicCollectionPage extends ConsumerStatefulWidget {
  const _YouTubeMusicCollectionPage({required this.collection});

  final YouTubeMusicCollection collection;

  @override
  ConsumerState<_YouTubeMusicCollectionPage> createState() =>
      _CollectionPageState();
}

class _CollectionPageState extends ConsumerState<_YouTubeMusicCollectionPage> {
  List<YouTubeMusicSection> _sections = const [];
  String? _nextPage;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final continuation = _nextPage;
    try {
      final page = await ref
          .read(youtubeMusicRepositoryProvider)
          .browseCollection(widget.collection.browseId, nextPage: continuation);
      if (!mounted) return;
      setState(() {
        _sections = [..._sections, ...page.sections];
        _nextPage = page.nextPage == continuation ? null : page.nextPage;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = youtubeMusicErrorMessage(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = widget.collection;
    final artist = collection.category == YouTubeMusicCategory.artists;
    final error = _error;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(collection.title, overflow: TextOverflow.ellipsis),
      ),
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            if (_sections.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    children: [
                      AlbumArtwork(
                        artworkUrl: collection.artworkUrl,
                        title: collection.title,
                        size: 164,
                        borderRadius: artist ? 82 : AppRadii.card,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        collection.title,
                        textAlign: TextAlign.center,
                        style: CupertinoTheme.of(context)
                            .textTheme
                            .navLargeTitleTextStyle,
                      ),
                      if (collection.subtitle case final subtitle?)
                        Text(subtitle, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            if (artist)
              for (final section in _sections) ...[
                if (section.title.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SectionHeader(title: section.title),
                  ),
                if (section.tracks.isNotEmpty)
                  YouTubeMusicTrackSliver(tracks: section.tracks),
                if (section.collections.isNotEmpty)
                  YouTubeMusicCollectionSliver(
                    collections: section.collections,
                  ),
              ]
            else
              YouTubeMusicTrackSliver(
                tracks: [for (final section in _sections) ...section.tracks],
                showPlayButton: true,
              ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: CupertinoActivityIndicator()),
                ),
              )
            else if (error != null)
              SliverToBoxAdapter(
                child: EmptyState(
                  icon: CupertinoIcons.exclamationmark_circle,
                  title: 'Could not load this collection',
                  subtitle: error,
                  actionLabel: 'Retry',
                  onAction: _load,
                ),
              )
            else if (_nextPage != null)
              SliverToBoxAdapter(
                child: CupertinoButton(
                  onPressed: _load,
                  child: const Text('Load More'),
                ),
              )
            else if (_sections.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  icon: CupertinoIcons.music_note_2,
                  title: 'No items available',
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }
}
