#!/usr/bin/env python3
"""Write leave-one-out candidates: the prompt minus each unit named in a units file.

`../prompt-tuning-haiku/ablate.py` scores its cuts in-process and keeps only exact counts; these
files go through `tune.py stage3 --output` instead, so `judge.py` can score every cut too.

  ./cut.py --prompt candidates/final-r6.txt --units units-r6.json --out candidates/cut-r6
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prompt", type=Path, required=True)
    parser.add_argument("--units", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument(
        "--keep",
        nargs="*",
        default=[],
        help="Also write one candidate with every unit removed except these.",
    )
    args = parser.parse_args()

    prompt = args.prompt.read_text(encoding="utf-8").strip()
    units = json.loads(args.units.read_text(encoding="utf-8"))
    args.out.mkdir(parents=True, exist_ok=True)
    for unit in units:
        if unit["remove"] not in prompt:
            sys.exit(f"unit {unit['name']}: text not found")
        cut = prompt.replace(unit["remove"], "").strip()
        (args.out / f"minus-{unit['name']}.txt").write_text(
            cut + "\n", encoding="utf-8"
        )
        print(f"minus-{unit['name']}: {len(cut.split())} words")
    if args.keep:
        cut = prompt
        for unit in units:
            if unit["name"] not in args.keep:
                cut = cut.replace(unit["remove"], "")
        cut = cut.strip()
        name = f"keep-{len(args.keep)}"
        (args.out / f"{name}.txt").write_text(cut + "\n", encoding="utf-8")
        print(f"{name}: {len(cut.split())} words")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
