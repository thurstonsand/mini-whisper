---
status: open
type: prototype
blocked-by: [8]
---

# Sound design: cues that belong to this app

## Question

`SoundsClient` maps the four cues — record start, commit, cancel, error — onto macOS's built-in alert sounds (Tink, Pop, Funk, Basso). They are placeholders: borrowed, shared with every other app on the system, and tuned as alerts rather than as the fast confirmations these are. What should the four cues actually sound like, where do the assets come from (authored, licensed, sampled from prior art), and how are they bundled and played — `NSSound` on a bundled resource, or something with lower latency given record-start fires on the critical path? Does the set stay at four, or do latch-engage and silence-rejection deserve their own voices instead of sharing?

## Notes

- The settings inventory raised the ambition: sounds become **per-cue selectable**, not one global on/off. So this ticket owns more than replacing four borrowed alert sounds — it owns whether a cue is a choice, whether there are sets or individual picks, and whether silencing one cue is possible without silencing all four.
- That has a shape consequence worth deciding here rather than in the window: `soundsEnabled: Bool` in `settings.json` becomes a per-cue structure, which is a settings-file migration, however small.
- Requested alongside [Iconography](23-iconography.md); same problem, different sense — borrowed system assets standing in for the app's own identity. Kept separate because the crafts and the assets don't overlap.
- Hex is the architectural north star and ships its own cue set; worth listening to before authoring anything.
- Record-start latency is user-visible: the cue is the acknowledgement that the hotkey registered. Measure, don't assume `NSSound` is fast enough.
- Cues must not leak into the recording — check whether the mic picks up the start cue through the speakers.
- Licensing has to survive the work allowlist: anything bundled ships in the installed artifact.
- Volume and mix sit next to [Audio ducking](21-audio-ducking.md); a cue that plays while ducking engages should not fight it.
