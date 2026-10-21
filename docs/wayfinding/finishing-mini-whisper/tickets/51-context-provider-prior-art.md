---
status: closed
type: research
blocked-by: []
claimed: gpt-5.6-terra subagent
---

# How does anything else route context to a system-wide process?

## Question

[The context provider seam](50-context-provider-sdk.md) has one hard problem underneath every design for it: at the end of a dictation MiniWhisper knows the frontmost application, and it needs to reach the right *provider process* for that context. Push and pull share the problem — a pushed state still has to be matched to whatever is frontmost when the dictation lands. The motivating case makes it worse: the frontmost app is a terminal emulator, and the provider is an agent process running in one pane of it, several levels below the window that holds focus.

Find out what is possible and what already exists, from primary sources:

- Programs that run system-wide on macOS and take context from other programs — launchers, automation tools, text expanders, and the dictation apps themselves. How does each one identify who is talking to it?
- Terminal-hosted processes advertising themselves outward. OSC escape sequences are the closest thing to a standard here (OSC 7, OSC 133, iTerm2's own codes) and are the first thing to read.
- What macOS actually lets an app learn about the frontmost window, its owning process, and that process's descendants, given the app already holds Accessibility.
- Local transports between arbitrary user processes — XPC, Unix sockets, local HTTP, distributed notifications, URL schemes, watched files — and for each, whether the receiver can verify who connected.
- Any existing protocol worth adopting instead of inventing one.

A well-supported negative is a real finding: if nothing does this, the seam is being designed from scratch and should know it.

## Resolution

[Context-provider routing prior art](../research/context-provider-prior-art.md) found no generic macOS join from frontmost terminal window to its active pane or child process. A terminal-specific focus broker, a host-app window integration, or a visible explicit active-provider lease are the viable routing shapes; Unix-domain sockets or XPC can securely carry the selected provider’s request, but cannot choose it. The research records the primary-source evidence and dead ends.
