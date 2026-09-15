
# Master Coding-Agent Prompt — Musii Queue System: Drag Reordering, Context Actions, Queue Management & Production Polish

You are an AI coding agent working directly inside the existing **Musii** Flutter Android repository.

Implement a production-ready upgrade to the playback queue covering four phases:

1. **Q1 — Queue interaction foundation:** drag-and-drop reordering.
2. **Q2 — Track context actions:** long-press track actions.
3. **Q3 — Queue management:** removal, Play Next/Add to Queue semantics, queue persistence, duplicate handling, and robust state management.
4. **Q4 — Interaction polish:** haptics, drag animations, swipe-to-remove, optimistic UI, transitions, and edge-case hardening.

The final result should feel like a polished modern music-player queue while preserving Musii's existing Cupertino aesthetic, playback behavior, persistence model, and architecture.

This is a production implementation, not a prototype.

---

# 1. Existing architecture and non-negotiable rules

Read the repository before changing anything.

The project uses:

* Clean Architecture / DDD.
* Core, Domain, Data, Presentation layers.
* Riverpod v3.
* Drift SQLite.
* `just_audio`.
* `audio_service`.
* Cupertino-oriented UI.
* Persistent MiniPlayer / Now Playing.
* Existing queue support.
* Existing playback state infrastructure.

The handoff explicitly documents the queue as a dynamic playback queue sheet and `PlayerStateSnapshot` as an existing domain concept.  

Preserve the existing architecture.

Do not introduce a second playback queue implementation.

Do not allow UI widgets to directly mutate the audio player queue unless that is already the established repository architecture.

Do not build an APK locally.

Required verification:

```bash id="w7fjo8"
dart format .
flutter analyze
flutter test
```

All must pass.

Do not run:

```bash id="cf2grk"
flutter build apk
```

or local Gradle builds.

Update:

```text id="t1f0sv"
docs/ai-handoff.md
```

after implementation.

---

# 2. First step: inspect the existing queue implementation

Before writing code, locate and understand:

```text id="xj9j1a"
lib/features/playback/
lib/features/library/
lib/features/playlist/
```

and specifically identify:

* queue domain model;
* queue repository;
* playback repository;
* audio handler;
* `just_audio` queue synchronization;
* queue provider(s);
* queue sheet;
* queue item widget;
* `PlayerStateSnapshot`;
* persistence/restoration logic;
* current next/previous behavior;
* shuffle implementation;
* repeat implementation;
* track action sheets, if any;
* playlist actions, if any;
* favorites;
* navigation to artist/album;
* existing haptic utilities;
* existing design tokens.

Do not assume the current queue is implemented exactly as described in this prompt.

Adapt the implementation to the actual repository.

---

# 3. Product goal

The finished queue should support this interaction model:

```text
Tap
→ play/select track

Long press
→ track action sheet

Long press + drag
→ reorder queue

Swipe left
→ remove from queue

Queue overflow
→ queue-level actions
```

The queue should feel like a first-class part of the playback experience.

---

# 4. Core queue concepts

The queue must distinguish:

```text
NOW PLAYING
```

from:

```text
UP NEXT
```

The currently playing track should be visually identifiable and should not behave identically to upcoming items.

Conceptually:

```text
Queue

NOW PLAYING
────────────────
Artwork   Song A
          Artist

UP NEXT
────────────────
Artwork   Song B
          Artist

Artwork   Song C
          Artist

Artwork   Song D
          Artist
```

The exact visual implementation should follow existing Musii styling.

---

# 5. Q1 — Queue reordering

Implement drag-and-drop reordering of upcoming queue items.

The user should be able to press/long-press a queue row and move it vertically.

Example:

Before:

```text
A ← playing
B
C
D
E
```

Move D above B:

```text
A ← playing
D
B
C
E
```

The queue must update immediately and persist the new order.

---

# 6. Currently playing item

Do not allow the currently playing item to be arbitrarily moved through the upcoming queue unless the existing playback architecture already explicitly supports this.

Preferred behavior:

```text
Now Playing
    ↓
fixed/current

Up Next
    ↓
reorderable
```

If the current audio engine absolutely requires moving the current item as part of its queue model, preserve playback correctness above all else, but do not expose confusing UI behavior.

---

# 7. Do not use array indexes as durable queue identity

Do not identify queue items exclusively by:

```text
index
```

because indexes change whenever tracks are inserted, removed, or reordered.

Queue items should have stable identity.

Conceptually:

