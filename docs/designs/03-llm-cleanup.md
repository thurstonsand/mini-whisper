# LLM cleanup pass

## Status

Accepted

## Decision Summary

Cleanup is an optional, blocking, best-effort LLM pass between transcription and delivery: the raw transcript, the captured field context, and the dictionary vocabulary go to a configurable OpenAI-compatible endpoint, and the cleaned text is what delivers. The key tradeoff is latency for quality — accepted because the user can always escape it: any activation press skips the pending cleanup instantly, a configurable timeout (default 10 s) backstops the unattended case, and no cleanup failure can ever fail a dictation.

## Problem Statement / Background

Raw ASR output is faithful to sound, not intent: disfluencies survive, punctuation is guessed, casing drifts, and spoken forms of symbols land literally ("dash dash help" instead of `--help`). The dictionary's deterministic passes fix taught terms, but the general problem — turning what was said into what was meant to be typed — needs a language model. This was staked as post-MVP stake 8, deliberately last because it is slow, and it is the one feature permitted to cross the network: the work environment sanctions exactly one LLM egress, an OpenAI-compatible gateway inside the controlled network.

Four research passes ground this design: the [model benchmark](../wayfinding/finishing-mini-whisper/assets/38-cleanup-model-benchmark.md) (provider survey plus a replay harness over History), [AX context beyond the focused field](../wayfinding/finishing-mini-whisper/assets/36-ax-context-beyond-the-field.md), [screenshot/OCR capture](../wayfinding/finishing-mini-whisper/assets/37-screenshot-ocr-context.md) (both concluding: ship focused-field-only), and [native endpoints](../wayfinding/finishing-mini-whisper/assets/40-native-llm-endpoints.md) (concluding: stay OpenAI-compatible, no SDK, no subscription auth).

## Goals

- A dictation with cleanup enabled delivers cleaned text in one paste — no revise-after-delivery.
- The raw transcript is always recoverable: skip is one keypress, failure falls back to raw, and history preserves both texts.
- Configuration lives in the already-designed Cleanup pane; the API key lives in the Keychain.
- Every cleanup is attributable in history: what the engine said, what the model returned, what delivered.

## Non-Goals

- Context beyond the focused field (whole-window AX reads, screenshot OCR). Scouted, documented, deliberately later.
- Native Anthropic/OpenAI-Responses endpoints, vendor SDKs, or subscription ("login with ChatGPT") auth. Researched and excluded — Anthropic forbids third-party subscription use; SDKs add unallowlisted supply-chain surface.
- A recommended-provider shortlist ([ticket 39](../wayfinding/finishing-mini-whisper/tickets/39-recommended-cleanup-providers.md) follows this stake).
- Streaming the completion. The response is small and delivery is atomic; partial text is useless.

## Exposed Shape

**The user surface.** The Cleanup pane as mocked in ticket 16: master toggle ("Clean up transcripts", footer: transcripts are sent to this endpoint, audio never leaves the Mac), endpoint address, the API-key state machine (blank → typed → stored-as-prefix-plus-dots; Save is what stores), model picker with best-effort `/v1/models` discovery falling through to Custom, Save as a bounded completion to the entered model, additional instructions appended to the built-in prompt, and a "Give up after" preset picker (5 / 10 / 20 / 30 s, default 10) beside the master toggle, its shared footer carrying both the privacy promise and the fallback promise ("If cleanup fails or runs past the limit, the transcript is delivered as heard") — the pane is mocked complete in `spikes/settings-mockup` (`.build/settings-mockup cleanup`). During a dictation, decided on real pixels in the [pill mock spike](../../spikes/cleanup-pill-mockup/): "Transcribing…" (blue dot) holds through the engine leg, then flips to "Polishing…" with a purple dot the moment the LLM request starts; at 3 s of cleanup the skip affordance reveals as a keycap chip — `Polishing… [⌥ Opt →] to skip`, the chord rendered in the same keycap vocabulary as Settings and onboarding, derived from the live first activation binding; on failure or timeout, a subdued transient notice: "Cleanup unavailable — pasted as heard". In History, the entry's text is the cleaned text; a hold-to-reveal affordance on the row shows the raw transcript.

**The interruption grammar.** One rule: any activation press while cleanup is in flight resolves it as a skip first. Tap = skip, deliver raw. Hold = skip, deliver raw, and start the new recording. Escape = the existing cancel law (archive to history, no delivery). No new meanings, no modes.

