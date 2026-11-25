# Musii — AI Engineering Handoff Document

> **Document Version**: 1.19.0
> **Target Audience**: Incoming AI Coding Assistants & Human Software Engineers  
> **Last Verified**: November 2026
> **App Identifier**: `com.blackpirateapps.musii`  
> **Verification**: See the Google Drive sync audit for suite results and live testing scope.

---

## 1. Executive Summary & Strict Operational Rules

Musii is an offline-first, Cupertino-styled personal music streaming player for Android. It connects directly to the user's Google Drive via OAuth 2.0, recursively scans and indexes their music collection into a reactive Drift SQLite database, and streams/caches audio with background audio playback, lock screen media controls, LRU cache eviction, offline pinning, synchronized LRC lyrics, and Last.fm scrobbling.

All production code paths are 100% complete with no mock data, no fake playback, and no placeholder TODOs. Static analysis (`flutter analyze`) passes with **0 issues**, and the automated test suite (`flutter test`) passes with **100% success**.

### ⚠️ Strict Operational Rules for AI Assistants
1. **DO NOT BUILD APK LOCALLY**:
   - **Rule**: Never run `flutter build apk` or local Gradle build tasks in this development environment.
   - **Rationale**: Local Android SDK/Gradle dependencies and memory constraints are reserved for development and testing. All APK compilation, keystore signing, and release artifact generation are strictly delegated to GitHub Actions CI (`.github/workflows/build-apk.yml`).
2. **Standard Workflow Protocol**:
   - Verify all Dart code with `flutter analyze` (enforce 0 issues).
   - Run the automated test suite with `flutter test` (must maintain 100% passing).
   - Update `docs/ai-handoff.md` with any architectural, database, or UI changes.
   - Commit changes with clear, descriptive commit messages and push to the remote git branch.

---

## 2. Architecture & Design Patterns

### Architectural Style: Clean Architecture & Domain-Driven Design (DDD)
The codebase strictly adheres to standard four-layer Clean Architecture:
1. **Core (`lib/core/`)**:
   - `result/result.dart`: Sealed `Result<S, F>` functional type (`Success`, `Failure`, `fold`, `map`). Never throw raw exceptions from repository layers.
   - `error/failures.dart`: Sealed `AppFailure` hierarchy (`AuthenticationFailure`, `DriveApiFailure`, `CacheFailure`, `DatabaseFailure`, `LastFmAuthenticationFailure`, `LastFmNetworkFailure`, `LastFmApiFailure`, `LastFmRateLimitFailure`, `LastFmConfigurationFailure`, etc.).
   - `logging/app_logger.dart`: Structured categorical logging with OAuth token, API secret, session key, and signature redaction.
   - `constants/app_constants.dart`: Design tokens (`AppRadii`, `AppSpacing`, `AppAudioConstants`, `AppGreeting`).
   - `filesystem/app_file_system.dart`: Centralized cache directory management, `.partial` file staging, and atomic commits.
   - `storage/secure_credential_store.dart`: Abstract `SecureCredentialStore` with hardware-backed Android Keystore (`FlutterSecureStorage`) and in-memory test store.
   - `database/`: Drift SQLite setup, 25 tables with `@DataClassName` annotations and schema v11 migration.
2. **Domain (`lib/features/*/domain/`)**:
   - Pure Dart entities (`Track`, `Album`, `Artist`, `Genre`, `Playlist`, `CacheEntry`, `PlayerStateSnapshot`, `TrackLyrics`, `LyricLine`, `LyricWord`, `LyricSource`, `SyncProgress`, `SyncPhase`, `SyncCancellationToken`).
   - Repository interfaces declaring business contracts (`MusicLibraryRepository`, `GoogleDriveRepository`, `CacheRepository`, `PlaybackRepository`, `LyricsRepository`, `PlaylistRepository`, etc.).
   - Domain services (`MetadataNormalizationService`, `LrcParser`).
3. **Data (`lib/features/*/data/`)**:
   - Concrete repository implementations (`GoogleDriveRepositoryImpl`, `MusicLibraryRepositoryImpl`, `CacheRepositoryImpl`, `PlaybackRepositoryImpl`, `LyricsRepositoryImpl`, `PlaylistRepositoryImpl`, etc.).
   - Network calls via `googleapis` and `http`.
   - SQLite queries via `drift`.
   - Audio decoding via `just_audio` and `audio_service`.
4. **Presentation (`lib/features/*/presentation/`)**:
   - iOS Cupertino design components tailored for Android (`CupertinoPageScaffold`, `CupertinoNavigationBar`, `CupertinoTabBar`, `CupertinoActionSheet`).
   - State management via `flutter_riverpod` (v3).
   - Navigation via `go_router` with persistent docked `MiniPlayer` above tabs.

---

## 3. Subsystems & Features

The [Now Playing and lyrics audit](now-playing-audit.md) tracks playback UI fixes and the Android performance baseline.

### 1. Home Screen Experience (Visual Authority)
Located in `lib/features/library/presentation/pages/home_page.dart` and `lib/features/library/presentation/widgets/`:
- **Atmospheric Twilight Backdrop**: Rich twilight and warm sunset gradient glow (`RadialGradient`) with 90px Gaussian blur, giving Cupertino dark mode depth and warmth without visual noise.
- **Dynamic Header & Subtitle**: Time-of-day greeting (`AppGreeting.getGreeting()`) paired with the subtitle *"Your music, your way."* in clean Cupertino typography.
- **Upper-Right Account Control (`AccountInfoSheet`)**: Subtle 38px circular avatar with Google profile photo or fallback avatar. Tapping opens a Cupertino modal sheet displaying Google account info, live music library statistics (song, album, artist counts), Google Drive connection state, and last sync timestamp.
- **Continue Listening Card (`ContinueListeningCard`)**:
  - Derived from active playback state or recent history.
  - Frosted glass container with rounded corners (`22px`), 1px translucent border, and subtle drop shadow.
  - Square album artwork (102px, radius 16px).
  - Left metadata: Song title (bold 16sp), artist name (13sp), album name (12sp), and technical badge pill (`FLAC · 706 kbps`, `MP3 · 320 kbps`).
  - Right circular play/pause action button (48px circle, translucent fill).
  - Bottom scrubber bar: Thin progress line with circular white thumb dot, current position (`1:43`), and remaining time (`-2:20`).
- **Horizontal Carousels for All Music Sections (`HomeArtworkCard`)**:
  - **Favorites**: Horizontal artwork carousel of favorited songs.
  - **Recently Played**: Horizontal carousel derived from actual playback history.
  - **Recently Added**: Horizontal carousel of recently added/indexed music (replaces legacy dense vertical rows).
  - **Albums & Playlists**: Horizontal carousels of square artwork cards.
  - **Artists**: Horizontal carousel of circular artist items.
- **Refined Section Headers (`SectionHeader`)**: Bold section titles with subtle "See All >" affordances and title chevrons where appropriate.
- **Content-Aware Geometry**: Sections only render when real data exists; empty states render clean Cupertino invitations to connect Drive.

### 2. Now Playing Experience (Visual Authority)
Located in `lib/features/playback/presentation/pages/now_playing_page.dart`:
- **Cupertino Top Bar**: Features a centered "Now Playing" title, left dismiss chevron (`chevron_down`), and right top queue access button (`text_badge_plus`), perfectly matching the Now Playing visual authority screenshot.
- **Vertical gestures** dismiss Now Playing or open the queue when the content fits. Pulling down updates a transform through one controller listener. On compact screens, vertical scrolling keeps the controls reachable.
- **Artwork backdrop** uses a shared 256-pixel decode for the player and lyrics panel and filters the image layer. The foreground cover keeps its own decode size.
- **Proportional Artwork Presentation**: Floating artwork sized responsively (`min(width * 0.64, height * 0.33)`) with rounded corners (22px) and subtle drop shadow.
- **Left-Aligned Track Metadata**: Song title, artist name, and album name with Cupertino typography and ellipsis truncation.
- **Technical Pill Badge**: Displays exact audio format and bitrate (e.g., `FLAC · 706 kbps`, `MP3 · 320 kbps`) in a translucent rounded pill container with adaptive background contrast (`isDarkBackground`).
- **More Actions Button**: Circular translucent Cupertino button (`...`) opening a contextual action sheet (Album, Artist, Lyrics, Share, Favorite, Download).
- **Apple Music-Style Scrubber**: Custom Material `SliderTheme` + `Slider` with thin 4px track, small 6px thumb radius, white active track, and semi-transparent gray inactive track. Uses selective Material import (`show Slider, SliderTheme, SliderThemeData, ...`).
- **5-Control Playback Cluster**:
  - Shuffle toggle with active highlight.
  - Previous track (skip-style `backward_end_fill` icon) / restart track (threshold > 3s).
  - Prominent 74px translucent circular Play/Pause button.
  - Next track button (skip-style `forward_end_fill` icon).
  - Repeat mode toggle (off, all, one).
