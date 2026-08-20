#!/usr/bin/env python3
"""S1-mini spike, MLX leg: same entries, same format, mlx-lm runtime.

Run with: uv run --with mlx-lm spikes/s1-mini-cleanup/spike_mlx.py [model] [limit] [styling]
Loads once, generates per entry with greedy decode, prints per-entry wall clock.
"""

from __future__ import annotations

import json
from pathlib import Path
import sys
import time

from mlx_lm import generate, load

HISTORY = (
    Path.home() / "Library/Application Support/MiniWhisper Dev/History/history.json"
)

SYSTEM = (
    "You are a text normalizer for speech-to-text transcripts. The input begins "
    "with a control line specifying the styling, structure, and context settings; "
    "clean the transcript to match those settings and output only the cleaned text."
)


def main() -> int:
    model_name = sys.argv[1] if len(sys.argv) > 1 else "superwhisper/s1-mini"
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 6
    styling = sys.argv[3] if len(sys.argv) > 3 else "semi-formal"
    model, tokenizer = load(model_name)
    entries = json.loads(HISTORY.read_text())["entries"][:limit]
    times = []
    for entry in entries:
        raw = entry["original"]["text"]
        control = f"[Styling: {styling}] [Structure: prose] [Context: general]"
        prompt = tokenizer.apply_chat_template(
            [
                {"role": "system", "content": SYSTEM},
                {"role": "user", "content": f"{control}\n{raw}"},
            ],
            tokenize=False,
            add_generation_prompt=True,
            enable_thinking=False,
        )
        budget = int(1.3 * len(tokenizer.encode(raw)) + 32)
        started = time.perf_counter()
        cleaned = generate(
            model, tokenizer, prompt=prompt, max_tokens=budget, verbose=False
        )
        elapsed = time.perf_counter() - started
        times.append(elapsed)
        print(f"--- {elapsed * 1000:.0f} ms [{styling}]")
        print(f"raw:     {raw}")
        print(f"cleaned: {cleaned.strip()}")
    times.sort()
    print(
        f"\nSummary: n={len(times)}, median={times[len(times) // 2] * 1000:.0f} ms, "
        f"min={times[0] * 1000:.0f} ms, max={times[-1] * 1000:.0f} ms",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
