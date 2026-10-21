# Profiles mock-up

Disposable AppKit/SwiftUI mock-up of the Profiles pane and the onboarding profile step, for [ticket 47](../../docs/wayfinding/finishing-mini-whisper/tickets/47-cleanup-endpoint-profiles.md) and [ticket 39](../../docs/wayfinding/finishing-mini-whisper/tickets/39-recommended-cleanup-providers.md). Not an Xcode target, imports no MiniWhisper code, must not ship. Every value in it is invented — the taglines especially, which are placeholder tradeoff copy rather than decided wording.

It exists to be reacted to. The picker question ("rows, cards, a pop-up, or tabs?") has no answer in prose, because the thing being weighed is how much pane a lineup eats and whether taglines get compared or merely read, and both are pixels.

```sh
swiftc -framework AppKit -framework SwiftUI \
  spikes/profiles-mockup/ProfilesMockup.swift -o .build/profiles-mockup
.build/profiles-mockup pane-a            # pane variants: pane-a pane-b pane-c
.build/profiles-mockup onb-a             # onboarding profile step: onb-a onb-b
.build/profiles-mockup onb-key           # the key page a factory profile falls into
.build/profiles-mockup onb-models        # the per-profile model set
```

Flags stack after the screen, in any order:

| flag              | what it does                                                      |
| ----------------- | ----------------------------------------------------------------- |
| `full`            | the lineup at five profiles instead of the two v1 ships           |
| `needs-setup`     | the selected factory profile has no key yet                       |
| `overridden`      | its endpoint has been edited in place, so Reset to Default exists |
| `offline`         | start on the offline profile — the three-file download case       |
| `custom-selected` | start on Custom, so its own detail rows are on screen             |
| `light` / `dark`  | force an appearance                                               |

Everything is live: profiles select, the key field stores, onboarding's Continue walks the real branch (a factory profile with no key goes to the key page, Custom goes straight to the downloads).

## What the pane is

Picker on top, the selected profile's details below it, the rows that belong to every profile after that (Give up after, Additional instructions), and Downloaded models last — name, role, which profiles use it, size, Delete. Only the picker differs between variants; everything under it is shared, which is the point. A factory profile's rows are editable in place and gain **Reset to Default** once touched; Custom keeps today's Cleanup pane exactly — enable toggle, address, key, model picker with Load Models and Save — plus the sidecar toggle, whose footer changes with the cleanup toggle above it, because with cleanup off the sidecar is the whole vocabulary story and with cleanup on it is a net loss.

### A — rows

The grammar the Model pane already uses for installed models: the whole row is the choice, the tagline lives under the name, status sits at the trailing edge. Five profiles is five rows, roughly 350 px, before the details start. Taglines stack vertically, so they are read in sequence rather than compared.

### B — pop-up

One `LabeledContent` row, constant height however long the lineup gets. Status rides beside the control; the tagline drops to the section footer, where it describes the current selection only. This is the only variant where Downloaded models is visible without scrolling at five profiles, and the only one where a sixth profile costs nothing. The cost is that the lineup is invisible until the menu is open, so a profile the user has never chosen never gets read.

### C — cards

Two across, each card a whole stack at a glance. The taglines sit side by side, which is the only layout in which the tradeoffs actually get compared — and the reason to consider it at all, since comparing is what a first-time chooser is doing. Five profiles is 630 px of pane before the first detail row, and the pane becomes two scroll regions in practice: pick up here, configure down there.

## What onboarding is

Profile becomes the first rail item, ahead of Permissions. That has a consequence the design doc has to answer: the welcome page's **Download Parakeet v2** button assumes it knows the model set, and once a profile decides the model set it does not. Either the welcome button becomes a plain Get Started and the durable background download starts one page later, or profile choice happens on the welcome page itself. The mock-up assumes the first.

### A — list

Radio rows in the standard step card, the same grammar as the Permissions page immediately after. Each row carries name, tagline, and a plain "Key required" at the trailing edge. Five profiles fit with nothing changed.

### B — cards

Two cards, the shape onboarding already uses when a page asks for a commitment ([the shortcut mock-up](../onboarding-shortcut-mockup/OnboardingShortcutMockup.swift)'s variant E). Each card ends with what it will cost to set up: "Needs an Anthropic key" or a green "Nothing else to set up". At five profiles it does not fit a 720×500 page for free — it buys the fifth by dropping the page glyph and the per-card icon, and the taglines wrap to five lines. Worth knowing before the lineup grows, since the onboarding window is fixed.

### The key page

A factory profile is prescriptive, so this page has no Skip. The only way past it is a different profile, and the link says which one and what it costs: "Use the Custom profile instead — no key, no cleanup". Continue is disabled while the field is empty.

### The download page

One bar for the whole job, the parts listed under it with role and size. `onb-models` is the Haiku profile's single file; `onb-models offline` is the three the offline profile needs, which is the case today's single-model page cannot render.

## Screenshots

```sh
./spikes/profiles-mockup/capture [output-dir]   # default .build
```

Launches the mock-up once per screen per appearance and photographs each by `CGWindowID`, so a capture never depends on which window is frontmost. [`evidence/`](evidence/) holds the full set, light and dark.

## Conventions

Written against [`.agents/skills/native-macos-ui`](../../.agents/skills/native-macos-ui/SKILL.md): `Form` + `.formStyle(.grouped)` owns the layout, `LabeledContent` for every label/value row, text styles rather than point sizes in the pane, semantic colors only, no control drawn by hand that AppKit provides. The onboarding pages use fixed sizes because the real onboarding window does — it is replicated here, not redesigned.
