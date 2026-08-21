# Gemini 3.6 Flash, direct — what the gateway costs

One question: how much of gemini's 2.5 s is Google, and how much is `aig.thurstons.house`. Same model, same raw, same prompt, same body — only the endpoint changes, from the gateway to Google's own OpenAI-compatible surface at `https://generativelanguage.googleapis.com/v1beta/openai`. `gemini-3.6-flash` is on the public API under that exact id; no substitution was needed.

Raw: [`built-in-r2`](../built-in-r2/) (Parakeet), the same 27 stage-3 transcripts every cleanup model in the matrix was scored on.

```sh
./corpus_cleanup.py stage3 stage3-polish.jsonl --raw results/built-in-r2/stage3-raw.jsonl \
  --endpoint https://generativelanguage.googleapis.com/v1beta/openai \
  --api-key-env GEMINI_APIKEY --model gemini-3.6-flash --results-dir results/gemini-direct
```

## Headline

| route                           | exact match       | cleanup median | cleanup mean | e2e median  |
| ------------------------------- | ----------------- | -------------- | ------------ | ----------- |
| gateway (`aig.thurstons.house`) | 19/27 (70.4%)     | 2476 ms        | 3482 ms      | 2532 ms     |
| **direct (Google)**             | **19/27 (70.4%)** | **1858 ms**    | 2827 ms      | **1914 ms** |

**The score is identical and so is the failure set** — `polish-01`, `-11`, `-15`, `-20`, `-22`, `-30`, `-33`, `-36`, the same eight entries, which is the sanity check the run existed to provide. Only two of 27 cleaned strings differ at all between the routes, both on entries both routes fail: the gateway writes `maxRetryCount` on `polish-20` where the direct call leaves `max retry count`, and the direct call adds a period to `polish-30`'s bare ending. Sampling noise, not transport.

## The proxy tax is real but small against the model

618 ms at the median — the direct route is 25% faster. Paired per entry, the median delta is a more modest **247 ms**, because both routes have long tails from the same source: gemini thinks for as long as it wants, and both routes recorded a >13 s outlier on the capstone. The distributions overlap heavily; the honest statement is that the gateway costs a few hundred milliseconds and gemini costs two seconds.

So the gateway is not why gemini is slow, and removing it does not make gemini a latency choice. What it does do is put gemini at 1.9 s end to end instead of 2.5 s, which matters when the comparison is against haiku at 0.7 s: the gap narrows from 3.6x to 2.7x and stays a gap.

## Caveat

One run each, 27 entries, a residential connection, and a model whose latency is dominated by non-deterministic thinking. The 618 ms median difference is larger than the noise on this corpus but not by an order of magnitude; a second pair of runs is cheap and would firm it up.
