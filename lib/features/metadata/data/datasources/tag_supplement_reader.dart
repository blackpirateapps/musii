import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import '../../../../core/logging/app_logger.dart';

/// Supplementary metadata extracted directly from container-specific tags
/// where [audio_metadata_reader] has gaps (e.g. FLAC ALBUM ARTIST with space,
/// WAV id3/ID3 RIFF chunks and LIST INFO IAAR, MP3 TPE2/TXXX, and M4A aART/cpil).
class AudioTagSupplement {
  final String? songArtist;
  final String? albumArtist;
  final bool isCompilation;

  const AudioTagSupplement({
    this.songArtist,
    this.albumArtist,
    this.isCompilation = false,
  });

  /// Extracts supplementary tags for [file] based on file extension and format magic.
  static Future<AudioTagSupplement> extract(
    File file, [
    String? knownExt,
  ]) async {
    if (!await file.exists()) {
      return const AudioTagSupplement();
    }

    final ext = (knownExt ?? p.extension(file.path))
        .replaceFirst('.', '')
        .toLowerCase();

    try {
      switch (ext) {
        case 'flac':
          return _extractFlac(file);
        case 'wav':
          return _extractWav(file);
        case 'mp3':
          return _extractMp3(file);
        case 'm4a':
        case 'mp4':
        case 'aac':
          return _extractMp4(file);
        default:
          return const AudioTagSupplement();
      }
    } catch (e, st) {
      AppLogger.debug(
        LogCategory.metadata,
        'Failed to extract supplementary tags for ${file.path}: $e\n$st',
      );
      return const AudioTagSupplement();
    }
  }

  // ---------------------------------------------------------------------------
  // FLAC / Vorbis Comments
  // ---------------------------------------------------------------------------

  static AudioTagSupplement _extractFlac(File file) {
    RandomAccessFile? reader;
    try {
      reader = file.openSync();
      final fileLength = reader.lengthSync();
      if (fileLength < 8) return const AudioTagSupplement();

      reader.setPositionSync(0);
      var header = reader.readSync(4);

      // Handle ID3v2 tag prepended before FLAC marker
      if (header.length == 4 &&
          header[0] == 0x49 &&
          header[1] == 0x44 &&
          header[2] == 0x33) {
        reader.setPositionSync(6);
        final sizeBytes = reader.readSync(4);
        final id3Size =
            10 +
            ((sizeBytes[3] & 0x7F) |
                ((sizeBytes[2] & 0x7F) << 7) |
                ((sizeBytes[1] & 0x7F) << 14) |
                ((sizeBytes[0] & 0x7F) << 21));
        if (id3Size < fileLength - 4) {
          reader.setPositionSync(id3Size);
          header = reader.readSync(4);
        }
      }

      if (String.fromCharCodes(header) != 'fLaC') {
        return const AudioTagSupplement();
      }

      bool isLastBlock = false;
      String? foundAlbumArtist;
      String? foundSongArtist;
      final List<String> artistList = [];
      bool isComp = false;

      while (!isLastBlock && reader.positionSync() + 4 <= fileLength) {
        final blockHeader = reader.readSync(4);
        final byte0 = blockHeader[0];
        isLastBlock = (byte0 & 0x80) != 0;
        final blockType = byte0 & 0x7F;
        final length =
            (blockHeader[1] << 16) | (blockHeader[2] << 8) | blockHeader[3];

        if (blockType == 4) {
          // VORBIS_COMMENT block
          final payload = reader.readSync(length);
          if (payload.length >= 8) {
            int offset = 0;
            final vendorLength = _readUint32LE(payload, offset);
            offset += 4 + vendorLength;

            if (offset + 4 <= payload.length) {
              final userCommentCount = _readUint32LE(payload, offset);
              offset += 4;

              for (
                int i = 0;
                i < userCommentCount && offset + 4 <= payload.length;
                i++
              ) {
                final commentLen = _readUint32LE(payload, offset);
                offset += 4;

                if (offset + commentLen <= payload.length) {
                  final commentStr = utf8.decode(
                    payload.sublist(offset, offset + commentLen),
                    allowMalformed: true,
                  );
                  offset += commentLen;

                  final eqIdx = commentStr.indexOf('=');
                  if (eqIdx != -1) {
                    final field = commentStr
                        .substring(0, eqIdx)
                        .trim()
                        .toUpperCase();
                    final value = commentStr.substring(eqIdx + 1).trim();

                    if (value.isNotEmpty) {
                      if (field == 'ALBUMARTIST' ||
                          field == 'ALBUM ARTIST' ||
                          field == 'ALBUM_ARTIST' ||
                          field == 'ENSEMBLE' ||
                          field == 'BAND' ||
                          field == 'ORCHESTRA') {
                        foundAlbumArtist ??= value;
                      } else if (field == 'ARTIST') {
                        artistList.add(value);
                      } else if (field == 'COMPILATION') {
                        if (value == '1' || value.toLowerCase() == 'true') {
                          isComp = true;
                        }
                      } else if (field == 'TCMP') {
                        if (value == '1') {
                          isComp = true;
                        }
                      }
                    }
                  }
                } else {
                  break;
                }
              }
            }
          }
          break; // VORBIS_COMMENT found and parsed
        } else {
          reader.setPositionSync(reader.positionSync() + length);
        }
      }

      if (artistList.isNotEmpty) {
        foundSongArtist = artistList.first;
      }

      if (isComp && foundAlbumArtist == null) {
        foundAlbumArtist = 'Various Artists';
      }

      return AudioTagSupplement(
        songArtist: foundSongArtist,
        albumArtist: foundAlbumArtist,
        isCompilation: isComp,
      );
    } finally {
      reader?.closeSync();
    }
  }

