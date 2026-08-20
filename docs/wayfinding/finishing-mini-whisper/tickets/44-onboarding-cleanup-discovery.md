---
status: open
type: grilling
blocked-by: [18]
---

# Onboarding cleanup discovery: the feature nobody is told about

## Question

Cleanup ships disabled and unconfigured, and nothing in the product ever mentions it exists — the pane sits in the settings window, but the settings window is something a satisfied user may never open. Onboarding is the one moment the app has the user's full attention. What is the *minimum* honest mention that gets the feature discovered without burdening the flow?

Constraints already decided elsewhere:

- Onboarding is the app's only modal flow and is deliberately short — welcome, permissions, shortcut, model, try-it. A full cleanup configuration step (endpoint, key, model) is almost certainly too heavy for it, and the feature needs an endpoint the user may not have on hand at install time.
- Cleanup requires bandwidth-free consent framing anyway: transcripts leave the Mac only if the user turns it on, which is a privacy story worth telling at the same moment.
- [Onboarding capability recovery (30)](30-onboarding-capability-recovery.md) already shaped how onboarding hands off to settings for things finished later — this mention should ride that grammar rather than invent a new one.

Candidate shapes to grill: a single sentence + "set up later in Settings → Cleanup" on an existing page (try-it or the closing page); a dedicated skippable card; a one-time post-onboarding pill notice; a menu-bar affordance the first N days. Output: a decided placement and wording, folded into the onboarding flow's design.
