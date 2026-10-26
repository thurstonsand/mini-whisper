# Profiles

## Status

Accepted

## Decision Summary

A **profile** is a whole dictation stack (engine, vocabulary strategy, cleanup leg, credentials, and the models it needs on disk), and exactly one is active. v1 ships five: four compiled-in factory profiles and Custom. Choosing one is the first thing onboarding asks, on the welcome page, so its download can start on the first click. The tradeoff is breadth for v1: two of the five bring capabilities the app does not have today, a hosted engine and a local cleanup model. That is accepted because the user wants the whole lineup comparable from day one, and because each profile lands as its own phase on a shared core.

## Problem Statement / Background

Cleanup today is one slot: one endpoint, one key, one model, configured by hand in the Cleanup pane. Switching providers means re-entering credentials the app already knew, a listing that dies with the process makes a configured endpoint read as Custom after relaunch, and the corpus has shown that the right vocabulary strategy depends on the cleanup model: the recognition sidecar is a net loss when an LLM reads the DICTIONARY block, and the entire vocabulary story when nothing does. Those are properties of a stack, not of an endpoint.

[Ticket 47](../wayfinding/finishing-mini-whisper/tickets/47-cleanup-endpoint-profiles.md) and [ticket 39](../wayfinding/finishing-mini-whisper/tickets/39-recommended-cleanup-providers.md) were grilled together on 2026-08-21 and settled what a profile is. The [corpus](../wayfinding/finishing-mini-whisper/assets/43-dictation-corpus/results/profiles-recommendation.md) chose the stacks. The [mock-up](../../spikes/profiles-mockup/README.md) ([ticket 49](../wayfinding/finishing-mini-whisper/tickets/49-profiles-ui-mockup.md)) settled the surfaces. On 2026-10-21 the user widened v1 from two profiles to all five, moved the factory profile to Haiku 5.5, chose cards, and made downloads independent of the profile choice.

## Goals

- One active profile drives every dictation: which engine hears it, where the vocabulary goes, and what cleans it.
- Switching profiles is immediate and never produces a broken dictation.
- Credentials are entered once per provider and survive switching away and back.
- Every model on disk is visible with its size and can be deleted; downloads never block each other or the profile choice.
- The first-run choice starts the right download on the first click.

## Non-Goals

- User-created profiles beyond Custom. The lineup is compiled in.
- A tuned prompt per profile. Every prompt-bearing profile ships the one built-in prompt, tuned for Haiku 5.5 ([ticket 48](../wayfinding/finishing-mini-whisper/tickets/48-prompt-eval-automation.md) round 6). Per-profile prompts come later, evidence first.
- Consent rules for changing a factory definition in a later release (deferred to [ticket 15](../wayfinding/finishing-mini-whisper/tickets/15-second-engine.md)).
- Backwards compatibility. The new settings schema is the only one the code reads; an old `settings.json` is deleted by hand.

## Exposed Shape

**The lineup.** Factory definitions are compiled in and static:

| id | name | engine | vocabulary | cleanup | credentials | models |
| --- | --- | --- | --- | --- | --- | --- |
| `haiku` | Parakeet + Claude Haiku | Parakeet TDT v2 | DICTIONARY block | `claude-haiku-5-5` at `https://api.anthropic.com/v1` | Anthropic | gate, Parakeet |
| `offline` | Offline | Parakeet TDT v2 | recognition sidecar | s1-mini on this Mac | none | gate, Parakeet, s1-mini |
| `accurate` | Most accurate | ElevenLabs Scribe v2 (hosted) | Scribe `keyterms` + DICTIONARY block | `gemini-3.8-flash` at Google's OpenAI-compatible endpoint | ElevenLabs, Google | gate |
| `cerebras` | Parakeet + Cerebras | Parakeet TDT v2 | DICTIONARY block | `gpt-oss-120b` at `https://api.cerebras.ai/v1` | Cerebras | gate, Parakeet |
| `custom` | Custom | Parakeet TDT v2 | user's choice | any OpenAI-compatible endpoint, optional | the user's endpoint | gate, Parakeet |

`haiku` is the default selection. A factory profile's endpoint and model can each be overridden; overrides survive switching away, and each field's reset icon returns that field alone to the factory value.

