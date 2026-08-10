---
status: closed
type: grilling
blocked-by: [8]
---

# Agent-driveability: maximal accessibility compatibility

## Resolution

Researched and implemented. Findings and the agent-facing contract live in [the research asset](../assets/22-agent-driveability.md); the implementation landed one `miniwhisper.<surface>.<element>` identifier vocabulary across onboarding, menu, About (now a custom accessible window), and the pill (whose phase/capture status/notice/level are readable out-of-process from the nonactivating panel — level quantized to 10% buckets), a curated per-surface XCUITest manifest gate run via `mise run test:ui`, and a debug-only deterministic scene driver. The raw-AX spike settled the open unknown: the UI-test runner is not a trusted AX client (`kAXErrorAPIDisabled`), so the gate stays XCU-shaped; out-of-process fidelity was proven separately with a Ghostty-attributed raw reader.

## Question

The app should be maximally accessibility-compatible — not primarily for assistive tech, but so that "computer use" agents can drive every surface programmatically. Phase 7's own validation already drove the onboarding window through the AX tree; that capability should be a guarantee, not an accident. What does full coverage require across the app's surfaces (onboarding window, menu bar dropdown, the pill, any future settings UI): accessibility identifiers/labels on every interactive element, AX actions for custom controls, honest state exposure (progress values, permission row states, pill phases)? Is there an audit tool or test harness that can assert coverage so regressions fail a gate?

## Notes

- Requested post-Phase-7: subagent validation repeatedly relied on AX-tree clicking and reading; gaps would have blocked evidence-gathering.
- The pill is a nonactivating panel — verify its states are AX-readable at all, since it never takes focus.
- SwiftUI provides `.accessibilityIdentifier`/`.accessibilityLabel`/`.accessibilityValue`; NSStatusItem menus are AX-native but item identifiers may need explicit assignment.
- Overlaps agreeably with UI testing: identifiers double as stable hooks for XCUITest/automation harnesses.
