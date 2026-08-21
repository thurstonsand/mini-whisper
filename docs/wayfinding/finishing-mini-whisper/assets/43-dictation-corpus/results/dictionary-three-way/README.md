# Dictionary three-way

Stage 2's audio, one vocabulary, three places to spend it: in the sidecar before the transcript exists, in the DICTIONARY block after it exists, or both. Every arm is scored on its **final text** — the string the app would have typed — so a boosted transcript and a cleaned transcript are compared on the same terms.

The hypothesis under test: the cleanup pass recovers misheard terms from the DICTIONARY block without biting traps, making the sidecar redundant or harmful.

```sh
# (a) and (c): the same 15-term `wants` union staged as CleanupPrompt's DICTIONARY block.
./corpus_cleanup.py stage2 stage2-dictionary.jsonl --raw results/built-in/stage2-bare.jsonl \
  --dictionary-from-wants --endpoint https://aig.thurstons.house/v1 \
  --model gpt-5.6-luna --model gemini-3.6-flash --results-dir results/dictionary-three-way --arm bare
# ... and again with --raw results/built-in/stage2-boosted.jsonl --arm boosted

./score_corpus.py --report results/dictionary-three-way/five-arm-score.json \
  sweep stage2-dictionary.jsonl --run bare=... --run bare+luna=... --run boosted=... (etc.)
```

Conditions: built-in microphone, first run's stage 2 recordings. Engine `parakeet-tdt-0.6b-v2-coreml @ ee09c56`, int8 encoder; sidecar at the shipping `minimumSimilarity` 0.65. Cleanup: `CleanupPrompt.builtIn` with no additional instructions, dictionary staged exactly as `CleanupPrompt.userMessage` stages it — gpt-5.6-luna and gemini-3.6-flash through the gateway at `aig.thurstons.house`, claude-haiku-4-5 direct against Anthropic's OpenAI-compatible endpoint, gpt-oss-120b on Cerebras. Terms match exactly as the corpus writes them.

## The arms

| arm | wants recall | traps bitten | added latency | end to end |
| --- | ------------ | ------------ | ------------- | ---------- |
| bare ASR | 5/18 27.8% | 0/8 0.0% | — | 56 ms |
| bare + luna | **18/18 100.0%** | 1/8 12.5% | +2379 ms | 2427 ms |
| bare + gemini | **18/18 100.0%** | **0/8 0.0%** | +1954 ms | 2005 ms |
| bare + haiku 4.5 | 17/18 94.4% | 2/8 25.0% | +671 ms | 719 ms |
| bare + gpt-oss-120b | 15/18 83.3% | 1/8 12.5% | +381 ms | 411 ms |
| sidecar-boosted | 16/18 88.9% | 5/8 62.5% | +98 ms | 154 ms |
| boosted + luna | **18/18 100.0%** | 4/8 50.0% | +2309 ms | 2407 ms |
| boosted + gemini | **18/18 100.0%** | 2/8 25.0% | +1890 ms | 2000 ms |
| boosted + haiku 4.5 | 17/18 94.4% | 4/8 50.0% | +770 ms | 931 ms |
| boosted + gpt-oss-120b | 16/18 88.9% | 5/8 62.5% | +326 ms | 476 ms |

## Verdict: the hypothesis holds, and the sidecar is worse than redundant

**bare + gemini is a perfect run** — every wanted term recovered, no trap bitten. bare + luna misses perfection by one: it writes `She answered with a MiniWhisper of her own`, the single case where a dictionary term is also an ordinary English phrase. haiku 4.5 costs one term (`tuistory`) and one extra trap (`Keychain`) to run three times faster; gpt-oss-120b is the weakest reader of the block, missing `Ghostty`, `Cerebras`, and `tuistory`, but it still beats the sidecar on traps four to one.

The sidecar cannot approach that. At its best setting it recovers 16 of 18 terms and bites 5 of 8 traps, and [the sweep](../boost-sweep/) shows no threshold does better. It works on acoustics — it never sees that "a ghostly draught moved through the stairwell" is a sentence about a draught — so the same evidence that recovers `Ghostty` in one sentence destroys `ghostly` in another.

**Boosting first actively harms the downstream arms, and it does so for all four models.** Every model bites strictly more traps on boosted input than on bare, and not one of them recovers a single additional term for it: luna 1→4, gemini 0→2, haiku 2→4, gpt-oss 1→5. The mechanism is one-way: `Ghostty` in the transcript is a plausible word in a plausible slot, and the cleanup pass has no signal that it used to be `ghostly`. The sidecar's false positives are laundered into fluent text and become permanent. Every trap bitten by a "boosted +" arm was already bitten by the sidecar alone, and gpt-oss-120b simply passes all five through unchanged — four models, four times the same result, which is about as much as twenty-four entries can say.

So the ordering is not a wash. Vocabulary spent before the transcript exists buys 89% recall at the cost of five destroyed sentences; the same vocabulary spent after buys 100% recall at the cost of zero to one. The sidecar's only remaining argument was latency — +98 ms against the gateway's +2 s. The two direct-endpoint models weaken even that: gpt-oss-120b on Cerebras adds 381 ms for 83.3% recall at one trap, and haiku 4.5 adds 671 ms for 94.4% at two. Both stay inside a few hundred milliseconds of the sidecar while beating it outright on the thing the sidecar is bad at. What survives is the offline case: with cleanup off, the sidecar is the whole vocabulary story.

## Caveats

- Twenty-four entries and eight traps. The gap here is wide enough to survive that, but "0/8" is not "zero".
- The gateway models are non-deterministic; a re-run may move a cell by one.
- End-to-end latency charges ASR plus cleanup. The cleanup pass is not free and this corpus does not measure whether the user is waiting on it.