**Settings.** `settings.json` gains a `profiles` object and loses `cleanup` and `improveRecognition`:

```json
"profiles": {
  "active": "haiku",
  "overrides": { "cerebras": { "model": "llama-4-scout" } },
  "custom": { "cleanupEnabled": true, "endpoint": "https://gateway.internal/v1", "model": "gpt-oss-120b", "boostsVocabulary": false }
},
"cleanupTimeout": 10,
"additionalInstructions": ""
```

Timeout and additional instructions stay global, as the grilling decided. Instructions are hidden for a profile whose cleanup has no prompt surface (Offline).

**Credentials.** One Keychain item per credential slot, account `profile.<id>.<provider>`: `profile.haiku.anthropic`, `profile.accurate.elevenlabs`, `profile.accurate.google`, `profile.cerebras.cerebras`, `profile.custom.endpoint`. The old `cleanup-api-key` item is ignored. Existence is read, never mirrored.

**Readiness.** A profile has two legs, and each is ready or not on its own terms:

- The **engine leg** needs its models installed and, for a hosted engine, its key. Not ready means the app is Degraded ("Most accurate needs setup"), exactly as a missing model is today.
- The **cleanup leg** needs its key, a chosen model, and, for Offline, s1-mini installed. A factory profile missing its key is Degraded ("Add Your API Key…") and dictation is off until the key is stored. Otherwise not ready means the profile is needs-setup and dictation delivers raw, which is the existing pass-through.

So switching to an incomplete profile either delivers raw or says plainly what it is missing; it never quietly runs as a different profile.

**Models.** The pinned store becomes a library of three assets, each pinned, verified, downloaded, and deleted on its own:

| asset | what | size | used by |
| --- | --- | --- | --- |
| Speech gate | Silero VAD, the silence rejection that runs before any engine | 1 MB | every profile |
| Parakeet TDT v2 | the local engine and its CTC recognition helper | 567 MB | every profile but Most accurate |
| s1-mini | the local cleanup model, Q4_K_M GGUF | 484 MB | Offline |

Asset directories keep today's folder names, so an existing install validates in place. Downloads are independent: switching to a profile while another profile's download runs leaves that download running, and the new profile asks for its own download the normal way. Nothing is deleted implicitly; the Models pane is the one place an asset goes away. Deleting an asset the active profile depends on asks first (`Delete…`), then the profile reads needs-setup; any other asset goes at once (`Delete`).

**The engine seam.** `ASREngineClient` dispatches on the active profile's engine. The local engine is today's `LocalASREngine`. The hosted engine runs the same local gate first (duration floor, then Silero), then uploads the canonical WAV to `POST https://api.elevenlabs.io/v1/speech-to-text` with `model_id=scribe_v2`, `language_code=eng`, and one `keyterms` part per dictionary term. Audio leaves the Mac only for this profile, and its tagline says so.

**The cleanup seam.** `CleanupClient` dispatches on the cleanup leg: OpenAI-compatible as today, or local s1-mini. The local leg is a new package, `Packages/LocalCleanup`, running the GGUF in process through llama.cpp's pinned xcframework (`b11801`, checksummed binary target), greedy decoding, the model card's verbatim system prompt and control line. It has no prompt surface, so the DICTIONARY block, field context, and additional instructions do not apply; an empty result is treated as degenerate and delivers raw.

