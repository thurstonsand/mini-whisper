# Prompt tuning round 5 — compression, and the words that would not leave

[Ticket 48](../../../../tickets/48-prompt-eval-automation.md)'s fifth round. The incumbent was 572 words. This round asked a different contraction question from round 1's rule deletion and round 4's register rewrite: how short can the same rules become before one stops working?

The answer is **524 words, down 48 words or 8.4%, and it ships** as `candidates/hand-524.txt`. A 300-word prompt was not hiding inside the prose. The first hand composition near that target broke whole-clause correction, unspoken paragraphing, spell-out, and identifiers. Putting back only the measured failures produced a 524-word floor that ties every guard. The recorded holdout is 9.40/15 in both arms at n=10, the frozen objective is 17.00 against 16.75/25 at n=20, and the layout arm improves both sides of its actual question: unspoken breaks 77/80 → 79/80 and single-subject text left whole 218/220 → 220/220, n=20.

Every number here uses `sdk-haiku`, the subscription transport established in round 4. No Anthropic API, Cerebras, Gemini, or other metered scorer was used. Scores are compared only with round-5 re-baselines on the same transport.

## Method

The hand arm replaced one of the incumbent's seven paragraphs at a time. Each paragraph got medium, short, and brutal rungs, while the other six remained byte-for-byte unchanged. Screening used n=6 on the frozen 25 and the rule's perturbation arm; fragile and surviving wordings were repeated at n=10 to n=20. The four worked examples were then measured separately at full length, compact form, and absent. Only after those isolated runs were complete were the survivors composed.

`build_candidates.py` contains every hand-authored rung and reproduces the files under `candidates/`. `leakcheck.py` passes every candidate at three consecutive corpus words and five exemplar words. The scoring model never proposed hand-arm wording.

The second arm used Sol through the maintainer's ChatGPT subscription. `propose.py --compress --proposer-provider codex-sol` generated a guarded second opinion, while SDK Haiku remained the scorer. That arm is reported separately below because the automated loop optimized the frozen split and did not know the guard grid.

## The paragraph ladder

The score column names the measurement that decided the paragraph. A rule rate is the perturbation grid's behavioral rate, not exact match on unrelated Harvard punctuation.

| paragraph | incumbent | shortest tried | shipped | what the cut was worth |
| --------- | --------: | -------------: | ------: | ---------------------- |
| role | 22 | 4 | 22 | The four-word rung held never-obey rule rate at 95.1% against 95.8%, n=6, but unspoken paragraphing fell to 34/40 at n=10. The paragraph rule reads its surroundings, so these 18 words came back. |
| tagged-source guard | 39 | 6 | 39 | The maintainer's nine-word form scored 92.4% against 95.8% on never-obey, n=6, and 34/40 against 38/40 on unspoken paragraphing, n=10. The six-word rung did no better on exact output. The short sentence preserved the proposition and weakened the order. |
| fidelity and scope | 34 | 7 | **15** | The chosen rung, `Edit only TRANSCRIPT. Preserve every detail and purpose. Add nothing; do not summarize or translate.`, held bare endings at 98.3% against 99.0%, n=12. In the final composition it scored 100% against 97.5%, n=10. Nineteen words were enumeration rather than instruction. |
| ordinary edits, backtracks, bare endings | 123 | 42 | 123 | The 60-word rung cut whole-clause backtracks from 44/48 to 28/48, n=6. A 99-word repair tied self-correction in isolation at 99.0%, n=12, then made the composed grid lose bare endings and bare hesitations. The paragraph came back whole. |
| typing commands, layout, symbols, spelling | 237 | 83 | **208** | The shipped cut retains the emphatic paragraph rule and full spell-out construction while shortening mechanical enumeration. On its rule arms it tied or improved layout, spell-out, spoken punctuation, and symbol attachment at n=10. In the final prompt it produced 79/80 unspoken breaks and preserved 220/220 no-break controls, n=20. |
| dictionary and context | 101 | 24 | 101 | The 46-word rung tied its own arms in screening: dictionary 91.7% and identifier 87.5% in both arms, n=6. The full grid caught the cross-rule cost: spell-out fell 59.2% → 53.8%, n=10. Fifty-five apparently local words were context for a different rule, so they came back. |
| output shape | 16 | 4 | 16 | The 11-word rung held never-obey rule rate at 95.8%, n=6, but unspoken paragraphing moved 38/40 → 37/40 at n=10. Five words were not worth another cross-rule edge. |
| **total** | **572** | **170 if every brutal rung were composed** | **524** | **48 words removed; every final guard held.** |

