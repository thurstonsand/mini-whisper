---
status: open
type: prototype
blocked-by: [8]
---

# Iconography: a real app icon everywhere the app is seen

## Question

`MiniWhisper/Assets.xcassets/AppIcon.appiconset` holds a `Contents.json` and no images, so the app shows the generic blank-document icon in Finder, the Dock, Spotlight, and the install path. What should the icon be, and where else does the app's identity need to show up consistently: the menu bar glyph (currently an SF Symbol, template-rendered), the onboarding window's `mic.fill` placeholders, the pill, notification/alert badges, the DMG or ZIP presentation, and the README? Does the menu bar want a custom template glyph of its own, or does an SF Symbol stay the right answer at that size while the app icon carries the identity?

## Notes

- Requested after seeing `MiniWhisper.app` render with the blank icon in Finder.
- Menu bar images must be template images to track light/dark and tinted menu bars; a full-color app icon does not transfer down to 16pt.
- The degraded state changes the menu bar symbol, so any custom glyph set needs a matching degraded variant.
- macOS 26 icons are authored in Icon Composer with layered light/dark/tinted/clear variants; decide whether to target that or ship a flat `.icns`-style set.
- Verify the icon actually lands: Finder, Dock, Spotlight, System Settings' Login Items and privacy panes, and the release artifact.
