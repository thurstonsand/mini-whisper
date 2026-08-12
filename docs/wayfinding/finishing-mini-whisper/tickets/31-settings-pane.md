---
status: open
type: build
claimed: settings-pane-build
blocked-by: []
---

# Settings pane

## Mission

Fill the settings window's default destination with the real pane, executing the contract settled in [Settings UI](16-settings-ui.md): ordered by how often a thing changes — Shortcuts, Microphone, Sounds, then Open at login with Version at the bottom. This is the fast-follow [History](11-history.md) deliberately scoped out, and it carries that ticket's debt: the pane is what finally ends hand-editing `settings.json`, so the menu bar's "Open Settings File" item dies here.

## Scope, settled at kickoff

1. **Shortcuts ship the full recorder.** Click a binding to rerecord it; multiple bindings or none; the `⋯` menu holds only Add Another and Remove. Key names follow Wispr's shorthand — glyph, short word, and a direction arrow for sided modifiers: right Option renders as `⌥ Opt →`, its left twin `⌥ Opt ←`. `HotkeyListener` already models `Hotkey`; the recorder UI and multi-binding storage are the new work.
2. **Microphone picker: system default or an explicit device**, ranked fallback lists stay dropped. An explicitly chosen device that is absent falls back to system default, and the pane says so — some visible "chosen device not found, using default" state rather than silence. How macOS exposes device arrival/departure (and how reliably) is an open investigation: learn from open-source dictation apps' device handling first, and a small spike is authorized if the AVFoundation/CoreAudio surface is murkier than prior art suggests.
3. **Sounds become per-cue pickers now, over the built-in system sounds.** This performs the `soundsEnabled: Bool` → per-cue settings migration that [Sound design](24-sound-design.md) flagged, so that ticket later swaps assets, not structure. Choosing a sound plays it; a play button replays it; `No audio` is dimmed so silence reads as the absence of a choice. Custom/authored cues remain ticket 24's.
4. **Mute-while-active is excluded.** That row is [Audio ducking](21-audio-ducking.md)'s feature wearing a toggle; the row appears when the mechanism exists.
5. **Permissions stay invisible until broken.** A granted capability shows nothing; an ungranted one pins an orange row to the top of the pane, reusing the menu bar's degraded-state detection. If onboarding's System Settings deep-links (prepopulating the right pane) can be reused from here, do it — same repair, same door.
6. **The menu bar slims.** Sounds and Open-at-login toggles migrate into the pane and leave the menu; "Open Settings File" is removed. The menu keeps status, Copy Last Transcript, Settings…, About, Quit. A full re-evaluation of what the menu *could* be — CodexBar-style rich content is the known ceiling; patterns already noted in [`CODEXBAR_PATTERNS.md`](../../../CODEXBAR_PATTERNS.md) — is deferred to its own future ticket rather than smuggled in here.

## Built: element 1 — Shortcuts

The pane exists with its first real section, and the two hardest problems it surfaced are settled window-wide.

- **The model**: `hotkeys: [Hotkey]`, ordered, possibly empty; a file with the old singular key decodes into a one-element array. Bindings are alternatives — `MultipleChordMatcher` activates exactly one per press, even for duplicates hand-edited into the file.
- **The recorder** lives in `HotkeyListener` and owns the keyboard outright while capturing: live chord as keys go down, full release commits, Escape always cancels. AppFeature stands the activation listener down before the recorder tap installs, so recording right Option cannot start a dictation. Duplicate commits are no-ops; validation failures show why and keep recording.
- **Witnessed keys only.** Both the recorder and the listener once prescanned `CGEventSource.keyState` over 0–127 to seed "currently held" state. A stuck ledger entry (keycode 127 — past the end of the virtual-keycode table, so no key-up can ever clear it) wedged the recorder into swallowing the entire system keyboard and starved activation dead. Both now track only transitions their own tap witnessed; no external ledger can wedge them again.
- **Display**: `HotkeyDisplayName` is the one vocabulary — `⌥ Opt →` — rendered as Wispr-style per-component keycap boxes (`HotkeyKeycaps`, shared with onboarding). Every runtime surface derives from the live first binding; empty bindings produce honest "set a shortcut in Settings" copy, never a ghost key.
- **The input grammar**, settled in the spike's cursor labs and playground: a 3pt accent bar is the row cursor, a focus ring marks the target within the row (keyboard-only). `j`/`k` move rows, `h`/`l` walk targets, `h` past the leftmost ascends to the sidebar, Return is the only press. Mouse hover moves the same bar — moves only, never clears — and the ring never appears in mouse mode. The `⋯` menu is deliberately mouse-only: a popover Return could open but keys couldn't drive was built and rejected.
- **Window laws** (fixed here, owned window-wide): chrome is pinned by a persistent toolbar with a keeper item in the `.navigation` group — pane selection can no longer change titlebar or sidebar geometry, and the keeper cannot stretch a pane's button capsule. Detail focus is carried by a persistent host outside every pane's Form/List, assigned on the window's `didBecomeKey`, so switching destinations cannot kill it and a focused pane can never paint nothing.
- **Regression insurance**: XCUITest contract batches for the settings focus/paint laws and the History cursor laws (one-grey counted across all rows, copy-keeps-cursor, round-trip, parked pointer, search), asserting AX state derived from the same expressions that drive paint.

