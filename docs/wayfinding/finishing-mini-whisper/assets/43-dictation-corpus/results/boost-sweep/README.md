# Boost similarity sweep

`RecognitionBoostThresholds.minimumSimilarity` swept across stage 2's recordings, everything else held at the app's own tuning. The threshold is now injectable — `LocalASREngine(modelRoot:gateConfiguration:boostThresholds:)` — and `asr-replay --minimum-similarity` is the seam this sweep used. The 0.65 run is byte-identical to `built-in/stage2-boosted.jsonl`, which is the proof the seam changed nothing.

```sh
for s in 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90; do
  asr-replay --stage stage2-dictionary.jsonl --boost-from-wants --minimum-similarity $s \
    --recordings recordings/stage2-dictionary-built-in --output results/boost-sweep/stage2-boosted-$s.jsonl
done
./score_corpus.py --report results/boost-sweep/sweep-score.json sweep stage2-dictionary.jsonl \
  --run 0.50=results/boost-sweep/stage2-boosted-0.50.jsonl ...
```

Recordings: built-in microphone, first run. Engine: `parakeet-tdt-0.6b-v2-coreml @ ee09c56`, int8 encoder, CTC boost model. 15-term `wants` union staged for every point.

## The curve

| minSimilarity | wants recall | traps bitten | median |
| ------------- | ------------ | ------------ | ------ |
| 0.50 | 18/18 100.0% | 8/8 100.0% | 150 ms |
| 0.55 | 18/18 100.0% | 8/8 100.0% | 151 ms |
| 0.60 | 18/18 100.0% | 7/8 87.5% | 152 ms |
| **0.65** (shipping) | 16/18 88.9% | 5/8 62.5% | 158 ms |
| 0.70 | 15/18 83.3% | 5/8 62.5% | 153 ms |
| 0.75 | 15/18 83.3% | 5/8 62.5% | 162 ms |
| 0.80 | 15/18 83.3% | 5/8 62.5% | 165 ms |
| 0.85 | 14/18 77.8% | 5/8 62.5% | 166 ms |
| 0.90 | 10/18 55.6% | 3/8 37.5% | 164 ms |

Bare ASR, for the floor: 5/18 recall, 0/8 traps, 56 ms.

## Verdict

**No threshold reaches 80% recall with fewer than two traps.** The question the sweep was run to answer has a clean negative answer.

The two quantities move together over the whole range. Above 0.60 the trap set stops shrinking at all — `Cerebras`, `Ghostty`, `Keychain`, `MiniWhisper`, and `Parakeet` are bitten identically from 0.65 through 0.85 while recall bleeds off — so the range 0.65–0.85 buys nothing but lost terms. The next drop in traps only arrives at 0.90, and it costs eight of eighteen wanted terms to get there. `Qwen` is never recovered at any setting.

That shape is what a similarity floor can do: it is one scalar separating "sounds like the term" from "is the term", and the corpus's traps were built to sound like the terms. The shipping 0.65 is a defensible point on a bad curve, not a bad point on a good one. The fix is not a better threshold — see [`dictionary-three-way`](../dictionary-three-way/), where the cleanup pass reads the same vocabulary as text and separates the two cases outright.
