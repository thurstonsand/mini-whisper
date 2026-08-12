# Dictionary: vocabulary, corrections, and the boost

## Status

Accepted

## Decision Summary

The dictionary is two lists wearing one UI: vocabulary entries (words taught as correct) and correction pairs (taught misspellings rewritten after transcription). Corrections and case repair are deterministic passes inside the engine; recognition-time vocabulary biasing ships as FluidAudio's CTC-sidecar rescorer — on by default, disclosed as experimental, gated stricter than upstream defaults. Quick add is an inline text field in the status menu, proven by spike. The key tradeoff: accepting a ~100 MB helper model and a bounded false-substitution risk in exchange for the only real recognition-time vocabulary mechanism our runtime exposes.

## Problem Statement / Background

Parakeet TDT v2 mangles names, jargon, and product terms ("MiniWhisper" → "mini whisperer"), and unlike Whisper it has no prompt channel: it is a transducer with no text decoder to condition. Users need to teach the app their words, and the moment they discover a mangling — reading a transcript that just landed — is the moment they know the word, so teaching must be reachable from the menu bar without opening a window.

Research (see [parakeet-vocabulary-hinting](../wayfinding/finishing-mini-whisper/research/parakeet-vocabulary-hinting.md) and [paid-app-dictionary-mechanisms](../wayfinding/finishing-mini-whisper/research/paid-app-dictionary-mechanisms.md)) established:

- Pinned FluidAudio v0.15.5 already contains the mechanism: a CTC 110M Core ML sidecar that re-scores dictionary terms against the audio after the primary TDT decode and substitutes only when the term wins acoustically (CTC-WS ported to Core ML). No upgrade required.
- Open-source peers (Hex, VoiceInk) ship exact-match post-replacement only. Monologue — the closest local peer — ships these exact sidecar assets alongside TDT v3.
- The risk is measured, not theoretical: MacParakeet's evaluation showed default thresholds lift OOV recall 22%→84% but produce false substitutions; a stricter gate (0.65 minSimilarity) cut false applications 9→1 at 74% recall.

The map's pruning excludes a general find-replace engine. What is in scope is a correction attached to a word already taught — the [Settings UI](../wayfinding/finishing-mini-whisper/tickets/16-settings-ui.md) resolution's "two features wearing one list."

## Goals

- Taught words stop being mangled: acoustically via the boost, deterministically via corrections and case repair.
- Adding a word at the moment of discovery takes seconds: open menu, click, type, done — no window.
- Every consumer of a transcript (delivery, history, rerun, paste-last) sees the same corrected text.
- Correction logic is pure and unit-tested; the pane and quick add are covered by the UI-test manifest.

## Non-Goals

