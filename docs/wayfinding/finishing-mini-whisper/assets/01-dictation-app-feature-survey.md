# Dictation app feature survey

Asset for [Dictation app feature survey](../tickets/01-dictation-app-feature-survey.md). Collected for the pruning session; this document recommends candidates but decides nothing.

Surveyed: **Hex**, **VoiceInk**, **Whispering** (open source, code read via librarian); **Wispr Flow**, **Aqua Voice**, **Superwhisper**, **MacWhisper** (closed source, surveyed from docs/marketing — taste reference, not implementation reference).

## Feature matrix

| Feature                               | Hex                                                | VoiceInk                                                                 | Whispering                                                              | Wispr Flow                                     | Aqua Voice                       | Superwhisper                   | MacWhisper                      |
| ------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------ | ----------------------------------------------------------------------- | ---------------------------------------------- | -------------------------------- | ------------------------------ | ------------------------------- |
| Hold-to-talk                          | ✅                                                 | ✅ (PTT mode)                                                            | ✅ (bindable)                                                           | ✅                                             | ✅ (hold Space-style)            | ✅ ("new")                     | ✅                              |
| Double-tap latch                      | ✅                                                 | ✅ (hybrid: short press latches, long press = PTT)                       | ❌                                                                      | ✅                                             | ✅                               | ⚠️ toggle modes                | ⚠️ (default: hold Option twice) |
| Side-specific modifier (right Option) | ✅ left/right/either per modifier                  | ❌                                                                       | ❌                                                                      | ✅                                             | ✅                               | ⚠️                             | ⚠️                              |
| Accidental-tap rejection              | ✅ configurable min-hold threshold                 | ⚠️ via mode semantics                                                    | ❌                                                                      | ✅                                             | ✅                               | ❓                             | ❓                              |
| Recording indicator overlay           | ✅ floating capsule w/ live level, per-state color | ✅ Mini or Notch styles, live transcript option                          | ✅ floating pill w/ meter, VAD state, cancel, "ship raw"                | ✅                                             | ✅                               | ✅                             | ⚠️                              |
| Local engine                          | WhisperKit + Parakeet (FluidAudio)                 | whisper.cpp GGML + Parakeet + Apple native                               | whisper.cpp GGUF (desktop)                                              | ❌ cloud                                       | ❌ cloud (local fallback tier)   | Whisper/Parakeet local + cloud | whisper.cpp/WhisperKit          |
| Model download UI                     | ✅ curated                                         | ✅ curated + **import local files**                                      | ✅ w/ progress/cancel, shared HF cache                                  | n/a                                            | n/a                              | ✅                             | ✅                              |
| Streaming / partial transcript        | ❌                                                 | ✅ where model supports                                                  | ❌ (VAD segmentation only)                                              | ✅                                             | ✅ "streaming mode"              | ⚠️                             | ❌                              |
| VAD / silence rejection               | ❌                                                 | ✅ VAD on by default; skips enhancement on short text                    | ✅ VAD trigger mode; **pads very short audio** vs whisper hallucination | ✅                                             | ✅                               | ✅ (Pro VAD)                   | ⚠️                              |
| Paste w/ clipboard restore            | ✅ (warns on type loss)                            | ✅ **ownership-checked full-type restore**                               | ❌ (clipboard default; cursor paste opt-in w/ honest fallback report)   | ✅                                             | ✅                               | ✅                             | ✅                              |
| History (text + audio)                | ✅ capped, playback, paste-last hotkey             | ✅ + retention policy, export                                            | ✅ raw+polished text, search, retry/retranscribe, ZIP export            | ✅                                             | ✅                               | ✅                             | n/a                             |
| Dictionary (vocabulary hinting)       | ❌                                                 | ✅ (fed to AI enhancement)                                               | ✅ (initial prompt + AI prompt injection)                               | ✅ **auto-learns from corrections**            | ✅                               | ✅ CSV import                  | ⚠️                              |
| Deterministic word replacement        | ✅ remappings + filler-word removal                | ✅ separate from vocabulary                                              | ❌ (intentionally)                                                      | ✅                                             | ✅                               | ⚠️                             | ⚠️                              |
| LLM cleanup pass                      | ❌ (deliberately)                                  | ✅ prompts, many providers incl. OpenAI-compatible/Ollama, timeout/retry | ✅ "Polish" default pass + named "recipes"                              | ✅ core product                                | ✅ core product ("Avalon")       | ✅ modes w/ model choice       | ✅ prompts, BYOK                |
| Per-app modes / context awareness     | ❌                                                 | ✅ modes mapped to apps/URLs + screen/selection context                  | ❌                                                                      | ✅ app-aware formatting (casual in Slack etc.) | ✅ style-matching by destination | ✅ "Super Mode" reads screen   | ✅ app-specific prompts         |
| Snippets / voice shortcuts            | ❌                                                 | ❌                                                                       | ⚠️ recipes adjacent                                                     | ✅ spoken cue → full text                      | ⚠️ custom prompting              | ⚠️                             | ❌                              |
| Sound effects                         | ✅ w/ volume                                       | ✅ custom sounds                                                         | ✅ per-event                                                            | ✅                                             | ✅                               | ✅                             | ⚠️                              |
| Launch at login / mic picker          | ✅                                                 | ✅                                                                       | ✅                                                                      | ✅                                             | ✅                               | ✅                             | ✅                              |
| Warm-mic fast start                   | ✅ "Super Fast Mode" (pre-roll buffer)             | ✅ model prewarm                                                         | ❌                                                                      | n/a                                            | n/a                              | ⚠️                             | ❌                              |
| File/meeting transcription            | ❌                                                 | ✅ batch import                                                          | ✅ imports                                                              | ❌                                             | ❌                               | ✅ meetings                    | ✅ **core product**             |

