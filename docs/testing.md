# Testing Suite & Verification Guide

Musii incorporates automated unit and widget test suites covering domain logic, metadata normalization, functional result error handling, and UI interactions.

---

## 1. Running Tests

### Run all tests:
```bash
flutter test
```

### Run with code coverage:
```bash
flutter test --coverage
```

### Run static code analysis:
```bash
flutter analyze
```

### Format code:
```bash
dart format --set-exit-if-changed .
```

---

## 2. Test Suite Structure

```
test/
├── unit/
│   ├── metadata_normalization_test.dart   # Tag cleaning, track prefix removal, artist deduplication
│   ├── result_and_failures_test.dart       # Sealed Result<S, F> functional error handling
│   ├── cache_and_playback_state_test.dart  # PlayerStateSnapshot, repeat modes, greeting calculation
│   └── playlist_and_search_test.dart       # Playlist model copyWith, search result emptiness
└── widget_test.dart                        # MusiiApp launch smoke test, Cupertino tab switching
```

---

## 3. Test Coverage Breakdown

### `test/unit/metadata_normalization_test.dart`
- Verifies that track numbers (`01 - `, `01. `, `[01] `, `1-01`) are stripped from song titles.
- Verifies filename fallback formatting when audio tags are missing.
- Verifies that artist aliases ("Various Artists", "V/A", "VA") map to the canonical constant.
- Verifies that SHA-256 artwork hash keys are deterministic and case-insensitive.

### `test/unit/result_and_failures_test.dart`
- Verifies `Result.success` unpacking and functional `fold` mapping.
- Verifies `Result.failure` containment of `AppFailure` instances.
- Verifies error details, HTTP status code propagation, and technical details.

### `test/unit/cache_and_playback_state_test.dart`
- Verifies `AppGreeting.getGreeting` according to current local hour.
- Verifies `PlayerStateSnapshot.hasNext` and `hasPrevious` boundary calculations.
- Verifies `AudioRepeatMode` enum parsing and default fallbacks.

### `test/unit/playlist_and_search_test.dart`
- Verifies `Playlist.copyWith` immutability and property assignment.
- Verifies `SearchResults.isEmpty` and `isNotEmpty` composite logic.

### `test/widget_test.dart`
- Pumping of `MusiiApp` wrapped in `ProviderScope`.
- Verification of Cupertino tab labels (`Home`, `Library`, `Search`, `Settings`).
- Tab navigation transitions and stream query timer cleanup.