**The package boundary.** `Packages/TranscriptCleanup` (today an empty stub) owns the client:

- In: raw transcript, optional `FocusedTextContext`, dictionary vocabulary terms, `CleanupConfiguration` (endpoint URL, model, timeout, additional instructions) and the key.
- Out: cleaned text, or a typed failure (unreachable, HTTP status, timeout, malformed/empty response). Cancellation is a first-class outcome, not an error.
- Owned inside: prompt assembly (built-in prompt + instructions + context + vocabulary), the chat-completions request shape, the timeout.
- Also exposed: the bounded verify used by the pane's Save, and model listing (`/v1/models`, optional, failure is "browsing unavailable").

**The pipeline seam.** In `AppFeature`, cleanup inserts between context capture and delivery: transcription completes → context captured (once — the same capture feeds the prompt and the join) → cleanup request as a cancellable effect → delivery of cleaned (or raw, on skip/failure) text through the unchanged join rules and no-receiver law. Disabled or unconfigured cleanup means the effect is a pass-through; the pipeline shape does not fork.

**Persistence.** Settings gains a cleanup section (enabled, endpoint, model, timeout, instructions). The key itself is a Data Protection Keychain generic-password item with a per-channel service name — the app's first non-JSON persistence, scoped to exactly this value. Key existence is read from the Keychain rather than duplicated into settings. `HistoryEntry` gains an optional cleanup record: cleaned text, model, endpoint identity, duration. It also persists the captured field context, so the benchmark harness can replay the real conditioned prompt — the benchmark run found history holds no context today, making context-conditioned comparison impossible.

## Design Decisions

### 1. Blocking, not deliver-then-revise

Cleaned text delivers once, or raw does. Revising already-delivered text means editing inside a foreign app — an AX surface far worse than the paste path, racing the user's own typing. The latency cost is contained by the skip chord and the timeout, not by weakening the delivery contract. Prompt caching was measured and rejected as a lever: the full request is ~700 tokens, under the 1024-identical-prefix floor where OpenAI-compatible automatic caching engages (verified against a live gateway — `cached_tokens: 0` on an identical repeat), and padding to qualify would cost more prefill than it discounts. The prompt is prefix-stable by construction — static system message first, volatile tagged fields last — so caching engages by itself, with no client change, if the prompt ever outgrows the floor.

### 2. Best-effort with one escape hatch and one backstop

Cleanup can never fail a dictation: any error, timeout, or garbage response delivers the raw transcript with a pill notice. The skip chord is the attended escape (visible from 3 s); the configurable timeout (default 10 s) is the unattended backstop — a long-forgotten dictation must not deliver into a context captured minutes ago. The pane toggle covers prolonged outage.

### 3. The activation key resolves pending cleanup

Skip composes with the existing gesture machine rather than adding a mode: an activation press during cleanup is a skip, and a hold is a skip plus the next recording's start. Escape keeps its single meaning everywhere. The cleanup wait becomes a phase the machine already knows how to leave.

### 4. Context is captured once, before the request

The same `FocusedTextContext` snapshot feeds the prompt and, later, the join rules on the cleaned text. A second capture at delivery would double the AX flake surface to serve a retargeting case the no-receiver law already governs.

### 5. The prompt's inputs and its ownership line

Transcript, field context (when available), dictionary vocabulary (so cleanup never "corrects" a taught term), and target-app identity at bundle-ID level — the AX research showed window titles are configurable metadata, not a foreground-program contract, so nothing finer is claimed. The built-in prompt owns what every user needs: punctuation, casing, disfluency removal, spoken-symbol conversion, and never-invent-content. Additional instructions are appended, never substituted, and stay personal taste. Cleanup runs everywhere the toggle is on; prose-versus-code is the prompt's problem. The shipped built-in prompt is [prior-art](../wayfinding/finishing-mini-whisper/assets/42-cleanup-prompt-prior-art.md) Candidate A — the conservative editor, whose tagged fields are data-never-instructions — with Candidate B's explicit spoken-symbol enumeration (dash, underscore, slash, at sign, and repetitions) merged in: the research's own finding that explicit beats intuitive for dictated control words. B's broader writing mechanics (lists, dates, quantities) stay out until the corpus proves them.

### 6. History preserves raw and cleaned; the pane displays cleaned