  // ---------------------------------------------------------------------------
  // WAV / RIFF
  // ---------------------------------------------------------------------------

  static AudioTagSupplement _extractWav(File file) {
    RandomAccessFile? reader;
    try {
      reader = file.openSync();
      final fileLength = reader.lengthSync();
      if (fileLength < 12) return const AudioTagSupplement();

      reader.setPositionSync(0);
      var header = reader.readSync(4);

      // Check leading ID3v2 before RIFF
      if (header.length == 4 &&
          header[0] == 0x49 &&
          header[1] == 0x44 &&
          header[2] == 0x33) {
        reader.setPositionSync(0);
        final id3Meta = ID3v2Parser(fetchImage: false).parse(reader);
        final res = _fromMp3Metadata(id3Meta);
        if (res.albumArtist != null || res.songArtist != null) {
          return res;
        }
      }

      reader.setPositionSync(0);
      final riffHeader = reader.readSync(12);
      if (riffHeader.length < 12) return const AudioTagSupplement();
      final riffMagic = String.fromCharCodes(riffHeader.sublist(0, 4));
      final waveMagic = String.fromCharCodes(riffHeader.sublist(8, 12));

      if (riffMagic != 'RIFF' || waveMagic != 'WAVE') {
        return const AudioTagSupplement();
      }

      String? foundAlbumArtist;
      String? foundSongArtist;
      bool isComp = false;

      while (reader.positionSync() + 8 <= fileLength) {
        final chunkHeader = reader.readSync(8);
        final chunkId = String.fromCharCodes(chunkHeader.sublist(0, 4));
        final chunkSize = _readUint32LE(chunkHeader, 4);
        final chunkDataOffset = reader.positionSync();

        if (chunkId == 'ID3 ' || chunkId == 'id3 ') {
          if (chunkSize >= 10) {
            final id3Head = reader.readSync(3);
            if (String.fromCharCodes(id3Head) == 'ID3') {
              reader.setPositionSync(chunkDataOffset);
              final id3Meta = ID3v2Parser(fetchImage: false).parse(reader);
              final res = _fromMp3Metadata(id3Meta);
              if (res.albumArtist != null) foundAlbumArtist ??= res.albumArtist;
              if (res.songArtist != null) foundSongArtist ??= res.songArtist;
              if (res.isCompilation) isComp = true;
            }
          }
        } else if (chunkId == 'LIST' && chunkSize >= 4) {
          final listTypeBytes = reader.readSync(4);
          final listType = String.fromCharCodes(listTypeBytes);

          if (listType == 'INFO') {
            final endOffset = chunkDataOffset + chunkSize;
            while (reader.positionSync() + 8 <= endOffset) {
              final subHeader = reader.readSync(8);
              final subId = String.fromCharCodes(subHeader.sublist(0, 4));
              final subSize = _readUint32LE(subHeader, 4);
              final subOffset = reader.positionSync();

              if (subSize > 0 && subOffset + subSize <= endOffset) {
                final textBytes = reader.readSync(subSize);
                // Null-terminated string
                int strLen = 0;
                while (strLen < textBytes.length && textBytes[strLen] != 0) {
                  strLen++;
                }
                final text = utf8
                    .decode(textBytes.sublist(0, strLen), allowMalformed: true)
                    .trim();

                if (subId == 'IAAR') {
                  foundAlbumArtist ??= text;
                } else if (subId == 'IART') {
                  foundSongArtist ??= text;
                }
              }

              final nextPos = subOffset + subSize + (subSize.isOdd ? 1 : 0);
              reader.setPositionSync(nextPos.clamp(0, endOffset));
            }
          }
        }

        final nextChunkPos =
            chunkDataOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
        reader.setPositionSync(nextChunkPos.clamp(0, fileLength));
      }

      if (isComp && foundAlbumArtist == null) {
        foundAlbumArtist = 'Various Artists';
      }

      return AudioTagSupplement(
        songArtist: foundSongArtist,
        albumArtist: foundAlbumArtist,
        isCompilation: isComp,
      );
    } finally {
      reader?.closeSync();
    }
  }

