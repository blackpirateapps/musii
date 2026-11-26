# Music library audit · Round 2

Audited commit `af3c7e300a0b6fb2b0bd671590c3262a5a035c09` on 26 November 2026. The installed Musii 1.0.0 APK on the USB-connected Redmi K20 Pro matched the release APK verified in [round 1](music-library-audit.md). This round covered stale sync snapshots, shared-file ownership, folder switching, artwork lifecycle, cache capacity and rollback, format detection, library navigation, and accessibility. Production code was unchanged.

## New findings

| ID | Severity | Finding | Evidence |
| --- | --- | --- | --- |
| LIB-14 | High | Resume deletes a track that returned to Drive after discovery | Sync fixture · Fixed |
| LIB-15 | High | One account can delete a shared track still indexed by another account | Two-account sync fixture · Fixed |
| LIB-16 | Medium | Failed folder change replaces the last working saved root | Sync fixture · Fixed |
| LIB-17 | Medium | Deleting the last embedded cover hides available folder artwork for one sync | Sync fixture · Fixed |
| LIB-18 | Medium | Superseded folder covers accumulate outside cache management | Filesystem fixture · Fixed |
| LIB-19 | Medium | Automatic cache limit is unenforced at download time | Android settings and cache fixture · Fixed |
| LIB-20 | Medium | Failed cache clear leaves database rows for deleted files | SQLite fault injection · Fixed |
| LIB-21 | Medium | A favorite can be removed by an action labeled Favorite | Android · Fixed |
| LIB-22 | Medium | Extensionless audio is downloaded during every incremental sync | Generated WAV and production metadata parser · Fixed |
| LIB-23 | Medium | Artist detail exposes only five songs and provides no full track list | Flutter widget test · Fixed |
| LIB-24 | Medium | Search reports No Results when its SQLite query fails | SQLite and Riverpod · Fixed |
| LIB-25 | Medium | Song overflow buttons have no accessibility label | Android accessibility tree and source · Fixed |

### LIB-14 · Resume can delete a track that is back in the selected folder

**Resolution.** Resume confirms would-be removals with a fresh Drive listing. Returning tracks keep their relationships and a failed confirmation leaves the run resumable.

**Reproduce.** Sync A and B, then favorite B, add it to a playlist, and pin its audio. Temporarily move B out of the selected folder. Start a new sync, wait until discovery finishes, and stop before reconciliation writes. Restore B to the selected folder and resume.

**Observed.** Resume performed zero Drive listing requests and reported one removal. B disappeared along with its pin, cached audio, favorite, and playlist membership. A new sync found B but did not restore those relationships.

