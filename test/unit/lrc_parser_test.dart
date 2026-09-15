import 'package:flutter_test/flutter_test.dart';
import 'package:musii/features/lyrics/domain/services/lrc_parser.dart';

void main() {
  group('LrcParser - Standard LRC', () {
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
      expect(result.lines[0].hasWords, isFalse);

      expect(result.lines[1].timestampMs, equals(65500));
      expect(result.lines[1].text, equals('Second lyric line'));
      expect(result.lines[1].sequence, equals(1));
      expect(result.lines[1].hasWords, isFalse);

      expect(result.lines[2].timestampMs, equals(120000));
      expect(result.lines[2].text, equals('Third lyric line'));
      expect(result.lines[2].sequence, equals(2));
      expect(result.lines[2].hasWords, isFalse);
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
      expect(LrcParser.hasTimestamps('v1:<01:23.45>Hello'), isTrue);
      expect(
        LrcParser.hasTimestamps('Plain lyric line with no bracket'),
        isFalse,
      );
      expect(LrcParser.hasTimestamps('[ti:Title only]'), isFalse);
    });
  });

  group('LrcParser - v1 Word-Synchronized Format', () {
    test('parses basic v1 word-synchronized line correctly', () {
      const raw =
          'v1:<00:18.812>Look <00:19.063>in <00:19.228>my <00:19.413>eyes <00:20.185>';

      final result = LrcParser.parse(raw);

      expect(result.isSynchronized, isTrue);
      expect(result.lines.length, equals(1));

      final line = result.lines[0];
      expect(line.timestampMs, equals(18812));
      expect(line.text, equals('Look in my eyes'));
      expect(line.hasWords, isTrue);
      expect(line.words.length, equals(4));

      // Word 0: Look [18.812, 19.063)
      expect(line.words[0].text, equals('Look'));
      expect(line.words[0].startMs, equals(18812));
      expect(line.words[0].endMs, equals(19063));
      expect(line.words[0].index, equals(0));

      // Word 1: in [19.063, 19.228)
      expect(line.words[1].text, equals('in'));
      expect(line.words[1].startMs, equals(19063));
      expect(line.words[1].endMs, equals(19228));
      expect(line.words[1].index, equals(1));

      // Word 2: my [19.228, 19.413)
      expect(line.words[2].text, equals('my'));
      expect(line.words[2].startMs, equals(19228));
      expect(line.words[2].endMs, equals(19413));
      expect(line.words[2].index, equals(2));

      // Word 3: eyes [19.413, 20.185)
      expect(line.words[3].text, equals('eyes'));
      expect(line.words[3].startMs, equals(19413));
      expect(line.words[3].endMs, equals(20185));
      expect(line.words[3].index, equals(3));
    });

    test('parses multiple consecutive word-synchronized lines', () {
      const raw = '''
v1:<00:18.812>Look <00:19.063>in <00:19.228>my <00:19.413>eyes <00:20.185>
v1:<00:20.282>Searching <00:20.554>is <00:20.802>so <00:21.119>wrong <00:21.748>
''';

      final result = LrcParser.parse(raw);

      expect(result.isSynchronized, isTrue);
      expect(result.lines.length, equals(2));

      expect(result.lines[0].text, equals('Look in my eyes'));
      expect(result.lines[0].timestampMs, equals(18812));
      expect(result.lines[0].words.length, equals(4));

      expect(result.lines[1].text, equals('Searching is so wrong'));
      expect(result.lines[1].timestampMs, equals(20282));
      expect(result.lines[1].words.length, equals(4));
    });

    test('preserves punctuation and apostrophes in words', () {
      const raw =
          'v1:<00:33.397>To <00:33.497>show <00:33.821>you, <00:34.200>I\'m <00:34.500>Mr. <00:35.000>Right! <00:35.800>';

      final result = LrcParser.parse(raw);
      expect(result.lines.length, equals(1));

      final line = result.lines[0];
      expect(line.text, equals('To show you, I\'m Mr. Right!'));
      expect(line.words[2].text, equals('you,'));
      expect(line.words[3].text, equals('I\'m'));
      expect(line.words[4].text, equals('Mr.'));
      expect(line.words[5].text, equals('Right!'));
    });

    test('handles missing trailing timestamp gracefully', () {
      const raw =
          'v1:<00:18.812>Look <00:19.063>in <00:19.228>my <00:19.413>eyes';

      final result = LrcParser.parse(raw);
      expect(result.lines.length, equals(1));

      final line = result.lines[0];
      expect(line.words.length, equals(4));
      expect(line.words[3].text, equals('eyes'));
      expect(line.words[3].startMs, equals(19413));
      expect(line.words[3].endMs, greaterThan(19413));
    });

    test('handles out-of-order timestamps safely without crashing', () {
      const raw =
          'v1:<00:10.000>First <00:09.000>Second <00:12.000>Third <00:13.000>';

      final result = LrcParser.parse(raw);
      expect(result.lines.length, equals(1));

      final line = result.lines[0];
      expect(line.words.length, equals(3));
      expect(line.words[0].text, equals('First'));
      expect(line.words[0].endMs, greaterThanOrEqualTo(line.words[0].startMs));
    });

    test('applies metadata offset to word timestamps', () {
      const raw = '''
[offset:+500]
v1:<00:10.000>Word1 <00:11.000>Word2 <00:12.000>
''';

      final result = LrcParser.parse(raw);
      expect(result.lines.length, equals(1));

      final line = result.lines[0];
      expect(line.timestampMs, equals(10500));
      expect(line.words[0].startMs, equals(10500));
      expect(line.words[0].endMs, equals(11500));
      expect(line.words[1].startMs, equals(11500));
      expect(line.words[1].endMs, equals(12500));
    });
  });
}
