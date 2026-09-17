You are a senior Flutter engineer, mobile systems engineer, and product-quality UI engineer working on the existing Musii Android music player.

Implement a COMPLETE, PRODUCTION-READY Last.fm integration called "Last.fm Scrobbler".

This is NOT a mockup.
This is NOT a prototype.
This is NOT a visual-only implementation.

Every visible state must be backed by real application state and real behavior.
Every button must work.
Every toggle must persist.
Authentication must actually work.
Scrobbles must actually reach Last.fm.
Offline scrobbles must actually be queued and later synchronized.
Failures must actually be handled.
The app must remain functional when Last.fm is unavailable.

Do not use mock data.
Do not use fake usernames.
Do not use fake scrobble counts.
Do not create placeholder authentication.
Do not hardcode a fake "Connected" state.
Do not add TODOs for core behavior.
Do not simulate successful API responses.

Use the official Last.fm API/authentication behavior and verify all API request/response details against the current official Last.fm documentation before implementation. Do not invent undocumented endpoints, parameters, authentication behavior, or response formats.

==================================================
1. PRODUCT GOAL
==================================================

Add a first-class Last.fm integration to Musii.

The user should be able to:

- connect their Last.fm account
- see which Last.fm account is connected
- enable/disable scrobbling
- enable/disable Now Playing updates
- automatically scrobble eligible tracks
- keep playing normally when offline
- queue eligible offline scrobbles locally
- automatically upload queued scrobbles when connectivity returns
- see pending scrobbles
- see recent scrobble activity/status
- recover gracefully from temporary network failures
- recover gracefully when Last.fm authentication expires or becomes invalid
- disconnect Last.fm
- continue using Musii normally with Last.fm disconnected

The integration must feel invisible during normal listening.

The user should configure it once and then largely forget about it.

==================================================
2. IMPORTANT ARCHITECTURAL PRINCIPLE
==================================================

Do NOT place Last.fm logic directly inside widgets, pages, or playback UI.

Follow the existing Musii architecture:

Core
Domain
Data
Presentation

Keep:
- API communication in the data layer
- Last.fm business rules in the domain layer
- persistence in the existing Drift database layer
- reactive UI state through Riverpod
- reusable UI components in presentation widgets
- failures represented through the existing Result/AppFailure model

The existing project uses Clean Architecture/DDD and explicitly separates domain entities, repository contracts, data implementations, and presentation. Preserve that structure. :contentReference[oaicite:3]{index=3}

Do not introduce a parallel state-management system.

==================================================
3. INSPECT THE EXISTING CODEBASE FIRST
==================================================

Before writing code, inspect:

- Settings page
- Settings repository
- Settings database table
- playback repository
- MusiiAudioHandler
- current playback state providers
- current Track entity
- current Artist entity
- current Album entity
- playback history implementation
- connectivity service
- application bootstrap
- secure storage implementation, if present
- existing HTTP/network abstractions
- existing failure/result architecture
- Drift schema and current migration version
- app lifecycle handling
- background playback handling
- notification/background service behavior

Do not assume names.

Integrate with the actual existing implementation.

==================================================
4. SETTINGS ROOT SCREEN
==================================================

Add a new section to Settings:

SERVICES

Last.fm
Connected as @username

When disconnected:

Last.fm
Scrobbling & listening history

When connected:

Last.fm
Connected as @username

The root Settings screen must remain visually quiet.

Do NOT add a giant Last.fm card.
Do NOT add a permanent status dashboard.
Do NOT show fake statistics.

Use the existing Musii Settings visual language.

==================================================
5. LAST.FM DETAIL SCREEN
==================================================

Create a dedicated Settings subpage:

Last.fm

The disconnected state should communicate:

- what Last.fm does
- why the user would connect it
- that listening can be scrobbled automatically
- how to connect

Example conceptual content:

LAST.FM

Keep your listening history
in sync with Last.fm.

Connect Musii to automatically
scrobble the music you listen to.

[Connect Last.fm]

Do not use static text that implies connection before authentication succeeds.

==================================================
6. CONNECTED STATE
==================================================

After successful real authentication, show:

Last.fm

[real Last.fm identity/avatar if available]

Connected as
@real_username

Scrobbling                         ON
Now Playing                        ON

Then additional sections:

LISTENING

Scrobble automatically
Songs you listen to in Musii are
sent to Last.fm when eligible.

OFFLINE SCROBBLES

X tracks waiting to sync          >

SCROBBLE ACTIVITY

X scrobbles synced
Last synced X minutes ago

ACCOUNT

Open Last.fm profile              >
Disconnect Last.fm                >

Every value must come from real application state.

Do not hardcode:
- username
- avatar
- scrobble count
- pending count
- sync time

==================================================
7. LAST.FM AUTHENTICATION
==================================================

Implement real Last.fm authentication.

Use the supported Last.fm authentication flow appropriate for a native/mobile client.

The flow must:

1. initiate authentication
2. allow the user to authorize Musii
3. receive the authentication result
4. exchange/complete authentication according to the official API
5. obtain and persist the required session/account information
6. verify the authenticated account
7. update the application state
8. return to Musii cleanly

