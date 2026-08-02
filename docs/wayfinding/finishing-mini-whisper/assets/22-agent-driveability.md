# Agent-driveability research

## Recommendation

Give every _semantic_ application element a stable AX identifier, a human-readable label, and a truthful current value where it has state. Use one lowercase, dot-separated namespace — for example, `miniwhisper.onboarding.download-model`, `miniwhisper.menu.sounds`, and `miniwhisper.pill.audio-level` — in both production accessibility modifiers/AppKit properties and XCUITest queries.

Do not gate every raw AX node. That would fail on AppKit's window controls, separators, SwiftUI hosting groups, decorative SF Symbols, and OS-owned menu items without finding a product regression. Instead, maintain a curated, per-surface accessibility manifest of MiniWhisper's semantic contract. An XCUITest gate should drive each deterministic state, walk the target surface's AX-backed XCUI tree, and assert the manifest's identifier, label, role, value/state, enabled state, and actionability. A separate `performAccessibilityAudit` is useful as a broad regression alarm, but cannot replace the manifest because it does not require stable identifiers or app-specific live values.

The pill requirement is feasible. The current unmodified nonactivating, transparent `NSPanel` already appeared to this out-of-process reader as an `AXWindow` with subrole `AXSystemDialog`; it did not need focus. Its semantic content is incomplete, not absent. Start with SwiftUI accessibility elements for phase, notice, device, and quantized audio level, plus an explicit accessible panel title/identifier. Retain a small AppKit `NSAccessibilityElement` bridge as the fallback only if those SwiftUI nodes do not remain separately visible and live-updating in the release build. Do **not** add `AXManualAccessibility`: it is a client-side Chromium/Electron escape hatch used by cua to materialize a disabled web tree, not an AppKit panel requirement.

## Method and scope

On 2026-08-02, `mise run build` succeeded. I launched the Debug app from this worktree and read its application AX tree from a separate terminal Swift process using `AXUIElementCreateApplication`, `AXUIElementCopyAttributeValue`, `AXUIElementCopyActionNames`, and recursive `AXChildren` traversal. The probe recorded role, title, description, identifier, value, menu mark, enabled state, focus, and action names. It is intentionally an out-of-process reader, rather than an in-process SwiftUI inspection.

The normal account already had the production nightly running at `/Applications/MiniWhisper.app`; it was never stopped. Debug PIDs from this worktree alone were stopped after each probe. For fresh onboarding, setting `HOME` was insufficient, but `CFFIXED_USER_HOME` isolated Foundation's Application Support location in `.build/agent-driveability-evidence/`; that let the actual Debug app show onboarding without changing the daily driver's markers. The test process inherited this terminal's existing Input Monitoring, Microphone, and Accessibility/PostEvent grants through responsible-process attribution, so all three permission rows reported Granted. This is evidence of AX exposure, not fresh-TCC behavior.

The throwaway probe was removed after the audit; raw dumps live only under ignored `.build/agent-driveability-evidence/` while this worktree exists. The important command shape was:

```sh
mise run build
CFFIXED_USER_HOME="$PWD/.build/agent-driveability-evidence/fresh-home" \
  "$PWD/.build/DerivedData/Build/Products/Debug/MiniWhisper.app/Contents/MacOS/MiniWhisper"
swift <temporary AX tree dumper> <debug-pid>
```

## Current AX audit

### Onboarding window

The real welcome window was exposed as `AXWindow` / `AXStandardWindow`, titled `Set Up MiniWhisper`, with an `AXHostingView` group. The title, explanatory strings, and button are readable today:

```text
AXWindow title="Set Up MiniWhisper"
  AXGroup subrole=AXHostingView
    AXImage description="Microphone" identifier="mic.fill"
    AXStaticText value="MiniWhisper"
    AXStaticText value="Fast, accurate dictation that runs on your Mac."
    AXButton description="Download Parakeet v2" enabled=1 actions=[AXPress]
```

