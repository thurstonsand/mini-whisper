# Prompt tuning round 6 — retuning for claude-haiku-5-5

[Ticket 48](../../../../tickets/48-prompt-eval-automation.md)'s sixth round. The factory profile's model moved to `claude-haiku-5-5`, and [the measurement that preceded this round](../haiku-5-5/README.md) found round 5's prompt scoring less than half as well on it. Round 5 cut words from a prompt that worked; this one had to add words to a prompt that had stopped working, on a model that reads instructions differently.

The answer **ships** as `candidates/final-r6.txt`, 965 words. On the scorer of record, `proxy-haiku`, it takes the frozen 25 from **7.65 to 14.00**, n=20, and the recorded holdout from **6.90 to 8.30**, n=10. The dictionary gate returns to 17/18 in all three runs with no trap bitten, and every rule in the nine-rule grid improves, layout from 54% to 98% and spoken punctuation from 40% to 82%. It was written by Sol from a written diagnosis, never from corpus entries, with Haiku only scoring.

**One thing is not settled, and it decides whether this should reach a release.** The second subscription transport, the Agent SDK, sends our prompt as the only system prompt. There the same text wins the frozen 25 (12.00 → 14.00) and loses the holdout (8.50 → 6.10), and it loses identifiers and backtracks on the grid. The two transports disagree because CLIProxyAPI places a Claude Code persona in front of our prompt, and that persona interacts with the wording rather than being a constant every arm pays. The app sends neither. The way to settle it is a small direct-API arm, which this round's no-metered-providers constraint ruled out; see [The transport question](#the-transport-question).

## Method

The round followed round 5's guards on the scorer of record: frozen 25, recorded holdout run only on finalists, stage-2 dictionary gate over three runs, the full nine-rule perturbation grid at n=10, the 22-entry layout arm at n=20, and `leakcheck.py` on every candidate before it was scored. Screening was n=6 on the frozen 25 and n=3 on the grid.

Three authoring arms ran, in this order.

1. **Hand patches.** `build_candidates.py` holds eleven single-behaviour patches against the round-5 incumbent, one per failure the [Haiku 5.5 measurement](../haiku-5-5/README.md) named, plus three compositions. Each patch is an exact sentence replacement, applied alone first.
2. **`propose.py`, guarded,** with `--proposer-provider codex-sol`, the round-5 setup: three rounds of six, alternating halves of the frozen objective, `--reject-leaks`.
3. **Sol as author, from a diagnosis.** `sol_author.py` is new. It shows Sol the current prompt and a plain-language account of what 5.5 does wrong, `diagnosis/gen*.txt`, written by hand from the grid's failure rows and phrased with no corpus words. Sol returns six full revisions; `propose.leaked` rejects any that quote three corpus words or five exemplar words, and Haiku scores the rest. The winner of each generation became the next generation's base.

All Haiku calls went through the Claude subscription: CLIProxyAPI for `proxy-haiku`, and Claude Code for `sdk-haiku`. Sol ran through the ChatGPT subscription. No metered provider was opened.

## Instrument changes

- **`propose.py` reads the Codex CLI's session.** pi's `auth.json` no longer carries a ChatGPT session, so `codex_transport` now reads `~/.codex/auth.json` and takes expiry from the access token's own JWT claims. A one-call smoke test returned the requested word.
- **`sdk-haiku` can reach 5.5.** Claude Code's alias list stops at `claude-haiku-4-5`, so `AgentSdkPipe` refused `claude-haiku-5-5`. A full `claude-` model ID that the list does not name is now tried rather than refused. Every answer is checked against the model that produced it, so an alias that silently resolved elsewhere would fail the run.

## The baseline, on two transports

The round-5 prompt on 5.5, against 4.5, every arm on the same day.

| arm | frozen 25 | holdout | n |
| --- | --------: | ------: | -: |
| `claude-haiku-4-5`, proxy | 16.50 | 9.10 | 10 |
| `claude-haiku-5-5`, proxy | 7.65 | 6.90 | 20 / 10 |
| `claude-haiku-5-5`, SDK | 12.00 | 8.50 | 10 |