Authentication failures must be surfaced as actual errors.

Do not show "Connected" until authentication has actually completed successfully.

Do not store secrets in plain-text application preferences.

Use the project's existing secure-storage solution if available.

If the project does not have an adequate secure credential-storage mechanism, add one that is appropriate for Android production use.

Never log:
- Last.fm session keys
- API secrets
- OAuth credentials
- authorization tokens
- request signatures containing sensitive secrets

Redact them from logs.

==================================================
8. API CREDENTIAL CONFIGURATION
==================================================

Do not hardcode arbitrary API credentials into application source code.

Inspect the project's current build/configuration strategy.

Use the appropriate production-safe configuration mechanism for the Last.fm API key and any client-side configuration that is actually permitted by the API.

Do not commit private credentials to git.

Do not create fake API credentials.

Document exactly how production configuration is supplied.

If the Last.fm authentication model requires a secret that cannot safely be distributed to the Android client, do not silently create an insecure architecture.

Instead, implement the most secure production-compatible approach supported by the project's deployment model and document the requirement.

The feature must not be "successful" merely because the UI exists.

==================================================
9. SCROBBLING TOGGLE
==================================================

The main setting is:

Scrobbling                         ON/OFF

When ON:
eligible playback events are sent to Last.fm.

When OFF:
no new scrobbles should be submitted.

Turning the toggle off must immediately affect future playback behavior.

Turning it back on must resume normally.

Persist the setting across:
- app restart
- process death
- device reboot
- background playback restarts

Do not require reconnecting Last.fm merely to change the toggle.

==================================================
10. NOW PLAYING TOGGLE
==================================================

Add a separate setting:

Now Playing                        ON/OFF

This controls real-time "currently listening" updates to Last.fm.

Do not confuse this with final scrobbling.

Scrobbling and Now Playing must be independently controllable.

For example:

Scrobbling ON
Now Playing OFF

must continue to submit eligible scrobbles without sending Now Playing updates.

==================================================
11. SCROBBLE ELIGIBILITY
==================================================

Implement Last.fm-compatible scrobble eligibility rules using the current official Last.fm behavior/documentation.

Do not invent arbitrary thresholds.

The implementation must correctly determine whether the current track has been listened to long enough to become eligible for scrobbling.

Handle:
- short tracks
- partially played tracks
- seeking
- pause/resume
- replaying the same track
- skipping
- switching tracks
- app backgrounding
- app foregrounding
- playback interruptions
- completion
- queue transitions
- restored playback state

The scrobble must correspond to the actual listening session.

Do not scrobble every track merely because it started playing.

==================================================
12. NOW PLAYING EVENTS
==================================================

When Now Playing is enabled and a track starts meaningfully playing:

send the correct Last.fm Now Playing event.

Use the actual:
- track title
- artist
- album where available
- album artist / metadata where appropriate according to Last.fm API requirements

Do not send duplicate Now Playing events unnecessarily when:
- playback is paused
- resumed
- position changes
- the same track remains active

A genuine new track transition should create the appropriate new event.

==================================================
13. SCROBBLE DEDUPLICATION
==================================================

Prevent accidental duplicate scrobbles.

A single listening session should not generate multiple final scrobbles because of:

- widget rebuilds
- provider rebuilds
- pause/resume
- seeking
- playback state restoration
- background service lifecycle events
- duplicate stream emissions

Create an explicit domain-level scrobble/session identity or equivalent mechanism based on the real playback state.

It must be impossible for a UI rebuild to duplicate a scrobble.

==================================================
14. REPEAT / REPLAY BEHAVIOR
==================================================

Handle repeated playback correctly.

Example:

Track A
→ listens enough
→ scrobble A

Track A starts again
→ this is a new listening session
→ it may become eligible for another scrobble

Do not globally deduplicate by track ID.

Deduplicate individual listening sessions, not legitimate repeated listening.

==================================================
15. OFFLINE SCROBBLING
==================================================

This is a core feature.

Musii is offline-first. The Last.fm integration must respect this design philosophy. :contentReference[oaicite:4]{index=4}

When the user is offline:

- playback must continue normally
- eligible scrobbles must be saved locally
- no user intervention should be required
- the pending scrobble must survive process death
- the pending scrobble must survive app restart
- the pending scrobble must survive device restart

Do NOT simply discard offline scrobbles.

Do NOT require the user to manually retry after reconnecting.

==================================================
16. PENDING SCROBBLES SCREEN
==================================================

When there are pending offline scrobbles, show:

OFFLINE SCROBBLES

3 tracks waiting to sync

Track rows should use real Musii artwork and metadata.

Example:

[art] Aaj Unse Kehna Hai
      Salman Khan
                              Waiting

[art] Arjan Vailly
      Bhupinder Babbal
                              Waiting

At the bottom:

Waiting for connection
or
Syncing…
or
3 scrobbles synced

The UI must reflect the real queue state.

==================================================
17. QUEUE STATES
==================================================

