# Hotkey mechanism and hold/latch prior art

Research date: 2026-07-18.

## Recommendation

Use a `CGEventTap` at `.cgSessionEventTap`, listening for `.flagsChanged`, key down/up, and mouse-down events. Normalize those impure Core Graphics events into physical key transitions, then feed a configurable, pure, synchronous chord matcher and gesture state machine. Right Option is the initial `HotKey` value, not part of the event vocabulary.

A passive `.listenOnly` tap is sufficient for modifier-only bindings such as right Option, left Option, right Control, or a modifier-only Hyper chord. Keyed bindings such as Command-L or Hyper-V introduce a second requirement: the frontmost app must not also receive the trigger key. Preserve that capability in the boundary now. A keyed configuration can recreate the same session tap as an active `.defaultTap`, run the pure matcher synchronously, and suppress only matched trigger-key events. If active filtering is unavailable, fail that configuration rather than silently firing both dictation and the frontmost app's shortcut.

`RegisterEventHotKey` remains the wrong shape: it registers a virtual-key-plus-modifiers combination, Carbon's side-specific modifier bits are explicitly unsupported on macOS, and it cannot express the raw modifier transitions required by modifier-only hold/latch gestures. An AppKit global event monitor also buys nothing here and uses the less suitable Accessibility permission path.

The parts worth stealing differ by project:

- **Hex:** the pure processor, dirty-until-release state, immediate recording start, 300 ms modifier-only floor, release-to-release double-tap lock, and clock-controlled scenario tests.
- **VoiceInk:** active filtering at `.cgSessionEventTap`, side-specific matching by modifier keycode, selective suppression for keyed shortcuts, pass-through modifier-only handling, synthetic releases when the tap is disabled, and serial delivery outside the callback.
- **Whispering:** recording-session ownership by ID, a release latch while asynchronous recording startup is in flight, stale-session rejection, and a maximum-recording safety fuse.

Do not make Hex's HID-level placement or private device masks foundational. MiniWhisper's initial modifier-only binding only needs passive observation. The generalized boundary should nevertheless support an active session-level tap when a configured keyed chord must be swallowed.

## Why CGEventTap

Apple DTS lists `CGEventTap`, AppKit's global event monitor, and `RegisterEventHotKey` as the global-keyboard options. It prefers `CGEventTap` over AppKit monitoring because `CGPreflightListenEventAccess()` and `CGRequestListenEventAccess()` directly expose its Input Monitoring permission, and confirms support for sandboxed apps from macOS 10.15 onward.[^apple-hotkeys] A second DTS example demonstrates a sandboxed `.cgSessionEventTap` with `.listenOnly` and the same permission flow.[^apple-sandbox]

Apple's `tapCreate` contract also fits fail-fast handling: unauthorized event bits are removed from the requested mask, and creation returns `nil` if no permitted bits remain. The callback runs on the run loop where its Mach-port source is installed.[^apple-tap-create]

### Why the session location is early enough

Tap **location** and tap **behavior** are independent choices:

- `.cghidEventTap` versus `.cgSessionEventTap` selects where the callback sits in the route.
- `.defaultTap` versus `.listenOnly` selects whether the callback is an active filter or passive observer.

Apple defines `.cgSessionEventTap` as the point where HID and remote-control events enter the current login session. `.cgAnnotatedSessionEventTap` is later, after an event has been annotated for a destination application.[^apple-session-tap] Command-L and Hyper-V therefore pass through the session location before macOS routes them to the frontmost app.

An active callback may return `nil` to delete an event.[^apple-tap-callback] Returning `nil` from a `.defaultTap` at `.cgSessionEventTap` removes the trigger before it reaches application routing, which is all MiniWhisper needs to prevent Command-L from reaching Safari or Hyper-V from reaching an editor. Active filtering does not require HID-level placement.

The HID location is earlier still: where HID events enter the WindowServer, before they enter a login session. That matters for software operating below or across the session boundary, not a per-user menu-bar app whose shortcut should work inside its own login session. Apple's current headers and documentation also say non-root processes cannot place a tap there, despite Hex requesting that location in its shipping code.[^apple-tap-create] MiniWhisper should not depend on that discrepancy when the documented session location already provides the necessary observation and deletion point.

