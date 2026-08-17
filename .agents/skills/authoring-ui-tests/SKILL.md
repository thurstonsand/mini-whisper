---
name: authoring-ui-tests
description: Doctrine for MiniWhisper's XCUITest suite. Use before writing or modifying any UI test, when reviewing one, when the suite has slowed, when a run beeps, or when a UI test is flaky.
---

# Authoring UI tests

Every UI-test operation crosses a process boundary, so the suite's speed is decided at authoring time, not tuned afterward. Each gesture spends one of three currencies, and a test is well-written when every coin it spends buys a claim:

| currency                                                  | price            |
| --------------------------------------------------------- | ---------------- |
| process launch + terminate                                | ~2 s + ~1 s      |
| synthesized event (`typeText`, `typeKey`, `click`, hover) | ~150 ms per call |
| remote accessibility read (per-element property query)    | ~70 ms           |

## Where a new claim goes

In order of preference:

1. **A law in an existing group.** If a `Law`/`assertLaws` group already launches the scene family (see `MiniWhisperUITests/UITestSupport.swift`), append a law. Laws run in the order written and inherit the state the previous law left, so a new law opens by stating the ground it stands on — `require()` for the ground (a broken requirement stops the group and names the laws that went unasked), plain asserts for the claims (a broken claim records and lets the next law run).
2. **A new law group** when the scene family is new. One launch, many ordered claims.
3. **A new standalone test** only when the launch condition itself is the claim — a seeded file, a distinct environment, a degraded scene.

`presentScene` swaps a running app to another _state-presented_ scene (onboarding pages, pill states) for the price of a poll instead of a relaunch. Imperatively presented windows — settings — still need a fresh process.

## Authoring rules

- **Poll, never wait.** `waitForExistence`, `wait(for:)`, and anything built on `XCTNSPredicateExpectation` re-evaluate on a one-second timer and bill the full second even when the condition already holds. Use the polling helpers: `awaitExistence`, `awaitNonExistence`, `awaitHittable`, `assertValue`, `assertLabel`, `assertKeyboardFocus`, or `poll` directly.
- **Poll, then assert.** A keystroke is delivered before it is drawn, so a bare property read after an interaction is a race. After any interaction, reads go through the polling asserts — the fast helpers donate no settle time the way the old one-second waits accidentally did.
- **Batch keystrokes.** One `typeText` call carries any number of characters for one synthesis cost. Split only where a claim must land between keys.
- **Snapshot for tree-wide claims.** One `app.snapshot()` costs less than a single per-element query and answers for every element at once. Claims about many rows or a whole manifest read one snapshot, never a query per element.
- **Menus are closed deliberately.** A law that opens the status menu closes it, or the next law's open becomes a toggle. One Escape dismisses the whole tracking menu even from an expanded Quick Add — a second Escape lands nowhere and beeps. Use `closeStatusMenu`, which checks before escaping.
- **The AX tree lingers.** Custom menu-item views outlive the closed menu in the accessibility tree, so "menu closed" is a native item ceasing to be hittable, never a custom view ceasing to exist.
- **`clickImmediately` for stalled clicks inside menus.** XCUITest's `click()` can stall for seconds against a tracking menu's run loop (a measured 5.7 s on one submit button). CGEvent clicks work on elements _inside_ an open menu; they cannot _open_ one — the status-item click stays on XCUITest's synthesizer.
- **Screenshots prove paint.** Focus rings and appearance claims that AX attributes have lied about are checked in pixels (`focusRingPixelCount`). Screenshot capture is nearly free.

The quiescence swizzle in `UITestSupport.swift` already removes XCTest's 200–400 ms post-event idle wait; `launch()` asserts its selectors still exist, so an Xcode rename fails loudly. Nothing to do when authoring — just don't reintroduce waits that assume it.

## Run only what the change touched

The fastest test is one that never runs. The suite is sliced by surface — onboarding, menu, dictionary, history, settings, pill (`mise run test:ui:<surface>`) — so a change to one surface runs that slice, not the suite. A change spanning surfaces runs one union pass, `scripts/run_ui_tests --surfaces menu,dictionary`, never two slice tasks back to back (that repeats shared tests). While iterating on a single test, go finer: `scripts/run_ui_tests <Suite>/<test>`. The full `mise run test:ui` is for concluding a unit of work, not for every loop.

Slice membership lives with the tests: every test class conforms to `SurfaceTagged` and declares the surfaces it exercises. When one test's surfaces diverge from its class (Quick Add lives in the menu but writes the dictionary), split it into its own class rather than widening the class's tags.

## Verify before finishing

1. Run the slice(s) covering the change — every run, sliced or full, ends with the profiler report.
2. Read the report: it breaks each test into the three currencies; `scripts/profile_uitest_bundle .build/uitest.xcresult --activities <TEST_ID>` drills into one test and flags any step over a second. Name the currency being overspent before optimizing anything.
3. **Zero beeps.** The report lists every system beep with the test and activity in flight. A beep is an unhandled event — always a test defect or an app bug, never noise. Precedent: a beep found Escape unhandled on the history storage popover, a real production bug.

## Dead ends

Tried, measured, closed. Re-litigate only with new evidence.

- Tried **parallel test execution** to overlap tests, but couldn't: Xcode serializes macOS UI tests onto the one screen and keyboard — measured 524 s against a 493 s serial baseline.
- Tried **CGEvent keyboard typing** to beat the ~150 ms synthesis floor, but couldn't: the runner lacks the TCC accessibility grant, so key events silently vanish.
- Tried **CGEvent clicks to open the status menu** to skip the synthesized click, but couldn't: the event posts before the item's tracking session is listening; the menu never opens.
- Tried **Swift Testing** (`@Test`/`@Suite`) for its ergonomics, but couldn't: Xcode refuses `import Testing` in UI-test targets and `XCUIApplication` misbehaves under it (swift-testing #516).
- Tried **class-level `setUp` launch sharing** to reuse one process across test methods, but couldn't: no reset story between methods — the law harness is the working form of the idea.
- Tried **recovery relaunch inside a law group** to isolate a failed law, but couldn't: laws deliberately inherit state, so the relaunch reset the ground and guaranteed a cascading second failure — the gate/claim split replaced it.
- Tried **merging the history interaction tests** to save their launches, but couldn't: restoring scroll position between laws cost more than the relaunch.
