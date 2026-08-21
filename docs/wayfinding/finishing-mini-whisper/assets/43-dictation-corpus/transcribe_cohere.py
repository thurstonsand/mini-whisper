#!/usr/bin/env python3
"""Replay a corpus stage through MLX Cohere Transcribe, writing asr-replay JSONL."""

import argparse
import json
from pathlib import Path
import resource
import sys
import time
import wave

MODEL = "CohereLabs/cohere-transcribe-03-2026"
REVISION = "b1eacc2686a3d08ceaae5f24a88b1d519620bc09"


def audio_seconds(path: Path) -> float:
    with wave.open(str(path)) as wav:
        return wav.getnframes() / wav.getframerate()


def peak_rss_mib() -> float:
    # macOS reports ru_maxrss in bytes, unlike Linux's KiB.
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024 / 1024


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--recordings", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--model", default=MODEL)
    parser.add_argument("--revision", default=REVISION)
    parser.add_argument("--language", default="en")
    parser.add_argument("--max-tokens", type=int, default=256)
    parser.add_argument(
        "--quantization", choices=("none", "4bit", "8bit"), default="none"
    )
    parser.add_argument("--quantization-group-size", type=int, default=64)
    return parser.parse_args()


def load_model(args: argparse.Namespace):
    from mlx_audio.stt import load

    started = time.monotonic()
    model = load(args.model, revision=args.revision, strict=True)
    if args.quantization != "none":
        import mlx.core as mx
        import mlx.nn as nn

        nn.quantize(
            model,
            bits=int(args.quantization.removesuffix("bit")),
            group_size=args.quantization_group_size,
        )
        mx.eval(model.parameters())
    load_ms = (time.monotonic() - started) * 1000
    return model, load_ms


def main() -> int:
    args = parse_args()
    entries = [
        json.loads(line)
        for line in args.stage.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    recordings = [(entry, args.recordings / f"{entry['id']}.wav") for entry in entries]
    missing = [path for _, path in recordings if not path.exists()]
    if missing:
        raise FileNotFoundError(f"missing recording: {missing[0]}")

    model, load_ms = load_model(args)
    model.generate(
        str(recordings[0][1]),
        language=args.language,
        max_tokens=args.max_tokens,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)

    with args.output.open("w", encoding="utf-8") as sink:
        for entry, wav in recordings:
            started = time.monotonic()
            result = model.generate(
                str(wav), language=args.language, max_tokens=args.max_tokens
            )
            latency_ms = (time.monotonic() - started) * 1000
            transcript = result.text.strip()
            sink.write(
                json.dumps(
                    {
                        "audioSeconds": audio_seconds(wav),
                        "id": entry["id"],
                        "latencyMs": latency_ms,
                        "outcome": "transcript",
                        "transcript": transcript,
                    },
                    sort_keys=True,
                )
                + "\n"
            )
            print(f"{entry['id']}: {latency_ms:.0f} ms  {transcript}")

    print(
        f"model load: {load_ms:.0f} ms; peak RSS: {peak_rss_mib():.0f} MiB",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
