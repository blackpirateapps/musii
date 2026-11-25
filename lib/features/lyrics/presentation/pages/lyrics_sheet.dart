import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../library/domain/entities/music_entities.dart';
import '../../../library/presentation/widgets/artwork_backdrop.dart';
import '../../domain/entities/lyric_model.dart';
import '../widgets/lyric_line_widget.dart';

void showLyricsSheet(
  BuildContext context,
  Track track, {
  bool followPlayback = false,
}) {
  showCupertinoModalPopup<void>(
    context: context,
    builder: (context) => Consumer(
      builder: (context, ref, child) {
        final displayedTrack = followPlayback
            ? ref.watch(
                    playerStateProvider.select((s) => s.value?.currentTrack),
                  ) ??
                  track
            : track;
        return LyricsSheet(
          key: ValueKey(displayedTrack.id),
          track: displayedTrack,
        );
      },
    ),
  );
}

class LyricsSheet extends ConsumerStatefulWidget {
  final Track track;

  const LyricsSheet({super.key, required this.track});

  @override
  ConsumerState<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends ConsumerState<LyricsSheet> {
  static const _followDuration = Duration(milliseconds: 300);
  final ScrollController _scrollController = ScrollController();
  final _dragDistance = ValueNotifier(0.0);
  final GlobalKey _viewportKey = GlobalKey();
  final Map<int, GlobalKey> _lineKeys = {};

  bool _userScrolledManually = false;
  int _activeIndex = -1;
  int _anchorIndex = 0;
  List<LyricLine>? _positionedLines;
  bool _alignmentScheduled = false;
  bool _animateAlignment = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _dragDistance.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LyricsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _activeIndex = -1;
      _positionedLines = null;
      _userScrolledManually = false;
      _lineKeys.clear();
      _anchorIndex = 0;
    }
  }

  GlobalKey _getKeyForIndex(int index) {
    return _lineKeys.putIfAbsent(index, () => GlobalKey());
  }

  void _scheduleAlignment({bool animate = true}) {
    _animateAlignment = animate;
    if (_alignmentScheduled) return;
    _alignmentScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _alignmentScheduled = false;
      if (mounted) _alignActiveLine(animate: _animateAlignment);
    });
  }

  void _alignActiveLine({required bool animate}) {
    final index = _activeIndex;
    if (_userScrolledManually || !_scrollController.hasClients || index < 0) {
      return;
    }

    final row = _lineKeys[index]?.currentContext?.findRenderObject();
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (row is! RenderBox || !row.hasSize) {
      if (index == _anchorIndex) return;
      // Anchor the viewport on the requested row so its height is laid out
      // even when preceding rows have variable height.
      _scrollController.jumpTo(0);
      setState(() {
        _anchorIndex = index;
        _lineKeys.clear();
      });
      _scheduleAlignment(animate: false);
      return;
    }
    if (viewport is! RenderBox || !viewport.hasSize) return;

    final position = _scrollController.position;
    final rowTop = row.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final target =
        (position.pixels +
                rowTop +
                row.size.height / 2 -
                viewport.size.height * 0.45)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((position.pixels - target).abs() < 0.5) return;
    if (animate && !MediaQuery.disableAnimationsOf(context)) {
      unawaited(
        _scrollController.animateTo(
          target,
          duration: _followDuration,
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  void _seekToLine(int index, LyricLine line) {
    if (ref.read(playerStateProvider).value?.currentTrack?.id !=
        widget.track.id) {
      return;
    }
    unawaited(
      ref
          .read(playbackRepositoryProvider)
          .seek(Duration(milliseconds: line.timestampMs)),
    );
    setState(() {
      _userScrolledManually = false;
      _activeIndex = index;
    });
    _scheduleAlignment();
  }

  Widget _buildTimedLyrics(
    List<LyricLine> lines, {
    required bool isDark,
    required bool isCurrentTrack,
  }) {
    final anchor = _anchorIndex.clamp(0, lines.length - 1);
    final centerKey = ValueKey(('lyrics-after', anchor));
    const horizontalPadding = EdgeInsets.symmetric(horizontal: AppSpacing.xl);

    Widget row(int index) {
      final line = lines[index];
      return LyricLineWidget(
        key: _getKeyForIndex(index),
        line: line,
        isActive: index == _activeIndex,
        isDark: isDark,
        nextLineTimestampMs: index + 1 < lines.length
            ? lines[index + 1].timestampMs
            : null,
        onTap: isCurrentTrack ? () => _seekToLine(index, line) : null,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) =>
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is UserScrollNotification &&
                  notification.direction != ScrollDirection.idle &&
                  !_userScrolledManually) {
                setState(() => _userScrolledManually = true);
              }
              return false;
            },
            child: CustomScrollView(
              key: _viewportKey,
              controller: _scrollController,
              center: centerKey,
              anchor: 0.45,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              semanticChildCount: lines.length,
              slivers: [
                SliverPadding(
                  key: ValueKey(('lyrics-before', anchor)),
                  padding: horizontalPadding,
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => row(anchor - 1 - index),
                      childCount: anchor,
                      semanticIndexCallback: (widget, index) =>
                          anchor - 1 - index,
                    ),
                  ),
                ),
                SliverPadding(
                  key: centerKey,
                  padding: horizontalPadding,
                  sliver: SliverList.builder(
                    itemCount: lines.length - anchor,
                    semanticIndexOffset: anchor,
                    itemBuilder: (context, index) => row(anchor + index),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(height: constraints.maxHeight * 0.55),
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;

    final lyricsAsync = ref.watch(trackLyricsProvider(track.id));
    final lyrics = lyricsAsync.value;

    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final isCurrentTrack = ref.watch(
      playerStateProvider.select((s) => s.value?.currentTrack?.id == track.id),
    );

    if (!isCurrentTrack) {
      _activeIndex = -1;
      _positionedLines = null;
    }

    ref.listen<Duration>(playbackPositionProvider, (prev, next) {
      if (ref.read(playerStateProvider).value?.currentTrack?.id != track.id ||
          lyrics?.isSynchronized != true) {
        return;
      }
      final newIndex = lyrics!.findActiveIndex(next);
      final previousIndex = _activeIndex;
      if (newIndex != previousIndex) {
        setState(() => _activeIndex = newIndex);
        if (!_userScrolledManually && newIndex >= 0) {
          final isAdjacentPlayback =
              previousIndex >= 0 &&
              newIndex == previousIndex + 1 &&
              (lyrics.lines[newIndex].timestampMs -
                      lyrics.lines[previousIndex].timestampMs) >=
                  _followDuration.inMilliseconds;
          _scheduleAlignment(animate: isAdjacentPlayback);
        }
      }
    });

    if (isCurrentTrack &&
        lyrics?.isSynchronized == true &&
        !identical(_positionedLines, lyrics!.lines)) {
      _positionedLines = lyrics.lines;
      _activeIndex = lyrics.findActiveIndex(ref.read(playbackPositionProvider));
      if (!_userScrolledManually && _activeIndex >= 0) {
        _scheduleAlignment(animate: false);
      }
    }

    final sheet = Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141416) : const Color(0xFFF7F7F8),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadii.sheet),
              ),
              child: ArtworkBackdrop(
                artworkPath: track.artworkPath,
                overlay: BoxDecoration(
                  color: isDark
                      ? CupertinoColors.black.withOpacity(0.75)
                      : CupertinoColors.white.withOpacity(0.85),
                ),
              ),
            ),
          ),

          // 2. Main Content
          SafeArea(
            top: false,
            child: Column(
              children: [
                GestureDetector(
                  key: const ValueKey('lyrics-drag-handle'),
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {
                    _dragDistance.value =
                        (_dragDistance.value + details.delta.dy).clamp(
                          0,
                          double.infinity,
                        );
                  },
                  onVerticalDragCancel: () => _dragDistance.value = 0,
                  onVerticalDragEnd: (details) {
                    if ((_dragDistance.value >= 96 ||
                            (details.primaryVelocity ?? 0) > 350) &&
                        ModalRoute.of(context)?.isCurrent == true &&
                        Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      _dragDistance.value = 0;
                    }
                  },
                  child: SizedBox(
                    width: double.infinity,
                    height: 36,
                    child: Center(
                      child: Container(
                        width: 38,
                        height: 5,
                        decoration: BoxDecoration(
                          color: CupertinoColors.systemGrey.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),
                  ),
                ),

                // Top Header Row
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Lyrics',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? CupertinoColors.white
                                    : CupertinoColors.black,
                              ),
                            ),
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: isDark
                                    ? CupertinoColors.systemGrey
                                    : CupertinoColors.secondaryLabel,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark
                                ? CupertinoColors.systemGrey.withOpacity(0.25)
                                : CupertinoColors.systemGrey5,
                          ),
                          child: Icon(
                            CupertinoIcons.xmark,
                            semanticLabel: 'Close lyrics',
                            size: 16,
                            color: isDark
                                ? CupertinoColors.white
                                : CupertinoColors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Body: Sync Lyrics / Plain Lyrics / Empty State
                Expanded(
                  child: lyricsAsync.when(
                    loading: () => const Center(
                      child: CupertinoActivityIndicator(radius: 14),
                    ),
                    error: (err, _) => Center(
                      child: Text(
                        'Failed to load lyrics',
                        style: TextStyle(
                          color: isDark
                              ? CupertinoColors.systemGrey
                              : CupertinoColors.secondaryLabel,
                        ),
                      ),
                    ),
                    data: (data) {
                      if (data == null || !data.hasLyrics) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.quote_bubble,
                                size: 52,
                                color: isDark
                                    ? CupertinoColors.systemGrey
                                    : CupertinoColors.systemGrey2,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                "Lyrics aren't available for this song.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? CupertinoColors.white
                                      : CupertinoColors.black,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      if (!data.isSynchronized) {
                        // Plain Lyrics Display
                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xl,
                            vertical: AppSpacing.lg,
                          ),
                          itemCount: data.lines.length,
                          itemBuilder: (ctx, i) {
                            final line = data.lines[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8.0,
                              ),
                              child: Text(
                                line.text,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  height: 1.6,
                                  color: isDark
                                      ? CupertinoColors.white
                                      : CupertinoColors.black,
                                ),
                              ),
                            );
                          },
                        );
                      }

                      return _buildTimedLyrics(
                        data.lines,
                        isDark: isDark,
                        isCurrentTrack: isCurrentTrack,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // 3. Floating "Return to current line" button when manually scrolled
          if (isCurrentTrack &&
              _userScrolledManually &&
              lyrics?.isSynchronized == true)
            Positioned(
              bottom: 24,
              right: 24,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                builder: (context, val, child) {
                  return Transform.translate(
                    offset: Offset(0, 20 * (1 - val)),
                    child: Opacity(opacity: val, child: child),
                  );
                },
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    setState(() {
                      _userScrolledManually = false;
                    });
                    if (_activeIndex >= 0) {
                      _scheduleAlignment();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? CupertinoColors.systemGrey.withOpacity(0.85)
                          : CupertinoColors.black.withOpacity(0.80),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: CupertinoColors.black.withOpacity(0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.arrow_down_to_line,
                          size: 16,
                          color: CupertinoColors.white,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Current line',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: CupertinoColors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return ValueListenableBuilder<double>(
      valueListenable: _dragDistance,
      child: sheet,
      builder: (context, offset, child) =>
          Transform.translate(offset: Offset(0, offset), child: child),
    );
  }
}