```dart id="unq2k7"
QueueItem {
  queueItemId
  trackId
}
```

A `trackId` identifies the underlying track.

A `queueItemId` identifies an occurrence of that track inside the queue.

This is important because duplicate tracks must be supported.

---

# 8. Duplicate queue entries

Duplicates are allowed.

Example:

```text
A
B
A
C
```

The two A entries are separate queue items.

Therefore:

```text
remove(queueItemId)
```

must remove exactly one occurrence.

Likewise:

```text
move(queueItemId, destination)
```

must move exactly that occurrence.

Do not implement duplicate handling using only `trackId`.

---

# 9. Drag interaction

Dragging should feel polished.

During drag:

* row lifts slightly;
* surrounding rows animate around it;
* row may receive a subtle scale/elevation change;
* the target position should be visually obvious;
* the queue must remain stable and predictable.

Do not introduce exaggerated animations.

The visual language should remain consistent with the existing Cupertino/translucent aesthetic.

---

# 10. Drag initiation

Prefer a long-press gesture to initiate queue dragging.

Avoid making a permanent visible drag handle mandatory unless the existing design strongly benefits from one.

The desired interaction is:

```text
press/hold
↓
subtle haptic response
↓
row enters drag state
↓
move vertically
```

Do not create conflicts where a short tap accidentally starts dragging.

---

# 11. Haptic feedback

Use haptics at meaningful interaction points if the existing app already has a haptic abstraction.

Recommended moments:

```text
drag begins
item settles into a new position
optional destructive action confirmation
```

Do not fire haptics on every pointer movement.

Do not add a new dependency solely for standard Flutter haptic feedback if the framework already provides the required functionality.

---

# 12. Persist reorder immediately

When the user finishes dragging:

```text
new local queue order
        ↓
persist
        ↓
synchronize playback queue
```

Do not require a second save action.

The UI should optimistically reflect the new order immediately.

---

# 13. Playback engine synchronization

Changing the queue order in the UI is not sufficient.

Ensure the actual playback engine/audio handler sees the new order.

The handoff documents full queue synchronization in the `AudioService`/media-session layer. 

After reorder:

```text
UI queue
      ↓
domain queue
      ↓
playback repository/audio handler
      ↓
just_audio/audio_service
```

The system state must remain consistent.

---

# 14. Preserve current playback position during reorder

If the currently playing track is unaffected:

```text
reorder upcoming items
```

must not restart the current track.

Do not reset:

* playback position;
* playing state;
* current track;
* repeat mode;
* shuffle mode;

merely because the queue was reordered.

---

# 15. Q2 — Long-press track action sheet

Long-pressing a track should present a Cupertino-style track action sheet.

The sheet should identify the selected track:

```text
Song Title
Artist Name
```

followed by context-aware actions.

---

# 16. Core track actions

Implement the appropriate subset of:

```text
Play Now
Play Next
Add to Queue
Add to Playlist
Favorite / Unfavorite
Go to Album
Go to Artist
Share
Remove from Queue
Cancel
```

The menu must be context-aware.

Do not show nonsensical actions.

For a track already in the queue:

```text
Remove from Queue
```

makes sense.

Showing:

```text
Add to Queue
```

may still be valid when duplicates are allowed, but think carefully about whether it is useful in that context.

Use product semantics consistently.

---

# 17. Reusable track action system

Do not implement a unique hard-coded action sheet only inside the queue.

Where practical, create a reusable track-action abstraction, such as:

```text
TrackAction
TrackActionContext
TrackActionSheet
```

Potential contexts:

```text
queue
album
artist
playlist
search
library
favorites
```

Different contexts can expose different actions.

This should become the shared action model for the application rather than creating slightly different behavior on every screen.

---

# 18. Play Now semantics

For a track outside the current playback position:

```text
Play Now
```

should make that track the current playing item and establish the appropriate subsequent queue according to existing product behavior.

Do not unexpectedly destroy the entire queue unless that is the existing Musii semantic.

Inspect current playback behavior first.

---

# 19. Play Next semantics

This must be deterministic.

Given:

```text
A ← playing
B
C
D
```

select:

```text
D → Play Next
```

result:

```text
A ← playing
D
B
C
```

Then select:

```text
E → Play Next
```

result:

```text
A ← playing
D
E
B
C
```

Repeated Play Next operations should preserve the order in which the user requested them.

Do not implement it by constantly inserting at index 1 if an already queued Play Next segment exists and doing so would reverse the requested order.

Model the semantics intentionally.

