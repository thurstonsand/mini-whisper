#!/usr/bin/env python3
"""S1-mini spike, GGUF leg: the documented input format against a local llama-server.

Reads the same dev-channel history entries the cleanup benchmark uses, so the outputs are
directly comparable with the gateway baselines. Prints per-entry wall clock and the output.
"""

from __future__ import annotations

import json
from pathlib import Path
import sys
import time
import urllib.request

HISTORY = (
    Path.home() / "Library/Application Support/MiniWhisper Dev/History/history.json"
)

# Required verbatim per the model card; any rewording degrades output.
SYSTEM = (
    "You are a text normalizer for speech-to-text transcripts. The input begins "
    "with a control line specifying the styling, structure, and context settings; "
    "clean the transcript to match those settings and output only the cleaned text."
)


def normalize(endpoint: str, transcript: str, styling: str) -> tuple[str, float]:
    control = f"[Styling: {styling}] [Structure: prose] [Context: general]"
    body = json.dumps(
        {
            "model": "s1-mini",
            "messages": [
                {"role": "system", "content": SYSTEM},
                {"role": "user", "content": f"{control}\n{transcript}"},
            ],
            "temperature": 0,
            "chat_template_kwargs": {"enable_thinking": False},
        }
    ).encode()
    request = urllib.request.Request(
        f"{endpoint}/v1/chat/completions",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    started = time.perf_counter()
    with urllib.request.urlopen(request, timeout=60) as response:
        payload = json.load(response)
    elapsed = time.perf_counter() - started
    return payload["choices"][0]["message"]["content"].strip(), elapsed


def main() -> int:
    endpoint = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8317"
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 6
    styling = sys.argv[3] if len(sys.argv) > 3 else "semi-formal"
    entries = json.loads(HISTORY.read_text())["entries"][:limit]
    times = []
    for entry in entries:
        raw = entry["original"]["text"]
        cleaned, elapsed = normalize(endpoint, raw, styling)
        times.append(elapsed)
        print(f"--- {elapsed * 1000:.0f} ms [{styling}]")
        print(f"raw:     {raw}")
        print(f"cleaned: {cleaned}")
    times.sort()
    print(
        f"\nSummary: n={len(times)}, median={times[len(times) // 2] * 1000:.0f} ms, "
        f"min={times[0] * 1000:.0f} ms, max={times[-1] * 1000:.0f} ms",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
