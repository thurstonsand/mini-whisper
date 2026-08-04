---
status: open
type: grilling
blocked-by: [8]
---

# Keyboard navigation: every surface reachable without a mouse

## Question

Onboarding is largely mouse-driven today, and the app as a whole has never been walked with the keyboard alone. Decide what keyboard-friendly means here — tab order, default and cancel actions, visible focus, and escape behavior — and make every surface obey it: onboarding's welcome, permission rows, model progress, and try-it step; the About window; and the menu.

## Notes

- macOS gates this at the system level: "Keyboard navigation" in System Settings decides whether Tab reaches buttons and checkboxes at all, and it is off by default. Decide whether MiniWhisper honors that setting or opts its own windows in — a setup flow that cannot be completed without a mouse on a default macOS install is the failure case worth avoiding.
- Onboarding is sequential and each step has exactly one obvious action, which makes default-button semantics the backbone: Return should do the thing the step exists to do, and the button that gets it should look like it. The permissions page exposes one action at a time by design — that ordering is already decided and the keyboard path should follow it rather than invent a second sequence.
- The app is `LSUIElement`, so it has no menu bar of its own and windows do not get focus by mere existence. Establish what makes an onboarding or About window key when it appears, and what happens to focus when a grant arrives while the user is in another app.
- The pill is out of scope and should be stated as such: it is a nonactivating panel that must never take focus, and dictation-time state is driven by the hotkey, not by the keyboard focus ring.
- Escape already has a meaning in the gesture machine (`.escape` cancels a recording). Whatever Escape does in a window must not collide with that, and the two paths should be distinguishable in the reducer, not just visually.
- Menus are keyboard-navigable natively, so the menu's share of this is narrower: check that every item is reachable and that the ones that open windows hand focus over correctly.
- Verification belongs in the existing seam. [Agent-driveability](22-agent-driveability.md) already gives every element a stable identifier and a curated `mise run test-ui` manifest; keyboard order and default actions are assertable there, so the outcome should extend that manifest rather than start a parallel one.