The proxy prepends about 135 tokens of Claude Code system prompt; 5.5 believes it, and sometimes answers a transcript with "I'm Claude Code, Anthropic's CLI". The SDK replaces Claude Code's system prompt with ours and adds a ~119-token meta user turn. Half of the measured 5.5 regression, frozen 16.50 → 7.65, is the persona: without it the same prompt scores 12.00. The other half is 5.5's own: the stage-2 gate's dictionary recall falls from 17/18 to 12–13/18 and the grid's spell-out from 63% to 16–32% on both transports.

## Hand patches moved single entries and nothing else

| patch | aimed at | frozen, proxy | frozen, SDK | grid mean rule rate |
| ----- | -------- | ------------: | ----------: | ------------------: |
| incumbent | | 7.40 | 12.00 | 68.9% |
| `output-whole` | extraction | **10.17** | **13.50** | 69.8% |
| `guard-assistant` | injected instructions | 9.67 | 11.33 | 71.3% |
| `edits-structure` | over-editing | 9.33 | 12.67 | 72.7% |
| `commands-mark` | spoken punctuation | 8.50 | 13.00 | 71.3% |
| `hand-a`, those four composed | | 9.50 | | 69.3% |

Frozen columns are n=6 except the incumbent's n=10; grid is n=3, n=10 for the incumbent. The seven other single patches screened on the frozen 25 scored 7.17 to 8.67. The rule-targeted ones were measured on their own grid arm, n=6, and moved nothing: `backtrack-must` 88.5% → 91.0%, `layout-sentence` 56.2% → 50.0%, `spell-required` 13.9% → 11.1%. Composing the four winners scored no better than `output-whole` alone. One sentence fixed the sentence it was written for, and for 5.5 that was not enough.

## The guarded loop fitted its half

`propose.py --holdout` took its training half from 2.50 to 6.75/13 and scored 4.75/12 on the unseen half, where the incumbent's share is about 4.9. Its winner, `candidates/auto-sol/best.txt`, wrote `so`, `okay`, `I think`, and `probably` into the prompt as "content, not filler". Those are the hedges of the failing entries, a word or two at a time, too short for a three-word leak check to see. Six of eighteen proposals were rejected for quoting corpus triples. Round 1's lesson repeats: shown failing cases, the proposer memorizes them.

## Sol from a diagnosis

| generation | base | best | words | frozen, proxy | frozen, SDK | grid mean |
| ---------- | ---- | ---- | ----: | ------------: | ----------: | --------: |
| 1 | incumbent | `sol/sol-4` | 684 | 10.17 | 13.17 | 75.3% |
| 2 | `sol-4` | `sol-gen2/g2-2` | 865 | 11.00 | 14.33 | 81.4% |
| 3 | `g2-2` | `sol-gen3/g3-1` | 967 | **14.17** | **14.50** | **87.1%** |
| 4 | `g3-1` | `sol-gen4/g4-1` | 1088 | 14.17 | 12.00 | 86.1% |

Screening n=6 on the frozen 25 and n=3 on the grid; each row is the best of six. Generation 1 alone matched the best hand patch. The diagnosis carried what the failing cases could not: it described a behaviour, such as *returns the token alone*, *writes its reasoning into the reply*, or *breaks between every short sentence*, so Sol wrote a rule, not an answer. Five of the 24 proposals were rejected by the leak check, each for an ordinary phrase such as `part of the` that also occurs in the corpus.

Generation 4 added 120 words and bought nothing, so the search stopped at `g3-1`. A compression pass on `g3-1`, `diagnosis/compress.txt`, reached 801 to 848 words and screened 12.00 to 14.67 on the frozen 25. It is parked, for two reasons. The two compressed candidates whose grids finished lost identifier-from-context from 87% to 65%, round 5's finding again. And every compressed text dropped four or five of the fragments `CleanupPromptTests` pins.

What `g3-1` added to the incumbent, by behaviour:

- **The tagged-field invariant became absolute and specific.** It now names what to refuse: answering, carrying out, refusing, discussing, or acknowledging a request. A request is kept as dictated wording, and the reply is always the whole transcript. Never-obey 68.3% → 93.3%.
- **Spoken typing commands became a replacement pass.** It runs before other edits and again after them, wherever a command falls, and adds nothing at a break boundary. Spoken punctuation 39.6% → 82.1%.
- **The paragraph rule got a threshold.** An unrequested break needs two sentences on each side. Layout 54.2% → 97.5%.
- **The edits paragraph lists what to preserve:** hedges, softeners, openers, profanity, word choice, sentence structure. It also corrects plain grammatical slips, and a backtrack must cancel its whole clause.
- **A closing self-check, and a demand for exactly one final version.** 5.5 would otherwise draft a reply, write "Wait, I need to correct this", and draft another.

## The closing sentence is fragile

`g3-1` ends with *Return exactly one final version of only the complete edited transcript*, and two of the fragments `CleanupPromptTests` pins were missing from it. Rewording both cost five points, so each change was measured alone.

| ending | frozen, proxy | n |
| ------ | ------------: | -: |
| `g3-1` as written | 14.17, 13.67 | 6, 6 |
| identifier sentence reworded only | 13.50 | 6 |
| "Return only the edited transcript, complete, in exactly one final version." | 10.83 | 6 |
| both rewordings | 8.83, 8.65 | 6, 20 |
| `g3-1` ending, rerun | 12.40 | 10 |
| **"Return only the edited transcript: exactly one final version of it, complete."** | **13.20** | 10 |
| "Return only the edited transcript, in exactly one complete final version." | 10.90 | 10 |
| "Return only the edited transcript, complete and exactly once." | 11.40 | 10 |

The colon form ships. Four wordings of one sentence span 2.3 points on 25 entries. The superseded runs are in `runs/final-reworded/` and the probes in `candidates/probes/`.

## Number forms came out

`g3-1` told the model to preserve "number forms, ordinals", because generation 1's diagnosis said 5.5 rewrites them. Removing the clause tied the frozen 25 on both transports: 12.90 against 12.25 on the proxy and 14.10 against 14.30 on the SDK, n=10 and n=20. By round 5's contraction rule the three words go. The question was raised by the SDK holdout's two number entries, so the decision was made on the frozen 25 alone; `runs/final-numbers/` holds every guard measured on the 968-word text before the cut.

## Confirmation and shipping

`final-r6` against the round-5 incumbent on `claude-haiku-5-5`, `proxy-haiku`:

| guard | incumbent | `final-r6` | n |
| ----- | --------: | ---------: | -: |
| frozen 25 | 7.65 | **14.00** | 20 |
| recorded holdout, 15 entries | 6.90 | **8.30** | 10 |
| dictionary wants recall | 12, 12, 13 / 18 | **17, 17, 17 / 18** | 3 |
| dictionary traps bitten | 0, 0, 0 | 0, 0, 0 | 3 |
| layout no-break controls | 208/220 | **217/220** | 20 |
| layout unspoken breaks | **80/80** | 72/80 | 20 |
| layout requested breaks | 20/60 | **40/60** | 20 |

The one loss is unspoken breaks, and it is the paragraph threshold doing its job too well. `layout-19` has two sentences per subject, and the two-sentences-a-side rule merges it in 7 of 20 runs. The nine-rule grid, n=10:

| rule | incumbent | `final-r6` |
| ---- | --------: | ---------: |
| bare endings | 96.2% | **100.0%** |
| dictionary exactness | 82.9% | **86.2%** |
| identifier from context | 77.2% | **87.5%** |
| layout | 54.2% | **97.5%** |
| never obey | 68.3% | **93.3%** |
| self-correction | 87.7% | **96.2%** |
| spell-out | 15.8% | **42.1%** |
| spoken punctuation | 39.6% | **82.1%** |
| symbol attachment | 97.9% | **99.6%** |

Whole-clause backtracks go 49/80 → 79/80 and identifier declarations 72/120 → 104/120. The frozen entries the Haiku 5.5 measurement named recover: `polish-07` 0 → 19/20, `polish-15` 0 → 16, `polish-16` 0 → 18, `polish-23` 0 → 13, `polish-28` 1 → 18, `polish-32` 0 → 17, `polish-33` 0 → 19. Two do not. `polish-14` still returns the bare address 20 of 20, and `polish-29` still turns the spoken comma into a sentence break. `polish-22` regresses from 11 to 1 of 20, on the ordinal `5th`, and `polish-02` from 14 to 4, on a dropped question mark.