✅ has it · ⚠️ partial/unclear · ❌ absent · ❓ unknown

## Per-app notes

### Hex (kitlangton) — architectural north star

Deliberately minimal, fully local, no LLM path. The gold is in the input handling: `HotKeyProcessor` is a pure, heavily tested state machine covering hold vs. double-tap-latch, accidental-press threshold (configurable min duration for modifier-only hotkeys), and **per-modifier left/right/either side selection** — the only open-source app surveyed that does side-specific modifiers, i.e. exactly our right-Option requirement. Floating capsule indicator with state colors and live level meter. History with paste-last-transcript hotkey. "Super Fast Mode" keeps the mic warm with an in-memory pre-roll buffer (tradeoff: persistent macOS mic indicator). Notable absences: no VAD/silence rejection, no dictionary.

### VoiceInk (Beingpax) — the everything app, GPL

Closest to our stack (whisper.cpp GGML on macOS, Swift). Broadest feature set: hybrid shortcut semantics (short press latches, long press acts as PTT — an elegant unification of our hold/latch flow), VAD on by default, streaming partial transcripts where the model supports it, **imported local model files** (our ideas.md #1), the strongest per-app/context system ("modes" mapped to apps/URLs), and the most robust delivery: snapshot _all_ pasteboard types, tag ownership, restore only if nothing else wrote since, CGEvent ⌘V with AppleScript fallback. Dictionary explicitly splits **vocabulary hinting** (fed to the model/LLM) from **deterministic replacements** (post-STT find/replace) — the split we want. Skips LLM enhancement for very short utterances.

### Whispering (epicenter-md) — pipeline clarity

Web-tech (Svelte/Tauri), so architecture inspiration only. Its virtue is an explicitly staged pipeline: raw STT → deterministic correction → optional "Polish" LLM pass → delivery, each independently configurable. Two anti-hallucination tricks worth stealing: **pads very short recordings** before sending to whisper, and its pill UI reports honestly whether text was _pasted at cursor_ or _fell back to clipboard_. VAD is a first-class recording trigger (continuous listening → auto-segment), which is the "endpointing" future. "Ship raw" button skips a slow Polish pass mid-flight.

### Wispr Flow — taste reference (user is a happy user)

Core feel: speak naturally, get _edited_ text — fillers removed, punctuation added, lists formatted, and **backtrack** (self-corrections mid-speech are applied, not transcribed: "meet at 3 — no, 4" → "meet at 4"). Context-aware micro-formatting: capitalization based on cursor position, trailing-period removal in messaging apps. **Dictionary auto-learns from your corrections.** Snippets: spoken cue expands to full formatted text. All cloud — none of the smart editing is locally reproducible without our gateway.

### Aqua Voice — taste reference (user is a happy user)

Real-time refinement while you speak (streaming mode: grammar, phrasing, formatting fixed live), style matching to destination (professional in email, casual in chat), custom dictionary, custom prompting/style rules. Cloud ("Avalon" model). Feel: hold key, talk naturally, release, done — output already reads like writing, not transcription.

### Superwhisper — the power-user benchmark

Modes (per-task prompt + model + voice-model + app-binding), "Super Mode" reads on-screen context, vocabulary with CSV import, local (Whisper/Parakeet) and cloud engines, meeting assistant, file transcription, agentic-coding pitch. Broad but heavy; the mode system is the interesting part.

### MacWhisper — transcription-first, dictation second

Core product is file transcription (diarization, subtitles, batch). Dictation exists (global hotkey — default is hold-Option-double-tap, amusingly close to our latch gesture), with optional BYOK AI cleanup and app-specific prompts. Least relevant to us except as evidence that dictation bolted onto a transcription app feels secondary — reviewers consistently rank its dictation flow below Superwhisper/VoiceInk.

## What makes the two taste references feel good

Distilled from the user's stated preferences plus the marketing/docs above — the pruning session should test each candidate against these:

1. **Zero-friction activation:** one key, hold-or-latch, no thinking. Both apps nail press-feel and near-instant start (warm capture path matters).
2. **Output reads like writing, not transcription:** fillers gone, punctuation right, casing right. In cloud apps an LLM does this; locally it's a combination of a good model, deterministic cleanup, and (later, via gateway) the cleanup pass.
3. **It learns your words:** dictionary, ideally low-ceremony (Wispr's learn-from-correction is the high bar).
4. **Invisible until needed, honest when working:** small indicator, clear states, no windows.

## Allowlist-fit notes

- Everything Hex/VoiceInk do with whisper.cpp + Apple frameworks is reproducible for us. VoiceInk's FluidAudio (Parakeet) is a third-party Swift package — assume unavailable until checked (already flagged in the engine ticket).
- Wispr/Aqua-grade _live_ editing (backtrack, streaming refinement) requires an LLM in the loop; for us that means the gateway, post-MVP, and probably per-utterance rather than truly live.
- WhisperKit (Hex's whisper path) is a third-party package (argmax) — we're committed to whisper.cpp directly, which VoiceInk proves out.

## Candidate list for the pruning session

Grouped by my read of gravity — the pruning session decides in/MVP/later/out:

**Activation & feel:** hold-to-talk; double-tap latch; side-specific pinned modifier; accidental-tap threshold; warm-mic/pre-roll fast start; cancel gesture (Esc); sound cues.
**Trust & feedback:** recording indicator overlay (capsule/pill w/ level meter); distinct transcribing state; honest paste-vs-clipboard-fallback reporting; menu bar state.
**Quality:** VAD silence rejection; short-audio padding; filler-word removal (deterministic); deterministic word replacements; vocabulary hinting (whisper initial-prompt); LLM cleanup via gateway; learn-dictionary-from-corrections.
**Delivery:** CGEvent ⌘V paste; ownership-checked clipboard restore; copy-only fallback; paste-last-transcript hotkey.
**Management:** point-at-existing model files; curated model download UI; model prewarm; mic selection; launch at login; settings window.
**Memory:** history (text ± audio), retention cap, search, retry/retranscribe.
**Context (heaviest):** per-app modes/prompts; screen/selection context; snippets.
**Likely out (other products' identities):** meeting/file transcription; diarization; translation; cross-platform; teams/shared dictionaries.
