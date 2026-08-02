---
status: open
type: grilling
blocked-by: [8]
---

# Agent-driveability: maximal accessibility compatibility

## Question

The app should be maximally accessibility-compatible — not primarily for assistive tech, but so that "computer use" agents can drive every surface programmatically. Phase 7's own validation already drove the onboarding window through the AX tree; that capability should be a guarantee, not an accident. What does full coverage require across the app's surfaces (onboarding window, menu bar dropdown, the pill, any future settings UI): accessibility identifiers/labels on every interactive element, AX actions for custom controls, honest state exposure (progress values, permission row states, pill phases)? Is there an audit tool or test harness that can assert coverage so regressions fail a gate?

## Notes

- Requested post-Phase-7: subagent validation repeatedly relied on AX-tree clicking and reading; gaps would have blocked evidence-gathering.
- The pill is a nonactivating panel — verify its states are AX-readable at all, since it never takes focus.
- SwiftUI provides `.accessibilityIdentifier`/`.accessibilityLabel`/`.accessibilityValue`; NSStatusItem menus are AX-native but item identifiers may need explicit assignment.
- Overlaps agreeably with UI testing: identifiers double as stable hooks for XCUITest/automation harnesses.
