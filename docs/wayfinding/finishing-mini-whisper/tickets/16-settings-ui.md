---
status: closed
type: prototype
blocked-by: [8]
---

# Settings UI (stake 6)

## Question

A real settings surface over the JSON file (which stays authoritative). Scope: which fields graduate from hand-editing, window vs. menu popovers, and whether the sound-effects popup from the MVP grows into it.

## Notes

- **Promoted ahead of [History](11-history.md).** History's grilling reached its UI question and found it undecidable without this one: the history view belongs in the same window as the keybind editor, and designing it ad hoc first would mean designing it twice. History now blocks on this ticket and inherits whatever shell it establishes.
- So this ticket owns more than configuration — it owns **the app's first window**, and the layout question is where history sits relative to settings, not merely which fields graduate from the JSON file. Read History's _Decisions carried_ section before designing; the retention presets and audio toggle are settled and need a home.
- Open with [Settings information architecture](28-settings-information-architecture.md), the research ticket firing in parallel.
- The [competitor audit](../assets/25-competitor-feature-audit.md) is also relevant background, though it covered features rather than organization.
- **Retyped from grilling to prototype.** The session's job is mock-ups to react to, covering the window's look and feel _including the history view_, so history's real implementation can be built from a picture rather than from prose. The research recommends one resizable sidebar window — History, Dictation, Model, General — which is the first thing the mock-ups should test rather than assume.

## Inventory

What the window must hold, so the mock-ups have real content instead of lorem ipsum. Shipped items exist today and are homeless or menu-bound; settled items are decided but unbuilt; staked items arrive with a later ticket and only need a plausible seat.

| item                                                                                                                                               | state                                    | source                                                                 |
| -------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- | ---------------------------------------------------------------------- |
| Hotkey binding — needs a recorder, not a text field                                                                                                | shipped (settings.json)                  | MVP                                                                    |
| Sound cues — per-cue selection, not one on/off switch                                                                                              | shipped as on/off (menu + settings.json) | MVP, [Sound design](24-sound-design.md)                                |
| Launch at login                                                                                                                                    | shipped (menu)                           | MVP                                                                    |
| Input device — read-only label today                                                                                                               | shipped (menu, pill)                     | MVP                                                                    |
| Model state, download progress, retry                                                                                                              | shipped (menu repair, onboarding)        | MVP                                                                    |
| Transcript retention TTL — never / 1 day / 7 / 30 / 90 / year / forever, default forever                                                           | settled                                  | [History](11-history.md)                                               |
| Audio retention TTL — same presets, default 3–7 days; **`never` is the off switch**                                                                | settled                                  | [History](11-history.md)                                               |
| The history list itself — recovery first, replay and correction after; likely holds _Copy Last to Clipboard_ rather than a separate paste-last row | settled                                  | [History](11-history.md), [Paste-last](12-paste-last-recovery.md)      |
| Paste-last binding — a second chord through the same gesture machine                                                                               | staked                                   | [Paste-last](12-paste-last-recovery.md)                                |
| Dictionary word list, plus quick-add from the menu                                                                                                 | staked                                   | [Dictionary](13-dictionary.md)                                         |
| Engine selection, if a second engine survives                                                                                                      | staked                                   | [Second engine](15-second-engine.md)                                   |
| Cleanup endpoint, model, credential, prompt, on/off — enough surface to earn its own pane                                                          | staked                                   | [LLM cleanup](18-llm-cleanup.md)                                       |
| Ducking on/off, and pause versus volume                                                                                                            | staked                                   | [Audio ducking](21-audio-ducking.md)                                   |
| Permission, device, and model state shown as settings rows — probably _instead of_ re-entering onboarding                                          | staked                                   | [Onboarding capability recovery](30-onboarding-capability-recovery.md) |
| Ranked microphone fallback — not merely a device picker                                                                                            | unstaked                                 | [research](../assets/28-settings-information-architecture.md)          |

