#!/usr/bin/env python3
"""Round 8's refusal guard: empty outputs per arm, by entry.

On the raw Anthropic API a safety-classifier refusal comes back as `finish_reason:
content_filter` with no content, which the harness records as an empty cleaned text and the app
treats as a degenerate response and falls back to the raw transcript. Every empty output this
round was such a refusal. Reads `tune.py stage3` and `perturb.py` JSON alike.

  ./refusals.py runs/confirm/*.json runs/confirm/grid/*.json
"""

from __future__ import annotations

import collections
import json
from pathlib import Path
import sys


def main() -> int:
    for path in map(Path, sys.argv[1:]):
        report = json.loads(path.read_text(encoding="utf-8"))
        rows = report.get("rows") or [row for run in report["repeats"] for row in run]
        empty = collections.Counter(
            row["id"] for row in rows if not row["cleaned"].strip()
        )
        named = ", ".join(f"{entry} {count}" for entry, count in sorted(empty.items()))
        print(
            f"{path}: {sum(empty.values())}/{len(rows)} refused{'  ' + named if named else ''}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
