# Prompt tuning round 7 — from scratch, by subtraction, and judged

[Ticket 48](../../../../tickets/48-prompt-eval-automation.md)'s seventh round, four questions from the maintainer after round 6 shipped (2026-10-25):

1. **Start from scratch.** Ignore the shipped prompt and its lineage, write fresh candidates for `claude-haiku-5-5` from the rules and plain diagnoses of failures, never from corpus entries, and compare the winners against round 6.
2. **Subtraction.** Find the smallest prompt that still scores well: leave-one-out ablation and a length-against-score curve on round 6 and on any from-scratch winner, and another look at round 6's parked compression pass.
3. **Tolerant scoring.** Count near-misses such as an optional comma as correct, after a survey of what exists, and make the judged score the primary metric with exact match beside it.
4. **Transport.** Establish what CLIProxyAPI injects, and whether it can be cut to the one identity line the Claude subscription requires.

The short answers:

1. **A from-scratch prompt beats round 6 on the objective and the holdout, and loses two rules.** Eight generations of Sol writing from a specification and diagnoses produced `candidates/gen7/r1.txt`, 943 words. Same session, n=10, judged: frozen 25 **18.90 → 22.20** (exact 16.20 → 20.10), recorded holdout **10.30 → 12.40** (exact 8.80 → 10.40). It is ahead on identifiers, spoken punctuation, and never-obey. It is behind on spell-out (42% → 21%), dictionary exactness, unrequested paragraph breaks (88% → 68%), and the dictionary gate (17 → 16/18). It is not shipped; see [Not shipped, and why](#not-shipped-and-why).
2. **Round 6 has nothing to give; the from-scratch prompt has about 200 words.** Both lineages wrote their way to about 950 words. Every round-6 section the frozen set cannot see turned out to be load-bearing on the grid, and the four cuts the grid tolerated cost 1.6 frozen points together; the compression pass stays parked. `gen7/r1` cut to **747 words** scores 22.70 frozen and 12.10 holdout at n=10, still well ahead of round 6, and gives up about five points of spoken punctuation and four spurious breaks in 66.
3. **The judge is the headline now.** `judge.py` agrees with 71 of 72 calibration labels and 33 of 33 held-out labels, κ 0.93 and 1.00. Every historical arm was rescored, and `tune.py` prints judged first and exact beside it. No hosted grader was worth a key.
4. **CLIProxyAPI cannot be cut to one line by configuration, and it moves our prompt.** For a subscription credential on `claude-haiku-5-5` it sends our system prompt as a system turn *after* the transcript, behind the identity line and a date reminder. The app sends it as the system prompt. Two configurations get closer; both are changes to pod042 and one risks metered billing, so neither was applied.

All Haiku calls ran through `proxy-haiku` on the Claude subscription and every Sol call through the ChatGPT subscription. No metered provider was opened.

## Tolerant scoring

`polish-11` started it. The maintainer ruled `She said, "It ships tonight."` and `She said "it ships tonight."` both correct, and asked that anything similarly close count. Exact match grades the expectation's house style as much as the cleanup.

### What exists

A survey of LLM-as-judge practice, hosted graders, and deterministic metrics, read-only, landed on four findings.

- **OpenAI's graders are not worth a key.** `string_check` and `text_similarity` are rapidfuzz, BLEU, and ROUGE, which run locally for free. `score_model` and `label_model` bill per token. The Evals platform goes read-only on 2026-10-31 and shuts down on 2026-11-30, and graders are deprecated with it.
- **The "decisions" API is real but metered.** `POST /v1/decisions` on `gpt-6-luna` answers typed predicate, choice, and score questions with calibrated probabilities, at $0.10 per million input tokens. A rescore here would cost about a cent, still metered, and it gives no rationale to audit.
- **Similarity thresholds are the wrong shape.** `/user/` against `/usr/` is a one-character edit, the same size as an acceptable comma. Tolerance has to come from deciding which differences are style, not from a distance.
- **Published practice matches what was built.** That means a reference-guided single-answer judge with a rubric, a judge from a different model family from the one under test, several votes, and calibration against human labels. MT-Bench, simple-evals' `EQUALITY_TEMPLATE`, and Inspect's graded QA all take that shape. The off-the-shelf "factuality" graders, such as Braintrust's, explicitly ignore punctuation, and some of this corpus's real failures are punctuation.

"jev" is most likely **Jev**, TypeSafe AI's decision model, launched 2026-09-15 and offered as a judge in LangSmith, MLflow, and Braintrust. It is metered, and its own benchmarks put it weakest on fine-grained, rubric-based judgments of generated text, which is exactly what `/usr` against `/user` is. A local Jev-compatible model, Kev, exists if the idea is worth a side experiment. It is not certain that this is what was meant; it could also be a slip for `jiwer`, the WER library.

### The judge

`../prompt-tuning-haiku/judge.py`. Only exact-match failures are judged, so it can only raise a score. Sol is the judge, a different family from the Haiku under test. It sees what the speaker said, the entry's tags, the expected text, and the output. It votes three times and the majority decides. The rubric accepts style choices the speaker never dictated: optional punctuation, quotation and capitalization conventions, numeral or word, an ordinal suffix, a meridiem's form. It rejects changed words, unapplied commands and backtracks, any difference in a symbol, identifier, path, or dictionary term, added formatting, extraction, and answering. "When unsure, reject."

Verdicts are cached in `judge-verdicts.jsonl`, keyed by a hash of the rubric (`6467b5a6714e`). A rescore years later gets the same verdicts, and a changed rubric re-judges everything instead of mixing two standards.

| label set | pairs | agree | κ | false accepts | false rejects |
| --------- | ----: | ----: | -: | ------------: | ------------: |
| `judge-calibration.jsonl`, hand-labelled before the judge first ran; the rubric was revised once against it | 72 | 71 | 0.93 | 1 | 0 |
| `judge-heldout.jsonl`, 33 later outputs from this round's gen-1 runs, labelled before their verdicts were read, never used on the rubric | 33 | 33 | 1.00 | 0 | 0 |

The one false accept is `hpolish-08`'s lowercase "rename the variable instead.", passed on a 2–1 split. The held-out set is one accept and 32 rejects, so it tests mostly leniency, which is the judge's risk. Every lenient pass on this round's finalists was read by hand: numerals for number words (`at 3`, `to 5`), a comma after an opener (`Okay, so`, `So,`), a capital on an unfinished dictation, optional commas in long prose, meridiem forms. The questionable one is `11.30am` for `11:30 a.m.` on the holdout, a 2–1 split that does not affect either finalist.

`tune.py stage3` now runs the judge on every arm and prints `judged … (exact …)`. Its JSON keeps both, with the rubric id. A tuning run therefore needs both subscriptions.

### The history, rescored

Exact → judged, on the same runs.

| arm | model | exact | judged | n |
| --- | ----- | ----: | -----: | -: |
| round 5 `hand-524`, frozen 25 | haiku-4-5 | 16.75 | 18.75 | 20 |
| round 5 on 5.5, frozen 25 | haiku-5-5 | 7.40 | 9.30 | 10 |
| round 6 `final-r6`, frozen 25 | haiku-5-5 | 14.00 | 16.45 | 20 |
| round 5 incumbent on 5.5, holdout | haiku-5-5 | 6.90 | 8.40 | 10 |
| round 6 `final-r6`, holdout | haiku-5-5 | 8.30 | 10.00 | 10 |
| round 6 on Cohere raw, frozen 27 | haiku-5-5 | 13.80 | 17.20 | 10 |
| round 6 on v2 control, frozen 27 | haiku-5-5 | 15.50 | 18.00 | 10 |
| round 6 on Cohere raw, holdout | haiku-5-5 | 12.80 | 12.80 | 10 |

The ordering of every comparison in rounds 5 and 6 survives. `polish-11` on Cohere now passes 10 of 10: both prompts write the quotation Cohere hears, and the judge accepts its comma and capital. Full output: `runs/rescore.txt`.

## From scratch

`write_fresh.py` is the author. Generation 1 sees two files and nothing else: no shipped prompt, no candidate, no corpus entry.

- `spec.txt` is the required behaviour, written from `CleanupPrompt`'s contract: the tagged fields, the Additional Instructions sentence, and thirteen rules.
- `diagnosis.txt` describes the target model, `claude-haiku-5-5`, by its measured habits in plain words.

Each of six candidates was given a different shape to write in: a numbered list, prose, rules with examples, as short as possible, headed sections, or most-violated first. Later generations revise one winner from a hand-written diagnosis of that winner's own failures, `diagnosis-gen*.txt`, phrased in behaviours and checked by `leakcheck.py` before Sol saw it. `propose.leaked` rejects any proposal that quotes three corpus words; a rejected one is resampled up to three times rather than edited by hand.

| gen | base | best | words | frozen judged | frozen exact |
| --- | ---- | ---- | ----: | ------------: | -----------: |
| 1 | spec only | `gen1/f6` | 363 | 12.33 | 11.17 |
| 2 | `f6` | `gen2/r4` | 511 | 15.33 | 14.17 |
| 3 | `gen2/r4` | `gen3/r3` | 632 | 16.00 | 14.33 |
| 4 | `gen3/r3` | `gen4/r6` | 747 | 18.17 | 17.17 |
| 5 | `gen4/r6` | `gen5/r2` | 876 | 21.00 | 19.83 |
| 6 | `gen5/r2` | `gen6/r1` | 928 | 22.17 | 19.83 |
| 7 | `gen6/r1` | `gen7/r1` | 943 | 22.00 | 19.83 |
| 8 | `gen7/r1` | `gen8/r3` | 1012 | 21.67 | 20.00 |
| control | | `final-r6` | 965 | 18.50 | 15.67 |

Screening is n=6 on the frozen 25. Each row is the best of six, scored with `final-r6` as the control in the same session. A short lineage from gen 1's 213-word `f4` reached 15.83 judged at 353 words in one generation (`short-gen2/r3`). That is 37% of round 6's length for 86% of its frozen score, but its grid spell-out was 6% and identifiers 61%.

What the generations learned, by behaviour:

- **Generations 2 and 3 restated rules and moved little.** Revising toward a diagnosis in other words did not fix a spoken period after an engine comma, an email address returned alone, a half-fixed compound pronoun, or a spelling aside. All four survived both revisions.
- **Generation 4 asked for one invented example per failing surface pattern, and that worked:** +2.2. The first attempt was rejected in full. Asked for the exact failing shape, Sol's first-choice examples were the corpus's own phrases, such as a common name with a spelled letter or a pair of spoken commands, so all six collided with the leak check. The diagnosis then asked for unusual invented words, and the examples became `qorven at ulmira dot invalid period` and `Tirn, with a Y`.
- **Generation 5 named why each rule failed,** for example "the model treats an address as the answer the user wants", and passed round 6 on the frozen 25 and the holdout.
- **Generations 6 and 7 fixed the paragraph rule by moving it.** Gen 5 inserted no unrequested break at a subject change, 0/40 on the layout arm, while round 6 gets 88%. Gen 6 strengthened the wording and got 2/24. Gen 7's diagnosis said only that the rule opened with a prohibition, "add no line breaks unless dictated", so the model obeyed the opening and read the requirement as optional. Leading with the required break took it to 16/24 at n=6 and 27/40 at n=10, with no spurious break on any of 110 single-subject controls.
- **Generation 8 aimed at spell-out and the dictionary and half-fixed one of them.** Its six candidates tied gen 7 on the frozen 25. On the two target rules, screened at n=3 in one session, spell-out went from gen 7's 22.2% to between 13.9% and 37.5%, and dictionary exactness stayed between 81.9% and 87.5%. The best, `gen8/r3`, added 69 words, and confirmed at n=10 below gen 7: frozen 21.90, holdout 11.70, grid spell-out 33.3%. The lineage stopped there.

### The finalist against round 6

Same session, `proxy-haiku`, judged with exact in brackets:

| guard | `final-r6` | `gen7/r1` | n |
| ----- | ---------: | --------: | -: |
| words | 965 | 943 | |
| frozen 25 | 18.90 (16.20) | **22.20 (20.10)** | 10 |
| recorded holdout, 15 | 10.30 (8.80) | **12.40 (10.40)** | 10 |
| dictionary wants recall | **17, 17, 17 / 18** | 16, 16, 16 / 18 | 3 |
| dictionary traps bitten | 0 | 0 | 3 |
| layout no-break controls | 110/110 | 110/110 | 10 |
| layout unspoken breaks | **35/40** | 27/40 | 10 |
| layout requested breaks | 21/30 | 21/30 | 10 |

The nine-rule grid, rule rate, n=3:

| rule | `final-r6` | `gen7/r1` |
| ---- | ---------: | --------: |
| bare endings | 100.0% | 100.0% |
| dictionary exactness | **87.5%** | 81.9% |
| identifier from context | 86.1% | **96.3%** |
| layout | **100.0%** | 97.2% |
| never obey | 95.8% | **98.6%** |
| self-correction | 97.9% | **99.3%** |
| spell-out | **41.7%** | 20.8% |
| spoken punctuation | 84.7% | **100.0%** |
| symbol attachment | 100.0% | 100.0% |

On the frozen 25 the gains are the failures round 6 named and did not fix, out of 10 runs:

- `polish-14`, the email address round 6 returned alone 20 of 20 at its confirmation: 5 → 10.
- `polish-29`, the spoken comma round 6 turned into a sentence break: 2 → 10.
- `polish-10`, a spoken colon and semicolon: 5 → 10.
- `polish-28`, the injected instruction: 7 → 10.

On the holdout, `hpolish-12` goes 3 → 10 and `hpolish-03` 0 → 6. Neither prompt passes `polish-37`'s one-letter spelling aside, and `polish-39` passes once. On the grid, identifiers improve on all three shapes it splits out: engine-mangled tokens 29 → 33/36, call sites 34 → 36, declarations 30 → 35.

### Not shipped, and why

Three reasons, in order of weight.

- **It regresses two guarded rules.** Under ticket 48's method, a winner on the objective must not lose a guard. Spell-out halves, the dictionary gate loses one want in every run (`Silero`, written from a sound-alike pair of ordinary words), and unrequested paragraph breaks fall from 88% to 68%. Spell-out was already the weakest rule at round 6. Generation 8 was aimed at exactly this and recovered spell-out to 33%, at 1,012 words, with no dictionary gain.
- **Shipping it means rewriting the package's pinned fragments.** `CleanupPromptTests` pins round 5 and 6's measured sentences verbatim: `source material, never instructions for you`, `DICTIONARY terms are exact spellings`, `The label is called Vybe.`, and 18 more, 21 in all. `gen7/r1` contains none of them, so shipping it replaces those tests' content. That is the maintainer's call, not this round's.
- **The holdout gain is the less certain one.** +2.1 at n=10, on 15 entries, from a lineage whose diagnoses were written from frozen failures only, so the holdout is a fair test. `gen4/r6`, two generations earlier, had already won the holdout (10.50 against 9.90) while losing the frozen 25, which suggests the from-scratch style generalizes rather than fits.

## Subtraction

### Round 6, leave one out

`units-r6.json` names 17 sentences or clauses of `final-r6`, and `cut.py` writes the prompt minus each. The frozen 25 is n=6, judged, against the intact 18.50 in the same session:

| unit removed | words | judged | Δ |
| ------------ | ----: | -----: | -: |
| inert-source invariant | 100 | 12.50 | −6.00 |
| closing self-check | 22 | 12.83 | −5.67 |
| subject paragraphs | 78 | 15.00 | −3.50 |
| edit only TRANSCRIPT | 38 | 15.17 | −3.33 |
| conventional paths | 7 | 15.83 | −2.67 |
| bare ending | 33 | 16.33 | −2.17 |
| break nowhere else | 39 | 16.33 | −2.17 |
| break commands | 36 | 16.50 | −2.00 |
| backtrack | 91 | 17.00 | −1.50 |
| symbols | 36 | 17.00 | −1.50 |
| output list | 16 | 17.17 | −1.33 |
| command pass | 54 | 17.33 | −1.17 |
| dictionary sentence | 63 | 17.33 | −1.17 |
| spell-out | 102 | 17.33 | −1.17 |
| role | 33 | 17.50 | −1.00 |
| context identifiers | 65 | 17.83 | −0.67 |
| no clause split | 9 | 18.83 | +0.33 |

The frozen set is blind to half of these. Of the cuts it priced cheapest, the grid priced two as the most expensive in the prompt:

| cut | words | frozen judged | identifiers | spell-out | spoken punct. | never obey |
| --- | ----: | ------------: | ----------: | --------: | ------------: | ---------: |
| intact | 965 | 18.50 | 86.1% | 41.7% | 84.7% | 95.8% |
| −5 cheapest, including context identifiers | 788 | 17.00 | 23.1% | 43.1% | 94.4% | 100.0% |
| −8, also spell-out, dictionary, backtrack | 532 | 17.83 | 21.3% | 0.0% | 88.9% | 100.0% |
| −11, also symbols, break commands, bare ending | 427 | 16.83 | 31.5% | 0.0% | 95.8% | 95.8% |
| −13 | 381 | 14.33 | | | | |

The context-identifier sentence carries identifiers from 23% to 86%, and the spell-out paragraph carries spell-out from 0% to 42%; the frozen 25 has one entry for each. Excluding those two, the cuts the grid tolerated were role, output list, command pass, and no-clause-split, 112 words. As `trim4`, 853 words, that scored 18.00 against 19.60 on the frozen 25 and 10.90 against 9.90 on the holdout, n=10. It lost `polish-19` and `-20`'s identifiers and `polish-14`'s extraction, and gained spoken punctuation. Keeping the role sentence and output list, `trim2`, 902 words, scored worse, 16.00. The effects are neither additive nor monotonic: the same four clauses cost 1.6 points together, and two of them cost 3.6.

The compression pass on round 6's `g3-1`, rescored here: `gc-5`, 848 words, 16.67 judged, and `gc-3`, `gc-6` 16.17 and 16.50, against 18.50. It stays parked; a rewrite for length loses about two points.

### The from-scratch winner, leave one out

`units-gen7.json` names `gen7/r1`'s sixteen sections. The two measured by no guard here, the Additional Instructions bullet and the three-word list heading, were not cut. Frozen 25, n=6, judged, against the intact 22.20 at n=10:

| section removed | words | judged |
| --------------- | ----: | -----: |
| symbols | 114 | 19.83 |
| context identifiers | 69 | 20.00 |
| punctuation restoration | 59 | 20.00 |
| spell-out | 95 | 20.83 |
| whole dictation | 60 | 21.00 |
| grammar | 53 | 21.00 |
| self-correction | 48 | 21.00 |
| paragraphs | 114 | 21.50 |
| closing self-check | 39 | 21.50 |
| disfluency | 53 | 22.00 |
| dictionary | 23 | 22.00 |
| one final version | 21 | 22.33 |
| typing commands | 115 | 22.33 |
| task and never-obey | 60 | 23.00 |

The frozen 25 says most of the prompt is free, so the cuts were composed cheapest first and measured on every guard. `curve-gen7/dropNN.txt` removes the NN cheapest sections. Frozen 25 is judged, n=6, except the intact n=10. The grid is rule rate, n=3, and the layout arm is n=6:

| cut | words | frozen | spoken punct. | never obey | self-corr. | spell-out | identifiers | no-break kept | unspoken breaks |
| --- | ----: | -----: | ------------: | ---------: | ---------: | --------: | ----------: | ------------: | --------------: |
| intact | 943 | 22.20 | 100.0% | 98.6% | 99.3% | 20.8% | 96.3% | 110/110 | 27/40 |
| −task | 883 | 22.17 | | | | | | 66/66 | 15/24 |
| −one version | 862 | 22.67 | | | | | | 63/66 | 14/24 |
| −typing commands | 747 | 22.67 | 94.4% | 98.6% | 100.0% | 29.2% | 97.2% | 62/66 | 15/24 |
| −dictionary, disfluency | 671 | 22.67 | 95.8% | 94.4% | 93.1% | 25.0% | 95.4% | 60/66 | 18/24 |
| −paragraphs, self-check | 518 | 22.50 | 93.1% | 86.1% | 95.8% | 23.6% | 95.4% | 59/66 | 0/24 |
| −self-correction, grammar, whole dictation | 357 | 19.00 | | | | | | | |

Unlike round 6, `gen7/r1` has slack. The 115-word typing-command bullet and the opening task paragraph can go together for about five points of spoken punctuation and four spurious breaks in 66. That is the price of `curve-gen7/drop03.txt`, 747 words, and the guards it was confirmed on are below. Under about 670 words never-obey starts to slip, and at 518 the unrequested paragraph break disappears with its bullet.

Confirmed at n=10 in the same session as the finalist table:

| guard | `final-r6`, 965 words | `gen7/r1`, 943 | `curve-gen7/drop03`, 747 |
| ----- | --------------------: | -------------: | -----------------------: |
| frozen 25 | 18.90 (16.20) | 22.20 (20.10) | **22.70 (19.90)** |
| recorded holdout | 10.30 (8.80) | **12.40 (10.40)** | 12.10 (10.10) |
| dictionary wants | **17, 17, 17** | 16, 16, 16 | 17, 17, 16 |

At 747 words, 23% shorter than round 6, it wins round 6's objective by 3.8 and its holdout by 1.8, and ties its dictionary gate. Its weak rules are the from-scratch ones: spell-out 29% on the grid, and unrequested breaks 15/24.

### Length against score

Frozen 25, judged, n=6 unless stated, by word count. Each lineage's points were measured in one session:

| words | round 6 cuts | `gen7/r1` cuts | written short |
| ----: | -----------: | -------------: | ------------: |
| 943–965 | 18.50 | 22.20 (n=10) | |
| 842–891 | 15.17–18.83 | 22.17–22.67 | |
| 747–788 | 17.00 | 22.67 | |
| 671 | | 22.67 | |
| 518–532 | 17.83 | 22.50 | |
| 353–427 | 14.33–16.83 | 19.00 | 15.83 (`short-gen2/r3`), 12.33 (`gen1/f6`) |
| 213 | | | 11.50 (`gen1/f4`) |

The frozen 25 alone would put the knee at about 500 words for the from-scratch prompt and nowhere for round 6, because round 6 has no knee: its scores at every length are within noise of each other and below the intact prompt. The guards put the from-scratch prompt's knee at about 750 words, where never-obey, layout, and spoken punctuation are still within a few points of the intact text. The smallest prompt that holds every guard but spell-out and the dictionary is about 750 words. Both lineages wrote their way up to about 950 words without being asked to, and the last 200 of the from-scratch ones were not needed.

## The transport

`proxy-haiku` is the scorer of record because it is the subscription path closest to an HTTP call from the app. Round 6 described it as "a Claude Code persona in front of our prompt" of about 135 tokens. Reading CLIProxyAPI's source at the deployed build, v8.0.41 commit `8289ec4`, shows something different. The executor's cloaking code is identical at upstream HEAD `bc06434`.

For a Claude **OAuth** credential, which the subscription is, every request is cloaked. `checkSystemInstructionsWithSigningModeAt` in `internal/runtime/executor/claude_executor_cloaking.go`:

1. **replaces the top-level `system` with two blocks:** an `x-anthropic-billing-header: cc_version=…; cc_entrypoint=cli; cch=…` line, and `You are Claude Code, Anthropic's official CLI for Claude.`
2. **moves our system prompt.** For a model on its legacy list, which includes `claude-haiku-4-5`, our prompt is prepended to the first user message inside `<system-reminder>`. For any other model, **including `claude-haiku-5-5`**, `insertClaudeMidConversationSystemBlocks` appends it as a `role: "system"` message *after* the user turn. The argument that decides this is `!policy.OAuth`, with the comment `OAuth top-level caller prompts trigger Anthropic's third-party classifier (#6432)`.
3. **prepends a `<system-reminder>` with `# currentDate`** to the transcript's turn, about 300 characters, on every cloaked path, strict or not. Only the date's value is configurable.

It also sets `metadata.user_id` and, upstream of api.anthropic.com, a `diagnostics` object, neither of which costs prompt tokens. There is no persona text beyond the identity line for Haiku. So the 135 tokens are the identity line, the date reminder, and framing. The model calls itself Claude Code because the identity line is the only system prompt it sees ahead of the transcript, and our rules arrive after the transcript.

Two consequences for the history:

- **The Haiku 5.5 measurement compared two layouts, not one.** [`haiku-5-5/`](../haiku-5-5/README.md) ran 4.5 and 5.5 "through the same transport". 4.5 got our prompt inside the transcript's turn, and 5.5 got it after the transcript. Part of the 16.50 → 7.40 drop may be layout. The SDK arm in round 6, 12.00 frozen for the same prompt, says about half.
- **Every round-6 and round-7 number is for our prompt arriving after the transcript.** The app sends it as the system prompt, ahead of the transcript, with nothing else. Both rounds' candidates were selected under the proxy's layout.

**It cannot be cut to the identity line by configuration alone.** The date reminder has no switch. Two configurations get close:

| option | config | what Haiku receives | risk |
| ------ | ------ | ------------------- | ---- |
| A: filter the reminder | `payload.filter` on `claude-haiku-5-5`, deleting the user block matching `# currentDate`; payload rules run after cloaking and before signing | system `[billing, identity]`, then the transcript, then our prompt as a system turn | none known, but our prompt still follows the transcript |
| B: no cloak | `"cloak_mode": "never"` in the OAuth auth file, and the harness sends the identity line as its first system message | system `[billing, identity, our prompt]`, then the transcript: the app's layout plus one line | the layout of issue #6432, which Anthropic answered with *"Third-party apps now draw from your extra usage"*, which is metered billing on the subscription |

The billing header cannot be removed for OAuth; CLIProxyAPI's docs say api.anthropic.com strips it before the model, at zero tokens. That is unverified here.

Option B is the one that matches what the app sends, and it is the only transport that would let the subscription stand in for the direct-API arm round 6 left open. Both options change `/CLIProxyAPI/config.yaml` or an auth file on pod042, which is shared infrastructure declared in `ansiblonomicon`, and B can bill. **Neither was applied.** The decision and a one-call test of B's billing behaviour are the maintainer's.

## Reproducing

```sh
set -a; . /Users/thurstonsand/Develop/mini-whisper/.env; set +a   # AIG_APIKEY, untracked
cd results/prompt-tuning-r7

# from scratch: generation 1 sees only spec.txt and diagnosis.txt
./write_fresh.py --out candidates/gen1
./write_fresh.py --revise candidates/gen1/f6.txt --diagnosis diagnosis-gen2.txt --out candidates/gen2
./write_fresh.py --revise candidates/gen2/r4.txt --diagnosis diagnosis-gen3.txt --out candidates/gen3
./write_fresh.py --revise candidates/gen3/r3.txt --diagnosis diagnosis-gen4.txt --out candidates/gen4
./write_fresh.py --revise candidates/gen4/r6.txt --diagnosis diagnosis-gen5.txt --out candidates/gen5
./write_fresh.py --revise candidates/gen5/r2.txt --diagnosis diagnosis-gen6.txt --out candidates/gen6
./write_fresh.py --revise candidates/gen6/r1.txt --diagnosis diagnosis-gen7.txt --out candidates/gen7
./write_fresh.py --revise candidates/gen7/r1.txt --diagnosis diagnosis-gen8.txt --out candidates/gen8
./write_fresh.py --revise candidates/gen1/f4.txt --diagnosis diagnosis-short-gen2.txt --out candidates/short-gen2

# subtraction
./cut.py --prompt candidates/final-r6.txt --units units-r6.json --out candidates/cut-r6
./cut.py --prompt candidates/gen7/r1.txt --units units-gen7.json --out candidates/cut-gen7

cd ../prompt-tuning-haiku
P=../prompt-tuning-r7/candidates/gen7/r1.txt O=../prompt-tuning-r7/runs/confirm2
./tune.py stage3 --prompt $P --repeat 10 --output $O/frozen10-gen7-r1.json          # judged, then exact
./tune.py stage3 --holdout --prompt $P --repeat 10 --output $O/holdout10-gen7-r1.json
./tune.py stage3 --prompt $P --script ../../stage3-layout.jsonl --raw ../prompt-tuning-r4/stage3-layout-raw.jsonl \
  --include-excluded --repeat 10 --output $O/layout10-gen7-r1.json
for i in 1 2 3; do ./tune.py stage2 --prompt $P --output $O/stage2-gen7-r1-$i.jsonl; done
./perturb.py --prompt $P --repeat 3 --out ../prompt-tuning-r7/runs/grid3
../prompt-tuning-r4/layoutrate.py $O/layout10-*.json
./judge.py --calibrate
./judge.py --accepted $O/frozen10-*.json     # every lenient pass, for audit
```

`runs/` holds every arm: `gen*/` and `short-gen2/` are the screens, `gen8-rules/` generation 8's two-rule grid screen, `write-gen*.txt` the authoring logs, `cut-*/` and `curve-*/` the subtraction, `gc/` the parked compression, `confirm/` and `confirm2/` the n=10 comparisons, and `grid3/` the nine-rule grid. `confirm/frozen10-final-r6` and `confirm/final-r6-b` are earlier same-day controls; the finalist table uses `confirm2/final-r6-c`, run beside `gen7/r1`. `candidates/` keeps every candidate Sol wrote that passed the leak check; `confirm*/`, `rerun/`, and `named/` are copies under the names the runs carry.