---

# 20. Add to Queue semantics

Given:

```text
A ← playing
B
C
D
```

select:

```text
E → Add to Queue
```

result:

```text
A ← playing
B
C
D
E
```

This means:

```text
Play Next
```

and:

```text
Add to Queue
```

are distinct operations.

---

# 21. Add to Playlist

Selecting:

```text
Add to Playlist
```

should open a second Cupertino sheet/dialog for playlist selection.

Do not display the entire playlist-selection experience inside the first action sheet.

Conceptually:

```text
Track action sheet
      ↓
Add to Playlist
      ↓
Playlist picker
```

The picker should:

* show existing playlists;
* support the existing playlist architecture;
* avoid duplicate track insertion if current playlist rules prohibit it;
* provide a path to create a new playlist if that functionality already exists or can be cleanly integrated.

Do not implement a fake playlist backend.

---

# 22. Favorite

Use the existing favorite infrastructure.

The action should dynamically show:

```text
Add to Favorites
```

or:

```text
Remove from Favorites
```

depending on current state.

Do not maintain a second favorite state inside the queue UI.

---

# 23. Album / Artist navigation

Use existing navigation/routes/providers.

Do not duplicate track lookup logic inside the queue.

If the track has no album/artist information, hide or disable the corresponding action gracefully.

---

# 24. Share

Use the existing sharing implementation if present.

Do not introduce a fake "shared" state.

If share functionality is not currently implemented, inspect the codebase before adding a new dependency. Keep this action out rather than inventing an incomplete implementation.

---

# 25. Remove from Queue

Removing a queue item must:

* immediately update UI;
* update the underlying playback queue;
* preserve current playback where possible;
* persist the new queue state;
* work correctly with duplicates.

Example:

```text
A ← playing
B
C
B
D
```

Removing the second B must produce:

```text
A
B
C
D
```

not remove both Bs.

---

# 26. Removing the currently playing item

Define and implement safe semantics.

Do not allow removal to accidentally stop playback or corrupt the queue.

Preferred behavior:

* the currently playing item is not presented with a destructive Remove action;
* or removal immediately advances playback according to the existing player semantics.

Choose the behavior that best matches the existing playback engine and document it.

The important requirement is:

> Removing a track must never leave the audio service referencing an invalid queue index/item.

---

# 27. Q3 — Queue-level management

Add a compact queue-level action menu.

Possible actions:

```text
Clear Up Next
Shuffle
```

and any existing queue-level controls that already belong there.

Do not overfill the header.

---

# 28. Clear Up Next

The safest semantic is:

```text
Current track remains playing
All upcoming tracks are removed
```

For:

```text
A ← playing
B
C
D
```

Clear Up Next produces:

```text
A ← playing
```

It must not stop A merely because upcoming items were removed.

---

# 29. Queue empty state

When there are no upcoming tracks, the sheet should communicate:

```text
Playing now
Nothing up next
```

or equivalent wording consistent with Musii.

Do not leave an awkward blank list.

The current playing track can remain visible even when there is no up-next queue.

---

# 30. Queue persistence

Inspect the existing playback-state persistence before adding anything new.

The handoff already contains `PlayerStateSnapshot`, so use/extend the existing persistence architecture rather than creating an independent queue persistence database. 

The queue should survive appropriate application lifecycle events according to the existing Musii persistence model.

At minimum, preserve:

```text
queue contents
queue ordering
current item
```

and any existing playback state that the app already persists.

---

# 31. Queue restoration

When the application/player initializes:

```text
persisted queue
       ↓
restore domain queue
       ↓
restore audio handler queue
       ↓
restore current item
```

Avoid duplicate queue insertion during restoration.

There must not be:

```text
old queue
+
restored queue
```

accidentally merged together.

---

# 32. Duplicate initialization prevention

Make queue initialization idempotent.

Do not permit:

```text
app bootstrap
+
provider initialization
+
audio handler initialization
```

to each append/restore the same tracks.

There should be one authoritative initialization pathway.

---

# 33. Queue and shuffle

The application already supports shuffle and repeat modes in the Now Playing control cluster. 

Do not break those modes.

Separate:

```text
user-defined queue
```

from:

```text
playback scheduling/order
```

where practical.

Manual reordering should not unexpectedly erase the user's queue simply because shuffle is enabled.

---

# 34. Shuffle semantics

Inspect the existing shuffle implementation first.

Do not invent a parallel shuffle algorithm.

If the current audio engine handles shuffle internally, integrate with that.