Driving that button with `AXPress`, then choosing the existing Permissions rail button, produced these material nodes:

```text
AXButton description="Permissions" actions=[AXPress]
AXButton description="Speech Model, 22%" actions=[AXPress]
AXButton description="Try It" actions=[AXPress]
AXStaticText value="Input Monitoring"
AXStaticText value="Granted"
AXStaticText value="Microphone"
AXStaticText value="Granted"
AXStaticText value="Paste Access"
AXStaticText value="Granted"
AXProgressIndicator value=0.03103760697163358
```

So ordinary SwiftUI controls are already operable, and progress has a numeric AX value. The gaps are stable identity and semantic grouping: none of the onboarding buttons, permission rows, state texts, progress indicator, failure message, or try-it editor has an app-owned identifier. The rail's `Speech Model, 22%` description combines a changing value into a label, so it is neither a stable selector nor an independently addressable progress value. The AX identifiers on decorative SF Symbol images (`mic.fill`, `lock.shield`, `cpu`) are framework implementation details, not product identifiers. Decorative images should be hidden; named semantic elements should receive the app namespace instead.

### Menu-bar dropdown

The actual status extra appeared as:

```text
AXMenuBarItem subrole=AXMenuExtra description="MiniWhisper"
  identifier="MiniWhisperStatusItem" actions=[AXPress]
```

This identifier is already used successfully by `MiniWhisperUITests.testMenuContainsQuitItem`. Its menu exposed the current status text, actions, and checkmark state:

```text
AXMenuItem title="Ready · Parakeet v2 · Shure MV7" enabled=0
AXMenuItem title="Copy Last Transcript" identifier="copyLastTranscript" enabled=1
AXMenuItem title="Sounds" identifier="toggleSounds" menuMark="✓" enabled=1
AXMenuItem title="Launch at Login" identifier="toggleLaunchAtLogin" enabled=1
AXMenuItem title="Settings File…" identifier="openSettingsFile" enabled=1
AXMenuItem title="About MiniWhisper" identifier="showAbout" enabled=1
AXMenuItem title="Quit" identifier="terminate:" enabled=1
```

The same probe of a Debug launch with missing Input Monitoring showed the disabled status and repair action:

```text
AXMenuItem title="Input Monitoring is off, so MiniWhisper can't see your hotkey" enabled=0
AXMenuItem title="Open Input Monitoring Settings" identifier="repairDegradedState" enabled=1
```

This is usable by a title-driven agent, but it is not the requested durable contract. The current menu item identifiers are synthesized from Objective-C action selectors, including the unstable framework-looking `terminate:`; the status line has no identifier or separate state value; and a toggle exposes its boolean state only as `AXMenuItemMarkChar` (`✓` when Sounds is on), not `AXValue`. Explicitly set `NSMenuItem` accessibility identifiers and labels, and expose toggle state as an accessible Boolean/value in the manifest. The static status line needs its own identifier and `AXValue`/label split, so an agent can read state without parsing display punctuation.

The application and Apple menu bars found in the walk are OS-owned. They, separators, and the window-management menu are not MiniWhisper contract nodes and must be excluded from the gate.

### About panel

`NSApp.orderFrontStandardAboutPanel` produced an `AXWindow` / `AXDialog` with an empty title and private `_NS:` identifiers. It exposed the icon, app name, version, window buttons, and one empty static-text value. The passed credits/attribution text was not present as readable AX text in this capture:

```text
AXWindow subrole=AXDialog title="" identifier="_NS:154"
  AXImage description="MiniWhisper icon" identifier="_NS:10"
  AXStaticText value="MiniWhisper" identifier="_NS:32"
  AXStaticText value="Version 1.0 (1)" identifier="_NS:50"
  AXStaticText value=""
```

This is the clearest current all-elements failure: the About surface has no app-owned identity and does not prove the required Parakeet/FluidAudio attribution is agent-readable. The future gate should include an About surface contract. If the standard panel remains, verify a release build exposes its credits through AX; otherwise use a small custom About window/view with explicit accessible text rather than trying to name AppKit's private children.

