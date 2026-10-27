#!/usr/bin/env python3
"""One table across round 9's arms."""

import json
from pathlib import Path
import sys

arms = [json.loads(Path(p).read_text()) for p in sys.argv[1:]]


def rate(rows, key):
    return sum(r[key] for r in rows) / len(rows) if rows else float("nan")


def line(name, cells):
    print(f"| {name} | " + " | ".join(cells) + " |")


line("guard", [a["label"] for a in arms])
line("---", ["---:" for _ in arms])
for stage in ("frozen", "holdout"):
    for key in ("exact", "normalizedMatch"):
        line(
            f"{stage} {key}",
            [
                f"{rate([r for r in a['rows'] if r['stage'] == stage], key):.1%}"
                for a in arms
            ],
        )
rules = sorted({r["rule"] for r in arms[0]["rows"] if r["rule"]})
for rule in rules:
    line(
        f"grid {rule}",
        [
            "{:.0%} ({:.0%})".format(
                rate([r for r in a["rows"] if r["rule"] == rule], "obeyed"),
                rate([r for r in a["rows"] if r["rule"] == rule], "obeyedFolded"),
            )
            for a in arms
        ],
    )
for key in ("lowercaseStart", "noFinalPeriod", "endsHappy"):
    line(f"all rows {key}", [f"{rate(a['rows'], key):.1%}" for a in arms])
line(
    "draft leaks",
    [f"{sum(r['leak'] for r in a['rows'])}/{len(a['rows'])}" for a in arms],
)
line("empty / refused", [f"{a['empty']}/{a['calls']}" for a in arms])