- **Bottom Action Bar** (border-outlined circular buttons with translucent fill):
  - Heart icon for instant favorites toggling.
  - Lyrics icon (`quote_bubble`) opening synchronized `LyricsSheet`.
  - Queue icon (`text_badge_plus`) opening the dynamic playback queue sheet.

### 3. Docked Mini-Player Integration
Located in `lib/features/playback/presentation/widgets/mini_player.dart`:
- Floating translucent card with horizontal insets (14px) and rounded corners (16px) docked right above bottom tabs.
- Features small album artwork (44px, radius 10px), title, artist, play/pause toggle, and next track button.
- Subtle 2px bottom progress bar indicator tracking playback position in real-time.
- Tapping opens the fullscreen Now Playing modal.

### 4. Lyrics Engine & Synchronization (Word-Level & Line-Level Upgraded)
Located in `lib/features/lyrics/`:
- **Parser (`LrcParser`)**:
  - Millisecond precision (`[mm:ss.xxx]` and `<mm:ss.xxx>`) and centisecond precision (`[mm:ss.xx]` and `<mm:ss.xx>`).
  - **`v1:<timestamp>word` Format Parsing**: Recognizes `v1:` prefixes and word-level angle bracket timestamps (`<00:18.812>Look <00:19.063>in...`), reconstructing clean human-readable line text without raw markup.
  - Retains punctuation, apostrophes (`I'm`, `Don't`), and whitespace naturally.
  - Offset tag parsing (`[offset:+/-ms]`).
  - Multi-timestamps on a single line (e.g., `[00:10.00][00:20.00] Chorus line`).
  - Strict range validation and graceful fallback for malformed or out-of-order tokens without runtime exceptions.
  - Plain text fallback for unsynchronized lyrics.
- **Deterministic Lyric Priority**:
  1. `LyricSource.embeddedSynced` (ID3 SYLT/SLT/synced tags)
  2. `LyricSource.embeddedPlain` (ID3 USLT/plain lyrics)
  3. `LyricSource.sidecarLrc` (Discovered `.lrc` sidecar file with matching base name)
  4. `LyricSource.none`
- **Database Schema**:
  - `Lyrics` table (`@DataClassName('LyricRow')`) with track foreign key.
  - `LyricLines` table (`@DataClassName('LyricLineRow')`) with millisecond timestamp and sequential index.
  - `LyricWords` table (`@DataClassName('LyricWordRow')`) with `lineId`, `wordIndex`, `startMs`, `endMs`, and index `idx_lyric_words_line`.
- **Domain Synchronization (`TrackLyrics`, `LyricLine`, `LyricWord`)**:
  - `TrackLyrics.findActiveIndex(Duration position)` / `calculateActiveIndex(lines, position)`: Canonical line-level active index derivation.
  - `LyricLine.findActiveWordIndex(Duration position)`: Returns the active word index for word-synced lines.
  - `LyricWord.progressAt(Duration position)`: Computes normalized `[0.0, 1.0]` progress for in-place highlighting.
- **Word-Level Highlight Renderer (`WordSyncedLyricText`, `LyricLineWidget`)**:
  - **Word-level sweep** uses a bounded ticker on an active row when playback is advancing. Paused and buffering states use the reported audio position directly. A partially revealed word keeps the feathered mask.
  - **Subtle Luminescence & Contrast Accent**: Active words sung in real-time gain an ethereal glow shadow (`blurRadius: 8.0`) that settles into crisp solid white upon completion.
  - **Simulated Line-Wide Sweep for Standard LRC**: Standard LRC lines without word timestamps render a continuous 14px feathered horizontal light sweep across their estimated duration, keeping non-word-synced lyrics dynamic and fluid.
  - **Repaint boundaries** isolate active row paint from the rest of the sheet.
- **Cupertino Lyrics Sheet (`LyricsSheet`)**:
  - Now Playing follows the live track. A library preview stays on the selected track and uses playback controls when that track is current.
  - The lazy timed list anchors directly at off-screen rows and aligns their measured center near 45% of the viewport. Adjacent lines can animate. Seeks and dense updates can jump directly.
  - Manual scrolling pauses auto-follow. **Current line** restores following without seeking. Tapping a timed line seeks when its track is playing.

### 5. Google Drive integration and sync

The [audit and remediation record](google-drive-sync-audit.md) links each pre-fix symptom to its regression coverage.

- **Drive listings.** The folder picker follows every page, includes shared-drive roots, and resolves accessible folder shortcuts. Recursive discovery handles supported audio shortcuts using target metadata and avoids cycles by target folder ID. Any incomplete Drive listing or repeated page token fails the run before local removals.
- **Folder checkpoints.** A folder enters the visited set after all its pages succeed. Its discovered files, child-to-parent links, and remaining folder queue commit together in SQLite. A stop or failure within a folder discards that folder’s partial listing. Startup recovery continues at the first unfinished folder. Completed discovery needs zero additional listing requests on resume, while outstanding audio, sidecar, or artwork work can still make remote requests.
- **Saved roots and account changes.** Roots, runs, and pruning are scoped to the active Google account. Signing out keeps indexed music and offline files available. Sign-out and account changes cancel an active run. Startup only attempts recovery with a restored Google sign-in.
- **Stop and force resume.** Drive list and media requests use an abort trigger. Each track transaction commits its checkpoint and preserves its original outcome on resume. Schema v11 persists Force Full Re-sync mode, so resume still processes the remaining tracks in force mode. Cancellation before reconciliation completes rolls back local removals.
- **Incremental metadata.** Unchanged audio reuses local metadata. A changed checksum, newer remote timestamp, or difference between known sizes refreshes audio metadata. Missing core metadata triggers repair. Discovery deduplicates by file ID and writes unchanged status in bounded SQLite batches.
- **Lyrics and artwork.** Sidecar fingerprints are tracked separately from audio. Editing or removing a matching LRC updates the stored lyrics without an audio download when the audio is unchanged. Embedded lyrics take priority. Sidecar downloads occur before the track transaction and remain retryable on failure. Album artwork prefers embedded bytes, then the matching folder cover. Folder parent links survive resume and cover files are refreshed by Drive fingerprint or force sync.
- **Failures and reconciliation.** A run with any unresolved track or media failure remains resumable and keeps the previous last-sync timestamp. Remote removals occur after complete discovery and successful processing. Track deletion and related lyrics, favorites, playlist memberships, queue entries, history, and aggregate updates share a transaction. Changed pinned tracks are refreshed from the downloaded audio. Unreferenced audio files are cleaned after sync and during cache maintenance.
- **Progress.** Subscribers receive the current state with their live subscription already attached. Progress counts unique audio IDs. A new or resumed run clears old failure text. The sheet offers Resume Sync for stopped and retryable failures.
- **Schema v11 upgrade.** The migration adds force mode, sidecar and artwork fingerprints, and embedded-artwork paths. Legacy unfinished discovery snapshots are reset because their folder checkpoints may be incomplete. A legacy source with a matching saved account email can retain its root. A source saved under the old generic account label keeps its indexed music and offline audio, and the active account selects a folder before syncing. A successful scan claims the legacy tracks it verifies on Drive.

