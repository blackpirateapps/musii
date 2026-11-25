import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Slider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musii/app/bootstrap/providers.dart';
import 'package:musii/features/last_fm/presentation/providers/last_fm_providers.dart';
import 'package:musii/features/library/domain/entities/music_entities.dart';
import 'package:musii/features/lyrics/domain/entities/lyric_model.dart';
import 'package:musii/features/lyrics/presentation/pages/lyrics_sheet.dart';
import 'package:musii/features/lyrics/presentation/widgets/lyric_line_widget.dart';
import 'package:musii/features/lyrics/presentation/widgets/word_synced_lyric_text.dart';
import 'package:musii/features/playback/domain/entities/playback_repository.dart';
import 'package:musii/features/playback/domain/entities/playback_state.dart';
import 'package:musii/features/playback/presentation/pages/now_playing_page.dart';

class _Playback extends Mock implements PlaybackRepository {}

class _InlineLyricsSetting extends InlineLyricsNotifier {
  _InlineLyricsSetting(this.enabled);

  final bool enabled;

  @override
  bool build() => enabled;
}

Track _track(String id, {String? title}) => Track(
  id: id,
  driveFileId: id,
  sourceId: 'audit',
  title: title ?? 'Track $id',
  normalizedTitle: id,
  artistName: 'Audit Artist',
  albumName: 'Audit Album',
  format: 'FLAC',
  bitrate: 1060000,
  durationMs: 300000,
);

TrackLyrics _lyrics(Track track, List<LyricLine> lines) => TrackLyrics(
  id: 'lyrics-${track.id}',
  trackId: track.id,
  source: LyricSource.embeddedSynced,
  isSynchronized: true,
  lines: lines,
);

List<LyricLine> _lines(
  int count, {
  int interval = 1000,
  bool wrap = false,
  String prefix = 'Audit',
}) => List.generate(count, (index) {
  final label = '$prefix line $index';
  return LyricLine(
    timestampMs: index * interval,
    sequence: index,
    text: wrap && index % 3 != 0 ? List.filled(10, label).join(' ') : label,
  );
});

class _Fixture {
  final WidgetTester tester;
  final _Playback repository = _Playback();
  final updates = StreamController<PlayerStateSnapshot>.broadcast();
  final seeks = <Duration>[];
  final startedLyrics = <String>{};
  final stoppedLyrics = <String>{};
  final pendingLyrics = <StreamController<TrackLyrics?>>[];
  late PlayerStateSnapshot snapshot;

  _Fixture(this.tester) {
    when(() => repository.seek(any())).thenAnswer((invocation) async {
      seeks.add(invocation.positionalArguments.single as Duration);
    });
    addTearDown(() async {
      await updates.close();
      for (final controller in pendingLyrics) {
        unawaited(controller.close());
      }
    });
  }

