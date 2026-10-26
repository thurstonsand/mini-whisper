# Profiles pane mock-up

A throwaway AppKit/SwiftUI mock-up of four layouts for the Profiles pane in the settings window. It follows the [profiles mock-up](../profiles-mockup/README.md), which settled the lineup. That one built the pane around a two-across grid of profile cards; the resulting pane is about 630 pt of cards before the first detail row, then the details, then "All profiles", then "Downloaded models", and it reads as one long wall.

It is not an Xcode target and imports no MiniWhisper code; do not ship it. The values come from [the profiles design](../../docs/designs/04-profiles.md) and are fixed in the mock.

```sh
swiftc -framework AppKit -framework SwiftUI \
  spikes/profiles-pane-mockup/ProfilesPaneMockup.swift -o .build/profiles-pane-mockup
.build/profiles-pane-mockup a          # variants: a b c d
```

Flags can follow the variant in any order:

| flag             | what it does                                                         |
| ---------------- | -------------------------------------------------------------------- |
| `accurate-nokey` | Most accurate is active and has no ElevenLabs key                    |
| `offline-nos1`   | Offline is active and S1-mini is not downloaded                      |
| `models`         | Most accurate is active with every key; opens on the models list     |
| `browse`         | Haiku is running and Most accurate is the profile on screen (B, C)   |
| `downloading`    | Parakeet TDT v2 is 42% downloaded                                    |
| `custom`         | Custom is active                                                     |
| `overridden`     | Haiku's model has been edited, so Reset to Default appears           |
| `tall`           | a window 1400 pt tall, so the whole pane fits in one image           |
| `light` / `dark` | force an appearance                                                  |

Round two adds `r2` (the revised D) and these flags after it:

| flag             | what it does                                                                |
| ---------------- | --------------------------------------------------------------------------- |
| `overridden2`    | Haiku's address overridden, its model being edited to a custom ID           |
| `downloads=1..3` | open the Downloads page, Most accurate active, Parakeet and S1-mini on disk |
| `scope=1..4`     | how settings for every profile are told apart from this profile's           |
| `settings`       | open the Settings pane (with `scope=2`)                                     |
| `key=1..4`       | Custom against Ollama on localhost, no key entered                          |
| `key-required`   | with `key=4`, the endpoint answered that it needs a key                     |
| `h=NNN`          | a window of that many points tall                                           |

Round three adds `r3` and these flags after it:

| flag | what it does |
| ---- | ------------ |
| `shot=offline`, `shot=custom-off` | Offline, or Custom with cleanup off, active |
| `shot=menu` | the profile menu open (Offline downloading, Custom never verified) |
| `shot=model-locked`, `shot=model-locked-both` | Haiku with its model overridden, or model and address, not being edited |
| `shot=override-draft` | Haiku mid-edit: a custom model ID, the previous setup still in use |
| `verify=draft\|verifying\|needs-key\|unknown-model\|verified\|flash` | Custom against Ollama through the Verify flow |
| `models=a\|b\|c` | the other designer's Models page; add `states` to A for mixed states |
| `r4` (instead of `r3`) | round four: per-field reset icons, the boost warning, no privacy line; takes the same `shot=` values plus `custom-boost` and `custom-boost-off` |
| `r5 r5shot=…` | round five's verify flow: `custom-new`, `custom-edit`, `checking`, `fail-unreachable`, `fail-needs-key`, `fail-unknown-model`, `custom-verified`, `haiku-edit-model`, `haiku-revoked`, `sheet` |
| `concept=blocks\|transit\|facts\|patchbay` | round six's Models concepts (with `r3`); add `states` for Offline active, Parakeet downloading, S1-mini failed |

Everything is live. You can switch profiles, save keys, start and stop downloads, and delete models (deletion asks first).

## What the user asked for