### 6. Android Media Notifications & Lock Screen Playback Controls
Located in `lib/app/bootstrap/bootstrap.dart`, `lib/core/services/notification_permission_service.dart`, and `lib/features/playback/data/repositories/playback_repository_impl.dart`:
- **AudioService Registration (`AudioService.init`)**:
  - Initializes background foreground service with `AudioServiceConfig` (channel `com.blackpirateapps.musii.channel.audio`, small icon `drawable/ic_stat_music`).
  - Graceful fallback for test/desktop runtime where native host channel is not present.
- **Android 13+ Notification Permission (`POST_NOTIFICATIONS`)**:
  - `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>` declared in `AndroidManifest.xml`.
  - Proactive request during bootstrap via `NotificationPermissionService.requestNotificationPermissionIfNeeded()`.
  - Toggle & settings shortcut available in `SettingsPage` under `PLAYBACK`.
- **MediaSession & Lock Screen Controls**:
  - Bidirectional controls for `skipToPrevious`, `play`/`pause`, `skipToNext`, `stop`, `seek`, `fastForward`, `rewind`, `skipToQueueItem`, `setShuffleMode`, and `setRepeatMode`.
  - Full queue synchronization (`queue.add`) keeping Android Auto, Wear OS, and system notification queues synchronized.
  - Safe local artwork file validation before supplying `artUri: Uri.file(...)`.
  - **Restored State Broadcasting**: `restoreSavedState()` must call `_broadcastPlaybackState()` after restoring the queue and media item. Without this, Android has no `PlaybackState` to render and the media notification will not appear after app restart.
  - **Artwork Resolution in Queue Restore**: `artworkPath` is not stored in the `Tracks` table — it is resolved dynamically via `MetadataNormalizationService.computeArtworkKey()` + `AppFileSystem.getArtworkCacheFile()`. The `_resolveArtworkPath()` helper in `MusiiAudioHandler` mirrors this pattern for restored tracks.

### 7. Wi-Fi Pre-Caching, In-Memory Artwork Retention & Folder Artwork Discovery
Located in `lib/core/services/connectivity_service.dart`, `lib/features/cache/`, `lib/features/library/presentation/widgets/album_artwork.dart`, `lib/features/metadata/domain/services/folder_artwork_resolver.dart`, and `lib/features/playback/`:
- **Folder-Based Album Artwork Extraction**:
  - When audio tracks lack embedded artwork (ID3 `APIC`, Vorbis picture, MP4 `covr`), Google Drive discovery captures folder image files (`.jpg`, `.jpeg`, `.png`, `.webp`).
  - `FolderArtworkResolver` resolves the best candidate image:
    1. Case-insensitive standard names in immediate folder: `cover`, `folder`, `front`, `albumart`, `album`, `artwork`.
    2. Case-insensitive standard names in parent folder (for multi-disc releases like `CD1/`, `CD2/`).
    3. Any valid image file in immediate folder.
    4. Any valid image file in parent folder.
  - Downloaded to `_fileSystem.getArtworkCacheFile(artworkKey)` ahead of database transactions, saving the path directly to `Albums.artworkPath`.
  - All tracks in the album automatically inherit the artwork path dynamically via `_resolveArtworkPath`.
- **Wi-Fi Pre-Caching Engine**:
  - When connected to Wi-Fi/Ethernet, automatically pre-fetches the next up to 3 upcoming queue tracks sequentially in background without interrupting playback.
  - In-flight download deduplication (`_inFlightDownloads`) in `CacheRepositoryImpl` prevents duplicate network downloads and concurrency race conditions.
- **In-Memory Artwork Retention**:
  - `AlbumArtwork` calculates target thumbnail dimensions via `cacheWidth` and `cacheHeight` (clamped to 64–800px) with `gaplessPlayback: true`.
  - `PaintingBinding.instance.imageCache` is expanded to 256MB capacity (2,000 textures) to eliminate pop-in re-decoding during fast scrolling.
  - `cacheExtent: 600.0` on sliver scrollviews retains viewport boundary layouts.

### 8. Playback Queue Engine & Context-Aware Reordering (Q1–Q4)
Located in `lib/features/playback/domain/entities/playback_state.dart`, `lib/features/playback/data/repositories/playback_repository_impl.dart`, `lib/features/playback/presentation/pages/queue_page.dart`, and `lib/features/library/presentation/widgets/track_overflow_sheet.dart`:
- **Unique QueueItem Identity**: Every item in the queue wraps a `Track` inside a `QueueItem` entity featuring a unique `id` (`qi_${timestamp}_${counter}_${trackId}`). This allows duplicate tracks to coexist in the playback queue safely without key collisions, ambiguous reordering, or inadvertent multi-item deletions.
- **Non-Disruptive Drag-and-Drop Reordering**: `QueuePage` renders upcoming tracks via `ReorderableListView.builder` using custom drag handles (`CupertinoIcons.line_horizontal_3`). Reordering modifies the upcoming sequence instantly while the currently playing track continues playback uninterrupted.
- **Custom Drag Proxy Decorator**: When lifting a queue item during drag, `proxyDecorator` scales the tile to `1.02` with an 8dp elevation shadow and theme-aware card backdrop (`0xFF2C2C2E` dark, `systemBackground` light), delivering iOS Apple Music tactile polish.
- **Context-Aware Track Action Sheet (`TrackActionContext`, `showTrackActionSheet`)**: Reusable track overflow sheet adapting options based on source (`queue`, `nowPlaying`, `library`, `album`, `artist`, `playlist`, `search`, `favorites`). Queue context exposes "Play Now", "Play Next", and destructive "Remove from Queue".
- **Long-Press Gestures & Tactile Haptics**: Long-pressing any song row or queue item triggers `HapticFeedback.mediumImpact()` and opens the contextual action sheet. Dragging, reordering, and dismissals provide subtle haptic confirmations (`lightImpact` / `selectionClick`).
- **Sequential "Play Next" Semantics**: `MusiiAudioHandler` maintains a `_playNextCount` counter that ensures consecutive "Play Next" calls insert tracks in chronological requested order (`A -> D -> E -> B -> C`) rather than reverse stack order.
- **Swipe-to-Remove & Safe Clear Up Next**: Swipe left on any up-next item triggers a `Dismissible` with a red destructive background and trash icon. "Clear Up Next" safely flushes upcoming tracks without stopping or resetting the currently playing song.
- **SQLite Queue Persistence**: Queue order and item identities are durably written to the `playback_queue` Drift table and restored during app cold start (`restoreSavedState()`).

### 9. Theme Architecture & Dynamic Dark/Light Mode
Located in `lib/app/theme/app_theme.dart`, `lib/app/app.dart`, `lib/features/settings/`, and `lib/app/bootstrap/providers.dart`:
- **Dynamic Platform Brightness Tracking**: `MusiiApp` mixes in `WidgetsBindingObserver` to listen to system `didChangePlatformBrightness()` events, resolving brightness dynamically from `View.maybeOf(context)?.platformDispatcher.platformBrightness ?? WidgetsBinding.instance.platformDispatcher.platformBrightness`.
- **System & Manual Modes (`AppThemeMode`)**: Supports `Follow System` (default), `Dark Mode`, and `Light Mode`, persisted in SQLite via `SettingsRepository` and exposed reactively through Riverpod `themeModeProvider`.
- **Atmospheric Dark Aesthetics**: Dark mode applies `Color(0xFF0C0D12)` scaffold background across all screens with atmospheric twilight glows, frosted glass cards (`ContinueListeningCard`, `MiniPlayer`), and dark Cupertino navigation bars.
- **Cupertino Action Sheet Selection**: Settings > Appearance provides an interactive Cupertino action sheet allowing immediate theme switching and feedback.

### 10. Last.fm Scrobbler Integration (Real-Time Now Playing & Offline-First Batching)
Located in `lib/features/last_fm/`, `lib/core/storage/secure_credential_store.dart`, `lib/core/database/tables.dart`, and `lib/features/playback/data/services/last_fm_playback_coordinator.dart`:
- **Clean Architecture & Schema v8**:
  - Upgraded Drift schema from v7 to v8 introducing `LastFmAccounts`, `PendingScrobbles`, and `ScrobbleHistory` tables with SQLite index `idx_pending_scrobbles_status` and `idx_scrobble_history_time`.
  - Pure domain entities: `LastFmAccount`, `ScrobbleSettings`, `PendingScrobble`, `ScrobbleHistoryItem`.
  - Hardware-backed AES KeyStore security: `SecureCredentialStore` (`FlutterSecureCredentialStore`) stores 32-character session keys and custom API credentials with `AndroidOptions(resetOnError: true)`. Secrets are never stored in plain SQLite text or SharedPreferences.
