# Musii — AI Engineering Handoff Document

> **Document Version**: 1.0.0  
> **Target Audience**: Incoming AI Coding Assistants & Human Software Engineers  
> **Last Verified**: September 2026  
> **App Identifier**: `com.blackpirateapps.musii`

---

## 1. Executive Summary

Musii is an offline-first, Cupertino-styled personal music streaming player for Android. It connects directly to the user's Google Drive via OAuth 2.0, recursively scans and indexes their music collection into a reactive Drift SQLite database, and streams/caches audio with background audio playback, lock screen media controls, LRU cache eviction, and offline pinning.

All production code paths are 100% complete with no mock data, no fake playback, and no placeholder TODOs. Static analysis (`flutter analyze`) passes with **0 issues**, and the automated test suite (`flutter test`) passes with **100% success**.

Local builds of the APK are intentionally disallowed on this development environment per project constraints; all APK builds are delegated to the GitHub Actions CI workflow in `.github/workflows/build-apk.yml`.

---

## 2. Architecture & Design Patterns

### Architectural Style: Clean Architecture & Domain-Driven Design (DDD)
The codebase strictly adheres to standard four-layer Clean Architecture:
1. **Core (`lib/core/`)**:
   - `result/result.dart`: Sealed `Result<S, F>` functional type (`Success`, `Failure`, `fold`, `map`). Never throw raw exceptions from repository layers.
   - `error/failures.dart`: Sealed `AppFailure` hierarchy (`AuthenticationFailure`, `DriveApiFailure`, `CacheFailure`, etc.).
   - `logging/app_logger.dart`: Structured categorical logging with OAuth token redaction.
   - `constants/app_constants.dart`: Design tokens (`AppRadii`, `AppSpacing`, `AppAudioConstants`).
   - `filesystem/app_file_system.dart`: Centralized cache directory management, `.partial` file staging, and atomic commits.
   - `database/`: Drift SQLite setup, 18 tables with `@DataClassName` annotations.
2. **Domain (`lib/features/*/domain/`)**:
   - Pure Dart entities (`Track`, `Album`, `Artist`, `Genre`, `Playlist`, `CacheEntry`, `PlayerStateSnapshot`).
   - Repository interfaces declaring business contracts.
   - Domain services (`MetadataNormalizationService`).
3. **Data (`lib/features/*/data/`)**:
   - Concrete repository implementations (`GoogleDriveRepositoryImpl`, `MusicLibraryRepositoryImpl`, `CacheRepositoryImpl`, `PlaybackRepositoryImpl`, etc.).
   - Network calls via `googleapis` and `http`.
   - SQLite queries via `drift`.
   - Audio decoding via `just_audio` and `audio_service`.
4. **Presentation (`lib/features/*/presentation/`)**:
   - iOS Cupertino design components tailored for Android (`CupertinoPageScaffold`, `CupertinoNavigationBar`, `CupertinoTabBar`, `CupertinoActionSheet`).
   - State management via `flutter_riverpod` (v3).

---

## 3. Important Pitfalls, Caveats & Solutions

When continuing development on this codebase, keep the following hard-learned insights in mind:

### 1. Drift Class Name Collision
- **Problem**: In Drift, table class `Tracks` automatically generates a row class named `Track` by default. This directly clashes with the domain entity `Track`.
- **Solution**: All Drift table definitions in `lib/core/database/tables.dart` MUST use `@DataClassName('<Entity>Row')` (e.g., `@DataClassName('TrackRow')`, `@DataClassName('AlbumRow')`, `@DataClassName('ArtistRow')`). Always map between `TrackRow` and `Track` in repository implementations.

### 2. Riverpod 3 State Management
- **Problem**: `StateProvider` was removed/deprecated in Riverpod 3.x.
- **Solution**: Use `NotifierProvider` and `Notifier<T>` for mutable UI state (e.g., `SearchQueryNotifier` in `lib/app/bootstrap/providers.dart`).

### 3. Google Sign-In Versions
- **Problem**: `google_sign_in` 7.x completely broke backwards compatibility and removed the familiar `GoogleSignIn(scopes: ...)` class interface.
- **Solution**: The project uses pinned `google_sign_in: ^6.2.2` (resolving to 6.3.0), which provides standard `signIn()`, `signInSilently()`, `currentUser`, and `onCurrentUserChanged`.

### 4. Google Drive API `$fields` Parameter
- **Problem**: In the Dart `googleapis` package for Google Drive v3, calling `driveApi.files.list(fields: ...)` produces an `undefined_named_parameter` compilation error.
- **Solution**: Google APIs in Dart use `$fields` (e.g., `$fields: 'files(id, name, mimeType, size)'`).

### 5. Cupertino on Android Styling
- **Problem**: Using Material widgets like `Divider` or `Icons` inside Cupertino views breaks the iOS aesthetic and creates missing widget errors when Material is not imported.
- **Solution**: Always use Cupertino-native separators (`Container` with `CupertinoColors.separator` or `CupertinoColors.white.withOpacity(...)`) and `CupertinoIcons`.