> the profiles pane needs a full rework. i was imagining that it would show you what your currently configured settings are, including what is configurable about them, with some picker to switch to a different profile, which would show you THOSE settings. well, i say that but actually we do need one central place to manage what models are downloaded so it's easy to clean them up if desired.

That gives four tests for each layout:

1. **Readable at a glance.** You can see what is running without scrolling past the whole lineup.
2. **Shows what is set and what can change.** The current configuration is visible, and anything editable looks editable.
3. **Easy to switch.** Moving to another profile, or just looking at one, is cheap.
4. **One place for models.** There is one obvious home for what is on disk, with Delete beside each model.

## Ideas considered

| # | idea | what it gets right | what it gets wrong |
| - | ---- | ------------------ | ------------------ |
| 1 | **Pop-up picker, then a detail form** | The lineup takes one row however many profiles there are. The active configuration starts about 60 pt down. | You can't see the lineup or any other profile's status until you open the menu. Picking a profile switches to it at once, so you can't look without switching. |
| 2 | **Master-detail inside the pane**: a short list of profiles on the left, the selected profile's form on the right | You can see every profile and its status all the time. Selecting a profile shows it without switching, so you can add its key first. Models can be the last item in the list. | It nests a second sidebar inside a sidebar window, and the detail column is narrow (about 450 pt), so long values wrap. "Selected" and "active" now mean different things and need two marks. |
| 3 | **Segmented control or tabs, one per profile** | It's flat and familiar, and the selection is plain to see. | Five long names don't fit in a segmented control at 860 pt. There's nowhere to show status, and tabs suggest you're looking, not switching. |
| 4 | **Current setup summary, then a Change Profile… sheet** | The page answers "what is running" first. The settings are split into what is fixed and what you can change. The sheet can lay out the lineup to compare before committing. | Switching takes two clicks and a modal. You can't see another profile's status without opening the sheet. |
| 5 | **Profiles and Models as two sidebar entries** | Models get a page you can find by name, modelled on Storage settings: total size, "Delete Unused…", one row per model. The Profiles page gets shorter. | It adds a sidebar entry. Model state that blocks a profile (such as "Needs S1-mini") has to show in both places. |
| 6 | **Table of profiles with columns** (engine, cleanup, what leaves this Mac, status) | It's the best layout for comparing: the tradeoffs line up in columns. It's native (`Table`). | Five rows of a five-column table is a lot of pane before anything you can edit. Editing still needs a detail area below or beside it. Works better inside a sheet than as the pane itself. |
| 7 | **One disclosure group per profile**, active one expanded | Everything lives in one list, and opening a profile is how you look at it. | You can expand several at once, which brings the wall back. Telling expanded from active is confusing. |
| 8 | **A radio list of profiles at the top**, status at the right, then the active profile's details | The whole lineup and every status fit in about 200 pt, about a third of today's card grid. It's one native control. | Picking a profile still switches to it at once. The profile descriptions don't fit, so they're gone except for the active profile's privacy line. |
| 9 | **Sections in pipeline order** (Speech, then Cleanup) instead of one profile-named block | It reads the way a dictation runs. Keys sit with the part that uses them: the ElevenLabs key under Speech, the Google key under Cleanup. | It's an ordering rule, not a layout, so it combines with any of the others (all four variants use it). |
| 10 | **A toolbar pop-up for the profile** (in the window toolbar) | The pane body is all settings. | The settings window keeps its toolbar the same on every pane (see `native-macos-ui`), and the active profile matters outside this pane. |
| 11 | **An inspector**: the profile list as the pane, details in a `.inspector` on the right | It's the native trailing-detail idiom. | At 860 pt the inspector is too narrow for an address field and a key field. It amounts to idea 2 with worse proportions. |

## The four built

These are the strongest candidates that differ the most from each other. Each one tries a different answer to the two real questions: **is looking at a profile the same as switching to it**, and **where do the models live**.