The important product rule is:

> Manually changing the queue should not cause the current track to restart or cause arbitrary destructive queue mutations.

---

# 35. Repeat semantics

Preserve:

```text
repeat off
repeat all
repeat one
```

Do not make queue clearing/removal accidentally alter repeat mode unless existing product semantics require it.

The current repeat control is documented in the handoff. 

---

# 36. Queue operations as explicit domain operations

Do not scatter queue list manipulation across UI widgets.

Prefer explicit operations such as:

```dart
moveItem(queueItemId, destinationIndex)
removeItem(queueItemId)
playNext(trackId)
enqueue(trackId)
clearUpNext()
```

The exact API can differ based on the existing architecture.

The important principle is:

> Queue business rules belong in the queue/playback domain/repository layer, not inside widget callbacks.

---

# 37. Optimistic UI

Queue actions should feel instant.

For example:

```text
drag
 ↓
UI changes immediately
 ↓
persist/synchronize
```

not:

```text
drag
 ↓
database operation
 ↓
audio service operation
 ↓
eventually UI changes
```

Likewise for removal.

However, if a downstream operation fails, the UI must have a safe rollback/reconciliation strategy.

Do not blindly assume persistence can never fail.

---

# 38. Failure recovery

If a queue mutation fails:

```text
operation
↓
failure
```

restore/reconcile the UI with the authoritative queue state.

Do not leave:

```text
UI queue != playback queue
```

silently.

Follow the project's `Result` / failure conventions. 

---

# 39. Queue state consistency invariant

At all times, these layers should converge on the same logical queue:

```text
UI
Domain
Persistence
Audio Handler
just_audio
```

There must be one logical queue.

If there are temporary optimistic differences, they must be short-lived and resolved deterministically.

---

# 40. Q4 — Swipe-to-remove

Add swipe-left removal for upcoming tracks if it integrates cleanly with existing gestures.

Preferred interaction:

```text
Swipe left
   ↓
Remove
```

Do not implement swipe-right and swipe-left with a large collection of unrelated actions.

Keep:

```text
drag = reorder
swipe left = remove
long press = actions
```

as the primary interaction vocabulary.

---

# 41. Gesture conflict handling

This is important.

Dragging and swiping must not interfere with each other.

The implementation should make these gestures distinguishable:

```text
vertical long-press/move
→ drag

horizontal swipe
→ remove

short tap
→ play/select
```

Do not create a situation where a user attempting to drag vertically accidentally removes a track.

Use appropriate gesture thresholds.

---

# 42. Swipe confirmation

A swipe should visually reveal the destructive action before it commits.

The user should have a clear indication:

```text
Remove
```

rather than the item disappearing with no explanation.

Use the existing design system.

---

# 43. Undo consideration

If Musii already has a snackbar/toast pattern, consider:

```text
Removed "Song"
[Undo]
```

for accidental removals.

Do not add an entire new notification framework solely for this.

If implementing Undo, make sure it is queue-item-aware so duplicate tracks restore to the correct original position.

---

# 44. Drag animation

During drag, use a subtle physical response:

```text
normal
 ↓
slight lift
 ↓
slight scale/elevation
 ↓
move
 ↓
settle
```

When released, the row should settle naturally into the new position.

Avoid overly springy movement.

---

# 45. Haptic design

Haptics should be:

```text
meaningful
sparse
consistent
```

Recommended:

* drag initiation: light feedback;
* item crosses/settles into a new slot: optional light feedback;
* destructive removal: optional confirmation feedback.

Do not vibrate on every pixel of movement.

---

# 46. Queue sheet animation

When queue contents change:

* inserted item can gently appear;
* removed item can gracefully disappear;
* reordered items should move smoothly;
* avoid rebuilding the entire sheet visually whenever one item changes.

Use stable keys.

---

# 47. Stable widget keys

Because duplicate tracks are supported, do not use:

```dart
ValueKey(track.id)
```

for queue rows if the same track can occur twice.

Use:

```dart
ValueKey(queueItem.queueItemId)
```

or an equivalent stable queue-entry identity.

This is important for correct drag/reorder animations.

---

# 48. Queue row design

Keep the queue visually compact.

Recommended structure:

```text
┌──────────────────────────────────────┐
│ Artwork   Song Title                 │
│           Artist                     │
└──────────────────────────────────────┘
```

Current track can include a subtle playing indication.

Do not permanently expose every action button.

Keep the default state uncluttered.

---

# 49. Current track emphasis