- **Production Last.fm 2.0 API Client (`LastFmApiClient`)**:
  - Canonical MD5 request signing (`generateSignature`) sorting parameters alphabetically excluding `format`, `callback`, and `api_sig`, with full multi-byte UTF-8 string encoding support.
  - Endpoints: `auth.getToken`, browser approval redirect URL generator (`buildAuthUrl`), `auth.getSession`, `user.getInfo`, `track.updateNowPlaying`, and batch `track.scrobble` (up to 50 tracks per request).
  - Error mapping: HTTP 200 Last.fm error codes (code 4/9/14 -> `LastFmAuthenticationFailure`, code 29 -> `LastFmRateLimitFailure`, code 11/16 -> `LastFmNetworkFailure`).
- **Canonical Scrobble Eligibility Rules (`ScrobbleEligibilityService`)**:
  - Minimum track duration: Strictly $\ge 30$ seconds.
  - Threshold requirement: $\min(\text{duration} / 2, 240\text{s})$ (50% of track or 4 minutes, whichever comes first).
  - Track validation: Non-empty track title and artist name required.
- **Non-Blocking Playback Coordination (`LastFmPlaybackCoordinator`)**:
  - Listens to audio player transitions via `MusiiAudioHandler`.
  - Dispatches `track.updateNowPlaying` asynchronously on start without stalling audio pipeline.
  - Tracks playback position: upon reaching the canonical threshold, queues the scrobble locally and emits an event on `onScrobbleSuccess`.
  - Replay / repeat-one detection: when track position jumps from $>10$s back to $<2$s, a new legitimate listening session is spawned with fresh Now Playing and independent scrobble eligibility.
  - Session deduping: guarantees an ongoing playback session is scrobbled exactly once.
- **Offline-First Synchronization (`LastFmSyncService`)**:
  - Scrobbles are written to `PendingScrobbles` immediately.
  - If online, uploads immediately. If offline, scrobbles remain safely queued in SQLite across app restarts and crashes.
  - Reactive `ConnectivityService` watcher debounces internet return and flushes pending queue in batches of 50.
  - Successfully synced scrobbles move atomically to `ScrobbleHistory` and increment account total count.
  - If Last.fm rejects a session with code 9/14 (auth revoked/expired), the account transitions to `reauthRequired` and pending scrobbles transition to `failed_reauth` to prevent retry storms.
- **Cupertino Presentation & User Interface**:
  - Settings root `SERVICES` section displaying Last.fm connection status.
  - `LastFmSettingsPage`: Clean Cupertino views for disconnected (intro card, connect button, API credential config dialog), connecting (browser authorization instructions, complete button), and connected (user profile avatar, username hero, real-time scrobbling toggle, Now Playing toggle, pending queue link with counter badge, scrobbles history link, and disconnect alert).
  - `PendingScrobblesPage`: Displays offline queue items with metadata and status pills (`Waiting`, `Syncing…`, `Retry scheduled`, `Requires reconnect`), plus a manual "Sync Now" button.
  - `ScrobbleHistoryPage`: Chronological list of submitted tracks with relative time formatting (`Just now`, `Yesterday`, `MMM d`).
  - `NowPlayingPage`: Ambient, non-intrusive "✓ Scrobbled" badge rendered adjacent to the technical format badge once a song crosses the threshold.

### 11. Inline Synced Lyrics Experience (Now Playing Screen Integration)
Located in `lib/features/playback/presentation/widgets/now_playing_inline_lyrics.dart`, `lib/features/playback/presentation/pages/now_playing_page.dart`, `lib/features/lyrics/presentation/widgets/`, `lib/features/settings/`, and `lib/app/bootstrap/providers.dart`:
- **Production Integration & Zero-Mock Architecture**:
  - Tightly coupled to Musii's canonical lyrics engine (`TrackLyrics`, `LyricLine`, `LyricWord`), real playback stream (`playbackPositionProvider`), and Drift database (`trackLyricsProvider`).
  - Completely free of mock data, fake lyric text, fake synchronization timers, and simulated playback states.
- **Dedicated Settings Switch & Independence**:
  - Managed via `SettingsRepository` (`getInlineLyricsEnabled()`, `setInlineLyricsEnabled(bool)`) backed by the SQLite `AppSettings` table (`key: 'inline_lyrics_enabled'`), defaulting to `true`.
  - Exposed via `inlineLyricsEnabledProvider` (`StateNotifierProvider<InlineLyricsNotifier, bool>`).
  - Toggleable in Settings > `LYRICS` section with a clean Cupertino switch and subtitle (`Show synchronized lyrics on the Now Playing screen`).
  - **Strict Product Distinction**: Turning inline lyrics OFF collapses the Now Playing lyric presentation immediately (`AnimatedSize` + `AnimatedOpacity` to height 0) while leaving underlying lyrics data intact. The full `LyricsSheet` modal remains independently accessible at all times via the action bar lyrics button.
- **Continuous Vertical Scrolling Reel & 3-Line Contextual Flow**:
  - Sits seamlessly between track metadata (title, artist, favorite button) and the playback scrubber, constrained to a fixed-height container (108px max height on regular screens, 72px on compact screens $<620$px) to guarantee zero scrubber jumping.
  - Enclosed in a vertical gradient `ShaderMask` (soft 14px top and bottom edge fades) so lines emerge and dissolve without edge clipping.
  - When playback advances from line $N$ to $N+1$, the entire column glides smoothly upward by one line pitch (36px) over 380ms with `Curves.easeOutCubic`:
    - Upcoming line physically rolls up from the bottom preview slot into the center spotlight while progressively expanding (scale $0.72 \to 1.0$) and brightening ($0.38 \to 1.0$) into pure white active typography.
    - Active line physically rolls up into the previous line slot while scaling down ($1.0 \to 0.72$) and dimming ($1.0 \to 0.24$).
    - Previous line glides past the top gradient fade and dissolves.
  - During rapid scrubber seeks ($|\Delta index| > 1$), snaps directly to the target destination without spinning intermediate lines.
- **Apple Music-Style Vocal Dots (`● ● ●`) & 3..2..1 Countdown**:
  - During instrumental intros (from 0:00 until the first lyric) and mid-song instrumental breaks ($\ge 3.0$s silence between lines):
    - The center slot features three elegant rounded dots (`●  ●  ●`).
    - **Ambient Breathing Phase** ($>3$s until vocals): The dots gently oscillate in opacity (0.18 to 0.65) with a smooth audio-synchronized harmonic wave.
    - **Countdown Phase** ($\le 3$s until vocals): The dots sequentially ignite to 100% white with a tactile spring pulse on the beat:
      - 3s before vocals: Dot 1 lights up (`● ○ ○`)
      - 2s before vocals: Dot 2 lights up (`● ● ○`)
      - 1s before vocals: Dot 3 lights up (`● ● ●`)
      - 0s (Vocals begin): The dots smoothly roll upward into history and the upcoming lyric line glides into the center spotlight in lockstep.
    - **Upcoming Lyric Preview**: The upcoming lyric sentence remains previewed in the bottom slot at 38% opacity throughout the instrumental section, giving full lyrical context.
- **Vsync-Extrapolated Word-by-Word Animation & Line Sweep Control**:
  - Leverages `LyricLineWidget` and `WordSyncedLyricText` directly in the center spotlight.
  - Word-synced lyrics smoothly highlight character-by-character via GPU shader mask with active vocal glow and 60/120 FPS vsync extrapolation.
  - For line-synced lyrics without word timestamps, `enableSimulatedLineSweep: false` is configured for inline display to present high-contrast, crisp active typography without synthetic progression sweeps, reserving simulated line sweep for the full `LyricsSheet`.