The credential row is the only one with a real constraint attached: it displays masked and stays editable in place, but an API key does not belong in a plaintext JSON file, so the settings file stops being the whole persistence story the moment cleanup lands. Keychain is the obvious answer and has not been decided.

Staked rows are seats, not commitments — the mock-ups should show that a pane can hold them later without being rebuilt, which is a different test from showing them today.

### Rows that were cut, and why

- **Audio storage on/off** collapsed into the audio TTL, because `never` _is_ off. That removes a control and, more usefully, removes an open question: the retention pass already deletes anything past its TTL, so choosing `never` deletes existing audio through the ordinary mechanism instead of a special case. See [History](11-history.md).
- **Streaming on/off** gets no control at all. It is selected by gesture — hold does not stream, latch does. See [Streaming](19-streaming.md).
- **Re-run onboarding** may get none either. The leaning is that onboarding stays a one-time flow and settings simply _shows_ the capability state it established, which is why the row above reads as state rather than as an action. See [Onboarding capability recovery](30-onboarding-capability-recovery.md).

## Resolution

The window is settled, and the artifact that settles it is runnable: [`spikes/settings-mockup/SettingsMockup.swift`](../../../../spikes/settings-mockup/SettingsMockup.swift), a single-file AppKit/SwiftUI mock-up following the context-capture spike's precedent. `./spikes/settings-mockup/capture` rebuilds and screenshots it; a launch argument selects the starting pane. It is real SwiftUI, so what it shows is what the app will look like rather than a drawing of it. Judgements below came from reacting to it over several rounds, not from arguing about it in prose.

The design rules it was written against are vendored at [`.agents/skills/native-macos-ui/SKILL.md`](../../../../.agents/skills/native-macos-ui/SKILL.md), adapted for macOS from Arjit Jaiswal's MIT-licensed SwiftUI Design Principles. Every ugly thing in the first draft was the same mistake — hand-drawing what AppKit already draws — and the checklist exists to stop that recurring.

### Shape

**One resizable window with a sidebar, no tabs.** Tabs were built and rejected: five destinations is already its ceiling, and History wants width that a tab bar cannot buy back.

**Features first, Settings among them, not over them.** The sidebar reads Settings — separated — then History, Model, Dictionary, Cleanup. Settings is the default destination on open. This inverts the obvious arrangement and matches what both surveyed apps do: preferences are one destination, not the container everything else lives inside. "Dictation" and "General" as pane names dissolved in the process; neither described a real thing.

### Settings pane

Ordered by how often a thing changes, not by importance: Shortcuts, Microphone, Sounds, mute-while-active, then Open at login with Version and the settings file. Open at login sits at the bottom against first instinct, because it is set once during setup and never touched again, while Shortcuts is what the window is opened to change.

- **Activate**, not Dictate. Hold to dictate, double-tap for hands free, stated once as the section footer.
- Shortcuts may be bound more than once or not at all. Clicking a binding rerecords it, so the `⋯` menu holds only Add Another and Remove. Key names use Wispr's shorthand — glyph plus short word, `⌥ Right Opt` — which stays readable without the symbols memorised.
- Microphone is system default or an explicit device. **Ranked priority-list fallback is dropped**; an unavailable explicit choice falls back to system default.
- Sound cues are per-cue, not one global switch. Choosing plays it; a play button replays it. `No audio` is dimmed so silence reads as the absence of a choice.
- **Permissions have no section.** A granted capability is invisible; an ungranted one pins an orange row to the top of the pane. "Hotkey listening" was dropped entirely — it is a health state with one repair, not a permission, and belongs in the same pinned banner when it occurs.

### History

Sectioned by day. One line per entry: time, app, transcript, then an aligned waveform column and the duration. **The row is the copy target**, said once at the top of the pane because nothing about a row says so otherwise. Copying leaves no selection behind — an early bug where it did revealed that copying is an action, not a selection, and keyboard navigation owns selection alone.

