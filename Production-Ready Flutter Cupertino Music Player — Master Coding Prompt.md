# Build a Production-Ready Flutter Music Player for Android

You are an expert Flutter architect and senior Android engineer. Build a complete, production-ready Android music player application in Flutter.

This is NOT a prototype, demo, proof of concept, UI mockup, or scaffold.

The application must contain:
- No mock data
- No fake repositories
- No hard-coded sample songs
- No placeholder screens
- No TODO implementation gaps
- No "coming soon" features for functionality explicitly specified below
- No simulated Google Drive responses
- No fake playback
- No dummy metadata

Every implemented feature must work end-to-end with real data.

The codebase must be maintainable by another senior Flutter developer and structured for long-term evolution.

The app must be optimized for Android phones and visually follow Apple's Cupertino design language while remaining an Android application.

---

# 1. PRODUCT DEFINITION

Build a premium personal music player whose primary music source is Google Drive.

Core product philosophy:

- Google Drive is the remote source of truth for cloud music files.
- A local database is the source of truth for the indexed library.
- Local storage is the source of truth for downloaded/cached audio.
- Audio files are NOT bulk-downloaded during library synchronization.
- Music metadata is indexed locally.
- When the user plays a cloud-only song, its audio file is downloaded to local cache and then played locally.
- Users can explicitly choose "Download for Offline" to retain a track locally.
- Cache management must be largely invisible to the user.
- The UI should feel like a premium music application rather than a cloud file browser.

The app must combine:
- Cupertino visual design
- Personal music library
- Google Drive integration
- Background playback
- Persistent queue
- Offline cache
- Intelligent metadata normalization
- Favorites
- Recently played
- Albums
- Artists
- Playlists
- Search
- Audio technical information

---

# 2. PLATFORM AND SCOPE

Target:
- Android only
- Flutter
- Portrait-first phone experience
- Follow system light/dark theme
- Respect Android system navigation and gestures
- Do not build separate iOS functionality
- Do not add unnecessary cross-platform abstractions that provide no value

The app must work correctly with:
- Android app lifecycle changes
- Screen locking
- Background playback
- Bluetooth/headset media controls
- Audio focus
- Phone calls/interruption scenarios
- App suspension
- Network loss
- Drive authentication expiry
- Drive file deletion/movement
- Cache eviction

The application must support Android's current recommended edge-to-edge layout behavior.

---

# 3. REQUIRED ENGINEERING PRINCIPLES

Use a layered architecture with strict separation of responsibilities.

Required dependency direction:

Presentation
→ Application / State
→ Domain
→ Data

Never allow:
- Widgets to directly call Google Drive APIs
- Widgets to directly query SQLite
- Playback code to directly mutate UI state
- Repositories to depend on Flutter widgets
- Data models to contain UI concerns

Use dependency injection throughout.

All asynchronous operations must have explicit:
- loading state
- success state
- error state
- cancellation behavior where appropriate

Avoid:
- giant StatefulWidgets
- business logic inside widgets
- global mutable singletons
- static service locators accessed everywhere
- untyped dynamic maps across layers
- duplicated state
- duplicated data transformation logic
- unnecessary inheritance hierarchies

Prefer:
- immutable models
- small focused services
- repository interfaces
- pure domain logic
- typed failures
- explicit state machines
- composition over inheritance

---

# 4. REQUIRED TECHNOLOGY STACK

Use the latest stable compatible versions at implementation time, and verify every package against its current official documentation before coding.

Use these technologies unless a package has become officially unsupported, in which case choose the current officially recommended equivalent and document the replacement:

Flutter:
- Stable Flutter channel
- Dart with sound null safety

State management:
- Riverpod
- flutter_riverpod
- code generation for providers where appropriate

Navigation:
- go_router

Persistence:
- Drift
- SQLite database underneath Drift

Immutable/value models:
- freezed
- json_serializable where serialization is required

Playback:
- just_audio
- audio_service
- audio_session

Google authentication:
- google_sign_in using the current supported Android flow

Google Drive:
- Google Drive REST API v3 through an appropriately maintained Dart HTTP/API implementation
- Use OAuth scopes appropriate for reading the user's existing Drive music library

Networking:
- dio

Connectivity:
- connectivity_plus

File system:
- path_provider
- path

Permissions/system behavior:
- permission_handler only where genuinely necessary
- Do not request permissions that Android does not require for the chosen implementation

Logging:
- logger or a similarly maintained structured logging solution

Functional error handling:
- Either a lightweight typed Result/Failure approach or a well-defined sealed Failure hierarchy
- Do not use exceptions as normal business-state signaling

Testing:
- flutter_test
- mocktail
- integration_test

Code generation:
- build_runner

Linting:
- flutter_lints
- Add stricter analysis rules suitable for production

Do NOT add packages simply because they are popular.
Every dependency must have a justified role.

Before implementation, inspect the current versions and APIs of all selected packages and use their currently supported API surface.

---

# 5. PROJECT STRUCTURE

Use a feature-oriented clean architecture.

The project must be organized approximately as follows:

lib/

  app/
    app.dart
    router/
    theme/
    bootstrap/
    lifecycle/
    configuration/

  core/
    error/
    logging/
    result/
    network/
    filesystem/
    database/
    platform/
    utilities/
    extensions/
    constants/

  features/

    authentication/
      data/
      domain/
      presentation/

    google_drive/
      data/
      domain/
      presentation/

    library/
      data/
      domain/
      presentation/

    metadata/
      data/
      domain/
      presentation/

    playback/
      data/
      domain/
      presentation/

    cache/
      data/
      domain/
      presentation/

    favorites/
      data/
      domain/
      presentation/

    recently_played/
      data/
      domain/
      presentation/

    playlists/
      data/
      domain/
      presentation/

    search/
      data/
      domain/
      presentation/

    settings/
      data/
      domain/
      presentation/

