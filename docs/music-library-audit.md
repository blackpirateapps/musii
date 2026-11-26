# Music library stress test and bug audit

Audited on 26 November 2026 at commit `af3c7e300a0b6fb2b0bd671590c3262a5a035c09`. The USB-connected Redmi K20 Pro ran Android 16, SDK 36, and Musii 1.0.0 (version code 1). The installed APK SHA-256 matched the release APK from GitHub Actions run `45690657277`. The library on the device contained 199 songs, 69 albums, and 77 artists. The audit changed no production code.

## Reproduced findings

| ID | Severity | Finding | Reproduction |
| --- | --- | --- | --- |
| LIB-01 | High | Unrelated non-Latin albums and artists collapse into the same records | SQLite and simulated Drive |
| LIB-02 | High | Distinct same-title releases merge when one artist name begins with the other | SQLite and simulated Drive |
| LIB-03 | High | Offline download can appear pinned after the download failed | SQLite and simulated Drive |
| LIB-04 | High | The audio cache accepts a payload with the wrong Drive checksum | SQLite and simulated Drive |
| LIB-05 | Medium | Exact searches miss titles with apostrophes and non-Latin text | Android and SQLite |
| LIB-06 | Medium | Searching for punctuation can match the entire library | Android and SQLite |
| LIB-07 | Medium | Album and artist details retain stale track download state | SQLite stream subscriptions |
| LIB-08 | Medium | Search retains results after library changes | Android and Riverpod with SQLite |
| LIB-09 | Medium | Home's See All buttons do nothing | Android and source review |
| LIB-10 | Medium | Artists show “0 songs” while their details list songs | Android |
| LIB-11 | Medium | Replaying a song repeatedly hides other recently played songs | SQLite |
| LIB-12 | Medium | A playlist can contain repeated additions with no way to remove an individual song | Android and SQLite |
| LIB-13 | Low | Concurrent favorite toggles fail and lose updates | SQLite |

### LIB-01 · Non-Latin metadata merges unrelated music

**Reproduce.** Sync two files tagged with different Japanese titles, artists, and albums. The fixture uses `夜空 / 青葉市子 / 檻髪` and `朝日 / 坂本龍一 / 音楽図鑑`, plus an ASCII-tagged control. Inspect Library → Albums and Artists.

**Observed and expected.** Both Japanese tracks get empty normalized titles and share artist ID `artist_` and album ID `album_::`. With the control there are three tracks, two artist records, and two album records. Every distinct artist and album should retain its own identity. Display tags on the individual tracks survive, while the grouped views combine unrelated releases.

