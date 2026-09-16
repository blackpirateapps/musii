import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/music_entities.dart';
import 'album_artwork.dart';
import 'track_overflow_sheet.dart';

class HomeArtworkCard extends ConsumerWidget {
  final Track? track;
  final Album? album;
  final String title;
  final String subtitle;
  final String? artworkPath;
  final VoidCallback onTap;
  final double width;
  final TrackActionContext trackContext;

  const HomeArtworkCard({
    super.key,
    this.track,
    this.album,
    required this.title,
    required this.subtitle,
    this.artworkPath,
    required this.onTap,
    this.width = 132.0,
    this.trackContext = TrackActionContext.library,
  });

  factory HomeArtworkCard.fromTrack({
    Key? key,
    required Track track,
    required VoidCallback onTap,
    double width = 132.0,
    TrackActionContext trackContext = TrackActionContext.library,
  }) {
    return HomeArtworkCard(
      key: key,
      track: track,
      title: track.title,
      subtitle: track.artistName ?? 'Unknown Artist',
      artworkPath: track.artworkPath,
      onTap: onTap,
      width: width,
      trackContext: trackContext,
    );
  }

  factory HomeArtworkCard.fromAlbum({
    Key? key,
    required Album album,
    required VoidCallback onTap,
    double width = 132.0,
  }) {
    return HomeArtworkCard(
      key: key,
      album: album,
      title: album.title,
      subtitle: album.artistName ?? 'Unknown Artist',
      artworkPath: album.artworkPath,
      onTap: onTap,
      width: width,
      trackContext: TrackActionContext.album,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () {
          if (track != null) {
            HapticFeedback.mediumImpact();
            showTrackActionSheet(
              context: context,
              track: track!,
              ref: ref,
              trackContext: trackContext,
            );
          }
        },
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Artwork with rounded corners
              ClipRRect(
                borderRadius: BorderRadius.circular(16.0),
                child: AlbumArtwork(
                  artworkPath: artworkPath,
                  title: title,
                  artist: subtitle,
                  size: width,
                  borderRadius: 16.0,
                ),
              ),
              const SizedBox(height: 6.0),
              // Track / Album Title
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.0,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ),
              const SizedBox(height: 2.0),
              // Artist / Subtitle
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.1,
                  color: isDark
                      ? CupertinoColors.systemGrey
                      : CupertinoColors.secondaryLabel,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