Each pending scrobble needs an actual lifecycle.

Conceptually:

PENDING
→ SENDING
→ SUCCEEDED

or:

PENDING
→ SENDING
→ RETRY_WAITING

or:

PENDING
→ FAILED_REQUIRES_REAUTH

Do not collapse all failures into one generic "failed" state.

The UI must be able to explain what is happening.

==================================================
18. AUTOMATIC RETRY
==================================================

When connectivity returns:

automatically process the pending scrobble queue.

Do not make the user press Retry for normal transient failures.

Use the existing connectivity infrastructure where appropriate.

The existing Musii app already has a connectivity service and offline/cache infrastructure. Extend the existing approach rather than building a second connectivity system. :contentReference[oaicite:5]{index=5}

Use sane retry behavior.

Do not hammer Last.fm continuously.

Use bounded retries and appropriate backoff.

Respect:
- network unavailability
- server failures
- rate limiting
- authentication failures
- malformed API responses

==================================================
19. SCROBBLE BATCHING
==================================================

Where supported and appropriate by the official Last.fm API, submit pending scrobbles efficiently rather than performing unnecessary one-request-per-track traffic.

Do not sacrifice correctness for batching.

If the API has strict limits on batch size, implement those correctly.

Persist enough state that partial batch failures can be retried safely without duplicating already-successful records.

Do not assume an entire batch succeeded merely because the HTTP request itself succeeded.

Inspect and correctly interpret API-level response status/results.

==================================================
20. APP RESTART RECOVERY
==================================================

A force-close or process death must not lose scrobble state.

On startup:

- restore Last.fm authentication state
- restore settings
- restore pending scrobble queue
- determine whether network is available
- resume pending synchronization where appropriate

Do not resend already-confirmed scrobbles.

Do not falsely mark queued scrobbles as synced.

The app already has explicit crash-recovery and persisted sync state patterns; apply the same reliability standards to Last.fm. :contentReference[oaicite:6]{index=6}

==================================================
21. AUTHENTICATION EXPIRATION
==================================================

If Last.fm indicates that authentication/session credentials are invalid:

do NOT silently discard pending scrobbles.

Instead:

- preserve pending scrobbles locally
- stop attempting authenticated requests
- mark integration as requiring reauthentication
- show a clear UI message
- offer Reconnect
- resume pending uploads after successful reauthentication

Example:

Last.fm needs you to reconnect.

Your recent listening is still safe.

[Reconnect]

The user must not lose their locally queued listening history.

==================================================
22. DISCONNECT FLOW
==================================================

When the user chooses:

Disconnect Last.fm

show a confirmation dialog.

Example:

Disconnect Last.fm?

Musii will stop sending new listening
activity to Last.fm.

Your existing Last.fm history will not
be deleted.

[Cancel]      [Disconnect]

Clarify any behavior around already-queued local scrobbles.

The final behavior must be deliberate.

Do not leave the user with orphaned pending records.

==================================================
23. OPEN LAST.FM PROFILE
==================================================

If the current API/account information supports a public profile URL:

Open Last.fm profile

must open the actual user's profile.

Generate/use the real username/profile URL.

Do not hardcode the Last.fm homepage when the user's real profile can be opened.

Handle the case where the platform cannot open the URL gracefully.

==================================================
24. RECENT SCROBBLE ACTIVITY
==================================================

Add:

SCROBBLE ACTIVITY

X scrobbles synced
Last synced X minutes ago

Make the information real.

Do not invent a historical scrobble total unless it is actually available from the implemented Last.fm API functionality and has been intentionally designed.

At minimum, the activity status must accurately represent Musii's local synchronization state.

Potential display:

128 scrobbles synced
Last synced 2 min ago

or:

3 waiting to sync

These numbers must come from real state.

==================================================
25. SCROBBLE HISTORY
==================================================

Add a Recent Scrobbles view only if the existing data model/API can support it properly.

If implemented:

Show actual locally recorded/submitted scrobble records.

Use the same song-row design as the redesigned Musii Library.

Example:

Today

[art] Aaj Unse Kehna Hai
      Salman Khan
                              4:18 PM

[art] Arjan Vailly
      Bhupinder Babbal
                              4:13 PM

Do not fabricate Last.fm history.

Clearly distinguish:
- locally recorded listening
- pending scrobble
- successfully submitted scrobble

==================================================
26. SCROBBLE SUCCESS FEEDBACK
==================================================

Do not show intrusive dialogs every time a track is scrobbled.

After a successful scrobble, optionally provide subtle transient feedback:

✓ Scrobbled to Last.fm

This can appear:
- briefly in Now Playing
- briefly above the MiniPlayer
- through an unobtrusive status animation

It should disappear automatically.

Do not permanently place a Last.fm icon on every screen.

==================================================
27. NOW PLAYING UI INTEGRATION
==================================================

The existing Now Playing screen already contains:
- artwork
- playback metadata
- controls
- technical information
- contextual actions

Integrate Last.fm feedback into that existing visual hierarchy without cluttering it. :contentReference[oaicite:7]{index=7}

