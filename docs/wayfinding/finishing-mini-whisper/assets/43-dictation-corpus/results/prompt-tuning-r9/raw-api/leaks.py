#!/usr/bin/env python3
"""Round 9's draft-leak heuristic over tune.py stage3 and perturb.py JSON: output longer than
1.5x the expect plus 20 characters. Prints counts and the leaking rows' ids."""

import collections
import json
from pathlib import Path
import sys

for path in map(Path, sys.argv[1:]):
    report = json.loads(path.read_text(encoding="utf-8"))
    rows = report.get("rows") or [row for run in report["repeats"] for row in run]
    leaks = [
        r
        for r in rows
        if r["cleaned"].strip() and len(r["cleaned"]) > 1.5 * len(r["expect"]) + 20
    ]
    ids = collections.Counter(r["id"] for r in leaks)
    print(
        f"{path}: {len(leaks)}/{len(rows)}  "
        + ", ".join(f"{k} {v}" for k, v in sorted(ids.items()))
    )
