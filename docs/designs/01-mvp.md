# MiniWhisper MVP

## Status

Accepted

## Decision Summary

Ship the full dictation vertical — hold/latch right-Option → capture → silence gate → local Parakeet transcription → paste into the frontmost app — as a signed, notarized, brew-tap-installed menu bar app. The engine is pinned FluidAudio v0.15.5 with Parakeet TDT 0.6B v2; the silence gate is FluidAudio's Silero VAD, re-calibrated against the bakeoff corpus before that corpus is destroyed. The key tradeoff throughout: reuse proven upstream mechanics (FluidAudio's chunk/merge, Hex's gesture shapes) rather than owning novel audio machinery.

## Problem Statement / Background

Dictation is becoming a daily part of directing coding agents, but the work machine's allowlist rules out every good dictation app; only Whispering clears review, and it is not good. MiniWhisper is a personal replacement built strictly from allowlisted or precedented capabilities. Ten wayfinding tickets ([map](../wayfinding/finishing-mini-whisper/map.md)) surveyed the field, pruned the feature set, and ran two bakeoffs (engine, silence rejection). This document folds those verdicts into one buildable spec. Planning ends here; everything after is execution.

## Goals

- One complete dictation: hold right-Option, speak, release, and the transcript appears where the cursor was — fast enough that release-to-text feels immediate (bakeoff baseline: ~100 ms warm median for short utterances).
- Latch mode: double-tap to record hands-free; single tap ends it. A lone tap is a near-no-op.
- Silence and near-silence never reach the engine and never produce hallucinated text.
- Every state the user needs is visible in exactly one place: the pill during dictation, the menu bar icon only when the app is structurally degraded.
- Installed on the work machine via `brew install thurstonsand/tap/mini-whisper`, signed and notarized, launching at login.

## Non-Goals

- The eight post-MVP stakes (history, paste-last, dictionary, warm-mic, second engine / fallback hardening (whisper.cpp Medium.en), settings UI, model download UI, LLM cleanup). `TranscriptCleanup` stays a dormant stub.
- Streaming transcription, non-default input devices, destination-app label on the pill, configurable sounds.
- Everything ruled out in [Prune the feature set](../wayfinding/finishing-mini-whisper/tickets/06-prune-the-feature-set.md).

## Exposed Shape

### End-user surface

- **Activation:** pinned physical chord, initially right Option, defined in the settings file. Hold to record, release to transcribe. Double-tap to latch, single tap to end. Escape cancels a recording outright.
- **The pill:** non-activating transparent panel, bottom-center above the Dock. States per [MVP UX](../wayfinding/finishing-mini-whisper/tickets/07-mvp-ux.md): recording (appears immediately on activation with live level bars + input device name; the red dot pops in only once capture delivers its first audio buffer), latch engaged (single ~250 ms bounce), transcribing (blue pulsing dot), "No speech detected" (fades \~1.5 s), "Copied — ⌘V to paste" (lingers ~3 s). Success is the pill disappearing.
- **Menu bar:** static template mic icon; changes only when degraded (permission missing, model missing, dead tap). Dropdown: status line ("Ready · Parakeet v2 · Shure MV7"), Copy Last Transcript, Sounds toggle, Launch at Login toggle, Settings File… (opens the JSON in the default editor), Quit. Degraded entries name the problem and deep-link the fix; the app never re-prompts a permission dialog after onboarding. No Dock icon.
- **Sounds:** four macOS built-ins — record start (short tick), commit (soft pop), cancel/rejected (muted thunk), error (Basso-class) — behind one toggle.
- **Settings file:** `~/Library/Application Support/MiniWhisper/settings.json`, exactly `{ hotkey, soundsEnabled }`. Validated at load; missing or invalid → defaults written back. Post-MVP features add keys when they land.
- **Onboarding:** the app's only modal flow. A one-time welcome asks for download consent, then starts the model download in the background while the visible flow proceeds through permissions → model compile/prewarm → one real try-it dictation (first specialization measured at 213 s; the first dictation never pays it).

