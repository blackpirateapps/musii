# Musii — AI Engineering Handoff Document

> **Document Version**: 1.10.0  
> **Target Audience**: Incoming AI Coding Assistants & Human Software Engineers  
> **Last Verified**: September 2026  
> **App Identifier**: `com.blackpirateapps.musii`  
> **Test Status**: 157 / 157 Passing (`flutter test`), 0 Analyzer Warnings (`flutter analyze`)

---

## 1. Executive Summary & Strict Operational Rules

Musii is an offline-first, Cupertino-styled personal music streaming player for Android. It connects directly to the user's Google Drive via OAuth 2.0, recursively scans and indexes their music collection into a reactive Drift SQLite database, and streams/caches audio with background audio playback, lock screen media controls, LRU cache eviction, offline pinning, and synchronized LRC lyrics.

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
   - `error/failures.dart`: Sealed `AppFailure` hierarchy (`AuthenticationFailure`, `DriveApiFailure`, `CacheFailure`, `DatabaseFailure`, etc.).
   - `logging/app_logger.dart`: Structured categorical logging with OAuth token redaction.
   - `constants/app_constants.dart`: Design tokens (`AppRadii`, `AppSpacing`, `AppAudioConstants`, `AppGreeting`).
   - `filesystem/app_file_system.dart`: Centralized cache directory management, `.partial` file staging, and atomic commits.
   - `database/`: Drift SQLite setup, 22 tables with `@DataClassName` annotations and schema v7 migration.
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
- **Interactive Pull-Down Gesture**: Dragging down anywhere on the screen (artwork, metadata, empty background) smoothly translates the modal downward with real-time tactile tracking, popping when pulled past the threshold (>120px) or flicked downwards (>300 px/s), and snapping gracefully back to top on early release.
- **Swipe-Up for Queue**: Swiping up when at top offset opens the Cupertino queue modal sheet.
- **Vibrant Blurred Artwork Aesthetic**: Real-time blurred album artwork backdrop with a lighter translucent gradient overlay (`0x40`/`0x80`/`0xB3` opacity) so album art colors bleed through vividly.
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
  - **In-Place Progressive Highlighting**: Completed words remain 100% active, current word progressively reveals active text via `_HorizontalFractionClipper`, future words remain muted (38% opacity). Zero text shifting and pixel-perfect glyph alignment.
  - **Fallback to Line-Level Sync**: Standard LRC lines without word timestamps render clean line-level highlighting.
  - **Symmetric Active/Inactive Line Transitions**: 280ms `Curves.easeOutCubic` animations via `AnimatedScale` (1.0 vs 0.97) and `AnimatedDefaultTextStyle`.
- **Cupertino Lyrics Sheet (`LyricsSheet`)**:
  - **45% Viewport Focal Alignment**: Uses dynamic sheet geometry (`LayoutBuilder`) with top padding (40% viewport height) and bottom padding (55% viewport height).
  - **Exact Item Geometry Positioning**: Calculates target scroll offsets via `RenderBox.localToGlobal` relative to the lyrics viewport.
  - **Cold Start & Mid-Playback Initial Positioning**: Immediate zero-duration frame jump to current line upon sheet opening part-way through playback.
  - **Smooth Viewport Movement**: 300ms `Curves.easeOutCubic` animated scrolling triggered on `activeIndex` changes.
  - **Manual Scroll Recovery & Tap-to-Seek**: User drag notifications pause auto-scroll and animate in the floating "Current line" button. Tapping "Current line" or tapping any lyric line seeks playback, snaps to the 45% focal position, and restores auto-following.

