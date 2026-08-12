---
status: open
claimed: fable-dictionary
type: grilling
blocked-by: [8]
---

# Dictionary: vocabulary hinting (stake 3)

## Question

Vocabulary hinting only — word remap/find-replace is excluded by the pruning. Parakeet/FluidAudio has no Whisper-style initial-prompt; investigate what hinting mechanism exists (custom vocab, biasing, post-pass?) and design the user surface (JSON list? file?).

The surface is two surfaces. The full one lists every word and supports edit and remove. The other is quick add: the moment a transcript comes back with a word mangled is the moment the word is known, so the menu bar needs one item that takes a typed word straight into the dictionary — open, click, type, done, no window. Design the full surface so quick add is a shortcut into it rather than a second path to the same data.