### Package boundaries

The app target stays a thin shell: TCA features orchestrate, `@DependencyClient`s wrap system boundaries, pure decision logic lives in packages with plain unit tests.

- **`HotkeyListener`:** owns the session CGEvent tap, physical-chord matcher, and the pure hold/latch gesture machine (Hex-shaped). Emits gesture events — `startRecording`, `stopAndTranscribe`, `latchEngaged`, `cancel` — as an async stream. Tap death is reported, never swallowed: fail closed, surface degraded.
- **`AudioCapture`:** AVAudioEngine capture from the system default input. Prepares and retains the stopped engine graph without keeping the microphone live, emits capture-liveness and level events for the pill, and returns one complete canonical recording (16 kHz mono Float32) on stop. Retains the complete capture; nothing trims it.
- **`ASREngine`:** the transcription boundary. Owns the silence gate _and_ the engine: on submit, classify the whole conformed recording once with FluidAudio's `VadManager`; if no segment qualifies, return `noSpeech`; otherwise hand the recording **unchanged** to a resident `AsrManager`. Result is a three-way shape — transcript, `noSpeech` (gate), `engineEmpty` (engine accepted audio, returned nothing) — because the bakeoff proved these are distinct failure classes. Also exposes model lifecycle: download / compile / prewarm with progress, for onboarding.
- **Delivery (app-side client):** pasteboard write → synthetic ⌘V → ownership-checked restore of the prior clipboard (VoiceInk-style change-count check). On paste failure: transcript stays on the clipboard, prior clipboard is **not** restored — the transcript is more precious.

### External contracts

- **FluidAudio v0.15.5** (pinned exact version; tested tag has zero transitive deps — current `main` already grew a mandatory XCFramework, so every Renovate bump gets dependency review + the regression gate before merge). Parakeet TDT 0.6B v2 English Core ML is pinned to immutable revision `ee09c569f73759e6d44c9bd16766f477b2b36d39`; Silero VAD Core ML is pinned to immutable revision `b419383c55c110e2c9271fa6ee0ea83d03c70d96`. FluidAudio v0.15.5 downloads mutable Hugging Face `main`, so MiniWhisper owns exact-revision download, validation, atomic cache promotion, and provenance, then enables FluidAudio offline mode before local loads.
- **macOS TCC:** permissions requested once, in onboarding, in the empirically determined order.
- **Homebrew:** generated cask in `thurstonsand/homebrew-tap` pointing at a stapled app ZIP from a tag-driven release.

## Design Decisions

### 1. Engine: pinned FluidAudio + Parakeet v2, reuse its merger

Per the [engine bakeoff](../wayfinding/finishing-mini-whisper/tickets/09-engine-bakeoff.md): 98 ms warm median, 3.21% edit distance, ~170 MiB RSS, and text Thurston preferred. FluidAudio's `AsrManager` owns 15-second chunking and overlap merging; MiniWhisper never implements app-level chunking or stitching. The engine protocol stays model-agnostic, but no second engine ships in the MVP — whisper.cpp Medium.en is a recorded contingency (post-MVP stake #5), not shipped code.

### 2. Silence gate: FluidAudio's VadManager, re-calibrated before the evidence is destroyed

The [silence bakeoff](../wayfinding/finishing-mini-whisper/tickets/10-silence-rejection-bakeoff.md) selected whisper.cpp's Silero v6.2 at 0.35 / 250 ms. FluidAudio v0.15.5's `VadManager` uses a different 256 ms model: its public API fixes inference at 4096 samples and repeat-last-pads partial input, so the earlier 512-sample contract cannot be implemented faithfully. Phase 4 amended the contract before fixture deletion: copy the complete nonempty utterance, zero-pad that gate-only copy to `ceil(sampleCount / 4096) * 4096`, and call `VadManager` once; segmentation uses the original sample count so padding cannot manufacture speech duration. Combining the fixed real calibration split with five regenerable synthetic calibration probes selected threshold `0.90` and `150 ms` minimum speech: the lowest swept threshold that rejected every no-speech calibration probe while preserving every calibration speech fixture. The untouched real holdout retained zero false accepts and rejects, with a 13.8 ms warm median. Accepted original audio still passes intact to `AsrManager`—no trim, padding, chunk, or stitch—and the absolute VAD budget remains ≤15 ms.

