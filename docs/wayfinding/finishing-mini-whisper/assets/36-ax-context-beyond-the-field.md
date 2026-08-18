# AX context beyond the focused field

Research date: 2026-08-17. This is reconnaissance for a later cleanup-context enrichment, not a product decision. It used source/document research plus read-only `AXUIElement` reads against applications that were already running. It did not activate, launch, move, or send input to any application; it did not read or retain live text from the probe.

## Recommendation

AX can provide useful *bounded, visible-window* enrichment for applications that expose a real accessibility tree, but it is not a portable document-context API. Treat a future reader as a separate, opt-in capability from `FocusedTextContext`:

1. Start only with the then-frontmost application's `AXFocusedWindow`, never all applications or all of the application's windows by default.
2. Walk `AXChildren`/`AXVisibleChildren` with strict depth, node, byte, and elapsed-time caps. Collect only textual leaves that explicitly expose a string/range contract; preserve role, title/description, geometry, truncation, and the relationship to the focused element. Do not flatten an arbitrary tree into an unlabeled prompt.
3. Keep terminals out of text enrichment. Their title is small, optional metadata; their buffer is either a rendered grid or absent, not the program's document.
4. Keep whole-app/window scanning and cross-app reads out of delivery. They are expensive, privacy-expansive, and not needed for the initial focused-field cleanup. If later adopted, make the scope legible in configuration and send only the bounded extraction to the cleanup gateway.

The existing focused-field path is correctly narrow. It has the machinery to prewarm Chromium/Electron trees, but it intentionally does not retain a whole-window snapshot. No recommendation here changes that line.

## What AX actually grants

`AXIsProcessTrusted()` answers whether **the caller** is a trusted accessibility client; it does not restrict the client to the currently focused element.[^apple-trust] `AXUIElementCreateApplication(pid)` creates an application AX root for a supplied PID, and its `AXWindows`, `AXFocusedWindow`, and `AXFocusedUIElement` attributes are separate concepts. The macOS SDK defines a window's `AXChildren` as its first-order visual views, and `AXVisibleChildren` as the on-screen subset of a container's children.[^apple-app][^apple-attributes]

So, once trusted, a client can make an AX root for another *running* app by PID and ask it for its windows and descendants. A subsequent `AXUIElementCopyAttributeValue` or parameterized read is still allowed to fail: Apple documents `cannotComplete` for messaging failure and `notImplemented` where a target does not fully support AX.[^apple-copy][^apple-parameterized] The API exposes what each process chooses/materializes; it does not promise a complete document, off-screen rows, hidden tabs, or a stable ordering suitable for prose.

### Read-only local observation

The probe was a small Swift CLI using only `AXUIElementCopyAttributeValue`, `AXUIElementCopyParameterizedAttributeNames`, and `AXUIElementCopyAttributeValue` for `AXWindows`/`AXChildren`. It reported roles, character counts, supported parameterized-attribute names, and window titles only—never `AXValue` or `AXStringForRange` contents.

Against the already-running Ghostty (PID 99475), the trusted client received two `AXWindow` objects from `AXWindows`, then walked both trees without changing focus. Each contained an `AXTextArea` advertising `AXStringForRange`; their declared character counts were 9,716 and 9,155. The trees also contained `AXStaticText`, controls, groups, scroll areas, and (in one window) a tab group. This is direct evidence that AX reads can reach an application's nonfocused window and siblings. It is **not** evidence that every native app, hidden window, tab, or terminal exposes the same shape. The intentionally omitted window titles carried terminal-session metadata, which is itself a privacy cost.

## Terminals: readable does not mean document context

The current `TerminalBundleIDs` policy rejects Terminal.app, iTerm2, Ghostty, kitty, Alacritty, and related terminal-shaped bundles as `gridSemantics`. That remains the defensible default.[^project-terminal-policy]