### Dictation pill

A Debug run with isolated completed onboarding and `MINIWHISPER_BENCHMARK_ACTIVATION=1` triggered an actual recording pill. Despite `NonactivatingPillPanel.canBecomeKey == false`, `canBecomeMain == false`, `.nonactivatingPanel`, `.borderless`, and `ignoresMouseEvents == true`, the separate AX process read:

```text
AXWindow subrole=AXSystemDialog title="" focused=0
  AXGroup subrole=AXHostingView
    AXStaticText value="Shure MV7"
```

That is positive feasibility evidence: a nonactivating panel subtree is available to an out-of-process AX reader on this host. It also establishes the present gap precisely. There is no app identifier or title on the panel, no accessible phase (`recording`, `transcribing`, or notice kind), no accessibility node/value for audio level, no live flag for the red dot, and no accessible notice text in this recorded state. The blue dot and all five audio bars are visual-only custom drawing. The device name only leaks through because it is a visible `Text`.

The benchmark transitioned too quickly from stop to an unavailable-engine outcome to capture a transcribing tree; the source confirms that the `Transcribing…`, `No speech detected`, and `Copied — ⌘V to paste` text branches are also plain SwiftUI `Text` with no app-owned identifiers. Treat their exact release AX shape as still to verify, not as audited evidence.

## What cua-class agents consume

