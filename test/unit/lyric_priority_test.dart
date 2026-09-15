import 'package:flutter_test/flutter_test.dart';
import 'package:musii/features/lyrics/domain/entities/lyric_model.dart';
import 'package:musii/features/lyrics/domain/services/lrc_parser.dart';

LyricSource determineLyricPriority({
  required String? embeddedLyrics,
  required String? sidecarLrcContent,
}) {
  if (embeddedLyrics != null && embeddedLyrics.trim().isNotEmpty) {
    final parsed = LrcParser.parse(embeddedLyrics);
    if (parsed.isSynchronized && parsed.lines.isNotEmpty) {
      return LyricSource.embeddedSynced;
    } else if (parsed.lines.isNotEmpty) {
      return LyricSource.embeddedPlain;
    }
  }

  if (sidecarLrcContent != null && sidecarLrcContent.trim().isNotEmpty) {
    final parsed = LrcParser.parse(sidecarLrcContent);
    if (parsed.lines.isNotEmpty) {
      return LyricSource.sidecarLrc;
    }
  }

  return LyricSource.none;
}

bool matchesLrcSidecar({
  required String audioFolderId,
  required String audioFilename,
  required String lrcFolderId,
  required String lrcFilename,
}) {
  if (audioFolderId != lrcFolderId) return false;

  String cleanBase(String name) {
    final withoutExt = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    return withoutExt.trim().toLowerCase();
  }

  return cleanBase(audioFilename) == cleanBase(lrcFilename);
}

void main() {
  group('Lyric Priority Rules (Section 14)', () {
    test(
      'embedded synchronized lyrics takes top priority over sidecar LRC',
      () {
        const embedded = '[00:10.00]Embedded synced line';
        const sidecar = '[00:12.00]Sidecar line';

        final source = determineLyricPriority(
          embeddedLyrics: embedded,
          sidecarLrcContent: sidecar,
        );

        expect(source, equals(LyricSource.embeddedSynced));
      },
    );

    test('embedded plain lyrics takes priority over sidecar LRC', () {
      const embedded = 'Plain embedded lyrics\nNo timestamps';
      const sidecar = '[00:12.00]Sidecar line';

      final source = determineLyricPriority(
        embeddedLyrics: embedded,
        sidecarLrcContent: sidecar,
      );

      expect(source, equals(LyricSource.embeddedPlain));
    });

    test('falls back to sidecar LRC if embedded lyrics are absent', () {
      const sidecar = '[00:12.00]Sidecar line';

      final source = determineLyricPriority(
        embeddedLyrics: null,
        sidecarLrcContent: sidecar,
      );

      expect(source, equals(LyricSource.sidecarLrc));
    });

    test(
      'falls back to sidecar LRC if embedded lyrics are empty/whitespace',
      () {
        const sidecar = '[00:12.00]Sidecar line';

        final source = determineLyricPriority(
          embeddedLyrics: '   \n  \n',
          sidecarLrcContent: sidecar,
        );

        expect(source, equals(LyricSource.sidecarLrc));
      },
    );

    test('returns none if neither embedded nor sidecar is present', () {
      final source = determineLyricPriority(
        embeddedLyrics: null,
        sidecarLrcContent: null,
      );

      expect(source, equals(LyricSource.none));
    });
  });

  group('LRC Filename Matching Rules (Section 13)', () {
    test(
      'matches same base filename in same folder regardless of extension case',
      () {
        expect(
          matchesLrcSidecar(
            audioFolderId: 'folder_1',
            audioFilename: '01 - Mayonaka no Door.flac',
            lrcFolderId: 'folder_1',
            lrcFilename: '01 - Mayonaka no Door.lrc',
          ),
          isTrue,
        );

        expect(
          matchesLrcSidecar(
            audioFolderId: 'folder_1',
            audioFilename: 'Track01.MP3',
            lrcFolderId: 'folder_1',
            lrcFilename: 'track01.LRC',
          ),
          isTrue,
        );
      },
    );

    test('normalizes insignificant whitespace in base filename', () {
      expect(
        matchesLrcSidecar(
          audioFolderId: 'folder_1',
          audioFilename: '01 - Song  .m4a',
          lrcFolderId: 'folder_1',
          lrcFilename: '01 - Song.lrc',
        ),
        isTrue,
      );
    });

    test('does NOT match files in different folders', () {
      expect(
        matchesLrcSidecar(
          audioFolderId: 'folder_1',
          audioFilename: '01 - Song.flac',
          lrcFolderId: 'folder_2',
          lrcFilename: '01 - Song.lrc',
        ),
        isFalse,
      );
    });

    test('does NOT match unrelated files in same folder', () {
      expect(
        matchesLrcSidecar(
          audioFolderId: 'folder_1',
          audioFilename: '01 - Song.flac',
          lrcFolderId: 'folder_1',
          lrcFilename: '02 - Other Song.lrc',
        ),
        isFalse,
      );
    });
  });
}
