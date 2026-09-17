import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/music_entities.dart';
import 'album_artwork.dart';

class SongRow extends StatelessWidget {
  final Track track;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final VoidCallback? onLongPress;
  final int? trackNumber;

  const SongRow({
    super.key,
    required this.track,
    this.isPlaying = false,
    required this.onTap,
    this.onMore,
    this.onLongPress,
    this.trackNumber,
  });

  String _formatDuration(int ms) {
    if (ms <= 0) return '--:--';
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        if (onLongPress != null) {
          onLongPress!();
        } else if (onMore != null) {
          onMore!();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 12.0,
        ),
        child: Row(
          children: [
            if (trackNumber != null)
              Container(
                width: 32,
                alignment: Alignment.centerLeft,
                child: Text(
                  '$trackNumber',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: isDark
                        ? CupertinoColors.white.withOpacity(0.5)
                        : CupertinoColors.black.withOpacity(0.5),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: AlbumArtwork(
                  artworkPath: track.artworkPath,
                  title: track.title,
                  artist: track.artistName,
                  size: 52,
                  borderRadius: 10.0,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (isPlaying)
                        const Padding(
                          padding: EdgeInsets.only(right: 6.0),
                          child: Icon(
                            CupertinoIcons.speaker_2_fill,
                            size: 14,
                            color: CupertinoColors.systemPink,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isPlaying
                                ? FontWeight.w600
                                : FontWeight.w500,
                            letterSpacing: -0.2,
                            color: isPlaying
                                ? CupertinoColors.systemPink
                                : (isDark
                                      ? CupertinoColors.white
                                      : CupertinoColors.black),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (track.isPinnedOffline || track.isCached)
                        Padding(
                          padding: const EdgeInsets.only(right: 4.0),
                          child: Icon(
                            CupertinoIcons.arrow_down_circle_fill,
                            size: 12,
                            color: isDark
                                ? CupertinoColors.white.withOpacity(0.4)
                                : CupertinoColors.black.withOpacity(0.4),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          '${track.artistName ?? 'Unknown Artist'} · ${track.albumName ?? 'Unknown Album'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: isDark
                                ? CupertinoColors.white.withOpacity(0.6)
                                : CupertinoColors.black.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _formatDuration(track.durationMs),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: isDark
                    ? CupertinoColors.white.withOpacity(0.4)
                    : CupertinoColors.black.withOpacity(0.4),
              ),
            ),
            if (onMore != null)
              CupertinoButton(
                padding: const EdgeInsets.only(left: 12.0),
                minSize: 0,
                onPressed: onMore,
                child: Icon(
                  CupertinoIcons.ellipsis,
                  size: 20,
                  color: isDark
                      ? CupertinoColors.white.withOpacity(0.4)
                      : CupertinoColors.black.withOpacity(0.4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
