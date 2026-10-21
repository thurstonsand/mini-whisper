# Prompt tuning round 3 — line breaks nobody asked for

[Ticket 48](../../../../tickets/48-prompt-eval-automation.md)'s third round, against material recorded after round 2: the [stage-3 layout arm](../../stage3-layout.jsonl) (16 multi-sentence entries), three [adjudicated field cases](../../field-cases.jsonl), and six [long-form passages](../../stage1-longform.jsonl). The tooling is [round 2's](../prompt-tuning-haiku/README.md) — `tune.py`, `perturb.py`, `leakcheck.py` — with a layout rule added to the grid and two harness gaps closed. The prompt that came out of it is `CleanupPrompt.builtIn` as it now stands; the candidate is `candidates/final3.txt`.

Two files are new here:

| file | what it does |
| ---- | ------------ |
| `breakrate.py` | re-judges a `tune.py` run on whitespace alone — spurious, missing, reshaped, intact — because an entry fails exact match identically whether cleanup split it across four lines or merely declined to write `6x` for "six times", and only one of those is a layout defect. |
| `shapes.py` | splits the layout grid by shape. The rule is three behaviours in one name (leave a paragraph alone, obey a spoken break, delete a hesitation) and a wording that buys one by selling another reads as flat in the pooled number. |

## The headline

**The rule works and the premise did not survive contact.** The wording that ships takes the no-break rate from **80.2% to 94.3% on gpt-oss-120b** and **95.3% to 98.4% on haiku**, at n=192 per cell, and costs nothing anywhere else that was measured. But the failure that prompted the round does not reproduce from its own audio under the shipped prompt on either model, and the two field cases that were supposed to be its evidence cannot be passed by any prompt, for reasons that have nothing to do with layout. The measurement that found the defect is the templated grid, not the field cases and not the corpus arm.

## Step 0 — can the scorer see the target?

Round 2's finding was that an optimizer aimed at an objective it cannot see will cheat. The layout arm's whole premise is that whitespace is meaningful, so that was checked before anything was scored.

`corpus_cleanup.py` judges stage 3 as `shape(content) == expect.strip()`. `shape()` strips the outer whitespace and peels the wrappers `CleanupResponseShaping` peels; it touches nothing inside. Twelve synthetic outputs confirm it:

| output | verdict |
| ------ | ------- |
| `layout-01` exactly | pass |
| the same with one `\n` inserted mid-paragraph | **fail** |
| the same with a Markdown hard break (`"  \n"`) — the field defect's own shape | **fail** |
| the same split on a blank line | **fail** |
| `layout-06`'s requested breaks, correct | pass |
| `layout-06` with the breaks flattened to spaces | **fail** |
| `layout-07`'s blank line downgraded to a single break | **fail** |
| `layout-08`'s list, correct | pass |
| `layout-08`'s list inside a Markdown fence | pass |
| `field-01` as it actually shipped | **fail** |

No fix was needed. The one forgiving case — a fenced list passing — is the app's own behaviour rather than a hole in the scorer, since `CleanupResponseShaping` unwraps the fence before the text is typed.

`leakcheck.py` was widened to `stage3-layout.jsonl`, `field-cases.jsonl`, and `stage1-longform.jsonl`, and to a field case's `engineRaw` and `shippedCleanup` alongside its `say` and `expect` — the same speech wearing different spelling. It earned the widening immediately: round 1's `baseline.txt` and `r2a.txt` turn out to quote **field-02** as well as `polish-39`, because the maintainer's real dictation and the corpus entry are both about "Grok with a Q". Everything shipped since round 2 is clean.

## Step 1 — the long-form side finding

Six Alice passages, 15 to 54 seconds, replayed through the pinned Parakeet artifact. Nothing else in this corpus is over fifteen seconds, so FluidAudio's chunk merger had never been measured by the instrument that measures everything else.

**It does not fall apart. Adjusted WER is 1.07% over 560 reference words, against 1.95% on stage 1's short sentences.**

