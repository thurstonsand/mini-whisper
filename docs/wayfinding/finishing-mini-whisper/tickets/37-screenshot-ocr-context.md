---
status: closed
type: research
claimed: subagent:ocr-context-research
blocked-by: []
---

# Screenshot/OCR context capture

## Question

The Aqua-style alternative to AX context: screenshot the screen (or the focused window), OCR it, and feed the recovered text to the cleanup pass as context. Scouting only — [LLM cleanup](18-llm-cleanup.md) ships without it. Establish:

1. **Mechanism**: ScreenCaptureKit (or the sanctioned modern API) for a one-shot capture of the focused window vs. full screen; Vision framework OCR (`VNRecognizeTextRequest` / the macOS 26-era successor) — accuracy on rendered UI text, and latency for one frame on Apple silicon.
2. **Permission cost**: Screen Recording is a new TCC grant with its own scary prompt and per-channel state; how it degrades, how apps detect it, whether a one-shot capture API with lighter permission exists now.
3. **Privacy contract**: what it means that screen pixels (potentially containing secrets unrelated to dictation) transit to a network endpoint — what surveyed apps (Aqua Voice foremost) disclose and gate.
4. **Coverage vs. AX**: which gaps this closes that AX cannot (canvas-rendered apps like Google Docs, terminals if AX fails there) — coordinate on paper with [AX context beyond the focused field](36-ax-context-beyond-the-field.md), which runs concurrently; do not probe the same live apps interactively.

Method constraints: background research on the user's live machine — never foreground, launch, or activate apps; docs, prior art, and at most self-contained capture probes that touch nothing user-visible. Findings to `../assets/37-screenshot-ocr-context.md`, cited; recommend, don't decide.

## Resolution

Findings and a recommendation-only future-enrichment shape are in [Screenshot/OCR context capture](../assets/37-screenshot-ocr-context.md). ScreenCaptureKit/Vision make locally OCR'd focused-region hints credible, especially for canvas editors, but automatic capture needs a separate Screen Recording/privacy contract; it remains outside cleanup's first release.
