import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/bootstrap/providers.dart';
import '../../../playlists/domain/entities/playlist.dart';
import 'album_artwork.dart';

class PlaylistCard extends ConsumerWidget {
  final Playlist playlist;
  final VoidCallback onTap;

  const PlaylistCard({super.key, required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    Widget artworkWidget;
    if (playlist.artworkPath != null && playlist.artworkPath!.isNotEmpty) {
      artworkWidget = AlbumArtwork(
        artworkPath: playlist.artworkPath,
        size: double.infinity,
        borderRadius: 16.0,
      );
    } else {
      final tracksAsync = ref.watch(playlistTracksProvider(playlist.id));
      artworkWidget = tracksAsync.when(
        data: (tracks) {
          final distinctArts = <String>[];
          for (final t in tracks) {
            final p = t.artworkPath;
            if (p != null && p.isNotEmpty && !distinctArts.contains(p)) {
              distinctArts.add(p);
              if (distinctArts.length == 4) break;
            }
          }

          if (distinctArts.isEmpty) {
            return AlbumArtwork(
              title: playlist.name,
              size: double.infinity,
              borderRadius: 16.0,
            );
          }

          if (distinctArts.length < 4) {
            return AlbumArtwork(
              artworkPath: distinctArts.first,
              size: double.infinity,
              borderRadius: 16.0,
            );
          }

          return ClipRRect(
            borderRadius: BorderRadius.circular(16.0),
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: AlbumArtwork(
                          artworkPath: distinctArts[0],
                          size: double.infinity,
                          borderRadius: 0,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: AlbumArtwork(
                          artworkPath: distinctArts[1],
                          size: double.infinity,
                          borderRadius: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: AlbumArtwork(
                          artworkPath: distinctArts[2],
                          size: double.infinity,
                          borderRadius: 0,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: AlbumArtwork(
                          artworkPath: distinctArts[3],
                          size: double.infinity,
                          borderRadius: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => AlbumArtwork(
          title: playlist.name,
          size: double.infinity,
          borderRadius: 16.0,
        ),
        error: (e, st) => AlbumArtwork(
          title: playlist.name,
          size: double.infinity,
          borderRadius: 16.0,
        ),
      );
    }

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(aspectRatio: 1.0, child: artworkWidget),
          const SizedBox(height: 12),
          Text(
            playlist.name,
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
            '${playlist.trackCount} ${playlist.trackCount == 1 ? 'song' : 'songs'}',
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