Each feature must have clear separation between:
- data sources
- DTOs
- repository implementations
- domain entities
- repository interfaces
- use cases/services
- Riverpod providers
- UI state
- widgets/pages

Keep related files cohesive and reasonably small.

---

# 6. APPLICATION STARTUP

Application startup must not perform a giant blocking initialization in a single widget.

Create a proper bootstrap sequence:

1. Initialize Flutter bindings.
2. Initialize logging.
3. Initialize local database.
4. Initialize application directories.
5. Initialize playback subsystem.
6. Initialize audio session.
7. Restore playback state.
8. Restore queue.
9. Load authenticated-user state.
10. Load library index state.
11. Render the application.
12. Perform background synchronization if appropriate.

The UI must become responsive as early as reasonably possible.

Long-running work must occur asynchronously.

Do not block the first frame on a complete Google Drive sync.

---

# 7. GOOGLE AUTHENTICATION

Implement real Google authentication.

Required behavior:
- Sign in with Google
- Detect already-authenticated users on app startup
- Sign out
- Handle token refresh
- Handle expired/revoked credentials
- Handle cancellation
- Handle network failures
- Surface actionable user-facing errors
- Never log access tokens or refresh tokens
- Store only what is necessary
- Use secure platform mechanisms for credentials where appropriate

The user must explicitly authorize Google Drive access.

Request only the minimum Drive permissions required for the application.

The app needs to read existing music files in the user's Drive, so choose the correct current scope based on the current Google Drive OAuth model.

Do not ask for write/delete access to Drive.

The application must NEVER modify or delete the user's Drive audio files.

---

# 8. GOOGLE DRIVE FOLDER SELECTION

After successful authentication, allow the user to choose the root music folder.

Required UX:

First connection:

"Connect Google Drive"

Then:

"Choose your music folder"

Display real Drive folders.

Allow navigation through folders.

Allow selecting one folder as the music-library root.

Persist the selected Drive folder ID locally.

The selected root folder may contain:
- nested folders
- album folders
- artist folders
- individual files

Recursively scan descendants.

The folder structure must NOT determine the final library grouping.

Embedded metadata is authoritative after normalization.

Do not hard-code a folder name such as "Music".

---

# 9. GOOGLE DRIVE SCANNING / INDEXING

This is a critical subsystem and must be production-quality.

Do not download all audio files during a normal library scan.

The scan must:

1. Enumerate files recursively from the selected root.
2. Identify supported audio files.
3. Store Drive file identifiers.
4. Store Drive metadata such as:
   - file ID
   - name
   - MIME type
   - size
   - modified timestamp
   - parent folder information if useful
5. Extract embedded audio metadata efficiently.
6. Extract embedded artwork where possible.
7. Normalize metadata.
8. Upsert records into SQLite.
9. Remove records for files that no longer exist inside the selected root.
10. Preserve local cache where the corresponding Drive file still exists.
11. Track sync state and errors.
12. Support incremental synchronization.

The UI must be able to display:
- Initial sync progress
- Number of files discovered
- Number processed
- Number failed
- Current operation
- Last successful sync
- Sync errors

Never display fake progress.

Progress must represent actual work.

---

# 10. AUDIO METADATA EXTRACTION

Supported formats must include at least:

- MP3
- FLAC
- M4A/AAC where supported
- OGG/Opus where supported
- WAV where metadata extraction is supported

The player must make reasonable format support explicit.

Extract when available:

- title
- artist
- album
- album artist
- composer
- genre
- year/date
- track number
- disc number
- compilation flag
- duration
- bitrate
- sample rate
- bit depth
- channel count
- codec/container information
- replay gain information if present and usable
- embedded album artwork
- file size

Important:

The product requirement is metadata-first.

Do NOT persistently download full audio files simply to populate the library.

Implement an efficient metadata extraction strategy.

Use range-based retrieval from Google Drive when technically reliable for the format and metadata location.

When range retrieval is insufficient, download the file to a temporary location solely for metadata/artwork extraction, then delete the temporary file immediately after successful or failed extraction.

Temporary files must never accidentally enter the permanent audio cache.

Document the metadata extraction limitations for each supported format.

---

# 11. METADATA NORMALIZATION

Create a dedicated domain-level metadata normalization service.

Never overwrite the original extracted metadata.

Store:
- raw metadata
- normalized metadata

Normalization should intelligently handle:

- casing differences
- whitespace differences
- Unicode normalization
- artist aliases where safely inferable
- album artist consistency
- track/disc numbering
- compilation albums
- "Various Artists"
- empty/invalid fields
- common filename noise
- duplicate-looking album names with insignificant formatting differences

Do NOT use an external metadata service in v1.

Do NOT hallucinate missing metadata.

Do NOT invent artists, albums, release years, or artwork.

Where metadata is missing:
- fall back to a conservative filename-based title
- use "Unknown Artist" only when necessary
- use "Unknown Album" only when necessary
- preserve the original values

The app must keep raw metadata so future normalization improvements can be applied without re-reading every file.

---

# 12. LIBRARY DATABASE

Use Drift/SQLite.

Create properly normalized tables.

At minimum:

users
music_sources
drive_folders
tracks
albums
artists
genres
playlists
playlist_tracks
favorites
recently_played
playback_queue
cache_entries
sync_runs
sync_errors
artwork
settings
playback_state

The exact schema may use join tables and denormalized search fields where they materially improve performance.

