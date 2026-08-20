---
status: open
type: grilling
blocked-by: [18, 43]
---

# Cleanup tone: formality levels, and maybe per-app auto-detection

## Question

Superwhisper ships Tone settings and per-mode formality (casual for messages, formal for client email, technical for code prompts), with modes auto-activating per app. MiniWhisper's cleanup pass has one register: the conservative editor. Additional instructions can shift it manually today, but that's one global dial.

What's worth adopting?

- **Formality levels**: a small enumerated tone control (e.g. as-spoken / neutral / formal) implemented as prompt fragments layered over the built-in prompt — same mechanism as additional instructions, but curated and named. Must not violate the prompt invariants (never invent content; instructions refine style only).
- **Per-app auto-detection**: the pipeline already captures the target bundle ID and sends it to the model as context. The stronger version — user-configured per-app tone rules (Slack → casual, Mail → formal) — reopens a fence: "per-app modes" was ruled out at the MVP prune, so adopting it needs an explicit decision that the fence moves for cleanup only.
- **Sequencing**: tone fragments are prompt text, so the ticket-43 corpus should judge them; grill after the corpus exists.

Output: a decided tone surface (or a decision to decline), folded into the cleanup design.