| entry | audio | ref words | scored WER | adjusted WER |
| ----- | ----- | --------- | ---------- | ------------ |
| longform-03 | 15.3 s | 45 | 0.0% | 0.0% |
| longform-01 | 24.8 s | 57 | 10.5% | 0.0% |
| longform-05 | 33.8 s | 82 | 16.5% | 1.2% |
| longform-02 | 35.8 s | 89 | 15.4% | 2.2% |
| longform-04 | 52.9 s | 147 | 3.4% | 2.0% |
| longform-06 | 54.1 s | 140 | 4.9% | 0.0% |
| **total** | | **560** | **8.11%** | **1.07%** |

The 8.11% headline is two scoring artifacts and no engine failure. The script carries typographic quotation marks and the reader voiced them — "quote", "end quote", "parentheses" — so every quoted passage scores those as insertions; and `score_corpus.py`'s normalizer treats a curly apostrophe as punctuation, splitting the reference's `wouldn’t` into two tokens against the engine's one. The adjusted column removes the spoken markup and folds the curly apostrophes, which leaves six real errors in 560 words: `down stairs`/`downstairs`, `pine-apple`/`pineapple`, `currants`/`currents`, and one mishearing of `end parentheses` as `and parentheses`.

None of them is near a chunk boundary, and the two longest passages — 52.9 s and 54.1 s, four chunks each — are the second-cleanest and the cleanest in the set. The merger is doing its job. Latency scales with audio and stays trivial: 173 ms for 54 seconds.

The corpus should probably stop using typographic quotes in read-aloud material, or `stage1-longform`'s `say` should record what the reader was asked to voice. That is an instrument note, not an engine result.

## Step 2 — the baseline, and what it says about the premise