### 5. Google Drive Integration & Incremental Sync Engine (Optimized & Crash-Safe)
Located in `lib/features/google_drive/` and `lib/features/library/`:
- **Persistent Discovery & Smart Zero-Rescan Resume**:
  - Streamed discovery records discovered files directly into the `DiscoveredFiles` table in SQLite (`@DataClassName('DiscoveredFileRow')`).
  - When discovery finishes, `discoveryCompleted = true` is committed to `SyncRuns`.
  - **Smart Zero-Rescan Resume**: When `resumeSync()` or startup crash recovery (`recoverInterruptedSyncIfNeeded()`) is called after discovery has completed, the engine **completely bypasses remote Google Drive directory scans**, loads discovered files directly from SQLite in milliseconds with **0 network requests**, and immediately resumes metadata extraction from the exact file checkpoint.
  - **Partial Discovery Continuation**: If sync is stopped *during* folder discovery (`discoveryCompleted == false`), `pendingFoldersJson` and `visitedFoldersJson` store the exact folder traversal state. Resuming continues traversing the remaining folder queue without rescanning from the root.
  - **Fresh Sync on Completion**: When a sync run is completed and the user subsequently triggers a sync ("Sync Now", "Sync Library Now", "Force Full Re-sync"), a new sync run is created that performs a fresh Drive scan and prunes obsolete discovered file rows.
- **Folder Selection During Active Sync**:
  - If a user chooses a new music folder while synchronization is actively in progress, `syncLibrary()` automatically cancels the running sync via `SyncCancellationToken`, updates status to `stopping`, and cleanly awaits termination of the active sync (`_activeSyncCompleter`).
  - Sequence numbering (`_syncSequenceNumber`) ensures rapid sequential folder selections cleanly supersede older requests.
  - The new sync runs for the newly selected root folder, prunes tracks from the previous folder during Step 6 reconciliation, and updates `MusicSources`.
- **Incremental Metadata Reuse**:
  - Stable Google Drive file identity (`driveFileId`) used as primary mapping.
  - For each discovered remote audio file, classifies into:
    - `UNCHANGED_COMPLETE`: Matches existing record in SQLite with matching modified timestamp (`!remote.modifiedTime.isAfter(local.driveModifiedAt)`), matching checksum, and complete metadata (title, format present). File size mismatch is only detected if the local record has a meaningful stored size (`fileSize > 0`). **Zero audio downloads, zero metadata parsing.** Reuses all local records.
    - `CHANGED`: Remote modification timestamp is newer, checksum differs, or file size changed (when local size is non-zero). Downloads temporary audio staging file, refreshes metadata, updates track and relations in SQLite.
    - `INCOMPLETE`: Track exists in SQLite but missing vital fields (e.g., missing title, format). Re-fetches and repairs metadata. Note: file size is NOT part of the completeness check — a track with `fileSize=0` but complete title/format is considered complete.
    - `NEW`: Completely new remote file. Full metadata extraction and relational upsert.
- **One-Tap Sync (`syncFromSavedFolder()`)**:
  - Looks up the previously configured root folder from in-memory progress → `MusicSources` table → latest `SyncRuns` record.
  - Triggers `syncLibrary()` directly without requiring the Google Drive folder picker UI.
  - Settings page "Sync Library Now" button calls this method to enable one-tap re-sync.
  - Returns `DriveApiFailure` if no folder has ever been configured.
- **Force Sync (`forceSync: true`)**:
  - When `syncLibrary(forceSync: true)` is called, ALL discovered files are added to the processing queue regardless of classification.
  - Bypasses the `unchangedComplete` optimization to force re-download and re-extraction of every file.
  - Settings page "Force Full Re-sync" button triggers this with a confirmation dialog.
  - Useful when metadata extraction logic has changed or files need complete re-indexing.
- **Atomic Work Units & Checkpoint Storage**:
  - Work unit: Single audio track processing with transactional SQLite commit.
  - Single atomic database transaction wraps:
    1. Artist upsert (`insertOnConflictUpdate`)
    2. Album upsert (`insertOnConflictUpdate`)
    3. Genre upsert (`insertOnConflictUpdate`)
    4. Track upsert (`insertOnConflictUpdate`)
    5. Lyrics saving
    6. `SyncRun` checkpoint update (`filesProcessed`, `filesAdded`, `filesUpdated`, `errorsCount`, `progressPercent`, `lastCheckpointAt`, `updatedAt`).
  - Temporary audio metadata extraction files (`.partial` / `temp_...`) are deleted immediately in `finally` blocks.