The cleanup record sits beside the structurally immutable original transcription — the corpus must distinguish a recognition error from a cleanup rewrite, re-transcription comparisons need the original, and the benchmark harness needs raw→cleaned pairs. Presentation inverts storage: the cleaned text is the entry's text (copy target included), with hold-to-reveal for the raw.

### 7. OpenAI-compatible chat completions over URLSession, key in the Keychain

No SDK (supply-chain surface on a strict allowlist), no Responses API (no primary-source latency win for a tiny bounded request), no subscription auth (forbidden or Codex-only per vendor terms). The key is a Data Protection Keychain generic-password item per channel; settings.json never carries a credential, so settings backups and exports stay clean. Xcode manages the required Developer ID provisioning profile during archive export through the release API key, so expiring profiles are renewed build input rather than manually rotated secrets.

## Edge Cases & Failure Modes

- **Endpoint unreachable / non-2xx / malformed or empty response:** deliver raw, pill notice, cleanup failure recorded on the history entry.
- **Timeout (default 10 s, configurable):** same as failure; the request is cancelled.
- **Skip:** request cancelled, raw delivers immediately, entry records cleanup as skipped.
- **Escape during cleanup:** existing cancel law — request cancelled, no delivery, transcript archived to history.
- **Cleanup enabled but endpoint/key/model incomplete:** treated as disabled; the pane is where incompleteness is visible.
- **Model returns extra prose (apologies, fences, commentary):** the client conforms at the edge — response shaping strips obvious wrappers; a response that still looks degenerate (empty, or wildly longer than input) falls back to raw as a failure.
- **Focus changed during cleanup:** delivery proceeds under the existing no-receiver law with the stale-context join; the capture is not retaken (Decision 4).
- **No field context (terminals, canvas apps):** the prompt simply omits it; cleanup still runs.
- **Keychain read fails at dictation time:** cleanup failure path — raw delivers; degraded surfacing stays with the pane, not the pill.

## Alternatives

### Deliver-then-revise

- **Status:** Rejected
- **Decision:** editing delivered text in a foreign app is fragile and races the user; one delivery of the right text with an instant skip beats two deliveries of shifting text.

### Cleaned text replaces the original in history

- **Status:** Rejected
- **Decision:** destroys forensics (recognition error vs. rewrite), breaks the immutable-original law, and consumes the benchmark's own corpus. Display, not storage, is where cleaned text wins.

### Skip cleanup in terminal-classified targets automatically

- **Status:** Rejected
- **Decision:** the user doesn't dictate shell commands; the prompt handles technical notation. Reconsider only with evidence of real damage.

### Native Anthropic endpoint / Responses API / vendor SDKs / subscription auth

- **Status:** Rejected
- **Decision:** see [native endpoints research](../wayfinding/finishing-mini-whisper/assets/40-native-llm-endpoints.md). Anthropic-native access remains conditional on a measured A/B gain and egress approval — revisit with the [recommended-providers ticket](../wayfinding/finishing-mini-whisper/tickets/39-recommended-cleanup-providers.md).

### Richer context (whole-window AX, screenshot OCR)

- **Status:** Open
- **Open Issue:** canvas editors and terminals contribute no context today.
- **Discussion:** both scouts recommend the same boundary — a bounded frontmost focused-window AX reader, or consent-gated local OCR sending text, never pixels. Neither belongs in this stake.
- **Next step:** a future ticket, evidence-driven, after cleanup is daily-driven.

## Implementation Plan