| Emulator | AX screen/text result | Title signal | Context verdict |
| --- | --- | --- | --- |
| Terminal.app | A prior local probe on macOS 26.5.2 found an `AXTextArea` whose 2,131-character value was the visible terminal grid while nvim occupied the alternate screen. It even supplied a nonzero cursor-shaped selected range, proving that a caret does not distinguish a source document from a TUI render.[^ticket-20] Apple documents that Terminal window/tab titles can include active process, shell command, working directory, or a custom name—not a canonical foreground-program identity.[^terminal-titles] | Useful only as configured UI metadata. | Do not consume buffer or infer nvim/tmux/TUI state from its title. Revalidate any future Terminal build independently. |
| iTerm2 | iTerm2 implements its terminal view as an accessibility text area, builds AX text from terminal lines, and supports value/range reads. Its source caps the exposed lines at the accessibility-line setting and data-source availability, so this is terminal-buffer data, not a guarantee of all scrollback or an editor document.[^iterm-text][^iterm-limit] | Window/session naming has several competing sources. OSC 0/2 outranks profile/fallback rules, and tmux integration has separate precedence.[^iterm-titles] | Readable grid/buffer is not LLM document context. Keep unavailable. |
| Ghostty | Ghostty exposes an `AXTextArea`, `AXValue`, character count, visible range, and `AXStringForRange`. Its source fills the cache by calling `ghostty_surface_read_text` from `GHOSTTY_POINT_SCREEN` top-left to bottom-right: current screen, not scrollback or an underlying program document.[^ghostty-ax] The local metadata-only probe above corroborates that its two existing windows expose range-capable text areas. | Ghostty describes the surface title as PTY-defined; terminal escape sequences can change it, and an empty title falls back to PWD when available.[^ghostty-title] | Keep unavailable. Title and grid can enrich a user-visible diagnostic, but not semantic cleanup input. |
| kitty | kitty deliberately creates an AX text area for dictation, but its macOS implementation returns zero characters and an empty AX value, with an explicit comment that the terminal buffer is not exposed. It may return selected text, which is not a screen-buffer contract.[^kitty-ax] | No buffer-based context path was found. | Negative case: no buffer walk to use. |
| Alacritty | No primary-source macOS AX text implementation was found in this research. Its manual documents title behavior, not `AXValue`/range exposure. Treat screen-buffer readability as unknown until measured against a running version; do not extrapolate from Ghostty or iTerm2.[^alacritty-title] | The title defaults to `Alacritty`; `dynamic_title` permits a terminal application to change it.[^alacritty-title] | Keep unavailable unless a version-specific probe proves document, rather than grid, semantics. |

### `AXTitle` is conventional transport, not a foreground-program contract

Terminal emulators commonly map terminal title escape sequences into window/tab UI, so `AXTitle` can expose a shell, directory, multiplexer's session/window, editor filename, or a user-configured string. It has no standardized meaning such as “the foreground program.” The emulator owns its mapping and precedence; the program owns whether it emits a title at all.

In particular, Neovim's `title` option defaults **off**. When enabled, it updates the terminal/GUI title using a configurable `titlestring`, whose default includes filename/path and `Nvim`.[^nvim-title] tmux's `set-titles` likewise defaults **off** and its `set-titles-string` is configurable (default: session/window metadata plus terminal title).[^tmux-title] Those are explicit counterexamples to treating the title as a reliable detector. A TUI may set a title, inherit its shell's title, leave a stale title behind, or emit arbitrary OSC text.

The safe conclusion is narrower: a bounded `AXTitle` can be optional provenance for a terminal context record, perhaps useful to a human or as a weak LLM hint, but it must never select the parser, assert what program owns the terminal, or authorize reading its grid as source text.

## Native focused-window tree walks

A Cocoa-style AX tree can offer far more than the focused text field: static labels, sibling fields, outline/table rows, document areas, tab labels, and accessibility descriptions. `AXChildren` is expressly the visual hierarchy, and `AXVisibleChildren` identifies the on-screen subset.[^apple-attributes] Those leaves may expose `AXTitle`, `AXDescription`, `AXValue`, or text-suite parameterized attributes such as `AXStringForRange`; the SDK declares the latter but individual roles decide whether they implement it.[^apple-attributes]

That is a capability, not a uniform result:

