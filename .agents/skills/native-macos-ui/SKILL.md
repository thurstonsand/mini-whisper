---
name: native-macos-ui
description: Use when building or reviewing any SwiftUI surface in MiniWhisper — settings, windows, panes, lists, the pill, onboarding. Encodes what makes an AppKit/SwiftUI surface look native rather than assembled.
---

# Native macOS UI

Adapted for macOS from [SwiftUI Design Principles](https://github.com/arjitj2/swiftui-design-principles) by Arjit Jaiswal (MIT), whose rules are written for iOS. The philosophy carries over unchanged; most of the specifics do not, because macOS has different containers, different metrics, and a much stronger set of built-in controls.

## The philosophy

**Restraint over decoration.** Every pixel earns its place. Fewer colors, fewer font sizes, fewer spacing values, fewer words — used consistently. Custom gradients, decorative borders, and bespoke dividers are noise. System components and semantic colors are harmony.

**Attention is scarce.** Interface copy should be shorter than feels comfortable. One clear label beats a label plus a footer explaining the label.

**If AppKit has the control, use the control.** The single largest source of un-native appearance is hand-drawing something the system already draws — and drawing it slightly wrong.

## Let the container do the layout

macOS containers carry the platform's metrics. Fighting them is what makes a window look assembled.

- `Form` + `.formStyle(.grouped)` owns section spacing, row height, and label alignment. Do not add `.padding` to its rows.
- `LabeledContent` for any label/value pair. Never `HStack { Text; Spacer; value }` — it misaligns against every real row on screen.
- `Section("Name")` for headers. No uppercase, no tracking, no custom font.
- `Table` for tabular data, not a `List` of hand-built `HStack`s. It brings column headers, sorting, alternating rows, and correct row metrics.
- `.inspector` or a trailing pane for detail. Splitting one pane into two stacked scroll regions with a draggable divider is almost always the wrong answer.
- `safeAreaBar` for a caption or button bar pinned to an edge, not `safeAreaInset` plus a hand-built `.background(.bar)` and `Divider()`. It brings the material and the separator itself, and under Liquid Glass it brings the right ones.
- One scrolling content region per pane.

## Animating rows

A `List` on macOS only honours an exit animation that is already in the update transaction when it reaches its hosted rows. A value-scoped `.animation(_:value:)` on the **row** is silently ignored for a change that arrives from an async task, so transient state reaching the row itself — a copied flash, a fading confirmation — must be cleared inside `withAnimation` at the mutation site. Outside a `List` both spellings work, which is what makes this easy to get wrong.

Attached to a **leaf view inside** the row, a value-scoped `.animation(_:value:)` does animate an async change: History's copy confirmation fades its badge and its duration on plain opacity modifiers, cleared by an ordinary state mutation from a clock effect, and both transitions were captured mid-fade. Animating a child's opacity resolves inside the row's own body rather than through the transaction `List` hands its rows, which is the line between the two cases. Prefer the leaf spelling — it keeps presentation timing in the view — and keep `withAnimation` at the mutation site as the fallback for anything the row must animate as a whole.

A value-dependent animation is how one piece of state gets two timings: `.animation(isCopied ? nil : .easeOut(duration: 0.5), value: isCopied)` arrives instantly and leaves slowly, because SwiftUI picks the animation from the value being moved to.

Where two things swap in one slot, stagger them rather than crossfading: two texts at half opacity in the same place is unreadable for the length of the transition. Fade the outgoing one fully out, then bring the incoming one in.

## Type

Use text styles, never fixed point sizes: `.body`, `.callout`, `.caption`, `.headline`. The system scales them, adapts them, and keeps them consistent with every other app. A fixed `.font(.system(size: 15))` is a number that will be wrong somewhere.

At most three distinct styles in a pane. If a fourth is needed, the layout is doing too much.

## Color

Semantic only: `.primary`, `.secondary`, `.tertiary`, `.separator`, `.windowBackground`, `.selection`, `.accentColor`. No hardcoded values, no opacity ladders. Status color is meaningful, not decorative — `.green` and `.orange` mean something in a capability row and nothing on a label.

## Glass

macOS 26's Liquid Glass arrives **automatically** for stock components when built against the macOS 26 SDK: sidebars float, toolbar items and the search field become glass, `Form` sections and sheets take the new radii. A window assembled from system containers is already adopting it, and needs no glass API at all.

- **Never apply `glassEffect` to content.** The HIG is explicit — glass belongs to the navigation layer floating above content, not to rows, cells, or anything in a list. Applied to a table row it renders as a stray outline, which is the rule made visible.
- `GlassEffectContainer`, `glassEffectID`, and `.buttonStyle(.glass)` exist for custom floating chrome. This app has none. Reach for them only when something genuinely hovers above the content layer.
- `hoverEffect` and `listRowHoverEffect` are **unavailable on macOS**. A hand-drawn hover background is not a workaround here, it is the only option.
- Concentric radii (`ConcentricRectangle`, `containerShape`) apply when a shape nests inside a rounded container. A row highlight inside a plain list has no such container, so a fixed radius is right in kind — match it to the selection highlight the same list draws, which is **8**, not the 6 that looks correct in isolation.

## Window chrome and focus

Both of these were regressions before they were rules. Chrome and focus belong to the window; panes that own either will break it whenever the pane changes.

- **Chrome must not depend on which pane is selected.** SwiftUI only materialises the window toolbar while some view contributes to it, and titlebar/sidebar geometry follows the toolbar's existence — so a pane whose `.searchable` is the only contribution changes the window's shape when the user navigates away. Pin it window-wide: a persistent `NSToolbar` on the window plus an always-present zero-size keeper `ToolbarItem`. Put the keeper in `placement: .navigation`: a zero-size sibling in the trailing group still widens a real button's glass capsule and pushes its glyph off-centre.
- **Column focus is carried by a persistent host, never by a pane's Form/List root.** A grouped `Form` resolves focus to its internal scroll responder, and replacing the detail subtree kills the focus target — `@FocusState` silently goes nil and keyboard paint dies. Wrap the swapping content in one stable container that owns `.focusable()`, `.focused(…)`, and key routing; panes are content.
- Initial focus assigns on the window's actual `didBecomeKey` (one-shot), not `onAppear` — and audit for `makeFirstResponder(nil)` calls that erase it after presentation.
- **A page that opens focused claims focus once, when the field exists.** The working spelling is a single `.task { await Task.yield(); focus = .target }` on the field itself: the yield puts the assignment after AppKit has chosen its own first responder, and a `@FocusState` assignment aimed at a view SwiftUI has not built yet lands nowhere. `.defaultFocus(_:_:priority:)` is **not** the cure — it fires when a focus container appears, so it does nothing for a page swapped into an already-presented window, which is what every mid-flow onboarding transition is. Measured on the try-it page: `.defaultFocus(priority: .userInitiated)` alone left the field unfocused on entry *and* after the model finished behind it; the yield-then-focus task passed both. What must stay banned is *stacking* assertions — `onAppear` plus a `didBecomeKey` hook plus a responder walk plus the task is four writers racing over one rule, and honest paint on dishonest focus is what a stray ring on entry actually is.
- **SwiftUI key handling is deaf until a SwiftUI view owns focus.** On entry the AppKit window is the responder, so `.onKeyPress` never fires and native traversal picks its own first stop. A page that deliberately opens *unfocused* therefore has nothing to hear its first Tab: route that key with a window-scoped local event monitor and let the page name its own cycle. Never leave the first keypress without a listener.
- Containers that hold a column-focus role wear `.focusEffectDisabled()`, or the system rings the entire scroll area. The interaction model's own paint is the focus indicator.

## Controls

- Never hand-draw a control. No rounded-rect "keycaps" as buttons, no custom toggles, no bespoke progress bars. (Keycap boxes *displaying* a recorded chord inside a real `Button` are content, not a control — that one is deliberate.)
- `Toggle` keeps its own label. `.labelsHidden()` is for when the enclosing row already labels it, not a layout convenience.
- Exclusive options are one `Picker` with one selection, never several toggles that can contradict each other.
- Buttons say what they do: `Copy`, `Delete`, `Choose…`. A trailing ellipsis means a further dialog follows; without one, the action happens immediately.

## Copy

- A `Section` footer must prevent a mistake or be deleted. It is not a place for tone.
- Labels are nouns or short verb phrases, sentence case, no trailing punctuation.
- Say the consequence, not the mechanism: "Keep audio for" beats "Audio retention TTL."

## Checklist

- [ ] No fixed font sizes; three text styles or fewer per pane
- [ ] No hardcoded colors or opacity values
- [ ] No hand-drawn control that AppKit already provides
- [ ] `LabeledContent` for every label/value row
- [ ] `Form` rows carry no manual padding
- [ ] One scrolling region per pane
- [ ] Every footer prevents a mistake
- [ ] Every ellipsis means a dialog follows
- [ ] Window looks correct at its minimum size, not only at its ideal one
- [ ] No `glassEffect` anywhere in the content layer
- [ ] Edge captions and button bars use `safeAreaBar`, not a hand-built bar
- [ ] Transient state cleared from a `Task` animates via `withAnimation` at the mutation site