**The Profiles pane.** Replaces the Cleanup pane and the Model placeholder in the sidebar. One section for the active profile: a pop-up picker whose items carry each profile's status (orange for a problem, grey for a note; the closed control shows the active one's, and is the pane's only status mark), the engine, then the endpoint's address, key, and model as read-only values. Each value has Edit (Add or Replace for a key); a factory field that differs from its definition also has a reset icon after Edit. Edit opens every endpoint fact as fields at once, with Cancel and Save, and Save is verify by construction: it proves the draft first, and only an answer stores the keys in the Keychain and the address and model in settings. Proof is free where it can be. A typed ElevenLabs key is sent to Scribe with `model_id` and no audio, which Scribe refuses on the missing file only when the key and model would transcribe. An endpoint is proven by its `/models` list when the list names the model and the endpoint refuses to list without the key; Anthropic, Google, and Cerebras all qualify. Anything less, such as a gateway without a list, an unlisted alias, or a list anyone can read, falls back to a one-word completion, which spends tokens only when it succeeds. A failure stays in the editor with one red line under the field it blames (unreachable or timed out → the address; 401/403 → the key, "Invalid key." or "This endpoint needs an API key."; a 404 naming a model → the model). The first Cancel stops a check and keeps the draft; the second, switching profile, or leaving the pane discards it. A reset is a Save of the factory value. Custom before its first Save reads None with one Set Up button and no cleanup toggle; that Save turns its cleanup on, and its key is optional. A key a dictation's cleanup was refused with reads "Invalid key" on the key row and in the picker until a cleanup or a Save succeeds. Custom's boost toggle warns only when cleanup is also on. Then an "All profiles" section with only what applies: the time limit when the profile cleans, additional instructions when it cleans through an endpoint. Model listings persist in `model-listings.json` in the channel's application support directory, keyed by endpoint, loaded optimistically and refetched quietly when the pane opens.