Requirements:
- primary keys
- foreign keys
- indexes
- unique constraints
- migration support
- transaction boundaries
- cascade behavior where appropriate

Drive file ID must be uniquely indexed within the relevant source.

Use database transactions for multi-table synchronization operations.

Never perform N+1 database queries for collection rendering.

Queries must be shaped for screen requirements.

---

# 13. SEARCH

Search must operate primarily on the local database.

Do not perform remote Drive searches for every keystroke.

Search across:
- title
- artist
- album
- album artist
- genre
- playlist names

Search should:
- be fast
- debounce text input
- normalize casing
- normalize diacritics where reasonable
- rank exact title matches above partial matches
- avoid duplicate results
- handle empty search state
- handle no results

Search results must be grouped:
- Songs
- Albums
- Artists
- Playlists

---

# 14. PLAYBACK ARCHITECTURE

Playback is a core subsystem and must be separated from UI state.

Use:
- just_audio
- audio_service
- audio_session

Playback must support:
- play
- pause
- resume
- seek
- next
- previous
- skip
- queue
- reorder queue
- remove from queue
- play next
- play last
- shuffle
- repeat off
- repeat one
- repeat all
- background playback
- lock screen controls
- Android notification controls
- Bluetooth/headset controls
- audio focus
- interruptions
- headset disconnect behavior

Use a dedicated PlaybackService/AudioHandler architecture.

UI widgets must observe playback state rather than control audio internals directly.

---

# 15. CLOUD PLAYBACK FLOW

The user experience must be:

Tap Play
→ Check permanent cache
→ If cached, play local file immediately
→ If not cached, obtain authenticated Drive media access
→ Download the audio file to a temporary cache file
→ Verify download completion
→ Atomically move it into the permanent cache
→ Start playback from the local cached file
→ Update cache database
→ Update recently played
→ Persist playback state

Never expose half-written files to the player.

Downloads must use temporary filenames and atomic rename.

Example:

song-id.partial
→ successful verification
→ song-id.audio

A failed or cancelled download must clean up the partial file.

---

# 16. CACHE DESIGN

Cache is separate from user-visible offline downloads.

Each cache entry must track:

- track ID
- local path
- file size
- downloaded timestamp
- last accessed timestamp
- pinned/offline flag
- checksum/hash if useful
- source Drive file version metadata
- cache state

Cache states:

- not_cached
- downloading
- cached
- failed

Users should not be forced to manually manage cache.

Implement:
- automatic cache eviction
- configurable cache size
- least-recently-used eviction
- protection for pinned offline tracks
- protection for currently playing track
- protection for queued tracks when appropriate
- safe cleanup of orphaned files

Never evict pinned offline files automatically.

Never evict a file while it is being played.

Never delete files directly without updating the database consistently.

---

# 17. "DOWNLOAD FOR OFFLINE"

This is an explicit user operation.

Song menu:

- Play
- Play Next
- Add to Queue
- Add to Playlist
- Favorite
- Download for Offline
- More

When downloaded:
- show "Remove Download" instead
- show a subtle offline indicator

For albums/playlists, support batch offline download.

Batch downloads must:
- have progress
- support cancellation
- tolerate partial failure
- resume sensibly when practical
- not crash on a single corrupt file

---

# 18. CACHE AND DRIVE VERSION CHANGES

A cached file must not become permanently stale.

Store the Drive version/modified timestamp metadata.

During sync:
- detect whether the remote file changed
- mark the cache as stale when appropriate
- do not silently replace a file currently playing
- safely invalidate or refresh later

Pinned offline content should be clearly treated as an offline copy of the current remote version.

---

# 19. RECENTLY PLAYED

Record:
- track ID
- started-at timestamp
- completed/meaningful playback status if useful

Do not count a track as meaningfully played after one accidental tap.

Use a sensible threshold such as:
- minimum playback duration, or
- percentage of track

Choose the threshold explicitly in code/configuration.

Recently played screen/home section must be powered entirely by real playback history.

---

# 20. FAVORITES

Favorites must be local-first and persistent.

A user can favorite:
- tracks

The favorite action must immediately update UI using optimistic local state.

Persist changes transactionally.

Home must have a real Favorites section based on actual user favorites.

No fake favorites.

---

# 21. PLAYLISTS

Implement real local playlists.

Users must be able to:
- create playlist
- rename playlist
- delete playlist
- add track
- remove track
- reorder tracks
- play playlist
- shuffle playlist
- add current track to playlist

Playlists are initially local application data.

Do NOT write playlists back to Google Drive unless explicitly required by a later product specification.

Playlist ordering must be persisted.

Generate playlist artwork intelligently:
- use explicit artwork if available
- otherwise create a deterministic collage/mosaic from tracks in the playlist
- never use placeholder artwork

---

# 22. HOME SCREEN — EXACT DESIGN

Home is a vertically scrolling Cupertino-style personalized feed.

Top section:

Large title:
"Good evening"

The greeting must use the user's device local time.

Use:
- Good morning
- Good afternoon
- Good evening
- Good night if desired, but define the exact time ranges in code and keep them stable.

Home content must contain 5–7 meaningful sections maximum.

Initial priority:

1. Recently Played
2. Favorites
3. Recently Added
4. Albums
5. Artists
6. Playlists

Only show sections that contain real data.

Never render empty fake sections.

If a section has no content:
- omit it rather than showing placeholders.

Each horizontal section:
- has a section title
- optionally has "See All"
- supports horizontal scrolling
- has polished momentum
- uses consistent card sizing
- adapts to screen width

Album cards:
- large artwork
- album name
- artist name
- no release year in the card

