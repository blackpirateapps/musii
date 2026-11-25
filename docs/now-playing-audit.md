# Now Playing and lyrics audit

Audited commit `920feaf098d6e2fd79fd1c29aa324468ebe9b124` on 2026-11-26. The Redmi K20 Pro reproduced the reported low-contrast inline lyrics. In two runs per workload, roughly 25% of displayed-frame intervals exceeded 25 ms with the full lyrics panel open, including when it was following playback without touch input. The corresponding rate was 0.35% during steady Now Playing playback and 0.72% during the scrubber workload. The delayed-seek fixture independently reproduced a visible thumb rebound.

## Remediation

| Finding | Change |
| --- | --- |
| 1. Stale track in the lyrics panel | The Now Playing panel follows the current track and resets its lyric view on track change. Library previews stay on the selected track and only enable timed playback controls when that track is playing. |
| 2. Active lyric can remain off-screen | The timed viewport anchors directly at a distant row and aligns against its measured layout. Rapid updates coalesce around the latest active row. |
| 3. Seek thumb rebounds | The scrubber displays the requested position until an audio snapshot acknowledges it. Track changes, errors, and acknowledgement timeout recover to the audio clock. |
| 4. Lyrics title hides the close button | The title ellipsizes inside the remaining header width while the close button keeps its touch target. |
| 5. Controls clipped on short screens | Now Playing scrolls when content exceeds the safe area, including landscape and large text. The header truncates to the available width. |
| 6. Dark inline lyrics and status icons | The reel and status icons use light foregrounds on the dark artwork surface in both app themes. Neighboring lyric rows have higher opacity. |
| 7. Word sweep freezes or drifts | Active lyric rows render the audio clock directly while paused or buffering and extrapolate between samples during playback. |
| 8. Cancelled pull leaves Now Playing offset | Pointer cancellation runs the same return animation as releasing a short pull. |
| 9. Unknown duration allows a 1 ms seek | The seek slider stays disabled and shows an unknown remainder until a duration is available. |
| 10. Lyric streams retained across tracks | Inline lyrics subscribe only when visible. Per-track providers dispose after the last viewer leaves. |

## Android stress runs