### 3. Gesture pipeline: session tap → chord matcher → pure machine

Per [hotkey prior art](../wayfinding/finishing-mini-whisper/tickets/02-hotkey-mechanism-prior-art.md): a session-level CGEvent tap feeds a configurable physical-chord matcher feeding an isolated pure gesture machine (hold / double-tap-latch / tap-end / near-no-op lone tap, Hex's shapes). Right Option is configuration, not architecture. Every binding runs a modifying tap and the matcher decides what it consumes — modifier-only bindings pass through, keyed bindings suppress their trigger; interruption recovery fails closed — a dead tap ends any active recording, plays the cancel path, and degrades the menu bar icon.

### 4. One state surface at a time

The pill owns all dictation-time state; the menu bar icon changes only for structural degradation, exactly when no pill exists to tell you. Errors are two-tier and dialog-free: per-dictation issues are transient pill messages plus a sound; structural issues are the degraded icon plus a menu item naming the fix.

### 5. Settings: one small JSON file, conformed at the edge

`{ hotkey, soundsEnabled }` in Application Support, human-edited until the settings UI stake lands. Load-time validation writes back defaults on missing/invalid content. Launch-at-login state lives in `SMAppService`, not JSON — the system owns it. Model pins and engine choice are code, not settings.

### 6. Unsandboxed, hardened runtime, Developer ID

Event taps and synthetic ⌘V into arbitrary apps are the sandbox's exact target surface; Hex ships unsandboxed and Whispering's allowlisted capabilities set the review precedent. App Sandbox is dropped; Hardened Runtime stays (notarization requires it). Distribution per the [distribution research](../wayfinding/finishing-mini-whisper/tickets/05-distribution-pipeline.md): tag-driven CI producing a signed, notarized, stapled app ZIP and a generated cask in the personal tap.

### 7. No voice audio in the repo, ever

Raw bakeoff fixtures (personal voice recordings) are deleted once Phase 4's re-calibration completes. What survives: aggregate results, manifests, and the scripts/procedure to re-record an equivalent corpus. The regression gate for future FluidAudio bumps runs against a locally re-recorded corpus, not committed audio.

### 8. Attribution

Parakeet TDT 0.6B v2 is CC-BY-4.0: attribution (model name, NVIDIA, license link) ships in the README and the app's about surface, satisfying whatever the license text requires.

## Edge Cases & Failure Modes

- **Lone tap:** records for a split second, gate rejects, muted thunk, no pill message beyond the brief recording state. Near-no-op by design.
- **Escape during recording:** pill vanishes immediately, cancel sound, audio discarded.
- **Gate rejects speech-free audio:** gray "No speech detected" pill, ~1.5 s fade, thunk. No engine call.
- **Engine returns empty on accepted audio:** the bakeoff's unproven Parakeet short-word behavior. Surfaced as its own result (`engineEmpty`), logged distinctly, shown as "No speech detected" to the user — but never fixed by weakening the gate or adding phrase workarounds.
- **Paste fails (secure input, hostile field):** transcript stays on clipboard, "Copied — ⌘V to paste" lingers ~3 s, prior clipboard not restored.
- **Clipboard changed by another app mid-dictation:** ownership check (change count) skips the restore rather than clobbering.
- **Tap dies (TCC revocation, system interruption):** active recording cancels through the normal cancel path; icon degrades; menu names the fix.
- **Permission revoked while running:** same degraded path; onboarding dialogs are never re-fired — the menu deep-links System Settings.
- **Model artifacts missing/corrupt at launch:** degraded icon; menu item re-enters the onboarding download step.
- **Recording spanning 15-second boundaries:** FluidAudio's merger territory. The regression corpus keeps long speech, quiet pauses, and boundary-crossing utterances so upstream bumps can't silently drop, glue, or duplicate words.
- **Machine sleep / display lock during latch:** treated as interruption — fail closed, cancel.

## Alternatives

### whisper.cpp as the MVP engine

- **Status:** Rejected
- **Decision:** Parakeet's text and latency won the bakeoff; Medium.en survives as post-MVP stake #5 (fallback hardening).
- **Discussion:** Full evidence in the [engine bakeoff assets](../wayfinding/finishing-mini-whisper/assets/09-engine-bakeoff/README.md).

### whisper.cpp's Silero for the shipping gate

- **Status:** Rejected
- **Decision:** Bundling whisper.xcframework solely for VAD costs more than re-calibrating FluidAudio's own Silero once against the same corpus. Returns with the whisper fallback engine if that stake lands.
- **Discussion:** The 0.35 / 250 ms verdict transfers as method, not as numbers; Phase 4 re-derives the numbers before the corpus is deleted.

### Committed regression audio

- **Status:** Rejected
- **Decision:** Personal voice recordings do not belong in a publishable repo. Reproducibility (scripts + manifest + procedure) is kept instead of the audio itself.

### App Sandbox retention

- **Status:** Rejected
- **Decision:** Incompatible in practice with the tap + synthetic-paste core; prior art (Hex) ships without it and notarization does not require it.

## Implementation Plan

Each phase owns one surface of the app and ends demonstrable — something manual to poke at, so the shape and feel can be reviewed before the next phase builds on it. Phases are committable units; build, tests, and lint pass at every boundary.

- [x] Phase 0: Agent-ready repo
  - Goal: The repo tuned for fast agent iteration, stale skeleton purged, and the TCC question answered with evidence.
  - Files: `MiniWhisper/*.swift` (skeleton), `mise.toml`, `scripts/`, `.gitignore`.
  - Work: Delete stale skeleton concepts (whisper-model-size settings, emoji status strings) down to a compiling thin shell that reflects this spec's vocabulary. Verify `mise run build/test/test-packages/lint/mw/mw-fresh` and the menu-screenshot script all work cold. Verify `.gitignore` covers every raw-fixture directory (audit `git status` for voice audio). Add any missing debug lever for headless demos (e.g. structured log stream for gesture/dictation events). (A TCC permission spike was built here and deliberately discarded; the real permission set is proven when the tap and paste paths land.)
  - Validation: Cold `mise run lint` passes; `git status` shows no sensitive files.

- [x] Phase 1: Hotkey pipeline
  - Empirical TCC findings: the session tap runs on the Accessibility grant (`kTCCServiceAccessibility`) alone, because it is a `.defaultTap`. The tap option selects the permission: `.listenOnly` is gated on Input Monitoring (`kTCCServiceListenEvent`), `.defaultTap` on Accessibility (see the Phase 7 findings for how that was established the hard way). Tap creation succeeds without any grant, so creation and the listener's `monitoringStarted` signal prove nothing; only `AXIsProcessTrusted` does, and it tracks grants and revocations live in-process. A missing grant is reported as a distinct permission-missing state rather than a silent dead tap. Implementation note: modifier direction must come from the event's own device-side flag bits — `CGEventSource.keyState` lags one event at a head-insert tap.
  - Goal: Hold, latch, lone-tap, and Escape gestures recognized live from the real tap.
  - Files: `Packages/HotkeyListener/`, app-side client + `AppFeature` wiring.
  - Work: CGEvent tap lifecycle (session level, fail-closed death reporting), physical-chord matcher over the settings-file chord, pure hold/latch/tap gesture machine as an isolated type, async gesture-event stream, TCA client wrapping it.
  - Validation: Gesture machine exhaustively unit-tested (Hex's cases as baseline: hold, latch double-tap, lone tap, Escape, interruption). Demo: run the app, watch the structured log narrate `startRecording` / `latchEngaged` / `stopAndTranscribe` / `cancel` as you perform each gesture.

- [x] Phase 2: Audio capture
  - Empirical TCC findings: the mic prompt fires on the first capture start — mid-gesture, swallowing the utterance (the interrupted capture completed empty without error), which confirms Phase 7 onboarding must front-load the request. Prompt body is the `NSMicrophoneUsageDescription` string: "MiniWhisper needs microphone access to transcribe your speech."
  - Goal: A hold produces a complete canonical recording and live levels.
  - Files: `Packages/AudioCapture/`, capture client, `RecordingFeature`.
  - Work: AVAudioEngine capture from default input; conform to 16 kHz mono Float32 at the edge; level metering stream; complete-capture retention; start/stop tied to gesture events; debug affordance that writes the finished capture to a WAV in a temp dir.
  - Validation: Package tests for conformance/accumulation seams. Demo: hold and speak, play back the WAV, watch levels move in the log.

- [x] Phase 3: The pill
  - Goal: Every pill state from the UX ticket, driven by real gestures and levels.
  - Files: `MiniWhisper/` pill panel + feature (new), wiring into `AppFeature`.
  - Work: Non-activating transparent NSPanel, bottom-center above the Dock; recording state (red dot, live bars, `AVCaptureDevice.localizedName`); latch bounce (~250 ms, eased, once); transcribing state (blue pulse); transient notices ("No speech detected" ~1.5 s, "Copied — ⌘V to paste" ~3 s); Escape-cancel instant vanish. Transcribe/notice states are demo-triggerable until the engine exists.
  - Validation: Reducer tests for state transitions. Demo: perform each gesture and watch every state, bounce included, in place over the Dock.

- [x] Phase 4: Engine + silence gate
  - Empirical findings: FluidAudio v0.15.5's `VadManager` fixes inference at 4096 samples (design amended — see Decision Point 2) and its downloader fetches mutable HF `main`, so the app owns exact-revision download/validation/provenance; Hugging Face's pinned resolve URLs preserve open-ended HTTP Range requests through their CDN (`206` with an exact `Content-Range`), enabling durable mid-file resume without weakening final SHA-256 verification; the signed redirect is bound to the original Range header, so the downloader reapplies that header on redirects and never persists the CDN URL. Resumable staging uses a revision-pair marker to discard incompatible trees, then reconstructs completed-file progress from the pinned manifest rather than a parallel progress file: completed LFS files must match size plus the manifest oid, and every transferred file is hashed before atomic promotion. Rehashing the installed 465 MB corpus cost 196–230 ms warm versus ~2 ms for existence/size validation, so launch uses existence/size and leaves corruption to fail loudly during Core ML load/prewarm. `VadSegmentationConfig`'s `negativeThreshold` initializer argument trips a contradictory debug assertion and must be assigned post-init. Post-phase latency work: activation → pill 3–8 ms, activation → first audio buffer ~230 ms (budgeted in `mise run benchmark-live`).
  - Goal: Released audio becomes a transcript (or an honest rejection) locally.
  - Files: `Packages/ASREngine/`, engine client, `AppFeature` wiring; bakeoff harness under `docs/wayfinding/.../assets/10-*/` for re-calibration.
  - Work: First, re-calibration: run the silence-bakeoff harness against FluidAudio `VadManager` on the existing 34-fixture corpus; select thresholds hitting zero false accepts/rejects on both splits (escalate if unreachable); record aggregates; then delete every raw voice fixture and document the re-record procedure. Then production: pinned FluidAudio dep; `ASREngine` gate → resident `AsrManager` submit path with the three-way result; model lifecycle API (download pinned revision, compile, prewarm, progress); minimal interim model-setup path (menu-triggered) until Phase 7's onboarding. Wire release → gate → transcribe → pill states. 15 ms VAD budget asserted in the regression harness.
  - Validation: Regression run over the (re-recorded or pre-deletion) corpus: classifications match manifest, long/boundary fixtures stitch cleanly, VAD budget holds. Demo: hold, speak, release — transcript in the log; silence — "No speech detected."

- [x] Phase 5: Delivery + sounds
  - Empirical TCC findings: synthetic ⌘V is gated by `kTCCServicePostEvent` (surfaced under Accessibility in System Settings), reset separately from `kTCCServiceAccessibility` by `mise run reset`, though an Accessibility grant satisfies it; a fresh run prompts in gesture order (Microphone at first capture, Accessibility at first paste). `CGPreflightPostEventAccess` caches its first answer per process and `CGRequestPostEventAccess` never lists the app in Accessibility, so the app asks with `AXIsProcessTrustedWithOptions` (which does list it) and reads status with `AXIsProcessTrusted`, which tracks grants and revocations live. Caveat for onboarding tests: terminal-launched runs can inherit the terminal's grants via responsible-process attribution — first-run evidence only counts from a Finder-launched .app.
  - Goal: The vertical completes — transcript lands at the cursor; the app is daily-drivable from this phase on.
  - Files: Delivery client, sounds client, `AppFeature` wiring.
  - Work: Pasteboard write → synthetic ⌘V → ownership-checked restore; fallback path (keep transcript on clipboard, no restore, pill notice); the four sound cues behind the settings toggle; success = pill disappearance.
  - Validation: Reducer tests for delivery outcomes incl. fallback and skipped restore. Demo: dictate into a real editor, a browser field, and a secure-input case to see the fallback; hear each cue.

- [x] Phase 6: Menu bar
  - Goal: The healthy/degraded surface and the full dropdown.
  - Files: `MiniWhisper/MenuBarController.swift`, `AppFeature`, settings store.
  - Work: Static template icon; degraded variant driven by structural failures (permissions, model, dead tap) with deep-linked fixes; dropdown per the UX ticket — status line, Copy Last Transcript, Sounds toggle, Launch at Login (`SMAppService`), Settings File… (opens JSON in default editor), Quit. `LSUIElement`, no Dock icon.
  - Validation: Reducer tests for degraded derivation. Demo: `capture_menu_screenshot` of healthy and induced-degraded states; toggle each item live.

- [x] Phase 7: Onboarding
  - Empirical TCC findings (macOS 26.5.2): Input Monitoring is gone from the app entirely. Two findings landed together. First, tccd refuses to prompt for it at all — `Service kTCCServiceListenEvent does not allow prompting; returning denied.` — so `IOHIDRequestAccess`, `CGRequestListenEventAccess`, and a listen-only event-tap attempt each come back denied with no dialog and no row for the user to switch on; running from `/Applications`, registering with Launch Services, and holding Accessibility first change nothing (developer forums thread 828082 corroborates). That produced a manual-add guidance flow — deep link, bundle path, ⇧⌘G — which shipped for a day. Second, and fatal to the whole concept: Accessibility already covers the listen-only keyboard tap. With `kTCCServiceListenEvent` reset to denied and only Accessibility granted, the full vertical ran on this host — hold, latch, transcribe, paste — while the preflight logged `iohid=false ax=true`. Karabiner-Elements reached the same conclusion in 16.0.0 ("Input Monitoring… is covered by the Accessibility setting"). So the permission set is Microphone + Accessibility, the manual-add flow and every IOHID call are deleted, and the Accessibility step's copy now names all three things that grant buys: the hotkey, the paste, and the field read. Evidence: `/tmp/imtest2.tcc.log` through `/tmp/imtest6.tcc.log` for the prompting refusal; the live dictation run for the coverage.
  - Correction (later, on the installed release build): the second finding was right in its conclusion and wrong in its mechanism, and it nearly cost the permission model. Accessibility does not cover a listen-only tap. The two tap options are gated on different services — WWDC 2019 "Advances in macOS Security" states it outright: "a listen-only event requires authorization for input monitoring, a modifying event app requires authorization for accessibility features." The coverage experiment ran against `com.thurstonsand.MiniWhisper.dev`, a bundle id that still carried a `kTCCServiceListenEvent` row from the Input Monitoring era, so the listen-only tap worked for a reason unrelated to Accessibility. The release bundle id, which never had that row, exposed it: `AXIsProcessTrusted` true, menu reading Ready, and `CGGetEventTapList` reporting the app's tap `enabled=false` — creation succeeds, the tap is born disabled, and no API says so. Karabiner's claim holds because Karabiner uses a modifying tap. The fix keeps the permission set (Microphone + Accessibility) and changes what earns it: `HotkeyListener` always creates a `.defaultTap`, so macOS checks the grant MiniWhisper already requires for the paste and the field read. Measured cost of the synchronous path, 300 injected keystrokes per run, three interleaved runs: median 2.41/2.67/2.37 ms against a 2.18/2.58/2.69 ms baseline — under noise, with the modifying tap faster in one run.
  - Goal: A fresh machine reaches "Ready" through one guided flow.
  - Files: Onboarding feature + window in `MiniWhisper/`.
  - Work: First-run detection; one startup join resolves completion, download consent, microphone, Accessibility status, and the engine's first readiness value into the initial snapshot. A one-time welcome requests explicit consent before writing a durable model-download marker and starting the ~450 MB transfer in the background. A consented relaunch skips the welcome and resumes a pin-matched staging tree's manifest-verified completed files plus any SHA-covered ranged partial from `Engine/pinned-v1.partial`; every file is hashed before atomic promotion, while ordinary launch validation is existence/size. The permissions page polls once a second but exposes exactly one action at a time in Microphone → Accessibility order; each native request is issued once on the main actor and suspends polling while it runs. The microphone request awaits its own answer, so polling resumes the moment it returns; a false Accessibility result cannot prove its prompt is gone, so that one resumes when MiniWhisper becomes active again. Neither grant needs a relaunch: `AXIsProcessTrusted` reports live, so polling picks the grant up and the hotkey listener starts in place. After setup the same reconciliation runs on app activation and menu open, which is what lets a grant or a revocation made years later move the listener without a relaunch. Derived state resumes setup in place; the rail carries compact background model progress and the full model page continues through compile/prewarm (the 213 s cost lives here, visibly); terminal "try it" moment with a completion-marking Skip escape hatch; degraded menu items re-enter the relevant step.
  - Validation: Demo: `mise run mw-fresh` (extended to reset all involved TCC classes and model-download consent) walks the full flow to a working first dictation. Kill the app during the Encoder weights transfer, relaunch, and verify the logged nonzero Range offset; poison a staged partial and verify its final hash failure restarts that file cleanly.

- [x] Phase 8: Distribution
  - Goal: `brew install thurstonsand/tap/mini-whisper` on the work machine.
  - Files: CI release workflow, signing/notarization config, cask generation, README (attribution), about surface.
  - Work: Drop App Sandbox / keep Hardened Runtime entitlements; tags publish stable releases and casks while main publishes nightly prereleases and a conflicting nightly cask; build, Developer ID sign, notarize, staple, and ZIP before updating `thurstonsand/homebrew-tap`; CC-BY-4.0 attribution in README and about; verify Renovate tracks the pinned FluidAudio version and document the bump gate (dependency review + regression corpus run).
  - Validation: Clean install from the tap on a second account/machine; signed-artifact TCC prompts match the development machine's observed set; first launch runs onboarding to a successful dictation.
  - Outcome: v0.1.0 published, signed, notarized, stapled, and installed from the tap — `spctl` reports `source=Notarized Developer ID`. Nightlies publish from every `main` push and version above the last stable tag.
  - Correction (later): the conflicting nightly cask is gone. Stable and nightly are separate apps — `MiniWhisper.app` from the Release configuration, `MiniWhisper Nightly.app` from a Nightly one — so their bundle identifiers, TCC grants, and application support directories never meet and both casks can be installed at once. A shared identity was what let a stale grant on one build mask a missing grant on another, which is the failure the Phase 7 correction chased.