The fidelity paragraph was the closest thing to pure fluff: its seven-item preservation list, five-item no-add list, and three named rewrite prohibitions collapsed to `Preserve every detail and purpose. Add nothing` without losing a guard. No whole paragraph was disposable. That distinction matters; round 1 had already tested deletion, and this round found that even semantically unrelated framing changes the paragraph and spell-out thresholds.

## The words put back

The intermediate names in `runs/` record a less graceful story than a single before-and-after table, and a more useful one.

| waypoint | words | result | verdict |
| -------- | ----: | ------ | ------- |
| `p5-optimized` inside otherwise incumbent text | 513 | 62/80 unspoken breaks against 77/80, n=20 | rejected; compressing the full spell construction changed the context of the exact paragraph order |
| `hand-survivor` | 384 | 70/80 unspoken breaks, n=20 | rejected; restoring the exact order was not enough after its surrounding paragraphs changed |
| `hand-incumbent-p5` | 413 | 40/40 unspoken breaks but only 105/110 no-break controls, n=10 | rejected; it crossed the threshold by over-applying it |
| `hand-stable` | 437 | 80/80 unspoken breaks, n=20, then bare endings 93.8% against 98.3% and layout-grid rule rate 91.7% against 99.6%, n=10 | rejected; the 99-word correction paragraph had lost words the composition needed |
| `hand-safe2` | 469 | bare endings 96.5% against 97.9%, n=20 | rejected; the seven-word fidelity rung was too broad once composed |
| **`hand-524`** | **524** | all confirmation guards tie, below | **ships** |

The correction paragraph was load-bearing to the example, not merely to the rule. With the incumbent sentence, whole-clause backtracks passed 79/80. A shorter invented example passed 61/80. Removing the example passed 48/80, all at n=10. The full worked construction stays.

The paragraph order was load-bearing to the fence. Its 69-word incumbent form produced 77/80 unspoken breaks in this round's re-baseline, n=20. A 50-word form that kept `must`, `find every place`, and `required, not optional` but compressed the one-subject fence produced 72/80. A 63-word form that shortened only the redundant two-subject sentence produced 79/80. Inside the more compressed command paragraph, however, even that five-word saving helped drive the result to 62/80. The words that survived are the emphatic ones and the exact boundary around them. Round 4's least elegant instruction remains stubbornly employed.

## Worked examples, one at a time

| example | full | compact | absent | verdict |
| ------- | ---- | ------- | ------ | ------- |
| whole-clause backtrack | 79/80 | 61/80 | 48/80 | Keep the incumbent example and its framing. Rule rate on the whole-clause shape, n=10. |
| symbol attachment | 240/240 | 240/240 | 204/240 | Compact safely. Rule rate, n=10. The shipped paragraph keeps the example in a shorter sentence. |
| spelling aside | 61.8% | 43.8% | 10.4% | Keep a full construction. Rule rate over 288 runs, n=12. A middle 34-word version that retained both spelling shapes and the full carrier tied at 59.0% against 57.6%, n=12, but combining it with other paragraph cuts suppressed unspoken paragraphing. |
| context declaration | 300/360 | 290/360 | 219/360 | The example remains load-bearing, especially on declarations: 103/120 full, 95/120 compact, 33/120 absent, n=10. The shipped prompt keeps it unchanged. |

The cheap examples were not cheap. The symbol example alone compressed cleanly; the other three either stayed or brought their governing paragraph down with them.

## Sol's 328-word second opinion

`propose.py` now has a proposer-only `codex-sol` transport over ChatGPT OAuth. It reads `~/.pi/agent/auth.json`, refuses to start with less than fifteen minutes of access-token life, posts the Responses body to ChatGPT's Codex backend, and parses SSE output deltas. Scoring still goes through SDK Haiku. A live one-call transport smoke test returned the requested exact word.

The guarded compression loop ran three rounds of six candidates, n=4 on alternating halves of the frozen objective. One of eighteen proposals was rejected for leaking corpus triples. The selected 328-word prompt improved the training half from 8.75/13 to 9.00/13 and scored 7.00/12 on the unseen half, n=4. It did find a much shorter and readable prompt. The grid found what its objective could not:

| rule | incumbent | Sol 328 | n | verdict |
| ---- | ---------: | ------: | -: | ------- |
| identifier from context | 88.9% | **80.0%** | 10 | rejected |
| never obey | 97.1% | **94.6%** | 10 | rejected |
| spell-out | 57.5% | **51.2%** | 10 | rejected |