The shipping prompt (`candidates/baseline.txt`, byte-identical to round 2's `final2`), metered.

| arm | model | score | n |
| --- | ----- | ----- | - |
| stage3-layout, 16 entries | claude-haiku-4-5 | **7.10/16** | 10 |
| stage3-layout, 16 entries | gpt-oss-120b | 5.50/16 | 6 |
| stage3-layout, 16 entries | gemini-3.6-flash | 7.83/16 | 6 |
| field-cases, 3 entries | claude-haiku-4-5 | 1.00/3 | 10 |
| field-cases, 3 entries | gpt-oss-120b | 1.00/3 | 6 |

Then `breakrate.py` on the same runs, which is where the premise came apart:

| arm | intact | **spurious** | missing | reshaped |
| --- | ------ | ------------ | ------- | -------- |
| layout, haiku, n=10 | 140/160 | **0** | 10 (`layout-08`) | 10 (`layout-16`) |
| field cases, haiku, n=10 | 30/30 | **0** | 0 | 0 |
| layout, gpt-oss-120b, n=6 | 81/96 | 3 | 5 | 7 |
| field cases, gpt-oss-120b, n=6 | 17/18 | 1 | 0 | 0 |

**Haiku inserted no spurious break in 190 metered calls.** gpt-oss-120b — the model that produced both field failures on the release channel — inserted four in 114. So under the shipped prompt the defect is a few-percent event on one model, not the reliable behaviour the field report describes.

Two follow-ups, because a defect that will not reproduce is a measurement problem until proven otherwise.

**The prompt that shipped the failures was the older one.** The field cases are dated 2026-08-20 and 2026-08-21; round 1's prompt landed in `af6aed3` on 08-21. Extracted from `2f74ca5` as `candidates/pre-r1.txt` and replayed on gpt-oss-120b, it produces **zero** spurious breaks in 114 calls — fewer than the current prompt. So the older wording does not explain it either.

**The harness was not sending the whole request.** `corpus_cleanup.user_message` mirrored `CleanupPrompt.userMessage` except for `TARGET_BUNDLE_ID`, which the app always sends and which the prompt grants authority over "local formatting". Both field cases were dictated into Ghostty. That gap is now closed (`--bundle-id`), and staging the bundle does move the rate — but not stably:

| prompt | bundle | spurious | n |
| ------ | ------ | -------- | - |
| shipped | none | 3/60 (5%) | 20 |
| shipped | `com.mitchellh.ghostty` | 8/60 (13%) | 20 |
| pre-r1 | none | 1/60 (2%) | 20 |
| pre-r1 | `com.mitchellh.ghostty` | 2/60 (3%) | 20 |

At n=6 the same four arms ranked in a different order entirely. Round 2's lesson about single runs applies to the defect rate as much as to the score: 2% to 13% across four arms of twenty is not a mechanism, it is a floor. The bundle identifier is worth keeping in the harness because the app sends it and the replay should be the app's request, but it is not the explanation.

What the shipped cleanups *do* show, and no prompt here asks for, is a house style: sentence-initial `I` lowercased, terminal periods stripped, Markdown hard breaks. That is three coordinated deviations, and the prompt has one sentence that could license any of them — the additional-instructions channel. **Worth checking the release build's Settings before spending another round on this.**

### The field cases cannot be passed, and not because of layout

Both failing field cases were adjudicated by editing the broken cleanup rather than by writing the intended text fresh, so their `expect` values carry the defect's own damage:

- **field-01** expects `…don't worry about it I just wanted to call out…` — no sentence break at all, where the raw has `. I just wanted`. The period vanished when the hard break was flattened.
- **field-02** expects lowercase `i want`, `i said`, `i want` mid-sentence, and a colon where the raw has a period. The lowercase `i` is the shipped output's house style, not English.

Both are already correct on layout in every arm measured, and both fail on casing and punctuation no prompt should produce. **They need re-adjudication before they are worth scoring**; as they stand they are a 1.00/3 floor that never moves. `field-03`, the negative case, is the one that passes: the quoted `MM sidecar model` survives correctly under every prompt and every model tried, so nothing here is at risk of blindly deleting `mm`.

### The `mm` hypothesis is dead

The ticket guessed that a bare hesitation `mm` survives because the prompt's self-correction example uses `mm` to open a backtrack. Measured directly, on 96 templated hesitation variants per prompt per model: **the shipped prompt deletes the bare hesitation 99.0% of the time on haiku and 93.8% on gpt-oss-120b.** The corpus's own probe cannot even ask the question — `layout-11`'s raw shows Parakeet deleted the `mm` before cleanup ever saw it, and `layout-12`'s came back as `uh`. The hypothesis was reasonable and it is wrong.

## Step 3 — the layout grid

The corpus arm cannot see the defect: across 160 metered haiku runs it never once fired. Round 2's answer to a rule the 25-entry corpus is blind to was the templated grid, so `perturb.py` gained a `layout` rule — 24 variants over Harvard lists 4-20, in three shapes:

- **none** (12) — three or four carrier sentences, sometimes with a filler, dictated as one paragraph. `forbidden=("\n",)`. This is the defect.
- **asked** (6) — a spoken `new line` or `new paragraph` between two carriers. `required=(separator,)`. This is the exception that must survive.
- **hesitation** (6) — a bare `mm`/`um`/`uh`/`er` mid-sentence, which must be deleted without the break rule or the backtrack rule reading it as the start of something.

## Step 4 — expand, one change at a time

The licence being exercised is `restore sensible capitalization, punctuation, and paragraph breaks`. Two changes address it, and the ticket insists they be measured apart before they are measured together.

Rule rate on the **none** shape, n=36 per cell, one pass each:

| candidate | change | haiku | gpt-oss-120b |
| --------- | ------ | ----- | ------------ |
| `baseline` | — | 94.4% | 80.6% |
| `c1-narrow-licence` | drop `, and paragraph breaks` from the licence | 97.2% | 88.9% |
| `c2-explicit-rule` | licence kept, explicit no-break sentence added | 100.0% | 91.7% |
| `c3-both` | both, with a list exception | 100.0% | 97.2% |
| `c4-both-no-list` | both, no list exception | 100.0% | 97.2% |

Each half is worth roughly the same alone and they compound, which is the expected shape: removing a licence does not by itself state a rule, and stating a rule while leaving the licence in place is an argument the model has to settle.

**The list exception was rejected.** `c3` and `c4` differ by one clause — `or the words themselves are plainly a list`. It was written to protect `layout-08`, the corpus's one dictated list. `layout-08` fails **10/10 under all three prompts including the baseline**: haiku never formats it as a list, with or without permission to. So the clause buys nothing on the entry it exists for, and at n=8 it costs the hesitation shape on haiku (91.7% against `c4`'s 97.9%) and four points of exact rate on gpt-oss-120b. Round 2's rule holds — every added sentence is also an instruction about every other sentence — and a clause that only widens an exception, on a case no model can reach anyway, is licence without a customer. Dropped.