Remaining after element 1: Microphone (built — see below), Sounds (3), permissions row (5), Open at login/Version, and the menu slimming (6).

## Built: the onboarding Shortcut step

A fast-follow the pane earned immediately: the primary binding is now chosen during onboarding, in a new step between Permissions and Speech Model. The model download runs behind it untouched.

- **The page**: hero-scale keycap that *is* the button — the settings row's contract writ large. Click (or focused Return/Space) → grey "Recording…" chip → live chord; release commits, Escape keeps whatever was last committed. One caption toggles "Click the shortcut to change" ↔ "Record your shortcut"; no ring while recording. Only the primary binding lives here — extras stay in Settings and are preserved by every commit.
- **One recorder, named**: `HotkeyBindingsFeature` owns bindings + recording + delegates; the settings pane (cursor/hover chrome only) and onboarding both scope to it. Commit policy is one invariant — a hotkey appears in the list at most once. `primaryBindingTapped` is the only holder of "empty appends, else replace index 0." AppFeature's cancel-before-install/restart-after-stop serves both consumers through one `beginHotkeyRecording`.
- **The window keyboard grammar**: Return activates the visible step's primary action on every page (the active permission's action as grants land, included). Tab visits only the page's actionable controls — rail buttons are mouse affordances, out of the chain everywhere; Shortcut and Try It own explicit two-target cycles driven by a `tabCycle` table and a window-scoped Tab monitor (`WindowTabKeys`), because SwiftUI key handling is deaf until a SwiftUI view owns focus. First Tab lands on the keycap; unfocused Return always sails to Continue.
- **Focus laws, learned the hard way**: claim focus when the field exists, not when the state that summons it changes — `.defaultFocus` fails on real mid-flow transitions, and `.onAppear` races AppKit's key-view selection (the Try It Skip button briefly wore focus paint nobody asked for). Focus paint derives only from `@FocusState`; the system focus effect lies and stays disabled where hand-drawn rings exist. Both laws recorded in the skill.
- **Pixel-truth testing**: entry states are asserted from decoded screenshots (zero focus-blue where no focus is claimed) after AX-only assertions passed while pixels showed a phantom ring. AX values derive from the same expressions that paint (`accessibilityPaintState`), real typed key events drive the keyboard suites, and scenes seed dependencies — a fixture bug had every onboarding scene wired to the live settings.json, and a UI test wrote into it before it was caught.
- Standing sighting, unreproduced: one report of a stray Skip focus ring post-refactor; a focus trace showed honest behaviour and is recoverable from session 019fd8f6 (`category == "focus-trace"`).

## Built: element 2 — Microphone

The picker: System Default or one explicit device, persisted as CoreAudio UID plus last-known name (the name exists only so the UI can speak about an absent device). Absent settings key decodes to System Default. An absent explicit device falls back to the current default with a visible sentence — "[Name] not connected. Using system default: [Default]." — and the stored selection is never overwritten; it heals when the device returns. The row is a full cursor-grammar citizen (j/k, ring, Return opens the popup) and carries a live level meter: the pill's own `AudioLevelBars` extracted and shared (pill rendering byte-identical, hash-proven), fed raw per-buffer RMS through the same normalization — no smoothing anywhere; the one lag ever observed was stock ProgressView's presentation animation, root-caused and removed.

