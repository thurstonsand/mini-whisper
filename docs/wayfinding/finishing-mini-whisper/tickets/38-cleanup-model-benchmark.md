---
status: closed
type: research
claimed: subagent:cleanup-model-benchmark
blocked-by: []
---

# Cleanup model benchmark: fast models for the cleanup task

## Question

Which models are fast enough to sit inside a blocking dictation pipeline while staying smart enough for the cleanup task (punctuation, casing, disfluency removal, spoken-symbol conversion, light rewording against field context)? Latency is the UX-defining axis. Deliver:

1. **Provider survey**: OpenAI-compatible fast-inference providers (Cerebras, Groq, Fireworks, Together, and peers) — model menus, measured/published TTFT and tokens-per-second, pricing, API compatibility quirks. Primary sources only.
2. **Benchmark harness design**: a runnable harness that replays History entries (raw transcript + captured field context) through any OpenAI-compatible endpoint and reports per-model latency and a cleaned/raw diff for eyeballing quality. History's raw+cleaned preservation ([LLM cleanup](18-llm-cleanup.md), round 2) is what makes the corpus exist.
3. **Ballpark runs on this machine** against official endpoints where credentials are available; where a key is missing, record exactly what the user must provision and leave the harness ready to run. The user runs work-gateway comparisons (Claude Haiku 4.5, GPT-5.6-luna) themselves.

Findings to `../assets/38-cleanup-model-benchmark.md`, harness under the same assets directory, cited; recommend a default-model shortlist, don't decide.

## Resolution

The provider screen, primary-source citations, credential status, and default-model test order are in [the benchmark findings](../assets/38-cleanup-model-benchmark.md). The dependency-free, read-only History replay harness is in [`../assets/38-cleanup-model-benchmark/`](../assets/38-cleanup-model-benchmark/README.md): it takes an OpenAI-compatible endpoint, key, and model(s), reports final-response wall-clock latency, and prints raw → cleaned diffs. No official-endpoint run was possible because no obvious provider credential environment variable was exported; the asset records the exact variables and commands needed, while the work-gateway comparisons remain for their operator.
