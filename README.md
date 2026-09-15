# Musii — Personal Cloud Music Player for Android

[![Build Musii Android APK](https://github.com/blackpirateapps/musii/actions/workflows/build-apk.yml/badge.svg)](https://github.com/blackpirateapps/musii/actions/workflows/build-apk.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.47.2-blue.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.13.2-blue.svg)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Musii** is an offline-capable personal music streaming player for Android, designed in an iOS Cupertino aesthetic. Musii directly connects to your Google Drive, recursively indexes your lossless audio library into a high-performance local SQLite database via Drift, and delivers background audio playback with lock screen media controls, LRU disk caching, and offline pinning.

---

## Highlights & Features

- **Personal Cloud Library**: Connect your Google Drive, pick any root directory, and recursively scan and index audio files (`FLAC`, `MP3`, `AAC`, `M4A`, `OGG`, `WAV`, `OPUS`).
- **Cupertino Design Language on Android**: Apple Music-inspired visual design adapted for modern Android phones—featuring translucent navigation bars, high-contrast typography, interactive modals, pull-to-refresh, dynamic color cards, and blurred now-playing backdrops.
- **Audio Playback Engine**:
  - Powered by `just_audio` and `audio_service`.
  - Android Foreground Media Service with MediaSession, lock screen notifications, notification actions, and headset media button dispatch.
  - Audio focus management (transient ducking and pause on phone calls).
  - High-precision audio scrubber, queue management (reorder, remove, insert next), shuffle, and repeat modes.
- **Atomic Local Caching & Offline Pinning**:
  - Two-stage atomic write pipeline (`.partial` download -> checksum verify -> atomic rename commit).
  - Configurable LRU cache quota with auto-eviction of non-pinned tracks.
  - Pin tracks for guaranteed offline playback.
- **Embedded Tag Extraction & Normalization**:
  - Embedded ID3, Vorbis, and MP4 tag extraction with embedded artwork extraction (`audio_metadata_reader`).
  - Title cleanup (stripping track number prefixes, noise, file extensions).
  - Artist alias deduplication (handling "Various Artists", "V/A", "VA").
  - Deterministic SHA-256 artwork cache keys.
- **Drift SQLite Relational Database**:
  - 18 relational tables and views indexing tracks, albums, artists, genres, playlists, playback history, favorites, cache entries, and sync logs.
  - Reactive `Stream` queries updating the UI in real time.
- **Clean Architecture & Riverpod 3**:
  - Strict separation of Core, Domain, Data, and Presentation layers.
  - Functional error handling with sealed `Result<S, F>` and `AppFailure` hierarchies (zero untyped throws in repository pipelines).
  - Declarative dependency injection with Riverpod.

---

## Architecture Overview

Musii is organized according to Clean Architecture principles:

```
lib/
├── app/                  # Application bootstrap, routing (GoRouter), and Cupertino themes
├── core/                 # Shared foundation: database, filesystem, logging, errors, Result<S, F>
└── features/             # Feature modules (Domain, Data, Presentation)
    ├── authentication/   # Google Sign-In and OAuth session persistence
    ├── google_drive/     # Drive v3 REST API, recursive directory traversal, chunked streaming
    ├── metadata/         # Tag extraction, normalization service, artwork storage
    ├── cache/            # LRU disk cache manager, offline pinning, atomic file pipeline
    ├── library/          # Music library synchronization diffing, albums, artists, tracks
    ├── playback/         # AudioHandler, JustAudio engine, queue management, player state
    ├── favorites/        # Favorite tracks repository and reactive observers
    ├── recently_played/  # Playback history, play count tracking, and recents
    ├── playlists/        # Playlist management, drag-and-drop reordering, track assignment
    ├── search/           # Multi-entity indexed search (tracks, albums, artists, playlists)
    └── settings/         # Cache size management, sync status, theme options
```

For full technical specifications, see [`docs/architecture.md`](docs/architecture.md).

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (`>= 3.47.0`)
- [Dart SDK](https://dart.dev/get-dart) (`>= 3.13.0`)
- Java Development Kit (JDK 17)
- Android Studio / Android SDK (Platform SDK 34, Build Tools 34.0.0)
- A Google Cloud Project with the Google Drive API enabled.

### Google Drive & OAuth Configuration

1. Create a project in the [Google Cloud Console](https://console.cloud.google.com/).
2. Enable the **Google Drive API**.
3. Create an **Android OAuth 2.0 Client ID**:
   - Package name: `com.blackpirateapps.musii`
   - Add your development SHA-1 certificate fingerprint (`keytool -list -v -keystore ~/.android/debug.keystore`).
4. For step-by-step setup, scopes, and instructions, see [`docs/google-drive-setup.md`](docs/google-drive-setup.md).

### Local Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/blackpirateapps/musii.git
   cd musii
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run code generation**:
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

4. **Verify code quality & tests**:
   ```bash
   flutter analyze
   flutter test
   ```

---

## Continuous Integration & APK Builds

APK builds are automated through GitHub Actions:
- Workflow file: [`.github/workflows/build-apk.yml`](.github/workflows/build-apk.yml)
- Triggers on `push` to `main`, pull requests, and manual triggers (`workflow_dispatch`).
- The pipeline sets up Java 17 and Flutter stable, runs code generation, static analysis, unit tests, builds `app-release.apk`, and uploads the release artifact.

To trigger an APK build manually:
1. Navigate to the **Actions** tab on GitHub.
2. Select **Build Musii Android APK**.
3. Click **Run workflow** on branch `main`.
4. Download the resulting `musii-release-apk` artifact.

---

## Documentation

Detailed architectural and operational documentation is located in [`docs/`](docs/):

- [`docs/architecture.md`](docs/architecture.md) — Layered architecture, Riverpod dependency injection, and data flow.
- [`docs/google-drive-setup.md`](docs/google-drive-setup.md) — Google Cloud OAuth 2.0 configuration and Drive scopes.
- [`docs/playback.md`](docs/playback.md) — AudioService, JustAudio playback pipeline, audio focus, and lock screen media session.
- [`docs/caching.md`](docs/caching.md) — Atomic file pipeline, LRU eviction algorithm, and offline track pinning.
- [`docs/database.md`](docs/database.md) — Drift SQLite schema, 18 tables, indexes, and migrations.
- [`docs/testing.md`](docs/testing.md) — Test suites, mocking guidelines, and execution commands.
- [`docs/release.md`](docs/release.md) — Release keystore setup, Gradle signing, and CI release workflow.
- [`docs/ai-handoff.md`](docs/ai-handoff.md) — Engineering handoff document for AI coding assistants and developers.

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
