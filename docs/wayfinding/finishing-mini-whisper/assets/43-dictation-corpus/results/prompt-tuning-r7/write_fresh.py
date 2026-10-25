#!/usr/bin/env python3
"""Round 7's author: Sol writes cleanup prompts from the specification, not from any prompt.

Generation 1 sees `spec.txt` and `diagnosis.txt` and nothing else: no shipped prompt, no
earlier candidate, no corpus entry. Each of its candidates is given a different shape to write
in, because six samples of one instruction converge. Later generations revise one winner from
a written diagnosis of that winner's own failures, the round-6 method, but on this lineage.
`propose.leaked` rejects any proposal quoting three corpus words or five exemplar words; Haiku
only scores.

  ./write_fresh.py --out candidates/gen1
  ./write_fresh.py --revise candidates/gen1/f3.txt --diagnosis diagnosis-gen2.txt --out candidates/gen2
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "prompt-tuning-haiku"))

import propose  # noqa: E402

sys.path.insert(0, str(propose.tune.CORPUS))
import corpus_cleanup  # noqa: E402

ATTEMPTS = 3

WRITE = """\
You write system prompts for small language models. Write the system prompt for the dictation \
cleanup model specified below, for the target model described below.

Hard constraints:
- Return the complete system prompt and nothing else. No commentary, fences, or labels.
- Every required behaviour must be covered. The specification is not to be copied: write \
instructions addressed to the model, in your own words.
- Any worked example must be invented and short. Do not reuse the specification's own phrases \
as examples beyond the symbol names it lists.
- The prompt is sent on every dictation, so every word must earn its place.
"""

SHAPES = {
    "f1": "Shape: a short numbered list of imperative rules, one line each where possible. "
    "Aim for about 250 words.",
    "f2": "Shape: a few compact prose paragraphs grouped by concern. Aim for about 350 words.",
    "f3": "Shape: rules, each followed by one short invented example of input and output. "
    "Aim for about 450 words.",
    "f4": "Shape: as short as you can make it while keeping every behaviour. Aim for 150 words.",
    "f5": "Shape: headed sections (role, fields, edits, commands, output) with terse bullets. "
    "Aim for about 400 words.",
    "f6": "Shape: open with the single most important instruction, then the rest in order of "
    "how often a small model gets them wrong. Aim for about 300 words.",
}

REVISE = """\
You are revising a system prompt for a dictation cleanup model. It was written from the \
specification below for the target model described below, and it now has measured failures, \
described below. Revise it so the model behaves.

Hard constraints:
- Return the complete revised prompt and nothing else. No commentary, fences, or labels.
- Keep every behaviour the specification requires. Change the fewest sentences that fix the \
failures; added length is a cost, and every sentence you add is also read as context for every \
other rule.
- Do not name specific words, phrases, names or sentences from the failure descriptions as \
examples. An invented example is allowed when a rule cannot work without one.
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument(
        "--revise", type=Path, help="Revise this candidate instead of writing."
    )
    parser.add_argument(
        "--diagnosis", type=Path, help="Its failures; required with --revise."
    )
    parser.add_argument("--candidates", type=int, default=6)
    args = parser.parse_args()

    spec = (HERE / "spec.txt").read_text(encoding="utf-8").strip()
    model = (HERE / "diagnosis.txt").read_text(encoding="utf-8").strip()
    if args.revise:
        if not args.diagnosis:
            parser.error("--revise needs --diagnosis")
        base = args.revise.read_text(encoding="utf-8").strip()
        failures = args.diagnosis.read_text(encoding="utf-8").strip()
        jobs = {
            f"r{index}": (
                REVISE,
                f"SPECIFICATION\n{spec}\n\n{model}\n\nCURRENT PROMPT\n{base}\n\n"
                f"MEASURED FAILURES\n{failures}\n\nReturn the complete revised prompt.",
            )
            for index in range(1, args.candidates + 1)
        }
    else:
        jobs = {
            name: (WRITE, f"SPECIFICATION\n{spec}\n\n{model}\n\n{shape}")
            for name, shape in list(SHAPES.items())[: args.candidates]
        }

    args.out.mkdir(parents=True, exist_ok=True)
    with (
        propose.codex_transport(None, len(jobs) * ATTEMPTS) as complete,
        ThreadPoolExecutor(max_workers=len(jobs)) as pool,
    ):

        def write(item: tuple[str, tuple[str, str]]) -> str:
            # A leak is resampled rather than repaired: editing Sol's text by hand would make
            # the candidate ours, and three-word collisions with the corpus are mostly chance.
            name, job = item
            for attempt in range(1, ATTEMPTS + 1):
                text = corpus_cleanup.shape(complete(*job)[0])
                quotes = propose.leaked(text, "")
                if not quotes:
                    (args.out / f"{name}.txt").write_text(text + "\n", encoding="utf-8")
                    return (
                        f"{name}: {len(text.split())} words, kept on attempt {attempt}"
                    )
                named = ", ".join(f"{where}: {what!r}" for where, what in quotes[:3])
            return f"{name}: rejected {ATTEMPTS} times, last for {named}"

        for line in pool.map(write, jobs.items()):
            print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
