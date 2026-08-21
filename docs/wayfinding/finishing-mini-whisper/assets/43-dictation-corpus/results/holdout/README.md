# Holdout — fresh audio, scored once

Forty-five entries (fifteen per stage; the first fifteen scored 2026-08-20, the extension recorded and scored the same night). Originally fifteen entries (`stage{1,2,3}-holdout.jsonl`) authored after the [prompt tuning](../prompt-tuning-haiku/) concluded, with all-new content on the same axes, recorded on the same built-in microphone, and never shown to any tuning loop. One scoring pass, no iteration: this directory answers whether the tuned prompt's in-sample gain survives inputs it has never seen. Raw transcripts are Parakeet via `asr-replay`; cleanup is claude-haiku-4-5 via Anthropic direct, n=10 per arm on stage 3, n=4 on the stage-2 block arm.

## What transferred perfectly — every architecture verdict

- **Stage 1: 2.46% WER** over 122 reference words (Harvard lists 2 and 3) at 56 ms median — in line with the training set's 1.95%.
- **The sidecar tradeoff replicated and worsened with more traps**: bare misses Zigbee/FluidAudio/XCUITest/Qwen/llama.cpp; boost recovers all but "Quin3" and bites **three of six traps** — "a ghastly chill" → "A Ghostty chill", "the cerebral scan" → "the Cerebras scan", and his literal keychain capitalized into the product. +98 ms, same overhead as in-sample. Parquet and story-time held.
- **The DICTIONARY block replicated exactly** (first-fifteen run): shipped prompt, bare raw, full 15-term vocabulary staged — **16/16 recall, 0/8 traps** (n=4). It recovered `Zigby → Zigbee` and `Fluid Audio → FluidAudio` from text alone. The block-beats-sidecar finding is not an artifact of the training sentences.

## What did not transfer — the stage-3 prompt gain

| arm | mean (of 15, n=10) |
| --- | --- |
| baseline (incumbent) | 7.7 |
| final (shipped) | 7.3 |

The in-sample +1.1 does not appear on fifteen fresh entries; the two prompts are statistically indistinguishable out-of-sample. Decomposed per entry (passes /10, final arm):

| entry | axis | base | final | reading |
| --- | --- | --- | --- | --- |
| hpolish-02 | symbols, flag | 10 | 10 | the symbol rule generalizes fully |
| hpolish-05 | numbers, time | 2 | 5 | the tuned time work transfers (+3); residual miss is `AM` vs `a.m.` |
| hpolish-03 | identifier, context | 3 | 0 | **regression**: Parakeet wrote `retryQ`; base sometimes expanded it to `RetryQueue` from context, final never does — the tuned context-scope wording reads as more conservative about rewriting engine-mangled tokens (`onFailure` is written correctly by both) |
| hpolish-04 | spell-out | 0 | 0 | the known finding, confirmed fresh: without its example haiku cannot construct a spell-out (`zero with an X` → `0x`) |
| hpolish-01 | disfluency, restart | 0 | 0 | both prompts keep the pre-correction false start; the user adjudicated the aggressive expectation as **correct** — the self-correction rule under-reaches |

The ten stumble entries (hpolish-06…15) sharpen that under-reach into a pattern:

- **Repairs generalize**: repetition (06), "scratch that" (08), "I mean" (09), the double correction "Tuesday, no Wednesday, no wait, Thursday" (12), and the backtrack-erased spell-out (13) all pass **10/10 under both prompts**. The rule is not broken; it is narrower than the adjudication wants.
- **Soft backtracks after a complete clause fail**: "Merge it tonight, actually no, wait for CI" (07, 0/10) and "So the fix is, hold on, just revert" (10, 0/10) keep the abandoned clause — exactly hpolish-01's shape. The model erases on explicit erasure verbs ("scratch that", "no wait") and preserves when the backtrack reads like continuation ("actually no", "hold on"). That distinction is the next tuning round's one target, with the perturbation grid as train-side signal.
- **Two of my expectations need the user's call**: hpolish-11 fails only on `forty-five` vs `45` (the repair itself works — thirty is erased every time; digits-vs-words for spoken durations is an open convention), and hpolish-14 fails 9/10 only on a missing final period when the raw ended unpunctuated (the disfluencies are cleaned perfectly; should a complete sentence get a period the speaker never said?).

