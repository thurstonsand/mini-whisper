# Sticky delivery

## Status

Accepted

## Decision Summary

A dictation delivers to the **target** it started in, wherever the user is when it finishes. The target is captured at the activation press: the frontmost app, its focused window, selected tabs, and element, and, when that element is a terminal surface, the exact tmux pane, nested multiplexers included, or else the Ghostty terminal. Delivery then takes the first route that applies: a pane or a Ghostty terminal is written to out of band; a GUI target that still has focus gets today's ⌘V; one that has lost it is delivered in the background, without ever changing which app is frontmost. A **submit** binding drives the same gestures and sends Return after the paste. A press while a dictation is polishing **detaches** it rather than skipping it: its cleanup keeps running and it delivers itself, so the user can dictate to the next agent without waiting. The tradeoff is that a dictation can now arrive minutes after it was spoken, which reverses the premise of [03](03-llm-cleanup.md) Decision 2; every route verifies its target is still the one captured before it writes anything, and falls back to the clipboard when it is not.

## Problem Statement / Background

Cleanup on the work machine is slow enough that waiting for it is the bottleneck: the user dictates a prompt to a coding agent, then sits on the pill until it pastes, because looking away means the paste lands wherever they looked. Most of those prompts go to agents running in tmux, and most of those in Agent Switchboard, whose Deck shows one agent at a time in a nested tmux client and swaps which one with `switch-client`. MiniWhisper must reach the right agent there with nothing Switchboard-specific in it.

Probes on 2026-10-31 (tmux 3.8, Ghostty, macOS 27) settled the mechanisms:

- tmux pane ids follow the process, not the screen. After `switch-client` moved a nested client to another session, `paste-buffer -t %0` still reached the original pane's process and nothing else.
- With `focus-events on` set before a client attaches, Ghostty reports focus per surface: of two clients in two tabs, only the visible tab's carries `focused` in `client_flags`, and an outer tmux forwards focus to a nested client in its active pane.
- A client's server is the peer address of its connected unix socket, readable with `proc_pidfdinfo`; a client that started its own server holds a socketpair instead, whose other end belongs to the server, beside its listening socket; its binary is `proc_pidpath`. Neither depends on argv, environment, or `PATH`, which the app does not share with the shell.
- `paste-buffer` writes to the pane even while it is in copy mode, and leaves the mode alone; a raw `\r` pasted after a bracketed paste submits in pi.
- A background app keeps its own focus, and `kAXFocusedAttribute` moves it without bringing the app forward. Focusing a field in a background Safari tab selects that tab; Chrome needs its captured tab `AXPress`ed first, about 10 ms.
- `kAXSelectedTextAttribute` inserts into an unfocused Cocoa field in a background app (TextEdit, 46 ms). Web content acknowledges the same write and ignores it.
- Keystrokes posted to a background browser's pid with `postToPid` land in its focused field while the user types into the frontmost app, with no crossover either way. Chromium takes one character per event; a line break is Shift-Return. 1969 characters took 3 s.
- A background Electron app (VS Code) drops posted keystrokes and AX writes alike while acknowledging both, and names no focused element; the field's own `AXFocused` still answers.
- Ghostty 1.4's scripting dictionary addresses a terminal by id from any tab or window: `input text … to terminal` pastes into it and `send key "enter"` presses Return, both answered in about 15 ms.
- `Foundation.Process` costs ~70 ms per spawn; `posix_spawn` costs ~5 ms, which keeps a two-level resolution near 15 ms.

## Goals

- A dictation lands in the field, window, or pane it started in, regardless of what is frontmost when it finishes.
- Nested tmux, including Agent Switchboard's Deck, resolves to the innermost pane with no app-specific code.
- A submit binding pastes and sends Return to the same target.
- The user can start the next dictation while the last one polishes, without giving up its cleanup.
- Deliveries to one target arrive in the order they were dictated.

## Non-Goals

