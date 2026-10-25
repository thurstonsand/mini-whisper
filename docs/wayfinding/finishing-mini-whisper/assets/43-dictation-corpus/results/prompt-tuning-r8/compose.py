#!/usr/bin/env python3
"""Splice section winners from `revise_section.py` into their shared base, in one prompt.

Each winner differs from the base in exactly one section, so its new text is recovered from where
the base's section starts, and composing is replacing every chosen section at once.

  ./compose.py --base candidates/base/gen7-747.txt --out candidates/compose/c1.txt \\
      candidates/s-spell-out/spell-out-2.txt candidates/s-typing-commands/typing-commands-2.txt
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def new_section(base: str, candidate: str, section: dict) -> tuple[str, str]:
    """The base text the winner replaces, and what replaces it."""
    old = section["text"] or section["after"]
    start = base.index(old)
    grown = len(candidate) - len(base)
    if section["text"]:
        return old, candidate[start : start + len(old) + grown]
    return old, old + candidate[start + len(old) : start + len(old) + grown]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--sections", type=Path, default=HERE / "sections.json")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("winners", type=Path, nargs="+")
    args = parser.parse_args()

    base = args.base.read_text(encoding="utf-8").strip()
    sections = json.loads(args.sections.read_text(encoding="utf-8"))
    edits = []
    for winner in args.winners:
        name = winner.stem.rsplit("-", 1)[0]
        candidate = winner.read_text(encoding="utf-8").strip()
        old, new = new_section(base, candidate, sections[name])
        assert base.replace(old, new) == candidate, winner
        edits.append((old, new))
    composed = base
    for old, new in edits:
        assert composed.count(old) == 1, old[:60]
        composed = composed.replace(old, new)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(composed + "\n", encoding="utf-8")
    print(f"{args.out}: {len(composed.split())} words")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
