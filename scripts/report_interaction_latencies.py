#!/usr/bin/env python3

import argparse
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
import re
import statistics
import sys

TIMESTAMP_FORMAT = "%Y-%m-%d %H:%M:%S.%f"
LINE_PATTERN = re.compile(
    r"^(?P<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}).*benchmark (?P<marker>[a-z-]+)$"
)
THRESHOLDS_MS = {
    "pill": 25.0,
    "capture": 300.0,
    "transcription": 75.0,
}


@dataclass
class Cycle:
    activation: datetime
    pill: datetime | None = None
    first_buffer: datetime | None = None
    release: datetime | None = None
    transcription: datetime | None = None


def milliseconds(start: datetime, end: datetime) -> float:
    return (end - start).total_seconds() * 1000


def parse_cycles(log_path: Path) -> list[Cycle]:
    cycles: list[Cycle] = []
    current: Cycle | None = None

    for line in log_path.read_text().splitlines():
        match = LINE_PATTERN.match(line)
        if not match:
            continue
        timestamp = datetime.strptime(match.group("timestamp"), TIMESTAMP_FORMAT)
        marker = match.group("marker")

        if marker in {"activation-triggered", "hotkey-press"}:
            current = Cycle(activation=timestamp)
            cycles.append(current)
        elif current is None:
            continue
        elif marker == "pill-visible" and current.pill is None:
            current.pill = timestamp
        elif marker == "first-audio-buffer" and current.first_buffer is None:
            current.first_buffer = timestamp
        elif marker == "recording-release" and current.release is None:
            current.release = timestamp
        elif marker == "transcription-started" and current.transcription is None:
            current.transcription = timestamp

    return cycles


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Report and enforce MiniWhisper interaction-latency thresholds."
    )
    _ = parser.add_argument("log", type=Path)
    args = parser.parse_args()

    cycles = parse_cycles(args.log)
    if not cycles:
        print(f"No benchmark activations found in {args.log}", file=sys.stderr)
        return 1

    measurements: dict[str, list[float]] = {name: [] for name in THRESHOLDS_MS}
    print("run  activation→pill  activation→first-buffer  release→transcription")
    for index, cycle in enumerate(cycles, start=1):
        missing = [
            name
            for name, value in {
                "pill-visible": cycle.pill,
                "first-audio-buffer": cycle.first_buffer,
                "recording-release": cycle.release,
                "transcription-started": cycle.transcription,
            }.items()
            if value is None
        ]
        if missing:
            print(f"Run {index} is incomplete: {', '.join(missing)}", file=sys.stderr)
            return 1

        pill = milliseconds(cycle.activation, cycle.pill)
        capture = milliseconds(cycle.activation, cycle.first_buffer)
        transcription = milliseconds(cycle.release, cycle.transcription)
        measurements["pill"].append(pill)
        measurements["capture"].append(capture)
        measurements["transcription"].append(transcription)
        print(
            f"{index:>3}  {pill:>10.1f} ms  {capture:>17.1f} ms  {transcription:>21.1f} ms"
        )

    print()
    failures: list[str] = []
    labels = {
        "pill": "activation→pill",
        "capture": "activation→first-buffer",
        "transcription": "release→transcription",
    }
    for name, values in measurements.items():
        maximum = max(values)
        threshold = THRESHOLDS_MS[name]
        status = "PASS" if maximum <= threshold else "FAIL"
        print(
            f"{labels[name]:>24}: median {statistics.median(values):6.1f} ms, "
            f"max {maximum:6.1f} ms, threshold {threshold:6.1f} ms  {status}"
        )
        if maximum > threshold:
            failures.append(labels[name])

    if failures:
        print(f"Latency regression: {', '.join(failures)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