- Multiplexers other than tmux. The route is a seam; herdr, WezTerm, kitty, and Zellij each expose a focused pane and a write-to-pane command and can join it later.
- Bringing any app forward. The user's frontmost app, window, and keyboard are never borrowed; a target that cannot be reached without them gets the clipboard.
- Background delivery into Electron apps. They drop input while inactive, so they deliver only while the user is still in them.
- Detaching a dictation that is still transcribing. A press during transcription restarts, as today.

## Exposed Shape

**The target.** Captured once per dictation, beside the Chromium prewarm, by the press that starts it:

```text
Target
  app       bundle id, name, pid           → History's target app, the pill's destination
  window    AX focused window, and its title
  tabs      selected tabs in the window's own chrome   → pressed again before focusing
  element   AX focused element, and the deepest focused text element under it
  pane      tmux binary, socket, pane id, pane pid, session, foreground command   (optional)
  terminal  Ghostty terminal id and foreground pid, when there is no pane         (optional)
```

The pane is resolved by walking the target app's descendant processes for tmux clients, grouping them by the server each is connected to, and asking each server (`show -gv focus-events ; list-clients`) which of them is focused. Exactly one focused client, on a server with `focus-events on`, names a pane; any other answer names none, and the dictation is a GUI target. When that pane's own descendants hold a tmux client, the walk recurses into its server.

**Routes.** In order:

1. **Pane.** The pane still exists with the same pane pid, and — for a submit — the same foreground command. `load-buffer` into a named buffer, `paste-buffer -d -p`, then, for a submit, a raw `\r` through a second buffer. The clipboard and focus are untouched.
2. **Ghostty terminal.** The terminal still exists and — for a submit — runs the same foreground process. `input text` to it by id, then `send key "enter"`, as raw Apple Events to the captured Ghostty's pid, so a second Ghostty can never answer. A capture never waits on the Automation consent alert: without consent there is no terminal, and the alert is raised beside the press for the next dictation.
3. **Focused.** The target's element is the focused element of the frontmost app. Today's ⌘V, then Return for a submit.
4. **Background.** The user is elsewhere. A native field takes the text through `kAXSelectedTextAttribute`, confirmed by reading the field back. Otherwise the target app's own focus is moved back to the field — selected tabs pressed, element focused — and the text is typed to its pid in chunks of 24 characters. Each chunk waits for the field's length to show it before the next goes out, and each checks first that the field still has the app's focus; a user who comes back to the field changes nothing. A chunk that changes nothing ends the typing: from the first, the app ignored the keys; later, it is unconfirmed; both copy. Only a field that grew by exactly what was typed is delivered; then Return follows for a submit, if the field still has focus, and the app's own focus is put back where it was unless the user is in the app. Anything short of that leaves the app's focus on the field, where any keys still queued belong. Terminals without a pane or a Ghostty terminal are never typed into: a typed line break is a Return there. A single-line field gets its line breaks as spaces. A user who is in the target app, but away from the field, keeps their focus and gets the clipboard.

A target whose pane died, or whose foreground command changed under a submit, copies to the clipboard and says so. Field context is still read late, as [03](03-llm-cleanup.md) Decision 4 has it, but from the captured element rather than whatever is frontmost.

**Submit.** Return pressed while a recording is live ends it and submits; the event tap swallows its press, repeats, and release, so the field never sees a Return of its own. The gesture machine arms the tap only for a hold, a second press, or a latch, and Return is untouched everywhere else. A third command in `settings.json`'s `bindings`, `submit`, empty by default, does the same from the activation gestures. It drives the activation gestures; whichever press ends the recording decides whether it submits: the held chord for a hold, the closing tap for a latch. A lone submit tap while the pill's dictation is polishing marks it to submit and leaves its cleanup running; a submit hold detaches it like any other press. The Settings row reads "Activate and submit".

**Detach.** A dictation with a transcript is never dropped by the next one. The press that starts a new recording moves the pill's dictation to the background, where its cleanup and delivery continue under its own generation. If that press turns out to be a lone tap, the detached dictation is skipped instead — cleanup cancelled, delivered as heard — which keeps tap-to-skip. A background dictation's delivery is silent while another dictation is in flight; its notices and cue play only when nothing is.