Home must remain visually calm:
- generous spacing
- no excessive borders
- minimal dividers
- no generic dashboard cards
- no material design floating-card aesthetic

---

# 23. LIBRARY SCREEN — EXACT DESIGN

Library is a primary bottom navigation destination.

At the top:

Large title:
"Library"

Directly below:
Cupertino-style category navigation:

Albums | Artists | Songs | Playlists

This is a segmented/category interface, NOT four unrelated pages hidden behind generic buttons.

Default selection:
Albums

Albums:
- responsive 3-column grid on typical phones
- adapt column width for larger phone widths
- preserve comfortable minimum card size
- artwork has generous corner radius
- album title
- artist name

Do not display album year in the card.

Artists:
- classic iOS-style list
- compact album/artist artwork treatment
- artist name
- alphabetical ordering
- optional alphabet index on the right
- correct Unicode sorting

Songs:
- compact list
- artwork
- title
- artist
- album
- overflow menu

Playlists:
- visually richer list/grid depending on available space
- deterministic artwork collage where explicit artwork is absent

Library must update reactively as database content changes.

---

# 24. ALBUM DETAIL SCREEN

Create a polished Cupertino album detail page.

Top:
- large album artwork
- album name
- album artist
- total track count
- duration summary where available
- subtle technical details where useful

Actions:
- Play
- Shuffle
- Add/download offline where appropriate

Track list:
- disc separators for multi-disc albums
- track number
- title
- explicit artist if it differs materially
- duration
- overflow menu

Tapping a track:
- starts playback
- queue behavior must be predictable

Do not create fake album artwork.

---

# 25. NOW PLAYING SCREEN — EXACT DESIGN

This is the signature screen.

Use a Cupertino-inspired immersive layout.

Structure:

Top:
- "Now Playing"
- minimal navigation affordance

Center:
- large rounded-square album artwork

Below artwork:
- song title
- artist
- album

Technical badge:
Example:
"FLAC · 24-bit / 96 kHz"

Progress:
- thin Apple-style scrubber
- current time
- remaining/total time
- large enough touch target despite thin visual appearance

Primary playback controls:
- large central circular Play/Pause
- Previous
- Next

Secondary controls:
- Favorite
- Audio info
- Queue

Keep Shuffle and Repeat available without visually dominating the primary controls. Place them within an elegant secondary interaction surface and clearly indicate active states.

Do not clutter the screen.

---

# 26. NOW PLAYING BACKGROUND

The Now Playing background must use:
- the current album artwork as visual input
- a blurred artwork backdrop
- a dynamically derived soft gradient

The background must remain legible.

Requirements:
- dark/light adaptation
- text contrast
- no harsh color transitions
- no seizure-inducing animation
- subtle movement only
- background updates smoothly when track changes

Do not store generated backgrounds permanently unless there is a demonstrated performance benefit.

Cache only if necessary.

---

# 27. NOW PLAYING ARTWORK ANIMATION

Use expressive but elegant animation.

When the mini-player expands:
- artwork should morph from mini-player position/size into full artwork
- transition should preserve visual continuity
- use spring-like motion
- avoid excessive overshoot

When changing tracks:
- artwork changes smoothly
- title and artist transition without abrupt popping
- avoid excessive cross-screen movement

Animations must be:
- interruptible
- performant
- 60fps where device capability permits
- respectful of reduced-motion accessibility settings where available

---

# 28. NOW PLAYING GESTURES

Implement all of the following:

Swipe left on artwork:
→ next track

Swipe right on artwork:
→ previous track

Swipe down:
→ minimize Now Playing

Swipe up:
→ open/expand Queue

Tap artwork:
→ reveal/hide additional information

Gesture requirements:
- reasonable velocity/distance thresholds
- do not accidentally trigger during vertical scrolling
- use horizontal gesture recognition for track switching
- animate according to gesture progress where practical
- support accessibility equivalents for every gesture-driven action

---

# 29. QUEUE

Queue should open as an expandable bottom sheet originating from Now Playing.

Initial sheet:
- current track
- Up Next
- queue list
- drag handles for reordering

Support:
- Play Next
- Play Last
- Reorder
- Remove
- Clear queue where appropriate
- Shuffle queue
- persist queue across app restarts

Queue state must survive app restarts.

Do not create separate duplicated queue state in UI and playback service.

Playback service and database must have a clear single source of truth strategy.

---

# 30. AUDIO INFORMATION SHEET

When the user taps the technical information badge, show a polished Cupertino modal/bottom sheet.

Display real values only:

Format
FLAC

Bit depth
24-bit

Sample rate
96 kHz

Bitrate
1,423 kbps

Channels
Stereo

File size
real value

Source
Google Drive

File name
real filename

Do not display fields when the value is unknown.

Do not fabricate codec details.

---

# 31. MINI-PLAYER — EXACT DESIGN

The mini-player must appear above bottom navigation whenever a track is actively loaded/playing/paused in the playback service.

Content:
- small album artwork
- song title
- artist
- play/pause

Optional:
- thin progress indicator

The mini-player must:
- remain visually attached to the navigation area
- expand into Now Playing
- support swipe-to-dismiss only if that behavior does not conflict with normal navigation
- correctly reflect actual playback state

Opening Now Playing should animate from mini-player state.

---

# 32. APP NAVIGATION

Bottom navigation:

Home
Library
Search
Settings

Do not add unnecessary primary tabs.

Navigation must use:
- go_router
- nested navigation where appropriate
- state-restoring behavior
- correct Android back button behavior
- correct nested-page back-stack behavior

Required destinations include at minimum:
- Home
- Library
- Search
- Settings
- Album detail
- Artist detail
- Playlist detail
- Now Playing
- Queue sheet
- Google Drive source setup
- Sync screen/status
- Audio info sheet