The bounded repair transplanted each incumbent rule alone.

| transplant | resulting words | incumbent | Sol base | repaired | n |
| ---------- | --------------: | --------: | -------: | -------: | -: |
| never-obey paragraph | 342 | 96.5% | 91.0% | **99.3%** | 12 |
| identifier rule and declaration example | 355 | 84.5% | 74.8% | **83.8%** | 12 |
| full spell-out rule and example | 376 | **59.4%** | 51.7% | **54.2%** | 12 |

Never-obey cost fourteen words and identifier cost twenty-seven. Both recovered. Spell-out cost forty-eight words and still remained 5.2 points below the incumbent. All three exact transplants produce a 417-word prompt before any full-grid confirmation, and the spell rule is still below its gate. Replacing Sol's whole command paragraph with the incumbent's would put that route at 459 words before the other two repairs and 500 after them, by word-count arithmetic. That is materially the 524-word hand result, with less direct evidence behind the remaining rules, so the repair stopped at its declared bound.

Sol found the attractive 328-word shape and nothing the hand ladder missed about the floor. The second opinion was useful precisely because its three failures independently rediscovered the same load-bearing examples and guard wording.

## Confirmation and shipping

`hand-524` against the round-4 incumbent, subscription transport throughout:

| guard | incumbent | `hand-524` | n |
| ----- | --------- | ---------- | -: |
| frozen 25 | 17.00 | 16.75 | 20 |
| recorded holdout, 15 entries, run once at the end | 9.40 | 9.40 | 10 |
| dictionary wants recall | 17/18 in all three runs | 17/18 in all three runs | 3 |
| dictionary traps bitten | 1, 1, 2 | **1, 1, 1** | 3 |
| layout no-break controls | 218/220 | **220/220** | 20 |
| layout unspoken breaks | 77/80 | **79/80** | 20 |
| layout requested breaks | 40/60 | 40/60 | 20 |

The frozen delta is one quarter of an entry and the holdout is exact. The full nine-rule confirmation, n=10:

| rule | incumbent | `hand-524` |
| ---- | ---------: | ----------: |
| bare endings | 97.5% | **100.0%** |
| dictionary exactness | 92.1% | 92.1% |
| identifier from context | **88.9%** | 87.8% |
| layout | 98.8% | **99.6%** |
| never obey | **97.9%** | 97.5% |
| self-correction | **99.6%** | 99.4% |
| spell-out | 56.7% | **62.9%** |
| spoken punctuation | 91.2% | 91.2% |
| symbol attachment | 100.0% | 100.0% |

No rule moves backward by more than 1.1 points; round 4's accepted noise band was 2.1 points. Four improve, two tie exactly, and three are inside that band. `leakcheck.py` passes, and all 54 `TranscriptCleanup` tests pass. The prompt therefore meets the ticket's shipping rule and now lives in `CleanupPrompt.builtIn`.

## Reproducing

```sh
cd ../prompt-tuning-r5
./build_candidates.py
../prompt-tuning-haiku/leakcheck.py candidates/hand-524.txt candidates/auto-sol/best.txt candidates/auto-repaired/*.txt

cd ../prompt-tuning-haiku
./perturb.py \
  --prompt ../prompt-tuning-r5/candidates/incumbent.txt \
  --prompt ../prompt-tuning-r5/candidates/hand-524.txt \
  --repeat 10 --out ../prompt-tuning-r5/runs/hand524-final-grid

./tune.py stage3 --prompt ../prompt-tuning-r5/candidates/hand-524.txt \
  --script ../../stage3-layout.jsonl --raw ../prompt-tuning-r4/stage3-layout-raw.jsonl \
  --include-excluded --repeat 20 \
  --output ../prompt-tuning-r5/runs/layout20-hand-524.json
(cd ../prompt-tuning-r4 && ./layoutrate.py --per-entry \
  ../prompt-tuning-r5/runs/layout20-{incumbent,hand-524}.json)

./tune.py stage3 --prompt ../prompt-tuning-r5/candidates/hand-524.txt --repeat 20
./tune.py stage3 --holdout --prompt ../prompt-tuning-r5/candidates/hand-524.txt --repeat 10

./propose.py --prompt ../prompt-tuning-r5/candidates/incumbent.txt \
  --compress --rounds 3 --candidates 6 --repeat 4 --holdout --reject-leaks \
  --proposer-provider codex-sol --out ../prompt-tuning-r5/candidates/auto-sol
```

All model calls in this round used the maintainer's Claude or ChatGPT subscriptions. There is no metered-provider command here. Sensible, for once.