### 6. Widget Test Stream Query Timer Flush
- **Problem**: Drift stream queries cancel asynchronously using zero-duration timers on unmount, causing `flutter test` to fail with `!timersPending`.
- **Solution**: In widget tests that mount `MusiiApp()`, unmount the tree and pump a short duration before test conclusion:
  ```dart
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 100));
  ```

---

## 4. Codebase Directory Map

```
lib/
├── main.dart                                  # App entry point, WidgetsFlutterBinding, AudioHandler init
├── app/
│   ├── app.dart                              # MusiiApp root, CupertinoApp, theme bindings
│   ├── bootstrap/
│   │   ├── bootstrap.dart                    # AppBootstrap initialization sequence
│   │   └── providers.dart                    # Riverpod dependency injection registry
│   ├── router/
│   │   └── app_router.dart                   # GoRouter configuration & shell navigation
│   └── theme/
│       └── app_theme.dart                    # Dark & Light Cupertino themes
├── core/
│   ├── constants/app_constants.dart           # Spacing, radii, audio formats, greetings
│   ├── database/
│   │   ├── app_database.dart                 # Drift database class & connection
│   │   ├── app_database.g.dart               # Generated Drift queries & row classes
│   │   └── tables.dart                       # 18 Drift table declarations with @DataClassName
│   ├── error/failures.dart                   # Sealed AppFailure hierarchy
│   ├── filesystem/app_file_system.dart       # AppFileSystem cache directories & atomic commits
│   ├── logging/app_logger.dart               # Categorized structured logger with OAuth redaction
│   └── result/result.dart                    # Sealed Result<S, F> functional error pattern
└── features/
    ├── authentication/                       # Google Sign-In & SQLite token persistence
    ├── google_drive/                         # Drive v3 REST client, recursive scan, streaming
    ├── metadata/                             # Tag extraction (audio_metadata_reader) & normalization
    ├── cache/                                # LRU cache management, atomic files, offline pinning
    ├── library/                              # Sync diffing, tracks, albums, artists, UI views
    ├── playback/                             # JustAudio, MusiiAudioHandler, player state, now playing
    ├── favorites/                            # Favorites management and reactive streams
    ├── recently_played/                      # Playback history and play count tracking
    ├── playlists/                            # Playlist CRUD and track ordering
    ├── search/                               # Multi-entity search across indexed library
    └── settings/                             # Cache size controls, sync info, theme switcher
```

---

## 5. Development & Verification Commands

```bash
# Get dependencies
flutter pub get

# Run Drift code generation
dart run build_runner build --delete-conflicting-outputs

# Verify static analysis (must be 0 issues)
flutter analyze

# Run unit and widget tests
flutter test

# Auto-format Dart source code
dart format .
```

---

## 6. How to Extend the Application

### Adding Support for Another Cloud Provider (e.g. OneDrive, Dropbox, WebDAV)
1. In `lib/core/database/tables.dart`, the `MusicSources` table already supports a `type` column.
2. Implement a new remote repository implementing the contract pattern used by `GoogleDriveRepository`:
   - Methods: `listFolders(parentId)`, `listAudioFilesRecursively(rootFolderId)`, `getStreamUri(fileId)`.
3. In `MusicLibraryRepositoryImpl`, wire the new provider into the synchronization pipeline.

### Adding an Audio Equalizer
1. Add an equalizer UI sheet under `lib/features/playback/presentation/widgets/`.
2. Connect to `just_audio`'s `AndroidEqualizer` audio effect:
   ```dart
   final equalizer = AndroidEqualizer();
   final player = AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [equalizer]));
   ```
3. Expose equalizer presets (Rock, Pop, Classical, Flat, Bass Boost) via a `NotifierProvider`.

### Adding Synchronized Lyrics (LRC)
1. Add a `LyricsRepository` under `lib/features/playback/`.
2. Scan for `.lrc` sidecar files in Google Drive during recursive sync, or query embedded USLT/SYLT tags in `MetadataExtractor`.
3. In `NowPlayingPage`, add a toggle to switch the album artwork view to a scrolling synchronized lyrics view driven by `playerState.position`.

---

## 7. CI/CD & Build Workflows

### 1. Build APK Workflow (`.github/workflows/build-apk.yml`)
- **Trigger**: Push to `main`, PR, or manual `workflow_dispatch`.
- **Keystore Secrets**: Automatically checks for `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, and `KEY_PASSWORD`.
- **Output Artifact**: `musii-release-apk` (`build/app/outputs/flutter-apk/app-release.apk`).
- **Fallback**: Gracefully uses debug signing if secrets are not populated.

### 2. Signing Report Workflow (`.github/workflows/signing-report.yml`)
- **Trigger**: Manual `workflow_dispatch` or push affecting Android configs.
- **Function**: Executes Gradle `signingReport` and `keytool` on the release keystore to output SHA-1, SHA-256, and MD5 fingerprints.
- **Output**: Posts a Markdown summary directly to `$GITHUB_STEP_SUMMARY` and uploads `android-signing-report` artifact.