---

# 33. SEARCH SCREEN — EXACT DESIGN

Use Cupertino search behavior.

Top:
- prominent search field
- immediate focus support
- keyboard-aware layout

Results:
- grouped sections
- songs
- albums
- artists
- playlists

Results must use actual indexed data.

No network request per keystroke.

Search should update quickly as the user types.

Empty state:
- elegant explanatory state
- no fake recommendations

---

# 34. SETTINGS

Settings must use Cupertino list sections.

Sections:

Playback
- Crossfade
- Gapless Playback
- Volume normalization
- Audio behavior
- Queue behavior where appropriate

Library
- Music Sources
- Sync Library
- Cache
- Last sync
- Indexed track count

Google Drive
- Connection status
- Selected folder
- Change folder
- Sync now
- Disconnect

Appearance
- Follow System

About
- app version
- build number
- licenses

Cache section must display:
- current cache usage
- cache limit
- offline downloads count
- clear cache option, with protection for pinned downloads unless explicitly confirmed

---

# 35. DESIGN SYSTEM

The application must consistently use Flutter Cupertino widgets and Cupertino styling primitives wherever practical.

Use:
- CupertinoPageScaffold
- CupertinoNavigationBar / Sliver variants where appropriate
- CupertinoTabScaffold or a carefully controlled equivalent for bottom navigation
- CupertinoListSection
- CupertinoListTile where supported
- CupertinoSearchTextField
- CupertinoActionSheet / Cupertino modal patterns
- Cupertino switches and controls
- Cupertino buttons

Avoid Material styling by default.

Do not mix Material cards, Material floating action buttons, Material navigation bars, and Cupertino surfaces randomly.

The visual language must feel coherent.

---

# 36. TYPOGRAPHY

Use the platform's appropriate system typography.

Visual hierarchy:

Screen title:
- large
- bold
- Apple-style large-title treatment

Section title:
- medium-large
- semibold

Primary content:
- regular/medium
- high contrast

Secondary metadata:
- smaller
- reduced contrast

Technical metadata:
- compact
- subdued

Never use oversized typography merely to fill space.

Keep line lengths short enough for music metadata.

Handle:
- long album names
- long artist names
- very long filenames
- CJK text
- right-to-left text
- emoji safely

Use appropriate truncation.

---

# 37. CORNER RADII

Use a consistent radius system.

Recommended base system:

Small surfaces:
12 px

Cards:
16 px

Album artwork:
20 px

Large sheets:
24 px

Do not invent random radii throughout the app.

Central play button:
fully circular

---

# 38. SPACING SYSTEM

Use a consistent spacing scale based on 4/8 pixel rhythm.

Common spacing:
- 4
- 8
- 12
- 16
- 20
- 24
- 32

Do not hard-code arbitrary spacing repeatedly.

Create reusable spacing constants/tokens where appropriate.

---

# 39. LIGHT/DARK MODE

Follow system appearance automatically.

Do not create a separate manual light/dark toggle in v1.

The same design must adapt gracefully to both modes.

Now Playing gradient behavior must change appropriately for readability.

Do not assume pure white or pure black backgrounds everywhere.

Use semantic colors and Cupertino-style tonal hierarchy.

---

# 40. RESPONSIVE LAYOUT

Phone portrait is the primary target.

Responsive rules must:
- adapt album grid columns
- adapt artwork size
- respect safe areas
- handle small Android phones
- handle large Android phones
- avoid overflow
- respect font scaling

The album grid should normally resolve to 3 columns on typical phones.

Do not use a hard-coded fixed screen width.

---

# 41. ACCESSIBILITY

Production-quality accessibility is mandatory.

Provide:
- semantic labels
- meaningful button descriptions
- adequate touch targets
- text scaling support
- sufficient color contrast
- non-gesture alternative actions
- screen-reader-friendly list semantics

Do not rely purely on iconography when the meaning can be ambiguous.

---

# 42. EMPTY STATES

All empty states must be real and intentional.

Examples:

No Google Drive connected:
"Connect Google Drive to build your music library."

No music:
"No music found in this folder."

No favorites:
"Favorite songs will appear here."

No recently played:
"Songs you play will appear here."

No playlists:
"Create a playlist to start organizing your music."

Do not use lorem ipsum or generic placeholder content.

---

# 43. ERROR UX

Every important failure must result in a human-readable UI state.

Examples:

Drive authentication failure
→ "Google Drive connection expired. Sign in again."

Network unavailable during play
→ "This song isn't cached and Google Drive is unavailable."

Corrupt file
→ "This audio file couldn't be played."

Missing remote file
→ mark it unavailable and allow library reconciliation

Metadata extraction failure
→ keep the track indexed using conservative fallback metadata

Never expose raw stack traces to users.

---

# 44. OFFLINE BEHAVIOR

The app must remain useful when the user is offline.

Offline capabilities:
- browse indexed library
- browse cached artwork
- play cached tracks
- browse favorites
- browse recently played
- browse playlists
- browse album/artist metadata
- use cached queue

Cloud-only tracks must clearly fail gracefully when unavailable offline.

Do not erase the library just because Drive is temporarily unreachable.

---

# 45. SYNCHRONIZATION MODEL

Implement incremental synchronization.

Maintain:
- selected root folder ID
- last sync timestamp
- remote modification/version information
- sync cursor/token if supported by current Drive API strategy
- scan status

On sync:
- detect additions
- detect modifications
- detect removals
- update metadata
- preserve unchanged records

Do not rescan and fully rebuild the entire local database on every app startup.

Provide manual:
"Sync Now"

