---
status: closed
type: grilling
blocked-by: [8]
---

# Dictionary: vocabulary hinting (stake 3)

## Question

Vocabulary hinting only — word remap/find-replace is excluded by the pruning. Parakeet/FluidAudio has no Whisper-style initial-prompt; investigate what hinting mechanism exists (custom vocab, biasing, post-pass?) and design the user surface (JSON list? file?).

The surface is two surfaces. The full one lists every word and supports edit and remove. The other is quick add: the moment a transcript comes back with a word mangled is the moment the word is known, so the menu bar needs one item that takes a typed word straight into the dictionary — open, click, type, done, no window. Design the full surface so quick add is a shortcut into it rather than a second path to the same data.

## Resolution

Designed in [docs/designs/02-dictionary.md](../../designs/02-dictionary.md) (Accepted, amended through implementation) on two terra research reports — [the runtime's actual mechanism](../research/parakeet-vocabulary-hinting.md) and [what the paid apps really ship](../research/paid-app-dictionary-mechanisms.md) — and two spikes (tickets [33](33-quick-add-menu-spike.md), [34](34-quick-add-disclosure-spike.md)).

The answer to the hinting question: the pinned runtime exposes exactly one recognition-time mechanism — FluidAudio's CTC-sidecar rescorer (`parakeet-ctc-110m`, required asset alongside the speech model) — shipped default-on behind an "Improve recognition" toggle, gated stricter than upstream per MacParakeet's false-substitution evidence. Everything else is deterministic engine passes: correction pairs and taught-case repair, case-insensitive, word-boundary, longest-match-first, single pass. Measured sidecar cost: +207 ms release→delivered with a non-empty dictionary; zero when off or empty.

The surface landed as designed: one mixed-list Dictionary pane (History's dialect — shared file storage, cursor laws, hover trash, add/edit sheet) over `dictionary.json` in `Packages/SpeechDictionary`, and quick add as the spike-settled accordion in the status menu — collapsed native-parity row, one-way expand, misheard-as disclosure, shake on invalid, taught-only degrading to vocabulary. Landed across `d30b35f` (engine + data), the pane/quick-add commit, and the boost commit.