The surviving sentence, added after the `new line` / `new paragraph` definition:

> A line break is never invented: however many sentences the speaker dictates, they are one paragraph unless a break was asked for aloud.

### The measurement of record

Layout grid at **n=16**, 192 runs per shape-cell, metered:

| model | shape | baseline | final3 |
| ----- | ----- | -------- | ------ |
| gpt-oss-120b | **none** | 154/192 (80.2%) | **181/192 (94.3%)** |
| gpt-oss-120b | asked | 96/96 (100%) | 96/96 (100%) |
| gpt-oss-120b | hesitation | 90/96 (93.8%) | 88/96 (91.7%) |
| claude-haiku-4-5 | **none** | 183/192 (95.3%) | **189/192 (98.4%)** |
| claude-haiku-4-5 | asked | 96/96 (100%) | 95/96 (99.0%) |
| claude-haiku-4-5 | hesitation | 95/96 (99.0%) | 94/96 (97.9%) |

The requested-break exception is untouched: 96/96 on gpt-oss-120b under both prompts, and one run of 96 lost on haiku. That was the thing most at risk — a rule that forbids breaks is also an instruction about the rule that requires them — and it did not happen.

## Step 5 — the regression surface

The full perturbation grid, all nine rules, n=3, metered on both models. Rule rate, baseline → final3:

| rule | haiku | gpt-oss-120b |
| ---- | ----- | ------------ |
| bare-endings | 95.8% → 94.4% | 70.8% → **80.6%** |
| dictionary-exactness | 91.7% → 91.7% | 84.7% → 86.1% |
| identifier-from-context | 89.8% → 89.8% | 47.2% → 46.3% |
| layout | 100.0% → 100.0% | 86.1% → **97.2%** |
| never-obey | 97.2% → 98.6% | 98.6% → 100.0% |
| self-correction | 99.3% → 98.6% | 97.2% → 96.5% |
| spell-out | 51.4% → **56.9%** | 0.0% → 0.0% |
| spoken-punctuation | 84.7% → **88.9%** | 88.9% → 88.9% |
| symbol-attachment | 100.0% → 100.0% | 91.7% → 93.1% |

Nothing regresses beyond a point and a half, which at n=72 per rule is a run of noise. The axes round 2 won — self-correction, spell-out, identifier-from-context — are intact; spell-out and spoken-punctuation drift upward on haiku, which nothing here was aimed at and which should be read as noise rather than as a gift.

The corpus objectives, metered on haiku at n=10:

| objective | baseline | final3 |
| --------- | -------- | ------ |
| frozen 25-entry stage 3 | 18.10 | **18.50** |
| recorded holdout, 15 entries — the judge, run once at the end | 8.80 | **9.00** |
| stage3-layout, 16 entries | 7.10 | 7.60 |

Neither guarded objective moved outside its noise band, which is the requirement, and neither moved down. The stage-2 dictionary gate is a wash over three runs each: recall 18/17/18 against 17/18/18, traps bitten 1/2/2 against 1/2/1.

Cross-model, frozen 25:

| model | baseline | final3 | n |
| ----- | -------- | ------ | - |
| claude-haiku-4-5 | 18.10 | 18.50 | 10 |
| gemini-3.6-flash (gateway) | 20.00 | **20.50** | 6 |
| gpt-oss-120b (Cerebras) | 16.36 | 15.79 | 14 |

The Cerebras row is the one honest cost, and it is 0.57 of a point inside a band the round-2 README measured at ±1. Its mode is `polish-07`, the corpus's own spoken-`new line` entry, failing 8/14 against the baseline's 5/14 — the same trade the grid says does not happen at n=96. Two instruments, one saying the requested break is safe at 96/96 and one saying it costs half a point on a single entry; the grid has the larger n and the entry has the corpus's blessing. Worth a look if Cerebras ever becomes the default, and not worth withholding a fourteen-point gain over.