Automatic synchronization should be conservative and not drain battery.

---

# 46. SYNC SAFETY

A sync must be transactional where possible.

A partial sync must not leave the library in a corrupt state.

Track:
- sync started
- sync completed
- sync failed
- counts of added/updated/removed/errors

If the application crashes during sync:
- recover cleanly
- resume or restart safely
- never duplicate tracks
- never orphan large temporary files

---

# 47. ARTWORK HANDLING

Prefer embedded artwork from the audio file.

Do not use an external artwork provider in v1.

Store artwork locally in a dedicated cache.

Artwork requirements:
- deduplicate identical artwork where practical
- resize oversized artwork for UI usage
- preserve original artwork only when needed
- do not decode giant images repeatedly
- use memory-efficient image loading

Never display random placeholder album art.

When artwork doesn't exist:
- generate a deterministic typography/gradient artwork based on album/artist metadata
- it must look intentional
- it must be deterministic
- it must not be mistaken for real artwork

---

# 48. PERFORMANCE

The app must remain responsive with at least:
- 10,000 tracks
- 1,000 albums
- 2,000 artists

Avoid loading all songs into memory.

Use:
- paginated/streamed queries where appropriate
- lazy lists/grids
- optimized database queries
- image caching
- background metadata processing
- isolates for CPU-heavy parsing if necessary

Never do large synchronous database or metadata processing operations on the UI isolate.

---

# 49. MEMORY MANAGEMENT

Be particularly careful with:
- high-resolution album artwork
- FLAC files
- long queues
- large database result sets

Never load an entire music library's artwork into memory.

Never read an entire large audio file into a Dart byte array unless absolutely necessary.

Prefer file streams / native playback paths.

---

# 50. THREADING / ISOLATES

CPU-heavy work such as:
- metadata parsing
- image manipulation
- normalization of large collections

may run outside the main isolate when beneficial.

Do not overuse isolates for trivial operations.

The UI thread must remain smooth.

---

# 51. SECURITY

Never:
- log OAuth tokens
- expose Drive credentials
- hard-code API secrets
- store secrets in source control
- write access credentials to normal logs

Use secure Android configuration where needed.

Google OAuth client configuration must follow Google's official Android setup.

Never ship test credentials.

---

# 52. DATABASE MIGRATIONS

Every schema change must use Drift migrations.

Do not:
- delete the user's database on schema changes
- silently recreate the database
- drop all data in production

Include migration tests.

---

# 53. CODE QUALITY

Enforce:
- strict null safety
- linting
- formatting
- meaningful names
- small classes
- focused responsibilities
- no dead code
- no unused dependencies
- no unnecessary comments

Comments should explain:
- why
not:
- what obvious code does

Public domain/repository interfaces should have concise documentation when behavior isn't obvious.

---

# 54. STATE MODEL

Use explicit states.

Examples:

Google Drive connection:
- disconnected
- connecting
- connected
- reauthenticationRequired
- error

Library sync:
- idle
- scanning
- extractingMetadata
- updatingDatabase
- complete
- failed

Download:
- idle
- queued
- downloading
- completed
- failed
- cancelled

Playback:
- idle
- loading
- buffering/downloading
- playing
- paused
- completed
- error

Do not represent complex state with many unrelated booleans.

---

# 55. REPOSITORY CONTRACTS

Create repository interfaces such as:

AuthRepository
GoogleDriveRepository
MusicLibraryRepository
MetadataRepository
PlaybackRepository
CacheRepository
FavoriteRepository
PlaylistRepository
RecentlyPlayedRepository
SettingsRepository

The domain layer should depend on interfaces only.

Concrete implementations belong in data.

---

# 56. DOMAIN USE CASES

Implement explicit use cases for major actions.

Examples:

AuthenticateWithGoogle
SelectMusicFolder
SyncDriveLibrary
GetHomeSections
SearchLibrary
PlayTrack
PlayAlbum
PlayPlaylist
AddToQueue
PlayNext
PlayLast
ReorderQueue
ToggleFavorite
CreatePlaylist
AddTrackToPlaylist
DownloadForOffline
RemoveOfflineDownload
ClearCache
GetAudioInfo

Avoid putting all of this into one giant MusicService.

---

# 57. UI COMPONENT LIBRARY

Create reusable components for:

- album artwork
- album card
- artist row
- song row
- section header
- mini-player
- large play button
- technical metadata badge
- empty state
- loading state
- sync progress
- queue item
- playlist artwork mosaic
- Cupertino action sheet
- download/offline status indicator

The same component must not be reimplemented separately across screens unless the visual requirement genuinely differs.

---

# 58. HOME SECTION SYSTEM

Create a reusable HomeSection abstraction.

A Home section must know:
- title
- optional See All action
- data source
- item renderer
- navigation destination

The Home feed should be assembled from real data.

Do not hard-code sample albums.

Do not hard-code section contents.

Only show sections with meaningful content.

---

# 59. LIBRARY SORTING

Albums:
- primarily by normalized album name
- configurable secondary ordering by artist where necessary

Artists:
- alphabetical

Songs:
- title alphabetical by default

Playlists:
- user-defined or recently modified ordering

Support deterministic sorting.

---

# 60. DUPLICATE DETECTION

Detect likely duplicate remote files using:
- Drive file ID
- normalized metadata
- size
- duration
- checksums where practical

Do not automatically delete duplicates.

Group/mark duplicates intelligently.

The user must retain control.

---

# 61. DATA CONSISTENCY

A track must not exist as a broken reference across:
- database
- cache
- playlist
- favorites
- recently played
- queue

Use foreign keys and repository-level transactional handling.