- **Stop & Resume Engine**:
  - Explicit `SyncCancellationToken` with non-blocking checks across folder scanning and item processing loops.
  - `stopSync()` requests cooperative stop, allows the current atomic item transaction to safely finish, commits checkpoint, updates session state to `stopped` (`isResumable: true`), and exits cleanly.
  - `resumeSync()` reads previous root folder and sync session, performs reconciliation, skips all completed items, and continues work.
- **Crash & Force-Close Recovery**:
  - Process death / force-stop leaves `SyncRuns` table with `status == 'running'` and accurate `lastCheckpointAt`.
  - On app launch, `recoverInterruptedSyncIfNeeded()` automatically detects interrupted unclosed sessions and resumes without restarting from zero.
  - Progress percentage in UI immediately reflects the actual completed tracks.
- **Remote Deletion Reconciliation**:
  - Full remote scan builds complete `driveFileMap`. Tracks present locally but absent on Drive are deleted from `tracks`, `cacheEntries`, and `lyrics`, and album/artist aggregates are updated.
- **Database Schema v5**:
  - `SyncRuns` table (`@DataClassName('SyncRunRow')`) with columns: `id`, `sourceId`, `rootFolderId`, `rootFolderName`, `startedAt`, `updatedAt`, `lastCheckpointAt`, `completedAt`, `status`, `phase`, `currentFile`, `errorMessage`, `progressPercent`, `filesDiscovered`, `filesProcessed`, `filesAdded`, `filesUpdated`, `filesRemoved`, `errorsCount`, `discoveryCompleted`, `pendingFoldersJson`, `visitedFoldersJson`.
  - `DiscoveredFiles` table (`@DataClassName('DiscoveredFileRow')`) with columns: `id`, `syncRunId`, `driveFileId`, `name`, `mimeType`, `size`, `modifiedTime`, `md5Checksum`, `parentFolderId`, `isLrc`.
  - Indexes:
    - `CREATE INDEX IF NOT EXISTS idx_sync_runs_status ON sync_runs(status, started_at);`
    - `CREATE INDEX IF NOT EXISTS idx_discovered_files_sync ON discovered_files(sync_run_id);`
- **UI Presentation (`SyncProgressSheet`)**:
  - Running: displays progress bar, file counts, current filename, and prominent Cupertino `Stop Sync` button.
  - Stopping: displays animated activity indicator and disables stop button.
  - Stopped: displays "Sync Stopped", "X of Y completed", and prominent Cupertino `Resume Sync` button.
  - Complete: displays "Library Synced", `Sync Now` button (to trigger incremental re-sync), and `Done` button.
  - Idle with saved folder: displays `Sync Now` button and `Done` button.

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

### 7. Wi-Fi Pre-Caching & In-Memory Artwork Retention
Located in `lib/core/services/connectivity_service.dart`, `lib/features/cache/`, `lib/features/library/presentation/widgets/album_artwork.dart`, and `lib/features/playback/`:
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

---

## 5. Development & Verification Commands

```bash
# Get dependencies
flutter pub get

# Run Drift code generation
dart run build_runner build --delete-conflicting-outputs

# Verify static analysis (must be 0 issues)
flutter analyze

# Run all tests (all 157 tests must pass)
flutter test

# Auto-format Dart source code
dart format .
```

---

## 6. CI/CD & Build Workflows

### 1. Build APK Workflow (`.github/workflows/build-apk.yml`)
- **Trigger**: Push to `main`, PR, or manual `workflow_dispatch`.
- **Keystore Secrets**: Automatically checks for `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, and `KEY_PASSWORD`.
- **Output Artifact**: `musii-release-apk` (`build/app/outputs/flutter-apk/app-release.apk`).
- **Fallback**: Gracefully uses debug signing if secrets are not populated.

### 2. Signing Report Workflow (`.github/workflows/signing-report.yml`)
- **Trigger**: Manual `workflow_dispatch` or push affecting Android configs.
- **Function**: Executes Gradle `signingReport` and `keytool` on the release keystore to output SHA-1, SHA-256, and MD5 fingerprints.
- **Output**: Posts a Markdown summary directly to `$GITHUB_STEP_SUMMARY` and uploads `android-signing-report` artifact.
