---
status: closed
type: grilling
blocked-by: [16]
---

# Onboarding capability recovery

## Question

Proposed by the [competitor audit](../assets/25-competitor-feature-audit.md). Onboarding today is a one-shot flow ending at a completion marker. How should the app re-check permissions, input device, and model readiness after that; re-run the try-it practice; and introduce later high-risk capabilities — without growing a permanent dashboard the user has to look at?

## Notes

- Not a duplicate of the degraded menu bar, which *reports* a broken capability and offers one repair. This is about re-entering the flow that *establishes* a capability, and about proving a new one works before it is trusted with real text.
- [Keyboard navigation](27-keyboard-navigation.md) owns reaching existing onboarding without a mouse; [Settings UI](16-settings-ui.md) owns configuration. Neither owns reset or re-check, which is why this earned its own stake.
- Blocked on the settings window because a re-entry point almost certainly lives in it, and because the answer may turn out to be a settings row rather than a flow.
- The try-it step is the shape to reuse: a real dictation through the real pipeline, not a simulated check. Every later stake that touches the vertical — [selection voice editing](29-selection-voice-editing.md), [LLM cleanup](18-llm-cleanup.md), a [second engine](15-second-engine.md) — arrives wanting exactly that proof, and none of them should build it again.
- Watch the scope boundary: the map excludes product-ization, so this is one person re-checking his own machine, not a support surface.
- **This ticket may not survive.** Inventorying the settings window produced a leaning against re-entering onboarding at all: keep it a one-time flow, and let settings *show* permission, device, and model state as ordinary rows. If a row can display the state and offer its one repair — which the degraded menu already proves is possible — then re-entry has nothing left to do and this stake dissolves into [Settings UI](16-settings-ui.md).
- The mock-ups are the test. If they can seat capability state without the window turning into a dashboard, close this and rule it out of scope. What would keep it alive is the other half of its question: proving a *new* capability works before trusting it with real text, which no settings row does.

## Resolution

Dissolved, as the ticket predicted. A code audit (2026-08-10) confirmed every recovery behavior it asked about shipped with the settings pane (commit `a6ae4b6`):

- All five degraded states derive from shared health state (`Degradation.swift`) and surface twice: the degraded menu bar with one repair item per state, and the pinned orange `RepairRow` section atop the settings pane (`SettingsPane.swift`) — the exact shape [Settings UI](16-settings-ui.md) decided, a full keyboard-cursor citizen.
- Repairs deep-link the correct System Settings privacy anchors; grants are re-detected live on app activation, menu open, and pane appearance (`reconcileAccessibility` auto-starts/stops the hotkey listener without relaunch).
- A deleted or failed model degrades into a re-download/retry repair; an interrupted consented download auto-resumes at launch.
- A vanished explicit microphone shows "not connected, using system default" and heals when the device returns.

Re-entering onboarding is dead: it stays a one-shot flow. The surviving fragment — a re-runnable full-pipeline try-it proof — is declined: the settings pane's live mic level meter proves capture, and using the app proves the rest. No breadcrumb needed.