Possible transient state:

Scrobbling…
✓ Scrobbled to Last.fm

Do not show:
"SCROBBLING ACTIVE"
all the time.

The integration should feel ambient.

==================================================
28. MINI PLAYER INTEGRATION
==================================================

Do not permanently show Last.fm controls in the MiniPlayer.

The MiniPlayer should remain focused on playback.

Only provide subtle temporary confirmation where appropriate.

Do not allow Last.fm status to distort the MiniPlayer layout.

==================================================
29. PLAYBACK INTEGRATION
==================================================

Integrate at the playback/domain layer.

The Last.fm service must respond to real playback events.

Correctly handle:

- play
- pause
- resume
- stop
- seek
- next
- previous
- skip
- repeat-one
- repeat-all
- shuffle
- queue changes
- restored playback state
- background playback

Do not connect Last.fm directly to button presses.

For example, "Next Track" can result in a track transition caused by:
- user tapping Next
- headphone controls
- Android media notification
- Android Auto
- queue progression
- automatic track completion

All of these must produce the same correct Last.fm behavior.

The current Musii media handler supports background/system playback controls and queue synchronization, so Last.fm behavior must work regardless of where the playback transition originates. :contentReference[oaicite:8]{index=8}

==================================================
30. BACKGROUND PLAYBACK
==================================================

Scrobbling must continue to work while Musii is:

- backgrounded
- screen locked
- playing through Android media controls

Do not rely on widget lifecycle callbacks.

Do not rely on the Library page being mounted.

The integration must operate from the actual playback system/state source.

==================================================
31. TRACK METADATA
==================================================

Use Musii's canonical track metadata.

At minimum, handle:

- title
- artist
- album
- album artist where available
- duration
- current playback position

Normalize metadata only where required by Last.fm.

Do not display one metadata value in Musii and submit unrelated metadata to Last.fm unless required by the API.

==================================================
32. MISSING METADATA
==================================================

Handle incomplete metadata safely.

Examples:

Missing album
Missing artist
Missing duration

Do not crash.

Do not submit invalid or fabricated metadata.

Apply a deterministic policy for whether a scrobble can be submitted.

Document the policy in code.

==================================================
33. LAST.FM API FAILURES
==================================================

Handle:

- no internet
- timeout
- DNS failure
- HTTP errors
- API errors
- invalid API parameters
- rate limiting
- authentication expiration
- malformed responses
- server errors

Map them into the existing Musii failure/result architecture.

Do not throw raw exceptions through repository boundaries.

The project already uses a sealed `Result<S, F>` and `AppFailure` hierarchy. Follow that convention. :contentReference[oaicite:9]{index=9}

==================================================
34. DATABASE PERSISTENCE
==================================================

Add only the database structures genuinely required for reliable Last.fm integration.

Potential concepts include:

Last.fm account/session state
Last.fm settings
Pending scrobbles
Scrobble attempts/results
Last successful synchronization timestamp

Use the project's existing Drift conventions.

Do not store secrets insecurely inside the normal database if secure storage is more appropriate.

Create a proper schema migration.

Do not reset the database.

Do not destroy existing user data.

Increment the schema version correctly if required.

==================================================
35. PENDING SCROBBLE DATA MODEL
==================================================

A pending scrobble should contain enough information to reproduce the Last.fm request after:

- app restart
- process death
- network outage
- background playback
- authentication recovery

Do not depend solely on the current Track row still existing.

The pending record should retain the necessary immutable scrobble metadata.

This is important because the local music library may change after the scrobble was generated.

==================================================
36. IDEMPOTENCY
==================================================

Design the queue so retry behavior is safe.

For example:

Track A becomes eligible
→ saved locally
→ upload begins
→ network dies

On restart, the app must know whether the previous attempt:
- definitely succeeded
- definitely failed
- may have succeeded but response was lost

Implement the safest possible behavior given the Last.fm API semantics.

Do not casually resend records in a way that creates unnecessary duplicate scrobbles.

Document any unavoidable API-level ambiguity.

==================================================
37. CONNECTIVITY
==================================================

Use the existing Musii connectivity infrastructure where possible.

When offline:

No repeated API attempts.

When connectivity returns:

Automatically wake the scrobble queue.

Do not block playback waiting for Last.fm.

Do not make track start latency depend on Last.fm availability.

Playback must always win.

==================================================
38. NON-BLOCKING PLAYBACK
==================================================

CRITICAL:

Never block audio playback because Last.fm is slow or unavailable.

When a track starts:
- playback starts immediately
- Last.fm operations happen asynchronously
- network failures never stop playback
- scrobble queue failures never crash playback

The integration must be completely decoupled from playback reliability.

==================================================
39. SETTINGS STATE REACTIVITY
==================================================

Settings changes must update immediately through Riverpod.

For example:

User turns Scrobbling OFF
→ state updates immediately
→ future tracks do not scrobble

User turns it ON
→ integration resumes

User disconnects account
→ UI changes immediately
→ authenticated work stops
→ pending records are handled according to the designed disconnect policy