**Ordering.** A dictation ready to deliver waits while an earlier one bound for the same target has not yet delivered.

**The pill.** While a dictation transcribes or polishes, the pill names its destination — the app, then the tmux session or the window title — once the user is somewhere other than the target, checked twice a second. A user still at the target sees the pill as it has always looked.

**Escape.** Escape cancels a polishing dictation only when its target is still where the user is, judged as delivery judges it: the same pane, or focus on or inside the captured element. Escape in another app or another agent leaves it alone, and the activation key still means skip.

**Refusal.** A press that cannot start a recording — the engine not ready, a key missing — detaches nothing. The dictation stays in the pill, and the rest of the press means nothing.

## Design Decisions

### 1. Capture at the press, read at delivery

The press is the only moment that names the user's intent: by release the user may already be looking elsewhere, and by delivery that is expected. The field's text is different — it is read as late as possible because it is the one fact the user keeps changing — so the capture keeps the element and the late read asks it.

### 2. The pane route wins even when the terminal is frontmost

In the Deck, Ghostty never leaves the front while the user switches agents, so "frontmost and focused" would paste into the wrong agent. Any target with a pane goes through the pane.

### 3. Focus flags, not activity

With no unique focused client there is no pane. Choosing the most recently active client would pick a background tab whenever the focused surface is a plain shell. A server without `focus-events` marks every client focused forever, so it is not trusted at all.

### 4. Never move the user's focus

A round trip that brings the target forward and hands focus back reaches every GUI app, but flashes the target over whatever the user is doing and steals their keystrokes while it runs. Every app keeps its own focus whether or not it is frontmost, and that focus can be moved without the user's. Background delivery works inside the target app only; where the app will not take input in the background, the clipboard is the honest answer.

### 5. Typed input proves itself

A posted keystroke is acknowledged whether or not the app acts on it, so the field's length is the witness. Each chunk waits for the field to show the last, so the app never holds a backlog: focus that leaves the field is noticed between chunks, and nothing is left queued to land after the app's focus is handed back.

### 6. Detach generalizes skip

Skipped tails already lived beside the pill's dictation, keyed by generation, owed a paste and an entry. Detach makes every leg of a dictation — field capture, cleanup, delivery, the History write — answer to its own generation, so a detached dictation is the same record with its cleanup still running. Deferring the skip to the end of the tap costs the tap ~0.5 s and keeps the documented grammar.

### 7. Synthetic events carry a marker

The app's own ⌘V and Return pass through its own event tap, where an untagged one reads as a foreign key and discards a recording started within the accidental-input window. Every synthesized event carries a marker in `eventSourceUserData`, and the tap passes marked events through unseen.

## Edge Cases & Failure Modes

- **Pane closed or server gone:** copied, notice, History records `targetGone`.
- **Agent exited back to its shell under a submit:** copied rather than run as a shell command.
- **Target app quit:** copied.
- **Field cannot take focus again in its app** (closed tab, editor tab switched in an Electron app): the app's focus restored, copied, `targetUnreachable`.
- **App ignores background input** (Electron): copied, `targetUnreachable`.
- **User comes back to the target mid-typing:** typing carries on into the field. Moving the app's focus off the field stops it: copied, `interrupted`; what was typed stays.
- **Typed length does not match** (an emoji in Chrome's rich-text editors, which its accessibility text omits): copied, `unconfirmed`.
- **User in the target app, away from the field:** copied, `targetInUse`.
- **Ghostty Automation not granted:** no terminal is captured; a delivery while the user is away copies, `targetUnreachable`. The same holds for any terminal without a pane.
- **Secure input on:** copied, as today.
- **Two dictations to one pane, the later one cleaned first:** the later one waits.
- **Escape in the target while it polishes:** cancelled and archived, as today.

## Alternatives

### Deliver at the frontmost field, as before

- **Status:** Rejected
- **Decision:** it is the behaviour the user is trying to stop waiting on.

### App-specific integration with Agent Switchboard

- **Status:** Rejected
- **Decision:** the process tree and tmux's own focus flags reach the same pane, and keep working for any nested tmux.
