import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../library/domain/entities/music_entities.dart';
import '../../domain/entities/lyric_model.dart';

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
  bool _userScrolledManually = false;
  int _lastActiveIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveLine(int index) {
    if (_userScrolledManually || !_scrollController.hasClients) return;
    const itemHeight = 64.0;
    final targetOffset = (index * itemHeight) - 180;
    final clampedOffset = targetOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  int _findActiveIndex(List<LyricLine> lines, Duration currentPosition) {
    if (lines.isEmpty) return -1;
    final curMs = currentPosition.inMilliseconds;

    int activeIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].timestampMs <= curMs) {
        activeIndex = i;
      } else {
        break;
      }
    }
    return activeIndex;
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final playerSnapshot = ref.watch(playerStateProvider).value;
    final position = playerSnapshot?.position ?? Duration.zero;

    final lyricsAsync = ref.watch(trackLyricsProvider(track.id));
    final lyrics = lyricsAsync.value;

    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

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
          if (track.artworkPath != null &&
              File(track.artworkPath!).existsSync())
            Positioned.fill(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadii.sheet),
                ),
                child: Image.file(File(track.artworkPath!), fit: BoxFit.cover),
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

                      // Synchronized Lyrics Display
                      final activeIndex = _findActiveIndex(
                        data.lines,
                        position,
                      );

                      if (activeIndex != _lastActiveIndex) {
                        _lastActiveIndex = activeIndex;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (activeIndex >= 0) {
                            _scrollToActiveLine(activeIndex);
                          }
                        });
                      }

                      return NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is UserScrollNotification) {
                            setState(() {
                              _userScrolledManually = true;
                            });
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xl,
                            vertical: 120,
                          ),
                          itemCount: data.lines.length,
                          itemBuilder: (ctx, i) {
                            final line = data.lines[i];
                            final isActive = (i == activeIndex);

                            return GestureDetector(
                              onTap: () {
                                ref
                                    .read(playbackRepositoryProvider)
                                    .seek(
                                      Duration(milliseconds: line.timestampMs),
                                    );
                                setState(() {
                                  _userScrolledManually = false;
                                });
                                _scrollToActiveLine(i);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14.0,
                                ),
                                child: Text(
                                  line.text.isNotEmpty ? line.text : '♪',
                                  style: TextStyle(
                                    fontSize: isActive ? 24 : 19,
                                    fontWeight: isActive
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    letterSpacing: -0.3,
                                    color: isActive
                                        ? (isDark
                                              ? CupertinoColors.white
                                              : CupertinoColors.black)
                                        : (isDark
                                              ? CupertinoColors.white
                                                    .withOpacity(0.38)
                                              : CupertinoColors.black
                                                    .withOpacity(0.38)),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
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
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  setState(() {
                    _userScrolledManually = false;
                  });
                  if (_lastActiveIndex >= 0) {
                    _scrollToActiveLine(_lastActiveIndex);
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
        ],
      ),
    );
  }
}
