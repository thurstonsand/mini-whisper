#!/usr/bin/env python3
"""Long-audio seam fixtures built from stage 1's recordings.

Almost every corpus recording fits in the engine's 15-second window, so a seam defect — a word
duplicated or dropped where two windows meet — has nowhere to show. `build` concatenates stage 1
utterances into 30, 60, and 90-second fixtures, each twice: `tight`, where trimmed utterances
abut with 50 ms between them so words straddle window boundaries, and `gapped`, where 1.5 s of
room-level noise separates them so quiet pauses straddle the boundaries instead. Each fixture
starts at a different utterance so different words land at the seams. Output is deterministic.

`diff` scores what only long audio can break: each fixture transcript against the same engine's
own transcripts of the isolated utterances, so every difference is introduced by the chunker and
merger rather than by a mishearing the engine would make anyway.

  ./seam_fixtures.py build stage1-intelligibility.jsonl \\
      recordings/stage1-intelligibility-built-in OUT_DIR
  ./seam_fixtures.py diff OUT_DIR/seam-fixtures.jsonl seam.jsonl stage1.jsonl
"""

from __future__ import annotations

import argparse
from array import array
from difflib import SequenceMatcher
import json
import math
from pathlib import Path
import random
import sys
from typing import Any
import wave

from score_corpus import by_id, load_jsonl, normalize

RATE = 16000
FRAME = RATE // 50
MARGIN = RATE * 80 // 1000
TARGETS = (30, 60, 90)
GAPS = {"tight": 0.05, "gapped": 1.5}
FIXTURES_FILE = "seam-fixtures.jsonl"


def read(path: Path) -> array:
    with wave.open(str(path)) as file:
        if (file.getframerate(), file.getnchannels(), file.getsampwidth()) != (
            RATE,
            1,
            2,
        ):
            sys.exit(f"{path} is not 16 kHz mono int16")
        samples = array("h")
        samples.frombytes(file.readframes(file.getnframes()))
    return samples


def rms(samples: array) -> float:
    return math.sqrt(sum(s * s for s in samples) / max(len(samples), 1))