- **Interactivity & Accessibility**:
  - Tapping the inline lyric container immediately opens the canonical `LyricsSheet` scrolled directly to the active line via `showLyricsSheet(context, track)`.
  - Wrapped in Flutter `Semantics(label: 'Current lyric: ${line.text}')` during active singing, and `Semantics(label: 'Vocals start in $sec')` / `Semantics(label: 'Instrumental section')` during instrumental passages for complete screen reader accessibility.

---

## 4. Important Pitfalls, Caveats & Solutions

1. **Drift Column Naming Shadowing**:
   - In Drift table declarations, defining `TextColumn get text => text()();` shadows the builder method `text()`. Always use `TextColumn get content => text().named('text')();` to map the column name cleanly.
2. **Matcher vs Drift Import Ambiguity**:
   - Both `package:drift/drift.dart` and `package:flutter_test/flutter_test.dart` export `isNotNull` and `isNull`. In test files, always use:
     ```dart
     import 'package:drift/drift.dart' hide isNotNull, isNull;
     ```
3. **Drift Class Name Collision**:
   - Always annotate Drift table definitions with `@DataClassName('<Entity>Row')` (e.g., `@DataClassName('TrackRow')`, `@DataClassName('LyricRow')`, `@DataClassName('SyncRunRow')`) to prevent clashes with pure domain entities.
4. **Cupertino Navigation Bar Duplicate Titles**:
   - `CupertinoSliverNavigationBar` renders two `Text` widgets (collapsed and expanded large title). Use `find.text(...), findsWidgets` in widget tests rather than `findsOneWidget`.
5. **Playlist Reordering Index**:
   - When moving items in `PlaylistRepositoryImpl.reorderPlaylistTracks(playlistId, oldIndex, newIndex)`, do not apply an off-by-one decrement in the repository layer; the repository operates on target index slots directly.
6. **Auth Stream Cold Start — Broadcast Stream Initial Value**:
   - `GoogleAuthRepository._userStreamController` is a broadcast `StreamController` that only emits on sign-in/sign-out events. On cold app start, `watchCurrentUser()` must first yield the current user (via `getCurrentUser()` which calls `signInSilently()` + DB fallback) before forwarding the stream. Without this, `currentUserProvider` stays `null` and the homepage shows the "Connect Google Drive" empty state even when already signed in.
7. **AudioService Platform Channel Binding in Tests**:
   - `AudioService.init` interacts with Android native platform channels (`flutter.baseflow.com/permissions/methods`, `com.ryanheise.audioservice`). In unit and widget tests, avoid calling raw `AudioService.init` without mock platform channels; `MusiiAudioHandler` can be instantiated directly or overridden via `musiiAudioHandlerProvider.overrideWithValue(...)` or `playerStateProvider.overrideWith(...)`.
8. **Stale Audio Prevention & Track Loading State in Playback Pipeline**:
   - When switching tracks or restoring state, `just_audio.AudioPlayer` may retain the previous audio file or be in an idle state while the new track is being fetched. `MusiiAudioHandler` maintains `_loadedTrackId` and `_loadingTrackId`. When `play()` / `resume()` is triggered from the Now Playing screen, MiniPlayer, or lock screen, it validates that `_loadedTrackId == target.id`. If not loaded (or if loading), it never calls `_player.play()` on stale audio; instead it executes `loadAndPlayTrack(target)` to ensure the currently displayed track is loaded and played. Furthermore, `_player` stream events are guarded during track transitions so stale track positions, durations, or premature `ready` states do not overwrite the loading track's snapshot.
9. **MaterialLocalizations in Cupertino Widget Tests with ReorderableListView / Dismissible**:
   - Material widgets such as `ReorderableListView` and `Dismissible` check for `MaterialLocalizations`. When testing Cupertino pages containing these widgets in isolated test harnesses, provide `localizationsDelegates: const [DefaultMaterialLocalizations.delegate, DefaultCupertinoLocalizations.delegate, DefaultWidgetsLocalizations.delegate]` to the test `CupertinoApp`.
10. **Synchronous Favorite Status in Action Sheets**:
    - Avoid `await ref.read(isTrackFavoriteProvider(id).future)` inside modal action sheet openers, as awaiting stream completion introduces an asynchronous microtask delay that delays popup rendering. Instead, query synchronous state via `ref.read(isTrackFavoriteProvider(id)).value ?? false` or pass a `Consumer` inside the dialog.
11. **Discovery State Persistence & Cancellation Locks**:
    - When interrupting an active sync session to switch folders, always request cancellation via `SyncCancellationToken` and await `_activeSyncCompleter!.future` before modifying sync state or database records. This guarantees the previous sync's atomic transaction, file deletions, and `_isSyncRunning` teardown complete cleanly before the new folder sync begins. Furthermore, never overwrite `DiscoveredFiles` without scoping by `syncRunId`, ensuring resumed syncs can accurately bypass remote Google Drive scans when `discoveryCompleted == true`.
12. **Cupertino Dynamic Theme Resolution & WidgetsBindingObserver**:
    - `CupertinoApp.router` requires explicit `CupertinoThemeData` to update when system brightness toggles. Hardcoding `theme: AppTheme.lightTheme` prevents brightness inheritance. `MusiiApp` registers a `WidgetsBindingObserver` to trigger reactive frame rebuilds upon `didChangePlatformBrightness()`, dynamically supplying `AppTheme.darkTheme` or `AppTheme.lightTheme` according to user settings and device state.
13. **Canonical Album Identity, Multi-Format Tag Extraction & Reconciliation (Schema v7)**:
    - **Issue**: In music libraries with FLAC, WAV, MP3, and M4A audio files, duplicate album cards frequently appeared when tracks featured guest artists (e.g., "Daft Punk feat. Julian Casablancas") or belonged to compilation/soundtrack releases, because audio parsers defaulted to track artist rather than reading true album artist tags. Furthermore, third-party parser `audio_metadata_reader` suffered severe format limitations:
      - Dropped `albumArtist` completely for MP3 files (ID3v2 `TPE2`/`TXXX`).
      - Ignored MP4/M4A `aART` and `cpil` atoms.
      - Dropped `ALBUM ARTIST` (with space) in FLAC Vorbis comments (only checked `ALBUMARTIST`).
      - Contained a bug where null bytes were prepended to ID3 `TXXX` values (`\x00ALBUM ARTIST`).
      - Completely lacked RIFF `id3 ` / `INFO` chunk parsing for WAV files.
    - **Solution**:
      - **Low-Level Tag Supplement Parser (`TagSupplementReader`)**: Implemented a high-speed format-aware binary tag parser (`lib/features/metadata/data/datasources/tag_supplement_reader.dart`) that parses FLAC (Vorbis comments with and without spaces, ensemble, orchestra, band, compilation flags, skipping ID3v2 headers), WAV (RIFF chunk walker for `id3 `, `ID3 `, `LIST/INFO` `IAAR`/`IART`, and leading ID3v2 headers), MP3 (ID3v2 parser for `TPE2`, `TXXX:ALBUM ARTIST`, `TCMP`), and MP4/M4A (`moov/udta/meta/ilst` atom parser for `aART`, `cpil`, `----` custom reverse-DNS boxes). Strips embedded null bytes and normalizes artist names.
      - **Ingestion Pipeline Matching**: In `MusicLibraryRepositoryImpl`, track ingestion assigns `meta.albumArtist ?? effectiveAlbumArtist` directly to `Tracks.albumArtist`. When `meta.albumArtist` is missing, existing albums with the same `normalizedTitle` are checked for compatible artist prefixes or substrings. When a subsequent track supplies the canonical album artist, the existing album record is upgraded in-place.
      - **Schema v7 Database Migration & Reconciler (`reconcileDuplicateAlbums`)**: Upgraded Drift schema to v7 (`lib/core/database/app_database.dart`). The reconciliation engine groups all albums by `normalizedTitle`, sorts candidates by root artist length, and groups them via transitive compatibility (matching any member in a subgroup). It elects the canonical winning album artist (giving priority to known album artists and base artist names), reassigns tracks, updates surviving album metadata, and deletes duplicate album rows.
      - **Library Aggregate & Zombie Pruning**: At the conclusion of sync, `_recomputeLibraryAggregates()` prunes 0-track zombie albums and 0-track/0-album orphaned artists to maintain referential integrity.