When a Drive track disappears:
- do not instantly destroy user-created playlist references unnecessarily
- retain enough tombstone/reference information where useful
- clearly mark unavailable items

---

# 62. ANDROID PLAYBACK NOTIFICATION

Implement a polished Android media notification with:
- artwork
- title
- artist
- play/pause
- next/previous where supported

Use proper media session integration.

The notification must reflect the same state as the playback service.

---

# 63. LOCK SCREEN / BLUETOOTH

Playback controls from:
- lock screen
- Bluetooth headset
- car/media controls

must operate against the same PlaybackService state.

Test:
- play/pause
- next
- previous
- interruption
- resume

---

# 64. APP LIFECYCLE

Handle:
- foreground
- background
- process restart
- activity recreation
- configuration/theme changes
- playback continuation

Persist enough playback state to restore:
- current track
- queue
- queue index
- position
- repeat mode
- shuffle mode

Do not attempt to restore an impossible remote state without a valid local/cached source.

---

# 65. TESTING REQUIREMENTS

Do not consider the task complete without tests.

Unit tests:
- metadata normalization
- sorting
- duplicate detection
- cache eviction
- sync reconciliation
- search ranking
- playback state transitions
- playlist ordering
- recently-played logic

Repository tests:
- Drive repository behavior
- database repository behavior
- cache repository behavior

Widget tests:
- Home
- Library
- Search
- Mini-player
- Now Playing
- Queue
- Settings

Integration tests:
- Google sign-in flow abstraction
- folder selection flow
- library indexing flow
- cached playback
- cloud download-to-play flow
- offline playback
- favorites
- playlist operations

Use fake/test implementations only inside tests.

Production code must never depend on mock repositories.

---

# 66. TEST FIXTURES

Tests may use synthetic audio fixtures and test files.

Production application data must never use fixtures.

Include small valid:
- MP3
- FLAC
- metadata test files
where legally appropriate for repository tests.

Test metadata extraction with:
- complete metadata
- missing fields
- malformed tags
- multiple artists
- multi-disc albums
- embedded artwork
- no artwork

---

# 67. OBSERVABILITY

Create structured logging categories:

Auth
Drive
Sync
Metadata
Database
Cache
Playback
UI

Log:
- operation start/end
- counts
- errors
- durations when useful

Never log:
- OAuth tokens
- sensitive credentials
- full private Drive contents unnecessarily

In release mode, avoid excessive debug logging.

---

# 68. ERROR CLASSIFICATION

Create typed failures such as:

AuthenticationFailure
AuthorizationFailure
NetworkFailure
DriveApiFailure
DriveFileNotFound
MetadataExtractionFailure
UnsupportedFormatFailure
PlaybackFailure
CacheFailure
DatabaseFailure
ValidationFailure

Map failures into user-friendly presentation messages.

Preserve enough technical context for diagnostics.

---

# 69. NO PLACEHOLDER BEHAVIOR

The coding agent must NEVER implement any of the following:

- "Lorem ipsum"
- hard-coded sample songs
- fake progress values
- fake album artwork
- fake Google Drive results
- fake authentication success
- fake loading delays
- simulated playback timers
- buttons that do nothing
- screens labeled "Coming Soon"
- stub methods returning empty data to make UI compile
- TODO markers in production paths
- silently swallowed exceptions

When a feature cannot be implemented because of an external configuration requirement, fail explicitly and document the exact setup requirement rather than pretending the feature works.

---

# 70. INITIAL USER EXPERIENCE

First launch when not connected:

Screen:
"Your music, everywhere."

Primary action:
"Connect Google Drive"

No fake library should be visible.

After connecting:
- choose folder
- run real scan
- show real progress
- display real library

After successful indexing:
navigate to Home.

---

# 71. GOOGLE DRIVE DISCONNECT

Disconnect must:
- remove authentication state
- stop cloud operations
- preserve user-local data where appropriate
- clearly identify which library entries are cloud-backed
- not delete local offline tracks without explicit confirmation

The user must understand the effect before destructive local cleanup.

---

# 72. CACHE SIZE SETTINGS

Provide sensible defaults.

Recommended initial default:
- 5 GB maximum automatic cache

Offline-pinned content can exceed automatic cache accounting only according to a clearly defined product rule; otherwise count all local audio toward total storage and simply exclude pinned files from automatic eviction.

Allow the user to change the cache limit.

Validate:
- minimum reasonable size
- maximum reasonable size

Do not permit obviously unsafe values.

---

# 73. PLAYER BEHAVIOR

When a cloud-only song is tapped:
- display a subtle loading/download state
- do not show a fake playback progress bar
- begin playback as soon as the local file is sufficiently prepared according to the chosen implementation
- for v1, prioritize reliable complete-file download before playback over complex progressive playback
- preserve a responsive UI during download

When a cached song is tapped:
- start playback as quickly as the audio engine allows

Do not make the UI indistinguishable between remote and cached states unless actual playback is ready.

---

# 74. ALBUM / ARTIST / PLAYLIST NAVIGATION

Every entity must be navigable.

Artist page:
- artwork if available
- artist name
- albums
- songs

Album page:
- artwork
- album metadata
- songs
- play/shuffle

Playlist page:
- playlist artwork
- title
- track count
- play/shuffle
- reorder/edit

---

# 75. UI ANIMATION SYSTEM

Create a coherent animation language.

Use:
- Cupertino-style transitions
- spring curves for player transformations
- opacity/scale transitions for content changes
- shared/matched artwork transitions where practical
- gesture-driven interactive sheets

Do NOT:
- animate every list item unnecessarily
- use long animations
- cause janky scrolling
- create decorative motion that competes with album artwork

Typical transitions should feel fast and premium.

