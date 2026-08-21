#!/usr/bin/env python3
"""Per-shape breakdown of a perturbation run.

`perturb.py` reports one rate per rule, and two of the rules are several behaviours wearing one
name: `self-correction` mixes noise removal with clause deletion, `identifier-from-context` mixes
call sites with declarations and engine-mangled fragments. The grid already encodes which shape a
variant is — it is the index — so this reads the saved rows back and splits them.

  ./subrates.py perturbation/final.json perturbation/final2.json
"""

from __future__ import annotations

import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import perturb  # noqa: E402

SELF_CORRECTION = (
    "filler",
    "stutter",
    "word repair",
    "whole-clause backtrack",
    "double correction",
    "cross-rule backtrack",
)


def shape(row: dict) -> str | None:
    name = row["id"]
    if name.startswith("disfl-"):
        return SELF_CORRECTION[int(name.split("-")[1]) % 6]
    if name.startswith("ident-m"):
        return "engine-mangled token"
    if name.startswith("ident-"):
        index = int(name.split("-")[1])
        return "call site" if index % 2 == 0 else "declaration"
    return None


def main() -> int:
    # Judged fresh rather than read off the row: a run saved before the grid's sentence-case fix
    # carries the old verdict, and these tables are compared across that boundary.
    variants = {variant.id: variant for variant in perturb.grid(sorted(perturb.RULES))}
    reports = {}
    for path in map(Path, sys.argv[1:]):
        rows = json.loads(path.read_text(encoding="utf-8"))["rows"]
        counts: dict[str, list[int]] = {}
        for row in rows:
            name = shape(row)
            if name is None:
                continue
            tally = counts.setdefault(name, [0, 0])
            tally[0] += variants[row["id"]].obeyed(row["cleaned"])
            tally[1] += 1
        reports[path.stem] = counts

    names = list(dict.fromkeys(name for counts in reports.values() for name in counts))
    width = max(len(name) for name in names)
    print(f"{'shape':{width}}  " + "  ".join(f"{label:>12}" for label in reports))
    for name in names:
        cells = []
        for counts in reports.values():
            obeyed, total = counts.get(name, (0, 0))
            cells.append(f"{obeyed:>5}/{total:<6}" if total else " " * 12)
        print(f"{name:{width}}  " + "  ".join(cells))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