The current track should be visually stronger than upcoming tracks, but not enormous.

Possible treatment:

```text
Current:
stronger title/artist
playing indicator

Upcoming:
normal emphasis
```

Reuse existing typography/colors.

Do not introduce a giant current-track card unless the existing Musii design already uses that language.

---

# 50. Long-press visual feedback

Before opening the action sheet:

```text
press and hold
↓
row subtly highlights
↓
light haptic
↓
sheet opens
```

The user should clearly understand which row they invoked.

---

# 51. Context-aware actions

A queued track should expose:

```text
Play Now
Play Next
Add to Playlist
Favorite
Go to Album
Go to Artist
Remove from Queue
```

An arbitrary library track can expose:

```text
Play Now
Play Next
Add to Queue
Add to Playlist
Favorite
Go to Album
Go to Artist
```

Adjust based on actual application capabilities.

Do not expose actions that do nothing.

---

# 52. Queue action model

Where useful, define a central action enum:

```text
TrackAction
```

with handlers in the appropriate application/domain layer.

Do not let the action sheet itself manipulate:

```text
AudioPlayer
DriftDatabase
Google Drive
```

directly.

---

# 53. AudioService integration

The handoff documents `AudioService` handling queue synchronization, including `skipToQueueItem`, queue updates, and media controls. 

Make queue reorder/removal/insertion compatible with that infrastructure.

Verify that:

```text
previous
next
skipToQueueItem
notification queue
Android Auto queue where applicable
```

remain correct after mutations.

---

# 54. Queue index correctness

Be extremely careful with queue indices when removing/reordering.

The currently playing item may change index after a mutation.

Do not assume:

```text
currentIndex
```

remains unchanged numerically.

Use stable queue identity where possible and derive the new playback index after queue mutation.

---

# 55. Queue mutation while playing

Test mutations such as:

```text
reorder first upcoming item
remove item before current playback index
remove item after current playback index
insert Play Next
insert duplicate
clear Up Next
```

while audio is actively playing.

The track currently producing audio must continue correctly unless the user explicitly chooses Play Now or otherwise changes playback.

---

# 56. Queue mutation while paused

All mutations should work while paused without unexpectedly starting playback.

Do not turn:

```text
remove/reorder
```

into:

```text
play
```

---

# 57. Queue mutation from multiple UI surfaces

If queue changes can originate from:

```text
queue sheet
track action sheet
album page
search
playlist
library
```

all should eventually converge on the same queue repository/domain operations.

Do not maintain separate business logic for each screen.

---

# 58. Search/library integration

When:

```text
Add to Queue
Play Next
Play Now
```

are invoked outside the queue, the same queue model must be used.

This feature should establish the reusable queue API for the entire app.

---

# 59. Empty/initial queue

When no queue exists:

```text
Add to Queue
```

should create the appropriate queue.

```text
Play Next
```

should behave safely and deterministically when there is no current/up-next item.

Do not assume there is always a playing track.

---

# 60. No-current-track scenario

The queue model must handle:

```text
no current track
queue contains tracks
```

without crashing.

In that state, `Play Now` should be able to establish the current track.

---

# 61. Queue identity and playlist/library track identity

A queue entry should refer to the domain track, not duplicate all track metadata into the queue model.

Avoid:

```text
QueueItem
  title
  artist
  album
  ...
```

as the source of truth.

Prefer:

```text
QueueItem
  queueItemId
  trackId
```

and resolve track metadata through the existing track/library model.

This prevents queue metadata becoming stale.

---

# 62. Persistence schema

Inspect existing database tables before deciding whether a new `QueueItems` table is necessary.

If current queue state is already persisted through the playback/player state model, extend it correctly.

If normalized queue storage is needed, implement it through Drift with:

```text
queueItemId
trackId
position/order
```

and any necessary current-item information.

Use existing Drift naming conventions and avoid class-name collisions. The handoff specifically calls out the use of `@DataClassName('<Entity>Row')` for Drift entities. 

---

# 63. Database migration

If schema changes are necessary:

* increment schema correctly;
* write a real migration;
* preserve existing data;
* regenerate code;
* test migration behavior.

Do not delete/recreate unrelated tables.

---

# 64. Queue persistence frequency

Persist queue mutations at safe operation boundaries:

```text
after reorder completes
after insertion
after removal
after clear
after current-item changes where appropriate
```

Do not write to SQLite continuously during every drag pixel.

---

# 65. Drag-time performance

While dragging:

