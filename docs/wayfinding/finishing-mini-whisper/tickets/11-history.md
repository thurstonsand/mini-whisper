---
status: open
type: grilling
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
- **Corpus was demoted, then promoted back by accident.** The [Cohere run](26-cohere-transcription-model.md) discovered the engine bakeoff's private corpus audio is gone, so no engine measurement this project has made is reproducible. That makes history the only realistic path to a corpus — see [Second engine](15-second-engine.md). It does not displace recovery as the primary job, but it does mean two questions land here that a pure recovery design would have skipped: whether a transcript can be corrected in place, and whether audio retention should have an exempt-from-pruning marker for entries worth keeping.

That also dissolves what had been the open question here — what turning audio off does to audio already on disk. Shortening a TTL prunes whatever now falls outside it, and `never` is just the shortest TTL, so the answer is the ordinary retention pass rather than a special case. The requirement that follows is that retention must run when the setting *changes*, not only on a timer, or the control appears to do nothing.

### What the accidental version proved

A one-off rescue paired 20 of the 129 leaked WAVs to their transcripts by scraping the unified log, where the debug file writer and the transcript logger happen to fire within 200 ms of each other; the result is 22.6 minutes in `assets/09-engine-bakeoff/fixtures/recovered/`. The other 109 were unrecoverable because unified-log retention is hours, and the 20 texts are engine output rather than ground truth, so `reference` is null on every entry until someone listens.

That is the feature this ticket is meant to replace, and its failure modes are the requirements: pairing must be durable rather than incidental, and an entry has to distinguish what the engine said from what was actually said, or the corpus it accumulates can only ever measure agreement with the incumbent.

Still open, and now inheriting the settings window's answers: the on-disk store's shape, whether a menu submenu of recent transcripts exists alongside the window, replay and re-transcription, search, and per-entry deletion.
