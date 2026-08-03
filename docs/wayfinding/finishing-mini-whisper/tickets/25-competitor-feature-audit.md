---
status: open
type: research
blocked-by: [8]
---

# Competitor feature audit: Wispr Flow, Aqua Voice, Monologue

## Question

The original feature survey ([ticket 01](01-dictation-app-feature-survey.md)) shaped the MVP cut and the post-MVP stakes, but it predates daily-driving MiniWhisper and the field has moved since. Audit Wispr Flow, Aqua Voice, and Monologue as they exist today — features, UX details, and the small touches that only show up in actual use — and report anything worth adding to MiniWhisper's map: new stakes, refinements to existing tickets, or deliberate exclusions worth recording.

## Notes

- The user has daily-driven all three on his personal machine; the audit should surface what the apps *do*, and the grilling that follows decides what MiniWhisper *adopts* — research collects and recommends, it doesn't decide.
- Compare against the existing stakes before proposing: history (11), paste-last (12), dictionary (13), warm-mic (14), settings UI (16), LLM cleanup (18), streaming (19), context capture (shipped, 20), audio ducking (21), iconography (23), sound design (24). A finding that refines an existing ticket belongs in that ticket's orbit, not a new stake.
- Areas the earlier survey under-weighted that deserve attention now: context-capture behavior in hostile targets (how does Wispr Flow handle Google Docs' canvas sink?), tone/formality adjustment, per-app behavior, command/edit modes, correction flows after a wrong transcription, and onboarding polish.
- The out-of-scope list on the map still stands (no cloud STT, no teams/sharing, one-person app); findings that collide with it should be noted as deliberate exclusions rather than silently dropped.
- Write findings as an asset (`assets/25-competitor-feature-audit.md`) per research-ticket convention and link it from the resolution.
