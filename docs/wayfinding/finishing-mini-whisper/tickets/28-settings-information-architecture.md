---
status: closed
claimed: subagent:gpt-5.6-terra
type: research
blocked-by: []
---

# Settings information architecture: how other apps organize configuration

## Question

[Settings UI](16-settings-ui.md) was promoted to next, and it now owns the app's first window rather than a preferences sheet. Before that grilling opens, establish how comparable apps *organize* configuration: what panes exist, what lives in each, where history sits relative to settings, and which options exist at all. The [competitor audit](../assets/25-competitor-feature-audit.md) covered features; this covers arrangement.

## Notes

- Survey Wispr Flow, Aqua Voice, Monologue, [Hex](https://github.com/kitlangton/Hex), Superwhisper, and MacWhisper. Hex is the architectural north star and its source is readable — weight it accordingly, and read the actual settings implementation rather than screenshots.
- The question is shape, not feature count: how many panes, what the top-level split is, whether history is a pane or a separate window, whether the window is a `Settings` scene or a plain window, whether a menu-bar app opens it from the menu or the Dock.
- Note specifically where each app puts the things MiniWhisper already has: hotkey binding, sounds toggle, launch at login, input device, model state. Today these are split across the menu and a hand-edited JSON file.
- Note which options exist that MiniWhisper has never considered — the point of a survey is the option you didn't know to want.
- macOS platform convention matters as much as competitor practice: what does a modern SwiftUI menu-bar app's settings window look like in 2026, and what do the HIG and `Settings` scene actually give you for free.
- Retention presets and the audio toggle from [History](11-history.md)'s *Decisions carried* need a home in whatever shape this recommends. So does a keybind recorder.
- Write findings as an asset (`assets/28-settings-information-architecture.md`) per research-ticket convention and link it from the resolution. Collect and recommend; the grilling decides.

## Resolution

Findings: [Settings information architecture: how comparable apps organize configuration](../assets/28-settings-information-architecture.md).

The survey recommends, for [Settings UI](16-settings-ui.md) to decide, one resizable application window with a stable sidebar: **History**, **Dictation**, **Model**, and **General**. It takes Hex’s TCA/AppKit-owned one-window shape and makes History a sibling content destination rather than a settings tab, because MiniWhisper has already settled recovery as History’s primary job. The tradeoff is a larger first window and early navigation commitments; it avoids squeezing recovery/audio evidence into preferences or creating two window systems. The asset records placement options, source-level Hex precedent, platform mechanics, evidence gaps, and unstaked options including microphone fallback, a re-enterable microphone proof, explicit storage policy, settings deep links, and capability recovery.
