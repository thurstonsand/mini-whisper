#!/usr/bin/env python3
"""The contraction half: delete one unit of the prompt, and see what it was worth.

Each unit is a sentence or a clause named in `units.json` by the exact text it removes. Removing
it produces a candidate; the candidate is scored on the frozen stage-3 objective and, because
stage 3 stages no DICTIONARY block, on the stage-2 dictionary run as well — a sentence about the
dictionary cannot show its worth on a stage that has no dictionary.

  ./ablate.py --prompt candidates/r2a.txt --units units.json --repeat 8 --out runs/ablation

Stage-2 output lands in `<out>/stage2-<unit>.jsonl` for `score_corpus.py sweep` to score.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import tune  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prompt", type=Path, required=True)
    parser.add_argument("--units", type=Path, required=True)
    parser.add_argument("--repeat", type=int, default=8)
    parser.add_argument("--workers", type=int, default=9)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument(
        "--stage2", action="store_true", help="Also run the dictionary gate."
    )
    parser.add_argument(
        "--provider", choices=sorted(tune.PROVIDERS), default="anthropic"
    )
    parser.add_argument("--model")
    args = parser.parse_args()

    prompt = args.prompt.read_text(encoding="utf-8").strip()
    units = json.loads(args.units.read_text(encoding="utf-8"))
    stage3 = tune.entries(tune.STAGE3, tune.STAGE3_RAW, keep_excluded=False)
    stage2 = tune.entries(tune.STAGE2, tune.STAGE2_RAW, keep_excluded=True)
    vocabulary: list[str] = []
    for entry in stage2:
        for term in entry.get("wants", []):
            if term not in vocabulary:
                vocabulary.append(term)
    args.out.mkdir(parents=True, exist_ok=True)

    with tune.transport(args.provider, args.model, args.workers) as complete:
        table = ablate(args, prompt, units, complete, stage3, stage2, vocabulary)
    (args.out / "ablation.json").write_text(
        json.dumps(table, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return 0


def ablate(
    args: argparse.Namespace,
    prompt: str,
    units: list[dict],
    complete: tune.Completion,
    stage3: list[dict],
    stage2: list[dict],
    vocabulary: list[str],
) -> list[dict]:
    table = []
    for unit in [{"name": "intact", "remove": "", "replace": ""}, *units]:
        candidate = prompt
        if unit["remove"]:
            if unit["remove"] not in prompt:
                sys.exit(f"unit {unit['name']}: text not found")
            candidate = prompt.replace(unit["remove"], unit.get("replace", "")).replace(
                "  ", " "
            )
        scores, misses = [], {}
        for _ in range(args.repeat):
            rows = tune.fan_out(stage3, candidate, complete, [], args.workers)
            for row in rows:
                if row["cleaned"] != row["expect"].strip():
                    misses[row["id"]] = misses.get(row["id"], 0) + 1
            scores.append(sum(row["cleaned"] == row["expect"].strip() for row in rows))
        mean = sum(scores) / len(scores)
        print(f"{unit['name']:24} {mean:5.2f}  {scores}  {misses}")
        table.append(
            {"unit": unit["name"], "mean": mean, "scores": scores, "failCounts": misses}
        )
        (args.out / f"{unit['name']}.txt").write_text(
            candidate + "\n", encoding="utf-8"
        )

        if args.stage2:
            rows = tune.fan_out(stage2, candidate, complete, vocabulary, args.workers)
            (args.out / f"stage2-{unit['name']}.jsonl").write_text(
                "".join(
                    json.dumps(
                        {
                            "id": row["id"],
                            "transcript": row["cleaned"],
                            "latencyMs": 0.0,
                        },
                        ensure_ascii=False,
                    )
                    + "\n"
                    for row in sorted(rows, key=lambda row: row["id"])
                ),
                encoding="utf-8",
            )
    return table


if __name__ == "__main__":
    raise SystemExit(main())
