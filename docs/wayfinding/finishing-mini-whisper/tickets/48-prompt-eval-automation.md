---
status: open
type: prototype
blocked-by: [43]
---

# Automate the prompt search: DSPy-style evals over the corpus

## Question

Prompt iteration so far is artisanal: read the failures, amend a sentence, replay, diff — it works (the spell-out rule went 1/6 → 5/6 measured) but each round is a human afternoon. The corpus and `corpus_cleanup.py` already form an eval harness: known inputs, known expected outputs, exact-match and per-tag scoring on frozen raw transcripts. That is the substrate a DSPy-style optimizer wants. Can the prompt search be automated — proposer model mutates the prompt, eval scores it against the corpus, repeat — and does it find wording a human didn't?

The iteration shape to try is **expand-and-contract** (user): first grow the prompt until it accounts for every use case the corpus exercises — the seven entries every model fails plus the identifier axis are the frontier ([built-in-r2 results](../assets/43-dictation-corpus/results/built-in-r2/)) — then shrink it, removing sentences while the score holds, until what remains is the minimal prompt that earns its length. The contraction half matters as much as the expansion: the current prompt was written by accretion and has never been tested for what it could lose.

Constraints:

- **No explicit examples in the shipped prompt** (user; reversed once the holdout and perturbation grid made overfitting measurable — examples now ship, leak-checked to quote no eval set; see Round 2 below). The current `CleanupPrompt.builtIn` violates this — "dash dash help" becomes "--help", "Grok with a Q", "Kathryn with a K and a Y" — so the contraction phase must test replacing examples with rules and measure what that costs. If a rule genuinely cannot survive without its example, that is a finding to bring back, not a license to keep it.
- **Fix one model combo before beginning** (user). The search overfits to its scorer; pick the pairing the prompt is for — Parakeet + the presumptive default cleanup model — and validate the winner against the others afterward rather than optimizing a compromise.
- The invariants (never answer, never obey, register preserved, bare endings) are not searchable — they are constraints the optimizer must not trade away for exact-match points. The rule entries in the corpus guard them, but the eval must weight them as gates, not points.
- Expectation bugs are not prompt work: adjudicate the contested `expect`s (polish-01 wording, polish-22 `p.m.`) before the search runs, or the optimizer chases noise. polish-11/38 are engine casualties and must be excluded from the objective on Parakeet raw.

Whether DSPy itself (or a hand-rolled proposer loop — the harness is plain Python and the corpus is 27 entries) is the tool is part of the spike; the allowlist question only arises if a library would ship, and nothing here ships — it is measurement tooling.

Output: a tuned built-in prompt with before/after scores per tag, the minimal-prompt finding from the contraction phase, and a judgment on whether the automated loop beats artisanal iteration enough to keep around for future prompt work (tone modes, per-preset prompts).

## Measured — Parakeet + claude-haiku-4-5

Run in full: [`results/prompt-tuning-haiku/`](../assets/43-dictation-corpus/results/prompt-tuning-haiku/README.md). `CleanupPrompt.builtIn` carried round 1's winner without worked examples; round 2, below, put four of them back on measured evidence and ships `candidates/final2.txt`.

