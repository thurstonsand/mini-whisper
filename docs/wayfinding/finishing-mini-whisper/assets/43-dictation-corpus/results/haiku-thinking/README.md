# Haiku 5.5 with thinking disabled

The question (2026-10-27): the app sends `model`, `messages`, and `stream: false` and nothing else, so `claude-haiku-5-5` runs at Anthropic's defaults: adaptive thinking on, effort `medium`. Would `thinking: {"type": "disabled"}` make cleanup faster without making it worse? Haiku only.

The answer is **no**. Disabling thinking saves about 200 ms at the median and 2 s at p90, and it costs a point and a half on the holdout, half the unspoken breaks, a dictionary want, and the grid's identifier, spell-out, and layout rules. It also refuses a grid input that the default arm does not.

## Conditions

- Prompt: `r8-857`, the shipped `CleanupPrompt.builtIn` (`../prompt-tuning-r8/candidates/confirm5/r8-857.txt`, identical to the Swift).
- Transport: the raw Anthropic API, `POST https://api.anthropic.com/v1/chat/completions`, `tune.py --provider anthropic-api --metered`. The `disabled` arm adds `--thinking-disabled`, which puts `"thinking": {"type": "disabled"}` in the body. The compatibility layer accepts it; `reasoning_effort` is documented as ignored there, so effort cannot be lowered on this endpoint.
- Both arms ran in the same session, concurrently, with round 8's guard set: frozen 25 and holdout at n=10, the layout arm at n=10, three stage-2 runs, and the nine-rule grid at n=10. Judged by Sol, exact in brackets.
- Latency is `latency.py`: serial, both arms back to back per entry with alternating order, 62 entries × 3 repeats, after the quality arms finished.

## Quality

| guard | default (thinking on) | `thinking: disabled` |
| ----- | --------------------: | -------------------: |
| frozen 25, n=10 | 20.00 (18.00) | 20.00 (16.70) |
| holdout, n=10 | **11.50 (9.50)** | 10.10 (8.10) |
| dictionary wants, 3 runs | **17, 17, 17** | 16, 15, 16 |
| dictionary traps bitten | 0 | 1 |
| layout no-break controls | **109/110** | 100/110 |
| layout unspoken breaks | **39/40** | 16/40 |
| layout requested breaks | 21/30 | **30/30** |
| refusals, all arms | 3/3140 (`layout-none-07`) | 10/3140 (`punct-17`, every run) |

The grid, rule rate:

| rule | default | disabled |
| ---- | ------: | -------: |
| bare endings | 92.9% | 85.4% |
| dictionary exactness | 83.3% | 84.2% |
| identifier from context | **99.7%** | 59.2% |
| layout | **92.1%** | 71.2% |
| never obey | 100.0% | 97.1% |
| self-correction | 97.7% | 94.4% |
| spell-out | **66.7%** | 25.0% |
| spoken punctuation | **92.5%** | 80.0% |
| symbol attachment | 100.0% | 100.0% |

The default arm reproduces round 8's `r8-857` confirmation within noise: frozen 20.40, holdout 11.30, identifiers 100%, spell-out 70.4%.

The frozen tie hides two directions. Without thinking, the restarts and backtracks are no longer applied: `polish-02` goes 5/10 → 0/10, `hpolish-01` 4/10 → 0/10 ("So the deploy is hold off until the tests finish."), `hpolish-07` 9/10 → 1/10 ("Merge it tonight, actually no, wait for CI."), and the dictated paragraph break in `polish-07` 10/10 → 0/10. In the other direction, `polish-33`'s pronoun grammar goes 7/10 → 10/10 and `polish-15` 7/10 → 9/10.

## Latency

Serial, n=186 per arm, request start to response body:

| arm | median | p90 | p95 | max | mean output tokens |
| --- | -----: | --: | --: | --: | -----------------: |
| default | 1189 ms | 3539 ms | 4328 ms | 7707 ms | 171.7 |
| disabled | 992 ms | 1408 ms | 1508 ms | 3149 ms | 40.0 |

Paired on the same entry, disabled is faster in 127 of 186, by 227 ms at the median and 625 ms on average. At `medium` effort the default arm thought on 54 of 186 requests (more than 20 output tokens over the disabled arm's answer). Those carry the whole tail: 2552 ms median and 5173 ms p90, against 1084 and 1492 for the same entries with thinking off. When it did not think, the arms differ by 76 ms. Thinking is most frequent on the layout arm (30/66) and rarest on the short frozen dictations (11/75).

The requests that thought are the restart, backtrack, and layout entries that thinking off gets wrong, so the 2 s tail is the price of exactly the gains above.

## Spend

| arm | calls | USD |
| --- | ----: | --: |
| default, all guards | 3,212 | 0.93 |
| disabled, all guards | 3,212 | 0.70 |
| latency | 372 | 0.10 |
| **total** | 6,796 | **1.72** |

## Reproducing

```sh
cd ../prompt-tuning-haiku
P=../prompt-tuning-r8/candidates/confirm5/r8-857.txt
T="--provider anthropic-api --metered"          # add --thinking-disabled for the other arm
./tune.py stage3 $T --prompt $P --repeat 10 --output ../haiku-thinking/runs/default/frozen10.json
./tune.py stage3 $T --holdout --prompt $P --repeat 10 --output ../haiku-thinking/runs/default/holdout10.json
./tune.py stage3 $T --prompt $P --script ../../stage3-layout.jsonl --raw ../prompt-tuning-r4/stage3-layout-raw.jsonl --include-excluded --repeat 10 --output ../haiku-thinking/runs/default/layout10.json
./tune.py stage2 $T --prompt $P --output ../haiku-thinking/runs/default/stage2-1.jsonl   # ×3
./perturb.py $T --prompt $P --repeat 10 --out ../haiku-thinking/runs/default/grid
cd ../haiku-thinking && ./latency.py runs/latency.jsonl 3
```
