import 'dart:io';

import 'package:flutter/cupertino.dart';

import '../../../../core/constants/app_constants.dart';

class AlbumArtwork extends StatelessWidget {
  final String? artworkPath;
  final String? title;
  final String? artist;
  final double size;
  final double borderRadius;

  const AlbumArtwork({
    super.key,
    this.artworkPath,
    this.title,
    this.artist,
    this.size = 56.0,
    this.borderRadius = AppRadii.artwork,
  });

  @override
  Widget build(BuildContext context) {
    if (artworkPath != null && artworkPath!.isNotEmpty) {
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
      final targetCacheDim = size.isFinite
          ? (size * dpr).round().clamp(64, 800)
          : 800;

      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.file(
          File(artworkPath!),
          width: size.isFinite ? size : null,
          height: size.isFinite ? size : null,
          cacheWidth: targetCacheDim,
          cacheHeight: targetCacheDim,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => _buildFallback(),
        ),
      );
    }
    return _buildFallback();
  }

  Widget _buildFallback() {
    // Generate deterministic colors from title + artist
    final seed = '${artist ?? ''}:${title ?? ''}'.hashCode;
    final hue1 = (seed.abs() % 360).toDouble();
    final hue2 = ((hue1 + 45) % 360).toDouble();

    final color1 = HSVColor.fromAHSV(1.0, hue1, 0.65, 0.45).toColor();
    final color2 = HSVColor.fromAHSV(1.0, hue2, 0.70, 0.30).toColor();

    final initials = (title != null && title!.trim().isNotEmpty)
        ? title!.trim()[0].toUpperCase()
        : '♫';

    return LayoutBuilder(
      builder: (context, constraints) {
        final dim = size.isFinite
            ? size
            : (constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : (constraints.hasBoundedHeight
                        ? constraints.maxHeight
                        : 56.0));
        final fontSize = (dim * 0.4).clamp(12.0, 72.0);

        return Container(
          width: size.isFinite ? size : null,
          height: size.isFinite ? size : null,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              colors: [color1, color2],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Text(
              initials,
              style: TextStyle(
                color: CupertinoColors.white.withOpacity(0.85),
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }
}