- The waveform _is_ the play button, gaining a play glyph on hover. The mark that says audio exists is the thing that plays it, and it disappears when the TTL prunes the audio — which makes retention visible without a word of explanation.
- Hover swaps the duration for a `⋯` holding Rerun Transcription, Save Audio, Delete. Right-click anywhere in the row opens the same menu.
- Arrows and `j`/`k` move, Return copies.
- **Storage lives here, not in Settings**, behind a toolbar popover: retention governs the rows you are looking at, and reducing either value confirms first because the deletion is immediate and otherwise silent. Retention must run when the setting _changes_, not only on a timer, or the control appears to do nothing.

### Model

Installed models are one exclusive choice, so the whole row selects and a checkmark marks the one in use; Delete is disabled on it. Available models sit below with their own downloads, and a total-on-disk row covers everything. The status row is gone — readiness is expressed by the rows themselves.

**Cancel and quit differ, and that is the load-bearing decision.** Quitting mid-download pauses and keeps the partial file, resuming at next launch. Cancel is explicit intent, so it deletes the partial. A failed download keeps its partial for the same reason a quit does. There is no user-visible paused state: it is downloading, or it was cancelled.

Worth revisiting when a second model actually ships: nothing on the page explains _why_ one model over another. The idea to explore then is a live comparison — record a fixed phrase, run it through each installed model, report latency and output — which is also machinery the [corpus problem](15-second-engine.md) needs.

### Dictionary

Named Dictionary, as everyone else names it. Rows are not selectable; clicking opens the editor, and hover shows only a trash icon. Sort is Newest First or Alphabetical. No dates in rows.

One sheet serves add and edit, prefilled when editing. A toggle sits alone in its own section so it cannot move under the pointer when flipped, and reveals the correction shape: `Misspelling → Correct spelling`, dimmed on the left, following Wispr. Placeholders name each field's role rather than showing example values, which is what made an earlier attempt read as prefilled data.

**This page is two features wearing one list.** Vocabulary biases the engine before transcription; corrections rewrite after it. That is a real seam, and it is why the map's exclusion of find-replace still holds — what is ruled out is a general text-substitution engine, not a correction attached to a word already taught.

### Cleanup

Endpoint address, API key, model, and a Save that verifies. Additional instructions are added to a built-in prompt rather than replacing it, and save as typed.

- **The API key is a state machine.** Never set is blank. Stored shows a six-character prefix then dots, as inert text rather than a field, because a half-edited secret is a secret that no longer works — touching it replaces it outright, in an ordinary text field where selection, ⌘A, and paste all behave. A successful Save is what moves a typed key into the stored state; a failure leaves it in the clear so it can be corrected. The visible prefix has [no precedent](../assets/26-cohere-transcription-model/README.md) among surveyed apps, which all mask completely — it is a deliberate product cue, and the key itself belongs in the Keychain.
- **Model discovery is best effort.** A dropdown with `Custom…` at the bottom, plus a Load Models button. Terra's [survey of open-source clients](https://github.com/janhq/jan) found nobody using that arrangement and recommended an always-editable text field instead; both were built and the picker was kept, because the amendment that makes it safe is what the survey was actually worried about: **a failed listing falls through to `Custom` with the field already open**, captioned on the Model row itself. `/v1/models` is optional and plenty of gateways omit it, so discovery failing must read as "browsing unavailable", never as "you may not enter a model".
- **Save sends a bounded completion to the entered model**, not a models-listing request. Only that tests the endpoint, the key, and the model together. Open WebUI's verify is weaker than its own fallback for precisely this reason.
- Success says `Saved` once, quietly. Failure says the specific reason. Nothing is reported until Save is pressed.

### Rules that emerged, and are not local to one pane

- **Rows that swap a control on hover must pin their height.** A `Button` reports a larger intrinsic height than the text it replaces, and a frame does not clamp what it is given. Both lists hit this; both fix it by fixing the row height.
- **A trailing accessory slot needs a fixed width as well.** Otherwise swapping metadata for buttons reflows the transcript and reveals a different amount of text on hover.
- **A footer must prevent a mistake or be deleted.** Most of the first draft's explanatory text was the author enjoying himself.
- One `MoreMenu` component for every `⋯`, because getting `.iconOnly` and the indicator right once beats getting it subtly wrong in four places.

