---
status: closed
type: prototype
blocked-by: [42]
---

# Coded-speech corpus: prove the prompt on real dictations

## Question

**Rescheduled at the design review:** this spike runs *after* the cleanup pass is implemented. Once the real pipeline works end-to-end, recording the corpus and tweaking the prompt against it is much cheaper than staging either in advance. The shipped default prompt is chosen from the prior-art candidates at design time and refined here later.

Which built-in prompt (and which model) actually handles spoken technical language? Build a small recorded corpus of the user dictating coded speech across scenarios — explicit punctuation commands ("comma", "period", "colon"), spoken symbols (the proverbial "dash dash help"), and identifier recovery where the raw transcript says "API controller" but the provided field context contains `apiController` — each entry carrying the raw transcript, the staged context, and the intended output. Replay it through the [benchmark harness](../assets/38-cleanup-model-benchmark/) with the candidate prompts from [prompt prior art](42-cleanup-prompt-prior-art.md), across models, and judge by diff. HITL: the user records the corpus (the app's own history captures raw transcripts; context is staged per entry) and judges the outputs. Output: the chosen built-in prompt and evidence for the recommended-model shortlist feeding [ticket 39](39-recommended-cleanup-providers.md).

**Expanded at pickup:** the corpus now covers the whole vertical, not just the prompt — three recordable stages at [assets/43-dictation-corpus](../assets/43-dictation-corpus/): intelligibility (Harvard lists + confusables, WER per mic/noise condition), the sidecar (staged dictionary with recall and trap sentences), and polish (the original coded-speech scope: disfluency, spoken punctuation, symbols, identifier-from-context, and the rule invariants, each entry carrying say/expect/context). Scripts are committed for reuse across engines, boost configs, prompts, and models; every stage scores latency beside accuracy. `record.py` is the recording harness. Remaining: the user records, stages replay through their harnesses, and the diff judgment picks the shipped prompt.

## Resolution

Built, recorded, and driven through two tuning rounds; the prompt it produced ships in `CleanupPrompt.builtIn`. The corpus grew into a three-part instrument: the 76-entry recorded train set, a 228-variant [perturbation grid](../assets/43-dictation-corpus/results/prompt-tuning-haiku/perturbation/README.md) (templated, text-only, the train-side signal for rule work), and a 45-entry recorded [holdout](../assets/43-dictation-corpus/results/holdout/README.md) that is judged once per round and never tuned on — that split is what let worked examples back into the prompt safely. Verdicts it rendered along the way: the engine matrix and cleanup ladder ([rollup](../assets/43-dictation-corpus/results/README.md)), sidecar-vs-DICTIONARY-block (fed [profiles](47-cleanup-endpoint-profiles.md)), the per-provider latency answers (fed [presets](39-recommended-cleanup-providers.md)), and the tuned example-bearing prompt (method on [48](48-prompt-eval-automation.md), full history in [prompt-tuning-haiku](../assets/43-dictation-corpus/results/prompt-tuning-haiku/README.md)). Known ceilings, documented not fixed: compound dictionary traps, engine-mangled identifier fragments, meridiem casing. The instrument stays: new prompt work trains on the grid and answers to the holdout.
