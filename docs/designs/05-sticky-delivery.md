# Sticky delivery

## Status

Accepted

## Decision Summary

A dictation delivers to the **target** it started in, wherever the user is when it finishes. The target is captured at the activation press: the frontmost app, its focused window and element, and, when that element is a terminal surface hosting a multiplexer, the exact pane, nested multiplexers included. Delivery then takes the first route that applies: a pane is written to out of band, with no focus change and no clipboard; a GUI target that still has focus gets today's ⌘V; one that has lost it gets a focus round trip that brings it back, pastes, and restores whatever the user was in. A **submit** binding drives the same gestures and sends Return after the paste. A press while a dictation is polishing **detaches** it rather than skipping it: its cleanup keeps running and it delivers itself, so the user can dictate to the next agent without waiting. The tradeoff is that a dictation can now arrive minutes after it was spoken, which reverses the premise of [03](03-llm-cleanup.md) Decision 2; every route verifies its target is still the one captured before it writes anything, and falls back to the clipboard when it is not.

## Problem Statement / Background

Cleanup on the work machine is slow enough that waiting for it is the bottleneck: the user dictates a prompt to a coding agent, then sits on the pill until it pastes, because looking away means the paste lands wherever they looked. Most of those prompts go to agents running in tmux, and most of those in Agent Switchboard, whose Deck shows one agent at a time in a nested tmux client and swaps which one with `switch-client`. MiniWhisper must reach the right agent there with nothing Switchboard-specific in it.

Probes on 2026-10-31 (tmux 3.8, Ghostty, macOS 27) settled the mechanisms:

- tmux pane ids follow the process, not the screen. After `switch-client` moved a nested client to another session, `paste-buffer -t %0` still reached the original pane's process and nothing else.
- With `focus-events on` set before a client attaches, Ghostty reports focus per surface: of two clients in two tabs, only the visible tab's carries `focused` in `client_flags`, and an outer tmux forwards focus to a nested client in its active pane.
- A client's server is the peer address of its connected unix socket, readable with `proc_pidfdinfo`; its binary is `proc_pidpath`. Neither depends on argv, environment, or `PATH`, which the app does not share with the shell.
- `paste-buffer` writes to the pane even while it is in copy mode, and leaves the mode alone; a raw `\r` pasted after a bracketed paste submits in pi.
- An AX round trip — `kAXFrontmostAttribute` on the app, `AXRaise` on the captured window, `kAXFocusedAttribute` on the captured element — brings a background Ghostty tab forward, takes a paste and Return, and restores a different app, in about 370 ms.
- `Foundation.Process` costs ~70 ms per spawn; `posix_spawn` costs ~5 ms, which keeps a two-level resolution near 15 ms.

## Goals

- A dictation lands in the field, window, or pane it started in, regardless of what is frontmost when it finishes.
- Nested tmux, including Agent Switchboard's Deck, resolves to the innermost pane with no app-specific code.
- A submit binding pastes and sends Return to the same target.
- The user can start the next dictation while the last one polishes, without giving up its cleanup.
- Deliveries to one target arrive in the order they were dictated.

## Non-Goals

- Multiplexers other than tmux. The route is a seam; herdr, WezTerm, kitty, and Zellij each expose a focused pane and a write-to-pane command and can join it later.
- Holding or replaying the user's keystrokes during a focus round trip. Keys typed in its ~0.4 s window reach the target.
- Background insertion into GUI fields through `kAXSelectedTextAttribute`. One mechanism, the round trip, covers every GUI target and can send Return.
- Detaching a dictation that is still transcribing. A press during transcription restarts, as today.

## Exposed Shape

**The target.** Captured once per dictation, beside the Chromium prewarm, by the press that starts it:

```text
Target
  app      bundle id, name, pid           → History's target app, the round trip
  window   AX focused window              → raised by the round trip
  element  AX focused element, and the deepest focused text element under it
  pane     tmux binary, socket, pane id, pane pid, foreground command   (optional)
```

The pane is resolved by walking the target app's descendant processes for tmux clients, grouping them by the server each is connected to, and asking each server (`show -gv focus-events ; list-clients`) which of them is focused. Exactly one focused client, on a server with `focus-events on`, names a pane; any other answer names none, and the dictation is a GUI target. When that pane's own descendants hold a tmux client, the walk recurses into its server.

