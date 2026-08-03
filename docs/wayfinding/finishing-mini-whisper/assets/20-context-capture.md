# Context capture probe

Research date: 2026-08-02. This is a disposable field probe for ticket 20, not a product decision. Its source is [`spikes/context-capture/`](../../../../spikes/context-capture/).

## Recommendation

Keep the existing **Paste Access** onboarding step. Its `AXIsProcessTrustedWithOptions` request grants `kTCCServiceAccessibility`, which is the Accessibility API trust required to obtain the focused element and read its attributes. It must not become a second ask. The existing app has that exact approved TCC service on the validation host.

Do not use `AXUIElementCreateSystemWide()` to resolve focus: its focused-element read fails with `kAXErrorCannotComplete` on macOS 26.5.2 even for a trusted process. Resolve `NSWorkspace.frontmostApplication` → `AXUIElementCreateApplication(pid)` → `kAXFocusedUIElementAttribute` instead — this succeeded against every target below, and matches what delivery needs anyway (the frontmost app is the paste target). Two mechanics are mandatory: clamp the requested window to `kAXNumberOfCharacters` (targets reject past-end ranges with `AXError -25201` instead of clamping), and when the focused element is a valueless container (Chromium returns `AXWebArea`), descend to the deepest descendant with `AXFocused = true` — that node carries the real value and caret.

On a successful capture, request one bounded fragment: the selected range plus **256 UTF-16 code units before and after it**. Preserve the three portions—`before`, `selected`, and `after`—rather than a full `AXValue`. That is enough preceding punctuation and local whitespace for the first consumers (spacing and sentence capitalization), gives ticket 18 useful editing context, and keeps the normal zero-length-selection request to 512 code units. The selection itself needs an explicit cap before implementation: a “selected range plus N” request is not actually bounded when a user selects a 100-page document. Recommend a 1,024-UTF-16-unit selection cap with `selectionWasTruncated`; immediate delivery can still use `before`, while an LLM must not be told that a truncated selection is complete.

If capture is unavailable, deliver blind exactly as Phase 5 does. Return a classified unavailable outcome so the pill can honestly say that the current app/field does not expose context. Do not infer from a previous MiniWhisper transcript.

## Grant verdict

**No new permission ask is needed.** Apple defines `AXIsProcessTrusted()` and `AXIsProcessTrustedWithOptions` as checking whether the current process is a trusted Accessibility client, and exposes `AXUIElementCopyAttributeValue` / parameterized attribute reads in the same API family.[^apple-trust] Phase 7 already uses the prompting form for Paste Access, specifically because it creates the Accessibility row and tracks revocation live.[^mvp-phase-5]

Read-only inspection of `/Library/Application Support/com.apple.TCC/TCC.db` on the validation host found:

| Service                    | Client                         | `auth_value` | Interpretation                                                |
| -------------------------- | ------------------------------ | ------------ | ------------------------------------------------------------- |
| `kTCCServiceAccessibility` | `com.thurstonsand.MiniWhisper` | `2`          | Installed MiniWhisper has the approved Accessibility service. |
| `kTCCServiceAccessibility` | `com.mitchellh.ghostty`        | `2`          | Ghostty has the same approved service.                        |
| `kTCCServiceAccessibility` | `com.apple.Terminal`           | `0`          | Terminal is not approved.                                     |
| `kTCCServicePostEvent`     | `com.mitchellh.ghostty`        | `2`          | Separate synthetic-event service, as Phase 5 found.           |

This establishes the service equivalence and the installed app's actual grant, and the probe subsequently completed real field reads across the whole target matrix under Ghostty-attributed trust. A shipping-bundle focused-field smoke test remains mandatory: no read has yet been made as the MiniWhisper process itself. Do not add an onboarding query before the existing Input Monitoring request; Phase 7 established that doing so can suppress the Keystroke Receiving dialog.[^mvp-phase-7]

## Probe

`spikes/context-capture/ContextCaptureProbe.swift` is a standalone Swift CLI, deliberately outside the app target. It tries `AXUIElementCreateSystemWide()`'s `AXFocusedUIElement`, falls back to the frontmost-app route when that fails, and logs ordinary and parameterized attributes, role/subrole/PID, `AXValue`, selected text/range, character count, `AXStringForRange`, and the insertion-point line (`AXLineForIndex` → `AXRangeForLine` → `AXStringForRange`). Every request is timed independently.