| variant | idea | browse ≠ activate? | where the models live |
| ------- | ---- | ------------------ | --------------------- |
| A | 1 + 9: pop-up, then the pipeline form | No: picking switches | the last section of the pane |
| B | 2 + 9: master-detail in the pane | **Yes**: the list shows a profile; Use This Profile switches | a Models item at the end of the profile list |
| C | 4 + 6 + 9: summary, "You can change", sheet with a table | **Yes**: the sheet's table shows; Use … switches | the last section of the pane |
| D | 8 + 5 + 9: radio lineup, Models in the sidebar | No: picking switches | a **Models** entry in the settings sidebar |

All four share the detail grammar. Fixed facts are plain `LabeledContent` values. Anything you can edit is a bordered field, a pop-up, a toggle, or a button, so you can tell what is editable by its shape. A grouped `Form` otherwise draws a text field as bare text that looks exactly like a fixed value; today's pane has that problem. A missing key or model is an orange-triangle row with its fix right there (a key field and Save, or Download). Timeout and instructions sit under Cleanup, with a footer that says they apply to every profile. That footer is there to prevent a real mistake: changing the timeout while thinking it only affects this profile. Instructions are hidden for Offline. Every variant shows the privacy line for the profile on screen.

### A: pop-up and pipeline form

One `Profile` row holds a status label and the pop-up, with the privacy line underneath. Then come Speech, Cleanup, and "Models on this Mac" with a total. The page always shows the profile that is running. The whole thing is a single scrolling `Form` with nothing new to learn. At 680 pt you can see the active configuration and every editable field without scrolling. The models are one scroll away, and the tall capture shows the whole pane ends at about 840 pt. **Tradeoff:** the lineup is hidden in a menu, so you can't see that Cerebras needs a key unless you switch to it. And you can't look at a profile without making it the one that runs.

### B: master-detail

A 216 pt list on the pane's left edge holds the five profiles, each with a one-line status ("Active", "Ready", "Needs setup", "Downloading · 42%"). Under a Storage header comes **Models** with the total on disk. Selecting a profile shows its form, and **Use This Profile** is what switches. So you can paste the Most accurate keys before switching, which none of the other layouts let you do in place. Selecting Models shows the shared models list. **Tradeoff:** it nests a second list inside the settings window's sidebar layout. The detail column is about 450 pt, so the tagline wraps and the Additional instructions label stacks above its field. "Selected" and "active" are separate states: the list highlight versus a green Active mark.

### C: what is running, then what you can change

The **Active profile** section is a summary you can read top to bottom: name, tagline, any problem, then Speech, Vocabulary, Cleanup, and Leaves this Mac. The **You can change** section holds only the controls, and the models follow. **Change Profile…** opens a sheet with the lineup as a native `Table` (profile, speech, cleanup, status) and a description of the highlighted row. **Use Most accurate** switches; Cancel leaves everything as it was. This is the most literal reading of "show you what your currently configured settings are, including what is configurable about them". **Tradeoff:** switching is two clicks and a modal. The summary repeats values that the controls below also show (the model name appears twice). Another profile's settings can only be compared in the sheet's columns; you can't edit them before switching.

### D: radio lineup, Models in the sidebar

The lineup is a native `.radioGroup` picker: five 37 pt rows, each with its status at the right edge. You can see the whole lineup and its status in about 200 pt, with the active profile's details right underneath. Models move out of the pane to their own **Models** entry in the settings sidebar. That page is modelled on Storage settings: a summary of total on disk and what the active profile doesn't use, with **Delete Unused…**, then one row per model. The Profiles pane ends with a small "Models" row and **Show Models**, so the link is still visible from here. **Tradeoff:** picking a radio switches immediately, so there's still no looking without switching. And it adds a fifth sidebar item to a window that has kept its sidebar short.

## Recommendation

**D**, with **B** as the alternative if looking without switching turns out to matter.

