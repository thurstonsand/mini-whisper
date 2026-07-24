---
status: closed
claimed: charting-session-foreground
type: research
blocked-by: []
---

# Dictation app feature survey

## Question

What features do the good dictation apps ship, and which are worth stealing? Survey the field — Hex, VoiceInk, Superwhisper, MacWhisper, Whispering, Aqua Voice, Wispr Flow (the last two closed-source; survey from docs/marketing) and anything else reputable — and produce a feature matrix as a markdown asset at `../assets/01-dictation-app-feature-survey.md`. Open-source repos to read (librarian): kitlangton/Hex, Beingpax/VoiceInk, epicenter-md/epicenter (Whispering). For each feature: what it does, who does it best, implementation notes if the project is open source, and whether it fits our dependency allowlist. The user is a happy Aqua Voice / Wispr Flow user, so pay particular attention to what makes those two feel good. This feeds the pruning session — collect, don't decide.

## Resolution

Survey complete: [feature matrix and per-app notes](../assets/01-dictation-app-feature-survey.md). Seven apps covered — Hex, VoiceInk, and Whispering read at source level; Wispr Flow, Aqua Voice, Superwhisper, and MacWhisper from docs/marketing as taste references. Headlines: Hex's `HotKeyProcessor` is the only open-source implementation of side-specific modifiers plus double-tap latch — direct prior art for our fixed activation UX. VoiceInk (whisper.cpp, Swift, GPL) proves out nearly our whole stack, including local-model import, VAD-by-default, hybrid hold/latch semantics, and ownership-checked clipboard restore. Whispering contributes the cleanest pipeline staging and two anti-hallucination tricks (short-audio padding, honest paste-vs-fallback reporting). The asset ends with a gravity-grouped candidate list and a four-point "what makes Aqua/Wispr feel good" rubric for the pruning session to decide against.