```sh
swiftc -warnings-as-errors -framework ApplicationServices -framework Foundation \
  spikes/context-capture/ContextCaptureProbe.swift -o .build/context-capture-probe
.build/context-capture-probe 256 --delay=5
```

`--delay=5` lets an operator refocus the target after submitting the command. `--activate-chromium` attempts `AXManualAccessibility` then `AXEnhancedUserInterface` on the frontmost app **before** the focused-element read (activation after the read is useless: a focused read against an inactive Chromium tree returns `noValue`), and logs both AX results. When the system-wide read fails the probe falls back to the frontmost-app route and clamps bounded ranges to the reported character count.

### Observed harness behavior

| Launcher                                               | `AXIsProcessTrusted()` | Focused-element result            | Time     |
| ------------------------------------------------------ | ---------------------- | --------------------------------- | -------- |
| Agent shell, responsible process attributed to Ghostty | `true`                 | `AXError.cannotComplete (-25204)` | 0.043 ms |
| New Ghostty window running the probe                   | `true`                 | `AXError.cannotComplete (-25204)` | 0.014 ms |
| Terminal `.command` running the probe                  | `false`                | `AXError.cannotComplete (-25204)` | 0.022 ms |

The Ghostty result verifies responsible-process attribution at the **trust preflight** boundary: the unsigned CLI inherited Ghostty's approved Accessibility trust without receiving its own TCC row.

Follow-up runs resolved the `-25204` mystery: it is **not** an execution-path problem. From the same agent shell, `AXUIElementCreateApplication(frontmostPID)` → `kAXFocusedUIElementAttribute` succeeded against every target in the matrix while the system-wide element kept failing. The defect is specific to `AXUIElementCreateSystemWide()`'s focused-element read on macOS 26.5.2; per-application focus resolution is unaffected. Production should never touch the system-wide element.

## Target matrix

Measured 2026-08-02 on macOS 26.5.2 via the frontmost-app route, all from the agent shell (Ghostty-attributed trust). Attribute reads after element acquisition were sub-millisecond everywhere; first focused-element acquisition per app ranged 0.4–19 ms.

