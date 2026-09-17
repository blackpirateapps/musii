import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musii/features/metadata/data/datasources/tag_supplement_reader.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('musii_tag_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Uint8List buildFlacBytes(
    List<String> vorbisComments, {
    bool prependId3 = false,
  }) {
    final builder = BytesBuilder();

    if (prependId3) {
      // Prepend an ID3v2 tag: "ID3\x03\x00\x00" + size (10 bytes total tag size)
      builder.add([0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
    }

    // fLaC magic
    builder.add(utf8.encode('fLaC'));

    // Vorbis comment block payload
    final commentPayload = BytesBuilder();
    // Vendor length (4 bytes LE) + vendor string
    const vendor = 'musii_test';
    final vendorBytes = utf8.encode(vendor);
    final vLen = ByteData(4)..setUint32(0, vendorBytes.length, Endian.little);
    commentPayload.add(vLen.buffer.asUint8List());
    commentPayload.add(vendorBytes);

    // User comment list length (4 bytes LE)
    final cCount = ByteData(4)
      ..setUint32(0, vorbisComments.length, Endian.little);
    commentPayload.add(cCount.buffer.asUint8List());

    for (final comment in vorbisComments) {
      final cBytes = utf8.encode(comment);
      final cLen = ByteData(4)..setUint32(0, cBytes.length, Endian.little);
      commentPayload.add(cLen.buffer.asUint8List());
      commentPayload.add(cBytes);
    }

    final payloadBytes = commentPayload.toBytes();
    final blockHeader = [
      0x84, // isLastBlock = 1, type = 4 (VORBIS_COMMENT)
      (payloadBytes.length >> 16) & 0xFF,
      (payloadBytes.length >> 8) & 0xFF,
      payloadBytes.length & 0xFF,
    ];

    builder.add(blockHeader);
    builder.add(payloadBytes);

    return builder.toBytes();
  }

  Uint8List buildId3TagBytes(Map<String, String> textFrames) {
    final frameBytes = BytesBuilder();

    for (final entry in textFrames.entries) {
      final frameId = entry.key; // e.g. TPE1, TPE2, TXXX
      final text = entry.value;

      final payload = BytesBuilder();
      if (frameId == 'TXXX') {
        // Encoding 3 (UTF-8) + description + 0x00 + value
        payload.addByte(0x03);
        payload.add(utf8.encode('ALBUM ARTIST'));
        payload.addByte(0x00);
        payload.add(utf8.encode(text));
      } else {
        // Encoding 3 (UTF-8) + value
        payload.addByte(0x03);
        payload.add(utf8.encode(text));
      }

      final pBytes = payload.toBytes();
      frameBytes.add(utf8.encode(frameId)); // 4 bytes
      // Frame size (4 bytes BE)
      final fSize = ByteData(4)..setUint32(0, pBytes.length, Endian.big);
      frameBytes.add(fSize.buffer.asUint8List());
      frameBytes.add([0x00, 0x00]); // flags
      frameBytes.add(pBytes);
    }

    final allFrames = frameBytes.toBytes();
    final id3Builder = BytesBuilder();
    id3Builder.add([0x49, 0x44, 0x33, 0x04, 0x00, 0x00]); // ID3v2.4
    // Synchsafe size (4 bytes)
    final len = allFrames.length;
    id3Builder.add([
      (len >> 21) & 0x7F,
      (len >> 14) & 0x7F,
      (len >> 7) & 0x7F,
      len & 0x7F,
    ]);
    id3Builder.add(allFrames);

    return id3Builder.toBytes();
  }

  group('AudioTagSupplement - FLAC', () {
    test(
      'extracts ALBUM ARTIST with space from FLAC Vorbis comments',
      () async {
        final file = File('${tempDir.path}/track.flac');
        await file.writeAsBytes(
          buildFlacBytes([
            'TITLE=Get Lucky',
            'ARTIST=Daft Punk feat. Pharrell Williams',
            'ALBUM ARTIST=Daft Punk',
            'ALBUM=Random Access Memories',
          ]),
        );

        final supplement = await AudioTagSupplement.extract(file, 'flac');
        expect(supplement.albumArtist, equals('Daft Punk'));
        expect(
          supplement.songArtist,
          equals('Daft Punk feat. Pharrell Williams'),
        );
        expect(supplement.isCompilation, isFalse);
      },
    );

    test('extracts ALBUMARTIST and ALBUM_ARTIST from FLAC', () async {
      final file = File('${tempDir.path}/track2.flac');
      await file.writeAsBytes(
        buildFlacBytes([
          'TITLE=Song',
          'ARTIST=Artist A',
          'ALBUMARTIST=Main Artist',
        ]),
      );

      final supplement = await AudioTagSupplement.extract(file, 'flac');
      expect(supplement.albumArtist, equals('Main Artist'));
    });

    test(
      'extracts ENSEMBLE and BAND as album artist fallback in FLAC',
      () async {
        final file = File('${tempDir.path}/classical.flac');
        await file.writeAsBytes(
          buildFlacBytes([
            'TITLE=Symphony No. 5',
            'ARTIST=Herbert von Karajan',
            'ENSEMBLE=Berlin Philharmonic',
          ]),
        );

        final supplement = await AudioTagSupplement.extract(file, 'flac');
        expect(supplement.albumArtist, equals('Berlin Philharmonic'));
      },
    );

    test('detects COMPILATION=1 in FLAC and maps to Various Artists if album artist omitted', () async {
      final file = File('${tempDir.path}/comp.flac');
      await file.writeAsBytes(
        buildFlacBytes([
          'TITLE=Track 1',
          'ARTIST=Solo Artist',
          'COMPILATION=1',
        ]),
      );

      final supplement = await AudioTagSupplement.extract(file, 'flac');
      expect(supplement.isCompilation, isTrue);
      expect(supplement.albumArtist, equals('Various Artists'));
    });

    test('handles FLAC with prepended ID3v2 header gracefully', () async {
      final file = File('${tempDir.path}/prepended_id3.flac');
      await file.writeAsBytes(
        buildFlacBytes([
          'TITLE=Track With ID3 Header',
          'ARTIST=Clean Artist',
          'ALBUM ARTIST=Clean Album Artist',
        ], prependId3: true),
      );

      final supplement = await AudioTagSupplement.extract(file, 'flac');
      expect(supplement.albumArtist, equals('Clean Album Artist'));
      expect(supplement.songArtist, equals('Clean Artist'));
    });
  });

  group('AudioTagSupplement - WAV / RIFF', () {
    test('extracts album artist from embedded ID3 chunk in WAV', () async {
      final id3Bytes = buildId3TagBytes({
        'TPE1': 'WAV Song Artist',
        'TPE2': 'WAV Album Artist',
      });

      final wavBuilder = BytesBuilder();
      wavBuilder.add(utf8.encode('RIFF'));
      final totalSize = ByteData(4)
        ..setUint32(0, 4 + 8 + id3Bytes.length, Endian.little);
      wavBuilder.add(totalSize.buffer.asUint8List());
      wavBuilder.add(utf8.encode('WAVE'));

      // Add 'ID3 ' chunk
      wavBuilder.add(utf8.encode('ID3 '));
      final cSize = ByteData(4)..setUint32(0, id3Bytes.length, Endian.little);
      wavBuilder.add(cSize.buffer.asUint8List());
      wavBuilder.add(id3Bytes);

      final file = File('${tempDir.path}/test.wav');
      await file.writeAsBytes(wavBuilder.toBytes());

      final supplement = await AudioTagSupplement.extract(file, 'wav');
      expect(supplement.albumArtist, equals('WAV Album Artist'));
      expect(supplement.songArtist, equals('WAV Song Artist'));
    });

    test('extracts album artist from RIFF LIST INFO IAAR subchunk', () async {
      final infoBuilder = BytesBuilder();
      infoBuilder.add(utf8.encode('INFO'));

      // Subchunk IAAR
      final iaarBytes = utf8.encode('RIFF Album Artist\x00');
      infoBuilder.add(utf8.encode('IAAR'));
      final iaarSize = ByteData(4)
        ..setUint32(0, iaarBytes.length, Endian.little);
      infoBuilder.add(iaarSize.buffer.asUint8List());
      infoBuilder.add(iaarBytes);
      if (iaarBytes.length.isOdd) infoBuilder.addByte(0x00);

      // Subchunk IART
      final iartBytes = utf8.encode('RIFF Track Artist\x00');
      infoBuilder.add(utf8.encode('IART'));
      final iartSize = ByteData(4)
        ..setUint32(0, iartBytes.length, Endian.little);
      infoBuilder.add(iartSize.buffer.asUint8List());
      infoBuilder.add(iartBytes);
      if (iartBytes.length.isOdd) infoBuilder.addByte(0x00);

      final infoData = infoBuilder.toBytes();

      final wavBuilder = BytesBuilder();
      wavBuilder.add(utf8.encode('RIFF'));
      final totalSize = ByteData(4)
        ..setUint32(0, 4 + 8 + infoData.length, Endian.little);
      wavBuilder.add(totalSize.buffer.asUint8List());
      wavBuilder.add(utf8.encode('WAVE'));

      // Add 'LIST' chunk
      wavBuilder.add(utf8.encode('LIST'));
      final cSize = ByteData(4)..setUint32(0, infoData.length, Endian.little);
      wavBuilder.add(cSize.buffer.asUint8List());
      wavBuilder.add(infoData);

      final file = File('${tempDir.path}/test_info.wav');
      await file.writeAsBytes(wavBuilder.toBytes());

      final supplement = await AudioTagSupplement.extract(file, 'wav');
      expect(supplement.albumArtist, equals('RIFF Album Artist'));
      expect(supplement.songArtist, equals('RIFF Track Artist'));
    });
  });

  group('AudioTagSupplement - MP3', () {
    test('extracts TPE2 as album artist and TPE1 as song artist', () async {
      final id3Bytes = buildId3TagBytes({
        'TPE1': 'Daft Punk feat. Julian Casablancas',
        'TPE2': 'Daft Punk',
      });

      final mp3Builder = BytesBuilder();
      mp3Builder.add(id3Bytes);
      // Dummy MPEG frame header
      mp3Builder.add([0xFF, 0xFB, 0x90, 0x64]);

      final file = File('${tempDir.path}/test.mp3');
      await file.writeAsBytes(mp3Builder.toBytes());

      final supplement = await AudioTagSupplement.extract(file, 'mp3');
      expect(supplement.albumArtist, equals('Daft Punk'));
      expect(
        supplement.songArtist,
        equals('Daft Punk feat. Julian Casablancas'),
      );
    });

    test('extracts TXXX ALBUM ARTIST in MP3', () async {
      final id3Bytes = buildId3TagBytes({
        'TPE1': 'Track Singer',
        'TXXX': 'Custom Album Artist',
      });

      final mp3Builder = BytesBuilder();
      mp3Builder.add(id3Bytes);
      mp3Builder.add([0xFF, 0xFB, 0x90, 0x64]);

      final file = File('${tempDir.path}/test_txxx.mp3');
      await file.writeAsBytes(mp3Builder.toBytes());

      final supplement = await AudioTagSupplement.extract(file, 'mp3');
      expect(supplement.albumArtist, equals('Custom Album Artist'));
      expect(supplement.songArtist, equals('Track Singer'));
    });
  });

  group('AudioTagSupplement - MP4 / M4A', () {
    test('extracts aART and cpil boxes from M4A atom hierarchy', () async {
      // Build moov -> udta -> meta -> ilst -> aART & cpil
      final aArtText = utf8.encode('M4A Album Artist');
      final aArtData = BytesBuilder();
      final aArtDataSize = ByteData(4)
        ..setUint32(0, 16 + aArtText.length, Endian.big);
      aArtData.add(aArtDataSize.buffer.asUint8List());
      aArtData.add(utf8.encode('data'));
      aArtData.add([
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
      ]); // type UTF8, locale 0
      aArtData.add(aArtText);

      final aArtBox = BytesBuilder();
      final aArtBytes = aArtData.toBytes();
      final aArtBoxSize = ByteData(4)
        ..setUint32(0, 8 + aArtBytes.length, Endian.big);
      aArtBox.add(aArtBoxSize.buffer.asUint8List());
      aArtBox.add(utf8.encode('aART'));
      aArtBox.add(aArtBytes);

      // ilst
      final ilstData = aArtBox.toBytes();
      final ilstBox = BytesBuilder();
      final ilstSize = ByteData(4)
        ..setUint32(0, 8 + ilstData.length, Endian.big);
      ilstBox.add(ilstSize.buffer.asUint8List());
      ilstBox.add(utf8.encode('ilst'));
      ilstBox.add(ilstData);

      // meta (size + 'meta' + 4 bytes version/flags + children)
      final metaData = ilstBox.toBytes();
      final metaBox = BytesBuilder();
      final metaSize = ByteData(4)
        ..setUint32(0, 12 + metaData.length, Endian.big);
      metaBox.add(metaSize.buffer.asUint8List());
      metaBox.add(utf8.encode('meta'));
      metaBox.add([0x00, 0x00, 0x00, 0x00]); // 4 bytes version/flags
      metaBox.add(metaData);

      // udta
      final udtaData = metaBox.toBytes();
      final udtaBox = BytesBuilder();
      final udtaSize = ByteData(4)
        ..setUint32(0, 8 + udtaData.length, Endian.big);
      udtaBox.add(udtaSize.buffer.asUint8List());
      udtaBox.add(utf8.encode('udta'));
      udtaBox.add(udtaData);

      // moov
      final moovData = udtaBox.toBytes();
      final moovBox = BytesBuilder();
      final moovSize = ByteData(4)
        ..setUint32(0, 8 + moovData.length, Endian.big);
      moovBox.add(moovSize.buffer.asUint8List());
      moovBox.add(utf8.encode('moov'));
      moovBox.add(moovData);

      // ftyp
      final ftypBox = [
        0x00,
        0x00,
        0x00,
        0x14,
        0x66,
        0x74,
        0x79,
        0x70,
        0x4D,
        0x34,
        0x41,
        0x20,
        0x00,
        0x00,
        0x02,
        0x00,
        0x6D,
        0x70,
        0x34,
        0x32,
      ];

      final fileBuilder = BytesBuilder();
      fileBuilder.add(ftypBox);
      fileBuilder.add(moovBox.toBytes());

      final file = File('${tempDir.path}/test.m4a');
      await file.writeAsBytes(fileBuilder.toBytes());

      final supplement = await AudioTagSupplement.extract(file, 'm4a');
      expect(supplement.albumArtist, equals('M4A Album Artist'));
    });
  });
}