  // ---------------------------------------------------------------------------
  // MP3 / ID3v2
  // ---------------------------------------------------------------------------

  static AudioTagSupplement _extractMp3(File file) {
    RandomAccessFile? reader;
    try {
      reader = file.openSync();
      if (!MP3Parser.canUserParser(reader)) {
        return const AudioTagSupplement();
      }

      final mp3Meta = MP3Parser(fetchImage: false).parse(reader);
      return _fromMp3Metadata(mp3Meta);
    } finally {
      reader?.closeSync();
    }
  }

  static AudioTagSupplement _fromMp3Metadata(Mp3Metadata meta) {
    String? songArtist = meta.leadPerformer?.replaceAll('\x00', '').trim();
    if (songArtist == null || songArtist.isEmpty) {
      songArtist = meta.originalArtist?.replaceAll('\x00', '').trim();
    }

    String? albumArtist = meta.bandOrOrchestra?.replaceAll('\x00', '').trim();
    if (albumArtist == null || albumArtist.isEmpty) {
      // Check customMetadata keys
      for (final entry in meta.customMetadata.entries) {
        final keyUpper = entry.key.replaceAll('\x00', '').trim().toUpperCase();
        if (keyUpper == 'ALBUM ARTIST' ||
            keyUpper == 'ALBUMARTIST' ||
            keyUpper == 'ALBUM_ARTIST' ||
            keyUpper == 'TPE2') {
          final val = entry.value.replaceAll('\x00', '').trim();
          if (val.isNotEmpty) {
            albumArtist = val;
            break;
          }
        }
      }
    }

    bool isComp = false;
    for (final entry in meta.customMetadata.entries) {
      final keyUpper = entry.key.replaceAll('\x00', '').trim().toUpperCase();
      if (keyUpper == 'TCMP' ||
          keyUpper == 'COMPILATION' ||
          keyUpper == 'ITUNESCOMPILATION') {
        final val = entry.value.replaceAll('\x00', '').trim();
        if (val == '1' || val.toLowerCase() == 'true') {
          isComp = true;
          break;
        }
      }
    }

    if (isComp && (albumArtist == null || albumArtist.isEmpty)) {
      albumArtist = 'Various Artists';
    }

    return AudioTagSupplement(
      songArtist: songArtist?.isNotEmpty == true ? songArtist : null,
      albumArtist: albumArtist?.isNotEmpty == true ? albumArtist : null,
      isCompilation: isComp,
    );
  }

  // ---------------------------------------------------------------------------
  // MP4 / M4A / AAC
  // ---------------------------------------------------------------------------

