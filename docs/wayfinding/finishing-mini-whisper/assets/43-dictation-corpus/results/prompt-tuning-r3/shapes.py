#!/usr/bin/env python3
"""The layout grid split by shape. `perturb.py` reports one rate for a rule, and this rule is
three behaviours in one name: leaving a paragraph alone, obeying a spoken break, and deleting a
hesitation. A wording that buys one by selling another reads as flat in the pooled number."""

import collections
import json
from pathlib import Path
import sys

for path in sys.argv[1:]:
    rows = json.loads(Path(path).read_text(encoding="utf-8"))["rows"]
    tally = collections.defaultdict(lambda: [0, 0, 0])
    for row in rows:
        if row["rule"] != "layout":
            continue
        shape = row["id"].split("-")[1]
        tally[shape][0] += 1
        tally[shape][1] += row["obeyed"]
        tally[shape][2] += row["match"]
    print(path)
    for shape in ("none", "asked", "hesitation"):
        n, obeyed, exact = tally[shape]
        if not n:
            continue
        print(
            f"  {shape:11} rule {obeyed:3d}/{n:3d} ({obeyed / n:5.1%})   exact {exact:3d}/{n:3d} ({exact / n:5.1%})"
        )
