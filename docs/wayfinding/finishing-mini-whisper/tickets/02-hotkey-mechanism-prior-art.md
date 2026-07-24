---
status: closed
claimed: hotkey-research
type: research
blocked-by: []
---

# Hotkey mechanism and hold/latch prior art

## Question

The activation UX is fixed: pinned right-Option, hold-to-record / release-to-transcribe, double-tap to latch, single tap ends a latched recording, lone tap ≈ no-op. What is the right mechanism, and what prior art exists for the state machine?

- Side-specific modifiers rule out Carbon `RegisterEventHotKey`; confirm the CGEvent-tap (`flagsChanged`) approach, the Input Monitoring permission flow, and its failure modes (tap disabled by timeout, secure input, permission revocation).
- Study Hex's `HotKeyProcessor` (its most-tested type) and any equivalents in VoiceInk/Whispering: how they encode hold vs. double-tap-latch vs. cancel, debounce windows, and how they test it.
- Output: `../assets/02-hotkey-mechanism-prior-art.md` — a summary with a recommended event pipeline and a sketch of the pure state machine (events in, start/stop/cancel decisions out) suitable for the `HotkeyListener` package.

## Resolution

[Hotkey mechanism and hold/latch prior art](../assets/02-hotkey-mechanism-prior-art.md) confirms a session-level CGEvent tap feeding a configurable physical-chord matcher and isolated pure gesture machine, with passive observation for modifier-only bindings, optional active suppression for keyed bindings, fail-closed interruption recovery, and recording-session ownership. Right Option is the initial configuration, not an architectural special case. Hex supplies the gesture and test baseline, VoiceInk the narrower event-adapter precedent, and Whispering the asynchronous recording-safety pattern.
