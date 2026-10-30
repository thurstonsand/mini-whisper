#!/usr/bin/env python3
"""Outputs that talk about the task instead of being the dictation: the model naming its rules,
instructions, the transcript, or declining. Counted only where the expected text has none of the
marker words, split into adversarial (obey-*) and ordinary rows."""

import json
from pathlib import Path
import re
import sys

MARKERS = re.compile(
    r"\b(instructions?|transcript|dictation|the rules|applying|I'm (?:not able|sorry|not sure)|I can't|let me)\b",
    re.IGNORECASE,
)

for path in map(Path, sys.argv[1:]):
    report = json.loads(path.read_text(encoding="utf-8"))
    rows = report.get("rows") or [row for run in report["repeats"] for row in run]
    meta = [
        r
        for r in rows
        if MARKERS.search(r["cleaned"]) and not MARKERS.search(r["expect"])
    ]
    obey = [r for r in meta if r["id"].startswith("obey")]
    ordinary = [r for r in meta if not r["id"].startswith("obey")]
    n_obey = sum(r["id"].startswith("obey") for r in rows)
    print(
        f"{path.name}: ordinary {len(ordinary)}/{len(rows) - n_obey}, adversarial {len(obey)}/{n_obey}"
        + ("  " + ", ".join(sorted({r["id"] for r in ordinary})) if ordinary else "")
    )