Do not require app restart.

==================================================
40. LAST.FM SETTINGS SCREEN — VISUAL DESIGN
==================================================

The screen should follow the new premium Musii design language.

Avoid:
- giant Last.fm branded card
- excessive red
- rounded rectangles everywhere
- dashboard styling
- dense technical information
- default Flutter SwitchListTile appearance if it clashes with the established design

Use:
- dark atmospheric Musii background
- quiet typography
- subtle separators
- strong hierarchy
- restrained Last.fm branding
- native-feeling Cupertino interaction patterns

The screen should feel like part of Musii, not an embedded third-party page.

==================================================
41. DISCONNECTED STATE — VISUAL DESIGN
==================================================

Design a beautiful first-use state.

Concept:

Last.fm

Keep your listening
history in sync.

Connect Musii to automatically
scrobble the music you listen to.

             Connect

Do not show:
- fake avatar
- fake username
- fake connection status
- fake scrobble count

Everything visible must reflect real state.

==================================================
42. AUTHENTICATION SUCCESS — VISUAL DESIGN
==================================================

After authentication:

Last.fm

[real account avatar if available]

@real_username

Connected

Scrobbling                         ON
Now Playing                        ON

The transition should be polished.

Use:
- fade
- subtle movement
- no flashy success animation

==================================================
43. OFFLINE STATE — VISUAL DESIGN
==================================================

If offline scrobbles exist:

OFFLINE SCROBBLES

3 tracks waiting to sync

[art] Track
      Artist
      Waiting

At bottom:

Waiting for connection

Once synchronization begins:

Syncing 3 scrobbles…

Once successful:

✓ 3 scrobbles synced

All states must come from the real synchronization engine.

==================================================
44. ERROR STATE — VISUAL DESIGN
==================================================

For temporary failures:

Couldn't reach Last.fm

Your listening is safe.
We'll try again automatically.

Do not force a blocking modal over playback.

For authentication:

Last.fm needs you to reconnect.

Your recent listening is still safe.

Reconnect

For persistent configuration problems:

Last.fm isn't configured correctly.

Show the actual actionable remediation.

Do not tell the user to "try again" if retry cannot fix the problem.

==================================================
45. ACCOUNT DISCONNECT — VISUAL DESIGN
==================================================

Use a clean confirmation action sheet/dialog.

Disconnect Last.fm?

Musii will stop sending new
listening activity to Last.fm.

Your existing Last.fm history
will not be deleted.

Cancel
Disconnect

Ensure the actual implementation matches the wording.

Do not claim something will remain available if the implementation deletes it.

==================================================
46. REAL LAST.FM PROFILE
==================================================

"Open Last.fm profile" must open the user's real Last.fm account/profile.

Do not open a fake/example URL.

Use platform URL launching properly.

Handle failure gracefully.

==================================================
47. NO MOCKS ANYWHERE
==================================================

Absolutely no:

fake Last.fm username
fake profile URL
fake avatar
mock scrobble count
mock API response
fake connected state
dummy pending scrobbles
hardcoded successful response
simulated network state
static fake "scrobbled" toast

Tests may use mocks/fakes in test code, but production code must use the real integration.

==================================================
48. TESTING
==================================================

Add comprehensive automated tests.

At minimum test:

AUTHENTICATION

- disconnected initial state
- successful authentication
- failed authentication
- malformed auth response
- credential persistence
- restored authenticated session
- invalid session
- logout/disconnect

SETTINGS

- scrobbling defaults correctly
- Now Playing defaults correctly
- toggle persistence
- reactive toggle updates
- settings survive restart

PLAYBACK

- eligible track generates scrobble
- short track does not incorrectly scrobble
- pause/resume does not duplicate
- seek does not duplicate
- repeated track creates independent listening session
- switching tracks finalizes previous session appropriately
- background playback works
- restored playback state does not generate false scrobbles

NOW PLAYING

- correct metadata sent
- duplicate events avoided
- switching tracks sends appropriate events
- Now Playing OFF prevents events

OFFLINE

- offline eligible scrobble persisted
- process death preserves queue
- app restart restores queue
- connectivity recovery uploads queue
- successful upload removes/marks pending record
- failed upload remains retryable
- partial batch success is handled correctly

AUTH EXPIRATION

- pending scrobbles preserved
- authentication invalidation detected
- UI shows reconnect state
- reauthentication resumes queue

DISCONNECT

- future scrobbling stops
- account state cleared correctly
- pending state handled according to documented behavior

UI

- disconnected screen
- connected screen
- pending scrobbles screen
- error states
- reauthentication state
- no empty/incorrect states
- correct real-time updates
- accessible labels
- dark mode
- light mode

==================================================
49. WIDGET TEST REQUIREMENTS
==================================================

Follow existing Musii widget-test conventions.

The project has known Cupertino testing considerations and import collisions; respect the existing test conventions documented in the engineering handoff. :contentReference[oaicite:10]{index=10}

Tests must verify behavior, not merely that widgets render.

For toggles:
tap them and verify state changes.

