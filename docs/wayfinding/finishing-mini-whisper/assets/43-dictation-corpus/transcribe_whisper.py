#!/usr/bin/env python3
"""Replay a corpus stage through whisper.cpp, writing asr-replay's JSONL contract.

`whisper-cli` is a one-shot process, so each entry pays a spawn and a model load that
the in-process engine pays once. Latency is therefore taken from whisper's own timers:
`total time - load time`, the transcription work alone. `--overhead-report` prints the
wall-clock spawn+load tax separately so nobody mistakes one number for the other.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import wave

TIMING = re.compile(r"whisper_print_timings:\s+(load|total) time =\s+([0-9.]+) ms")


def audio_seconds(path: Path) -> float:
    with wave.open(str(path)) as wav:
        return wav.getnframes() / wav.getframerate()


def transcribe(
    wav: Path, model: Path, extra_flags: list[str]
) -> tuple[str, float, float]:
    """Return (transcript, transcription ms, total wall-clock ms for the spawn)."""
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "out"
        command = [
            "whisper-cli",
            "--model",
            str(model),
            "--language",
            "en",
            "--no-timestamps",
            "--output-json",
            "--output-file",
            str(out),
            *extra_flags,
            "--file",
            str(wav),
        ]
        started = time.monotonic()
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        wall_ms = (time.monotonic() - started) * 1000
        payload = json.loads(out.with_suffix(".json").read_text())

    timings = {name: float(value) for name, value in TIMING.findall(result.stderr)}
    transcript = "".join(
        segment["text"] for segment in payload["transcription"]
    ).strip()
    return transcript, timings["total"] - timings["load"], wall_ms


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--recordings", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument(
        "--flag",
        action="append",
        default=[],
        dest="flags",
        help="extra whisper-cli flag, repeatable",
    )
    parser.add_argument(
        "--overhead-report",
        action="store_true",
        help="print the per-entry spawn+load tax excluded from latencyMs",
    )
    args = parser.parse_args()

    entries = [
        json.loads(line) for line in args.stage.read_text().splitlines() if line.strip()
    ]
    args.output.parent.mkdir(parents=True, exist_ok=True)

    overheads = []
    with args.output.open("w") as sink:
        for entry in entries:
            wav = args.recordings / f"{entry['id']}.wav"
            if not wav.exists():
                print(f"missing recording: {wav}", file=sys.stderr)
                continue
            transcript, latency_ms, wall_ms = transcribe(wav, args.model, args.flags)
            overheads.append(wall_ms - latency_ms)
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

    if args.overhead_report and overheads:
        overheads.sort()
        median = overheads[len(overheads) // 2]
        print(
            f"spawn+load overhead excluded from latencyMs: "
            f"median {median:.0f} ms, max {overheads[-1]:.0f} ms",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