* do not write every intermediate position to the database;
* keep intermediate state in memory;
* persist final order when drag settles.

This avoids unnecessary database writes.

---

# 66. Queue loading performance

The queue should render quickly even if it contains many items.

Use the existing list/sliver patterns.

Do not load every album-art image at massive resolution.

Reuse the existing artwork caching/thumbnail behavior. The handoff already documents optimized artwork sizing and a large in-memory image cache. 

---

# 67. No unnecessary metadata fetching

Queue rendering must not trigger metadata downloads.

The queue should use already persisted track information.

Do not make a queue row call Google Drive just because it needs:

```text
title
artist
album
artwork
```

Use the local repository/cache.

This is particularly important given the previous sync optimization work.

---

# 68. Error handling

Follow the existing failure model.

Examples:

```text
reorder persistence fails
→ reconcile queue

add to playlist fails
→ show existing error UX

remove fails
→ restore item

audio queue update fails
→ reconcile with authoritative playback state
```

Do not silently swallow failures.

Do not crash playback because a UI queue operation failed.

---

# 69. Offline operation

Queue operations should work offline whenever the necessary track data is already local.

Do not require Google Drive availability for:

* reorder;
* remove;
* enqueue;
* Play Next;
* favorite;
* queue persistence.

The existing app is offline-first. 

---

# 70. Queue and downloaded/offline tracks

Do not assume a queue item must be downloaded.

The existing playback/cache layer determines whether playback uses:

* local cached audio;
* remote streaming.

Queue manipulation should operate independently of cache state.

---

# 71. Testing — domain queue operations

Add comprehensive unit tests for:

```text
enqueue
playNext
remove
move
clearUpNext
duplicate entries
current item handling
empty queue
no-current-track state
```

Examples:

### Play Next order

```text
A
B
C
```

Play Next D:

```text
A
D
B
C
```

Then Play Next E:

```text
A
D
E
B
C
```

### Duplicate removal

```text
A
B
A
```

remove second A:

```text
A
B
```

### Reordering

```text
A
B
C
D
```

move D to position 1:

```text
A
D
B
C
```

---

# 72. Testing — queue persistence

Test:

```text
save queue
kill/reinitialize repository
restore queue
```

and confirm:

* same order;
* same duplicates;
* same current item.

---

# 73. Testing — audio queue synchronization

Mock the playback/audio handler where appropriate.

Verify:

```text
domain reorder
→ audio queue reorder/update
```

and:

```text
remove
→ audio handler receives correct mutation
```

Do not initialize raw `AudioService` unnecessarily in tests; the existing handoff documents native platform-channel pitfalls and recommends provider overrides/direct handler construction for tests. 

---

# 74. Testing — widget queue

Add widget tests for:

* queue displays current item;
* upcoming items display in order;
* long press opens track actions;
* remove action removes the correct item;
* duplicate tracks remain distinguishable;
* empty queue state renders;
* clear Up Next behaves correctly.

Use stable queue-item keys.

---

# 75. Testing — drag reorder

Test the reorder logic independently of exact gesture-frame timing.

Where widget-level gesture testing is practical, verify:

```text
drag item
→ final queue order correct
```

Do not create brittle tests that depend on exact animation frame counts.

---

# 76. Testing — swipe removal

Verify:

```text
swipe row
→ correct queue item removed
```

and especially:

```text
duplicate track occurrences
```

remove only one instance.

---

# 77. Testing — action semantics

Verify at minimum:

```text
Play Now
Play Next
Add to Queue
Remove from Queue
Add to Playlist
Favorite
```

using mocks/fakes for downstream repositories where appropriate.

---

# 78. Regression tests for playback

Verify that queue operations do not accidentally:

* stop playback;
* restart playback;
* reset playback position;
* change repeat mode;
* corrupt current item;
* make next/previous invalid.

The existing playback system is more important than the queue UI.

---

# 79. Navigation tests

Verify:

```text
Go to Album
Go to Artist
```

use existing navigation paths and do not create duplicate routes.

---

# 80. Accessibility

Queue rows should remain understandable with:

* larger text;
* screen-reader semantics where existing app conventions support them;
* sufficient contrast.

Do not communicate queue order solely with animation.

---

# 81. Avoid unnecessary visual clutter

Do not permanently put:

```text
Play
Play Next
Add
Favorite
Remove
More
```

buttons on every row.

The default queue should remain clean.

Use:

```text
tap
long press
drag
swipe
```

to progressively reveal functionality.

---

# 82. Queue header

