# Musii — AI Engineering Handoff Document

> **Document Version**: 1.2.0  
> **Target Audience**: Incoming AI Coding Assistants & Human Software Engineers  
> **Last Verified**: September 2026  
> **App Identifier**: `com.blackpirateapps.musii`  
> **Test Status**: 51 / 51 Passing (`flutter test`), 0 Analyzer Warnings (`flutter analyze`)

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
   - `database/`: Drift SQLite setup, 20 tables with `@DataClassName` annotations and schema v2 migration.
2. **Domain (`lib/features/*/domain/`)**:
   - Pure Dart entities (`Track`, `Album`, `Artist`, `Genre`, `Playlist`, `CacheEntry`, `PlayerStateSnapshot`, `TrackLyrics`, `LyricLine`, `LyricSource`).
   - Repository interfaces declaring business contracts.
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

### 1. Now Playing Experience (Visual Authority)
Located in `lib/features/playback/presentation/pages/now_playing_page.dart`:
- **Vibrant Blurred Artwork Aesthetic**: Real-time blurred album artwork backdrop with a lighter translucent gradient overlay (`0x40`/`0x80`/`0xB3` opacity) so album art colors bleed through vividly.
- **Proportional Artwork Presentation**: Floating artwork sized responsively (`min(width * 0.62, height * 0.32)`) with rounded corners and subtle drop shadow.
- **Left-Aligned Track Metadata**: Song title, artist name, and album name with Cupertino typography and ellipsis truncation.
- **Technical Pill Badge**: Displays exact audio format and bitrate (e.g., `FLAC · 706 kbps`, `MP3 · 320 kbps`) in a translucent rounded pill container.
- **More Actions Button**: Circular translucent Cupertino button (`...`) opening a contextual action sheet (Album, Artist, Lyrics, Share, Favorite).
- **Apple Music-Style Scrubber**: Custom Material `SliderTheme` + `Slider` with thin 4px track, small 6px thumb radius, white active track, and semi-transparent gray inactive track. Uses selective Material import (`show Slider, SliderTheme, SliderThemeData, ...`).
- **5-Control Playback Cluster**:
  - Shuffle toggle with active highlight.
  - Previous track (skip-style `backward_end_fill` icon) / restart track (threshold > 3s).
  - Prominent 74px translucent circular Play/Pause button.
  - Next track button (skip-style `forward_end_fill` icon).
  - Repeat mode toggle (off, all, one).
- **Bottom Action Bar** (border-outlined circular buttons with translucent fill):
  - Heart icon for instant favorites toggling.
  - Lyrics icon (`square_arrow_up`) opening synchronized `LyricsSheet`.
  - Queue icon (`text_badge_plus`) opening the dynamic playback queue sheet.

### 2. Lyrics Engine & Synchronization
Located in `lib/features/lyrics/`:
- **LRC Parser (`LrcParser`)**:
  - Millisecond precision (`[mm:ss.xxx]`) and centisecond precision (`[mm:ss.xx]`).
  - Multi-timestamps on a single line (e.g., `[00:10.00][00:20.00] Chorus line`).
  - Offset tag parsing (`[offset:+/-ms]`).
  - Strict range validation skipping invalid lines (`seconds >= 60`, `minutes >= 60`).
  - Plain text fallback for unsynchronized lyrics.
- **Deterministic Lyric Priority**:
  1. `LyricSource.embeddedSynced` (ID3 SYLT/SLT/synced tags)
  2. `LyricSource.embeddedPlain` (ID3 USLT/plain lyrics)
  3. `LyricSource.sidecarLrc` (Discovered `.lrc` sidecar file with matching base name)
  4. `LyricSource.none`
- **Database Schema v2**:
  - `Lyrics` table (`@DataClassName('LyricRow')`) with track foreign key and cascade deletion.
  - `LyricLines` table (`@DataClassName('LyricLineRow')`) with millisecond timestamp and sequential index.
- **Cupertino Lyrics Sheet (`LyricsSheet`)**:
  - Synchronized auto-scrolling highlighting active line with translucent inactive lines.
  - Tap-to-seek: Tapping any lyric line instantly seeks audio playback.
  - Manual scroll detection with "Return to current line" button.

### 3. Google Drive Integration & Recursive Sync
Located in `lib/features/google_drive/` and `lib/features/library/`:
- OAuth 2.0 authentication via `google_sign_in: ^6.2.2`.
- Recursive folder traversal finding audio files (`.mp3`, `.flac`, `.m4a`, `.aac`, `.wav`, `.ogg`) and sidecar `.lrc` files.
- Atomic sync transaction diffing local SQLite database with cloud state.
- Offline audio caching with LRU eviction and atomic temporary file staging (`.partial` -> destination).

### 4. Android Media Notifications & Lock Screen Playback Controls
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
   - Always annotate Drift table definitions with `@DataClassName('<Entity>Row')` (e.g., `@DataClassName('TrackRow')`, `@DataClassName('LyricRow')`) to prevent clashes with pure domain entities.
4. **Cupertino Navigation Bar Duplicate Titles**:
   - `CupertinoSliverNavigationBar` renders two `Text` widgets (collapsed and expanded large title). Use `find.text(...), findsWidgets` in widget tests rather than `findsOneWidget`.
5. **Playlist Reordering Index**:
   - When moving items in `PlaylistRepositoryImpl.reorderPlaylistTracks(playlistId, oldIndex, newIndex)`, do not apply an off-by-one decrement in the repository layer; the repository operates on target index slots directly.
6. **Auth Stream Cold Start — Broadcast Stream Initial Value**:
   - `GoogleAuthRepository._userStreamController` is a broadcast `StreamController` that only emits on sign-in/sign-out events. On cold app start, `watchCurrentUser()` must first yield the current user (via `getCurrentUser()` which calls `signInSilently()` + DB fallback) before forwarding the stream. Without this, `currentUserProvider` stays `null` and the homepage shows the "Connect Google Drive" empty state even when already signed in.
7. **AudioService Platform Channel Binding in Tests**:
   - `AudioService.init` interacts with Android native platform channels (`flutter.baseflow.com/permissions/methods`, `com.ryanheise.audioservice`). In unit and widget tests, avoid calling raw `AudioService.init` without mock platform channels; `MusiiAudioHandler` can be instantiated directly or overridden via `musiiAudioHandlerProvider.overrideWithValue(...)` or `playerStateProvider.overrideWith(...)`.

---

## 5. Development & Verification Commands

```bash
# Get dependencies
flutter pub get

# Run Drift code generation
dart run build_runner build --delete-conflicting-outputs

# Verify static analysis (must be 0 issues)
flutter analyze

# Run all tests (all 46 tests must pass)
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