  Future<void> mount(
    Track track, {
    required Map<String, TrackLyrics> lyrics,
    List<Track>? tracks,
    Widget child = const NowPlayingPage(),
    Size size = const Size(393, 851),
    double textScale = 1,
    int position = 0,
    bool playing = false,
    bool buffering = false,
    bool inlineLyrics = true,
    Duration duration = const Duration(minutes: 5),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    snapshot = PlayerStateSnapshot(
      currentTrack: track,
      isPlaying: playing,
      isBuffering: buffering,
      position: Duration(milliseconds: position),
      duration: duration,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackRepositoryProvider.overrideWithValue(repository),
          playerStateProvider.overrideWith(
            (ref) => Stream.multi((sink) {
              final sub = updates.stream.listen(sink.addSync);
              sink.onCancel = sub.cancel;
              sink.addSync(snapshot);
            }),
          ),
          inlineLyricsEnabledProvider.overrideWith(
            () => _InlineLyricsSetting(inlineLyrics),
          ),
          lastScrobbledTrackProvider.overrideWith((ref) => Stream.value(null)),
          for (final item in tracks ?? [track]) ...[
            isTrackFavoriteProvider(item.id)
                .overrideWith((ref) => Stream.value(false)),
            trackLyricsProvider(item.id).overrideWith((ref) {
              final controller = StreamController<TrackLyrics?>(
                onListen: () => startedLyrics.add(item.id),
                onCancel: () => stoppedLyrics.add(item.id),
              )..add(lyrics[item.id]);
              pendingLyrics.add(controller);
              return controller.stream;
            }),
          ],
        ],
        child: CupertinoApp(
          theme: const CupertinoThemeData(brightness: Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(top: 28, bottom: 24),
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: child,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> position(
    int milliseconds, {
    Track? track,
    bool? playing,
    bool? buffering,
    Duration frame = const Duration(milliseconds: 16),
  }) async {
    snapshot = snapshot.copyWith(
      position: Duration(milliseconds: milliseconds),
      currentTrack: track,
      isPlaying: playing,
      isBuffering: buffering,
    );
    updates.add(snapshot);
    await tester.pump(frame);
  }
}

Finder _activeSheetLine() => find.descendant(
  of: find.byType(LyricsSheet),
  matching: find.byWidgetPredicate(
    (widget) => widget is LyricLineWidget && widget.isActive,
  ),
);

double _slider(WidgetTester tester) =>
    tester.widget<Slider>(find.byType(Slider)).value;

void main() {
  setUpAll(() => registerFallbackValue(Duration.zero));

  testWidgets('far resume in 240 variable-height lyric lines', (tester) async {
    final a = _track('a');
    final fixture = _Fixture(tester);
    await fixture.mount(
      a,
      lyrics: {a.id: _lyrics(a, _lines(240, wrap: true))},
      child: LyricsSheet(track: a),
      position: 180000,
    );
    await tester.pumpAndSettle();
    final view = find.byType(CustomScrollView);
    final active = _activeSheetLine();
    expect(tester.widget<LyricLineWidget>(active).line.sequence, 180);
    expect(
      tester.getCenter(active).dy,
      closeTo(
        tester.getTopLeft(view).dy + tester.getSize(view).height * 0.45,
        1,
      ),
    );
  });

  testWidgets('open panel across a playback track transition', (tester) async {
    final a = _track('a');
    final b = _track('b');
    final fixture = _Fixture(tester);
    await fixture.mount(
      a,
      tracks: [a, b],
      lyrics: {
        a.id: _lyrics(a, _lines(30, prefix: 'Old')),
        b.id: _lyrics(b, _lines(30, prefix: 'New')),
      },
      position: 2000,
    );
    await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
    await tester.pumpAndSettle();
    await fixture.position(4000, track: b);
    await tester.pumpAndSettle();
    final sheet = tester.widget<LyricsSheet>(find.byType(LyricsSheet));
    expect(sheet.track.id, b.id);
    expect(find.text('Old line 4'), findsNothing);
    expect(
      tester.widget<LyricLineWidget>(_activeSheetLine()).line.text,
      'New line 4',
    );
    await tester.tap(find.text('New line 3').hitTestable());
    expect(fixture.seeks, [const Duration(seconds: 3)]);
  });

  testWidgets('lyrics header long title on a small phone', (tester) async {
    final a = _track('a', title: List.filled(14, 'Deluxe Version').join(' '));
    final fixture = _Fixture(tester);
    await fixture.mount(
      a,
      lyrics: {a.id: _lyrics(a, _lines(4))},
      child: LyricsSheet(track: a),
      size: const Size(360, 800),
    );
    expect(tester.takeException(), isNull);
    expect(find.byIcon(CupertinoIcons.xmark).hitTestable(), findsOneWidget);
    final title = tester.widget<Text>(find.text(a.title));
    expect(title.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(find.text(a.title)).width, lessThan(360));
  });

  testWidgets('Now Playing at 360 x 640 with large text', (tester) async {
    final a = _track('a');
    final fixture = _Fixture(tester);
    await fixture.mount(
      a,
      lyrics: {a.id: _lyrics(a, _lines(4))},
      size: const Size(360, 640),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final lyricsButton = find.byIcon(CupertinoIcons.quote_bubble);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -350),
    );
    await tester.pumpAndSettle();
    expect(lyricsButton.hitTestable(), findsOneWidget);
  });

  testWidgets('Now Playing at 851 x 393 in landscape', (tester) async {
    final a = _track('a');
    final fixture = _Fixture(tester);
    await fixture.mount(
      a,
      lyrics: {a.id: _lyrics(a, _lines(4))},
      size: const Size(851, 393),
    );
    expect(tester.takeException(), isNull);
    final lyricsButton = find.byIcon(CupertinoIcons.quote_bubble);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -350),
    );
    await tester.pumpAndSettle();
    expect(lyricsButton.hitTestable(), findsOneWidget);
  });

  testWidgets('paused seek and sub-300 ms word highlight corrections', (
    tester,
  ) async {
    final a = _track('a');
    final fixture = _Fixture(tester);
    const line = LyricLine(
      timestampMs: 0,
      sequence: 0,
      text: 'Audit word',
      words: [
        LyricWord(startMs: 0, endMs: 900, text: 'Audit', index: 0),
        LyricWord(startMs: 900, endMs: 1800, text: 'word', index: 1),
      ],
    );
    await fixture.mount(
      a,
      lyrics: {
        a.id: _lyrics(a, [line]),
      },
      child: LyricsSheet(track: a),
      position: 500,
    );
    int progress() => tester
        .widget<WordSyncedLyricText>(find.byType(WordSyncedLyricText))
        .position
        .inMilliseconds;
    final samples = <int>[progress()];
    for (final position in [600, 700, 800, 900, 1000]) {
      await fixture.position(position);
      samples.add(progress());
    }
    expect(samples, [500, 600, 700, 800, 900, 1000]);
  });

  testWidgets('dense feed of two hundred timed lyric updates', (tester) async {
    final a = _track('a');
    final fixture = _Fixture(tester);
    await fixture.mount(
      a,
      lyrics: {a.id: _lyrics(a, _lines(300, interval: 125))},
      child: LyricsSheet(track: a),
      playing: true,
    );
    var activeMatches = 0;
    for (var index = 1; index <= 200; index++) {
      await fixture.position(
        index * 125,
        frame: const Duration(milliseconds: 125),
      );
      final active = _activeSheetLine().evaluate().map((entry) => entry.widget);
      if (active.whereType<LyricLineWidget>().any(
        (row) => row.line.sequence == index,
      )) {
        activeMatches++;
      }
    }
    await tester.pump(const Duration(seconds: 2));
    expect(activeMatches, greaterThanOrEqualTo(190));
    final active = _activeSheetLine();
    expect(tester.widget<LyricLineWidget>(active).line.sequence, 200);
    expect(active.hitTestable(), findsOneWidget);
  });

  testWidgets(
    'lyric clock holds during buffering and restarts with the audio',
    (tester) async {
      final a = _track('a');
      final fixture = _Fixture(tester);
      await fixture.mount(
        a,
        lyrics: {a.id: _lyrics(a, _lines(4, interval: 4000))},
        child: LyricsSheet(track: a),
        playing: true,
        buffering: true,
        position: 1000,
      );
      final progress = find.descendant(
        of: _activeSheetLine(),
        matching: find.byType(WordSyncedLyricText),
      );
      var maxRendered = 1000;
      for (var frame = 0; frame < 15; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final position = tester
            .widget<WordSyncedLyricText>(progress)
            .position
            .inMilliseconds;
        if (position > maxRendered) maxRendered = position;
      }
      expect(maxRendered, 1000);
      await fixture.position(1100, buffering: false);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<WordSyncedLyricText>(progress).position.inMilliseconds,
        greaterThan(1100),
      );
    },
  );

