---
status: open
type: prototype
blocked-by: []
claimed: 2b
---

# Profiles mock-up: what the picker is, and how onboarding asks

## Question

The [profiles](47-cleanup-endpoint-profiles.md) + [presets](39-recommended-cleanup-providers.md) grilling settled what a profile is — a named full dictation stack, exactly one active, factory profiles overridable by delta, Custom the open one — and left two questions that prose cannot answer, because both are about how much room a thing takes and whether the eye compares or merely reads.

1. **The Profiles pane picker.** Rows with status badges, cards, a pop-up, tabs, a segmented control? It replaces the Cleanup pane, so it has to carry the picker, the selected profile's details, the rows every profile shares, and a model-storage section in one pane. It must show Active against Needs-setup, carry a one-line tradeoff per profile with no benchmark numbers in it, and still work at roughly five profiles — the lineup grows by Offline, Most accurate, and further providers.
2. **The onboarding profile step.** Profile choice becomes onboarding's first configuration step, branching to key entry (factory, not skippable) or straight through (Custom, keyless). The existing model-download page must grow from one model to a per-profile set.

Output: runnable variants of both, screenshotted light and dark, with the tradeoffs written down so the user picks.

## Artifact

[`spikes/profiles-mockup`](../../../../spikes/profiles-mockup/README.md) — a standalone AppKit/SwiftUI app, three pane pickers (`pane-a` rows, `pane-b` pop-up, `pane-c` cards), three welcome pages carrying the profile choice (`welcome-a` list, `welcome-b` cards, `welcome-c` pop-up), plus the key page and the grown download page. A `full` flag renders every screen at five profiles, which is where the variants stop agreeing. Screenshots in [`evidence/`](../../../../spikes/profiles-mockup/evidence/).

## Decided so far

- **Profile choice moves to the welcome page** (user, 2026-10-21). The welcome button is the download consent and the profile decides the model set, so choosing there lets the durable background download start on the first click instead of one page later. The welcome button names its download (one model, several, or none for a hosted engine); the rail drops its Profile step, and a factory profile adds a Cleanup Key step at the head of it. The mock-up's onboarding variants were rebuilt on the welcome page as list, cards, and pop-up.
- Open: which welcome variant, and which pane picker. Also for the design doc: what switching to a profile with a different model set does to a download that has already started.
