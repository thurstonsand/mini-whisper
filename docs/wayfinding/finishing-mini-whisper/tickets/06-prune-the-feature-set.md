---
status: closed
claimed: charting-session-foreground
type: grilling
blocked-by: [1]
---

# Prune the feature set: MVP line and post-MVP stakes

## Question

Given the feature survey, which features are in this app at all, which sit inside the MVP, and in what order do the rest land? A grilling session over the survey matrix: for each candidate feature, in/out/later, with the user's Aqua Voice / Wispr Flow habits as the taste reference. The output fixes the MVP line ("usable daily at work" is the bar), names the post-MVP stakes in priority order, and updates the map — graduating fog into future tickets where the answers make them specifiable, and moving rejected features to Out of scope.

## Resolution

Decided against the [survey](../assets/01-dictation-app-feature-survey.md) candidate list and its taste rubric.

**MVP** ("I dictate daily at work"):

- Hold-to-talk on the pinned right-Option, double-tap latch, accidental-tap rejection (one state machine)
- Recording pill overlay: states + live level meter
- whisper.cpp engine, point-at-existing model file — plus hard-coded links to a recommended model set in lieu of any download UI
- Silence rejection: Silero VAD if the whisper.cpp research confirms it's usable, else an energy gate for MVP with VAD to follow
- Paste with ownership-checked clipboard restore (VoiceInk-style)
- Sound effects from macOS built-ins
- Launch at login
- Signed/notarized brew-tap install — distribution is inside the MVP; it isn't a daily driver at work until it installs there
- Mic: system default only; settings live in a human-editable JSON file from day one (a settings *UI* comes much later)

**Post-MVP stakes, in priority order:**

1. History — text + audio, with an option to disable audio storage
2. Paste-last-transcript hotkey + menu item to re-copy to clipboard
3. Dictionary — vocabulary hinting only (whisper initial-prompt); word remap/find-replace explicitly excluded
4. Warm-mic fast start, with an easy toggle (gesture like triple-press vs. separate bind — decided in the UX ticket)
5. Parakeet second engine — contingent on the engine research finding a path without FluidAudio (verified NOT allowlisted)
6. Settings UI — tolerable to hand-edit the JSON until then
7. Model download UI
8. LLM cleanup pass — optional, via the OpenAI-compatible gateway, deliberately last (it's slow)

**Excluded** (out of scope until the destination is redrawn): word remap/find-replace, per-app modes and screen/selection context awareness, snippets/voice shortcuts, meeting/file transcription, diarization, translation, shared/team features. Streaming transcription is excluded from the stakes; reconsider only if Parakeet lands (whisper.cpp can't genuinely stream). BYO sound effects noted as a possible future nicety under sounds.

**Security precedent worth recording:** Whispering is allowlisted at work (though unusably bad). Anything Whispering embeds or does — e.g. bundled Silero VAD, local GGUF inference — is therefore precedent that the same capability in MiniWhisper should clear review.
