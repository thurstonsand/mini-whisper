---
status: closed
type: research
claimed: subagent:ax-context-research
blocked-by: []
---

# AX context beyond the focused field

## Resolution

Research is recorded in [the AX context findings](../assets/36-ax-context-beyond-the-field.md). AX can inspect exposed text beyond the focused field, including another window of a running app, but tree completeness and semantics are target-specific. Terminal buffers are grids or absent and `AXTitle` is configurable metadata, not a foreground-program contract; native/Chromium reads need bounded, focused-window capability probes; cross-app scanning is technically reachable under the existing grant but carries substantial privacy and latency cost. The asset recommends rather than decides a later bounded visible-window enrichment.

## Question

What can the Accessibility API read beyond the focused element, per app class — and how reliably? The cleanup pass ([LLM cleanup](18-llm-cleanup.md)) ships on today's focused-field capture; this ticket scouts the enrichment that would follow. Specifically:

1. **Terminals**: can the visible screen buffer be read via AX (Terminal.app, iTerm2, Ghostty, kitty, Alacritty)? What do their window/tab titles (AXTitle) reveal about the foreground program — nvim, tmux, a TUI — and how conventional is that signal?
2. **Native apps**: what does walking the AX tree of the focused *window* (not just the focused element) yield — sibling text, labels, document text outside the caret's element?
3. **Chromium/Electron**: does the existing `ChromiumAccessibility` enablement extend to whole-window reads, or only the focused field?
4. **Other windows / other apps**: is out-of-focus-window text reachable at all with the Accessibility grant we hold, and at what cost?

Method constraints: this runs in the background on the user's live machine — never foreground, launch, or activate apps, and never steal focus; probe only what is already running, plus documentation, prior art (Hex, VoiceInk, Whispering), and Apple's AX references. Findings to `../assets/36-ax-context-beyond-the-field.md`, cited; recommend, don't decide.