**Cause.** The ASCII-style word filter strips these names before they become artist IDs and album keys. [Metadata normalization](../lib/features/metadata/domain/services/metadata_normalization_service.dart#L217) · [Library ingestion](../lib/features/library/data/repositories/music_library_repository_impl.dart#L1814)

### LIB-02 · Similar artist names merge distinct releases

**Reproduce.** Sync two tracks whose album tag is `Live` and whose artist tags are `The Band` and `The Bandits`. Omit both album-artist tags. List the first track first.

**Observed and expected.** The albums query returns one release containing both artists' tracks. The fixture represents two different releases and should produce two album cards. Users browsing an album or playing its track list get songs from a different release.

**Cause.** When there is no album-artist tag, the same-title candidate lookup accepts a raw prefix or substring match without an artist-name boundary. [Album candidate lookup](../lib/features/library/data/repositories/music_library_repository_impl.dart#L1851)

### LIB-03 · Failed offline download leaves a pinned track without audio

**Reproduce.** Index a song with no cached audio. Make its media request return HTTP 503 and select Download for Offline. Inspect the pin state after the download attempt finishes.

**Observed and expected.** Pinning returns success. The cache entry later becomes `failed`, the song remains pinned, and the local cache lookup returns no audio. The action sheet uses the pin flag to offer Remove Offline Download. A failure should be surfaced and the track should have a way to retry downloading. The probe simulated the media failure without changing the device's network settings.

**Cause.** The cache marks the track pinned before launching an unawaited download. The overflow action closes the sheet and has no failure feedback. [Pin operation](../lib/features/cache/data/repositories/cache_repository_impl.dart#L252) · [Overflow action](../lib/features/library/presentation/widgets/track_overflow_sheet.dart#L152)

### LIB-04 · Offline cache commits audio with the wrong checksum

**Reproduce.** Index a three-byte fixture with the Drive MD5 of `xyz`. Return the three bytes `abc` on the media request and call the normal cache download entry point.

**Observed and expected.** The repository succeeds, the final file contains `abc`, and the cache reports the song cached. With a known Drive checksum, the cache should reject mismatched bytes and preserve any prior valid copy. The same-size response demonstrates that a size check alone would miss this case.

**Cause.** The cache validates that the indexed version still matches its reservation, records the staged byte count, and renames the file without verifying the bytes against the remote checksum. [Download and commit](../lib/features/cache/data/repositories/cache_repository_impl.dart#L142)

### LIB-05 · Exact title and artist searches miss indexed music

**Reproduce.** On Android, search for the visible song title `Don't Wanna Go`, using its straight apostrophe. In the fixture, search for `Don't Stop`, `夜空`, `青葉市子`, and `檻髪`.

**Observed and expected.** Android displayed No Results for the visible title. The fixture returned no song hit for either exact title, no artist hit for `青葉市子`, and no album hit for `檻髪`. The punctuation-free control `Dont Stop` found the same fixture track. The artist and album queries can still find song rows through their display tags. Searching a display title should find the indexed entity.

**Cause.** Search normalizes query case and whitespace at the ends. The indexed title and artist keys also strip punctuation and non-Latin letters, so the stored text and the query use different representations. [Search predicates](../lib/features/search/data/repositories/search_repository_impl.dart#L88) · [Search key generation](../lib/features/metadata/domain/services/metadata_normalization_service.dart#L217)

### LIB-06 · Percent and underscore act as search wildcards

**Reproduce.** Enter a single `%` in Search. For an isolated check, seed 10,000 tracks, none containing a percent sign or underscore in their searchable text, and query each character.

**Observed and expected.** Android showed unrelated songs. The fixture returned all 10,000 tracks for each query. An ordinary text search should match literal punctuation only where it appears. An accidental punctuation query also forces the broadest result set.

**Cause.** The user query is interpolated into a bound SQLite `LIKE` pattern without escaping its wildcard characters. [Search predicates](../lib/features/search/data/repositories/search_repository_impl.dart#L96)

### LIB-07 · Open album and artist details miss track-only updates

**Reproduce.** Subscribe to an album and its artist, each with one unpinned track. Update only that track's `isPinnedOffline` field, as the cache does during a pin.

**Observed and expected.** The full-library stream reflects the pin. Neither open detail stream emits another snapshot during the 150 ms observation window. A new subscription reads the new value immediately. Open details should update when their own track data changes so context actions use current download state.

**Cause.** Each detail stream listens to its parent row and reads the child queries once per parent emission. Track-only writes leave the parent query untouched. [Album and artist streams](../lib/features/library/data/repositories/music_library_repository_impl.dart#L534)

### LIB-08 · A search query stays stale after a playlist changes

**Reproduce.** Search for a new playlist name, switch to Library, create a playlist with that name, and return to Search with the query intact. For the inverse, search for an existing playlist, delete it, and read the same results again.

**Observed and expected.** The retained query shows the old snapshot. A repository search made directly after either mutation returns the current playlist list. Changing the query refreshes the results. An unchanged query should reflect library changes so users can find newly added items and avoid opening deleted ones.

**Cause.** The future provider depends on the query and repository instance. Library writes do not invalidate the completed future. [Search provider](../lib/app/bootstrap/providers.dart#L335)

### LIB-09 · Home's See All controls leave the user on Home

**Reproduce.** From Home with an indexed library, tap See All next to Recently Played, Recently Added, or Albums.

**Observed and expected.** Each tap left the same Home screen visible. The controls should open the corresponding collection. Source inspection shows the same empty callbacks for Favorites, Artists, and Playlists. [Home section callbacks](../lib/features/library/presentation/pages/home_page.dart#L275)

### LIB-10 · Artist cards and details report zero songs for populated artists

**Reproduce.** Open Library → Artists on the audited device. Open an artist with a `0 songs` badge and tracks under Popular.

**Observed and expected.** Multiple cards read `0 songs`. One detail page also read `0 songs` and showed a numbered song under Popular. The count should include the visible song. The app reads the displayed total from the stored artist aggregate and fetches the artist's tracks separately. Fresh sync and recovery calculated the correct count in the 1,205-track fixture. The cause of the stale aggregate in this device's database was not established. [Artist mapper and queries](../lib/features/library/data/repositories/music_library_repository_impl.dart#L471) · [Artist detail](../lib/features/library/presentation/pages/artist_detail_page.dart#L104)

### LIB-11 · Replays crowd older songs out of Recently Played

**Reproduce.** Record one play for each of 11 different songs. Then record 30 newer plays of a twelfth song. Read the default Recently Played list.

**Observed and expected.** The list contains only the twelfth song. Raising the query limit to 41 returns all 12 distinct songs. The 30-song list should include up to 30 distinct tracks in last-played order, including the 11 earlier songs in this fixture.

**Cause.** SQLite limits the number of play events to 30 before Dart removes repeat track IDs. [Recently Played query](../lib/features/recently_played/data/repositories/recently_played_repository_impl.dart#L71)

### LIB-12 · Playlist duplicates accumulate with no per-song removal control

**Reproduce.** Use a scratch playlist. Add the same library track twice through the overflow action, then open the playlist and inspect either row's menu. In the fixture, issue 24 add requests for one track and call the existing removal operation once.

**Observed and expected.** On Android, the scratch playlist displayed two numbered rows for the same song. The menu showed Add to Playlist and had no removal action. The repository accepted 24 copies and removed all 24 in one call. If repeat entries are supported, a user should be able to remove just the selected occurrence. If entries are unique, repeated adds should leave the playlist unchanged.

**Cause.** Membership insertions accept repeat track IDs. The detail page delegates to the standard track menu, while the removal API accepts a track ID and deletes every matching membership. [Membership writes](../lib/features/playlists/data/repositories/playlist_repository_impl.dart#L174) · [Playlist row menu](../lib/features/playlists/presentation/pages/playlist_detail_page.dart#L297)

### LIB-13 · Concurrent favorite toggles lose updates

**Reproduce.** Start with one unfavorited track and issue 20 concurrent calls to `toggleFavorite` for its ID.

**Observed and expected.** One call succeeds, 19 return database failures, and the track ends favorited. Sequentially applying 20 toggles would leave it unfavorited. The result confirms a repository race. A device gesture sequence producing the same degree of concurrency was not established.

**Cause.** The read and write are separate operations. Concurrent calls observe the same absent favorite before competing to insert a row constrained to one per track. [Favorite mutation](../lib/features/favorites/data/repositories/favorite_repository_impl.dart#L94) · [Favorite uniqueness](../lib/core/database/tables.dart#L146)

## Verification

| Check | Result |
| --- | --- |
| Static analysis | No issues |
| Existing Flutter suite | 331 tests passed |
| Targeted audit probes | 11 scenarios passed. Assertions reproduce the current behavior for the named defects. |
| 10,000-track SQLite fixture | All 10,000 tracks loaded in 389 ms and matched the broad query in 366 ms on the final host run. Exact-result ranking passed in 6 ms. |
| 1,205-track sync fixture | 13 pages. Initial sync requested 1,205 media files in 5.19 seconds. Unchanged sync requested zero in 319 ms. An injected HTTP 503 left the missing track intact until recovery. Resume used the discovery checkpoint, fetched only the failed file, and finished with one add, one update, and one removal. |
| USB device browse | Repeated cold launches and 40 song-list flings completed. Library navigation and search remained usable. The scratch playlist was deleted after the test. One tap started a song during the playlist exercise and playback was paused. |
| Live Drive picker | My Drive loaded and listed the saved music folder. Opening it loaded six visible child-folder rows. The audit stopped before confirming a folder or starting a live sync. |
| Scope | Pagination, failed media, cache integrity, and reconciliation stress used fixtures and isolated storage. |

The host ran Flutter 3.47.2 and Dart 3.13.2. The fixture used in-memory Drift SQLite, a temporary filesystem, scripted HTTP through the production Drive repository, and a fake metadata extractor. It does not measure large-library Android rendering or real media transfer throughput.

Run the [targeted audit probes](../tool/audit/music_library_probe_test.dart) from the repository root.

```bash
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter test --no-pub --reporter expanded tool/audit/music_library_probe_test.dart
```

The [Google Drive sync audit](google-drive-sync-audit.md) contains the earlier sync findings and their regression coverage.
The [second-round music library audit](music-library-audit-round-2.md) continues with sync recovery, shared files, cache, and library actions.