What the spike campaign proved (`spikes/mic-binding-spike/`, the evidence record):

- Explicit binding via `kAudioOutputUnitProperty_CurrentDevice` on a fresh unprepared engine works for ordinary devices, cold USB included (Shure MV7). Ordering is irrelevant; readback is asserted; formats are read only after binding.
- System Default stays deliberately **unbound** — the engine follows macOS's own routing, which erases default-churn prewarm staleness and keeps Continuity-as-default working (coreaudiod owns that wake).
- Continuity mics are unreachable via app-local HAL binding — readback succeeds, IO never starts, even during a successful concurrent AVCaptureSession capture of the same phone. Not an OS impossibility: Apple's sanctioned app-local route is an AVCaptureSession backend (Continuity Camera sample), so Continuity is excluded from explicit selection until that backend exists — recorded follow-up, backend-tagged selection identity (`AVCaptureDevice.uniqueID` is a different namespace than CoreAudio UIDs; never bridge by name).
- Idle virtual/loopback devices and sleeping headset dongles clock zero or silent buffers by nature; the silence gate absorbs the empty result — no watchdogs.
- Device filtering is by declared attribute only, never name: `IsHidden == 1` dropped; aggregate-transport devices declaring composition `private = 1` dropped — that is AVAudioEngine's own `CADefaultDeviceAggregate` (which declares `IsHidden = 0`), usually manufactured by our own prewarmed engine and reflected back by enumeration. User-created Audio MIDI aggregates declare `private = 0` and survive.

Architecture: one `MicrophoneSelection` type (lives in AudioCapture; AppSettings imports it like Hotkey); one selectability policy feeding both enumeration and resolution, contract-tested so the picker can never offer what the route won't bind; fresh UID resolution before every prepare/start (`kAudioObjectUnknown` means absent, never an error); prewarm keyed by resolved binding and re-prepared on selection commit (pane delegate → AppFeature → RecordingFeature); debounced CoreAudio listeners (250 ms, retained blocks, same-queue removal) publishing immutable snapshots only while the pane is open; the meter runs its own engine through the shared `AudioEngineInput` seam — CoreAudio is multi-client, so it coexists with real dictation (proven live) and can never diverge from capture on resolution policy. Mid-recording device loss keeps the conservative failure; a sibling quality audit collapsed the routing types (`AudioInputBinding`), fixed a reachable release-beats-session-ID hang on silent devices, and caught the menu naming the default instead of the selection.

Remaining: Sounds (3), permissions row (5), Open at login/Version, and the menu slimming (6).

## Built: element 3 — Sounds, and the gesture machine it provoked

The pane's Sounds section: four rows — Activate, Complete, Cancel, Error — each a native popup over the sounds enumerated live from `/System/Library/Sounds` (logged fallback to the classic four), with a trailing play button on one vertical line. Choosing plays once; the play button replays; playback stops-then-restarts on spam. "No audio" sits first and dims only while it is the selection — a dimmed row inside an open menu reads as disabled (and `NSPopUpButtonCell.menuItem` with a detached display item renders blank; the trap is real). Each cue's default is annotated `Name (default)` and injected even if enumeration misses it. `SoundSettings` is four optional names on the shared settings value; absent key means default, explicit null means deliberately silent. The menu bar's Sounds toggle died with the bool that backed it. There is no legacy decode of any kind — `soundsEnabled` and the singular `hotkey` key were purged with the no-users-exist rule; an empty settings file resolves to the defaults.