A compact queue header can include:

```text
Queue
12 songs
⋯
```

or equivalent.

The overflow action should expose queue-level functions such as:

```text
Clear Up Next
```

without overwhelming the sheet.

---

# 83. Queue count

Ensure the count reflects actual up-next items and does not accidentally include the current item unless that is explicitly the established product convention.

Choose one convention and use it consistently.

---

# 84. Action-sheet dismissal

After an action succeeds:

* dismiss the sheet appropriately;
* refresh/reconcile the queue state;
* provide lightweight feedback where useful.

Do not leave stale action sheets open over a changed queue.

---

# 85. Long-press race conditions

Avoid cases where:

```text
long press
+
drag
```

opens an action sheet after the user has started dragging.

Gesture recognition must make the interaction deterministic.

---

# 86. Rapid queue mutations

Users may:

```text
Play Next A
Play Next B
Play Next C
```

quickly.

Ensure these operations serialize correctly or use a centralized queue mutation coordinator.

The final queue must reflect the intended order.

---

# 87. Queue mutation serialization

There should be one authoritative queue mutation pathway.

Do not allow simultaneous operations such as:

```text
drag reorder
+
remove
+
Play Next
```

to corrupt ordering.

Use the existing repository/state architecture to serialize mutations where needed.

---

# 88. Concurrency with playback events

Playback can independently emit:

```text
track changed
queue changed
position changed
```

while the user modifies the queue.

Ensure event handling does not overwrite newer user changes with stale state.

Prefer versioned/authoritative state reconciliation if needed.

Do not use arbitrary delays as a synchronization mechanism.

---

# 89. Queue refresh from audio handler

If the audio handler is authoritative for any part of queue state, make sure UI refreshes do not repeatedly recreate or reorder the queue incorrectly.

The flow should be explicit:

```text
user operation
→ queue mutation
→ audio handler synchronization
→ resulting state
→ UI
```

rather than:

```text
user operation
→ local list mutation
→ background listener unexpectedly restores old queue
```

---

# 90. App restart

After app restart:

```text
persisted queue
↓
restore
↓
UI queue
↓
audio handler queue
```

must have identical logical order.

Do not duplicate tracks.

Do not lose queue positions.

---

# 91. Android media controls

Because MediaSession/AudioService integration already supports queue synchronization, verify that queue changes remain compatible with system controls. 

In particular, after mutation:

* next works;
* previous works;
* skip-to-item where supported works;
* notification queue remains sensible.

---

# 92. Queue clear behavior and media session

Clearing Up Next must not leave the Android media-session queue containing stale upcoming items.

Synchronize the media-session queue with the new logical queue.

---

# 93. No fake queue state

Do not solve UI problems by maintaining:

```text
fakeQueueForUI
```

separate from the real playback queue.

The UI must represent the real queue.

---

# 94. Production logging

Use the existing structured logger for significant operations:

```text
queue item added
queue item removed
queue reordered
play next
clear up next
queue restored
queue mutation failure
audio queue reconciliation
```

Do not log unnecessary personal/media data.

---

# 95. Performance acceptance

The queue must remain responsive with at least thousands of logical queue items.

Do not:

* rebuild the entire app on every reorder;
* write SQLite on every drag movement;
* create expensive metadata lookups for every frame;
* re-download artwork;
* repeatedly recreate the audio handler queue unnecessarily.

---

# 96. Implementation order

Implement in this order:

```text
1. Inspect existing queue architecture
2. Define/strengthen QueueItem identity
3. Centralize queue mutation operations
4. Implement Q1 drag reorder
5. Synchronize reorder with playback/audio service
6. Add Q2 reusable track action model
7. Implement Play Now / Play Next / Add to Queue
8. Implement playlist/favorite/navigation/remove actions
9. Implement Q3 queue persistence and restoration
10. Implement Clear Up Next
11. Harden duplicates/current-item behavior
12. Implement Q4 swipe removal
13. Add haptic/drag polish
14. Add optimistic updates + reconciliation
15. Add tests
16. Run analyzer/tests
17. Update ai-handoff.md
```

Do not start with visual polish before queue semantics are correct.

---

# 97. Definition of done — Q1

Q1 is complete when:

* upcoming tracks are draggable;
* current playback remains stable;
* final order is persisted;
* audio handler/just_audio reflects the new order;
* duplicate tracks reorder correctly;
* drag does not conflict with tap;
* drag feels visually polished;
* no excessive database writes occur during drag.

---

