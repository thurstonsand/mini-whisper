#!/usr/bin/env python3
"""Round 8's author: Sol rewrites one section of a prompt, and nothing else.

Round 7's `write_fresh.py --revise` hands Sol the whole prompt. Under a length cap that went
wrong in round 8's first generation: all three surviving rewrites cut the spell-out and
context-identifier bullets to make room, and those rules fell from 38% and 100% to 7% and 34%.
Here Sol sees the whole prompt for context but returns one section, which is spliced in place,
so every other sentence is the base's own. A section is named in `sections.json` by its exact
text; an empty `text` with an `after` anchor inserts a new section instead. Sol still sees only
`../prompt-tuning-r7/spec.txt`, the target-model description, and a written diagnosis, never a
corpus entry, and `propose.leaked` rejects a section that quotes the corpus.

  ./revise_section.py --prompt candidates/base/gen7-747.txt --section spell-out --out candidates/s-spell
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
SPEC = HERE.parent / "prompt-tuning-r7"
sys.path.insert(0, str(HERE.parent / "prompt-tuning-haiku"))

import propose  # noqa: E402

sys.path.insert(0, str(propose.tune.CORPUS))
import corpus_cleanup  # noqa: E402

ATTEMPTS = 3

REWRITE = """\
You are revising one section of a system prompt for a dictation cleanup model. The prompt was \
written from the specification below for the target model described below. The section has \
measured failures, described below. Rewrite only that section so the model behaves.

Hard constraints:
- Return the rewritten section and nothing else: no commentary, fences, labels, or other sections.
- Keep the section's job, and its format: a section that is a bullet starts with "- ".
- Use at most WORD_LIMIT words. Shorter is better if it works; every word is read as context for \
every other rule.
- Any example must be invented, from unusual made-up words, and short. Do not use first-person \
or object pronouns in examples, and do not write a spoken command directly followed by another \
command or by a number word.
"""

INSERT = """\
You are adding one section to a system prompt for a dictation cleanup model. The prompt was \
written from the specification below for the target model described below. It has measured \
failures, described below, that no current section addresses. Write the new section.

Hard constraints:
- Return the new section and nothing else: no commentary, fences, labels, or other sections.
- Use at most WORD_LIMIT words. Shorter is better if it works; every word is read as context for \
every other rule.
- Any example must be invented, from unusual made-up words, and short. Do not use first-person \
or object pronouns in examples, and do not write a spoken command directly followed by another \
command or by a number word.
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prompt", type=Path, required=True)
    parser.add_argument("--section", required=True, help="A name in sections.json.")
    parser.add_argument("--sections", type=Path, default=HERE / "sections.json")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--candidates", type=int, default=4)
    args = parser.parse_args()

    base = args.prompt.read_text(encoding="utf-8").strip()
    section = json.loads(args.sections.read_text(encoding="utf-8"))[args.section]
    spec = (SPEC / "spec.txt").read_text(encoding="utf-8").strip()
    model = (SPEC / "diagnosis.txt").read_text(encoding="utf-8").strip()
    if section["text"] and section["text"] not in base:
        sys.exit(f"section {args.section}: text not found in {args.prompt}")
    if not section["text"] and section["after"] not in base:
        sys.exit(f"section {args.section}: anchor not found in {args.prompt}")
    system = (REWRITE if section["text"] else INSERT).replace(
        "WORD_LIMIT", str(section["words"])
    )
    target = (
        f"SECTION TO REWRITE\n{section['text']}"
        if section["text"]
        else "THE NEW SECTION GOES AFTER THIS TEXT\n" + section["after"]
    )
    user = (
        f"SPECIFICATION\n{spec}\n\n{model}\n\nCURRENT PROMPT\n{base}\n\n{target}\n\n"
        f"MEASURED FAILURES\n{section['failures']}\n\nReturn only the section."
    )

    args.out.mkdir(parents=True, exist_ok=True)
    with (
        propose.codex_transport(None, args.candidates * ATTEMPTS) as complete,
        ThreadPoolExecutor(max_workers=args.candidates) as pool,
    ):

        def write(index: int) -> str:
            name = f"{args.section}-{index}"
            for attempt in range(1, ATTEMPTS + 1):
                text = corpus_cleanup.shape(complete(system, user)[0])
                if section["text"]:
                    candidate = base.replace(section["text"], text)
                else:
                    candidate = base.replace(
                        section["after"], section["after"] + "\n\n" + text
                    )
                quotes = propose.leaked(candidate, base)
                if not quotes:
                    (args.out / f"{name}.txt").write_text(
                        candidate + "\n", encoding="utf-8"
                    )
                    return (
                        f"{name}: section {len(text.split())} words, prompt "
                        f"{len(candidate.split())}, kept on attempt {attempt}"
                    )
                named = ", ".join(f"{where}: {what!r}" for where, what in quotes[:3])
            return f"{name}: rejected {ATTEMPTS} times, last for {named}"

        for line in pool.map(write, range(1, args.candidates + 1)):
            print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