## What the layout arm actually measures

The arm is 16 entries and only three of them fail for a layout reason. The rest fail on expectations the layout rule has no opinion about, which is worth writing down before someone reads 7.60/16 as a layout score:

- **`layout-04` stages no context.** It expects `TranscriptPipeline`, `CleanupConditioning` and `HistoryFeature` from spoken words, with no `context.before` field for the identifier rule to resolve against. It fails 10/10 everywhere and always will. Either it gains a context block or it is not an identifier entry.
- **`layout-09` expects `6x`** where the engine delivered `six times`. Round 1 rejected a numbers-to-digits rule twice on the evidence of the corpus.
- **`layout-10` expects an em dash** where the raw carries a period. Nothing in the transcript records that the speaker meant one.
- **`layout-06` and `layout-07` get their breaks exactly right** in every run of every model and fail on the terminal periods, which their `expect` omits and every model supplies.
- **`layout-11` cannot test what it was written to test.** Parakeet deleted the `mm` before cleanup saw it — the same class of entry as `polish-11` and `polish-38`, a stage-1 result wearing a stage-3 label.

`layout-14`, the never-obey invariant, passes 10/10 under every candidate. `layout-08` and `layout-16`, the two list entries, fail everywhere: haiku will not turn a spoken enumeration into a numbered list, and no wording tried here changed that. That is the round's coverage gap, unfixed.

## The shipped change

Two edits to `CleanupPrompt.builtIn`, and nothing else in the Swift source. `candidates/final3.txt` is the text; `leakcheck.py` passes it against all nine corpus files and the grid vocabularies.

```diff
-…; restore sensible capitalization, punctuation, and paragraph breaks; and keep only the final wording of a correction.
+…; restore sensible capitalization and punctuation; and keep only the final wording of a correction.

 "New line" is a single line break; "new paragraph" is a blank line between paragraphs.
+A line break is never invented: however many sentences the speaker dictates, they are one paragraph unless a break was asked for aloud.
```

## Reproducing

```sh
set -a; . ../../../../../../.env; set +a          # ANTHROPIC_APIKEY, CEREBRAS_APIKEY, AIG_APIKEY
REPLAY=../../../../../../Packages/ASREngine/.build/release/asr-replay

# Frozen raws, once.
(cd ../.. && $REPLAY --stage stage3-layout.jsonl --recordings recordings/stage3-layout \
   --output results/prompt-tuning-r3/stage3-layout-raw.jsonl)
(cd ../.. && ./score_corpus.py stage1 stage1-longform.jsonl results/prompt-tuning-r3/stage1-longform.jsonl)

cd ../prompt-tuning-haiku
./leakcheck.py ../prompt-tuning-r3/candidates/final3.txt

# The headline: the grid, which is the only instrument that can see the defect.
./perturb.py --rule layout --repeat 16 --provider cerebras --out ../prompt-tuning-r3/grid/n16-cerebras \
  --prompt ../prompt-tuning-r3/candidates/baseline.txt --prompt ../prompt-tuning-r3/candidates/final3.txt
(cd ../prompt-tuning-r3 && ./shapes.py grid/n16-cerebras/*.json)

# The guards.
./tune.py stage3 --prompt ../prompt-tuning-r3/candidates/final3.txt --repeat 10          # frozen 25
./tune.py stage3 --holdout --prompt ../prompt-tuning-r3/candidates/final3.txt --repeat 10  # the judge, once

# A field case replays with the application it was dictated into, as the app sends it.
./tune.py stage3 --prompt ../prompt-tuning-r3/candidates/final3.txt \
  --script ../../field-cases.jsonl --raw ../prompt-tuning-r3/field-cases-raw.jsonl \
  --bundle-id com.mitchellh.ghostty --repeat 20 --output /tmp/field.json
(cd ../prompt-tuning-r3 && ./breakrate.py --per-entry /tmp/field.json)
```

Roughly 6,000 metered calls for the round, split between `api.anthropic.com` and `api.cerebras.ai`. The two-tier discipline was not needed: the model carrying the defect has no subscription transport, and haiku's arms were small enough to meter outright.