  static AudioTagSupplement _extractMp4(File file) {
    RandomAccessFile? reader;
    try {
      reader = file.openSync();
      final fileLength = reader.lengthSync();
      if (fileLength < 8) return const AudioTagSupplement();

      reader.setPositionSync(0);

      String? albumArtist;
      String? songArtist;
      bool isComp = false;

      // Locate moov -> udta -> meta -> ilst
      final ilstRange = _findIlstBox(reader, fileLength);
      if (ilstRange != null) {
        final ilstStart = ilstRange.start;
        final ilstEnd = ilstRange.end;
        reader.setPositionSync(ilstStart);

        while (reader.positionSync() + 8 <= ilstEnd) {
          final boxHeader = reader.readSync(8);
          final boxSize = _readUint32BE(boxHeader, 0);
          final boxType = String.fromCharCodes(boxHeader.sublist(4, 8));
          final boxDataOffset = reader.positionSync();

          if (boxSize < 8 || boxDataOffset + boxSize - 8 > ilstEnd) {
            break;
          }

          if (boxType == 'aART') {
            albumArtist = _extractMp4DataString(
              reader,
              boxDataOffset,
              boxSize - 8,
            );
          } else if (boxType == '\u00A9ART') {
            songArtist = _extractMp4DataString(
              reader,
              boxDataOffset,
              boxSize - 8,
            );
          } else if (boxType == 'cpil') {
            isComp = _extractMp4DataBool(reader, boxDataOffset, boxSize - 8);
          } else if (boxType == '----') {
            // Custom reverse DNS box: look for name == ALBUMARTIST or ALBUM ARTIST
            final custom = _extractMp4CustomTag(
              reader,
              boxDataOffset,
              boxSize - 8,
            );
            if (custom != null) {
              final nameUpper = custom.name.trim().toUpperCase();
              if (nameUpper == 'ALBUMARTIST' ||
                  nameUpper == 'ALBUM ARTIST' ||
                  nameUpper == 'ALBUM_ARTIST') {
                albumArtist ??= custom.value;
              }
            }
          }

          reader.setPositionSync(boxDataOffset + boxSize - 8);
        }
      }

      if (isComp && albumArtist == null) {
        albumArtist = 'Various Artists';
      }

      return AudioTagSupplement(
        songArtist: songArtist,
        albumArtist: albumArtist,
        isCompilation: isComp,
      );
    } finally {
      reader?.closeSync();
    }
  }

  static ({int start, int end})? _findIlstBox(
    RandomAccessFile reader,
    int fileLength,
  ) {
    reader.setPositionSync(0);

    // Scan top-level boxes for 'moov'
    int moovOffset = -1;
    int moovSize = 0;
    while (reader.positionSync() + 8 <= fileLength) {
      final header = reader.readSync(8);
      final size = _readUint32BE(header, 0);
      final type = String.fromCharCodes(header.sublist(4, 8));
      final dataOffset = reader.positionSync();

      if (size < 8) break;
      if (type == 'moov') {
        moovOffset = dataOffset;
        moovSize = size - 8;
        break;
      }
      reader.setPositionSync(dataOffset + size - 8);
    }

    if (moovOffset == -1) return null;

    // Inside moov, find udta
    final moovEnd = moovOffset + moovSize;
    reader.setPositionSync(moovOffset);
    int udtaOffset = -1;
    int udtaSize = 0;
    while (reader.positionSync() + 8 <= moovEnd) {
      final header = reader.readSync(8);
      final size = _readUint32BE(header, 0);
      final type = String.fromCharCodes(header.sublist(4, 8));
      final dataOffset = reader.positionSync();

      if (size < 8) break;
      if (type == 'udta') {
        udtaOffset = dataOffset;
        udtaSize = size - 8;
        break;
      }
      reader.setPositionSync(dataOffset + size - 8);
    }

    if (udtaOffset == -1) return null;

    // Inside udta, find meta
    final udtaEnd = udtaOffset + udtaSize;
    reader.setPositionSync(udtaOffset);
    int metaOffset = -1;
    int metaSize = 0;
    while (reader.positionSync() + 8 <= udtaEnd) {
      final header = reader.readSync(8);
      final size = _readUint32BE(header, 0);
      final type = String.fromCharCodes(header.sublist(4, 8));
      final dataOffset = reader.positionSync();

      if (size < 8) break;
      if (type == 'meta') {
        // 'meta' has 4 bytes flags/version before child boxes
        metaOffset = dataOffset + 4;
        metaSize = size - 12;
        break;
      }
      reader.setPositionSync(dataOffset + size - 8);
    }

    if (metaOffset == -1 || metaSize <= 0) return null;

    // Inside meta, find ilst
    final metaEnd = metaOffset + metaSize;
    reader.setPositionSync(metaOffset);
    while (reader.positionSync() + 8 <= metaEnd) {
      final header = reader.readSync(8);
      final size = _readUint32BE(header, 0);
      final type = String.fromCharCodes(header.sublist(4, 8));
      final dataOffset = reader.positionSync();

      if (size < 8) break;
      if (type == 'ilst') {
        return (start: dataOffset, end: dataOffset + size - 8);
      }
      reader.setPositionSync(dataOffset + size - 8);
    }

    return null;
  }