**Expected.** A completed discovery snapshot can seed recovery. Removal should also establish that an absent track is still absent when recovery may have outlived the listing. This differs from the earlier stop-during-pagination bug, since all pages completed successfully before Stop. [Saved discovery handling](../lib/features/library/data/repositories/music_library_repository_impl.dart#L873) · [Reconciliation](../lib/features/library/data/repositories/music_library_repository_impl.dart#L1510)

### LIB-15 · One account can remove a shared file another account still indexes

**Resolution.** Schema v12 stores account memberships per Drive track. A successful sync removes only its own membership and prunes the track when the last account drops it.

**Reproduce.** Index the same Drive file ID from account A's music root and then account B's music root. Favorite the song. Remove it from A's root while it remains listed under B, switch back to A, and resync A.

**Observed.** The first sync assigned the only track record to A. B's sync completed with the same track visible. A's next sync removed the record and favorite. B's saved run still reported complete, even though local browsing no longer showed the track. Resyncing B restored the file with no favorite.

**Expected.** A shared file still indexed through B should remain in the library after A stops listing it. A single unique file ID and one `sourceId` cannot record both roots' membership. The subsequent sync preserves the original owner, and reconciliation prunes by that owner. [Track schema](../lib/core/database/tables.dart#L75) · [Source assignment](../lib/features/library/data/repositories/music_library_repository_impl.dart#L1351) · [Reconciliation](../lib/features/library/data/repositories/music_library_repository_impl.dart#L1510)

### LIB-16 · Failed folder change replaces the last working saved root

**Resolution.** The chosen root and successful timestamp are saved together during reconciliation. A failed replacement can be resumed without overwriting the working source. The account sheet displays the saved root and successful timestamp.

**Reproduce.** Complete a sync of folder A. Select folder B and return HTTP 503 for its listing. Run an ordinary sync from the saved folder.

**Observed.** After the failed attempt, the saved root is B, the last successful timestamp still belongs to A, and the indexed tracks still come from A. An ordinary saved-folder sync requests B again.

**Expected.** Keep the working root associated with its successful timestamp and index until a replacement succeeds, or represent the failed selection separately from the active library. A failed run can still be retried from its own checkpoint. [Saved-folder lookup](../lib/features/library/data/repositories/music_library_repository_impl.dart#L383) · [Source write before discovery](../lib/features/library/data/repositories/music_library_repository_impl.dart#L851)

### LIB-17 · Removing embedded artwork leaves a blank album despite available folder art

**Resolution.** Artwork preparation uses the tracks that will survive reconciliation, so removing the last embedded cover lets the same sync select folder artwork.

**Reproduce.** Index an album with two tracks and a matching `cover.jpg`. Only track A has embedded artwork. Remove A from Drive and run one normal sync. Run a second unchanged sync as a control.

**Observed.** The first sync removed A, made zero artwork requests, and left the album and surviving track with no artwork. The second sync requested the cover and restored artwork.

**Expected.** The first completed sync should pick the available folder cover when the last track with embedded art disappears. Artwork preparation checks the old track set before reconciliation removes A. [Artwork preparation](../lib/features/library/data/repositories/music_library_repository_impl.dart#L2102) · [Artwork selection](../lib/features/library/data/repositories/music_library_repository_impl.dart#L2199)

### LIB-18 · Superseded folder covers accumulate outside cache management

**Resolution.** Sync reclaims unreferenced versioned artwork after database writes. Artist fallback covers follow the current album artwork so they do not retain superseded files.

**Reproduce.** Sync one album through 12 versions of the same Drive cover, each with a different fingerprint. Delete the cover on Drive and sync. Run cache eviction with a zero-byte target and clear cached audio.

**Observed.** The current album correctly lost its removed cover, but all 12 obsolete artwork files stayed on disk. The cache size reported zero, and both maintenance operations left all 12 files in place.

**Expected.** Obsolete artwork needs reclamation or a separate storage limit. Folder artwork is stored under a versioned filename, while the current cache inventory and eviction manage audio paths. [Versioned cover writes](../lib/features/library/data/repositories/music_library_repository_impl.dart#L2132) · [Audio cache scope](../lib/core/filesystem/app_file_system.dart#L153)

### LIB-19 · Normal downloads can exceed both saved and displayed cache limits

**Resolution.** Settings exposes cache capacity controls. Normal download commits apply the stored capacity, budget the incoming file size inside the database transaction, and evict eligible older audio. Pinned and playing media remain exempt.

**Reproduce.** In a fixture, save the minimum cache limit. Seed one evictable audio file just below the default 5 GiB limit using a sparse file, then request a second three-byte song.

**Observed.** The settings repository returned the saved minimum. Neither file was evicted. The final cache size was two bytes above the 5 GiB default. On Android, the Automatic Cache Limit row displayed the default and tapping it opened no control.

**Expected.** Apply the saved limit to normal download and eviction decisions. A completed download should make room for new audio when enough cached bytes are evictable. The repository evicts before downloading with a fixed default and does not budget for the incoming payload. [Download entry point](../lib/features/cache/data/repositories/cache_repository_impl.dart#L106) · [LRU limit](../lib/features/cache/data/repositories/cache_repository_impl.dart#L310) · [Settings row](../lib/features/settings/presentation/pages/settings_page.dart#L450)

### LIB-20 · Failed cache clear leaves the database claiming deleted audio is cached

**Resolution.** Cache clear and LRU eviction commit database changes before unlinking files. A failed write retains all cached bytes and a successful retry removes them.

**Reproduce.** Cache two tracks. Inject a SQLite trigger that rejects changing a track's `is_cached` flag from true to false. Invoke Clear Cached Audio.

**Observed.** The operation returned failure and SQLite retained both cached rows and flags. One of the two files had already been deleted. Its cache lookup returned no file.

**Expected.** A partial failure should leave the database and disk consistent. The SQLite rollback cannot undo the filesystem deletion, which happens before the database writes. The LRU eviction loop uses the same ordering. [Clear implementation](../lib/features/cache/data/repositories/cache_repository_impl.dart#L378) · [LRU deletion](../lib/features/cache/data/repositories/cache_repository_impl.dart#L339)

### LIB-21 · A menu action labeled Favorite can remove an existing favorite

**Resolution.** The overflow menu waits for the live favorite state. Once available it executes the specific add or remove action shown, so a stale label cannot toggle in the opposite direction.

**Reproduce.** Favorite a track and verify it appears in Home → Favorites. Cold-launch the app, navigate to Library → Songs, and open that track's overflow menu.

**Observed.** On Android, the menu said Favorite for the already-favorited track. The text stayed unchanged after one second and after closing and reopening the menu. Tapping the displayed Favorite action removed the track from Favorites. The temporary favorite was removed as part of the repro, restoring the initial state.

**Expected.** An existing favorite should offer Remove from Favorites, or the action should wait for the current state. The menu reads a stream value once and uses a false fallback. The action then toggles the actual database state. [Overflow state and action](../lib/features/library/presentation/widgets/track_overflow_sheet.dart#L23)

### LIB-22 · Extensionless audio downloads on every incremental sync

**Resolution.** Supported MIME types supply a format when a Drive filename lacks an extension. A generated WAV now indexes once and skips all three unchanged syncs.

**Reproduce.** Serve two valid one-second PCM WAV files with MIME type `audio/wav`, one named `Extensionless` and one named `Control.wav`. Sync once, then sync three more times with identical remote fingerprints.

**Observed.** Both tracks indexed. The production metadata extractor stored an empty format for the extensionless file. Each of the three unchanged syncs downloaded only that file again.

**Expected.** Supported audio discovered by MIME type should acquire a usable format from the bytes or MIME type and skip redundant downloads when unchanged. The extractor derives the persisted format from the filename suffix, and sync treats an empty value as incomplete. [Metadata format](../lib/features/metadata/data/repositories/metadata_extractor_impl.dart#L18) · [Repair classification](../lib/features/library/data/repositories/music_library_repository_impl.dart#L630)

### LIB-23 · Artist detail has no full track list

**Resolution.** Artist details show their complete track list under Songs. The lazy list renders additional rows as users scroll and keeps each track individually actionable.

**Reproduce.** Open an artist with seven indexed guest tracks and no albums credited to that artist. Scroll through the artist detail page.

**Observed.** The page showed seven songs in its header and rendered five rows under Popular. It exposed no action to view the remaining two songs. The Play action uses the full queue, so the songs are present but cannot be individually opened from that page.

**Expected.** The artist page should offer access to the rest of its track list. A featured artist with no credited album cards has no alternate route from this screen. [Artist songs](../lib/features/library/presentation/pages/artist_detail_page.dart#L160)

### LIB-24 · Search database errors appear as No Results

**Resolution.** The search provider propagates repository failures, so the Search Error state appears when SQLite rejects a query.

**Reproduce.** Run a query that finds two songs, then inject a SQLite schema error by dropping the tracks table in an isolated fixture. Submit the same query through the app's search provider.

**Observed.** The repository returned a database failure. The provider returned a successful empty result, leading to the No Results branch rather than the page's Search Error branch.

**Expected.** Surface the error so users can distinguish a failed search from a genuine empty result. [Search provider](../lib/app/bootstrap/providers.dart#L335) · [Search UI](../lib/features/search/presentation/pages/search_page.dart#L80)

### LIB-25 · Song overflow controls have no accessible label

**Resolution.** Song overflow buttons expose a track-specific accessible label. The widget regression verifies the label in the semantic tree.

**Reproduce.** On Android, open Library → Songs and inspect the system accessibility tree for the ellipsis next to a track.

**Observed.** The overflow was a clickable node with empty text and content description. The corresponding widget supplies an icon with no semantic label. The track row itself has text, so this finding concerns the separate overflow control.

**Expected.** Each overflow button should expose an accessible name that identifies its action and track. [Song row button](../lib/features/library/presentation/widgets/song_row.dart#L163)

## Verification

- Static analysis was clean and the existing Flutter suite passed all 331 tests. The [round 2 audit probes](../tool/audit/music_library_round_two_test.dart) cover 11 scenarios, including one control where 30 simultaneous requests for the same song coalesced into one download and eviction preserved pinned and currently playing songs. Both rounds' probes passed together in a 22-scenario run.
- The device checks used the existing signed-in library. Account changes, remote deletions, HTTP faults, and the simulated 5 GiB cache ran against isolated fixtures. The sparse test file used logical length to test cache accounting.
- No Google account was switched, no Drive folder was changed, and no live cache was cleared during the device audit.

```bash
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter test --no-pub --reporter expanded tool/audit/music_library_round_two_test.dart
```