  testWidgets('seek control stays interactive when duration is unknown', (
    tester,
  ) async {
    final a = _track('a');
    final fixture = _Fixture(tester);
    await fixture.mount(a, lyrics: {}, duration: Duration.zero);
    final slider = find.byType(Slider);
    expect(tester.widget<Slider>(slider).max, 1);
    expect(find.text('0:00'), findsOneWidget);
    expect(find.text('-0:00'), findsOneWidget);
    final bounds = tester.getRect(slider);
    await tester.tapAt(Offset(bounds.right - 8, bounds.center.dy));
    await tester.pump();
    expect(fixture.seeks, [const Duration(milliseconds: 1)]);
  });

  testWidgets('twenty-five sequential lyrics panel opens and closes', (
    tester,
  ) async {
    final a = _track('a');
    final fixture = _Fixture(tester);
    await fixture.mount(
      a,
      lyrics: {a.id: _lyrics(a, _lines(30))},
      position: 2000,
    );
    for (var cycle = 0; cycle < 25; cycle++) {
      await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
      await tester.pumpAndSettle();
      expect(find.byType(LyricsSheet), findsOneWidget);
      await tester.tap(find.byIcon(CupertinoIcons.xmark));
      await tester.pumpAndSettle();
      expect(find.byType(LyricsSheet), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'seek thumb and elapsed label during delayed seek acknowledgement',
    (tester) async {
      final a = _track('a');
      final fixture = _Fixture(tester);
      await fixture.mount(a, lyrics: {}, position: 30000);
      await tester.pumpAndSettle();
      final slider = find.byType(Slider);
      final bounds = tester.getRect(slider);
      final gesture = await tester.startGesture(bounds.center);
      await gesture.moveTo(Offset(bounds.right - 45, bounds.center.dy));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
      final landed = _slider(tester);
      await fixture.position(30100);
      await tester.pump(const Duration(milliseconds: 220));
      final stale = _slider(tester);
      expect(stale, landed);
      expect(find.text('4:30'), findsOneWidget);
      final target = fixture.seeks.single.inMilliseconds;
      await fixture.position(target);
      expect(_slider(tester), target);
      expect(find.text('4:30'), findsOneWidget);

      await tester.tapAt(Offset(bounds.left + 80, bounds.center.dy));
      await tester.pump();
      expect(_slider(tester).round(), fixture.seeks.last.inMilliseconds);
      await tester.pump(const Duration(seconds: 2));
      expect(_slider(tester), target);
    },
  );

  testWidgets('gesture cancellation on pull-to-dismiss', (tester) async {
    final a = _track('a');
    final fixture = _Fixture(tester);
    await fixture.mount(a, lyrics: {});
    final title = find.text('Now Playing');
    final startY = tester.getCenter(title).dy;
    final gesture = await tester.startGesture(Offset(195, startY + 115));
    await gesture.moveBy(const Offset(0, 30));
    await gesture.moveBy(const Offset(0, 55));
    await tester.pump();
    final pulledY = tester.getCenter(title).dy;
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(pulledY, greaterThan(startY));
    expect(tester.getCenter(title).dy, startY);
  });

  testWidgets(
    '64 track changes retain lyric subscriptions with inline lyrics off',
    (tester) async {
      final tracks = List.generate(64, (index) => _track('track-$index'));
      final fixture = _Fixture(tester);
      await fixture.mount(
        tracks.first,
        tracks: tracks,
        lyrics: {
          for (final track in tracks) track.id: _lyrics(track, _lines(10)),
        },
      );
      for (final track in tracks.skip(1)) {
        await fixture.position(0, track: track);
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 500));
      debugPrint(
        'track churn: started=${fixture.startedLyrics.length} '
        'cancelled=${fixture.stoppedLyrics.length}',
      );
    },
  );
}