The phone ran Android 16 (API 36), with a nominal 60 Hz display mode and a 1080 × 2340 physical viewport. The installed release APK, version 1.0.0+1, matched the CI artifact byte for byte. Runs used the same artwork-backed FLAC track with synchronized lyrics as the report screenshot, with the app in its Light theme. [CI build for the audited commit](https://github.com/blackpirateapps/musii/actions/runs/45668797015)

| Workload | Presented frames by run | Gaps over 25 ms by run | p99 gap by run | Longest gap |
| --- | ---: | ---: | ---: | ---: |
| Now Playing paused and settled | 0, 1 | — | — | — |
| Now Playing playing with inline lyrics | 568, 565 | 0/567, 4/564 | 16.2, 16.3 ms | 32.4 ms |
| Full lyrics panel following playback | 452, 455 | 111/451, 111/454 | 32.4, 32.4 ms | 32.4 ms |
| Full lyrics panel with alternating scroll gestures | 443, 448 | 115/442, 113/447 | 32.4, 32.4 ms | 48.5 ms |
| Now Playing with alternating scrubber drags | 556, 562 | 6/555, 2/561 | 32.3, 16.3 ms | 32.4 ms |
| Lyrics panel open and close loop | 499 | 64/498 | 32.4 ms | 32.5 ms |

Each capture sampled roughly 9.2–9.6 seconds. The stress inputs sent 24 alternating 250 ms lyrics scroll gestures per scrolling run, 18 alternating 280 ms slider drags per scrubbing run, and 11 open/close pairs in the final loop. The phone stayed in the same app process. The Android logs checked after the runs contained no Musii crash or ANR. A moderate scroll showed the **Current line** button, which successfully returned to the active row on the tested song.

The samples use actual presentation timestamps from the Musii `SurfaceView` BLAST layer. The 25 ms threshold is halfway between one and two nominal refresh periods. Presentation gaps can include time when the app intentionally produced no new frame. The Perfetto FrameTimeline captures exposed compositor and system UI slices on this setup without app-layer attribution for the Flutter surface. The table measures presentation cadence on this device and song. Dart build times, GPU raster times, and touch-to-presentation latency remain unmeasured. [Perfetto FrameTimeline](https://perfetto.dev/docs/data-sources/frametimeline)

## Confirmed findings

### High impact

1. **The lyrics panel keeps the previous song's lyrics after playback advances.** Open the panel on track A and advance playback to B while the panel remains open, for example through automatic queue advancement. In the widget fixture the header stayed on A, B's 4-second position highlighted A's 4-second row, and tapping A's 3-second row sent an unscoped seek while B was current. The popup captures a `Track` at launch, while its position listener and seek action use shared playback state. The title, rows, and seek targets should belong to the same track as the clock. [Popup and position listener][sheet-position] · [Line tap][sheet-tap]

2. **Auto-follow can leave the active line off-screen indefinitely.** Open the panel paused at 3:00 with 240 variable-height timed rows, two out of every three long enough to wrap. After 120 simulated frames, row 180 was still unmounted and the list was stuck at an offset of 8,627 logical pixels. In a separate burst with 200 timestamps 125 ms apart, the correct row was mounted on 87 of 200 updates and no active row was mounted after a two-second hold. For unbuilt items, the panel multiplies the index by a fixed 48-pixel estimate and retries after layout without checking that the target changed or making progress toward it. The highlighted row should come into view after opening, seeking, or resuming follow, including when earlier lines wrap. [Scroll targeting and retry][sheet-scroll] · [Position updates][sheet-position]

3. **The scrubber can snap to the old playback position after release.** Drag the thumb far forward and deliver an old position event before the player acknowledges the new seek. In the fixture the thumb landed at 270.662 s, returned to 30.100 s, then reached only 87.835 s 48 ms after the acknowledgement even though playback reported 270.662 s. Both the thumb and elapsed display use the interpolated position. Each distinct position event restarts a 200 ms interpolation, including stale events and discontinuous jumps. The seek target should stay visible while the seek is pending and settle to the acknowledged position. [Scrubber update loop and seek callbacks][scrubber]

4. **Long titles can push the lyrics close button off-screen.** Open lyrics at 360 × 800 logical pixels for the 209-character title fixture. Flutter reported a horizontal overflow of 2,355 logical pixels using the test font, and the close icon had no hit target. The header's title column receives unbounded horizontal space inside a `Row`, so its single-line ellipsis cannot reserve room for the close button. A long title should truncate within the space left by the close control. [Lyrics header][sheet-header]

5. **Now Playing controls are cut off on short screens and in landscape.** At 360 × 640 logical pixels with 2× text, safe-area insets, and inline lyrics enabled, the page overflowed by 122 pixels horizontally and 41 vertically. At 851 × 393 in landscape with default text size, the page overflowed by 143 pixels vertically. The lyrics control could not be tapped in either fixture. The page locks its column to the safe-area height and disables scrolling, with compact handling limited to the inline lyrics threshold. Playback and lyrics controls should stay reachable at both sizes. [Sizing and constrained layout][now-layout] · [Bottom controls][now-bottom]

6. **Light theme makes inline lyrics hard to read against the dark artwork backdrop.** Open the screenshot's song in Light theme. The Redmi showed black active lyrics and barely visible surrounding lines, matching the supplied image. The Now Playing backdrop is darkened in both themes, while the reel selects its foreground colors using the global Cupertino theme. The foreground needs to remain legible against the rendered backdrop. The same device also showed dark Android status icons over the dark top of the screen. [Backdrop treatment][now-backdrop] · [Inline colors and opacity][inline-colors]

### Medium impact

7. **Word highlighting can stay frozen after small paused seeks and run ahead during buffering.** In one active word-timed row, paused positions of 500, 600, 700, 800, 900, and 1,000 ms all rendered at 500 ms. The small-change branch adjusts its anchor without updating the displayed position when paused. In a separate fixture where the player stayed at 1,000 ms with both playing and buffering set, the rendered sweep reached 1,500 ms. The extrapolator watches the playing flag while the playback clock is stalled. The highlight should reflect the new point after a paused seek and hold when audio is stalled. [Lyric clock and update branches][lyric-clock]

8. **Cancelling a downward pull can leave the page displaced.** Start a downward drag, move the page, and cancel the pointer before release. The title moved from y=58 to y=113 and remained there after 500 ms. The full-screen recognizer handles end but has no cancel handler to restore its offset. The page should return to its resting position when the gesture is cancelled. [Dismiss drag handlers and transform][now-drag]

9. **Unknown duration exposes a seek that can only send 0–1 ms.** With a current track and zero duration in the playback snapshot, the slider remained interactive. A tap near the right edge sent a 1 ms seek and the elapsed and remaining times displayed zero seconds. The one-millisecond placeholder doubles as the interactive maximum. The seek control should represent duration availability. [Slider fallback][scrubber]

10. **Lyrics subscriptions stay open across track changes even with inline lyrics switched off.** With the panel closed and inline lyrics disabled, cycling through 64 tracks started 64 lyric streams and none was cancelled while the app scope remained alive. The inline widget reads and watches lyrics before applying the visibility setting, and the per-track provider family has no automatic disposal. Heap growth and the number of database queries during invalidation were outside the measurement. [Inline subscription and setting][inline-listen] · [Per-track provider][lyric-provider]

11. **The lyrics panel's drag handle does not respond to a pull.** On Android, dragging down over the handle by about 607 physical pixels left the modal fully open. The handle is a decorative container with no gesture wiring. The visible down-drag affordance should dismiss the panel, or the dismissal control should communicate how the sheet closes. [Modal and handle][sheet-position] · [Handle widget][sheet-handle]

## Code-review findings and performance leads

- **Playback load failure and cancellation feedback.** Initial loading publishes `isBuffering: true` and `isPlaying: false`, so pressing the spinner invokes resume. The handler returns while that track is in flight, leaving no cancellation through the center control. On download or decoder failure it logs the error and clears the spinner without publishing a reason to the screen. Reproduce with an uncached track on a stalled or failing connection. The live runs used a playable track. [Loading snapshot][load-state] · [Failure handling and resume][load-error] · [Center playback control][now-play-button]
- **The dismiss animation adds a new listener on each snap-back.** Short repeated pulls add listeners to the same animation controller without removing the old ones. Those callbacks all read the current animation and request state updates during later snap-backs. No per-frame listener count was collected on Android. [Dismiss controller][now-drag]
- **Artwork composition and text rendering are profiling candidates for the panel slowdown.** The player and panel each draw a large backdrop blur (sigma 55 and 50). Both backdrop images use full-size file decodes, while the foreground cover requests a decode size. The active lyric row can rebuild on animation ticks, reconstruct word spans, and apply a shader to partially revealed text. The inline reel also applies a shader mask. The phone trace establishes the higher frequency of presentation gaps with the panel open. Profiling is needed to attribute those gaps to blur, image decode, scrolling, or lyric painting. [Player backdrop][now-backdrop] · [Panel backdrop][sheet-backdrop] · [Cover image sizing][album-decode] · [Text spans and masks][word-renderer] · [Inline reel mask][inline-mask]
- **Accessibility coverage gaps are visible in the widget code.** The icon-only playback buttons and sheet close control have no explicit accessible action labels, and the panel's timed scroll and row animations do not read the reduced-motion flag. The inline reel already reads that flag. TalkBack and Android reduced-motion behavior were outside the live run. [Playback controls][now-play-button] · [Close button][sheet-header] · [Panel scroll animation][sheet-scroll] · [Row animation][row-animation] · [Inline motion setting][inline-listen]

## Reproducing the audit

Run the repository baseline and the separate audit probes. The probes preserve the audit scenarios and include a 25-cycle modal lifecycle control. Each remediated scenario checks the corrected behavior. The remaining scenarios still characterize the audited baseline.

```sh
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter test --no-pub tool/audit/now_playing_stress_test.dart --reporter expanded
```

Static analysis reported no issues, all 310 repository tests passed, and the 13 targeted probes passed. The widget fixtures drive the real player page and lyrics panel through scripted playback snapshots. The phone runs exercise the installed release separately. [Audit probes](../tool/audit/now_playing_stress_test.dart)

To repeat the presentation measurement, find the Musii `SurfaceView…(BLAST)#…` layer in `adb shell dumpsys SurfaceFlinger --list`. Save the newest valid presentation timestamp from the second column of `dumpsys SurfaceFlinger --latency "<layer>"` immediately before each workload. Poll that same layer roughly every 400 ms during the run so the rolling buffer retains coverage. Discard zero, the pending timestamp sentinel `9223372036854775807`, and timestamps at or before the initial sample. Deduplicate, sort, and subtract consecutive timestamps. Run each playing condition twice with the same song, seek region, and theme. Keep manual scroll and automatic following as distinct workloads. Low-end devices, other refresh modes, live download failures, and long-session heap or thermal behavior remain unverified.

[now-drag]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/playback/presentation/pages/now_playing_page.dart#L58-L153
[now-layout]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/playback/presentation/pages/now_playing_page.dart#L131-L200
[now-backdrop]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/playback/presentation/pages/now_playing_page.dart#L155-L185
[now-play-button]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/playback/presentation/pages/now_playing_page.dart#L482-L577
[now-bottom]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/playback/presentation/pages/now_playing_page.dart#L587-L683
[scrubber]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/playback/presentation/pages/now_playing_page.dart#L765-L850
[sheet-position]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/lyrics/presentation/pages/lyrics_sheet.dart#L14-L175
[sheet-scroll]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/lyrics/presentation/pages/lyrics_sheet.dart#L60-L139
[sheet-backdrop]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/lyrics/presentation/pages/lyrics_sheet.dart#L208-L237
[sheet-handle]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/lyrics/presentation/pages/lyrics_sheet.dart#L244-L255
[sheet-header]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/lyrics/presentation/pages/lyrics_sheet.dart#L257-L315
[sheet-tap]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/lyrics/presentation/pages/lyrics_sheet.dart#L438-L465
[lyric-clock]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/lyrics/presentation/widgets/lyric_line_widget.dart#L65-L181
[row-animation]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/lyrics/presentation/widgets/lyric_line_widget.dart#L217-L240
[word-renderer]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/lyrics/presentation/widgets/word_synced_lyric_text.dart#L101-L224
[inline-listen]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/playback/presentation/widgets/now_playing_inline_lyrics.dart#L305-L355
[inline-colors]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/playback/presentation/widgets/now_playing_inline_lyrics.dart#L556-L629
[inline-mask]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/playback/presentation/widgets/now_playing_inline_lyrics.dart#L639-L659
[lyric-provider]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/app/bootstrap/providers.dart#L231-L237
[album-decode]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/library/presentation/widgets/album_artwork.dart#L24-L39
[load-state]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/playback/data/repositories/playback_repository_impl.dart#L329-L341
[load-error]: https://github.com/blackpirateapps/musii/blob/920feaf098d6e2fd79fd1c29aa324468ebe9b124/lib/features/playback/data/repositories/playback_repository_impl.dart#L396-L486