---

# 76. PERFORMANCE BUDGET

Target:
- smooth scrolling
- minimal frame drops
- no synchronous large-file work on UI isolate
- no full-library object materialization for grid/list screens

Particularly optimize:
- Home horizontal lists
- Album grid
- Song list
- artwork loading
- queue scrolling

---

# 77. RELEASE CONFIGURATION

Provide:
- debug
- profile
- release configuration

Ensure:
- proper app label
- application ID
- launcher icon setup
- splash screen
- versioning
- signing documentation
- ProGuard/R8 considerations if applicable
- release-safe logging

Do not commit signing secrets.

---

# 78. GOOGLE CONFIGURATION DOCUMENTATION

Create a complete README describing:
- creating Google Cloud project
- enabling Drive API
- configuring Android OAuth client
- adding package name
- SHA-1/SHA-256 configuration as required
- consent screen configuration
- required OAuth scopes
- local development setup
- release configuration
- any required API credentials/configuration

The application must not claim Google integration is complete if required Google Cloud setup has not been performed.

---

# 79. DOCUMENTATION

Create:

README.md

docs/
  architecture.md
  google-drive-setup.md
  playback.md
  caching.md
  database.md
  testing.md
  release.md

Documentation must explain:
- architecture
- major decisions
- data flow
- sync model
- caching model
- authentication
- playback
- database migrations
- testing
- release setup

---

# 80. STATIC ANALYSIS

Before declaring completion:

Run:
- dart format
- flutter analyze
- code generation
- flutter test
- integration tests where environment permits

Resolve:
- analyzer errors
- warnings introduced by the application
- dead imports
- dead code
- formatting issues
- generated-code issues

Do not suppress warnings merely to make CI green unless the suppression is justified and documented.

---

# 81. BUILD VALIDATION

Produce an actual Android release build.

Verify:
- app launches
- Google sign-in UI flow works with configured credentials
- Drive folder selection works
- real music files are indexed
- metadata appears
- artwork appears
- real audio downloads
- real audio plays
- background playback works
- notification works
- queue works
- favorites work
- playlists work
- cache works
- offline playback works

The completion criterion is functional behavior, not compilation alone.

---

# 82. ACCEPTANCE CRITERIA

The implementation is complete only when the following end-to-end scenario works:

1. Fresh install.
2. Launch app.
3. See "Your music, everywhere."
4. Connect a real Google account.
5. Select a real Drive music folder.
6. Recursively scan its audio files.
7. Build a local SQLite library.
8. Display Home with actual music.
9. Browse Albums.
10. Open an actual album.
11. Tap an actual song.
12. Download the real Drive file.
13. Cache it.
14. Play it using the real audio engine.
15. Lock the phone.
16. Continue listening in background.
17. Use notification controls.
18. Return to app.
19. See correct current playback state.
20. Open Now Playing.
21. Use gestures.
22. Open queue.
23. Reorder queue.
24. Favorite a song.
25. Add it to a playlist.
26. Close the app.
27. Reopen it.
28. Restore library, favorites, playlist, queue, and playback state appropriately.
29. Disable network.
30. Play the cached track.
31. Confirm it works offline.
32. Sync Drive again.
33. Detect a new/modified/removed cloud file.
34. Update the library correctly.

---

# 83. IMPORTANT IMPLEMENTATION STRATEGY

Before writing the full application:

1. Inspect the repository and existing Flutter project.
2. Identify any existing code worth preserving.
3. Establish architecture and dependency choices.
4. Verify current package APIs against official documentation.
5. Create the database schema and migrations.
6. Implement Google authentication.
7. Implement Drive folder selection.
8. Implement Drive indexing.
9. Implement metadata extraction.
10. Implement database synchronization.
11. Implement cache manager.
12. Implement playback service.
13. Implement queue persistence.
14. Implement library UI.
15. Implement Home.
16. Implement Search.
17. Implement Settings.
18. Implement Now Playing and mini-player.
19. Add animations.
20. Add tests.
21. Run analysis/tests/build.
22. Fix all resulting issues.
23. Produce final documentation.

Do not build the entire UI with placeholder repositories and promise to connect real services later.

Build vertically with real functionality.

---

# 84. DESIGN PRIORITY ORDER

When making implementation decisions, use this priority:

1. Correctness
2. Data integrity
3. Playback reliability
4. Security
5. Performance
6. Maintainability
7. Accessibility
8. Cupertino visual fidelity
9. Animation polish

Never sacrifice data integrity or playback reliability for visual effects.

---

# 85. DESIGN REFERENCE

The visual target is:

"Apple Music aesthetics, but cleaner and distinctly its own."

It should feel:
- premium
- calm
- elegant
- expressive
- artwork-driven
- spacious
- refined

It must NOT feel:
- like a Material Android app
- like a file browser
- like a generic admin dashboard
- like a prototype
- overloaded with controls
- visually noisy

Use Cupertino design language as the foundation.

The user should feel that Google Drive is simply the invisible source behind their personal music library.

---

# 86. FINAL ENGINEERING REQUIREMENT

Do not stop after generating source files.

Actually validate the application.

Where external configuration prevents a real integration test, document the exact manual setup step required, but do not replace the integration with a fake implementation.

Never claim a feature works unless it has been implemented and verified to the extent possible in the available environment.

The final codebase must be production-oriented, readable, testable, modular, and ready for continued development.

Return:
- complete source implementation
- generated files where needed
- database migrations
- tests
- Android configuration
- documentation
- build/run instructions
- list of any environment-specific setup requirements

Do not return a conceptual answer.
Do not return pseudocode.
Do not return an architecture-only proposal.

Build the actual application.