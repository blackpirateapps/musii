import 'package:flutter_test/flutter_test.dart';
import 'package:musii/features/lyrics/domain/services/lrc_parser.dart';

void main() {
  group('LrcParser', () {
    test('parses standard [mm:ss.xx] timestamps into milliseconds', () {
      const lrc = '''
[00:12.34]First lyric line
[01:05.50]Second lyric line
[02:00.00]Third lyric line
''';

      final result = LrcParser.parse(lrc);

      expect(result.isSynchronized, isTrue);
      expect(result.lines.length, equals(3));

      expect(result.lines[0].timestampMs, equals(12340));
      expect(result.lines[0].text, equals('First lyric line'));
      expect(result.lines[0].sequence, equals(0));

      expect(result.lines[1].timestampMs, equals(65500));
      expect(result.lines[1].text, equals('Second lyric line'));
      expect(result.lines[1].sequence, equals(1));

      expect(result.lines[2].timestampMs, equals(120000));
      expect(result.lines[2].text, equals('Third lyric line'));
      expect(result.lines[2].sequence, equals(2));
    });

    test('parses [mm:ss.xxx] millisecond timestamps', () {
      const lrc = '''
[00:04.567]Millisecond precision
[00:10.123]Another line
''';

      final result = LrcParser.parse(lrc);

      expect(result.isSynchronized, isTrue);
      expect(result.lines.length, equals(2));
      expect(result.lines[0].timestampMs, equals(4567));
      expect(result.lines[0].text, equals('Millisecond precision'));
      expect(result.lines[1].timestampMs, equals(10123));
    });

    test('parses lines with multiple timestamps on a single line', () {
      const lrc = '''
[01:12.30][01:15.48]Repeated chorus line
''';

      final result = LrcParser.parse(lrc);

      expect(result.isSynchronized, isTrue);
      expect(result.lines.length, equals(2));

      // Sorted ascending
      expect(result.lines[0].timestampMs, equals(72300));
      expect(result.lines[0].text, equals('Repeated chorus line'));

      expect(result.lines[1].timestampMs, equals(75480));
      expect(result.lines[1].text, equals('Repeated chorus line'));
    });

    test('handles offset metadata tag correctly', () {
      const lrc = '''
[offset:+500]
[00:10.00]Line shifted forward by 500ms
''';

      final result = LrcParser.parse(lrc);

      expect(result.isSynchronized, isTrue);
      expect(result.offsetMs, equals(500));
      expect(result.lines.length, equals(1));
      expect(result.lines[0].timestampMs, equals(10500));
    });

    test('handles negative offset metadata bounded to zero', () {
      const lrc = '''
[offset:-800]
[00:00.50]Line shifted back
''';

      final result = LrcParser.parse(lrc);

      expect(result.isSynchronized, isTrue);
      expect(result.offsetMs, equals(-800));
      expect(result.lines.length, equals(1));
      // 500ms - 800ms = -300ms clamped to >= 0
      expect(result.lines[0].timestampMs, equals(0));
    });

    test('extracts metadata tags [ar], [ti], [al]', () {
      const lrc = '''
[ti:Stay With Me]
[ar:Miki Matsubara]
[al:Pocket Park]
[00:01.00]To you...
''';

      final result = LrcParser.parse(lrc);

      expect(result.metadataTags['ti'], equals('Stay With Me'));
      expect(result.metadataTags['ar'], equals('Miki Matsubara'));
      expect(result.metadataTags['al'], equals('Pocket Park'));
      expect(result.lines.length, equals(1));
    });

    test(
      'handles malformed lines and empty lines gracefully without crashing',
      () {
        const lrc = '''
[ti:Test]

[invalid-tag:unknown]
This is random text without timestamps
[99:99:99]
[00:05.00]Valid line 1

[00:10.00]Valid line 2
''';

        final result = LrcParser.parse(lrc);

        expect(result.isSynchronized, isTrue);
        expect(result.lines.length, equals(2));
        expect(result.lines[0].timestampMs, equals(5000));
        expect(result.lines[0].text, equals('Valid line 1'));
        expect(result.lines[1].timestampMs, equals(10000));
        expect(result.lines[1].text, equals('Valid line 2'));
      },
    );

    test('treats text with no timestamps as plain unsynchronized lyrics', () {
      const plain = '''
First stanza line
Second stanza line
Third stanza line
''';

      final result = LrcParser.parse(plain);

      expect(result.isSynchronized, isFalse);
      expect(result.lines.length, equals(3));
      expect(result.lines[0].text, equals('First stanza line'));
      expect(result.lines[0].timestampMs, equals(0));
      expect(result.lines[1].text, equals('Second stanza line'));
      expect(result.lines[2].text, equals('Third stanza line'));
    });

    test('returns empty result for null or empty input', () {
      final nullResult = LrcParser.parse(null);
      expect(nullResult.lines, isEmpty);
      expect(nullResult.isSynchronized, isFalse);

      final emptyResult = LrcParser.parse('   \n  \n');
      expect(emptyResult.lines, isEmpty);
      expect(emptyResult.isSynchronized, isFalse);
    });

    test('hasTimestamps helper correctly detects presence of timestamps', () {
      expect(LrcParser.hasTimestamps('[01:23.45]Hello'), isTrue);
      expect(LrcParser.hasTimestamps('[01:23]Hello'), isTrue);
      expect(
        LrcParser.hasTimestamps('Plain lyric line with no bracket'),
        isFalse,
      );
      expect(LrcParser.hasTimestamps('[ti:Title only]'), isFalse);
    });
  });
}
