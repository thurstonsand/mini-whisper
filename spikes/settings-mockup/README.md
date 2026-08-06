# Settings mock-up

Disposable AppKit/SwiftUI mock-up of the settings window for [ticket 16](../../docs/wayfinding/finishing-mini-whisper/tickets/16-settings-ui.md). It is not an Xcode target, imports no MiniWhisper code, and must not ship. Every value in it is invented.

It exists to be reacted to. Real SwiftUI in a real window means the design is judged on the platform's own metrics, materials, and control sizes rather than on a drawing of them — which is how several decisions got reversed that prose had left standing.

```sh
swiftc -framework AppKit -framework SwiftUI \
  spikes/settings-mockup/SettingsMockup.swift -o .build/settings-mockup
.build/settings-mockup            # opens on Settings
.build/settings-mockup history    # also: model, dictionary, cleanup, componentstates
.build/settings-mockup playground # also: cursorlab1, cursorlab2, cursorlab3
```

A trailing `light` or `dark` argument forces that appearance.

The launch argument picks the starting pane, matching on the destination name with spaces removed. Everything is interactive: panes navigate, rows hover and copy, sheets open, pickers and toggles work.

`componentstates` is a mock-up-only page with no counterpart in the app. It shows every state the stateful rows can take — six model install states, six endpoint save outcomes, three API-key states — side by side, so they can be compared rather than imagined one at a time.

The cursor labs settled the Settings pane's keyboard-cursor design for [ticket 31](../../docs/wayfinding/finishing-mini-whisper/tickets/31-settings-pane.md): `cursorlab1`/`cursorlab2` show six row-cursor treatments A–F, `cursorlab3` freezes the chosen composition (accent bar for the row, focus ring for the target within it), and `playground` is that composition live — j/k/h/l/Return work, mouse hover moves the same bar, and the caption strip narrates what each press would do.

## Screenshots

```sh
./spikes/settings-mockup/capture [output-dir]   # default .build
```

Launches the mock-up once per pane and photographs each. The process prints its `CGWindowID` to stdout on launch and `capture` feeds that to `screencapture -l`, so a capture never depends on which window happens to be frontmost — the earlier coordinate-scraping version silently photographed the terminal instead.

Output is gitignored. [`evidence/`](evidence/README.md) holds the screenshots that are worth keeping: the ones that settled a decision whose reasoning is not obvious without the picture.

## Conventions

Written against [`.agents/skills/native-macos-ui`](../../.agents/skills/native-macos-ui/SKILL.md) — system containers own the layout, text styles instead of point sizes, semantic colors only, and no control drawn by hand that AppKit already provides. Two rules in that document were discovered here and are worth knowing before editing this file: a `List` only honours an exit animation already in the update transaction, and `glassEffect` must never touch the content layer.
