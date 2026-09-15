import 'package:flutter/cupertino.dart';

import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/music_entities.dart';

class TechnicalBadge extends StatelessWidget {
  final Track track;
  final VoidCallback? onTap;

  const TechnicalBadge({super.key, required this.track, this.onTap});

  String _formatBadgeText() {
    final parts = <String>[];
    if (track.format != null && track.format!.isNotEmpty) {
      parts.add(track.format!.toUpperCase());
    }

    if (track.bitDepth != null && track.sampleRate != null) {
      final khz = (track.sampleRate! / 1000)
          .toStringAsFixed(1)
          .replaceAll('.0', '');
      parts.add('${track.bitDepth}-bit / $khz kHz');
    } else if (track.bitrate != null && track.bitrate! > 0) {
      final kbps = (track.bitrate! / 1000).round();
      parts.add('$kbps kbps');
    }

    if (parts.isEmpty) {
      return track.format?.toUpperCase() ?? 'AUDIO';
    }

    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final text = _formatBadgeText();
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
        decoration: BoxDecoration(
          color: isDark
              ? CupertinoColors.white.withOpacity(0.12)
              : CupertinoColors.black.withOpacity(0.06),
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: isDark
                ? CupertinoColors.white.withOpacity(0.8)
                : CupertinoColors.black.withOpacity(0.7),
          ),
        ),
      ),
    );
  }
}