# 98. Definition of done — Q2

Q2 is complete when:

* long press presents a Cupertino-style action sheet;
* selected track is clearly identified;
* actions are context-aware;
* Play Now works;
* Play Next works;
* Add to Queue works;
* Add to Playlist works;
* Favorite works;
* Album/Artist navigation works where data exists;
* Remove from Queue works;
* no action directly manipulates infrastructure from the UI.

---

# 99. Definition of done — Q3

Q3 is complete when:

* queue is persistently restorable;
* order survives restart;
* duplicates survive correctly;
* current item is restored safely;
* Clear Up Next works;
* queue operations remain consistent with shuffle/repeat;
* next/previous continue working;
* no duplicate initialization occurs;
* queue state is consistent with the audio handler.

---

# 100. Definition of done — Q4

Q4 is complete when:

* swipe-left removal works;
* drag uses subtle animation;
* haptics are appropriate;
* row transitions are smooth;
* optimistic UI feels instantaneous;
* failures reconcile safely;
* gesture conflicts are resolved;
* queue remains performant;
* visual design remains consistent with Musii.

---

# 101. Full acceptance test

The coding agent must be able to verify this complete interaction:

```text
Queue:

A ← playing
B
C
D
```

Long press D:

```text
D
Artist

Play Now
Play Next
Remove from Queue
Add to Playlist
Favorite
Go to Album
Go to Artist
```

Tap:

```text
Play Next
```

Result:

```text
A ← playing
D
B
C
```

Then long press another track E and choose:

```text
Play Next
```

Result:

```text
A ← playing
D
E
B
C
```

Then drag C above B:

```text
A ← playing
D
E
C
B
```

Swipe C left:

```text
A ← playing
D
E
B
```

Restart application:

```text
A ← playing
D
E
B
```

The queue must restore exactly, with no duplicates.

---

# 102. Critical consistency scenario

The coding agent must specifically validate:

```text
Queue UI
     ↕
Domain queue
     ↕
Persistent queue state
     ↕
Playback repository
     ↕
AudioService / just_audio
```

After every mutation, these must describe the same logical ordering.

A queue feature is **not complete** merely because the UI looks correct.

---

# 103. Critical duplicate scenario

Verify:

```text
A
B
A
C
```

Then:

```text
long press second A
→ Remove from Queue
```

Result:

```text
A
B
C
```

Then:

```text
Add A to Queue
```

Result:

```text
A
B
C
A
```

Then:

```text
Play Next A
```

Result:

```text
A ← current
A
B
C
A
```

The queue item identity must distinguish every occurrence correctly.

---

# 104. Critical playback-safety scenario

While A is actively playing:

```text
reorder B/C/D
remove D
add E
Play Next F
clear Up Next
```

At no point should A:

* restart;
* jump backward;
* stop unexpectedly;

unless the user explicitly selected an action that changes current playback.

---

# 105. Critical persistence scenario

Perform:

```text
1. Start with A/B/C/D.
2. Reorder.
3. Add duplicates.
4. Remove one duplicate.
5. Stop/restart app.
6. Open queue.
```

The exact final logical queue must be restored.

---

# 106. Final report

After implementation, report:

```text
Files changed:
...

Queue data model:
...

Drag/reorder implementation:
...

Play Next semantics:
...

Add to Queue semantics:
...

Long-press action system:
...

Playlist integration:
...

Favorite integration:
...

Queue persistence:
...

Duplicate handling:
...

Current-track handling:
...

Shuffle/repeat interaction:
...

Swipe removal:
...

Haptics/animation:
...

AudioService synchronization:
...

Tests added:
...

flutter analyze:
...

flutter test:
...

Known limitations:
...
```

Do not claim anything was tested or visually verified unless it was actually tested.

---

# 107. Final product standard

The finished queue should feel like this:

```text
                         Queue     ⋯

NOW PLAYING
────────────────────────────────────
        [art]  Song A
               Artist
               ♫ Playing

UP NEXT
────────────────────────────────────
        [art]  Song D
               Artist

        [art]  Song E
               Artist

        [art]  Song B
               Artist

        [art]  Song C
               Artist
```

And the interaction model should be immediately understandable:

```text
Tap
→ play

Long press
→ actions

Long press + move
→ reorder

Swipe left
→ remove

Queue menu
→ clear/manage
```

The queue should feel **fast, tactile, predictable, and safe**. The underlying queue semantics and playback synchronization are more important than the animations; visual polish must never come at the expense of a correct playback queue.
