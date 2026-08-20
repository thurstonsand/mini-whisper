# Cleanup benchmark harness

`cleanup_benchmark.py` is a dependency-free Python 3 script for running the same History corpus against one or more OpenAI-compatible chat-completions models. It reads the history file only; it neither alters it nor writes corpus text or model output into this directory.

The dev-channel default is:

```text
~/Library/Application Support/MiniWhisper Dev/History/history.json
```

It selects only `HistoryEntry.original.text`, never a re-transcription or `delivery.text`. That preserves the distinction between immutable ASR evidence and a later cleanup/delivery result. Entries persist the dictation's field context (log version 2; version 1 is still read), and the payload includes it automatically. `--without-context` makes a matched corpus useful for an explicit context A/B.

## Run

The endpoint is the API base URL: the harness appends `/chat/completions`. Keep the run small at first: its output contains raw dictation and cleaned text so the diff can be judged, and those are sent to the endpoint you name.

```sh
cd docs/wayfinding/finishing-mini-whisper/assets/38-cleanup-model-benchmark

python3 cleanup_benchmark.py \
  --endpoint https://api.groq.com/openai/v1 \
  --api-key-env GROQ_API_KEY \
  --model openai/gpt-oss-20b \
  --model openai/gpt-oss-120b \
  --limit 10
```

Provider-ready variants:

```sh
# Cerebras
python3 cleanup_benchmark.py \
  --endpoint https://api.cerebras.ai/v1 \
  --api-key-env CEREBRAS_API_KEY \
  --model gpt-oss-120b --limit 10

# Fireworks (the `accounts/...` model namespace is significant)
python3 cleanup_benchmark.py \
  --endpoint https://api.fireworks.ai/inference/v1 \
  --api-key-env FIREWORKS_API_KEY \
  --model accounts/fireworks/models/gpt-oss-20b --limit 10

# Together
python3 cleanup_benchmark.py \
  --endpoint https://api.together.ai/v1 \
  --api-key-env TOGETHER_API_KEY \
  --model openai/gpt-oss-20b --limit 10

# SambaNova
python3 cleanup_benchmark.py \
  --endpoint https://api.sambanova.ai/v1 \
  --api-key-env SAMBANOVA_API_KEY \
  --model gpt-oss-120b --limit 10
```

For the controlled work gateway, substitute its base URL, the gateway's exported key variable, and the allowed model IDs. The caller owns provisioning and approval of that egress; no gateway assumptions are baked into the script.

Useful controls:

```text
--history PATH                 use another channel/corpus
--entry UUID                   replay one entry (repeatable)
--limit N                      benchmark newest N usable originals
--timeout SECONDS              per request; default 10 seconds
--max-completion-tokens N      default 96
--without-context              do not send field context even when stored
```

The report is intentionally non-streaming wall-clock time from HTTP request start to the final response body. That is the blocking pipeline's user-visible completion time, including network, queueing, prefill, decoding, and response transfer. It is not TTFT or decode TPS; use provider figures only as a provisional screen, then repeat this harness at the relevant network location and load. The 10-second default is the cleanup ticket's hard backstop, not a claim that a model meeting it feels good; inspect median and tail latency against the roughly three-second skip affordance.

`--help` is a no-network smoke test. A real run returns nonzero if any request fails, prints each entry's request wall-clock time and unified `raw → cleaned` diff, then prints per-model median/p95/min/max for successful requests. It deliberately does not save results because the corpus is private.
