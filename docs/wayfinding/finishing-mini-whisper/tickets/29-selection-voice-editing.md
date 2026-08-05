---
status: open
type: grilling
blocked-by: [18]
---

# Selection voice editing

## Question

Proposed by the [competitor audit](../assets/25-competitor-feature-audit.md) after Aqua Voice's Edit Mode. Should a user-selected existing range be captured, sent through the sanctioned cleanup gateway, replaced, and locally undoable? Establish selection acquisition, target limits, privacy disclosure, failure fallback, and whether the current hold key may infer this mode from the presence of a selection.

## Notes

- The interesting part is not the rewrite model, which is [LLM cleanup](18-llm-cleanup.md)'s gateway doing ordinary work. It is that **selection makes the scope visible**: the user can see exactly what is about to be replaced before speaking, which no other feature in this app can claim.
- Aqua's shipped details worth stealing or rejecting deliberately: a chip showing the selection size, a deliberate fallback to ordinary dictation for search fields and selections over 6,000 characters, and a voice undo chain confined to the edit history rather than the system undo stack.
- Mode inference from selection state is the risky decision. The same hold key meaning two things is elegant when the selection is deliberate and hostile when it is stale — a selection the user forgot about turns a dictation into a destructive replacement.
- Depends on [FieldContext](../../../../Packages/FieldContext), which reads the caret's surroundings but does not today model a selected range. Establish what selection acquisition costs on top of the shipped capture, and whether the same targets that already fail context capture fail this too.
- Sends the user's existing text off-machine, which the shipped context capture never does. That is a privacy line worth naming explicitly, not assuming inherited from cleanup.
