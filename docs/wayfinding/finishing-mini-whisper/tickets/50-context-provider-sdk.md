---
status: open
type: prototype
blocked-by: [51]
---

# A context provider seam: let other programs tell MiniWhisper what the user is looking at

## Question

Cleanup reads exactly one thing about the world: the focused field, through per-app AX ([context capture](20-context-capture.md)), joined by `FOCUSED_TEXT_CONTEXT` and `TARGET_BUNDLE_ID` in the prompt. Everything else the user can see is invisible to it. When the dictation is aimed at a coding agent, the field holds an empty prompt box and the entire conversation that would disambiguate the sentence is three inches above the caret, in a program that knows exactly what it is.

The proposal is a seam: a documented way for another program — a pi extension, a shell script, an editor plugin — to hand MiniWhisper context for the dictation about to happen. The pi extension supplies the current prompt buffer and whatever the agent has on screen; MiniWhisper stages it in the cleanup prompt beside the field context it already has.

## The routing problem is the ticket (2026-08-21, user)

Pull is the shape, because the app is the only party that knows when context is wanted: a provider has no idea a dictation is happening. Push would mean the app keeping per-process state and matching it to whatever is frontmost at delivery time — and that matching is the same problem pull has, arriving from the other direction. Neither shape escapes it:

> you do know at least what the frontmost app is, but how do you translate that to being able to pull information from the right process?

The frontmost application is a terminal emulator. The provider is an agent running in one pane of one window of it, possibly one of several. A bundle identifier does not reach it, a PID of the emulator does not reach it, and the AX tree of a terminal is [documented as unsuitable](20-context-capture.md) for reading content. So this is a spike before it is a design: find out what is *possible*, then decide what to build. [Prior art research](51-context-provider-prior-art.md) runs first — anything that already solves "the process inside the pane tells the outside world what it is" is worth more than a clever answer invented here.

The [prior art is in](51-context-provider-prior-art.md), and it says routing cannot be inferred: no documented macOS path runs from a terminal window to the pane's child process, so the association has to be *declared* by something that already knows it. Three shapes survive — a terminal-owned focus broker, a host-app plugin sharing window identity, and an explicit user-granted lease.

The research's one negative did not hold. Ghostty ships an sdef, and `application → front window → selected tab → focused terminal → id` answers "which pane has focus" in one `osascript` line on stable 1.3.1 — [verified live](../research/context-provider-prior-art.md#addendum-2026-08-21-ghosttys-negative-is-wrong). The pane's tty is missing until tip (0.4.0) adds it, and `ghosttykitd` already bridges that gap with tty↔terminal-id bindings claimed at spawn. So the broker for the motivating case exists, is daily-driven, and belongs to the same author as this app.

What has to be decided, now that the spike has said what can be built:

- **Which of the three shapes ships first.** The broker is available for Ghostty rather than blocked on upstream, which is the opposite of what the research first concluded — so the question is whether MiniWhisper queries Ghostty's focused terminal directly or goes through ghosttykit, and what a provider registry keyed by terminal id costs that project.
- **How a provider is addressed.** The whole ticket. Whatever the answer is, it has to survive a terminal emulator in front and an agent process below it.
- **The deadline.** Pull puts a foreign process on the critical path: the dictation cannot enter cleanup until the answer arrives or the wait expires. Cleanup already lives under a give-up timer and a never-fail-a-dictation contract; the provider inherits both, and the budget it gets is a number this ticket has to name.
- **The transport.** A local HTTP endpoint, a Unix socket, an XPC service, a file the provider writes, a URL scheme. The provider is an arbitrary program on the same Mac, and MiniWhisper is sandbox-free but distributed through a work allowlist, so "what may talk to it" is a security question and not only an ergonomic one.
- **What a provider may say.** Free text, or named fields the prompt already understands? Everything a provider sends lands inside a prompt whose first rule is that tagged content is source material and never instructions — a hostile or careless provider is a prompt-injection vector aimed at text that gets typed into the user's editor. Bounding size, tagging provenance, and whether a provider can be trusted per-bundle-ID all belong here.
- **Whether the user can see it.** A dictation whose transcript was shaped by an invisible third program needs some accounting: the pill, the history entry, or both. History already stores field context per entry; provider context would want the same treatment or it is unauditable.
- **Registration and failure.** How a provider announces itself, what happens when it is slow or dead, and the rule that no provider may ever fail a dictation — the same contract cleanup already lives under.

**Screen content is out of scope here and stays where it was decided.** [Ticket 37](37-screenshot-ocr-context.md) settled that MiniWhisper does not read the screen: local Vision OCR of a small focused rect is viable but only behind separate default-off Screen Recording consent, and nothing about it ships. A provider that happens to know what is on its own screen is a different thing — it is that program volunteering what it already has, with no new permission for MiniWhisper — and that difference is exactly why this seam is worth designing rather than reopening 37.

Output: a decided provider contract — shape, transport, payload, trust boundary, and visibility — small enough that the first provider is a pi extension somebody writes in an afternoon.
