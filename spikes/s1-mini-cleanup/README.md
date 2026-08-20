# S1-mini cleanup spike

Runtime and quality comparison for [ticket 45](../../docs/wayfinding/finishing-mini-whisper/tickets/45-local-cleanup-s1-mini.md): "S1-mini" by "Superwhisper" (0.6B Qwen3 fine-tune, a dedicated STT text normalizer) against the gateway baseline, on the same dev-channel history entries the cleanup benchmark harness uses. Findings live in the [ticket asset](../../docs/wayfinding/finishing-mini-whisper/assets/45-local-cleanup-s1-mini.md).

## Legs

```sh
# GGUF (llama.cpp; downloads Q4_K_M ~462 MiB on first run)
brew install llama.cpp
llama-server -hf superwhisper/s1-mini-GGUF:Q4_K_M --jinja \
  --chat-template-kwargs '{"enable_thinking":false}' --temp 0 --port 8317
python3 spikes/s1-mini-cleanup/spike_gguf.py            # history entries, timed
python3 spikes/s1-mini-cleanup/probe.py                 # styling axes + failure boundaries

# MLX (bf16 ~1.2 GB on first run)
uv run --with mlx-lm spikes/s1-mini-cleanup/spike_mlx.py
```

The gateway baseline comes from the benchmark harness (`assets/38-cleanup-model-benchmark/`) against `gpt-5.6-luna`.

Input format is load-bearing: the exact documented system prompt, a `[Styling: …] [Structure: …] [Context: …]` control line, and `enable_thinking=false`. Any deviation degrades to garbage — this model takes no other instructions.