- A native text editor often puts an entire document in a single `AXTextArea`. The existing focused-field probe already observed complete range contracts in TextEdit, Notes, and Xcode, but that proves each target/version only; it does not say which *other* document panes or sidebars they expose.[^ticket-20]
- Static sibling text is commonly reachable as `AXStaticText`/`AXValue`, while lists and outlines may virtualize only visible rows. `AXVisibleChildren` makes that distinction explicit in the platform contract.[^apple-attributes]
- An AX text value can be a control's state rather than prose—Apple calls `AXValue` a catch-all user-modifiable setting, and its type depends on the role.[^apple-attributes] A generic walk must inspect role/type and must not concatenate every value it sees.
- Tree order is visual/accessibility structure, not document order. A sidebar, toolbar, search result, and editor can all be siblings. An LLM needs source/role boundaries and a deliberately small chosen region, not an unlabelled dump.

A later prototype should test a target matrix with a frontmost, visible native window and assert: node cap/timeout, extraction byte cap, roles accepted, text ordering, virtualized-row behavior, protected-field exclusion, and whether the proposed local region changes cleanup quality. It should not start by scanning entire apps.

## Chromium and Electron

`ChromiumAccessibility.prewarmFrontmostApp()` is a **tree-enablement/warm-up** path, not a whole-window context reader. It acts only on the frontmost app, detects Electron/Chromium by the renderer helper in its bundle, and records success per process instance. For Electron it writes `AXManualAccessibility = true` to the application AX root; for Chromium browsers it first tests focus then breadth-first traverses application descendants, capped at 5,000 nodes. The traversal reads roles/children only and discards all text. `FocusedFieldReader` subsequently follows the focused-descendant chain only, stopping after 16 levels and inspecting up to 64 children at a level.[^project-chromium][^project-reader]

Electron documents that a third-party macOS client can set `AXManualAccessibility` on an application's AX element, and that manual accessibility exposes Chrome's accessibility tree.[^electron-doc] Electron's implementation makes that app-level attribute settable and maps it to complete screen-reader mode; merely reading an accessibility role establishes only a basic/native mode.[^electron-source] Thus the enablement is process/tree-scoped, not intrinsically focused-field-scoped.

That means a later reader can use the prewarmed visible Electron tree as input to a bounded focused-window walk. It does **not** make “the whole Chromium window is readable” a guarantee:

- Chromium applies a changed process accessibility mode across `WebContents`, but its implementation does not apply it immediately to hidden contents; they receive the effective mode when shown.[^chromium-source]
- Canvas editors can still expose only a keystroke sink. The existing Google Docs measurement is exactly that: a range-capable `AXTextArea` that permanently returns two zero-width spaces rather than document text.[^ticket-20]
- Chrome 151 on this host rejected both documented attribute writes, while the existing bounded background traversal woke its tree. That is an empirical compatibility accommodation in `ChromiumAccessibility`, not a Chromium API guarantee.[^ticket-20][^project-chromium]

So existing code provides a useful prerequisite for visible Chromium/Electron tree inspection, but no extraction policy, privacy boundary, or latency budget for it. A whole-window reader should reuse the once-per-PID prewarm state and run asynchronously, not add a traversal to delivery.

## Other windows and other applications

**Reachable:** Yes, for any running app that exposes a tree. The trusted-client scope plus `AXUIElementCreateApplication(pid)` and `AXWindows` makes focus an application convention, not an authorization boundary.[^apple-trust][^apple-app][^apple-attributes] The local Ghostty probe reached a second, nonfocused window without activation. It is technically possible to enumerate many running applications from `NSWorkspace` and inspect their AX roots.

**Not guaranteed:** Background, hidden, minimized, off-screen, or never-materialized content can be missing, stale, virtualized, or expensive to construct. Chromium explicitly delays accessibility-mode application for hidden `WebContents`; the platform's separate `AXVisibleChildren` contract also warns that visibility is a real distinction.[^chromium-source][^apple-attributes] An AX client must accept unsupported attributes, process exit, and `cannotComplete` without retrying its way into the delivery path.[^apple-copy][^apple-parameterized]

