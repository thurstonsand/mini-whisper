#!/usr/bin/env python3
"""What did the prompt do to the line breaks, and nothing else?

Exact match is the objective, but it cannot answer the question this round exists for. A layout
entry fails identically whether cleanup split it across four lines or merely declined to write
`6x` for "six times", and the second is not a layout defect at all. So this reads a `tune.py` run
file and re-judges every repeat on whitespace alone:

  spurious   the entry's `expect` is one paragraph and the output is not — the field defect
  missing    `expect` asks for a break the output did not produce
  reshaped   both have breaks, in different places or different counts
  intact     the break structure matches, whatever the words did

The denominator is entries × repeats, so two prompts are comparable at different n.

  ./breakrate.py runs/baseline-layout.json runs/*-cerebras.json
"""  # noqa: RUF002

from __future__ import annotations

import argparse
import json
from pathlib import Path


def structure(text: str) -> list[int]:
    """The break skeleton: the run-length of every newline group, in order. Two outputs share a
    skeleton when they break in the same places by the same amount, whatever the words are."""
    runs = []
    count = 0
    for character in text.strip():
        if character == "\n":
            count += 1
        elif count:
            runs.append(count)
            count = 0
    if count:
        runs.append(count)
    return runs


def verdict(expect: str, cleaned: str) -> str:
    wanted, got = structure(expect), structure(cleaned)
    if wanted == got:
        return "intact"
    if not wanted:
        return "spurious"
    if not got:
        return "missing"
    return "reshaped"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runs", type=Path, nargs="+")
    parser.add_argument("--per-entry", action="store_true")
    args = parser.parse_args()

    for path in args.runs:
        run = json.loads(path.read_text(encoding="utf-8"))
        counts: dict[str, int] = {}
        entries: dict[str, dict[str, int]] = {}
        for rows in run["repeats"]:
            for row in rows:
                call = verdict(row["expect"], row["cleaned"])
                counts[call] = counts.get(call, 0) + 1
                entries.setdefault(row["id"], {})
                entries[row["id"]][call] = entries[row["id"]].get(call, 0) + 1
        total = sum(counts.values())
        summary = "  ".join(
            f"{name} {counts.get(name, 0)}/{total} ({counts.get(name, 0) / total:.0%})"
            for name in ("intact", "spurious", "missing", "reshaped")
        )
        print(f"{run['label']}  {run['model']}  n={len(run['repeats'])}\n  {summary}")
        if args.per_entry:
            for entry_id, calls in sorted(entries.items()):
                if set(calls) == {"intact"}:
                    continue
                detail = " ".join(
                    f"{name}={value}" for name, value in sorted(calls.items())
                )
                print(f"    {entry_id:12} {detail}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