This does not make every macOS key sequence bindable. Secure-attention and other OS-reserved sequences may never be available to a user-session filter. “Generalized” means any ordinary physical chord delivered through the session event stream, with unavailable bindings rejected explicitly.

Use:

- location: `.cgSessionEventTap` — global to the login session without making HID-level placement a requirement;
- placement: `.headInsertEventTap` — lowest avoidable observation latency;
- options: `.listenOnly` for modifier-only bindings; `.defaultTap` only for keyed bindings configured to suppress their trigger;
- mask: `.flagsChanged`, `.keyDown`, `.keyUp`, and mouse-down events;
- a dedicated run-loop thread with a deliberately tiny callback;
- synchronous normalization and pure matching in the callback, followed by asynchronous decision delivery.

The callback should extract a timestamp, physical key transition, and normalized modifier state; synchronously obtain a decision plus pass/suppress disposition; enqueue only the decision; then return the original event or `nil`. AVFoundation, TCA, UI work, and recording startup do not belong on that run loop. Suppress the configured nonmodifier trigger's down, repeat, and matching up events—not modifier transitions—so the frontmost app cannot observe half of a keyed shortcut.

## Generalized physical keys and modifiers

A `.flagsChanged` event is the event type for modifier/status-key transitions.[^apple-flags-changed] Its `keyboardEventKeycode` identifies the physical key that changed. Apple's current Xcode 26.5 SDK declares layout-independent virtual keycodes for left and right Command, Shift, Option, and Control; for example, left Option is `0x3A` and right Option is `0x3D` in `Carbon.framework/.../HIToolbox.framework/.../Headers/Events.h`.

The ordinary Core Graphics modifier flags are aggregate: `.maskAlternate` says an Option key is down, not which one.[^apple-event-flags] Hex recovers sides from undocumented device-dependent bits in `CGEventFlags.rawValue`: `0x20` for left Option, `0x40` for right Option, and similar masks for the other modifiers.[^hex-hotkey-model] They are “private device masks” in the narrow sense that Core Graphics does not publish them as `CGEventFlags` constants. Hex uses them because each event is converted directly into a complete modifier snapshot; when L goes down in Command-L, the changed keycode identifies L, so the snapshot still needs another way to know which Command key is held.

MiniWhisper can avoid that dependency by maintaining a pressed-key set from physical transitions. Every `.flagsChanged` event identifies the concrete modifier that changed; every ordinary key down/up identifies its physical key. When L goes down, the set already records whether left Command, right Command, or both preceded it. Reset that set whenever the tap is recreated or interrupted, and remain blocked until all observed input is released so a missing first edge cannot activate dictation.

Model configuration separately from observations:

```swift
enum ModifierKind: Hashable, Sendable {
  case command, control, option, shift, function
}

enum ModifierSide: Hashable, Sendable {
  case left, right
}

enum SideRequirement: Hashable, Sendable {
  case left
  case right
  case either
  case both
}

struct ModifierRequirement: Hashable, Sendable {
  let kind: ModifierKind
  let side: SideRequirement
}

struct Key: RawRepresentable, Hashable, Sendable {
  let rawValue: CGKeyCode
}

struct HotKey: Equatable, Sendable {
  let key: Key?
  let modifiers: Set<ModifierRequirement>
}
```

`key == nil` means a modifier-only chord. A non-`nil` key is the primary trigger. Side policy is independent for every modifier kind:

```swift
HotKey(key: nil, modifiers: [.option(.left)])   // only left Option
HotKey(key: nil, modifiers: [.option(.right)])  // only right Option
HotKey(key: nil, modifiers: [.option(.either)]) // either Option side

HotKey(key: .l, modifiers: [.command(.left)])   // only left Command-L
HotKey(key: .l, modifiers: [.command(.right)])  // only right Command-L
HotKey(key: .l, modifiers: [.command(.either)]) // either Command side + L

HotKey(
  key: .v,
  modifiers: [
    .command(.either), .control(.either),
    .option(.either), .shift(.either),
  ]
) // Hyper-V
```

Those convenience members are illustrative; the stored declarations should remain direct and non-magical. Matching should be exact across modifier kinds and nonmodifier keys, while each requirement applies its explicit side policy:

- `.left`: left must be down; right is rejected as an extra side of that kind.
- `.right`: right must be down; left is rejected.
- `.either`: at least one side must be down; left, right, or both satisfy it.
- `.both`: left and right must both be down.