D answers the request most directly. The current configuration and the full lineup with status are both visible without scrolling. Switching is one click on a native control. Models get one obvious home, found by name in the sidebar instead of at the bottom of something else, with a Delete Unused… action that answers "clean them up if desired" in one step. The radio list takes about a third of the cards' height and drops only the taglines, which mattered for choosing at first run (onboarding still has the cards) and matter much less for a returning user.

The cost is that picking switches immediately. That is today's behaviour, and the design already makes it safe: a profile with a missing cleanup leg delivers raw text, and one with a missing engine reads Degraded and says why. If the user does want to look before committing, especially to add a key before switching, B is the layout built for that. B's in-pane Models item can then become D's sidebar entry without changing anything else.

A is the conservative fallback and the cheapest to build from today's code. C is best on paper for showing what is set versus what you can change, but switching through a modal is a lot of ceremony for something the menu bar may also do.

## Screenshots

```sh
./spikes/profiles-pane-mockup/capture [output-dir] [name-filter]   # default evidence/
```

The script launches the mock-up once per screen per appearance and photographs each window by its `CGWindowID`, so a capture never depends on which window is frontmost. A sheet is attached to its window, so the same capture includes it. [`evidence/`](evidence/) holds every shot in light and dark:

| shot | state |
| ---- | ----- |
| `pane-{a,b,c,d}-default` | Haiku active, key stored, every model installed |
| `pane-{a,b,c,d}-tall` | the same, 1400 pt tall, so the whole pane is in one image |
| `pane-{a,b,c,d}-accurate-nokey` | Most accurate active, ElevenLabs key missing |
| `pane-{a,b,c,d}-offline-nos1` | Offline active, S1-mini not downloaded |
| `pane-{a,b,c,d}-models-notinuse[-tall]` | Most accurate active; Parakeet and S1-mini read "Not in use" |
| `pane-b-browse[-tall]`, `pane-c-browse` | Haiku running, Most accurate shown (B's list, C's sheet) |
| `pane-a-downloading`, `pane-d-downloading` | Parakeet 42% downloaded (A's pane, D's Models page) |
| `pane-a-custom-tall`, `pane-a-overridden` | Custom's own rows; a factory profile with Reset to Default |
| `pane-d-accurate-nokey-tall` | D with the whole pane in one image while a key is missing |

## Conventions

The mock is written against [`.agents/skills/native-macos-ui`](../../.agents/skills/native-macos-ui/SKILL.md). `Form` with `.formStyle(.grouped)` owns the layout; every label/value row is a `LabeledContent`; text uses text styles (`.headline`, `.callout`, and body), not point sizes; colours are semantic only. No control is hand-drawn: the lineup is a `.radioGroup` picker, a `List`, a pop-up, or a `Table`. Window chrome matches the real settings window: 860×680 content, the same sidebar column widths, and the zero-size keeper toolbar item.

## Round two

Thurston chose D. This round revises it with his feedback, then mocks three open questions. Everything here is dark mode only, under `evidence/r2-*-dark.png`. The round-one screenshots above predate the change to `gemini-3.8-flash`.

### The revised D

Shots: `r2-d-revised`, `r2-d-revised-tall`, `r2-d-overridden`, `r2-d-accurate-nokey`.

- **One state, one mark.** The filled radio is the only "active" mark; the green "✓ Active" is gone. Beyond that:
  - "Ready" is gone from the lineup too. With Active removed, the running profile was the only row without a word, which read as a different state. Now no mark means ready, and the only status text is a problem ("Needs a Cerebras key") or a download.
  - The orange triangle on a missing key or model row is gone. The lineup's warning already says what is missing; the empty key field or the Download button is the fix, not a second warning.
  - "· on this Mac" / "· hosted" is gone from the Engine row. The privacy line under the lineup already says where audio goes.
  - The "Models · Show Models" row at the bottom of the pane is gone. The sidebar's Downloads entry is the way there, and the Downloads page now shows what the profile uses.
  - Each model's "used by" list is gone from the Downloads page, because "in use" is now the highlight. Which other profiles a deletion breaks moves into the Delete confirmation, the one moment it matters.
