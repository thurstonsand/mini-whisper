# Finishing MiniWhisper

## Destination

An accepted MVP design doc in `docs/designs/` — every decision resolved for the vertical "hold right-Option → record → transcribe locally → paste into the frontmost app," including distribution (signed, notarized, brew-installable) — plus the post-MVP feature set pruned from a survey of existing dictation apps and staked out by name. Planning ends there; building the MVP is execution, and post-MVP features get designed only after the MVP is daily-driven.

## Notes

- Domain: macOS menu bar dictation app. Swift 6.2, TCA. Architectural north star is [Hex](https://github.com/kitlangton/Hex) — steal its shapes, own the code.
- Research tickets are AFK fact-gathering: they touch no code, write their findings as a markdown asset in `assets/` next to `tickets/` (named after the ticket, e.g. `assets/01-dictation-app-feature-survey.md`), and link it from the resolution. They collect and recommend; they don't decide — decisions belong to the grilling tickets.
- Research tickets are safe to run in parallel (separate sessions, `claimed:` set first); grilling tickets run one at a time with the user.
- Grilling tickets run via the `grill-me` skill, Gate 1 scoped to the ticket's question. The MVP spec ticket carries through Gate 2.
- Hard constraints (from the work allowlist story — see AGENTS.md):
  - Dependencies must stay a subset of what's already allowlisted at work: whisper.cpp, swift-composable-architecture, Apple frameworks. New deps only if verified available. Exception, decided in the [engine bakeoff](tickets/09-engine-bakeoff.md): the allowlist screen is tentatively relaxed for pinned FluidAudio; final installed-artifact compliance and Parakeet CC-BY-4.0 attribution need explicit acceptance in the MVP spec.
  - Network use must stay inside the controlled network; the only sanctioned LLM egress is an OpenAI-compatible gateway.
  - Dev happens on a personal machine (unconstrained); the _installed artifact_ must comply: signed, notarized, installed via the `thurstonsand/homebrew-tap`.
- Fixed points (decided while charting, honor in all tickets):
  - Activation UX: a pinned side-specific modifier (right Option). Hold to record, release to transcribe. Double-tap to latch recording, single tap to end it. A lone tap is a near-no-op.
  - Silence rejection matters: sending silence to the engine must not produce artifacts.
  - Transcript cleanup, when it comes, talks to a configurable OpenAI-compatible endpoint.
  - Feature set and MVP line: decided — see [Prune the feature set](tickets/06-prune-the-feature-set.md) for the MVP cut and the eight ordered post-MVP stakes.
  - Security precedent: Whispering is allowlisted at work; any capability it embeds (bundled Silero VAD, local GGUF inference) should clear review for MiniWhisper too.
  - Settings persist in a human-editable JSON file from day one; a settings UI is stake #6.

## Decisions so far

<!-- one line per closed ticket: gist here, detail in the ticket -->

- [Dictation app feature survey](tickets/01-dictation-app-feature-survey.md) — seven apps surveyed into a feature matrix; Hex's HotKeyProcessor and VoiceInk's whisper.cpp stack are the key prior art; candidate list and taste rubric ready for the pruning session.

- [Prune the feature set](tickets/06-prune-the-feature-set.md) — MVP cut fixed (activation trio, pill, whisper.cpp + existing model file, silence rejection, paste-with-restore, sounds, login item, brew-tap install) and eight post-MVP stakes ordered: history, paste-last, dictionary, warm-mic, Parakeet, settings UI, model download UI, LLM cleanup.
- [Distribution: signing, notarization, homebrew tap](tickets/05-distribution-pipeline.md) — recommend tag-driven Developer ID releases as stapled app ZIPs with a generated stable cask, retaining App Sandbox only after signed CGEvent/TCC proof.
- [Hotkey mechanism and hold/latch prior art](tickets/02-hotkey-mechanism-prior-art.md) — recommend a session CGEvent tap feeding a configurable physical-chord matcher and Hex-shaped gesture machine; right Option is initial configuration, not a special case.
- [Engine landscape: whisper.cpp, models, streaming, and Parakeet](tickets/04-engine-landscape.md) — benchmark allowlisted transcribe.cpp/GGUF/Metal with Parakeet v2 Q5 leading, Turbo and base.en as controls; import models into managed storage, keep batch and genuine streaming capabilities separate.
- [Engine bakeoff: feel the latency before choosing](tickets/09-engine-bakeoff.md) — tentatively choose pinned FluidAudio v0.15.5 with Parakeet v2, reuse its proven 15-second merger rather than owning stitching, and retain whisper.cpp Medium.en as fallback.
- [Silence rejection and VAD landscape](tickets/03-silence-rejection-and-vad.md) — recommend ASREngine-owned Silero VAD before Whisper decoding, retaining complete capture audio and reusing the same activity primitive for future pure endpointing policy.
- [MVP UX: what the user sees, hears, and feels](tickets/07-mvp-ux.md) — pill fixed (bottom-center HUD: red dot + bars + device name; single-bounce latch; pulsing transcribe; transient rejection/fallback notices; success = disappearance), static menu bar icon that changes only when degraded, two-tier no-dialog errors, four built-in sound cues.
- [MVP spec](tickets/08-mvp-spec.md) — the destination: accepted design doc at [docs/designs/01-mvp.md](../../designs/01-mvp.md) folding every resolution into the full vertical, cut into nine demonstrable phases; FluidAudio's own VAD replaces whisper.cpp entirely, sandbox dropped, no voice audio ever committed.
- [Agent-driveability](tickets/22-agent-driveability.md) — one `miniwhisper.<surface>.<element>` identifier vocabulary across every surface including the nonactivating pill, gated by a curated per-surface manifest (`mise run test-ui`); the UI-test runner cannot make raw AX reads, so the gate is XCU-shaped with out-of-process fidelity proven separately.
- [Silence rejection bakeoff: prove the gate on real audio](tickets/10-silence-rejection-bakeoff.md) — select Silero v6.2 at `0.35` / `250 ms` as a whole-utterance preflight that passes accepted audio intact; retain Parakeet's empty built-in-mic “yes/no” output as an engine regression case.

## Not yet specified

- The eight post-MVP stakes and streaming graduated to tickets on user request, all blocked by the [MVP spec](tickets/08-mvp-spec.md) and opening only once the MVP is daily-driven: [History](tickets/11-history.md), [Paste-last-transcript recovery](tickets/12-paste-last-recovery.md), [Dictionary](tickets/13-dictionary.md), [Warm-mic fast start](tickets/14-warm-mic.md), [Second engine / fallback hardening](tickets/15-second-engine.md) (stake #5 reworded per the bakeoff inversion), [Settings UI](tickets/16-settings-ui.md), [Model download UI](tickets/17-model-download-ui.md), [LLM cleanup pass](tickets/18-llm-cleanup.md), [Streaming transcription and the live-text pill](tickets/19-streaming.md), [Context capture](tickets/20-context-capture.md) (added post-Phase-5: read the focused field's real text before delivery — spacing and edit-awareness without guessing), [Audio ducking](tickets/21-audio-ducking.md) (added post-Phase-7: duck actively playing audio while a recording is live, crash-safe restore), [Iconography](tickets/23-iconography.md) (added post-Phase-7: a real app icon and a consistent glyph set, verified everywhere the app is seen), [Sound design](tickets/24-sound-design.md) (added post-Phase-7: replace the borrowed macOS alert sounds with the app's own cues).

## Out of scope

- Product-ization: App Store distribution, licensing, other users' needs, marketing. This app is made for one person.
- Cloud transcription services. Speech-to-text stays local; only cleanup may cross the network, and only via the controlled gateway.
- Non-macOS platforms.
- Ruled out in [Prune the feature set](tickets/06-prune-the-feature-set.md): word remap/find-replace, per-app modes and screen-wide context awareness (focused-field text capture later reopened as [Context capture](tickets/20-context-capture.md)), snippets/voice shortcuts, meeting/file transcription, diarization, translation, shared/team features.