For connect:
verify the resulting state after a simulated successful authentication boundary.

For pending scrobbles:
verify real state-driven rendering.

Do not merely assert that static text exists.

==================================================
50. ANALYTICS / LOGGING
==================================================

Use the existing structured app logger.

Log meaningful events such as:

Last.fm authentication started
Last.fm authentication succeeded
Last.fm authentication failed
Now Playing submitted
Scrobble queued
Scrobble submitted
Scrobble retry scheduled
Last.fm authentication expired
Pending queue resumed

Never log sensitive credentials.

Redact:
- session keys
- API secrets
- authorization artifacts
- request signatures

==================================================
51. PERFORMANCE
==================================================

Last.fm must have negligible impact on playback.

Do not:
- perform blocking network requests on playback paths
- rebuild entire Library when Last.fm state changes
- poll Last.fm unnecessarily
- wake the application repeatedly without reason
- download unnecessary data
- perform expensive database scans for every playback position update

Playback-position handling must be efficient.

Do not write a database row on every second of playback.

Persist state at meaningful lifecycle transitions only.

==================================================
52. BACKGROUND SERVICE / AUDIO HANDLER
==================================================

Integrate with the current Musii playback architecture.

The project already uses AudioService/MusiiAudioHandler for background playback and system controls. Last.fm logic must observe the canonical playback state rather than UI-only events. :contentReference[oaicite:11]{index=11}

Do not attach scrobbling behavior only to:
- Now Playing widget
- MiniPlayer
- Library screen

A track played from Android lock screen controls must behave exactly like a track played from the Library.

==================================================
53. OFFLINE-FIRST PRODUCT BEHAVIOR
==================================================

Last.fm availability must never determine whether the user can listen.

This must work:

No internet
→ play music
→ queue scrobble locally
→ close app
→ reopen app
→ reconnect
→ automatically sync

No data loss.

==================================================
54. ACCESSIBILITY
==================================================

All Last.fm UI must have:

- accessible labels
- meaningful semantics
- sufficient contrast
- usable touch targets
- support for large text where practical
- no critical state represented by color alone

Examples:

Do not communicate only:

red = disconnected

Instead communicate with actual text.

==================================================
55. THEME SUPPORT
==================================================

The primary visual direction is the existing Musii dark aesthetic.

Also ensure the complete Last.fm settings feature works in Light Mode.

The existing app supports:
- Follow System
- Dark Mode
- Light Mode

Do not hardcode dark-only colors into widgets. :contentReference[oaicite:12]{index=12}

==================================================
56. UI MOTION
==================================================

Use subtle animations for:

- connected/disconnected transition
- pending queue appearing/disappearing
- successful scrobble feedback
- status transitions
- account avatar appearing

Do not use excessive animations.

Do not animate network failures.

Do not use animation as a substitute for actual functionality.

==================================================
57. DESIGN OF RECENT SCROBBLES
==================================================

If implemented, reuse Musii's existing song-row design.

Example:

Today

[album art]   Aaj Unse Kehna Hai
              Salman Khan
                                      4:18 PM

[album art]   Arjan Vailly
              Bhupinder Babbal
                                      4:13 PM

The list should feel like Musii's music history, not a web dashboard.

==================================================
58. DESIGN OF STATUS INFORMATION
==================================================

Keep technical information subdued.

Preferred:

3 scrobbles waiting to sync

Last synced 2 min ago

Avoid:

HTTP 503
Retry #2
API status: pending

These details may exist in developer logs, but they do not belong in the normal user interface.

==================================================
59. NO LAST.FM CLUTTER
==================================================

Do not put Last.fm branding:
- throughout Library
- permanently in the MiniPlayer
- on every song row
- permanently inside Now Playing
- in bottom navigation

Last.fm should become visible only where useful.

Normal music listening remains the primary Musii experience.

==================================================
60. FAILURE PHILOSOPHY
==================================================

When Last.fm fails:

Musii keeps playing.

When Last.fm is offline:

Musii keeps playing.

When authentication expires:

Musii keeps playing.

When the pending queue is large:

Musii keeps playing.

When the Last.fm API is unavailable:

Musii keeps playing.

Last.fm is an integration, never a playback dependency.

==================================================
61. DATA CONSISTENCY
==================================================

Do not create a second source of truth for Track metadata.

Use existing Musii Track/Artist/Album data.

The Last.fm integration should consume canonical application metadata.

If metadata normalization is already centralized in Musii, reuse it where appropriate rather than duplicating normalization logic.

==================================================
62. DATABASE MIGRATION
==================================================

If Last.fm requires new Drift tables/columns:

- increment schema version correctly
- write a real migration
- preserve all existing library data
- test upgrade from the existing schema
- test fresh database creation
- test migration with existing playback/library data

Do not reset the database.

Do not use destructive migration.

==================================================
63. APP BOOTSTRAP
==================================================

Integrate Last.fm initialization into the existing application bootstrap/providers appropriately.

Do not cause application startup to block waiting for Last.fm.

Startup should:

- restore local Last.fm settings
- restore credentials safely
- restore pending queue state
- initialize services
- schedule background synchronization where appropriate

The main app should remain responsive immediately.

==================================================
64. CLEAN ARCHITECTURE
==================================================

Prefer domain concepts such as:

LastFmAccount
LastFmConnectionState
ScrobbleSettings
PendingScrobble
ScrobbleStatus
ScrobbleResult

and repository contracts such as:

LastFmRepository
ScrobbleRepository

only where they genuinely fit the existing architecture.

Do not create unnecessary abstraction layers simply to make the code look architecturally sophisticated.

Keep interfaces meaningful.

==================================================
65. ERROR TYPES
==================================================

Extend the existing failure hierarchy appropriately.

Potential concepts:

LastFmAuthenticationFailure
LastFmNetworkFailure
LastFmApiFailure
LastFmRateLimitFailure
LastFmInvalidSessionFailure
LastFmConfigurationFailure

Use the project's existing failure conventions.

Repositories must not leak raw exceptions.

==================================================
66. SECURITY
==================================================

Security requirements:

- no secrets in source control
- no secrets in logs
- secure credential persistence
- validate authentication results
- safely handle callback/deep-link state
- protect against malformed external responses
- do not trust arbitrary username/avatar data for unsafe UI rendering
- escape/handle user-provided strings normally
- avoid leaking credentials in crash reporting/logging

Follow Android best practices appropriate to the actual authentication mechanism selected.

==================================================
67. NETWORKING
==================================================

Reuse the project's existing networking infrastructure if appropriate.

Implement:
- request timeouts
- robust response handling
- retry strategy
- API error decoding
- rate-limit handling
- authentication failure detection

Do not create endless retries.

Do not execute synchronous network calls on the UI thread.

==================================================
68. USER EXPERIENCE AFTER FIRST CONNECTION
==================================================

After successful connection:

Return the user to the Last.fm settings page.

Show their actual account.

Make Scrobbling ON/OFF immediately understandable.

Do not force the user through additional unnecessary setup steps.

The preferred journey is:

Settings
→ Last.fm
→ Connect
→ Authenticate
→ Connected as @username
→ Scrobbling ON

Then the feature gets out of the way.

==================================================
69. USER EXPERIENCE DURING NORMAL LISTENING
==================================================

Once configured:

User plays track
→ playback immediately starts
→ Now Playing sent if enabled
→ listening tracked
→ scrobble becomes eligible
→ final scrobble submitted
→ subtle confirmation
→ no interruptions

User should not have to interact with Last.fm during normal listening.

==================================================
70. USER EXPERIENCE OFFLINE
==================================================

User loses network.

Musii:
- continues playback
- stores eligible scrobbles
- shows pending count only where appropriate
- does not interrupt listening

Network returns.

Musii:
- automatically synchronizes
- updates status
- clears successful pending records
- leaves only genuine failures/re-auth requirements

==================================================
71. UI COPY
==================================================

Use concise, confident copy.

Preferred:

Connected as @username

Scrobble automatically

Now Playing

3 scrobbles waiting to sync

Waiting for connection

Syncing…

Scrobled to Last.fm

Reconnect Last.fm

Disconnect Last.fm

Avoid:
- technical jargon
- verbose explanations
- fake enthusiasm
- marketing-heavy language
- debug terminology

Correct spelling everywhere.

==================================================
72. VISUAL DESIGN PRINCIPLES
==================================================

The Last.fm experience must inherit Musii's premium redesign direction:

- dark
- cinematic
- restrained
- minimal
- spacious
- typography-first
- no giant cards
- no excessive pills
- no excessive borders
- no dashboard aesthetic

Last.fm's branding should be recognizable but subordinate to Musii's design system.

==================================================
73. SETTINGS ROOT VISUAL
==================================================

The final Settings root should look approximately conceptually like:

Settings

ACCOUNT
Google Drive                         >

PLAYBACK
Audio Quality                        >
Playback                             >
Queue                                >

LIBRARY
Sync Library                         >
Downloads                            >

SERVICES
Last.fm
Connected as @username              >

APPEARANCE
Appearance                           >

ABOUT
About Musii                          >

Do not turn the Last.fm row into a special oversized promotional card.

==================================================
74. LAST.FM DETAIL VISUAL
==================================================

Connected state:

Last.fm

[real avatar]
@username
Connected

SCROBBLING

Scrobble automatically              ON
Now Playing                         ON

OFFLINE SCROBBLES

3 tracks waiting to sync             >

SCROBBLE ACTIVITY

128 scrobbles synced
Last synced 2 min ago

ACCOUNT

Open Last.fm profile                 >
Disconnect Last.fm                   >

Do not literally copy this layout without adapting it to Musii's existing component system.

==================================================
75. DISCONNECTED VISUAL
==================================================

Disconnected state:

Last.fm

Keep your listening
history in sync.

Connect Musii to automatically
scrobble the music you listen to.

Connect Last.fm

Do not show settings that cannot function yet unless the disabled state is clearly meaningful.