**Routes.** In order:

1. **Pane.** The pane still exists with the same pane pid, and — for a submit — the same foreground command. `load-buffer` into a named buffer, `paste-buffer -d -p`, then, for a submit, a raw `\r` through a second buffer. The clipboard and focus are untouched.
2. **Focused.** The target's element is the focused element of the frontmost app. Today's ⌘V, then Return for a submit.
3. **Round trip.** Remember the frontmost app, window, and element; bring the target's back and verify its element has focus; ⌘V, Return for a submit; restore what was remembered. Verification failure restores and copies instead. While focus is borrowed, a press or an Escape is judged against the remembered spot, not the app the round trip brought forward.

A target whose pane died, or whose foreground command changed under a submit, copies to the clipboard and says so. Field context is still read late, as [03](03-llm-cleanup.md) Decision 4 has it, but from the captured element rather than whatever is frontmost.

**Submit.** A third command in `settings.json`'s `bindings`, `submit`, empty by default. It drives the activation gestures; whichever press ends the recording decides whether it submits: the held chord for a hold, the closing tap for a latch. A lone submit tap while the pill's dictation is polishing marks it to submit and leaves its cleanup running; a submit hold detaches it like any other press. The Settings row reads "Activate and submit".

**Detach.** A dictation with a transcript is never dropped by the next one. The press that starts a new recording moves the pill's dictation to the background, where its cleanup and delivery continue under its own generation. If that press turns out to be a lone tap, the detached dictation is skipped instead — cleanup cancelled, delivered as heard — which keeps tap-to-skip. A background dictation's delivery is silent while another dictation is in flight; its notices and cue play only when nothing is.

**Ordering.** A dictation ready to deliver waits while an earlier one bound for the same target has not yet delivered.

**Escape.** Escape cancels a polishing dictation only when its target is still where the user is, judged as delivery judges it: the same pane, or focus on or inside the captured element. Escape in another app or another agent leaves it alone, and the activation key still means skip.

**Refusal.** A press that cannot start a recording — the engine not ready, a key missing — detaches nothing. The dictation stays in the pill, and the rest of the press means nothing.

## Design Decisions

### 1. Capture at the press, read at delivery

The press is the only moment that names the user's intent: by release the user may already be looking elsewhere, and by delivery that is expected. The field's text is different — it is read as late as possible because it is the one fact the user keeps changing — so the capture keeps the element and the late read asks it.

### 2. The pane route wins even when the terminal is frontmost

In the Deck, Ghostty never leaves the front while the user switches agents, so "frontmost and focused" would paste into the wrong agent. Any target with a pane goes through the pane.

### 3. Focus flags, not activity

With no unique focused client there is no pane. Choosing the most recently active client would pick a background tab whenever the focused surface is a plain shell. A server without `focus-events` marks every client focused forever, so it is not trusted at all.

### 4. One round trip for every GUI target

AX insertion reaches only some Cocoa fields and cannot submit. The round trip reaches anything AX can focus, including Ghostty tabs and windows, and its verification step turns every case it cannot reach into an honest clipboard fallback.

### 5. Detach generalizes skip

Skipped tails already lived beside the pill's dictation, keyed by generation, owed a paste and an entry. Detach makes every leg of a dictation — field capture, cleanup, delivery, the History write — answer to its own generation, so a detached dictation is the same record with its cleanup still running. Deferring the skip to the end of the tap costs the tap ~0.5 s and keeps the documented grammar.

### 6. Synthetic events carry a marker

The app's own ⌘V and Return pass through its own event tap, where an untagged one reads as a foreign key and discards a recording started within the accidental-input window. Every synthesized event carries a marker in `eventSourceUserData`, and the tap passes marked events through unseen.

## Edge Cases & Failure Modes

- **Pane closed or server gone:** copied, notice, History records `targetGone`.
- **Agent exited back to its shell under a submit:** copied rather than run as a shell command.
- **Target app quit:** copied.
- **Round trip cannot focus the element:** previous focus restored, copied.
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
