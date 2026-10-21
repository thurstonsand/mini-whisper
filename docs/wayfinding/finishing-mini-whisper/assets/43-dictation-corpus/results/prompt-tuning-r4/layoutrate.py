#!/usr/bin/env python3
"""`breakrate.py`, split by what the entry is asking for.

Round 3's arm was sixteen entries that all wanted the same thing — leave it alone — so one pooled
break rate said everything. The arm now contains four entries that want a break nobody spoke and
two long controls that must not get one, and an absolute rule and a narrow rule are told apart by
exactly that difference. Pooling them hides it: a prompt that never breaks scores 18/22 intact and
looks excellent.

The tags do the grouping, so an entry declares its own question:

  no-break        expect is one paragraph; any break is the field defect
  unspoken-break  expect has a break the speaker never asked for; not producing it is the failure
  requested-break expect has a break the speaker did ask for; the exception that must survive

  ./layoutrate.py ../prompt-tuning-r4/runs/layout-*.json
"""

from __future__ import annotations

import argparse
import collections
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "prompt-tuning-r3"))

import breakrate  # noqa: E402

SHAPES = ("no-break", "unspoken-break", "requested-break")
CALLS = ("intact", "spurious", "missing", "reshaped")


def shape(tags: list[str]) -> str:
    for name in SHAPES:
        if name in tags:
            return name
    return "other"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runs", type=Path, nargs="+")
    parser.add_argument("--per-entry", action="store_true")
    args = parser.parse_args()

    for path in args.runs:
        run = json.loads(path.read_text(encoding="utf-8"))
        tally: dict[str, collections.Counter] = collections.defaultdict(
            collections.Counter
        )
        entries: dict[str, collections.Counter] = collections.defaultdict(
            collections.Counter
        )
        for rows in run["repeats"]:
            for row in rows:
                call = breakrate.verdict(row["expect"], row["cleaned"])
                tally[shape(row["tags"])][call] += 1
                entries[row["id"]][call] += 1
        print(f"{run['label']}  {run['model']}  n={len(run['repeats'])}")
        for name in (*SHAPES, "other"):
            counts = tally.get(name)
            if not counts:
                continue
            total = sum(counts.values())
            detail = "  ".join(
                f"{call} {counts[call]}/{total} ({counts[call] / total:.0%})"
                for call in CALLS
            )
            print(f"  {name:16} {detail}")
        if args.per_entry:
            for entry_id, counts in sorted(entries.items()):
                if set(counts) == {"intact"}:
                    continue
                print(
                    f"    {entry_id:12} "
                    + " ".join(
                        f"{call}={counts[call]}" for call in CALLS if counts[call]
                    )
                )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