  static String? _extractMp4DataString(
    RandomAccessFile reader,
    int offset,
    int length,
  ) {
    reader.setPositionSync(offset);
    final end = offset + length;

    while (reader.positionSync() + 8 <= end) {
      final header = reader.readSync(8);
      final size = _readUint32BE(header, 0);
      final type = String.fromCharCodes(header.sublist(4, 8));
      final dataOffset = reader.positionSync();

      if (size < 8 || dataOffset + size - 8 > end) break;

      if (type == 'data') {
        // data atom: 4 bytes type/flags, 4 bytes locale, string bytes
        if (size >= 16) {
          reader.setPositionSync(dataOffset + 8);
          final textBytes = reader.readSync(size - 16);
          final text = utf8.decode(textBytes, allowMalformed: true).trim();
          return text.isNotEmpty ? text : null;
        }
      }
      reader.setPositionSync(dataOffset + size - 8);
    }
    return null;
  }

  static bool _extractMp4DataBool(
    RandomAccessFile reader,
    int offset,
    int length,
  ) {
    reader.setPositionSync(offset);
    final end = offset + length;

    while (reader.positionSync() + 8 <= end) {
      final header = reader.readSync(8);
      final size = _readUint32BE(header, 0);
      final type = String.fromCharCodes(header.sublist(4, 8));
      final dataOffset = reader.positionSync();

      if (size < 8 || dataOffset + size - 8 > end) break;

      if (type == 'data') {
        if (size >= 9) {
          reader.setPositionSync(dataOffset + 8);
          final byteVal = reader.readByteSync();
          return byteVal == 1;
        }
      }
      reader.setPositionSync(dataOffset + size - 8);
    }
    return false;
  }

  static ({String name, String value})? _extractMp4CustomTag(
    RandomAccessFile reader,
    int offset,
    int length,
  ) {
    reader.setPositionSync(offset);
    final end = offset + length;

    String? tagName;
    String? tagValue;

    while (reader.positionSync() + 8 <= end) {
      final header = reader.readSync(8);
      final size = _readUint32BE(header, 0);
      final type = String.fromCharCodes(header.sublist(4, 8));
      final dataOffset = reader.positionSync();

      if (size < 8 || dataOffset + size - 8 > end) break;

      if (type == 'name') {
        // 4 bytes flags + name string
        if (size >= 12) {
          reader.setPositionSync(dataOffset + 4);
          tagName = utf8
              .decode(reader.readSync(size - 12), allowMalformed: true)
              .trim();
        }
      } else if (type == 'data') {
        if (size >= 16) {
          reader.setPositionSync(dataOffset + 8);
          tagValue = utf8
              .decode(reader.readSync(size - 16), allowMalformed: true)
              .trim();
        }
      }
      reader.setPositionSync(dataOffset + size - 8);
    }

    if (tagName != null && tagValue != null) {
      return (name: tagName, value: tagValue);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Endian Reading Helpers
  // ---------------------------------------------------------------------------

  static int _readUint32LE(Uint8List bytes, int offset) {
    return (bytes[offset]) |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  static int _readUint32BE(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        (bytes[offset + 3]);
  }
}