def trim(samples: array) -> tuple[array, float]:
    """Cut leading and trailing silence, keeping 80 ms of margin; returns the noise floor too."""
    frames = [rms(samples[i : i + FRAME]) for i in range(0, len(samples), FRAME)]
    floor = sorted(frames)[len(frames) // 10]
    voiced = [i for i, level in enumerate(frames) if level > max(floor * 4, 150)]
    start = max(voiced[0] * FRAME - MARGIN, 0)
    end = min((voiced[-1] + 1) * FRAME + MARGIN, len(samples))
    return samples[start:end], floor


def build(stage: Path, recordings: Path, out: Path) -> Path:
    """Writes the fixture WAVs and their stage file into `out`; returns the stage file."""
    entries = load_jsonl(stage)
    utterances = []
    for entry in entries:
        samples, floor = trim(read(recordings / f"{entry['id']}.wav"))
        utterances.append((entry, samples, floor))
    noise = random.Random(43)
    floor = sorted(u[2] for u in utterances)[len(utterances) // 2]

    out.mkdir(parents=True, exist_ok=True)
    stage_lines = []
    for gap_name, gap_seconds in GAPS.items():
        for target_index, target in enumerate(TARGETS):
            fixture_id = f"seam-{gap_name}-{target}s"
            gap = array("h")
            gap.extend(
                max(-32768, min(32767, round(noise.gauss(0, floor))))
                for _ in range(round(gap_seconds * RATE))
            )
            audio = array("h")
            segments = []
            cursor = target_index * 7 + (0 if gap_name == "tight" else 3)
            while len(audio) < target * RATE:
                entry, samples, _ = utterances[cursor % len(utterances)]
                if audio:
                    audio.extend(gap)
                segments.append(
                    {
                        "id": entry["id"],
                        "start": round(len(audio) / RATE, 3),
                        "end": round((len(audio) + len(samples)) / RATE, 3),
                    }
                )
                audio.extend(samples)
                cursor += 1
            with wave.open(str(out / f"{fixture_id}.wav"), "wb") as file:
                file.setnchannels(1)
                file.setsampwidth(2)
                file.setframerate(RATE)
                file.writeframes(audio.tobytes())
            scripts = by_id(entries)
            stage_lines.append(
                {
                    "id": fixture_id,
                    "say": " ".join(scripts[s["id"]]["say"] for s in segments),
                    "segments": segments,
                }
            )
    fixtures = out / FIXTURES_FILE
    fixtures.write_text("".join(json.dumps(line) + "\n" for line in stage_lines))
    return fixtures


def diff(fixtures: Path, results: Path, isolated: Path) -> list[dict[str, Any]]:
    """Every word a fixture transcript changed against the isolated utterances it is made of."""
    long_runs = by_id(load_jsonl(results))
    isolated_runs = by_id(load_jsonl(isolated))
    report = []
    for fixture in load_jsonl(fixtures):
        expected: list[str] = []
        owner: list[dict] = []
        for segment in fixture["segments"]:
            words = normalize(isolated_runs[segment["id"]]["transcript"])
            expected.extend(words)
            owner.extend([segment] * len(words))
        heard = normalize(long_runs[fixture["id"]]["transcript"])
        opcodes = SequenceMatcher(None, expected, heard, autojunk=False).get_opcodes()
        changes = []
        for tag, i1, i2, j1, j2 in opcodes:
            if tag == "equal":
                continue
            kind = {"insert": "inserted", "delete": "dropped", "replace": "replaced"}[
                tag
            ]
            if (
                tag == "insert"
                and heard[j1:j2] == expected[max(i1 - (j2 - j1), 0) : i1]
            ):
                kind = "duplicated"
            segment = owner[min(i1, len(owner) - 1)]
            changes.append(
                {
                    "kind": kind,
                    "expected": " ".join(expected[i1:i2]),
                    "heard": " ".join(heard[j1:j2]),
                    "context": " ".join(expected[max(i1 - 4, 0) : i2 + 4]),
                    "utterance": segment["id"],
                    "utteranceSpan": [segment["start"], segment["end"]],
                }
            )
        report.append(
            {
                "id": fixture["id"],
                "audioSeconds": long_runs[fixture["id"]]["audioSeconds"],
                "latencyMs": long_runs[fixture["id"]]["latencyMs"],
                "isolatedWords": len(expected),
                "changedWords": sum(
                    max(i2 - i1, j2 - j1)
                    for tag, i1, i2, j1, j2 in opcodes
                    if tag != "equal"
                ),
                "changes": changes,
            }
        )
    return report


def print_diff(report: list[dict[str, Any]]) -> None:
    for fixture in report:
        print(
            f"{fixture['id']}: {fixture['isolatedWords']} words, "
            f"{fixture['changedWords']} changed vs isolated, {fixture['latencyMs']:.0f} ms"
        )
        for change in fixture["changes"]:
            print(
                f"  {change['kind']:>10} [{change['expected']}] → [{change['heard']}]"
                f"  in {change['utterance']} {change['utteranceSpan']}  …{change['context']}…"
            )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)
    build_parser = commands.add_parser("build")
    build_parser.add_argument("stage", type=Path)
    build_parser.add_argument("recordings", type=Path)
    build_parser.add_argument("out", type=Path)
    diff_parser = commands.add_parser("diff")
    diff_parser.add_argument("fixtures", type=Path, help=f"{FIXTURES_FILE} from build")
    diff_parser.add_argument("results", type=Path, help="asr-replay output, fixtures")
    diff_parser.add_argument("isolated", type=Path, help="the same engine's stage 1")
    diff_parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if args.command == "build":
        print(build(args.stage, args.recordings, args.out))
        return 0
    report = diff(args.fixtures, args.results, args.isolated)
    print_diff(report)
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