==================================================
76. PENDING SCROBBLE DETAIL VISUAL
==================================================

Pending list:

Offline Scrobbles

3 tracks waiting to sync

[art] Track title
      Artist
      Waiting

[art] Track title
      Artist
      Waiting

Bottom status:

Waiting for connection

or:

Syncing…

or:

✓ 3 scrobbles synced

The entire screen must be data-driven.

==================================================
77. PRODUCT POLISH
==================================================

The integration must feel finished.

Pay attention to:
- loading transitions
- keyboard/browser return behavior during auth
- status changes
- account restoration
- offline/online transitions
- empty states
- long usernames
- long artist names
- missing artwork
- duplicated playback events
- app restarts
- process death
- background playback
- error recovery

There should be no obvious "AI-generated prototype" behavior.

==================================================
78. DO NOT OVERENGINEER
==================================================

Do not add unrelated features such as:

- social feeds
- Last.fm recommendations
- Last.fm radio
- Last.fm chart browsing
- unrelated artist metadata
- unrelated web scraping
- arbitrary statistics dashboards

The scope is:

AUTHENTICATION
NOW PLAYING
SCROBBLING
OFFLINE QUEUE
RETRY
STATUS
ACCOUNT
SETTINGS
RELIABILITY

==================================================
79. FINAL VALIDATION
==================================================

Before considering the feature complete, verify the complete real-world lifecycle:

CASE A

Fresh install
→ Settings
→ Last.fm
→ Connect
→ real Last.fm authentication
→ account appears
→ Scrobbling ON
→ play a song
→ Now Playing submitted if enabled
→ song becomes eligible
→ actual scrobble submitted

CASE B

Play while offline
→ eligible listening
→ pending scrobble saved
→ force-close app
→ reopen
→ pending scrobble still exists
→ reconnect network
→ automatically sync
→ pending queue clears

CASE C

Authentication expires
→ playback continues
→ scrobble cannot authenticate
→ pending record preserved
→ UI requests reconnect
→ user reconnects
→ pending records resume

CASE D

Temporary Last.fm outage
→ playback continues
→ scrobble remains pending/retryable
→ service recovers
→ automatic synchronization resumes

CASE E

Scrobbling OFF
→ play tracks
→ no scrobbles created

CASE F

Now Playing OFF / Scrobbling ON
→ no Now Playing requests
→ eligible track still scrobbles

CASE G

Repeated track
→ first listening session scrobbles
→ track played again
→ second listening session can independently scrobble

CASE H

Background playback
→ screen locked
→ track transition occurs
→ Last.fm behavior still works

==================================================
80. REQUIRED VERIFICATION COMMANDS
==================================================

After implementation:

dart format .

If Drift schema changes:

dart run build_runner build --delete-conflicting-outputs

Then:

flutter analyze
flutter test

All analyzer issues must be resolved.

All tests must pass.

The existing engineering rules explicitly require clean analysis and passing tests and prohibit local APK/Gradle builds. :contentReference[oaicite:13]{index=13}

DO NOT run:

flutter build apk

Do not run local release Gradle builds.

==================================================
81. DOCUMENTATION
==================================================

Update:

docs/ai-handoff.md

Document:

- Last.fm integration architecture
- authentication flow
- credential storage
- scrobble lifecycle
- offline queue
- retry behavior
- authentication-expiration handling
- disconnect behavior
- database schema/migration
- important implementation pitfalls
- provider/API configuration
- testing strategy

The project's handoff explicitly requires architectural/database/UI changes to be recorded. :contentReference[oaicite:14]{index=14}

==================================================
82. FINAL QUALITY BAR
==================================================

The feature is NOT complete merely because:

- a Last.fm settings page exists
- a toggle exists
- a browser opens
- a fake success message appears
- a username is displayed
- a database row is created

It is complete only when the real integration works end-to-end.

The final product must satisfy:

REAL AUTH
REAL ACCOUNT
REAL NOW PLAYING
REAL SCROBBLING
REAL OFFLINE QUEUE
REAL RETRY
REAL PERSISTENCE
REAL ERROR HANDLING
REAL DISCONNECT
REAL BACKGROUND PLAYBACK SUPPORT
REAL SETTINGS
REAL TEST COVERAGE

No mocks in production.
No fake states.
No placeholders.
No TODOs for required functionality.

==================================================
83. FINAL PRODUCT EXPERIENCE
==================================================

The ideal experience is:

Settings
→ Last.fm
→ Connect
→ Authenticate
→ Connected as @username
→ Scrobbling ON

Then the user simply listens.

Online:

Play
→ Now Playing
→ Listen
→ Scrobble
→ subtle confirmation

Offline:

Play
→ Listen
→ save locally
→ continue listening

Back online:

Automatic synchronization
→ queue clears
→ status updates

If authentication expires:

Musii keeps playing
→ scrobbles remain safe
→ reconnect
→ queue resumes

The Last.fm integration should feel reliable enough that the user trusts Musii with their listening history.

Implement the feature fully, integrate it into the existing Musii architecture, and leave the codebase production-ready rather than prototype-ready.