**Cost:** Cross-window/app reads turn the existing Paste Access permission into broad content collection. A future implementation could read exposed messages, source code, document text, file names, and labels outside the paste target, then potentially send them to the configured cleanup endpoint. Traversing remote AX objects is also O(nodes × attribute reads), with no platform-level global deadline; existing focused capture's 60 ms budget exists precisely because even the first AX IPC handshake can be costly.[^project-reader][^ticket-20] This is not a harmless fallback. It needs a named user-facing scope, hard bounds, secure-field filtering, no logging of contents, a fail-closed unavailable result, and an explicit decision about cross-app transmission.

## Prior art

No audited dictation app establishes a portable whole-window AX-context pattern:

- Hex's paste client asks only for the system-wide focused element, probes its value/selected text, and writes selected text; it does not walk an application window for cleanup context.[^hex]
- VoiceInk separates selected-text capture from whole-window context. Its ScreenCaptureKit service uses AX only to identify the focused window title/frame, then obtains whole-window text through screen capture and OCR, rather than assuming a complete AX tree.[^voiceink-screen][^voiceink-selected]
- Whispering’s current design document labels AX selected-text capture as a later spike; it is not existing whole-window AX extraction prior art.[^whispering]

That reinforces the capability-driven recommendation: use AX where a target proves it has semantically useful text, but retain a separate OCR path for visual context and never fabricate equivalence between the two.

## Sources

