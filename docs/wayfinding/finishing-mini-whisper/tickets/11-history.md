---
status: open
type: grilling
claimed: history-build
blocked-by: [8, 16]
---

# History (stake 1)

## Question

Text + audio history of past dictations, with a toggle to disable audio storage. Where does it live on disk, what retention policy, what UI surfaces it (menu? window?), and how does the audio-storage toggle interact with the settings JSON? Opens only after the MVP is daily-driven.

## Decisions carried

A first grilling pass ran and then handed the ticket back: the UI question turned out to depend on a settings window that does not exist yet, so this ticket now blocks on [Settings UI](16-settings-ui.md) rather than inventing a surface ad hoc. What that pass settled stands, and the resumed session starts from it.

- **Primary job is recovery** — getting the text back when a dictation went somewhere wrong. Quality forensics (hearing what you actually said) and corpus-building (feeding dictionary, second-engine bakeoffs, cleanup tuning) are welcome consequences, not design drivers. When a decision is contested, recovery wins.
- **Retention is one mechanism, two keys.** Transcripts and audio each get a TTL drawn from the same preset list — never, 1 day, 7, 30, 90, a year, forever. Transcripts default to forever; audio defaults to somewhere in 3–7 days, following [Aqua's three-day cap](../assets/25-competitor-feature-audit.md) rather than sentiment. Audio's value decays far faster than a transcript's, and a month of it is roughly 350 MB of recorded speech serving a job that was called incidental.
- **There is no separate audio on/off switch.** `never` is the bottom of the TTL scale and means exactly that, so storage and retention are one control rather than two that can contradict each other. Audio is on by default so forensics is possible without foresight.
- **`writeDebugWAV` dies.** The live `AudioCaptureClient` currently writes every completed capture to a UUID-named WAV in the temp directory, ungated by build configuration — 125 files and 83 MB were sitting there when this pass found it, unpairable with any transcript. History subsumes it: one owner for recorded audio, with a directory, a retention policy, and a toggle. Gating it to the dev channel in the meantime was considered and declined — it stays exactly as it is until this stake lands, and this stake owns its removal.
- **The audit refines this ticket**: retained audio should be framed as optional recovery evidence with a clear cap, and entries should carry enough pipeline provenance to tell a recognition error from a cleanup change from a delivery failure.
- **Corpus was demoted, then promoted back by accident.** The [Cohere run](26-cohere-transcription-model.md) discovered the engine bakeoff's private corpus audio is gone, so no engine measurement this project has made is reproducible. That makes history the only realistic path to a corpus — see [Second engine](15-second-engine.md). It does not displace recovery as the primary job, but it does mean one question lands here that a pure recovery design would have skipped: whether a transcript can be corrected in place.

That also dissolves what had been the open question here — what turning audio off does to audio already on disk. Shortening a TTL prunes whatever now falls outside it, and `never` is just the shortest TTL, so the answer is the ordinary retention pass rather than a special case. The requirement that follows is that retention must run when the setting *changes*, not only on a timer, or the control appears to do nothing.

### What the accidental version proved

A one-off rescue paired 20 of the 129 leaked WAVs to their transcripts by scraping the unified log, where the debug file writer and the transcript logger happen to fire within 200 ms of each other; the result is 22.6 minutes in `assets/09-engine-bakeoff/fixtures/recovered/`. The other 109 were unrecoverable because unified-log retention is hours, and the 20 texts are engine output rather than ground truth, so `reference` is null on every entry until someone listens.

That is the feature this ticket is meant to replace, and its failure modes are the requirements: pairing must be durable rather than incidental, and an entry has to distinguish what the engine said from what was actually said, or the corpus it accumulates can only ever measure agreement with the incumbent.

Still open: search and per-entry deletion, both pane details.

### The store (settled by prior-art survey)

A subagent read the actual persistence code of Hex, VoiceInk, Whispering/Epicenter, and FluidVoice (GPL — described, never copied). Hex keeps one Codable JSON plus a `Recordings/` directory with count-based trimming; VoiceInk uses SwiftData with independent transcript/audio expiry — the only direct prior art for our two-TTL split — but does not prune when the setting changes, which is exactly the failure this ticket forbids; Whispering creates the row *before* transcribing so a failed transcription is still durable history; FluidVoice budgets audio by bytes inside UserDefaults.

Decision: **Hex's shape — `@Shared(.fileStorage)` on one versioned JSON log, WAVs in an audio directory beside it — with Hex's two defects corrected.** A directory-per-entry store was designed and fully built first, then reverted the same day: laid against the field — JSONL, SQLite3, GRDB, SwiftData, UserDefaults — the deciding question became what TCA users actually do, and the answer is Point-Free's Sharing library, already a transitive dependency of TCA, holding small collections in a `.fileStorage` file. It is the pattern our north star's history already ships, it costs no allowlist addition and no new idiom, and search stays an in-memory filter either way — single-digit milliseconds at a heavy year's ~10k entries. SQLite/GRDB's only real lure was FTS5 full-text ranking, which earns nothing at this scale; SwiftData's managed reference types fight TCA's value types badly enough that Point-Free built SharingGRDB to answer it.

```text
…/Application Support/<channel>/History/
  history.json      # versioned HistoryLog: [HistoryEntry], newest first
  audio/<UUID>.wav  # referenced by relative filename; absent once pruned
```

The corrections to Hex, both born from the log-scrape postmortem: filenames in the log are **relative**, never absolute paths, so the store survives being moved; and pairing-by-reference is backstopped by a **launch-time reconcile** that forces log and disk back into agreement in whichever direction they disagree — missing WAV clears the entry's audio metadata, unreferenced WAV is deleted.

- Transcript TTL removes the entry (and releases its audio file); audio TTL deletes bytes and nulls the entry's audio metadata. Retention is a pure function over the log returning the kept log plus filenames to delete, so it tests without a filesystem.
- `transcriptions` is an append-only list — text, engine, timestamp — so a re-transcription never overwrites what the engine said at dictation time. The entry also carries the delivery outcome and target-app identity, so a bad result can be told apart: recognition error, cleanup change, or delivery failure.
- `Packages/History` holds the value types, the retention function, and the `AudioVault` (WAV write/delete/reconcile); the `@Shared(.fileStorage)` wiring lives in the app layer where TCA already is.

### Settled at build kickoff

- **The two TTLs live in `settings.json`.** The retention popover is still settings even though it renders inside History; the file stays the one authoritative settings surface.
- **No recent-transcripts submenu in the menu bar.** Paste-last already covers the immediate-recovery case there; the full page is one click away, and a submenu would be a second history surface to keep honest.
- **Re-transcription ships in the first pane**, not as a later enablement. Audio is stored in canonical engine-input format so any engine — current or a bakeoff candidate — can re-run it. A re-transcription must not overwrite the record of what the engine said at dictation time: the entry keeps the original output alongside any later one, or the corpus can only measure agreement with whichever engine ran last.
- **Build order:** store package first, then pipeline wiring (which deletes `writeDebugWAV` in the same commit), then the settings window shell with stub panes and a menu item, then the History pane ported from the mock-up. The Settings pane is a deliberate fast-follow, not part of this ticket. That fast-follow also removes the menu bar's "Open Settings File" item — it survives only because the file is still the sole way to change the hotkey, and the pane ends that.

### Built so far

1. **Store package** — `Packages/History` plus the `AppSettings` extraction it forced.
2. **Pipeline wiring** — every dictation now writes a `HistoryEntry` at its terminal moment: original transcription with fixed engine identity, delivery outcome and detail, target-app identity captured at delivery, and a paired WAV when the audio TTL allows. `writeDebugWAV` is deleted; the vault is audio's only owner. No-speech and engine-empty outcomes write nothing; a transcription failure with retained audio writes an entry with `original` nil — recoverable audio with no transcript is the case history exists for. Retention runs at launch (reconcile, prune, delete audio) and defers while a dictation is in flight, because orphan reconciliation would race an in-flight WAV write. The retention policy is always in state, so a dictation begun before the first maintenance pass still keeps its audio. Proven end-to-end by `benchmark-live` driving three real mic captures into three complete entries.

3. **Settings window shell** — the resizable sidebar window ships with its settled destination order and stub panes.
4. **History pane** — the real, day-sectioned pane now reads the shared log, searches and copies transcripts, plays retained audio, deletes entries, appends re-transcriptions, and applies confirmed retention changes immediately. The settings window and History pane are TCA features, and the debug agent scene can land directly on deterministic History rows.
5. **One settings source** — the two TTLs landing here forced the question of who owns `settings.json`, and the answer is now one `@Shared` value in app state rather than a client per key. The per-field save methods, the three separate readers, and the sounds and retention load actions are gone; the window column, its keyboard mode, and the whole h/j/k/l loop live in the settings feature instead of in History.

### The pane's interaction contract

Settled across the build's review rounds, recorded here because most of it is invisible in a screenshot:

- **The row is the copy target.** Click or `l`/Return copies; a tinted `✓ Copied` replaces the duration and leaves staggered — badge and tint fully out before the duration returns — so the two never share the slot. Copying is an action, not a selection: nothing stays selected.
- **The waveform glyph is the play button** — play on hover, stop while playing, completion reported by the player, one entry at a time. The column is absent when the entry has no audio, which is how retention stays visible.
- **The `⋯` menu** holds Re-transcribe (appends; the original is structurally immutable) and Delete. A pin/exemption feature was built and cut: keep-worthy audio is `forever` TTL or export, not a third state.
- **One cursor, one mode, one grey.** The keyboard cursor is a *place*, not a selection — it survives copying, focus moves, and pane round-trips, and the viewport restores to it on return. Input mode follows the last real input: keys give a sticky cursor grey, genuine pointer movement gives hover grey, and highlight visibility is derived from mode × focus × cursor so exactly one grey can exist. Rows sliding under a parked pointer are not mouse input.
- **The vim loop**: `j`/`k` move the cursor, `l`/Return copy, `h` ascends to the sidebar where the same keys walk destinations and descend back. `/` focuses search; Return keeps the filter, Escape abandons it. An unmoved cursor resolves to the first row, so entering the column always highlights something.
- **Retention lives in the toolbar's storage popover**: two TTL pickers and a stored-counts line. Shortening a limit warns destructively and prunes immediately on confirm.

Remaining: daily-drive the completed pane and close the ticket.