### Liquid Glass

Reviewed against macOS 26's redesign, verified against the HIG and the installed SDK's `swiftinterface` rather than blog posts. **The window already adopts it.** Built from stock containers against the macOS 26 SDK, the sidebar floats, toolbar items and the search field become glass, and `Form` sections and sheets take the new radii — with no glass API called anywhere. Two changes came out of the review and both are applied:

- The History caption bar uses **`safeAreaBar`**, which supplies the material and separator itself, replacing a hand-built `safeAreaInset` + `.background(.bar)` + `Divider()`.
- Row highlights moved from **radius 6 to 8**, matching the selection highlight the same `List` draws. A radius ladder made the mismatch measurable; 6 looked right only in isolation.

Everything else hand-rolled was confirmed correct and deliberately left alone. Three findings are worth keeping:

- **`glassEffect` must never touch content.** Applied to a history row it renders as a stray grey outline — the HIG's "don't use Liquid Glass in the content layer" made visible.
- **`hoverEffect` and `listRowHoverEffect` are unavailable on macOS.** The hand-drawn hover background is not a workaround, it is the only option. `.listRowBackground` was tested as the native alternative and is worse: a full-bleed square band that swallows separators and loses the hover fill entirely.
- **Concentric radii do not apply here.** The row highlights sit in no rounded container, so a fixed radius is correct in kind; only the number was wrong.

This strengthens the skill's central claim rather than complicating it — a window that used the system's controls got the redesign for free.

The screenshots behind each of these are kept at [`spikes/settings-mockup/evidence`](../../../../spikes/settings-mockup/evidence/README.md), because the variants that produced them are gone and the findings are not obvious without them.

### Animating rows in a List

A `List` on macOS only honours an exit animation already present in the update transaction when it reaches its hosted rows. A value-scoped `.animation(_:value:)` on the row is silently ignored for a change arriving from an async task, so transient state reaching the row itself must be cleared inside `withAnimation` at the mutation site. Isolated by testing the same model behind a plain `VStack` and a `List`: without `withAnimation` the VStack faded correctly while the List row had already vanished. It is not an `@Observable` or computed-property problem, which is what made it hard to find.

The rule is narrower than this spike could see. Building the real pane found that a value-scoped `.animation(_:value:)` on a **leaf view inside** the row does animate an async change: the shipped confirmation fades badge and duration on opacity modifiers, cleared by an ordinary reducer mutation from a clock effect, verified by capturing both transitions mid-fade. Animating a child's opacity resolves inside the row's own body instead of the transaction `List` hands its rows. So the constraint is about what the row animates as a whole, and the leaf spelling is preferred where it applies, because it keeps presentation timing in the view rather than in the reducer.

The copied confirmation leaves in two transactions rather than one: badge and tint fade out over 0.5s, and only once gone does the duration fade in over 0.25s. Crossfading them superimposed two texts in one slot at half opacity, which is unreadable for the length of the transition. The shipped pane spells the stagger as a delay on the returning half and a value-dependent animation on each — instant arrival, slow exit — rather than as a second state the reducer has to hold.

Both rules are in [`.agents/skills/native-macos-ui`](../../../../.agents/skills/native-macos-ui/SKILL.md) so the next surface does not rediscover them.

### Still open

`.searchable` is not honouring `.searchToolbarBehavior(.minimize)` in the spike's plain `NSWindow`, so search fields stay expanded where they should collapse to a magnifying glass. This may be an artifact of not using a real `Scene` and should be retested in the app before being treated as unavailable.

Left undecided as cosmetic: whether `MoreMenu` should use `.menuStyle(.button)` inside `Form` rows to match neighbouring bordered buttons. It would mean splitting the component, since History's hover accessory wants borderless, and that costs more than it returns.

### What this unblocks

[History](11-history.md) can now be built from a picture. Its _Decisions carried_ section holds the retention and audio rules; this ticket holds the surface they live on.