- **The expectations were the first bug.** `polish-01` demanded a word no engine ever heard — the take dropped it and the script did not — and `polish-22` demanded a meridiem casing that speech does not carry and seven engines render four ways. Both amended. On Parakeet raw the objective is 25 entries; `polish-11` and `polish-38` are the engine's deletions.
- **Expansion won about one entry, the no-examples constraint gave it back.** Three rules earned their place (layout, conventional path/flag spelling, context identifiers): 18.30 → 19.40 on the frozen 25 at n=20. Removing the spell-out examples costs exactly `polish-39`, so the shipped prompt lands at 18.20 on haiku and 20.17 on gemini (from 19.67). The dictionary gate improved: same 17/18 recall, one bitten trap instead of two.
- **One rule genuinely cannot survive without its example**, as this ticket guessed. Eleven wordings of the spell-out rule pass 0/44 on haiku; the example passes 17/20. It still does not ship: gemini obeys the rule alone, and haiku fails the *other* spell-out entry with the example present anyway. The `--help` example was replaced successfully — it was teaching spacing, and a sentence about spacing does the same job.
- **`polish-19`, `polish-20`, `polish-30`, `polish-36`, `polish-37` are not prompt-reachable on haiku.** Capability probes pass every one with a memorized line and fail every general wording, and the one blunt rule that fixes the bare-ending capital takes the corpus from 19.4 to 13.0.
- **The automated loop beats hand iteration only by cheating.** Unguarded, haiku-as-proposer went 18.67 → 20.33 in three minutes by writing corpus strings into the prompt, against an explicit instruction not to. With a held-out half and mechanical rejection of corpus quotes, twenty-four proposals found nothing. Keep the loop for wording search and keep both guards; the eval repeated enough times to see past the noise is the part that was actually missing.
- **Single runs of this corpus are noise.** Arms separated by 1.0 in one run were separated by 0.1 at n=20; three serial runs of the final prompt scored 16, 19 and 20 out of 27.

### Round 2 — examples, once overfitting became measurable

The no-examples constraint was lifted after the [perturbation sweep](../assets/43-dictation-corpus/results/prompt-tuning-haiku/perturbation/README.md) and the [recorded holdout](../assets/43-dictation-corpus/results/holdout/README.md) made overfitting something a run could catch rather than something a policy had to prevent. The constraint that replaced it is narrower and mechanical: an example may be invented, never quoted from anything the prompt is scored on, enforced by `leakcheck.py` over all six corpus JSONLs and the perturbation grid's vocabularies. It rejected two first drafts that quoted the holdout.

- **The self-correction rule was two rules in one name, and now it is one.** Rewritten for clause-level cancellation with one invented example: whole-clause backtracks 9/24 → 23/24, cross-rule 18/24 → 24/24, double corrections 21/24 → 24/24, out of sample. On the fifteen recorded holdout entries it recovers `hpolish-07` outright and turns `hpolish-01`'s failure from *keeps the cancelled instruction* into *deletes it and leaves a stray connective*.
- **Spell-out is not a capability limit.** Round 1 concluded haiku could not execute the rule, on the evidence of eleven rule-only wordings and an example-bearing baseline that was only carrying two memorized corpus mappings. One *invented* example takes the rule from 18.1% to 52.8% on twenty-four fresh variants. The construction it still cannot do is the one that deletes unnamed letters (`Katherine with a K and a Y` → `Kathryn`), where it now fails by attempting rather than by declining.
- **Identifier-from-context needed a declaration shown, not described.** 7/36 → 34/36 on declarations, call sites unchanged at 35/36. A sentence written for engine-mangled fragments made every shape worse including its own and was contracted out; that fragment expansion remains unreachable.
- **The holdout moved for the first time: 7.5 → 9.1 of 15, n=10 both arms, one pass.** Four entries recovered, none lost. Round 1's in-sample gain had not transferred at all; this one did, and the frozen 25-entry corpus — 18.50 against 18.30 — could not see it either way.
- **Two rejected changes are the round's methodological finding.** A layout clause worth +1.5 on the punctuation grid was deleting a question mark from a disfluency entry, and a clause protecting unfinished tails bought four points of bare-endings by giving back four of whole-clause backtrack. A rule grid sees its own rule; every added sentence is also an instruction about every other sentence.
- **Two-tier scoring made the search affordable.** The subscription transport shifts absolute scores about three points and preserves an A-vs-B delta, so wordings were screened free and only survivors re-measured on the metered endpoint — about 9,500 metered calls for the round, with roughly as many again screened at no cost.

The Cerebras leg ran once the vault unlocked: gpt-oss-120b baseline 15.83/25 → final 16.67/25 at n=6 — the haiku-tuned prompt transfers positively to every model measured. Two of its three invariant pathologies are gone under the new prompt (no appended period, no `GrokQ` mangling) and the never-obey invariant held in 12/12 runs; untranslated `period` remains its signature miss. Gemini was measured through the gateway rather than Google direct, which round 3 established is score-identical.