Touring the cues exposed the double-tap playing the activate cue twice, and the fix cascaded into the largest gesture-machine change since witnessed-keys. Two research passes ground it (cue timing: Hex replays the cue on double-tap — defensible company, left; tap norms: QMK/ZMK's 200 ms tap-hold default, clearing the 116 ms mean typing dwell):

- **One continuous capture per interaction.** Phases `idle → holding → provisional → secondPress → latched`; a release under `tapMaximumDuration` (200 ms) enters provisional with the capture still running and no event emitted — the pill truthfully shows recording across a forming double-tap, the inter-tap audio lands in the transcript, and the old start/stop/start churn (with its mid-tap "no speech" race) is unrepresentable. `doubleTapWindow` (300 ms) is now first-release→second-press, Android's double-tap semantic, and doubles as the provisional deadline. A second press classifies at its own release: short latches, long is tap-then-hold — one dictation from the first press.
- **The machine stays a pure value type.** Provisional is its first state unstable under silence, so the deadline arrives as an input (`deadlineElapsed`), scheduled by a cancellable reducer clock effect with a generation token against stale deadlines. Machine tests are phase × input tables.
- **The cue law is structural**: `startRecording` is emitted once per interaction, so "one interaction, one cue, at onset" needs no suppression flag. The gate gained a 500 ms `minimumUtteranceDuration` floor ahead of VAD — speech physics, deliberately not gesture timing — and too-short discards are logged and wordless.
- **Escape archives instead of destroying**: cancel cue, no delivery, transcript into history with nil delivery, pill notice "Cancelled — saved to History", and Copy Last Transcript serves it — the fastest recovery for an accidental Escape. Escaped silence dismisses quietly. Foreign input early in a press is a silent misfire discard; after 300 ms it passes through and recording continues (no surveyed app aborts an established recording; Apple dictation types while listening). Typing while latched is supported.
- **The cursor law was amended** while unifying: hover and the keyboard cursor are one row state per surface, and hover carries focus into the detail column (a bare hover must paint); a parked pointer still steals nothing.
- **Focus returns on window close**: an accessory app that activates itself owes focus back. `ActivationHandback` keeps a rolling last-frontmost-that-wasn't-us (Rectangle's shape — a one-time snapshot goes stale) and gives back via cooperative `yieldActivation` (Ice's mechanism), only if we still hold focus. Settings and About use it; onboarding's `NSApp.hide` already passes focus back; the pill is a nonactivating panel and never takes it.

Decision evidence: cue-timing survey (session 019fdd0f), tap-norm/foreign-key survey (session 019fdd3f), focus-return survey (librarian run 019fddcd).

Remaining: permissions row (5), Open at login/Version, and the rest of the menu slimming (6).

## Built: the paste-last rebind row

[Paste-last recovery](12-paste-last-recovery.md) brought a second action into the Shortcuts section, and the section absorbed it as a sibling rather than a special case: one `ShortcutRow` view parameterized by command renders both rows with the same keycap/chip/recorder presentation, and `HotkeyBindingsFeature` edits whichever command's array it is constructed for. What the second action forced structural:

- **The model became per-action.** `HotkeyBindingsSettings` holds `activate` and `pasteLastTranscript` arrays; the flat `hotkeys` key is gone with the no-users-exist rule. A chord belongs to at most one command — enforced at construction and in decode (a hand-edited duplicate fails fast), so ambiguous matcher routing is unrepresentable rather than checked.
- **One recording at a time, one guard.** A shared `recordingCommand` coordinator spans the editor children; `beginRecording` is the single gate for every input path, and commit/cancel/clear releases it. The row `.disabled` state is cosmetic.
- **Unbound is legitimate for paste-last.** Its last binding can be removed; the pill narrates the state ("Nowhere to paste — transcript saved to History"). The Shortcuts footer now scopes hold/double-tap guidance to activation.

## Inherited constraints

- The window's input model is already law: the pane participates in the h/j/k/l loop (`h` ascends to the sidebar), and keyboard focus behavior follows the contract recorded in [History](11-history.md).
- "Activate", not Dictate: hold to dictate, double-tap for hands-free, stated once as the Shortcuts section footer.
- Settings writes go through the single `@Shared` settings value; no per-key clients return.
- Design rules in [`.agents/skills/native-macos-ui`](../../../.agents/skills/native-macos-ui/SKILL.md) bind; the mock-up at [`spikes/settings-mockup`](../../../spikes/settings-mockup/SettingsMockup.swift) is the visual reference for this pane's rows.