- [x] Phase 1: The TranscriptCleanup package
  - Goal: the whole client exists and is provable without the app — prompt assembly, request, typed outcomes, response conformance.
  - Files: `Packages/TranscriptCleanup/` (replacing the stub).
  - Work: `CleanupConfiguration` (endpoint, model, timeout, additional instructions); the built-in prompt (Candidate A + B's symbol enumeration) with tagged-field assembly over transcript, optional `FocusedTextContext`, vocabulary, bundle ID; the chat-completions request over URLSession; typed outcomes (cleaned text, cancellation, unreachable/HTTP/timeout/malformed); response shaping that strips wrappers and rejects degenerate output; the bounded verify and optional `/v1/models` listing for the pane.
  - Validation: package unit tests — prompt assembly with absent optional blocks, outcome mapping against a stub URLProtocol, shaping cases; `mise run test:packages`. Verify URLSession task cancellation surfaces as the cancellation outcome, not an error (the design's open question).

- [x] Phase 2: Settings and the Keychain
  - Goal: cleanup configuration persists; the key lives in the Keychain.
  - Files: `Packages/AppSettings/`, a Keychain client in the app layer.
  - Work: cleanup section on the settings value (enabled, endpoint, model, timeout default 10 s, instructions); Data Protection Keychain generic-password storage keyed per channel, with existence queried from the Keychain; no legacy decode — absent section is defaults.
  - Validation: settings codec tests; a smoke write/read/delete from the dev test host under an isolated Keychain service.

- [ ] Phase 3: The history cleanup record
  - Goal: entries can carry cleaned text and the context that conditioned it, without touching the immutable original.
  - Files: `Packages/History/`.
  - Work: optional cleanup record on `HistoryEntry` (cleaned text, model, endpoint identity, duration, skipped/failed disposition); persist the captured field context on the entry so the benchmark harness can replay conditioned prompts; retention and reconcile untouched.
  - Validation: package codec and retention tests; harness under `docs/wayfinding/finishing-mini-whisper/assets/38-cleanup-model-benchmark/` still reads the log.

- [ ] Phase 4: Pipeline insertion and the Polishing pill
  - Goal: a dictation with cleanup enabled delivers cleaned text end-to-end; a failing endpoint delivers raw with the notice.
  - Files: `MiniWhisper/AppFeature.swift` (+History extension), `MiniWhisper/PillFeature.swift`, `MiniWhisper/PillView.swift`.
  - Work: cancellable cleanup effect between `contextCaptured` and delivery; disabled/unconfigured is a pass-through, the pipeline shape does not fork; timeout and failure fall back to raw with the subdued "Cleanup unavailable — pasted as heard" notice; entry records the cleanup record; the pill flips to Polishing… (purple dot) when the request starts, per the spike's chosen chrome.
  - Validation: reducer tests for success/failure/timeout/pass-through; live smoke against a local mock endpoint (the harness's mock serves) showing cleaned delivery, then a dead endpoint showing raw + notice.

- [ ] Phase 5: The skip grammar
  - Goal: any activation press resolves a pending cleanup as a skip; the 3 s reveal shows the keycap chip.
  - Files: the gesture machine and `AppFeature+Gesture.swift`, `PillFeature`/`PillView`.
  - Work: cleanup-pending as a machine phase with tap = skip-deliver-raw, hold = skip-deliver-raw + start recording, Escape = existing cancel law; a 3 s reveal effect adding `Polishing… [⌥ Opt →] to skip` derived from the live first binding; request cancellation on skip.
  - Validation: machine phase × input table tests; reducer tests for skip-then-record; live smoke with a slow mock endpoint exercising tap, hold, and Escape.

- [ ] Phase 6: The Cleanup pane
  - Goal: the settings window's Cleanup destination is real; hand-editing ends where it did for every other setting.
  - Files: `MiniWhisper/SettingsFeature.swift`, a new `CleanupPane.swift`, agent scene driver.
  - Work: the pane per the ticket-16 contract and mock — toggle with its footer, endpoint, the API-key state machine over the Keychain, model picker with best-effort listing falling through to Custom, the "Give up after" preset picker, additional instructions, Save as the bounded verify with quiet `Saved`/specific failure; full cursor-grammar citizenship; deterministic agent scenes.
  - Validation: XCUITest batch for the pane's laws via `mise run test:ui:settings`; `mise run lint`.

- [ ] Phase 7: Evidence and closure
  - Goal: the vertical proven and the docs honest.
  - Files: `CONTEXT.md`, `DEV.md` if commands changed; the map.
  - Work: an end-to-end pass against a real endpoint — dictation cleaned and delivered, skip exercised, outage exercised; update the glossary's cleanup-pass entry to the shipped meaning; run the update-docs skill.
  - Validation: `mise run lint`, `mise run test:ui` as the concluding pass, recorded evidence in the session.

## Open Questions

- Prompt refinement: the [coded-speech corpus spike](../wayfinding/finishing-mini-whisper/tickets/43-coded-speech-corpus.md) runs after implementation — recorded punctuation commands, spoken symbols, and identifier-from-context scenarios replayed through the harness — and may amend the default prompt's text, not its invariants.
- Whether URLSession task cancellation is clean enough for the skip path or the effect needs its own hardening — verified in Phase 1.