On `claude-haiku-4-5` through the same proxy, the new prompt scores 17.50 against 16.50 on the frozen 25 and 8.30 against 9.10 on the holdout, n=10. Rolling the model back does not require rolling the prompt back.

`leakcheck.py` passes and all 54 `TranscriptCleanup` tests pass with every pinned fragment intact. Under ticket 48's rule on the scorer of record, the prompt ships, and it now lives in `CleanupPrompt.builtIn`.

## The transport question

The same text through the Agent SDK, `claude-haiku-5-5`:

| guard | incumbent | `final-r6` | n |
| ----- | --------: | ---------: | -: |
| frozen 25 | 12.00 | **14.00** | 10 |
| recorded holdout | **8.50** | 6.10 | 10 |
| identifier from context | **43.1%** | 34.4% | 10 |
| self-correction | **77.9%** | 73.1% | 10 |
| layout | 48.3% | **95.8%** | 10 |
| never obey | 84.2% | **89.2%** | 10 |
| spoken punctuation | **80.0%** | 75.4% | 10 |

The losses share one mechanism. Across the 2,200 grid runs where an edit was due, count the replies that return the transcript's words unedited:

| transport | incumbent | `final-r6` |
| --------- | --------: | ---------: |
| proxy, behind a Claude Code persona | 13.5% | **8.0%** |
| SDK, our prompt alone | **8.9%** | 13.9% |

Behind the persona, the round's absolute, inert-source wording pulls 5.5 back to editing. Without it, the same wording makes 5.5 more inclined to leave the text alone. That is where the SDK loses its backtracks and identifiers, and on the holdout it is `hpolish-08` and `-12` at 2 of 10 each. The SDK holdout is also noisy at n=10: the 968-word text passed those two entries 8 and 10 of 10. The direction is consistent across the grid, though.

Neither transport is the app's request. The app sends our prompt as the system message straight to the model's endpoint, with no persona and no meta turn, and that is closer to the SDK's shape. So the proxy's numbers may overstate what ships, and the SDK's may understate it. A direct-API arm, the frozen 25 and the holdout at n=10 for both prompts, is about 800 calls of Haiku 5.5. That is the measurement that decides it. It is metered and was out of scope here.

## On another engine's raw