14. **CupertinoTabBar Dynamic Opacity & Artist Artwork Resolution Pipeline**:
    - **CupertinoDynamicColor withOpacity() Gotcha**: Never call `.withOpacity()` directly on `CupertinoDynamicColor` instances (like `CupertinoColors.systemBackground.withOpacity(0.9)`). Because `CupertinoDynamicColor` extends `Color`, `.withOpacity()` strips dynamic brightness resolution and evaluates the light base ARGB value (`0xFFFFFFFF`), rendering a white background in dark mode. Always resolve brightness dynamically via `CupertinoTheme.brightnessOf(context) == Brightness.dark` before calculating bar translucent colors.
    - **Artist Artwork Resolution & Deezer Integration**: Audio file tags (MP3 ID3, FLAC Vorbis, MP4 covr) only embed album artwork. To prevent artist profiles from defaulting to empty initial-letter tiles, `MusicLibraryRepositoryImpl` applies a two-stage pipeline: (1) Immediate local fallback to the artist's first indexed album artwork for 100% offline visual presentation; (2) Background download of official artist photography via Deezer's public API (`https://api.deezer.com/search/artist?q={name}`) with zero API key requirement, caching files under `AppFileSystem.getArtworkCacheFile('artist_{normalizedName}')` and updating `Artists.artworkPath` in SQLite reactively.
15. **Folder-Based Album Artwork Discovery, Track-Level Persistence & Schema v10 Migration**:
    - **Issue**: Previously, songs whose album artwork was fetched from an external image in the same folder (`cover.jpg`, `folder.png`, etc.) on Google Drive rather than embedded in audio tags only displayed artwork on the Album Details page (`AlbumDetailPage`), but failed to appear everywhere else (Home screen carousels, Search results, Playback Queue, MiniPlayer, and Now Playing screen).
    - **Root Causes**:
      1. *Album vs Track Artwork Storage*: The `Albums` table stored `artworkPath`, which `AlbumDetailPage` read directly from the `Album` entity. However, the `Tracks` table lacked an `artworkPath` column, and all other views relied on `Track.artworkPath`.
      2. *Artist Key Discrepancy*: Other repositories and streams (`watchAllTracks`, `SearchRepositoryImpl`, `FavoriteRepositoryImpl`, `RecentlyPlayedRepositoryImpl`, `PlaylistRepositoryImpl`) resolved artwork dynamically via `_resolveArtworkPath(row.albumName, row.artistName)`. When external folder art was cached, it was keyed using `effectiveAlbumArtist` (or `album.artistName`). Whenever a track had a distinct track artist (e.g., featured artists, guest vocalists, compilations, or after `reconcileDuplicateAlbums()`), the key looked up for `(albumName, trackArtist)` did not match the cached file `(albumName, albumArtist)` and returned `null`.
      3. *Sync Ingestion Disconnect*: When folder art was resolved during `_recomputeLibraryAggregates()`, existing tracks already written to SQLite were never updated with `artworkPath`.
      4. *Playback Queue Loss*: `PlaybackRepositoryImpl.playAlbum()` loaded tracks into `MusiiAudioHandler` without propagating `album.artworkPath` to tracks that lacked embedded artwork.
      5. *Incremental Sync Gap*: When `discoveryAlreadyComplete` was true (incremental/resumed syncs), `folderParentMap` was not populated from SQLite, preventing multi-disc folder lookups.
    - **Solution & Architecture (Schema v10)**:
      1. *Drift Schema v10*: Added `TextColumn get artworkPath => text().nullable()();` to the `Tracks` table (`lib/core/database/tables.dart`, `app_database.dart`). Added migration from schema version $< 10$ with `addColumn(tracks, tracks.artworkPath)` and an immediate SQLite backfill:
         ```sql
         UPDATE tracks 
         SET artwork_path = (SELECT albums.artwork_path FROM albums WHERE albums.id = tracks.album_id)
         WHERE tracks.album_id IS NOT NULL;
         ```
      2. *Track Ingestion & Checkpointing*: In `_upsertTrackAndRelationsInTx()`, tracks are persisted with `artworkPath: Value(effectiveArtwork)` in `TracksCompanion`.
      3. *Post-Sync Aggregate Backfill*: In `_recomputeLibraryAggregates()`, after downloading any newly discovered folder images or resolving candidate images, all tracks belonging to the album are updated in SQLite via `update(tracks)..where((t) => t.albumId.equals(album.id)).write(TracksCompanion(artworkPath: Value(currentArtwork)))`.
      4. *Duplicate Album Reconciliation Propagation*: In `reconcileDuplicateAlbums()`, when duplicate or single albums are reconciled, all surviving tracks (both moved from duplicate albums and already belonging to the survivor) missing artwork inherit `survivorArt`.
      5. *Incremental Sync Parent Map*: In `syncLibrary()`, when `discoveryAlreadyComplete` is true, `folderParentMap` is populated from `DriveFolders` table so folder hierarchies are preserved.
      6. *Multi-Key Fallback Resolution*: In all repository track mappers (`MusicLibraryRepositoryImpl`, `FavoriteRepositoryImpl`, `RecentlyPlayedRepositoryImpl`, `SearchRepositoryImpl`, `PlaylistRepositoryImpl`), `_mapDbTrackToEntity` evaluates:
         `row.artworkPath ?? _resolveArtworkPath(row.albumName, row.albumArtist) ?? _resolveArtworkPath(row.albumName, row.artistName)`.
      7. *Playback Inheritance & Media Item Resolution*: `PlaybackRepositoryImpl.playAlbum()` and `playPlaylist()` inherit `album.artworkPath` / `playlist.artworkPath` for any queue tracks lacking artwork. In `_MusiiAudioHandler`, `_toMediaItem()`, `loadAndPlayTrack()`, `playNext()`, `playLast()`, and `_restoreSavedState()` all resolve track artwork through the fallback chain, ensuring lock screen, Bluetooth metadata, system notifications, and in-memory queue items always render folder artwork.
16. **`flutter_secure_storage` 11.2+ `AndroidOptions` Migration**:
    - In `flutter_secure_storage: ^11.2.0`, the deprecated constructor parameter `encryptedSharedPreferences: true` was removed. The Android implementation uses standard Android KeyStore with AES-GCM encryption out of the box. Always instantiate using `const AndroidOptions(resetOnError: true)` to avoid runtime argument exceptions and ensure auto-recovery if the KeyStore key is corrupted or invalidated across OS upgrades.
17. **Drift `QueryStream` 0-Duration Cleanup Timers in Riverpod Tests**:
    - Drift's `QueryStream._onCancelOrPause` schedules a zero-duration timer (`Timer(Duration.zero, ...)`) when a stream subscription is canceled so rapid rebuilds don't prematurely discard cached query results. In Flutter widget tests, if a Drift query stream provider (such as `lastFmAccountProvider`) is watched by a page being tested, disposing the test `ProviderContainer` upon widget unmount schedules this timer. If the test completes without pumping or without overriding the provider, Flutter's test runner fails the test with `!timersPending`. In isolated widget tests that test non-Last.fm functionality (e.g. `SettingsPage` appearance tests), override `lastFmAccountProvider.overrideWith((ref) => Stream.value(null))` or pump zero-duration microtasks to avoid pending timers.
18. **Last.fm Parameter Indexing Protocol**:
    - The Last.fm 2.0 API requires parameter indexing (`track[0]`, `artist[0]`, `timestamp[0]`) only when submitting batches of multiple tracks. Submitting a single track with indexed `[0]` parameters causes Last.fm to return empty responses or parse errors on some endpoints. `LastFmApiClient.scrobbleBatch` dynamically selects un-indexed parameter names (`track`, `artist`) when `batch.length == 1`, and indexed parameter names when `batch.length > 1`.
