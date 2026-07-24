---
status: closed
claimed: charting-session-foreground
type: grilling
blocked-by: [2, 3, 6]
---

# MVP UX: what the user sees, hears, and feels

## Question

The UX/UI of the initial vertical, concretely. With the MVP line fixed and the hotkey/silence research in hand: what does the menu bar item show in each state (idle/recording/transcribing/error)? Is a recording overlay indicator (Hex's invisible NSPanel) in the MVP or after it? How are errors surfaced (no model, mic permission denied, tap disabled, empty/silent transcription)? What happens to the transcript — paste with clipboard restore, clipboard fallback, both? Sound cues? Consider a prototype (sketch or throwaway UI) if words aren't enough; this is HITL — the user reacts, the ticket records the chosen shapes.

## Resolution

Decided via interview plus animated sideshow mock-ups; Thurston approved each shape. Aqua Voice's recording box (live text, destination app, input device, screenshot context) served as reference.

**The pill** — Hex-style non-activating transparent NSPanel, bottom-center just above the Dock, fixed position. States:

- *Recording (hold):* red dot + live level bars + input-device name on the pill (`AVCaptureDevice.localizedName`) — wrong-mic diagnosis at a glance.
- *Latch engaged:* no glyph; the pill bounces once — a single gentle scale-up/down, ~250 ms, eased — then continues identically.
- *Transcribing:* blue pulsing dot + “Transcribing…”; bars and device dropped.
- *Silence rejected:* gray “No speech detected”, fades after ~1.5 s.
- *Delivery fallback:* “Copied — ⌘V to paste”, lingers ~3 s.
- *Success has no state:* the pill disappears; the pasted text is the confirmation. Escape-cancel: pill vanishes immediately, cancel sound plays.
- Destination-app label (“→ Ghostty”) considered and skipped for MVP — device only.

**Menu bar** — static template mic icon while healthy; the pill owns dictation state exclusively (state changing in two screen regions was judged worse UX). The only icon change is *degraded* (dimmed/slashed) for structural failures — permissions, missing model, dead tap — exactly when no pill exists to tell you. Dropdown: passive status line first (“Ready · Parakeet v2 · Shure MV7”), then Copy last transcript, Sounds toggle, Launch at login, Settings file…, Quit. Degraded menu names the problem and deep-links the fix; never re-prompt permission dialogs. No Dock icon.

**Errors** — two tiers, no dialogs. Per-dictation issues are transient pill messages + a sound; structural issues are the degraded icon + menu item. On delivery fallback the transcript stays on the clipboard and the previous clipboard is NOT restored — the transcript is more precious. The only modal moments in the app's life: first-run onboarding (mic + Input Monitoring permissions, model setup).

**Sounds** — macOS built-ins, one global toggle, exact names tuned by ear: record start = short tick; commit = soft pop; cancel/discard (Escape or silence-rejected) = muted low thunk; error = Basso-class. No separate latch-engage sound — the second tap's start sound plus the bounce suffice.

**Recorded for the future, not built:** the pill grows upward into an Aqua-style live-text box when streaming transcription lands; click-and-drag pill repositioning; destination-app label; screenshot-as-context for the cleanup pass.