| Target                                         | Observed shape                                                                                                                                                                                                                                                                           | Evidence                                                                                                                    | Bounded read                                                          | Status                                   |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ---------------------------------------- |
| TextEdit (224,014-unit document, caret at end) | `AXTextArea`, full contract                                                                                                                                                                                                                                                              | value 0.53 ms (pulls all 224k units), bounded 256-unit read 0.085 ms, selected range 0.061 ms, insertion-point line 5.26 ms | Works; time insensitive to document size                              | **Exposed**                              |
| Notes                                          | `AXTextArea`, full contract (2,068-unit real note)                                                                                                                                                                                                                                       | value 5.04 ms, bounded 0.085 ms                                                                                             | Works                                                                 | **Exposed**                              |
| Xcode source editor                            | `AXTextArea`, full contract                                                                                                                                                                                                                                                              | all reads ≤ 0.15 ms                                                                                                         | Works                                                                 | **Exposed**                              |
| Safari `textarea` (autofocus, file://)         | `AXTextArea`, full contract                                                                                                                                                                                                                                                              | all reads ≤ 0.06 ms                                                                                                         | Works                                                                 | **Exposed**                              |
| Google Chrome 151 `textarea`                   | Fresh process has no focused element after both documented activation writes; a 376-node breadth-first walk wakes AX, then an `AXFocused = true` descendant is an `AXTextArea` with full value and caret `{40, 0}`                                                                       | both activation attributes fail; `--force-renderer-accessibility` also works; descend-to-focused resolves the field         | Works after background prewarm + descent                              | **Version-specific accommodation**       |
| Google Docs (Chrome 151, canvas editor)        | Focused element is an `AXTextArea` (`AXDescription = Document content`) inside an `about:blank` `AXWebArea`; its value is exactly `\u{200B}\u{200B}` with the caret pinned at `{1, 0}` — an empty document and a two-sentence document answer identically                                | value 0.044 ms, count 2, `AXStringForRange 0..<2` 0.050 ms; the docs.google.com `AXURL` sits two levels up the parent chain | Serves ranges, but never the document                                 | **Exposed — keystroke sink** (see below) |
| Dia (fresh-tab prompt box)                     | Focused element is a native `AXTextArea` with full contract, no wake needed; a word-wise selection inside `select a sentence, asdf asdf asdf` reported `{19, 15}`, leaving the space in `before` — a different layout from the one reported live, where the selection began at the space | value 0.042 ms, count 34, caret and selected range exact; a ⌘V lands in the AX value inside one 50 ms poll                  | Works                                                                 | **Exposed**                              |
| Dia (web page `textarea`)                      | Focused element resolves straight to the page's `AXTextArea`; the containing `AXWebArea` carries the page `AXURL`                                                                                                                                                                        | focused element 16.9 ms (cold process), value 0.042 ms                                                                      | Works                                                                 | **Exposed**                              |
| VS Code (Monaco)                               | `AXTextArea`, full contract after activation                                                                                                                                                                                                                                             | `AXManualAccessibility` set returns success (11.9 ms); a 500 ms check was empty and a later ~2 s check worked               | Works                                                                 | **Exposed after async readiness**        |
| Terminal.app running `nvim` (alternate screen) | `AXTextArea` whose value is the **visible screen grid** (2,131 units: prompt history + rendered nvim buffer); selected range `{193, 0}` = terminal cursor; insertion-point line returned the nvim cursor row exactly                                                                     | value 0.22 ms, bounded 0.08 ms                                                                                              | Works mechanically; semantics are the screen, not the edited document | **Exposed — grid semantics**             |
| Ghostty (TUI on screen)                        | `AXTextArea`, value = visible screen text (441 units), selected range `{0, 0}`; insertion-point line failed (`-25213`)                                                                                                                                                                   | value 0.14 ms                                                                                                               | Works mechanically; caret unreliable                                  | **Exposed — grid semantics**             |

The alternate-screen question is answered: terminals expose the **visible grid as one text value** — not the underlying document, and not nothing. A clean-window Ghostty re-probe (a fresh shell prompt with a typed command; the first Ghostty row above accidentally measured a stray error window) refined the caret picture: Ghostty advertises `AXSelectedTextRange` and `AXStringForRange` and serves the grid text in 0.077 ms, but the selected range answers `{0, 0}` wherever the cursor actually sits, and the line-navigation chain is incomplete (`AXRangeForLine` absent). Terminal.app's cursor-shaped selected range was the exception, not the rule. Upstream, Ghostty has in-progress AX work (cursor position, line navigation, change notifications) that would complete this contract. At a shell prompt the cursor genuinely marks the insertion point, so spacing decisions are plausible; inside a TUI the grid text is arbitrary screen content. Recommend classifying terminals by bundle ID exactly as cua does (`terminal.rs` allowlist: Terminal.app, iTerm2, Ghostty, kitty, WezTerm, Warp, Alacritty, Hyper, Zed helper) and routing them through the unavailable path **unconditionally**. A mechanical earn-back — graduating any terminal whose `AXSelectedTextRange` returns a nonzero, in-bounds caret — was drafted here and then withdrawn during implementation, because this table refutes it: Terminal.app running nvim reports `{193, 0}`, a nonzero in-bounds caret, over text that is still pure screen grid. The test admits exactly the case it exists to exclude. Graduation is therefore a per-terminal, per-version judgement backed by evidence that the target serves the *document* rather than the grid (Ghostty completing its upstream cursor and line-navigation work is the likely first candidate), not a range check the reader can make on its own. Prior art supports this floor: cua's terminal special case covers only the *write* path (AX text writes silently never reach the PTY, so it types synthetic keystrokes at the existing cursor — the same shape as MiniWhisper's ⌘V delivery), it reads no terminal caret at all, and Wispr Flow's compatibility documentation treats every terminal as a paste-only target. Nobody in the field reads terminal context today; assuming the cursor sits at the end of the grid would be inference, which this ticket rejects.

## Failure verdicts

| Failure / observation                                                           | Verdict                                                                                                                                                                                           | Consequence                                                                                                                                      |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Trusted `AXUIElementCreateSystemWide()` → `AXFocusedUIElement` returns `-25204` | **Holding it wrong on macOS 26.5.2**, not a missing grant. Per-PID focus works on the same host, and independent reports reproduce the trusted-but-`cannotComplete` symptom.[^systemwide-failure] | Never use the system-wide element. Route `NSWorkspace.frontmostApplication` → `AXUIElementCreateApplication(pid)` → focused element.             |
| Range past `AXNumberOfCharacters` returns `-25201`                              | **Holding the range wrong.**                                                                                                                                                                      | Clamp before requesting `AXStringForRange`; do not expect the target to clamp.                                                                   |
| Notes/Xcode/Ghostty `AXSubrole` returns `-25205`                                | **Genuinely unsupported optional attribute.**                                                                                                                                                     | Do not read subrole in the shipping path. Role and text contract decide eligibility.                                                             |
| Ghostty insertion-line returns `-25213`                                         | **Genuinely unsupported parameterized operation.** `-25213` is `kAXErrorParameterizedAttributeUnsupported`, not an AX outage.[^ax-errors]                                                         | Line context is diagnostic only. Bounded `AXStringForRange` still works, so do not discard an otherwise readable native field for this.          |
| Chrome fresh process returns `-25212` after both activation writes              | **Version-specific Chrome 151 compatibility failure.** The writes are rejected and do not reliably wake a fresh browser.                                                                          | Treat both documented attributes as an attempted optimization, not a proof of readiness. Use the Chrome-specific bootstrap below or blind paste. |
| Terminal `AXTextArea` exposes the screen grid                                   | **Genuinely unsuitable semantics, not an API failure.**                                                                                                                                           | Classify terminal bundle IDs as `gridSemantics` and blind paste.                                                                                 |
| Google Docs' focused `AXTextArea` answers `\u{200B}\u{200B}`                    | **Genuinely unsuitable semantics.** It is a keystroke sink for the canvas, not the document, and it is not stale: it never catches up, at any content or caret position.                          | Classify a field whose whole captured window is zero-width characters as `zeroWidthSink` and blind paste.                                        |
| Dia was invisible to the `" Framework.framework"` name test                     | **Detection held wrong.** Dia's Chromium lives in `ArcCore.framework`, so a name test walked past it and never woke the browser.                                                                  | Detect the family by the renderer helper (`Versions/*/Helpers/* (Renderer).app`), which Chrome and Dia both ship.                                |
| A cold first AX message to an app costs 8–20 ms                                 | **The handshake, not a hang.** Every read after it is sub-millisecond.                                                                                                                            | The 20 ms cap sat inside that distribution; the application element now gets 40 ms and the 60 ms budget still bounds the capture.                |

## Chromium activation

Chromium documents a lazy cached accessibility DOM: it recommends `AXEnhancedUserInterface`, `--force-renderer-accessibility`, or `chrome://accessibility` to enable it.[^chromium-a11y] Electron separately documents `AXManualAccessibility` for Electron apps.[^electron-a11y] The current Chrome browser result is narrower and worse than those documents promise.

### Chrome 151 verdict

On fresh, isolated Chrome 151 processes, `AXManualAccessibility = true` returned `-25205` (`kAXErrorAttributeUnsupported`) and `AXEnhancedUserInterface = true` returned `-25208` (`kAXErrorNotImplemented`). Ignoring both results then waiting **250 ms, 500 ms, or 1,000 ms** still returned `-25212` (`kAXErrorNoValue`) for the app's focused element. That is enough to call the errors real for this Chrome version: they are not successful writes with an inaccurate status, and a wait does not repair them.

A breadth-first `AXChildren` traversal did wake the same fresh process: 376 nodes / 187.3 ms on first walk, then the focused field returned with its full range/value contract. A fresh Chrome launched with the documented `--force-renderer-accessibility` flag also exposed the `AXTextArea` immediately (focused lookup 9.44 ms; bounded range read 0.036 ms). `chrome://accessibility` remains a documented user-controlled alternative but was not automated here. The launch flag cannot be imposed on the user's already-running Chrome, and the first traversal is far beyond delivery's hot-path budget.

No Chromium source change or issue was found that proves removal of either attribute in the Chrome 149–151 period. Current Chromium source and public documentation still discuss enhanced UI, so the safe conclusion is **version-specific incompatibility until a Chrome bug confirms otherwise**, not that Chrome has permanently removed the mechanism. `trycua/cua`'s documented flow would also fail on this host: it tries manual accessibility first, then tries enhanced UI only after `AttributeUnsupported`; Chrome produces exactly that first error, then rejects the fallback as `NotImplemented`.[^cua-chromium]

Traversal is an observed bootstrap effect, not established industry contract. Hammerspoon exposes generic AX tree traversal APIs, but does not present traversal as Chrome activation.[^hammerspoon-ax] WindowKit currently advertises a one-time Chromium nudge and says its `AXManualAccessibility` path works for Chrome/Electron; this host falsifies that as a universal Chrome 151 claim.[^windowkit] No audited VoiceInk or Whispering code was found that reads focused-field context, so neither supplies a dictation precedent.

For production, record the app version and PID. On a new Chrome PID, attempt the documented writes once, wait without blocking delivery, then test focus. If still empty, a once-per-PID **background** traversal may prewarm it for a later dictation; never perform the 187 ms walk in the delivery critical path. Until that prewarm succeeds, return unavailable. Do not use or toggle enhanced UI repeatedly; its window-manager resize risk remains documented.[^chromium-resize]

### Electron / VS Code settle

VS Code accepted `AXManualAccessibility` (11.9 ms) while rejecting enhanced UI, and a later two-second run exposed Monaco's full text contract. The first 500 ms run returned `noValue`. A later attempt at an isolated start could not give a clean timing result because Code's workbench, rather than its editor, owned focus. So **2 seconds is evidence of eventual readiness, not a defensible blocking settle time**.

`cua` settles for 500 ms only after a successful once-per-PID activation; it is an automation snapshot budget, not a delivery latency target.[^cua-tree] Use its 500 ms value as the first background readiness check, then retry at 1,000 and 2,000 ms. The capture operation itself never sleeps: it observes the cached ready/not-ready state and blind-pastes while activation remains pending. This handles the observed 500 ms failure without charging any dictation two seconds.

## Messaging timeout

`AXUIElementSetMessagingTimeout` is scoped to the supplied `AXUIElement`; it is not inherited from an application element. `cua` consequently sets its 2 s automation timeout on the app, top-level candidates, and every visited descendant.[^cua-tree] That is reasonable for an interactive computer-use driver, but not delivery.

The probe successfully set a 20 ms timeout on the focused Code web-area target; normal reads remained sub-millisecond. It did not deliberately hang a target, so the exact timeout overrun behavior remains unmeasured. Ship a **per-request timeout of `min(cap, budget remaining)`**, installed on each AX object immediately before it is asked anything — the app before the focused-element lookup, then the resolved text element before each of its reads. On the first AX timeout or `cannotComplete`, stop all further AX work and blind-paste—no retry on this dictation. Normal calls are below 1 ms, while one stalled message adds at most its installed timeout — never more than the budget still owed; this preserves the under-25-ms-class success path without pretending AX offers a cancellable whole-capture deadline. A strict end-to-end deadline remains impossible with this synchronous API and needs a separate design if it becomes a product requirement.[^ax-timeout]

Live testing corrected both halves of that.

First, the cap. Re-measured 2026-08-02 with one probe process per run, so every run paid a cold connection: the focused-element read cost 19.9, 14.1, 10.5, 8.6, 8.0, and 8.9 ms against a running Dia, and 12.9–17.1 ms against Chrome, while every attribute read that followed stayed under 0.2 ms. A 20 ms cap therefore sits inside the normal distribution of the *first* message to an application and turns a healthy app into an intermittent blind paste. The application element now gets 40 ms for that handshake; resolved elements keep 20 ms.

Second, the budget. A per-request cap plus a deadline checked *between* requests does not bound anything: three 20 ms requests can still start one after another while the deadline reads as met. Since AX offers no cancellable whole-capture deadline, the budget is enforced through the only knob it does offer. Before every request the reader computes the time left and installs `min(perCallCap, remaining)` as that element's messaging timeout; a request that would begin with nothing left returns `timedOut` without being sent. The worst case is then the budget itself rather than the sum of the caps, and the 60 ms in the code means what it says.

## Canvas editors: the Google Docs sink

Measured 2026-08-02 in Chrome 151 after the traversal wake, with the document created empty, then typed into (`Line one, second sentence here. And a third one,` plus a trailing space):

| Read                     | Empty document                                    | Document with two sentences |
| ------------------------ | ------------------------------------------------- | --------------------------- |
| focused role             | `AXTextArea` (`AXDescription = Document content`) | same                        |
| `AXValue`                | `"\u{200B}\u{200B}"`                              | `"\u{200B}\u{200B}"`        |
| `AXNumberOfCharacters`   | 2                                                 | 2                           |
| `AXSelectedTextRange`    | `{1, 0}`                                          | `{1, 0}`                    |
| `AXStringForRange 0..<2` | `"\u{200B}\u{200B}"`                              | `"\u{200B}\u{200B}"`        |

Six polls at 300 ms after typing never changed any of those answers, so **the suspected staleness is not a lag window**: Docs keeps its document on a `<canvas>` and hands the Accessibility API a two-zero-width-space input sink that the caret sits inside. Nothing catches up, so no delay, retry, or freshness check can help.

The join saw one zero-width space as the preceding text. `\u{200B}` is not whitespace and not punctuation, so the rules read it as a word character and added a separating space on top of the space the user had really typed — the double space reported from live use.

Field check, 2026-08-02: the user ran Wispr Flow and Aqua Voice against Google Docs and both paste with no spacing or capitalization smarts either — the sink defeats the whole field, not just this implementation. Blind paste plus the notice is the industry ceiling for Docs; a sink-specific separator policy was considered and dropped once this evidence landed. The one unexplored avenue remains Docs' screen-reader mode (⌘⌥Z), which may change what the canvas exposes — unprobed.

Detection was decided on content, not on a site allowlist. The `about:blank` `AXWebArea` above the sink carries no useful `AXURL`; the docs.google.com URL is two levels further up the parent chain, so identifying Docs by URL costs extra AX calls on the delivery path and only ever covers the one site. A field whose entire captured window is zero-width characters carries no context by definition, whoever built it, so the reader classifies that as `zeroWidthSink` and blind-pastes. An empty field stays `available` and empty, which is a different and correct answer.

## Prior art comparison

| Tool / source                        | Focus and timeout mechanics                                                                                                                                      | Chromium / terminal implication                                                                                                                                                                                                                                  |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `trycua/cua` production macOS driver | Per-PID application element only; never uses `AXUIElementCreateSystemWide`. Sets a 2 s timeout separately on each AX object it traverses.[^cua-focus][^cua-tree] | Manual accessibility → enhanced UI only on `AttributeUnsupported`, then 500 ms settle once per successful PID. Its terminal bundle-ID list bypasses AX selected-text writes because they report success but do not reach the PTY.[^cua-chromium][^cua-terminals] |
| Chromium documentation               | Documents enhanced UI plus launch/UI overrides.                                                                                                                  | Chrome 151 here violates the attribute route, but `--force-renderer-accessibility` works.                                                                                                                                                                        |
| Electron documentation / VS Code     | Documents manual accessibility for third-party clients.                                                                                                          | Works in VS Code; use asynchronous readiness rather than assuming Chrome behavior transfers.                                                                                                                                                                     |
| Hammerspoon / WindowKit              | Generic AX tree search is available; WindowKit advertises a once-per-PID Chromium nudge.                                                                         | Neither proves that traversal is a stable Chrome activation contract. WindowKit's universal manual-accessibility assertion conflicts with Chrome 151 here.                                                                                                       |

## Honest fallback taxonomy

The production client should conform AX failures at the boundary into this shape, retaining the raw `AXError` only for diagnostics:

```swift
enum ContextCapture {
  case available(FocusedTextContext)
  case unavailable(ContextUnavailable)
}

enum ContextUnavailable: Equatable, Sendable {
  case accessibilityPermissionMissing
  case noFocusedElement
  case nonTextElement(role: String?)
  case noTextRange(role: String?)
  case gridSemantics(bundleID: String?)
  case zeroWidthSink(role: String?)
  case protectedField(role: String?)
  case axFailure(operation: ContextAXOperation, error: Int32)
}
```

- `accessibilityPermissionMissing`: `AXIsProcessTrusted()` is false. This is structural and should match the existing Paste Access/degraded handling, not prompt again.
- `noFocusedElement`: the frontmost app's focus read returns `kAXErrorNoValue`, an invalid element, or a missing value. The field may have disappeared between transcription and delivery.
- `nonTextElement`: a focused element exists but its role/advertised attributes do not identify an editable text surface. This covers buttons, menus, and canvas controls.
- `noTextRange`: text-ish target, but no usable selected range or `AXStringForRange` support. A readable full `AXValue` is not a license to use it: this feature's contract is bounded context.
- `gridSemantics`: a terminal-owned `AXTextArea` exposes rendered screen content rather than the edited document. It is technically readable but deliberately unavailable for context, with no mechanical route back (see the terminal row above); a validated build of a specific terminal can earn separate policy later.
- `zeroWidthSink`: the captured window is non-empty and made only of zero-width characters (`U+200B`, `U+200C`, `U+200D`, `U+FEFF`). A canvas editor is feeding the Accessibility API a keystroke sink; joining against it invents a preceding character that is not on screen.
- `protectedField`: an identified secure/password target, or its documented access-denied equivalent. Never log its text and never try a fallback full read.
- `axFailure`: timeout, `cannotComplete`, unsupported parameterized attribute, or other AX error while reading a target that previously looked usable. This is the bucket for transient process exits and hostile implementations.

`available` alone enables spacing/capitalization. Every unavailable case preserves today's blind paste and causes the subtle pill notice; the visible copy should identify unavailability rather than implying a successful contextual edit.

## Proposed payload

```swift
struct FocusedTextContext: Equatable, Sendable {
  var role: String
  var before: String
  var selected: String
  var after: String
  var selectedRange: Range<Int>
  var beforeWasTruncated: Bool
  var selectionWasTruncated: Bool
  var afterWasTruncated: Bool
}
```

The range is in AX's UTF-16 coordinate system, never Swift `Character` offsets. The client should construct the pieces from bounded parameterized ranges, not split a fetched full value. `before` ends at the selection start; `selected` is the replacement range; `after` starts at the selection end. This supplies immediate deterministic policy with no invention: inspect `before` for existing trailing whitespace and sentence-ending punctuation before choosing an initial space/capital. It also gives a later cleanup agent the actual neighboring text, replacement text, truncation facts, and role—without sending the entire document or any previous transcript.

A payload is emitted only after all slices succeed and their returned UTF-16 lengths/ranges conform. Partial capture is unavailable, not “best effort” context. The delivery transcript itself remains separate from this capture so cleanup policy can decide whether the selected range is replaced or only neighboring text is consulted.

## Remaining unknowns / manual checklist

Use a Finder-launched/signed MiniWhisper build or an Accessibility-approved inspection host for definitive target measurements. A CLI inherits its responsible application's TCC identity; on this host its system-wide focus request cannot complete, while its per-PID AX route does.

The matrix above was completed programmatically; what remains needs either a human or the shipping bundle:

1. From the signed MiniWhisper bundle, exercise one real field read after onboarding's normal Input Monitoring → Microphone → Paste Access ordering. Revoke nothing and reset no TCC state. Confirm that a grant permits the read and a denied/secure/non-text field produces the appropriate unavailable taxonomy and blind paste.
2. Safari/Chrome variants not yet probed: plain `input`, `contenteditable`, and a secure/password field (to pin down the `protectedField` signature — expected `AXSecureTextField` or access denial).
3. Chrome: after a dictation-driven activation walk, verify normal window-manager resizing still behaves (the `AXEnhancedUserInterface` risk should not apply since that attribute was never successfully set, but confirm).
4. Mid-document caret tests in a huge document (caret in the middle rather than at the end) to confirm bounded reads stay flat.
5. Whether the release-time warm-up actually pays the cold handshake before delivery needs it. Both call sites now log `source=warm-up` / `source=delivery` with elapsed milliseconds and outcome under `category: context`, so a short utterance into a not-yet-read application will show either a delivery read that is already sub-millisecond (the warm-up won) or one that is paying 8–20 ms itself (the warm-up lost the race). Sequencing the warm-up ahead of delivery is a design decision that should wait for that evidence.

[^apple-trust]: Apple, [`AXIsProcessTrusted`](https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted) and [`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions), accessed 2026-08-02.

[^mvp-phase-5]: [`docs/designs/01-mvp.md`](../../../designs/01-mvp.md), Phase 5 empirical TCC findings.

[^mvp-phase-7]: [`docs/designs/01-mvp.md`](../../../designs/01-mvp.md), Phase 7 empirical TCC findings and onboarding ordering.

[^chromium-a11y]: Chromium, [Accessibility Technical Documentation](https://www.chromium.org/developers/design-documents/accessibility), “How Chrome detects the presence of Assistive Technology” and “Accessibility internals,” accessed 2026-08-02.

[^electron-a11y]: Electron, [Accessibility](https://www.electronjs.org/docs/latest/tutorial/accessibility/), “Within third-party software: macOS,” accessed 2026-08-02.

[^chromium-resize]: Chromium [issue 40865608](https://issues.chromium.org/issues/40865608), “macOS: Toggling AXEnhancedUserInterface started to cause freezes / lags,” and Apple Developer Forums, [“AXEnhancedUserInterface breaks window positioning”](https://developer.apple.com/forums/thread/659755), accessed 2026-08-02.

[^systemwide-failure]: [PyObjC #656](https://github.com/ronaldoussoren/pyobjc/issues/656), Apple Developer Forums [thread 794253](https://developer.apple.com/forums/thread/794253), and Stack Overflow [27694912](https://stackoverflow.com/questions/27694912/axuielementcreatesystemwide-kaxfocuseduielementattribute-always-returns-kaxerror), accessed 2026-08-02. These corroborate the symptom; the per-PID workaround is established by the local matrix and `cua`.

[^ax-errors]: Xcode macOS 26 SDK [`AXError.h`](/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Headers/AXError.h), inspected 2026-08-02.

[^cua-focus]: [`focused_element_of_pid`](https://github.com/trycua/cua/blob/7ea91eb3f334/libs/cua-driver/rust/crates/platform-macos/src/ax/bindings.rs#L448-L468), `trycua/cua` `7ea91eb3f334`, inspected 2026-08-02.

[^cua-chromium]: [`enable_chromium_accessibility`](https://github.com/trycua/cua/blob/7ea91eb3f334/libs/cua-driver/rust/crates/platform-macos/src/ax/bindings.rs#L644-L669), `trycua/cua` `7ea91eb3f334`, inspected 2026-08-02.

[^cua-tree]: [`tree.rs`](https://github.com/trycua/cua/blob/7ea91eb3f334/libs/cua-driver/rust/crates/platform-macos/src/ax/tree.rs#L39-L65) and its per-element timeout application at [210–250](https://github.com/trycua/cua/blob/7ea91eb3f334/libs/cua-driver/rust/crates/platform-macos/src/ax/tree.rs#L210-L250) and [386–394](https://github.com/trycua/cua/blob/7ea91eb3f334/libs/cua-driver/rust/crates/platform-macos/src/ax/tree.rs#L386-L394), `trycua/cua` `7ea91eb3f334`, inspected 2026-08-02.

[^cua-terminals]: [`terminal.rs`](https://github.com/trycua/cua/blob/7ea91eb3f334/libs/cua-driver/rust/crates/platform-macos/src/terminal.rs#L1-L53) and [`type_text.rs`](https://github.com/trycua/cua/blob/7ea91eb3f334/libs/cua-driver/rust/crates/platform-macos/src/tools/type_text.rs#L867-L927), `trycua/cua` `7ea91eb3f334`, inspected 2026-08-02.

[^hammerspoon-ax]: Hammerspoon [`hs.axuielement`](https://www.hammerspoon.org/docs/hs.axuielement.html), `buildTree` and `elementSearch`, accessed 2026-08-02.

[^windowkit]: Dot-Fun [WindowKit](https://github.com/Dot-Fun/windowkit), Chromium/Electron compatibility and release notes, accessed 2026-08-02.

[^ax-timeout]: Apple [`AXUIElementSetMessagingTimeout`](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout) and the macOS SDK [`AXUIElement.h`](/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Headers/AXUIElement.h), inspected 2026-08-02.