[^apple-trust]: Apple, [AXIsProcessTrusted](https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted), accessed 2026-08-17.
[^apple-app]: Apple, [AXUIElementCreateApplication](https://developer.apple.com/documentation/applicationservices/axuielementcreateapplication(_:)), accessed 2026-08-17.
[^apple-copy]: Apple, [AXUIElementCopyAttributeValue](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue), accessed 2026-08-17.
[^apple-parameterized]: Apple, [AXUIElementCopyParameterizedAttributeValue](https://developer.apple.com/documentation/applicationservices/1461203-axuielementcopyparameterizedattr), accessed 2026-08-17.
[^apple-attributes]: Apple, [`AXAttributeConstants.h`](https://github.com/apple-oss-distributions/HIServices/blob/main/HIServices/Accessibility/AXAttributeConstants.h) (the local macOS 26 SDK additionally inspected: `kAXWindowsAttribute`, `kAXFocusedWindowAttribute`, `kAXChildrenAttribute`, `kAXVisibleChildrenAttribute`, and text-suite parameterized attributes), accessed 2026-08-17.
[^terminal-titles]: Apple, [Change the title shown in a Terminal window](https://support.apple.com/guide/terminal/trml15228/mac) and [Change Profiles Tab settings](https://support.apple.com/guide/terminal/trmltab/mac), accessed 2026-08-17.
[^iterm-text]: iTerm2, [`PTYTextView.m` 7114–7232](https://github.com/gnachman/iTerm2/blob/69808ace4599/sources/TerminalView/PTYTextView.m#L7114-L7232) and [`iTermTextViewAccessibilityHelper.m` 246–333](https://github.com/gnachman/iTerm2/blob/69808ace4599/sources/Accessibility/iTermTextViewAccessibilityHelper.m#L246-L333), inspected 2026-08-17.
[^iterm-limit]: iTerm2, [`PTYTextView.m` 7368–7385](https://github.com/gnachman/iTerm2/blob/69808ace4599/sources/TerminalView/PTYTextView.m#L7368-L7385), inspected 2026-08-17.
[^iterm-titles]: iTerm2, [Names and Titles in iTerm2](https://github.com/gnachman/iTerm2/blob/69808ace4599/docs/names-and-titles.md#title-resolution), inspected 2026-08-17.
[^ghostty-ax]: Ghostty, [`SurfaceView_AppKit.swift` 223–275](https://github.com/ghostty-org/ghostty/blob/159cf6d7e7fe/macos/Sources/Ghostty/Surface%20View/SurfaceView_AppKit.swift#L223-L275) and [2320–2415](https://github.com/ghostty-org/ghostty/blob/159cf6d7e7fe/macos/Sources/Ghostty/Surface%20View/SurfaceView_AppKit.swift#L2320-L2415), inspected 2026-08-17.
[^ghostty-title]: Ghostty, [`SurfaceView_AppKit.swift` 8–19](https://github.com/ghostty-org/ghostty/blob/159cf6d7e7fe/macos/Sources/Ghostty/Surface%20View/SurfaceView_AppKit.swift#L8-L19) and [`stream_handler.zig` 925–947](https://github.com/ghostty-org/ghostty/blob/159cf6d7e7fe/src/termio/stream_handler.zig#L925-L947), inspected 2026-08-17.
[^kitty-ax]: kitty, [`cocoa_window.m` 2035–2110](https://github.com/kovidgoyal/kitty/blob/e7ccaa429d85/glfw/cocoa_window.m#L2035-L2110), inspected 2026-08-17.
[^alacritty-title]: Alacritty, [`alacritty.5.scd` 155–171](https://github.com/alacritty/alacritty/blob/1b2b36a64e88/extra/man/alacritty.5.scd#L155-L171), inspected 2026-08-17.
[^nvim-title]: Neovim, [`options.txt` 7044–7093](https://github.com/neovim/neovim/blob/master/runtime/doc/options.txt#L7044-L7093), inspected 2026-08-17.
[^tmux-title]: tmux, [`options-table.c` 968–986](https://github.com/tmux/tmux/blob/master/options-table.c#L968-L986), inspected 2026-08-17.
[^electron-doc]: Electron, [Accessibility: Within third-party software / macOS](https://github.com/electron/electron/blob/d36eebfc2e1a/docs/tutorial/accessibility.md#within-third-party-software), inspected 2026-08-17.
[^electron-source]: Electron, [`electron_application.mm` 220–319](https://github.com/electron/electron/blob/d36eebfc2e1a/shell/browser/mac/electron_application.mm#L220-L319), inspected 2026-08-17.
[^chromium-source]: Chromium, [`browser_accessibility_state_impl.cc` 735–850](https://github.com/chromium/chromium/blob/main/content/browser/accessibility/browser_accessibility_state_impl.cc#L735-L850), inspected 2026-08-17.
[^project-terminal-policy]: [`Packages/FieldContext/Sources/FieldContext/TerminalBundleIDs.swift`](../../../../Packages/FieldContext/Sources/FieldContext/TerminalBundleIDs.swift), inspected 2026-08-17.
[^project-chromium]: [`MiniWhisper/ChromiumAccessibility.swift`](../../../../MiniWhisper/ChromiumAccessibility.swift), inspected 2026-08-17.
[^project-reader]: [`MiniWhisper/FocusedFieldReader.swift`](../../../../MiniWhisper/FocusedFieldReader.swift), inspected 2026-08-17.
[^ticket-20]: [Ticket 20 AX probe](20-context-capture.md), especially “Target matrix,” “Canvas editors,” and “Chromium activation,” measured 2026-08-02.
[^hex]: Hex, [`PasteboardClient.swift` 345–382](https://github.com/kitlangton/Hex/blob/881c46f236f5/Hex/Clients/PasteboardClient.swift#L345-L382), inspected 2026-08-17.
[^voiceink-screen]: VoiceInk, [`ScreenCaptureService.swift` 40–190](https://github.com/Beingpax/VoiceInk/blob/304db118f655/VoiceInk/Services/ScreenCaptureService.swift#L40-L190), inspected 2026-08-17.
[^voiceink-selected]: VoiceInk, [`SelectedTextService.swift` 1–38](https://github.com/Beingpax/VoiceInk/blob/304db118f655/VoiceInk/Services/SelectedTextService.swift#L1-L38), inspected 2026-08-17.
[^whispering]: Whispering, [voice-cursor intent-in-context specification](https://github.com/epicenter-so/epicenter/blob/210c3d3691a0/apps/whispering/specs/20260628T003033-voice-cursor-intent-in-context.md#L25-L70), inspected 2026-08-17.
