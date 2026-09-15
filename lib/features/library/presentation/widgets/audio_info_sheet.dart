import 'package:flutter/cupertino.dart';

import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/music_entities.dart';

void showAudioInfoSheet(BuildContext context, Track track) {
  showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => AudioInfoSheet(track: track),
  );
}

class AudioInfoSheet extends StatelessWidget {
  final Track track;

  const AudioInfoSheet({super.key, required this.track});

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return 'Unknown';
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  String _formatChannels(int? channels) {
    if (channels == null) return 'Unknown';
    if (channels == 1) return 'Mono';
    if (channels == 2) return 'Stereo';
    return '$channels Channels';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final items = <MapEntry<String, String>>[];

    if (track.format != null && track.format!.isNotEmpty) {
      items.add(MapEntry('Format', track.format!.toUpperCase()));
    }
    if (track.bitDepth != null) {
      items.add(MapEntry('Bit Depth', '${track.bitDepth}-bit'));
    }
    if (track.sampleRate != null) {
      final khz = (track.sampleRate! / 1000)
          .toStringAsFixed(1)
          .replaceAll('.0', '');
      items.add(MapEntry('Sample Rate', '$khz kHz'));
    }
    if (track.bitrate != null && track.bitrate! > 0) {
      final kbps = (track.bitrate! / 1000).round();
      items.add(MapEntry('Bitrate', '$kbps kbps'));
    }
    if (track.channels != null) {
      items.add(MapEntry('Channels', _formatChannels(track.channels)));
    }
    if (track.fileSize > 0) {
      items.add(MapEntry('File Size', _formatFileSize(track.fileSize)));
    }
    items.add(const MapEntry('Source', 'Google Drive'));
    items.add(MapEntry('Title', track.title));
    if (track.artistName != null) {
      items.add(MapEntry('Artist', track.artistName!));
    }
    if (track.albumName != null) {
      items.add(MapEntry('Album', track.albumName!));
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1C1C1E)
            : CupertinoColors.systemBackground,
        borderRadius: AppRadii.sheetRadius,
      ),
      padding: const EdgeInsets.only(
        top: AppSpacing.md,
        bottom: AppSpacing.xxl,
        left: AppSpacing.lg,
        right: AppSpacing.lg,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark
                      ? CupertinoColors.systemGrey
                      : CupertinoColors.systemGrey4,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Audio Technical Information',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            CupertinoListSection.insetGrouped(
              margin: EdgeInsets.zero,
              children: items.map((entry) {
                return CupertinoListTile(
                  title: Text(
                    entry.key,
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark
                          ? CupertinoColors.systemGrey
                          : CupertinoColors.secondaryLabel,
                    ),
                  ),
                  trailing: Text(
                    entry.value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? CupertinoColors.white
                          : CupertinoColors.black,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.lg),
            CupertinoButton(
              color: isDark
                  ? CupertinoColors.white.withOpacity(0.1)
                  : CupertinoColors.systemGrey6,
              borderRadius: BorderRadius.circular(AppRadii.card),
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Done',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