[cua's macOS driver](https://github.com/trycua/cua/blob/7ea91eb3f334/libs/cua-driver/rust/crates/platform-macos/src/ax/tree.rs#L390-L612) starts at an application AX element, unions `AXChildren` with `AXWindows`, and performs a bounded depth-first walk. That union matters: AppKit can omit background windows from application children, but cua also reads `AXWindows`. It reads `AXRole`, `AXTitle`, `AXDescription`, `AXIdentifier`, `AXValue` (falling back to placeholder), `AXHelp`, position/size, enabled and selected state, value description/minimum/maximum, and advertised action names. Its [Markdown serializer](https://github.com/trycua/cua/blob/7ea91eb3f334/libs/cua-driver/rust/crates/platform-macos/src/ax/tree.rs#L639-L699) emits role, title, value, description, identifier, help, and actions.

cua marks an element addressable when it has an advertised AX action, or when a standard editable/control role has writable `AXValue`, and excludes disabled nodes from addressability. It invokes `AXPress`, `AXShowMenu`, `AXPick`, `AXConfirm`, `AXCancel`, or `AXOpen` after rereading `AXEnabled`; it can write focus/value for inputs. See [the action dispatcher](https://github.com/trycua/cua/blob/7ea91eb3f334/libs/cua-driver/rust/crates/platform-macos/src/input/ax_actions.rs#L100-L142). This means MiniWhisper must not mistake a visible string for a complete contract: controls need an action and enabled state, while passive state needs a label, identifier, and fresh value even though it is intentionally not pressable.

A qualification: cua's structured `elements[]` currently folds identifier into its fallback label and does not return an independent identifier or action list; those richer fields are in its Markdown tree. Its [desktop discovery](https://github.com/trycua/cua/blob/7ea91eb3f334/libs/cua-driver/rust/crates/platform-macos/src/windows.rs#L59-L82) is limited to on-screen layer-zero windows, but a matched per-window state walk includes background `AXWindows`. An agent that only uses cua structured output needs descriptive labels as well as identifiers. An agent that consumes its Markdown receives both.

cua writes `AXManualAccessibility` (then `AXEnhancedUserInterface`) only for Chromium/Electron applications, so those applications materialize their normally lazy web accessibility tree. [That code](https://github.com/trycua/cua/blob/7ea91eb3f334/libs/cua-driver/rust/crates/platform-macos/src/ax/tree.rs#L232-L250) is not evidence that native AppKit needs the flag. The current pill probe is contrary evidence: its native `NSHostingView` subtree materialized without it.

## Recommended accessibility contract

### Identifier vocabulary

Use an `AccessibilityID` declaration owned by the app target — direct constants, not derived types — with these rules:

- prefix every ID with `miniwhisper`;
- use lowercase dot-separated surface and element names; no visible copy, selector names, symbols, indices, or state in the ID;
- one ID names one semantic element for its lifetime; state changes update value, not ID;
- label is concise and user-facing; `AXValue` is the current fact; help is optional only when it adds operating guidance;
- hide decorative graphics rather than assigning them selectors.

Initial examples:

| Surface             | Identifier                                                  | Label                          | Value/action                                                   |
| ------------------- | ----------------------------------------------------------- | ------------------------------ | -------------------------------------------------------------- |
| Menu extra          | `miniwhisper.menu.status-item`                              | MiniWhisper                    | `AXPress` opens menu                                           |
| Status row          | `miniwhisper.menu.status`                                   | Status                         | `Ready; Parakeet v2; Shure MV7`                                |
| Sounds              | `miniwhisper.menu.sounds`                                   | Sounds                         | `On` / `Off`; `AXPress`                                        |
| Launch at Login     | `miniwhisper.menu.launch-at-login`                          | Launch at Login                | `On` / `Off`; `AXPress`                                        |
| Copy                | `miniwhisper.menu.copy-last-transcript`                     | Copy Last Transcript           | enabled; `AXPress`                                             |
| Onboarding progress | `miniwhisper.onboarding.model-progress`                     | Model download                 | numeric fraction and human-readable percentage                 |
| Permission row      | `miniwhisper.onboarding.permission.input-monitoring`        | Input Monitoring               | `Granted`, `Needs settings`, or `Restart required`             |
| Permission action   | `miniwhisper.onboarding.permission.input-monitoring.action` | Grant Input Monitoring         | current action; `AXPress`                                      |
| Try-it editor       | `miniwhisper.onboarding.try-it.text`                        | Try dictation                  | current entered text; writable/focusable                       |
| Pill root           | `miniwhisper.pill`                                          | MiniWhisper dictation          | visible/hidden presentation state                              |
| Pill phase          | `miniwhisper.pill.phase`                                    | Dictation phase                | `Recording`, `Transcribing`, `No speech detected`, or `Copied` |
| Pill device         | `miniwhisper.pill.input-device`                             | Input device                   | `Shure MV7`                                                    |
| Pill level          | `miniwhisper.pill.audio-level`                              | Input level                    | nearest 10% bucket from 0–100%; min 0, max 100                 |
| Pill notice         | `miniwhisper.pill.notice`                                   | Dictation notice               | exact current message                                          |
| About attribution   | `miniwhisper.about.attribution`                             | Speech recognition attribution | complete visible attribution text                              |

The phase and notice are deliberately separate. During recording the notice can be absent, and after a no-speech result it can carry the exact text without forcing an agent to parse a compound root value. The root remains useful as a one-node summary for low-capability clients.

### SwiftUI and AppKit mechanisms

For native SwiftUI controls and text, apply `.accessibilityIdentifier`, `.accessibilityLabel`, and `.accessibilityValue` to the semantic leaf. Use `.accessibilityElement(children: .contain)` for a semantic group whose meaningful children must remain addressable, and `.ignore` only where the group is the sole contract element. Do not use the latter to silence the individual phase/level/notice contract. Apply `.accessibilityHidden(true)` to the red/blue dots, capsule border, and individual bar shapes once their meaning is represented by the level element.

AppKit standard controls already implement the [NSAccessibility protocol](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol); Apple says `NSView`, `NSWindow`, `NSCell`, and `NSDrawer` provide default implementations. Set the desired identifier/label/value on the standard element rather than replacing its role or action. `setAccessibilityIdentifier(_:)` is available from macOS 10.10, and Apple's documentation calls the identifier a unique ID often used in automated testing. Use it explicitly for `NSStatusBarButton`, the `NSPanel`, and every `NSMenuItem`; do not rely on the present selector-derived AX IDs.

For the pill, first make the SwiftUI content expose the four semantic leaves above, set an explicit accessibility title/identifier on the `NSPanel` and hosting root, then run the external probe against recording, transcribing, and both notices. The current panel's default AX window is proof that `isAccessibilityElement`/`AXManualAccessibility` changes are not preconditions. If a particular SwiftUI version coalesces the leaves or fails to notify clients of live updates, use a dedicated AppKit accessibility container: an `NSView`/hosting wrapper whose `accessibilityChildren()` returns stable `NSAccessibilityElement` objects for root, phase, device, level, and notice, with screen-coordinate frames and values backed by `PillFeature.State`. Keep the panel noninteractive; no fake press action is needed for passive nodes.

When manually managing those elements, post `NSAccessibility.Notification.valueChanged` after an observable value changes. Apple's documentation defines it specifically for value changes. Quantize and throttle the meter before posting — for example, whole percentages at 5–10 Hz — so a 60 Hz audio callback does not turn an assistive or agent observer into an event flood. Phase and notice changes should post promptly.

### Shared contract with XCUITest

`accessibilityIdentifier` is the correct shared selector. The existing UI test demonstrates the path with `app.statusItems["MiniWhisperStatusItem"]`. Migrate it to the namespace and use the same string constants in XCUITest. Querying by label is a fallback for a human-oriented client, not a test selector; labels legitimately change with copy or localization. XCUITest still needs assertions for labels and values, so the identifier does not become an excuse for silent or stale state.

`XCUIApplication.performAccessibilityAudit(for:_:)` is available on macOS 14+ according to [Apple's API documentation](<https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/performaccessibilityaudit(for:_:)>) (Xcode 16.3+). It audits standard categories such as sufficient element description, contrast, hit region, and dynamic type. It is worthwhile on the onboarding/About scenes, with narrowly documented platform exceptions if any arise. It cannot state that `miniwhisper.pill.audio-level` exists, that a menu checkmark becomes `On`, or that every app contract ID is unique, so it must be supplementary.

## Proposed test gate

Add an explicit test-only presentation driver before adding the coverage tests: launch arguments select an isolated, deterministic state for welcome, each onboarding step and permission status, healthy/degraded menu, About, and each pill presentation/value. It must use the same view/controller code as production, not a parallel mock screen. The existing benchmark environment flag is evidence that a narrow demo seam is acceptable, but it is not a stable state driver: it races and self-terminates.

Place the gate in the existing `MiniWhisperUITests` XCTest target because it must launch the app and exercise menu/window behavior. Keep the contract data as straightforward Swift declarations shared with the app target if target membership permits; otherwise duplicate only literal expectations in the UI test target and require a code review when UI text/state changes. For each scene:

1. launch with an isolated test state and wait for its root identifier;
2. walk only that surface's XCUI descendants and compare them to a small manifest of contract elements;
3. for each manifest entry require a nonempty identifier, label/title, expected role, and an appropriate current value; require an action and enabled state only for an interactive entry;
4. mutate the state where relevant — toggle Sounds/Launch at Login, advance model progress, and drive every pill phase/level bucket — then re-read the same identifier and require its value to change truthfully;
5. assert no duplicate IDs within the application tree and no undeclared _app-namespaced_ IDs, while intentionally ignoring framework/OS nodes;
6. run `performAccessibilityAudit` on stable normal windows as a separate test, not as the manifest's implementation.

This is a coverage gate that genuinely walks the AX-backed UI tree, but it asserts the product's curated semantics rather than every implementation node. It catches a removed identifier, an unlabeled new button, a stale meter, a non-operable action, or a missing pill notice. It does not fail because SwiftUI inserted a hosting group, AppKit renamed a private `_NS:` identifier, or macOS inserted a separator. That boundary is what keeps the gate useful rather than a false-positive factory.

A short spike must establish whether the UI-test runner can read the raw `AXUIElement` attributes and action names of its launched app without an explicit Accessibility TCC grant. If it can, use the same small in-test walker as this research probe for exact role/action/value assertions. If it cannot, retain XCUITest's own AX-backed element queries for the gate and run the raw out-of-process walker in a developer-only diagnostic command; do not make CI depend on a globally granted Accessibility pane. The manifest and state driver remain identical either way.

## Unknowns and human-only proof

- This audit ran the Debug app on macOS 26.5.2 through a terminal with inherited grants. A human must run the signed/notarized app Finder-first on a clean account and inspect it with Accessibility Inspector or an external AX probe after explicitly enabling that probe. That proves the shipped code identity, not responsible-process attribution.
- The pill has direct positive evidence for its recording state, but transcribing and each notice state still need a slow deterministic test driver and external-tree capture after the semantic elements land.
- The standard About panel did not expose credits in this capture. Verify the final release on supported macOS versions before deciding whether to keep it; a custom accessible About surface may be necessary.
- AX value formatting for `NSMenuItem.state` is platform behavior: this host reported `AXMenuItemMarkChar`, not `AXValue`. The implementation should explicitly test and document the chosen agent-facing On/Off representation rather than assume a checkmark is portable.
- The raw AX walker needs a test-runner privilege spike before it can be an in-repo CI gate. XCUITest and `performAccessibilityAudit` are available, but they are not proof that arbitrary `AXUIElementCopyAttributeValue` calls from that runner are TCC-independent.
- The raw tree exposed layout/decorative nodes. "All UI elements" should mean all user-meaningful controls and information, plus intentionally named semantic representations of visual-only state — not every capsule, divider, or render primitive. Requiring the latter contradicts native SwiftUI/AppKit tree behavior and would make the requested gate brittle.

## Implementation findings

The 2026-08-02 implementation resolved the test-runner spike as verdict **(b)**. The UI-test runner reported `AXIsProcessTrusted() == false`, and its per-PID `AXUIElementCreateApplication` walk failed reading `AXIdentifier` with `kAXErrorAPIDisabled (-25211)`. In the same test, XCUITest read `miniwhisper.pill.phase`, label `Dictation phase`, and value `Recording`. The curated gate therefore remains XCUITest-shaped; making CI depend on a global Accessibility grant would make it less portable, not more honest.

`XCUIApplication.performAccessibilityAudit` compiles and runs on this macOS target. In practice, `.sufficientElementDescription` reported an undescribed framework group despite the curated semantic children, and `.parentChild` reported a SwiftUI/AppKit parent-child mismatch. The stable gate uses `.elementDetection` and `.action`; the manifest owns app-specific descriptions, values, and hierarchy-independent identity.

Two SwiftUI details required narrower mechanisms than the initial recommendation implied. Applying `accessibilityValue` to the custom audio-bar group produced no out-of-process `AXValue`, while SwiftUI pruned zero-sized semantic views, so the pill uses a rendered 1×1 transparent `Text` leaf while hiding the visual bars. The verified raw AX and XCUTest clients poll values rather than subscribing to manually posted notifications, so the reducer updates that leaf only when the nearest ten-percentage-point bucket changes; it needs no timer or cancellation state. Native `ProgressView(value:)` retained its numeric AX value (`0.42`) even when given a human-readable `42%` accessibility value, so the manifest asserts the truthful numeric fraction rather than assuming AppKit exposes the requested formatting.

Final external probes resolved the menu-value uncertainty. Raw `AXUIElement` reads reported `miniwhisper.menu.sounds` and `miniwhisper.menu.launch-at-login` with `AXValue=On`, and the status row as `Ready; Parakeet v2; Test Microphone`; the explicit AppKit values are not limited to XCUITest's bridge on this host. The custom About surface exposed both attributions and its version as `AXStaticText` values. A real isolated-home capture driven through a left-Option hotkey reported the pill window as `Visible`, phase `Recording`, capture status `Live`, the actual input device, and a live percentage, while the installed nightly remained running on its separate right-Option configuration.