- **Additional instructions** has no placeholder. The field keeps its rounded border, because a borderless empty field in a grouped `Form` is invisible.
- **Key fields** lost their "Paste your … key" prompt too. This applies the same rule; the label already names the key. Revert it if the rule was meant for instructions only.
- **Factory Address and Model** are read-only values with **Edit**. Edit turns Address into a field with Done, and turns Model into the same pop-up Custom uses (the endpoint's listing, then **Custom…**, which adds a Model ID field) with Load Models and Done. Once a value differs from the factory one, **Reset to Default** appears in that row. `r2-d-overridden` shows a corporate-gateway address and a Bedrock-style model ID, the remapping case Edit exists for.
- **Vocabulary** row removed.
- **Models** in the sidebar is now **Downloads**.
- Custom's privacy line said transcripts go to "the address above"; the address is now below the lineup, so it says "below".

### Downloads: what is in use

Most accurate is active, so only the speech gate is in use; Parakeet and S1-mini are on disk and unused. Nothing marks "not in use": anything unmarked is what you can delete.

| shot | idea | tradeoff |
| ---- | ---- | -------- |
| `r2-downloads-1` | **Grouped**: "Used by Most accurate", then "Other downloads". | The clearest. The "stops dictation" footer attaches to the only group it is true of. Rows change groups when the profile changes, so a model seems to move. |
| `r2-downloads-2` | **Tinted rows**: one list, in-use rows on an accent tint, legend in the footer. | A stable order, and it's quick to scan. The tint is hand-drawn (grouped `Form` ignores `listRowBackground` on macOS) and reads like a selection highlight. |
| `r2-downloads-3` | **The active profile's mark**: Most accurate's own symbol beside each model it uses, with the legend in the footer. | Ties the page back to the Profiles lineup and keeps the order stable. It's the quietest of the three, and you need the legend to know what the glyph means. |

**Recommendation: 1.** It answers "what can I delete" without a legend, and it's the only one where the warning sits on exactly the rows it applies to.

### Profile-specific vs every profile

Haiku is active. The baseline is `r2-d-revised`: the two global rows sit in Cleanup with a footnote.

| shot | idea | tradeoff |
| ---- | ---- | -------- |
| `r2-scope-1` | **Name vs All profiles**: the profile's rows in one section headed with its name, then an "All profiles" section. | The headings carry the scope, so no footnote is needed. The Speech/Cleanup split is lost, and the profile's name now appears twice (the radio and the heading), which goes against the one-mark rule. |
| `r2-scope-2-settings`, `r2-scope-2-profiles` | **Move them to Settings**: a Cleanup section in the main Settings pane. | The Profiles pane becomes purely the profile. But instructions now live away from the cleanup they tune, and need a footer saying Offline ignores them. |
| `r2-scope-3` | **Tag each row**: "All profiles" under the label of each global row. | The rows stay where they work (under Cleanup). Two tags is fine, but this doesn't scale as global settings grow. |
| `r2-scope-4` | **Nest under the profile**: the active profile's rows sit indented under its radio, and everything after the lineup is for every profile. | Literally "this belongs to that profile". The indent is manual padding, and switching profiles moves the rest of the lineup down. Built from one single-option radio group per profile, so no radio is drawn by hand. |

**Recommendation: 4.** It's the only one where scope is shown by position alone, with no extra words, and it makes the lineup itself the answer to "whose settings are these". If the moving lineup bothers you in use, 1 is the calmer fallback.

### Custom without a key

Custom points at Ollama (`http://localhost:11434/v1`) with no key entered.

| shot | idea | tradeoff |
| ---- | ---- | -------- |
| `r2-key-1` | **"No key needed" checkbox** (Thurston's): checking it disables the field and Save. | Explicit, and a missing key on an endpoint that needs one is still caught. But it's a second control for one fact, and in dark mode a disabled field barely looks greyed. |
| `r2-key-2` | **Optional field**: the same field as every key row, captioned "Optional". | The least UI, matching every other key row. An endpoint that does need a key fails at the first dictation instead of here. |
| `r2-key-3` | **No key until asked for**: "None" and **Add Key**; the field appears only after that. | The row says what is stored, which is nothing. People on a hosted endpoint have to find Add Key before anything works. |
| `r2-key-4`, `r2-key-4-required` | **The endpoint decides**: Load Models already calls it. Without a 401 the row reads "Not needed by this endpoint" with Add Key; with a 401 it becomes the key field, and the lineup reads "Needs an API key". | Nobody has to know whether their server wants a key. It depends on a probe, and an endpoint that lists models without a key but needs one for completions would fool it. |

**Recommendation: 2,** with 4's probe as a later refinement. Optional is what the endpoint actually is, it costs nothing in the UI, and it doesn't add a control whose only job is to contradict an empty field.

## Round three

Thurston's decisions: the key is the optional field (round-two approach 2), scope is nested (approach 4), and the picker goes back to a pop-up. Everything is dark mode only, under `evidence/r3-*-dark.png`. The round-two Downloads page is untouched; another designer's Models page is mocked separately at the end.

### Pop-up picker with nested scope

Shots: `r3-haiku`, `r3-offline`, `r3-custom-off`, `r3-menu`.

- **The Profile row is a pop-up.** Each menu item carries its own problem, in orange (or secondary grey for a download): "Needs a Cerebras key", "Downloading S1-mini · 42%", "Needs verifying". The closed control shows the selected item the same way, and that is the selected profile's only status mark. A ready profile shows nothing.
- **The selected profile's settings sit in the same section as the picker, indented beneath it.** The privacy line is that section's footer.
- **"All profiles" holds only what applies to the active profile.** Offline gets the timeout but no instructions, since S1-mini takes no prompt. Custom with cleanup off has neither, so the whole group disappears.
- Round two's rules still hold: one mark per state, no ghost text, no Vocabulary row, `gemini-3.8-flash`.
- With cleanup off, Custom's boost toggle carries its explanation as a caption instead of a separate footer section, because the pane would otherwise end on a lone toggle.

### Model locked like Address

Shots: `r3-model-locked` (model overridden), `r3-model-locked-both` (model and address overridden).

Model gets exactly the Address treatment: a read-only value with **Edit**. Edit opens the shared picker, which lists the endpoint's models plus Custom… for typing an ID. There is **one Reset to Default per profile**, on its own row, shown only when something is overridden. Its label says what it puts back: "Model changed from the default", "Address changed from the default", or "Model and address changed from the defaults". Reset never touches the key, which is the user's own value, not a factory one. Pressing Reset starts a draft like any other edit, so the defaults are verified before dictation uses them.

### Optional key and a required Verify

Shots, all Custom against Ollama on `localhost:11434` with no key:

| shot | state |
| ---- | ----- |
| `r3-verify-1-draft` | never verified: the primary button is **Verify**, and the picker reads "Needs verifying" |
| `r3-verify-2-verifying` | the spinner sits inside the button, which reads "Verifying" and is disabled |
| `r3-verify-3-needs-key` | a 401 with no key, against `gateway.internal` (Ollama needs no key, so a gateway stands in): "This endpoint needs an API key." and the key field has focus |
| `r3-verify-4-unknown-model` | `qwen3:32b` typed as a custom ID: "localhost:11434 has no model 'qwen3:32b'." with **Choose from its models**, which opens the endpoint's listing |
| `r3-verify-5-verified` | the steady state: no button, no line, no status in the picker |
| `r3-verify-5b-verified-flash` | the brief "✓ Verified" that replaces the button for two seconds after success |
| `r3-verify-6-override-draft` | Haiku with a custom model ID being drafted: **Discard** and **Verify**, and under them "Dictation keeps using claude-haiku-5-5 at api.anthropic.com until this verifies." |

- Any edit to the address, key, or model makes a draft.
- A key field has no Save; Verify is what stores it. A key that never verified is never stored.
- A failure sits under the button in orange, phrased as what to do. Editing anything clears it.
- The draft is not used until it verifies. With an earlier verified setup, dictation keeps using it and the quiet line names it; with none, the profile delivers raw and the picker says "Needs verifying".
- **Discard** is my addition. It appears only when there is a previous setup to go back to, because otherwise a draft you can't verify can't be abandoned short of retyping the old values.
- The flow simulates `OpenAICompatibleCleanup.verify()`. Today that returns `CleanupFailure.httpStatus` or `.unreachable`. Telling "no such model" apart from other 4xx errors needs the endpoint's error body (`model_not_found` on OpenAI-style servers, a 404 on Ollama), so the app would have to parse it.

### The Models page: three options from another designer

Their design, mocked as written. It replaces "Downloads" with **Models** (`internaldrive`) and gives every asset one fixed-width trailing slot that holds its whole status: size and Delete (`Delete…` when the active profile needs the asset), a progress bar, Waiting, ⚠︎ Couldn't download with Try Again, or Download (with ⚠︎ when needed). Most accurate is active, and all three assets are installed.

| shot | option |
| ---- | ------ |
| `r3-models-a` | **Inventory**: one section, fixed order; an in-use row has an accent symbol and "In use by Most accurate", the others give their purpose |
| `r3-models-a-states` | A with the gate failed, Parakeet downloading (42%), S1-mini waiting |
| `r3-models-b` | **Active stack**: Most accurate's pipeline (gate, Scribe v2 Hosted, Gemini Hosted), then "Other models on this Mac" |
| `r3-models-c` | **Components table**: Model, Used by, Size, with Download and Delete… in a bottom bar acting on the selected row (Parakeet) |

Notes from rendering them:

- The gate's caption in A says "In use by Most accurate", which reads as though only one profile uses it, though every profile does.
- In C the status slot carries no buttons, so a failed row shows its warning and the bar's Download is the retry.
- In C, a three-row table drawn full height is mostly empty stripes.

## Round four

Small edits to round three's pop-up and nested layout. Shots are `evidence/r4-*-dark.png`.

| shot | state |
| ---- | ----- |
| `r4-haiku` | the default, with no privacy line under the profile block |
| `r4-model-overridden` | Haiku with its model overridden: an ↺ before Edit on the Model row only |
| `r4-both-overridden` | model and address overridden: an ↺ on each row |
| `r4-custom-boost-warning` | Custom with cleanup and boost on: one secondary line under the toggle |
| `r4-custom-boost-off` | boost off: no caption, no warning |

- **↺ replaces the "… changed from the default" row.** It is a borderless `arrow.counterclockwise` icon button with the tooltip and accessibility label "Reset to Default", and it resets only its own field. It sits before Edit, so Edit stays in the same column whether or not the field is overridden.
- **The boost warning** reads "Cleanup usually handles your dictionary better without this." It has a small `exclamationmark.triangle` in secondary colour, not orange, and shows only when boost and cleanup are both on.
- **The privacy line is gone** for every profile.

## Round five: only a verified configuration is ever stored

This replaces round three's draft and Verify flow, which allowed a "Needs verifying" state. Address, key, and model only ever show the configuration that last verified; editing happens in place, and nothing is stored until the check passes. Shots are `evidence/r5-*-dark.png`.

| shot | state |
| ---- | ----- |
| `r5-custom-not-set-up` | first-time Custom: Address, API key, and Model read "None", one **Set Up** button, no cleanup toggle; the picker says "No cleanup" in grey |
| `r5-custom-editing` | Set Up pressed, Ollama typed, key empty with its "Optional" hint, focus on Address, **Cancel** and **Save** |
| `r5-checking` | fields disabled, Save reads "Checking…" with a spinner, Cancel still enabled |
| `r5-fail-unreachable` | "Couldn't reach localhost:11435." in red under Address, which has focus |
| `r5-fail-needs-key` | "This endpoint needs an API key." under the key, which has focus (against `gateway.internal`) |
| `r5-fail-unknown-model` | "localhost:11434 has no model 'qwen3:32b'." under the Model ID field, which has focus |
| `r5-custom-verified` | back at rest with the verified values; the cleanup toggle has appeared |
| `r5-haiku-editing-model` | Haiku entered through Model's Edit: all three fields open, with the model pop-up focused |
| `r5-haiku-key-rejected` | a key revoked after it verified: "Key rejected" in orange in the picker, and an orange caption on the key row |
| `r5-sheet-comparison` | the alternative, for comparison: the same fields and buttons in a sheet |

- **Edit mode.** Edit on any row, Replace on the key, or Set Up opens all three fields at once, focused on the row you pressed. Save is the default button (Return) and Cancel is the cancel button (Escape).
- **Success** stores everything at once and returns the group to rest; nothing else appears.
- **Failure** keeps edit mode open, puts one red line under the field at fault, and focuses that field.
- **↺** refills its field with the factory value and saves straight away through the same check. If the check fails, the group stays in edit mode and Cancel keeps the old override.
- **Decisions of mine:**
  - Cancel while checking stops the check and leaves you in edit mode with what you typed. A second Cancel discards the edit.
  - A stored key shows in the edit-mode field as dots. Leaving them alone keeps the key; clearing the field removes it (Custom only, where the key is optional).
  - Custom's key row at rest reads "None" with Edit when no key is stored, and the masked key with Replace when one is.
  - Custom's Boost vocabulary toggle stays visible while Custom is not set up, because with no cleanup it is the only way the dictionary reaches the transcript.

## Round six: four Models concepts from another designer

These are their designs, built as written, as the content of a **Models** sidebar page (`internaldrive`). They share their visual rules: tint stroke for the active profile, tint fill for what it uses, quinary fill with a hairline for what it doesn't, and a dashed border and cloud for hosted models. Haiku is active, and S1-mini is installed but unused. Shots are `evidence/r6-*-dark.png`.

| shot | concept |
| ---- | ------- |
| `r6-blocks` | **Shared blocks** (the designer's pick): rows are profiles, columns are GATE, SPEECH, and CLEANUP. The gate is one cell down all five rows, Parakeet is one block across four, and tint capsules mark each cell on the active row. |
| `r6-blocks-states` | Offline active, Parakeet downloading at 42%, S1-mini failed with Retry |
| `r6-transit` | **Transit map**: Mic → Gate → Speech → Cleanup → Paste, with a dashed "leaves this Mac" boundary. A line that dips below it is data leaving the Mac. The active line is 6 pt; the rest are faint. |
| `r6-transit-states` | the same states; missing stations are hollow |
| `r6-facts` | **Dictation Facts**: a nutrition label for the active profile beside a Pantry of what's on disk |
| `r6-patchbay` | **Patch bay**: profile cards with Speech and Cleanup ports, wired by curves to components grouped On this Mac and Off this Mac |

Notes from rendering:

- **Blocks:** the Scribe cell reads "Scribe v2", with ElevenLabs on its provider line. At the specified 190 pt, "ElevenLabs Scribe v2" truncated.
- **Blocks:** the gate cell has no Delete, because a 44 pt vertical cell has no room for a button.
- **Transit and patch bay:** neither shows Delete; the designer placed no Delete in either.
- **Transit:** a station shows its status (size, progress, Retry) in its label.
- **Transit:** an inactive line is drawn at 35% opacity.
- **Transit:** the hosted cleanup stations are ordered Google, Anthropic, Cerebras, Your endpoint, so Most accurate's line never crosses another station.
- **Patch bay:** all five cards and seven components fit in the default 680 pt window, so no tall shot was needed.
