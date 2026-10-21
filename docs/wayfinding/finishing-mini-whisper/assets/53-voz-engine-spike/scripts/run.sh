#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
corpus="$root/../43-dictation-corpus"
output="$corpus/results/voz"
model="$HOME/.cache/miniwhisper-research/voz/8e7ab8ca342c6bb00f9347a25e53fe44543b2a40"
mkdir -p "$output"
DAL_HTTP_DEBUG=1 "$root/.build/release/VozReplay" "$model" "$corpus" "$output" > "$output/run.log" 2>&1
DAL_HTTP_DEBUG=1 "$root/.build/release/VozReplay" "$model" --load-only > "$output/warm-load.log" 2>&1
python3 "$corpus/score_corpus.py" --report "$output/stage1-score.json" stage1 "$corpus/stage1-intelligibility.jsonl" "$output/stage1.jsonl"
python3 "$corpus/score_corpus.py" --report "$output/stage1-longform-score.json" stage1 "$corpus/stage1-longform.jsonl" "$output/stage1-longform.jsonl"
python3 "$corpus/score_corpus.py" --report "$output/stage2-score.json" sweep "$corpus/stage2-dictionary.jsonl" --run "voz=$output/stage2-bare.jsonl" --run "incumbent=$corpus/results/built-in/stage2-bare.jsonl"
python3 "$corpus/score_corpus.py" --report "$output/stage2-holdout-score.json" sweep "$corpus/stage2-holdout.jsonl" --run "voz=$output/stage2-holdout-bare.jsonl" --run "incumbent=$corpus/results/holdout/stage2-bare.jsonl"
