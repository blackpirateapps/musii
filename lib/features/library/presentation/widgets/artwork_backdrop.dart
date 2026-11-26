import 'dart:ui';

import 'package:flutter/cupertino.dart';

import 'album_artwork.dart';

/// Uses the artwork as the blur input without filtering the rest of the route.
class ArtworkBackdrop extends StatelessWidget {
  final String? artworkPath;
  final String? artworkUrl;
  final Decoration overlay;

  const ArtworkBackdrop({
    super.key,
    required this.artworkPath,
    this.artworkUrl,
    required this.overlay,
  });

  @override
  Widget build(BuildContext context) {
    final image = trackArtworkImage(artworkPath, artworkUrl);
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null)
            ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: 36,
                  sigmaY: 36,
                  tileMode: TileMode.clamp,
                ),
                child: Image(
                  image: ResizeImage(
                    image,
                    width: 256,
                    height: 256,
                    policy: ResizeImagePolicy.fit,
                  ),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (context, error, stack) =>
                      const SizedBox.expand(),
                ),
              ),
            ),
          DecoratedBox(decoration: overlay),
        ],
      ),
    );
  }
}
