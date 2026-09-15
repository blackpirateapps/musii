import 'package:flutter/cupertino.dart';

import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/music_entities.dart';
import 'album_artwork.dart';

class ArtistRow extends StatelessWidget {
  final Artist artist;
  final VoidCallback onTap;

  const ArtistRow({super.key, required this.artist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            AlbumArtwork(
              artworkPath: artist.artworkPath,
              title: artist.name,
              artist: artist.name,
              size: 48,
              borderRadius: AppRadii.circular, // Circular artist image
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                      color: isDark
                          ? CupertinoColors.white
                          : CupertinoColors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${artist.trackCount} ${artist.trackCount == 1 ? 'song' : 'songs'}',
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
            Icon(
              CupertinoIcons.chevron_forward,
              size: 18,
              color: isDark
                  ? CupertinoColors.systemGrey2
                  : CupertinoColors.systemGrey3,
            ),
          ],
        ),
      ),
    );
  }
}
