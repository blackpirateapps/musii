# Lyrics Subsystem Architecture & Specification

## 1. Overview
Musii includes a full production-ready lyrics engine supporting embedded tags (synced and plain) as well as sidecar `.lrc` files discovered in the user's Google Drive music folder.

## 2. Deterministic Lyric Priority
When indexing audio files, the synchronization engine evaluates lyric sources using a strict deterministic priority order:
1. **Embedded Synced** (`LyricSource.embeddedSynced`): Synchronized time-stamped lyrics embedded directly within audio metadata tags (`SYLT`, `SLT`, or formatted LRC tags in comment/lyrics fields).
2. **Embedded Plain** (`LyricSource.embeddedPlain`): Unsynchronized lyrics text embedded within audio metadata tags (`USLT`, `ULT`, or plain text lyrics).
3. **Sidecar LRC** (`LyricSource.sidecarLrc`): Discovered `.lrc` files in the same Google Drive folder with matching base names (case-insensitive, normalized).
4. **None** (`LyricSource.none`): When no lyrics are available.

If sidecar `.lrc` files are updated or if a higher priority lyric is discovered, the database record is updated atomically.

## 3. LRC Parser Features
Located in `lib/features/lyrics/domain/services/lrc_parser.dart`:
- **Timestamp Formats**:
  - Centisecond: `[mm:ss.xx]` (e.g., `[01:23.45]`)
  - Millisecond: `[mm:ss.xxx]` (e.g., `[01:23.456]`)
- **Multi-Timestamps**: Supports multiple timestamps on a single line (e.g., `[00:12.00][00:24.00] Repeated line`), expanding each into distinct sorted `LyricLine` entries.
- **Offset Handling**: Parses ID tags such as `[offset:+/-ms]` (e.g., `[offset:+500]`) and shifts timestamps accordingly.
- **Metadata ID Tags**: Strips and ignores standard header tags (`[ar:Artist]`, `[ti:Title]`, `[al:Album]`, `[by:Author]`).
- **Range Validation**: Gracefully ignores invalid timestamp formats where seconds or minutes exceed 59 (e.g., `[99:99.99]`).
- **Plain Text Fallback**: If no timestamps are present in the text, cleanly preserves and renders the raw lines as unsynchronized plain lyrics.

## 4. Database Persistence (Drift SQLite)
Schema version 2 introduced two dedicated tables in `lib/core/database/tables.dart`:
- **`Lyrics`** (`@DataClassName('LyricRow')`):
  - `id`: Unique lyric identifier (`lyr_<trackId>`)
  - `trackId`: Foreign key to `Tracks` with cascade deletion
  - `source`: Enum string (`embedded_synced`, `embedded_plain`, `sidecar_lrc`, `none`)
  - `isSynchronized`: Boolean flag
  - `offsetMs`: Millisecond offset integer
  - `rawText`: Complete raw lyric text
  - `updatedAt`: Timestamp
- **`LyricLines`** (`@DataClassName('LyricLineRow')`):
  - `id`: Line identifier (`lyrl_<trackId>_<seq>`)
  - `lyricsId`: Foreign key to `Lyrics` with cascade deletion
  - `timestampMs`: Millisecond timestamp
  - `content`: Line lyric text (mapped to database column `text`)
  - `sequence`: Ordering integer

## 5. UI Presentation (`LyricsSheet`)
- Cupertino modal sheet opened from Now Playing bottom bar or track overflow menu.
- Displays track title and artist header with dismiss handle.
- Synchronized auto-scrolling highlighting current line in active white/pink with translucent inactive lines.
- Tap-to-seek: Tapping any lyric line immediately seeks playback to that line's timestamp.
- User scroll detection: If the user scrolls away, auto-scroll pauses and a floating "Return to current line" button appears.
- Supports plain lyrics mode and empty states when no lyrics are available.