A profile pairs one engine with one prompt, so a prompt has to be judged on the raw it will receive. The [engine bakeoff](https://ampcode.com/threads/T-01a1600b-2fcf-71d0-bc3a-4744a5a663d5) now writes each engine's replay of the same four tuning inputs. Its first run put Cohere Transcribe at MLX 4-bit, Superwhisper's configuration, beside a same-session Parakeet v2 rerun, on branch `engine-bakeoff-harness` at `5b34175`. The fresh v2 raws are byte-identical to the ones every round has scored, so they serve as the control. The Cohere raws are copied into `engines/cohere-transcribe-4bit/`. Every arm below ran in one session on `proxy-haiku`, n=10, with all 27 frozen entries scored.

| guard | v2, round 5 | v2, round 6 | Cohere, round 5 | Cohere, round 6 |
| ----- | ----------: | ----------: | --------------: | --------------: |
| frozen 25 | 9.70 | **15.50** | 7.70 | **13.80** |
| `polish-11` and `polish-38` | 0/20 | 0/20 | 0/20 | 0/20 |
| recorded holdout, 15 | 7.30 | **9.00** | 8.60 | **12.80** |
| dictionary wants, three runs | | | 14, 14, 15 / 18 | 16, 16, 14 / 18 |
| dictionary traps bitten | | | 0 | 0 |
| layout no-break controls | | | 101/110 | **109/110** |
| layout unspoken breaks | | | **40/40** | 35/40 |
| layout requested breaks | | | 16/30 | **20/30** |

**Round 6's gains are not Parakeet's.** On the frozen 25 the same-session gain is +5.80 on v2 and +6.10 on Cohere. On the holdout it is larger on Cohere, 8.60 → 12.80 against 7.30 → 9.00. The trade on the layout arm is the same as on v2: fewer spurious breaks, and `layout-19` merged by the two-sentences-a-side threshold.

**The proxy moved between days.** The same v2 arms scored 7.65 and 14.00 in the confirmation above and 9.70 and 15.50 here; `polish-28` on round 5 went from 1/20 to 10/10. The delta held, and only same-session arms are compared.

**Neither excluded entry comes back yet, for two different reasons.**

- `polish-11` fails on its expectation, not the prompt. Cohere hears the quotation and both prompts return `She said, "It ships tonight."` in 10 of 10 runs; the expectation is `She said "it ships tonight."`. That is an adjudication question: the speaker dictated neither the comma nor the case.
- `polish-38` fails on the prompt. Cohere hands it `My last name is Sandberg, S-A-N-D-B-E-R-G, period.` and both prompts return `Sandberg, S-A-N-D-B-E-R-G.` They extract the name and keep the hyphenated spelling, so it is the extraction behaviour and the spell-out gap together. It belongs in the next round's objective for engines that hear it.

Cohere's raw changes what three more entries test. `polish-28`'s raw reads *write up home about ducks*, which is the engine's error and unreachable. `polish-29` and `polish-32` keep a trailing `, period` 10 and 8 times in 10 under round 6. That is a real prompt failure, and Cohere produces the shape far more often than v2: the spoken comma is already a comma and the spoken period follows it. `polish-01` fails on the comma Cohere puts after "So".

## What this round did not do

- **No direct-API arm**, as above.
- **Compression is parked.** 965 words is 84% longer than round 5's text. The compressed candidates show where the next contraction round starts and what it has to protect.
- **Spell-out is still the weakest rule,** at 42% on the proxy. Every miss has a spoken period right after the named letter. The patch that showed an example with a spoken full stop, `g2-spell-period`, did not move it: 43.1% against 45.8% at n=3.

## Reproducing

```sh
set -a; . /Users/thurstonsand/Develop/mini-whisper/.env; set +a   # AIG_APIKEY, untracked
cd ../prompt-tuning-r6
./build_candidates.py
../prompt-tuning-haiku/leakcheck.py candidates/final-r6.txt

# Sol from a diagnosis; each generation's base is the previous winner
./sol_author.py --diagnosis diagnosis/gen1.txt --out candidates/sol
./sol_author.py --prompt candidates/sol/sol-4.txt --diagnosis diagnosis/gen2.txt --out candidates/sol-gen2
./sol_author.py --prompt candidates/sol-gen2/g2-2.txt --diagnosis diagnosis/gen3.txt --out candidates/sol-gen3

cd ../prompt-tuning-haiku
F=../prompt-tuning-r6/candidates/final-r6.txt O=../prompt-tuning-r6/runs/final
./tune.py stage3 --prompt $F --repeat 20 --output $O/frozen20-final-r6.json
./tune.py stage3 --holdout --prompt $F --repeat 10 --output $O/holdout10-final-r6.json
./tune.py stage3 --prompt $F --script ../../stage3-layout.jsonl --raw ../prompt-tuning-r4/stage3-layout-raw.jsonl \
  --include-excluded --repeat 20 --output $O/layout20-final-r6.json
for i in 1 2 3; do ./tune.py stage2 --prompt $F --output $O/stage2-final-r6-$i.jsonl; done
./perturb.py --prompt $F --repeat 10 --out $O/grid10

# on another engine's raw: any replay of the same scripts, such as bakeoff.py writes
CO=../prompt-tuning-r6/engines/cohere-transcribe-4bit
./tune.py stage3 --prompt $F --raw $CO/stage3-raw.jsonl --include-excluded --repeat 10
./tune.py stage3 --holdout --prompt $F --raw $CO/stage3-holdout-raw.jsonl --repeat 10
./tune.py stage2 --prompt $F --raw $CO/stage2-bare.jsonl --output $O/stage2-cohere.jsonl

# the second transport
./tune.py stage3 --provider sdk-haiku --model claude-haiku-5-5 --prompt $F --repeat 10
./perturb.py --provider sdk-haiku --model claude-haiku-5-5 --prompt $F --repeat 10 --out $O/sdk-grid10
```

`sol_author.py` renames nothing. Each generation's files were renamed to `g2-*`, `g3-*`, and so on by hand, and leaking proposals were deleted after being reported. The incumbent baselines are under `runs/`, `runs/transport/`, and `runs/final/`, and the screens are under `runs/screen/` and `runs/grid3/`.
