import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../library/domain/entities/music_entities.dart';
import '../../domain/entities/lyric_model.dart';
import '../widgets/lyric_line_widget.dart';

void showLyricsSheet(BuildContext context, Track track) {
  showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => LyricsSheet(track: track),
  );
}

class LyricsSheet extends ConsumerStatefulWidget {
  final Track track;

  const LyricsSheet({super.key, required this.track});

  @override
  ConsumerState<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends ConsumerState<LyricsSheet> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _viewportKey = GlobalKey();
  final Map<int, GlobalKey> _lineKeys = {};

  bool _userScrolledManually = false;
  int _activeIndex = -1;
  bool _hasPerformedInitialScroll = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LyricsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _activeIndex = -1;
      _hasPerformedInitialScroll = false;
      _userScrolledManually = false;
      _lineKeys.clear();
    }
  }

  GlobalKey _getKeyForIndex(int index) {
    return _lineKeys.putIfAbsent(index, () => GlobalKey());
  }

  void _scrollToActiveLine(int index, {bool animate = true}) {
    if (_userScrolledManually || !_scrollController.hasClients || index < 0) {
      return;
    }

    final itemKey = _lineKeys[index];
    final itemContext = itemKey?.currentContext;
    final viewportContext = _viewportKey.currentContext;

    if (itemContext != null && viewportContext != null) {
      final itemBox = itemContext.findRenderObject() as RenderBox?;
      final viewportBox = viewportContext.findRenderObject() as RenderBox?;

      if (itemBox != null &&
          viewportBox != null &&
          itemBox.hasSize &&
          viewportBox.hasSize) {
        // Calculate item's relative position inside the lyrics viewport
        final itemTopInViewport = itemBox
            .localToGlobal(Offset.zero, ancestor: viewportBox)
            .dy;
        final itemHeight = itemBox.size.height;
        final itemCenterInViewport = itemTopInViewport + (itemHeight / 2);

        // Focal region at ~45% of the visible lyrics viewport height
        final focalY = viewportBox.size.height * 0.45;
        final delta = itemCenterInViewport - focalY;

        final currentOffset = _scrollController.offset;
        final targetOffset = (currentOffset + delta).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );

        if (animate) {
          _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        } else {
          _scrollController.jumpTo(targetOffset);
        }
        return;
      }
    }

    // Fallback if item is not yet laid out in viewport
    if (_scrollController.hasClients &&
        _scrollController.position.hasContentDimensions) {
      const estimatedItemHeight = 48.0;
      final viewportHeight = viewportContext != null
          ? (viewportContext.findRenderObject() as RenderBox?)?.size.height ??
                400.0
          : 400.0;
      final topPadding = viewportHeight * 0.40;
      final focalY = viewportHeight * 0.45;
      final estimatedOffset =
          (topPadding +
                  (index * estimatedItemHeight) -
                  focalY +
                  (estimatedItemHeight / 2))
              .clamp(0.0, _scrollController.position.maxScrollExtent);

      if (animate) {
        _scrollController.animateTo(
          estimatedOffset,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(estimatedOffset);
      }

      // Fine-tune precise pixel alignment once rendered
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_userScrolledManually) {
          _scrollToActiveLine(index, animate: false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;

    final lyricsAsync = ref.watch(trackLyricsProvider(track.id));
    final lyrics = lyricsAsync.value;

    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    // Listen to playback position changes and update active line
    ref.listen<Duration>(playbackPositionProvider, (prev, next) {
      final currentPos = next;
      final currentLines = lyrics?.lines ?? const [];
      if (lyrics?.isSynchronized != true || currentLines.isEmpty) return;

      final newActiveIndex = TrackLyrics.calculateActiveIndex(
        currentLines,
        currentPos,
      );

      if (newActiveIndex != _activeIndex) {
        setState(() {
          _activeIndex = newActiveIndex;
        });
        if (!_userScrolledManually && newActiveIndex >= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_userScrolledManually) {
              _scrollToActiveLine(newActiveIndex, animate: true);
            }
          });
        }
      }
    });

    // Initial positioning when lyrics data first becomes available
    if (lyrics != null && lyrics.isSynchronized && lyrics.lines.isNotEmpty) {
      final currentPos = ref.read(playbackPositionProvider);
      final currentActive = TrackLyrics.calculateActiveIndex(
        lyrics.lines,
        currentPos,
      );
      if (_activeIndex == -1 && currentActive != -1) {
        _activeIndex = currentActive;
      }

      if (!_hasPerformedInitialScroll) {
        _hasPerformedInitialScroll = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_userScrolledManually && _activeIndex >= 0) {
            _scrollToActiveLine(_activeIndex, animate: false);
          }
        });
      }
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141416) : const Color(0xFFF7F7F8),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
      ),
      child: Stack(
        children: [
          // 1. Blurred Backdrop from artwork if available
          if (track.artworkPath != null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadii.sheet),
                ),
                child: Image.file(
                  File(track.artworkPath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),

          Positioned.fill(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadii.sheet),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: Container(
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
                // Drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 38,
                    height: 5,
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemGrey.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(2.5),
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
                      Column(
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

                      // Synchronized Lyrics Display with 45% focal alignment
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final viewportHeight = constraints.maxHeight;
                          final topPadding = viewportHeight * 0.40;
                          final bottomPadding = viewportHeight * 0.55;

                          return NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if (notification is UserScrollNotification &&
                                  notification.direction !=
                                      ScrollDirection.idle) {
                                if (!_userScrolledManually) {
                                  setState(() {
                                    _userScrolledManually = true;
                                  });
                                }
                              }
                              return false;
                            },
                            child: ListView.builder(
                              key: _viewportKey,
                              controller: _scrollController,
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              padding: EdgeInsets.only(
                                left: AppSpacing.xl,
                                right: AppSpacing.xl,
                                top: topPadding,
                                bottom: bottomPadding,
                              ),
                              itemCount: data.lines.length,
                              itemBuilder: (ctx, i) {
                                final line = data.lines[i];
                                final isActive = (i == _activeIndex);
                                final nextLineTimestampMs =
                                    (i + 1 < data.lines.length)
                                    ? data.lines[i + 1].timestampMs
                                    : null;

                                return LyricLineWidget(
                                  key: _getKeyForIndex(i),
                                  line: line,
                                  isActive: isActive,
                                  isDark: isDark,
                                  nextLineTimestampMs: nextLineTimestampMs,
                                  onTap: () {
                                    ref
                                        .read(playbackRepositoryProvider)
                                        .seek(
                                          Duration(
                                            milliseconds: line.timestampMs,
                                          ),
                                        );
                                    setState(() {
                                      _userScrolledManually = false;
                                      _activeIndex = i;
                                    });
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (mounted) {
                                            _scrollToActiveLine(
                                              i,
                                              animate: true,
                                            );
                                          }
                                        });
                                  },
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // 3. Floating "Return to current line" button when manually scrolled
          if (_userScrolledManually && lyrics?.isSynchronized == true)
            Positioned(
              bottom: 24,
              right: 24,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 250),
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
                      _scrollToActiveLine(_activeIndex, animate: true);
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
  }
}