**The Models pane.** A patch bay: the gate as one strip across the top (every profile runs it), every profile as a card on the left with Speech and Cleanup ports, and what they plug into on the right, under "On this Mac" (Parakeet, S1-mini) and "Off this Mac" (Scribe and each profile's endpoint), joined by wires. Pointing at a card lights its wires and leaves them lit, without making it active. Each local model carries its one state: size and Delete, progress, Failed and Retry, or Download.

**Onboarding.** The welcome page carries every profile as cards, three over two; the arrow keys move the choice and Tab still lands only on the button. Its button names every model it downloads (`Download Parakeet TDT v2`, `Download Parakeet TDT v2 and S1-mini`, or `Get Started` when only the gate is needed, which downloads silently), and pressing it records consent and starts the durable download of every model the profile needs. A profile with keys adds one API Keys step at the head of the rail, one field per provider. Continue proves every key before storing any: the engine key (ElevenLabs) first, then the cleanup key against the factory endpoint. A failure names the provider ("Invalid ElevenLabs key."). Skip for Now is possible but not advised: the app reads Degraded and the hotkey refuses until the key is added in Settings → Profiles. The other escape is "Use Custom to skip cleanup". The Speech Model step shows the engine's progress as today, with a row under it for each model no engine owns (s1-mini), and is not finished until all of them are on disk.

## Design Decisions

### 1. All five profiles in v1

Supersedes the grilling's two-profile v1. Each profile is its own phase on a shared core, so the breadth costs sequencing, not coupling.

### 2. Engine and cleanup legs fail differently

A missing cleanup leg has a safe fallback, raw, which is the guarantee the cleanup design already makes. A missing engine leg has none: there is nothing to deliver. Pretending otherwise by silently falling back to a different engine would make the active profile a lie.

Amended: a factory profile without its cleanup key is Degraded too. Its key step in onboarding can be skipped, and a skipped key that silently delivered raw would make the profile just as much a lie as a silent engine fallback. Custom keeps the raw fallback, because its cleanup is optional by definition.

### 3. A credential belongs to a profile, not to a provider

Most accurate needs two keys, so the slot is the unit. Two profiles naming the same provider do not share a key; that keeps Reset, deletion, and needs-setup local to one profile, at the cost of entering a key twice in an unusual setup.

### 4. The gate is an asset of its own

Silence rejection is a fixed point for every engine, including a hosted one, so the gate cannot ride inside the Parakeet download. Splitting it lets Most accurate install 1 MB instead of 568 MB.

### 5. llama.cpp for s1-mini

The vendor ships GGUF, the spike measured 222 ms median at Q4 against 391 ms for MLX bf16, and the user chose easiest-and-most-performant over allowlist purity (ticket 45). It is a new dependency on the installed artifact; Whispering's local GGUF inference is the precedent the map already names.

### 6. Cards in both places

The welcome page lays the lineup out as cards; the pane's picker carries the same names, symbols, and statuses.

## Edge Cases & Failure Modes

- **Switching while a download runs:** the download continues; the new profile shows its own state.
- **Deleting the active profile's asset:** confirm; the profile becomes needs-setup or Degraded by leg.
- **Hosted engine unreachable or 4xx:** the transcription fails as an engine failure does today, with the error sound and the pill notice; nothing falls back to Parakeet.
- **Hosted key rejected (401):** the profile reads needs-setup for that slot after the failure.
- **s1-mini returns empty or degenerate text:** raw delivers, recorded as a cleanup failure.
- **A factory override pointing at a dead endpoint:** the cleanup failure path; the field's reset icon is one click, and is proven before it is stored.
- **An old settings file:** its retired keys are ignored and the defaults apply, as for any unknown key; nothing migrates.

## Alternatives

### A shared key per provider

- **Status:** Rejected
- **Decision:** slots per profile keep every state transition local; sharing would make deleting one profile's key break another.

### Falling back to Parakeet when a hosted engine cannot run

- **Status:** Rejected
- **Decision:** the active profile would stop meaning what it says, and a user who chose Most accurate would dictate through a different engine without knowing.

### MLX or Core ML for s1-mini

- **Status:** Rejected for v1
- **Decision:** MLX needs a 4-bit conversion the vendor does not publish; Core ML needs a conversion we would own. Both are reachable later behind the same seam.

## Implementation Plan

Each phase ships a working app and builds on the one before it.

- [x] Phase 1: Profiles over today's capabilities
  - Goal: Haiku, Cerebras, and Custom are real; the Profiles pane replaces Cleanup and Model.
  - Work: the profile model and factory lineup in `TranscriptCleanup`/`AppSettings`; the new settings schema; credential slots in `KeychainClient`; the pipeline planning cleanup from the active profile and taking `boostsVocabulary` from it; the Profiles pane with cards, details, overrides and Reset, global rows, and the model-listing cache; the sidecar toggle moved off the Dictionary pane; agent scenes for the pane.
  - Validation: package and reducer tests; `mise run test:ui:settings`; a live dictation smoke through the Custom profile against the proxy on `claude-haiku-5-5`.

- [x] Phase 2: The model library
  - Goal: models are assets with their own lifecycle, and profiles answer readiness by leg.
  - Work: split `PinnedModelStore` into the gate and Parakeet assets with independent download, validation, and deletion; concurrent independent downloads; per-profile readiness feeding `Degradation`; the Downloaded models section with Delete and `not in use`.
  - Validation: package tests for per-asset validation and deletion; an existing dev install still validating with no re-download; reducer tests for switching mid-download.

- [x] Phase 3: Most accurate
  - Goal: dictation through ElevenLabs Scribe v2 and Gemini, with the gate local.
  - Work: the hosted engine behind the engine seam with `keyterms`; two credential slots; the gate-only asset set; the audio-leaves-this-Mac copy.
  - Validation: package tests against a stub endpoint; a live smoke with the `.env` keys on a corpus recording.

- [x] Phase 4: Offline
  - Goal: dictation cleaned by s1-mini on this Mac with the sidecar on.
  - Work: `Packages/LocalCleanup` over the pinned llama.cpp xcframework; the s1-mini asset; the local cleanup leg; attribution ("S1-mini" by "Superwhisper") in third-party licenses.
  - Validation: an opt-in real-asset package test; a live dictation smoke with latency logged.

- [x] Phase 5: Onboarding
  - Goal: first run chooses a profile on the welcome page and starts its download on the first click.
  - Work: welcome cards, the download button and footnote, key steps per provider, the per-profile Speech Model step, agent scenes.
  - Validation: `mise run test:ui:onboarding`; a fresh-channel run with `mise run mw:fresh`.

- [ ] Phase 6: Evidence and closure
  - Goal: the vertical proven and the docs honest.
  - Work: `CONTEXT.md` and `DEV.md`; close tickets 47, 39, 45, and 49 and update the map; the full UI suite.
  - Validation: `mise run lint`, `mise run test:ui`, screenshots of every pane state.

## Open Questions

- Whether Gemini and Cerebras need their own prompt passes, measured after round 6 ships.
- Whether `keyterms` and the DICTIONARY block together over-bias Scribe; the corpus never crossed them.