The pressed snapshot never erases sides. Consequently the same matcher can distinguish only-left Command-L, only-right Command-L, either-side Command-L, and—if ever useful—both-Commands-L without changing the input model.

For modifier-only chords, activation occurs when the required modifier set becomes an exact match and release occurs when it ceases to match. For keyed chords, the nonmodifier key is the primary trigger: exact match on its down starts; its up finishes even if modifiers were released first. That mirrors Hex and gives suppression a well-defined down/up pair.

Carbon's own SDK explains why its registration API cannot replace this model. `RegisterEventHotKey` accepts one virtual keycode and one modifiers value, while `rightOptionKey`, `rightShiftKey`, and `rightControlKey` are marked “Not supported on Mac OS X” in `Events.h`. It is also legacy Carbon; Apple DTS says it cannot honestly recommend it.[^apple-hotkeys] MiniWhisper may use HIToolbox's named virtual-key constants without using Carbon's hotkey registration mechanism.

## Prior art

### Hex

At commit [`ca964279`](https://github.com/kitlangton/Hex/tree/ca96427990249223cc31027d14c1f2c9ded57910), [`HotKeyProcessor`](https://github.com/kitlangton/Hex/blob/ca96427990249223cc31027d14c1f2c9ded57910/HexCore/Sources/HexCore/Logic/HotKeyProcessor.swift) is a value-type reducer. Its phases are idle, press-and-hold with a start time, and double-tap lock; outputs are start, stop, cancel, and discard.[^hex-processor] It separately tracks the last release and a dirty flag.

For a modifier-only binding:

1. The matching press starts recording immediately.
2. A normal release stops it and records the release time.
3. A second press starts a new recording.
4. If the second release is less than 300 ms after the first release, it remains recording and enters the lock.
5. The next matching press stops the lock immediately.

The first quick recording is later discarded by `RecordingDecisionEngine`, which enforces at least 300 ms for modifier-only captures. This makes a lone tap a near-no-op without adding 300 ms of latency to a real hold. A second press held long enough that its release misses the release-to-release window remains an ordinary hold.

Hex also handles conflict input well. Escape cancels and dirties the processor. Extra input or a mouse click during the first 300 ms of a modifier-only hold discards it; after that floor, extra input is ignored and Escape remains the explicit cancellation path. Dirty input cannot backslide into activation as keys are released; only a fully neutral chord rearms it.

[`HotKeyProcessorTests`](https://github.com/kitlangton/Hex/blob/ca96427990249223cc31027d14c1f2c9ded57910/HexCore/Tests/HexCoreTests/HotKeyProcessorTests.swift) contains roughly 900 lines of injected-clock scenarios covering holds, quick and slow double taps, the second-release lock boundary, a long second hold, third-press stop, extra modifiers, mouse clicks, Escape, dirty-state recovery, and minimum-duration decisions.[^hex-tests] This is the strongest prior art in the survey. Its notable gap is an explicit left-versus-right Option processor test.

Hex's production [`KeyEventMonitorClient`](https://github.com/kitlangton/Hex/blob/ca96427990249223cc31027d14c1f2c9ded57910/Hex/Clients/KeyEventMonitorClient.swift) uses `.cghidEventTap`, the earliest HID-side tap location, with `.defaultTap`, the active-filter option. Its callback returns `nil` when a handler consumes an event, so a configured keyed shortcut does not also act in the frontmost app. Hex is the only inspected open-source implementation that chooses the HID location. That is why it accepts the broader Accessibility/IOHID permission surface. Its HID placement is not required merely to detect keys; a session-level active tap preserves the same suppression seam. Its active-filter capability becomes relevant to MiniWhisper only for generalized keyed chords such as Command-L or Hyper-V. A bare modifier has no trigger-key action to suppress, so the initial right-Option configuration can remain passive.

Hex also provides useful operational defenses: re-enable on `.tapDisabledByTimeout` and `.tapDisabledByUserInput`, verify/restart after wake and session activation, and trust observed event flow over occasionally stale IOHID permission state.[^hex-monitor]

### VoiceInk

At commit [`69ed170c`](https://github.com/Beingpax/VoiceInk/tree/69ed170c1d7f582e76f3f63a2ac2c30ddb3a2d75), [`ShortcutMonitor`](https://github.com/Beingpax/VoiceInk/blob/69ed170c1d7f582e76f3f63a2ac2c30ddb3a2d75/VoiceInk/Shortcuts/ShortcutMonitor.swift) uses `.defaultTap` at `.cgSessionEventTap`. Its callback returns `nil` when `handleCGEvent` requests suppression, directly demonstrating that active session-level filtering can consume keyed shortcuts before applications receive them. It tracks each shortcut's pressed state, handles `.flagsChanged` separately and without suppression for modifier-only shortcuts, synthesizes release callbacks when the tap is disabled, and calls `CGEvent.tapEnable` to recover.[^voiceink-monitor]

Its higher-level gesture is not MiniWhisper's: hybrid mode latches after a short press and uses a 500 ms boundary rather than requiring a double tap. VoiceInk also has no meaningful shortcut unit-test suite at this revision. Its event-adapter mechanics are useful; its gesture semantics and test posture are not.

### Whispering / Epicenter

At commit [`cb12bcc`](https://github.com/epicenter-md/epicenter/tree/cb12bccfdeba2ba6bad65bd905d78ea92130e99d), Whispering's desktop global-shortcut path intentionally rejects modifier-only and side-specific bindings, so it cannot implement the pinned right-Option UX.[^whispering-bindings] Its [`push-to-talk`](https://github.com/EpicenterHQ/epicenter/blob/cb12bccfdeba2ba6bad65bd905d78ea92130e99d/apps/whispering/src/lib/operations/push-to-talk.ts) operation is still useful downstream: a session owns the recording ID it starts, release during asynchronous startup sets `stopRequested`, stale releases cannot stop a newer recording, and a five-minute cap prevents an indefinitely stuck capture.[^whispering-ptt]

## Recommended event pipeline

```text
CGEvent tap callback
  → normalize to a physical KeyTransition + pressed-after snapshot
  → pure HotkeyGesture(configured HotKey) → HotkeyOutcome
      ↳ apply pass/suppress disposition synchronously
      ↳ enqueue capture decision asynchronously
  → HotkeyListener client boundary
  → AppFeature orchestration
  → AudioCapture start / finish / discard / cancel by recording ID
```

Responsibilities should remain sharp:

- **Event-tap adapter:** permissions, Mach port/run loop, CG keycode classification, physical pressed-key bookkeeping, callback recovery, wake/session recovery, and normalization.
- **Pure chord matcher:** compares the configured `HotKey` with each pressed-after snapshot and identifies activation, release, conflict, and full-release edges.
- **Pure gesture machine:** owns hold/latch timing, dirty-until-release behavior, and the synchronous pass/suppress disposition. It does not know Core Graphics, TCA, AVFoundation, or permissions.
- **HotkeyListener client:** owns listener lifetime and configuration, advertises whether suppression is available, and exposes an asynchronous decision stream.
- **AppFeature:** pairs decisions with recording-session IDs and coordinates AudioCapture/transcription.
- **AudioCapture:** provides idempotent start/finish/discard/cancel operations; it does not interpret keyboard gestures.

The adapter should emit generalized values resembling:

```swift
enum PhysicalKey: Hashable, Sendable {
  case key(Key)
  case modifier(ModifierKind, ModifierSide)
}

enum KeyPhase: Equatable, Sendable {
  case down
  case up
}

struct KeyTransition: Equatable, Sendable {
  let key: PhysicalKey
  let phase: KeyPhase
  let isRepeat: Bool
  let pressedAfter: Set<PhysicalKey>
  let time: Duration
}

enum HotkeyInput: Equatable, Sendable {
  case key(KeyTransition)
  case mouseDown(time: Duration)
  case monitoringInterrupted
}

enum HotkeyDecision: Equatable, Sendable {
  case startCapture
  case finishCapture
  case discardCapture
  case cancelCapture
}

enum EventDisposition: Equatable, Sendable {
  case passThrough
  case suppress
}

struct HotkeyOutcome: Equatable, Sendable {
  let decision: HotkeyDecision?
  let disposition: EventDisposition
}
```

There is no `rightOptionDown`, `leftControlDown`, or `otherInputDown`. Every keyboard input is one physical transition. “Other” is a relationship computed by the matcher: a key is conflicting only because it does not belong to the configured chord in the current phase.

`Duration` is monotonic time since listener startup, not wall-clock `Date`. Tests can pass exact values directly; production can derive them from `ContinuousClock`. The state machine needs no clock dependency if time arrives with the event.

## Pure state-machine sketch

```swift
struct HotkeyGesture: Equatable, Sendable {
  struct Timing: Equatable, Sendable {
    let tapWindow: Duration
    let minimumHold: Duration
  }

  enum Phase: Equatable, Sendable {
    case idle
    case holding(startedAt: Duration)
    case latched
    case blockedUntilRelease
  }

  let hotKey: HotKey
  let timing: Timing
  var phase = Phase.blockedUntilRelease
  var previousQuickReleaseAt: Duration?
  var suppressedTriggerIsDown = false

  mutating func receive(_ input: HotkeyInput) -> HotkeyOutcome {
    // Match the configured chord, then switch over phase and semantic edge.
  }
}
```

`Timing` belongs to gesture configuration rather than a specific key. Right Option can initially use Hex's 300 ms tap window and modifier-only floor. Other bindings can retain those semantics or choose a different minimum later without changing the event or state model.

Recommended semantic transitions to take into the MVP UX grilling ticket:

| Current phase      | Semantic input                   | Guard                                                              | Next phase                | Decision        |
| ------------------ | -------------------------------- | ------------------------------------------------------------------ | ------------------------- | --------------- |
| blocked            | key transition                   | `pressedAfter` is empty                                            | idle                      | —               |
| idle               | configured chord activation edge | exact match                                                        | holding(now)              | start capture   |
| idle               | unrelated key/modifier down      | —                                                                  | blocked                   | —               |
| holding            | configured release edge          | previous quick release exists and release-to-release `< tapWindow` | latched                   | —               |
| holding            | configured release edge          | held `< minimumHold`                                               | idle; remember release    | discard capture |
| holding            | configured release edge          | held `>= minimumHold`                                              | idle; clear prior release | finish capture  |
| holding            | unrelated key or mouse down      | held `< minimumHold`                                               | blocked                   | discard capture |
| holding            | unrelated key or mouse down      | held `>= minimumHold`                                              | holding                   | —               |
| holding            | Escape down                      | —                                                                  | blocked                   | cancel capture  |
| latched            | configured chord activation edge | —                                                                  | blocked                   | finish capture  |
| latched            | Escape down                      | —                                                                  | blocked                   | cancel capture  |
| holding or latched | monitoring interrupted           | —                                                                  | blocked                   | cancel capture  |

For a modifier-only `HotKey`, an activation edge is the transition into an exact modifier match and release is the transition out. For a keyed `HotKey`, activation is exact match on the primary key's down; release is that primary key's up. The next activation edge ends a latched recording regardless of which concrete binding is configured.

A first quick tap therefore starts capture immediately and discards it on release. A second quick tap starts a fresh capture and leaves that capture running at the second release. This matches Hex and avoids delaying every real hold while waiting to discover whether it was a tap. The 300 ms value is prior art, not yet a product decision; test it during the UX ticket.

Disposition is orthogonal to capture decisions. Modifier-only configurations always pass through. An active keyed configuration suppresses the primary key's down, repeats, and paired up while leaving modifier transitions and unrelated input untouched. `suppressedTriggerIsDown` survives phase changes so a stop/discard on key down cannot leak its paired key up to the frontmost app.

The effect layer should additionally adopt Whispering's startup latch. If `startCapture` is asynchronous and a finish/discard arrives before it returns, retain that terminal intent against the same session ID and execute it as soon as startup completes. Never let a late release stop a newer capture.

## Permission and failure behavior

### Input Monitoring

1. On an explicit enable/onboarding action, call `CGPreflightListenEventAccess()`.
2. If false, call `CGRequestListenEventAccess()` and explain where the user is being sent.
3. Attempt to create the passive tap. Treat `nil` as unavailable, not as an idle listener.
4. If permission remains unavailable, expose that state in the menu and provide a System Settings route. Do not repeatedly prompt.
5. On app activation, wake, and session reactivation, preflight and verify/recreate the tap. If recreation still fails after a grant, request a relaunch rather than claiming the hotkey is healthy.

Permission cache APIs have had stale results in shipping apps; Hex records actual event flow overriding a stale IOHID denial. MiniWhisper should use Apple's preflight API for presentation but use successful tap creation and observed health as operational truth.

### Optional active filtering

A `.listenOnly` tap cannot suppress Command-L or Hyper-V; those shortcuts would also reach the frontmost app. Supporting keyed bindings without side effects requires recreating the tap with `.defaultTap` and returning `nil` for consumed trigger events. That broadens the TCC surface from passive Input Monitoring toward Accessibility/event filtering and must be proved with the signed, sandboxed-or-unsandboxed artifact chosen by the distribution design.

Represent suppression as an explicit listener capability. If the configured `HotKey` has a primary key and requests suppression, startup must either establish active filtering or report the binding unavailable. Falling back to pass-through is not recovery; it is surprising input corruption with better branding.

### Tap disabled by timeout or user input

Apple documents that an unresponsive tap, or one disabled at user request, receives a disabled event and may be re-enabled with `CGEvent.tapEnable`.[^apple-tap-enable] The callback must handle both `.tapDisabledByTimeout` and `.tapDisabledByUserInput` before normal event decoding:

- emit `monitoringInterrupted`, causing active capture to cancel;
- clear physical pressed-state bookkeeping;
- call `tapEnable(..., true)`;
- remain blocked until all input is released.

The callback must stay constant-time enough that timeout disablement is exceptional. Recovery still exists because exceptional things are generally diligent.

### Secure Event Input

Apple's Secure Event Input technical note states that keyboard events are not passed to keyboard-intercept processes while secure input is active.[^apple-secure-input] Consequently, MiniWhisper cannot promise that the pinned modifier works in password/secure-entry contexts, and it may miss a release if secure input begins during capture.

Treat this as lost input, not permission denial:

- cancel active capture on known listener/session interruption;
- impose a maximum recording duration as a final safety fuse;
- reset to blocked after wake, fast-user switching, tap recreation, or app/session reactivation;
- do not rely on identifying which process enabled secure input—Apple DTS describes that attribution as best-effort and unreliable.[^apple-secure-owner]

An idle event tap cannot distinguish “the user pressed nothing” from “secure input hid the press.” The UI should report monitoring availability when it knows, but it must not invent certainty.

### Permission revocation and missing releases

There is no documented callback that cleanly models every live TCC revocation. Recheck on lifecycle boundaries, treat tap creation failure as unavailable, and cancel any active recording before tearing down a listener. A maximum-duration fuse protects the remaining case where a release disappears without a callback. Recreating the tap always resets the adapter and pure machine to blocked-until-release.

## Test inventory

The pure package should use Swift Testing and explicit `Duration` values. Run the common hold/latch scenarios against a configuration matrix, not only right Option. At minimum:

- left-only, right-only, either-side, and both-sides requirements for each modifier kind;
- `.either` accepts left, right, or both sides of its kind while still rejecting unconfigured modifier kinds;
- left-only Command-L rejects right Command-L and vice versa;
- either-side Command-L accepts both physical Command keys;
- modifier-only Hyper, Command-L, and Hyper-V produce the same semantic activation/release edges;
- right Option with another modifier does not activate when exact matching is configured;
- a keyed chord stops on its primary key's up even if a modifier was released first;
- startup while a key or modifier is held remains blocked until neutral;
- lone 299 ms tap starts then discards;
- 300 ms and longer hold starts then finishes;
- ordinary hold/release;
- double-tap release gaps at 299 ms and 300 ms;
- second tap held beyond the window becomes an ordinary hold;
- double tap latches; the next down finishes without waiting for its up;
- Escape cancels holding and latched phases;
- extra key, modifier, and mouse input before/after the minimum floor;
- dirty-state backslide cannot activate;
- tap timeout/user-disable interruption cancels and blocks;
- release arriving before asynchronous capture startup completes;
- stale release cannot terminate a newer recording session;
- passive modifier bindings always pass events through;
- active keyed bindings suppress trigger down/repeat/up but never modifiers or unrelated keys;
- a terminal decision still suppresses the paired trigger up;
- wake/session/tap recreation resets all physical pressed-state;
- maximum-duration safety cancellation.

The adapter needs a smaller set of integration tests around synthetic `CGEvent` normalization and one signed-app smoke-test matrix: grant Input Monitoring; activate from several frontmost apps with side-specific modifier bindings; switch among right Option, left Option, and right Control; prove Command-L and Hyper-V are swallowed only with active filtering; revoke and restore permission; recover after sleep; and verify secure fields fail safely. TCC and suppression behavior cannot be fully proved by a pure unit test.

## Allowlist fit

The recommendation uses only CoreGraphics, AppKit/Foundation lifecycle notifications, and existing project/TCA boundaries. `Carbon.HIToolbox` is needed only for Apple's named virtual-key constants such as `kVK_RightOption`; it is an Apple framework, not a third-party dependency. Raw keycodes can instead remain isolated behind the adapter. Generalized matching and optional active filtering require no new dependency.

[^apple-hotkeys]: Apple Developer Forums, Apple DTS, [“How to properly realize global hotkeys on macOS?”](https://developer.apple.com/forums/thread/735223), Aug. 2023.

[^apple-sandbox]: Apple Developer Forums, Apple DTS, [“App with sandbox TCC deny IOHIDDeviceOpen”](https://developer.apple.com/forums/thread/724608), Feb. 2023.

[^apple-tap-create]: Apple, [`CGEvent.tapCreate`](<https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)>).

[^apple-session-tap]: Apple, [`CGEventTapLocation.cgSessionEventTap`](https://developer.apple.com/documentation/coregraphics/cgeventtaplocation/cgsessioneventtap).

[^apple-tap-callback]: Apple, [`CGEventTapCallBack`](https://developer.apple.com/documentation/coregraphics/cgeventtapcallback).

[^apple-tap-enable]: Apple, [`CGEvent.tapEnable`](<https://developer.apple.com/documentation/coregraphics/cgevent/tapenable(tap:enable:)>).

[^apple-flags-changed]: Apple, [`CGEventType.flagsChanged`](https://developer.apple.com/documentation/coregraphics/cgeventtype/flagschanged).

[^apple-event-flags]: Apple, [`CGEventFlags`](https://developer.apple.com/documentation/coregraphics/cgeventflags).

[^apple-secure-input]: Apple Technical Note TN2150, [“Using Secure Event Input Fairly”](https://developer.apple.com/library/archive/technotes/tn2150/_index.html).

[^apple-secure-owner]: Apple Developer Forums, Apple DTS, [“How to find culprit when stuck in SecureInput mode?”](https://developer.apple.com/forums/thread/726353).

[^hex-hotkey-model]: Hex, [`HotKey.swift`](https://github.com/kitlangton/Hex/blob/ca96427990249223cc31027d14c1f2c9ded57910/HexCore/Sources/HexCore/Models/HotKey.swift#L214-L311), commit `ca964279`.

[^hex-processor]: Hex, [`HotKeyProcessor.swift`](https://github.com/kitlangton/Hex/blob/ca96427990249223cc31027d14c1f2c9ded57910/HexCore/Sources/HexCore/Logic/HotKeyProcessor.swift#L94-L485), commit `ca964279`.

[^hex-tests]: Hex, [`HotKeyProcessorTests.swift`](https://github.com/kitlangton/Hex/blob/ca96427990249223cc31027d14c1f2c9ded57910/HexCore/Tests/HexCoreTests/HotKeyProcessorTests.swift), commit `ca964279`.

[^hex-monitor]: Hex, [`KeyEventMonitorClient.swift`](https://github.com/kitlangton/Hex/blob/ca96427990249223cc31027d14c1f2c9ded57910/Hex/Clients/KeyEventMonitorClient.swift), commit `ca964279`.

[^voiceink-monitor]: VoiceInk, [`ShortcutMonitor.swift`](https://github.com/Beingpax/VoiceInk/blob/69ed170c1d7f582e76f3f63a2ac2c30ddb3a2d75/VoiceInk/Shortcuts/ShortcutMonitor.swift), commit `69ed170c`.

[^whispering-bindings]: Epicenter, [`key-binding.ts`](https://github.com/epicenter-md/epicenter/blob/cb12bccfdeba2ba6bad65bd905d78ea92130e99d/apps/whispering/src/lib/utils/key-binding.ts#L191-L387), commit `cb12bcc`.

[^whispering-ptt]: Epicenter, [`push-to-talk.ts`](https://github.com/EpicenterHQ/epicenter/blob/cb12bccfdeba2ba6bad65bd905d78ea92130e99d/apps/whispering/src/lib/operations/push-to-talk.ts), commit `cb12bcc`.