- A general text-substitution/snippet engine (excluded by the map's pruning).
- Model inventory UI for the CTC asset — [Model download UI](../wayfinding/finishing-mini-whisper/tickets/17-model-download-ui.md) owns listing/deleting models.
- Import/export (CSV, Wispr-style). Extensible file shape leaves the door open; nothing ships now.
- Tuning the boost thresholds against a corpus — constants start strict; loosening against history-vault audio is future work.

## Exposed Shape

### `dictionary.json`

Lives beside `settings.json` in the running channel's application support directory. Top-level object for extensibility:

```json
{
  "vocabulary": [
    { "text": "MiniWhisper", "addedAt": "2026-08-10T21:00:00Z" }
  ],
  "corrections": [
    { "misspelling": "mini whisperer", "text": "MiniWhisper", "addedAt": "2026-08-10T21:00:00Z" }
  ]
}
```

Free text, single words and phrases alike. `addedAt` backs the pane's Newest First sort. A missing file is an empty dictionary. Malformed content fails fast at load — conform at the edge.

### `Packages/Dictionary`

Owns the data: entry models (`DictionaryEntry` forms) and the `dictionary.json` codec, validated at decode (empty text or misspelling is rejected there — conform at the edge). Depends on nothing. History's precedent: user data with its own package.

The correction algorithm lives in `ASREngine`, expressed in the engine's own carrier types — the engine owns the pass because the engine is where speech becomes finished text. (Amended after review: an earlier draft gave `Dictionary` a public `TranscriptCorrector`, which forced either a forbidden package dependency or a third, dependency-neutral package with a wrapper nobody called.)

### App ⇄ engine boundary

The app hands dictionary contents to the engine as plain values at each transcribe call; there is no package dependency between `Dictionary` and `ASREngine`. Both engine consumers — live dictation and history's rerun — thread the current dictionary per call; that is honest per-call data, not duplicated knowledge. Inside the engine, order is: TDT decode → boost (if enabled and assets present) → corrections and case repair. The transcript that leaves the engine is finished text — delivery, history, and rerun all inherit it.

### The Dictionary pane

As the settings mockup settled it: rows not selectable, click opens the edit sheet, hover shows only a trash icon, sort is Newest First or Alphabetical, no dates in rows. One sheet serves add and edit; a toggle in its own section reveals the correction shape (`Misspelling → Correct spelling`, dimmed left). New: a "Recognition" section hosting the boost toggle — titled "Improve recognition", footer copy disclosing experimental status and that a taught word may occasionally be substituted incorrectly.

### Quick add (menu)

A view-based `NSMenuItem` under the menu's transcript items: two plain `NSTextField`s (Word, Misspelling — optional). Click focuses; Tab traverses; Return commits through the Dictionary store and closes the menu; Escape dismisses the menu and discards the draft — that dismissal *is* the abort. Proven by the [quick-add spike](../../spikes/quick-add-menu/README.md).

### CTC assets

`parakeet-ctc-110m` joins Parakeet v2 in ASREngine's pinned-model machinery and downloads eagerly during onboarding's model step, under the same recorded bandwidth consent. Existing installs fetch at next launch through the consented auto-resume path. A missing or failed CTC asset rides the existing model degradation machinery.

## Design Decisions

### 1. Separate `dictionary.json`, not `settings.json`

The dictionary is user data — more like history than configuration. A top-level object (not a bare array) keeps the format extensible. Tradeoff: a second load/save path, accepted for the cleaner boundary.

### 2. Two lists inside, one list in the UI

Vocabulary and corrections are a real seam — bias-before versus rewrite-after — but the user sees one dictionary. Storage honors the seam; the pane and sheet hide it behind the correction toggle. Every correction's right-hand side is also, conceptually, a vocabulary word; storing them separately avoids optional-field contortions.

### 3. Corrections apply inside the engine

History's Rerun Transcription is already a second engine consumer; a correction pass outside the engine means two call sites or a bug. The engine boundary is where speech becomes text, and corrected text is the text. Consequence: history records corrected output — raw engine output is not preserved.

### 4. Correction semantics: case-insensitive, word-boundary, phrase-capable, taught form verbatim

The engine's casing of a mangled word is exactly what users cannot control, so matching must be case-insensitive. Word boundaries prevent substring mangling. The taught form lands verbatim because people teach proper nouns — with one exception: a match at sentence start whose taught form is all-lowercase gets its first letter capitalized. Single pass, longest-match-first, no re-matching of produced output (no chains).

### 5. Case repair: vocabulary entries act from day one

A case-insensitive exact hit of a vocabulary word takes the taught casing ("miniwhisper" → "MiniWhisper", "tca" → "TCA"). Deterministic, zero acoustic risk, same pass as corrections. Makes the pane honest: adding a word visibly matters even where the boost has nothing to do.

### 6. The boost: CTC sidecar, on by default, disclosed as experimental, strict gate

The only exposed recognition-time mechanism for our runtime (no prompt channel, no logit-bias API in the Core ML TDT bundle). Default-on because an empty dictionary makes it a no-op and eager asset download means it works the moment the first word is taught; the toggle exists to opt out. Threshold constants live in one place and start stricter than FluidAudio's size-aware defaults, per MacParakeet's false-substitution evidence — a false substitution of a correctly-heard word is silent corruption of delivered text, worse than a missed boost. CTC models and the tokenized vocabulary are cached and rebuilt only on dictionary revision (MacParakeet's pattern); the spotter/rescorer run per transcription on the batch path.

### 7. CTC assets download eagerly during onboarding

Toggle-on-demand download was considered, but default-on makes the toggle-as-consent moment vanish; onboarding's welcome button already records bandwidth consent, and ~100 MB atop the existing model download is a marginal cost paid once. Deviation from the obvious lazy path is deliberate — record it here so nobody "fixes" it.

### 8. Quick add is an inline menu field

Spike-proven (see [ticket 33](../wayfinding/finishing-mini-whisper/tickets/33-quick-add-menu-spike.md)). Plain `NSTextField` over SwiftUI hosting for direct first-responder control. Escape's whole-menu dismissal is accepted as the abort. Click-to-focus is the deterministic path; auto-focus on open is best-effort only (the hosted view has no window during `menuWillOpen`). Recorded fallback if daily use sours: the menu item becomes a shortcut opening Settings → Dictionary with the add sheet pre-opened — quick add is already designed as a shortcut into the full surface, so the data path is unchanged.

## Edge Cases & Failure Modes

- **Empty dictionary:** boost and correction passes are no-ops; no CTC inference runs when there are no terms.
- **CTC asset missing/failed:** rides the existing model degradation machinery (repair row + menu item); transcription itself continues un-boosted — the sidecar is never on the critical path's failure line.
- **Duplicate add (quick add or sheet):** case-insensitive match on `text` is a no-op for vocabulary; a duplicate misspelling updates the existing pair. Quietly succeed — the user's intent ("this word should exist") is satisfied.
- **Correction output matching another rule:** never re-matched; single pass over the original transcript.
- **Overlapping matches:** longest match wins; remaining text continues after the replacement.
- **Term shorter than the sidecar's `minTermLength` (3):** FluidAudio skips it for boosting; case repair and corrections still apply. Not surfaced as an error.
- **Quick add commit with empty Word:** Return does nothing; the field stays. Misspelling filled but Word empty commits nothing.
- **Dictionary edited on disk while the pane is open:** shared file storage reloads (same posture as settings.json handling).
- **Malformed `dictionary.json`:** log and keep dictating — corrections silently don't apply, the file is left exactly as it is (settings precedent). The write-side guard — never save over a file that failed to load — lands with the pane.
- **A correction that deletes its match:** an empty transcript must not leave the engine as success; it degrades to the engine-empty outcome.

## Alternatives

### Corrections only (Hex/VoiceInk shape)

- **Status:** Rejected
- **Decision:** Abandons the ticket's premise while a real, allowlist-clean mechanism sits in the already-pinned dependency; the closest peer (Monologue) ships it.

### Boost as a separate follow-up ticket

- **Status:** Rejected
- **Decision:** The paid-app evidence firmed the mechanism; integrating in one ticket avoids a stored-but-inert vocabulary. The plan still phases it last, so the surface and corrections land and demo first.

### Boost default-off (MacParakeet's posture)

- **Status:** Rejected
- **Discussion:** Empty-dictionary no-op plus the strict gate make default-on a bounded bet, and it spares the user discovering a switch before their words start working. A one-line revert if daily use shows false substitutions.

### Quick add as floating panel or settings shortcut

- **Status:** Rejected
- **Decision:** The spike proved the inline field; the settings-sheet shortcut survives as the recorded fallback, not the primary.

## Implementation Plan

- [ ] Phase 1: `Packages/Dictionary` — model, store, corrector
  - Goal: The package exists with the full data layer and pure correction logic; nothing visible changes.
  - Files: `Packages/Dictionary/` (new: `DictionaryEntry.swift`, `DictionaryStore.swift`, `TranscriptCorrector.swift`, tests), workspace/project wiring.
  - Work: Entry models with Codable round-trip; store load/save/observe of `dictionary.json` (missing file = empty, malformed = fail fast); `TranscriptCorrector.apply` implementing decision 4 + 5 semantics (case-insensitive, word-boundary, phrase-capable, longest-first, single pass, verbatim + sentence-start exception, case repair).
  - Validation: `mise run test:packages` — corrector table tests covering every semantics clause and edge case above; store round-trip tests.

- [ ] Phase 2: corrections wired through the engine
  - Goal: A hand-edited `dictionary.json` visibly corrects real dictations everywhere transcripts land.
  - Files: `Packages/ASREngine` (transcribe boundary takes dictionary values), `MiniWhisper/ASREngineClient.swift`, `MiniWhisper/AppFeature.swift` (thread store contents to the client).
  - Work: Extend the engine's transcribe contract with vocabulary + corrections as plain values; apply the corrector post-decode; rerun-transcription inherits automatically.
  - Validation: Engine package tests; smoke test — teach "MiniWhisper", dictate "mini whisper", see the corrected transcript in delivery and history, then Rerun Transcription and confirm identical output.

- [ ] Phase 3: the Dictionary pane
  - Goal: The settings window's Dictionary placeholder becomes the real pane.
  - Files: `MiniWhisper/DictionaryPane.swift` (new), `MiniWhisper/DictionaryFeature.swift` (new), `MiniWhisper/SettingsWindowView.swift`, `MiniWhisper/SettingsWindowFeature.swift`, `MiniWhisper/AccessibilityID.swift`, UI-test manifest.
  - Work: Port the mockup's settled shape (rows, sheet, hover trash, sort) onto the store; keyboard laws per the window's input model (arrows/`j`/`k`, Return opens the sheet, Escape declines); AX identifiers per the `miniwhisper.<surface>.<element>` vocabulary; extend the curated UI-test manifest.
  - Validation: `mise run lint`; targeted settings UI tests; screenshot against the mockup.

- [ ] Phase 4: quick add in the menu
  - Goal: Open menu, click, type, Return — the word is in the dictionary.
  - Files: `MiniWhisper/MenuBarController.swift`, new quick-add item view (adapting `spikes/quick-add-menu/QuickAddMenu.swift`), `MiniWhisper/AccessibilityID.swift`, UI-test manifest.
  - Work: View-based NSMenuItem with Word + optional Misspelling fields per the spike's AppKit shape (explicit field-editor sync on Tab); Return commits through the store and closes the menu; duplicate handling per edge cases; AX identifiers.
  - Validation: UI test driving the real status item: type a word, Return, assert it appears in the pane; `./scripts/capture_menu_screenshot` for visual evidence.

- [ ] Phase 5: the boost
  - Goal: Taught words win acoustically; the toggle governs it; a fresh onboarding fetches everything.
  - Files: `Packages/ASREngine` (`PinnedModelStore.swift`, CTC integration, threshold constants file), `MiniWhisper/OnboardingFeature.swift` (asset scope), `MiniWhisper/DictionaryPane.swift` (Recognition section), `Packages/AppSettings` (boost toggle setting).
  - Work: Pin `parakeet-ctc-110m` and fold it into `setUpModel`/readiness so onboarding and the consented auto-resume path fetch it; integrate `CtcKeywordSpotter` + `VocabularyRescorer` post-decode (cache models and tokenized vocabulary by dictionary revision); strict-gate constants in one file with the MacParakeet citation; boost toggle (default on) in the pane with disclosure footer; missing-asset degradation.
  - Validation: `FRESH_MODEL=1 mise run mw:fresh` proves the onboarding download path; smoke test — teach an OOV name, dictate it, show the boosted transcript; toggle off, dictate again, show the un-boosted one; `mise run benchmark:live` confirms latency budgets hold with the sidecar active.

- [ ] Phase 6: documentation and close-out
  - Goal: The map and docs reflect reality.
  - Files: `CONTEXT.md` (verify terms), `DEV.md` (package list), `docs/wayfinding/finishing-mini-whisper/` (ticket 13 resolution, map line).
  - Work: Update the architecture package list; write ticket 13's resolution linking this doc; Decisions-so-far line.
  - Validation: `mise run lint` (markdown gate); links resolve.