19. **Last.fm Custom API Key & Shared Secret Precedence**:
    - `LastFmRepositoryImpl.getAuthUrl` must be asynchronous to query `SecureCredentialStore` (`_getEffectiveApiKey()`). If `getAuthUrl` synchronously only referenced build-time `--dart-define` (`envApiKey`), user-entered custom credentials would be omitted from the browser authorization URL (`https://www.last.fm/api/auth?api_key=&token=...`), causing Last.fm to reject requests with `"Invalid API key"`. Custom credentials stored in secure hardware storage take precedence over empty or fallback build-time keys.
    - **`cleanCredential` vs `cleanHex`**: `LastFmApiClient.cleanCredential(input)` strips double/single quotes, whitespace, and hidden unicode (`\u200B`, `\uFEFF`, `\u00A0`) but preserves dashes and underscores. This is critical because Last.fm request tokens (from `auth.getToken`) are base64-url/alphanumeric strings containing `-` and `_` (e.g. `l6hr-QpRjScViMEFhrmVZPteTgLFi-K7`), not 32-char hex like API keys. Never apply hex-only stripping to tokens.
    - **Canonical Auth Base URL**: `buildAuthUrl` uses `https://www.last.fm/api/auth/` (with trailing slash). It throws `ArgumentError` if `apiKey` is empty after cleaning, preventing silent generation of invalid URLs.
    - **Timer-Based Copy Feedback**: The "Copy Auth Link" button in `LastFmSettingsPage` uses a synchronous `setState(() => _copiedLink = true)` with `unawaited(Clipboard.setData(...))` for instant UI feedback, and a cancellable `Timer` (stored as `_copiedLinkResetTimer`) instead of `Future.delayed` to reset the label after 2 seconds. The timer is cancelled in `dispose()` to prevent `!timersPending` assertions in widget tests.
    - In widget tests, `_showConfigDialog()` is async and loads current API credentials from the repository before presenting the dialog, requiring `lastFmRepositoryProvider` to be overridden with `MockLastFmRepository`.
20. **`AlbumArtwork` Finite Sizing Constraints & Dynamic AspectRatio / Grid Collages**:
    - **Issue**: In `ArtistCard` (3:4 aspect ratio), `PlaylistCard` (1:1 aspect ratio and 2x2 collage), `ArtistDetailPage`, and `PlaylistDetailPage`, callers supply `size: double.infinity` so `AlbumArtwork` expands to fill the parent flex or aspect ratio box. In Dart, calling `(size * dpr).round()` on `double.infinity` throws an unhandled `UnsupportedError: Cannot convert to int: Infinity`, completely breaking the widget build and preventing artist portraits and generated playlist collages from appearing in the Library tabs. Furthermore, in `_buildFallback()`, passing `fontSize: size * 0.4` triggers Flutter's `assert(fontSize.isFinite)` check.
    - **Solution**: `AlbumArtwork` guards `size.isFinite`. When finite, it computes exact target cache thumbnails (`(size * dpr).round().clamp(64, 800)`) and sets `width: size, height: size`. When non-finite (`double.infinity`), it bounds the thumbnail cache size to `800`, passes `width: null, height: null` with `fit: BoxFit.cover` (allowing smooth expansion into tight `AspectRatio` and `Expanded` bounds), and resolves fallback initials font sizes dynamically via `LayoutBuilder` clamped between 12px and 72px. Additionally, `PlaylistCard` and `PlaylistDetailPage` deduplicate distinct album artworks from tracks so multi-album playlists render 2x2 collages while single-album playlists render clean full-size covers.
21. **Sub-Second SQLite Timestamp Truncation & Millisecond Run ID Tie-Breaking in Sync Engine**:
    - **Sub-Second Truncation Bug in `_classifyTrack`**: Google Drive API returns RFC 3339 timestamps with millisecond fractions (e.g., `2026-09-15T12:00:00.456Z`), but Drift/SQLite stores `DateTime` as an integer unix epoch in whole seconds. A direct comparison `remote.modifiedTime.isAfter(local.driveModifiedAt)` evaluates to `true` whenever remote has non-zero milliseconds, falsely marking unchanged songs as `updateModified` and triggering redundant re-downloads. `_classifyTrack` truncates both remote and local timestamps to second precision (`millisecondsSinceEpoch ~/ 1000`) before evaluating modification.
    - **Same-Second Sync Run Disambiguation**: When sync runs start within the same integer second, their `startedAt` SQLite timestamps are identical. Queries ordering by `OrderingTerm.desc(tbl.startedAt)` without tie-breaking can return older runs arbitrarily. To guarantee deterministic resolution of the most recent sync session, all `syncRuns` queries (`getLastSyncSession`, `recoverInterruptedSyncIfNeeded`, `resumeSync`, `syncFromSavedFolder`, `syncLibrary`) order by `[(tbl) => OrderingTerm.desc(tbl.startedAt), (tbl) => OrderingTerm.desc(tbl.id)]`, leveraging the monotonic millisecond epoch embedded in `tbl.id` (`sync_${timestampMs}`).
22. **Playback State Granularity, Repaint Boundaries & High-Frequency Stream Isolation**:
    - **Root Cause of UI Lag**: `playerStateProvider` emitted a new `PlayerStateSnapshot` on every audio position tick (~200ms). Because 13 consumer widgets across the app (including `RootNavigationShell`, `HomePage` with 7 carousels, `LibraryPage`, `SearchPage`, `NowPlayingPage`, `MiniPlayer`, and `ContinueListeningCard`) watched `playerStateProvider` without `.select()`, the entire widget hierarchy, navigation tab bar, and heavy Gaussian blurs (`BackdropFilter` sigma 20-90) rebuilt repeatedly at 5 FPS while music played.
    - **Selective Watching (`.select()`)**: Root pages and structural layouts now select only the specific immutable properties they require (e.g., `s.value?.currentTrack?.id`, `s.value?.isPlaying`, `s.value?.queueIndex`). When position ticks occur, Riverpod verifies selector equality and skips rebuilding entire parent trees.
    - **Dedicated Scrubber Isolation & 60 FPS Interpolation**: Real-time progress bars (`_MiniPlayerProgressBar`, `_NowPlayingScrubber`, `_ContinueListeningScrubber`) were extracted into isolated leaf `ConsumerWidget`s watching `playbackPositionProvider`. In `_NowPlayingScrubber`, an `AnimationController` smoothly lerps between 200ms position ticks at 60 FPS for a silky Apple Music-grade scrubber feel without triggering parent rebuilds.
    - **Repaint Isolation**: Static heavy blur backdrops in `NowPlayingPage` and `MiniPlayer` are wrapped in `RepaintBoundary` to prevent canvas repainting when scrubbers or play/pause buttons update.
    - **Non-blocking Artwork Verification**: Removed synchronous `File.existsSync()` checks from widget build methods (`AlbumArtwork`, `NowPlayingPage`, `LyricsSheet`), delegating missing-file fallbacks to Flutter's asynchronous `Image.file(..., errorBuilder: ...)` to prevent UI-thread I/O stalls during fast flings.
    - **Image Cache Tuning**: Balanced `PaintingBinding.instance.imageCache.maximumSizeBytes` to 128 MB (down from 256 MB) to prevent garbage collection pauses on memory-constrained devices while retaining smooth scroll performance.
23. **Vsync-Driven Word-by-Word Lyrics Extrapolation, Repaint Boundaries & Test Safety**:
    - **Issue**: `just_audio` emits `positionStream` updates at discrete ~200ms intervals (5 FPS). In word-synced lyrics where words typically last 200–400ms, the highlight jumped abruptly across 3–5 characters in a single frame. Furthermore, watching `playbackPositionProvider` in `LyricsSheet` triggered rebuilds of the entire modal sheet, the heavy sigma-50 `BackdropFilter`, and all 50+ lines every 200ms, and using dual `Text` widgets inside a `Stack` caused `find.text()` in widget tests to fail due to duplicate candidate widgets.
    - **Solution**:
      1. **Sub-Millisecond Vsync Extrapolation**: Extracted audio clock forward extrapolation into `_LyricLineWidgetState` using an `AnimationController` that advances smoothly at 60/120 FPS while `isPlaying == true`. Reconciles incoming audio drift with anchor damping, and automatically stops when paused or after 500ms without ticks (ensuring widget tests with `pumpAndSettle()` settle cleanly without pending timers).
      2. **Feathered Leading-Edge Shader Mask**: Replaced hard `ClipRect` with a GPU `ShaderMask(blendMode: BlendMode.srcIn)` rendering a single `Text` widget with an 8px soft feathered gradient wipe and active vocal glow, eliminating both glyph slicing and widget tree duplication.
      3. **Simulated Line Sweep for Standard LRC**: For lines without word-level timing, applies a 14px feathered progressive sweep across the estimated line duration, bringing dynamic Apple Music styling to standard LRC lyrics.
      4. **Isolated Active Line Repaint Boundary**: Wrapped active lines in `RepaintBoundary` and removed position watches from `LyricsSheet.build()`, ensuring only the active line repaints on vsync frames with 0% CPU overhead on inactive lines.