## Round 2 — judged once more, and this time it moved

The [perturbation sweep](../prompt-tuning-haiku/perturbation/) turned this file's five diagnoses into twenty-four fresh variants apiece, a tuning round was run against *that* — never against these fifteen — and the result was brought back here for a single scoring pass, both arms, n=10, same session.

| arm | mean (of 15, n=10) |
| --- | --- |
| round 1 (`final`, the prompt shipped above) | 7.5 |
| **round 2 (`final2`, shipped now)** | **9.1** |

Everything this file diagnosed as a rule gap and nothing it diagnosed as a ceiling:

| entry | axis | round 1 | round 2 | reading |
| --- | --- | --- | --- | --- |
| hpolish-07 | backtrack, "actually no" | 0/10 | **10/10** | the soft-cue clause deletion, fixed |
| hpolish-14 | disfluency, final period | 1/10 | **8/10** | the missing full stop mostly stops missing |
| hpolish-15 | backtrack + symbols | 9/10 | **10/10** | — |
| hpolish-02 | symbols, flag | 9/10 | **10/10** | the restored symbol example |
| hpolish-05 | numbers, time | 6/10 | 3/10 | unchanged mechanism; the meridiem is the engine's casing, `AM` against `a.m.` |
| hpolish-01 | backtrack, restart | 0/10 | 0/10 | **the clause is now deleted**; it fails on a surviving `So` — `So hold off until the tests finish.` |
| hpolish-10 | backtrack, "hold on" | 0/10 | 0/10 | the one shape that resisted: `So the fix is just revert the last commit` reads the cancelled fragment as a lead-in and welds it to the correction |
| hpolish-03 | identifier, mangled token | 0/10 | 0/10 | `onFailure` is right every time, `retryQ` never expands; the sweep says 27/36 at n=36 and this fragment is in the refused set |
| hpolish-04 | spell-out | 0/10 | 0/10 | the rule now fires half the time on fresh material, but this entry wants letters *deleted*, not substituted |
| hpolish-11 | numbers, repair | 0/10 | 0/10 | still only `forty-five` against `45`; the repair itself has always worked |

So the +1.6 is four entries recovered and none lost, and two of the remaining zeros are now near-misses of a rule that fires rather than silences of a rule that does not. The two open expectation questions from the first pass are still open and still the user's: `hpolish-11`'s digits-versus-words, and `hpolish-05`'s meridiem casing, which no cleanup pass can know the speaker's preference for.

Artifacts: `r3-final.json` and `r3-final2.json`, both arms, every run.

## Reading

Round 1's reading, left as written: the corpus's *architecture* conclusions — engine choice, where vocabulary lives, block over sidecar — generalize without qualification. The *prompt-tuning* gain is at least partly in-sample: one tuned rule travels (time), one was neutral-to-harmful out-of-sample (identifier conservatism), and the two structural failures (spell-out, restart adjudication) fail identically under both prompts. Five entries cannot rank prompts finely — but they are enough to say the tuned prompt is no better than the incumbent out-of-sample, and that future tuning rounds should hold these fifteen sacred and grow them.

Round 2 did hold them, tuned against templated material instead, and came back +1.6. That is the sequence this file was built to make possible: the holdout says *what is broken*, a generated grid says *whether a fix generalizes*, and the holdout is spent once at the end to say whether any of it was real.

Artifacts: `stage1.jsonl`, `stage2-{bare,boosted}.jsonl`, `stage3-raw.jsonl` (Parakeet replays), `stage3-pooled.json` (both arms, all runs, top misses), one full run per arm (`stage3-{baseline,final}-run1.jsonl`).
