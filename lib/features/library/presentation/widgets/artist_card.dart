import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../domain/entities/music_entities.dart';
import 'album_artwork.dart';

class ArtistCard extends ConsumerWidget {
  final Artist artist;
  final VoidCallback onTap;

  const ArtistCard({super.key, required this.artist, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    // Lazily fetch official artist portrait if missing
    if (artist.artworkPath == null ||
        !artist.artworkPath!.contains('artist_')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(artistArtworkDownloaderProvider).downloadArtistArtwork(artist);
      });
    }

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: AlbumArtwork(
              artworkPath: artist.artworkPath,
              title: artist.name,
              artist: artist.name,
              size: double.infinity,
              borderRadius: 12.0, // subtle corner radius
            ),
          ),
          const SizedBox(height: 12),
          Text(
            artist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${artist.trackCount} ${artist.trackCount == 1 ? 'song' : 'songs'}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: isDark
                  ? CupertinoColors.white.withOpacity(0.6)
                  : CupertinoColors.secondaryLabel,
            ),
          ),
        ],
      ),
    );
  }
}