24. **Inline Lyrics Continuous Reel, Viewport Height Stability & Timer-Free Countdown Synchronization**:
    - **Scrubber Jump Prevention & Continuous Reel**: Dynamically wrapped text lines in a music player can alternate between single-line and multi-line heights as words change, causing the playback scrubber and transport buttons to bounce vertically. `NowPlayingInlineLyrics` encloses the lyric display within a fixed-height layout box (`108.0` max height) with soft top and bottom GPU gradient edge masking (`ShaderMask`). Line advancement uses a single coordinated `_InlineLyricsReel` translating a 4-line stack vertically by 36px over 380ms (`Curves.easeOutCubic`), ensuring the upcoming line physically rolls into the center spotlight without teleportation artifacts.
    - **Audio-Clock Synchronized Countdown (Zero Ticker Overhead)**: Rather than running an active `Timer` or infinite `AnimationController.repeat()` which would stall widget tests with pending timers, `_VocalCountdownDots` computes harmonic wave breathing and 3..2..1 countdown directly from the incoming audio timestamp `(targetMs - currentMs)`. When audio pauses or seeks, countdown state and breathing phase react deterministically.
    - **Drift `QueryStream` Timers in Now Playing Tests**: Integrating `NowPlayingInlineLyrics` into `NowPlayingPage` caused existing widget tests in `now_playing_page_test.dart` to open a Drift SQLite query stream via `trackLyricsProvider(track.id)`. Because Drift's `QueryStream._onCancelOrPause` schedules a zero-duration cleanup timer (`Timer(Duration.zero, ...)`), tests asserting `tester.binding.hasScheduledFrame` or tearing down without an explicit stream override failed with `!timersPending`. All `NowPlayingPage` test harnesses must explicitly override `trackLyricsProvider.overrideWith((ref, trackId) => Stream.value(null))` when lyrics are not under test.
    - **Word-by-Word Audio Clock Binding & Dwell Protection**: Passing a non-null `position` to `LyricLineWidget` suppresses its internal `ref.watch(playbackPositionProvider)` subscription (`final Duration rawPos = widget.position ?? ref.watch(playbackPositionProvider);`). When the parent widget (`NowPlayingInlineLyrics`) throttles its own rebuilds and only updates state on slot changes, passing `widget.currentPosition` caused `LyricLineWidget` to freeze mid-sentence after its 500ms vsync extrapolation controller completed. Omitting `position` (leaving it `null`) allows `LyricLineWidget` to watch `playbackPositionProvider` directly within its isolated `RepaintBoundary`, continuously refreshing its anchor on every audio clock tick and extrapolating at 60/120 FPS to the very end of any sentence without triggering parent rebuilds. Additionally, instrumental gap detection enforces a minimum 800ms post-vocal dwell window and $\ge 3500$ms threshold, preventing lines from prematurely collapsing into countdown dots while words are still ringing out.
25. **Google Drive API `$fields` Whitespace Rejection, Onboarding Sync Route Lifecycle & Stream Cold Start**:
    - **Issue**: On fresh app installations, after signing in and selecting a Google Drive music folder, library synchronization appeared to never start or failed blankly without displaying errors, dumping the user onto an empty Home screen.
    - **Root Causes**:
      1. *Google Drive API v3 Whitespace Sensitivity*: Google Drive API v3 rejects spaces in `$fields` parameter strings (e.g. `'files(id, name, parents)'` or `'nextPageToken, files(...)'`) with HTTP 400 `Invalid field selection`. In `GoogleDriveRepositoryImpl`, both `listFolders` and `listAudioFilesRecursively` contained spaces after commas and inside parens, causing initial folder navigation and recursive scans to crash with HTTP 400.
      2. *Onboarding Route Teardown Race*: In `DriveFolderPickerPage`, `_startSync` previously opened `SyncProgressSheet` on its own local navigation context, awaited `syncLibrary(...)`, and subsequently executed `Navigator.popUntil(context, (r) => r.isFirst)`. When `syncLibrary` threw an exception (e.g., HTTP 400), `_startSync` resumed and popped the progress sheet immediately, hiding the failure banner and leaving the user on an unpopulated Home screen.
      3. *Sync Stream Cold Start*: `watchSyncProgress()` in `MusicLibraryRepositoryImpl` was backed by a broadcast `StreamController`. Riverpod's `syncProgressProvider` received `AsyncLoading(null)` upon subscription on cold start, defaulting to `const SyncProgress()` (`phase: idle`) and presenting a blank sheet with 0 files until the next stream event.
      4. *Home Empty State Disconnect*: When signed in without tracks, `HomePage` rendered an empty state with a "Go to Settings" button having an empty callback (`onPressed: () {}`).
    - **Solution**:
      1. *Compact `$fields`*: Strictly stripped all whitespace from Google Drive `$fields` parameters (`'files(id,name,parents)'` and `'nextPageToken,files(id,name,mimeType,size,modifiedTime,md5Checksum,parents)'`).
      2. *Decoupled Route & Sheet Presentation*: In `DriveFolderPickerPage`, `_startSync` first pops the picker navigation stack back to the root, displays `SyncProgressSheet` on `rootNavigatorKey.currentContext`, and runs `syncLibrary` in the background via `unawaited()`. This ensures the sheet remains mounted on the root context across errors and accurately presents `SyncPhase.failed` with the error description and retry controls.
      3. *Cold Start Yield & Immediate Scan Phase*: Refactored `watchSyncProgress()` to an `async*` generator that immediately yields `_currentProgress` upon subscription before yielding stream events. Emitted `SyncPhase.scanning` immediately at the entry of `syncLibrary()`, and emitted `SyncPhase.failed` in `syncFromSavedFolder()` when no folder ID is stored.
      4. *Actionable Empty States*: Wired `HomePage` empty state when signed in to "Select Music Folder", navigating directly to `DriveFolderPickerPage(showSyncSheetOnSelect: true)`. In Settings and Account Info sheets, if no folder ID is configured, sync buttons route to `DriveFolderPickerPage`.

---

## 5. Development & Verification Commands

```bash
# Get dependencies
flutter pub get

# Run Drift code generation
dart run build_runner build --delete-conflicting-outputs

# Verify static analysis (must be 0 issues)
flutter analyze

# Run all tests
flutter test

# Auto-format Dart source code
dart format .
```

---

## 6. CI/CD & Build Workflows

Both Android workflows pin Flutter 3.50.1 and use Java 17, Gradle 9.5.0, Android Gradle Plugin 9.3.1, and Kotlin 2.4.20. When updating Flutter in CI, update both workflow pins and check the Android toolchain against that Flutter release.

### 1. Build APK Workflow (`.github/workflows/build-apk.yml`)
- **Trigger**: Push to `main`, PR, or manual `workflow_dispatch`.
- **Keystore Secrets**: Automatically checks for `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, and `KEY_PASSWORD`.
- **Output Artifact**: `musii-release-apk` (`build/app/outputs/flutter-apk/app-release.apk`).
- **Fallback**: Gracefully uses debug signing if secrets are not populated.

### 2. Signing Report Workflow (`.github/workflows/signing-report.yml`)
- **Trigger**: Manual `workflow_dispatch` or push affecting Android configs.
- **Function**: Executes Gradle `signingReport` and `keytool` on the release keystore to output SHA-1, SHA-256, and MD5 fingerprints.
- **Output**: Posts a Markdown summary directly to `$GITHUB_STEP_SUMMARY` and uploads `android-signing-report` artifact.
