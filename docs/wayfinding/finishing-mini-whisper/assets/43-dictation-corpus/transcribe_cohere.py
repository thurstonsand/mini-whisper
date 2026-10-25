#!/usr/bin/env python3
"""Replay a corpus stage through MLX Cohere Transcribe, writing asr-replay JSONL.

`--runtime` writes the same runtime record `asr-replay` does, so `bakeoff.py` can compare the two.
Load runs from resolving the cached weights through the warmup transcription, the counterpart of
`asr-replay`'s prewarm; a download is timed apart, and only happens when the weights are not cached.
Each recording is decoded before its timer starts, as `asr-replay` does.
"""

import argparse
import json
from pathlib import Path
import resource
import sys
import time

import numpy as np

MODEL = "CohereLabs/cohere-transcribe-03-2026"
REVISION = "b1eacc2686a3d08ceaae5f24a88b1d519620bc09"


def read_samples(path: Path) -> np.ndarray:
    """16 kHz mono like `asr-replay` demands; field cases are float WAVs, the rest int16."""
    from mlx_audio.audio_io import read

    samples, sample_rate = read(path, dtype="float32")
    if sample_rate != 16000 or samples.ndim != 1:
        raise ValueError(f"{path} is not 16 kHz mono")
    return samples


def peak_rss_bytes() -> int:
    # macOS reports ru_maxrss in bytes, unlike Linux's KiB.
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss


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
    parser.add_argument("--runtime", type=Path, help="JSON destination: load, memory")
    return parser.parse_args()


def resolve_weights(args: argparse.Namespace) -> tuple[Path, float | None]:
    """The cached snapshot, downloading it first if needed; returns the download seconds."""
    from huggingface_hub import snapshot_download
    from huggingface_hub.errors import LocalEntryNotFoundError
    from mlx_audio.utils import DEFAULT_ALLOW_PATTERNS

    def snapshot(local_files_only: bool) -> Path:
        return Path(
            snapshot_download(
                args.model,
                revision=args.revision,
                allow_patterns=DEFAULT_ALLOW_PATTERNS,
                local_files_only=local_files_only,
            )
        )

    try:
        return snapshot(local_files_only=True), None
    except LocalEntryNotFoundError:
        started = time.monotonic()
        path = snapshot(local_files_only=False)
        return path, time.monotonic() - started


def load_model(args: argparse.Namespace, weights: Path):
    from mlx_audio.stt import load

    model = load(str(weights), strict=True)
    if args.quantization != "none":
        import mlx.core as mx
        import mlx.nn as nn

        nn.quantize(
            model,
            bits=int(args.quantization.removesuffix("bit")),
            group_size=args.quantization_group_size,
        )
        mx.eval(model.parameters())
    return model


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

    weights, download_seconds = resolve_weights(args)
    started = time.monotonic()
    model = load_model(args, weights)
    model.generate(
        read_samples(recordings[0][1]),
        sample_rate=16000,
        language=args.language,
        max_tokens=args.max_tokens,
    )
    load_seconds = time.monotonic() - started
    args.output.parent.mkdir(parents=True, exist_ok=True)

    with args.output.open("w", encoding="utf-8") as sink:
        for entry, wav in recordings:
            samples = read_samples(wav)
            started = time.monotonic()
            result = model.generate(
                samples,
                sample_rate=16000,
                language=args.language,
                max_tokens=args.max_tokens,
            )
            latency_ms = (time.monotonic() - started) * 1000
            transcript = result.text.strip()
            sink.write(
                json.dumps(
                    {
                        "audioSeconds": len(samples) / 16000,
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

    peak = peak_rss_bytes()
    print(
        f"model load: {load_seconds * 1000:.0f} ms; peak RSS: {peak / 2**20:.0f} MiB",
        file=sys.stderr,
    )
    if args.runtime:
        quantization = (
            "" if args.quantization == "none" else f" mlx-{args.quantization}"
        )
        runtime = {
            "identity": f"{args.model}@{args.revision}{quantization}",
            "stage": args.stage.name,
            "entries": len(recordings),
            "loadSeconds": load_seconds,
            "peakResidentBytes": peak,
            "modelBytes": sum(f.stat().st_size for f in weights.iterdir()),
        }
        if download_seconds is not None:
            runtime["downloadSeconds"] = download_seconds
        args.runtime.write_text(json.dumps(runtime, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
