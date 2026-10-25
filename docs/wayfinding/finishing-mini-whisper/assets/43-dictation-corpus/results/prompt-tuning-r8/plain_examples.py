#!/usr/bin/env python3
"""Round 8's refusal fix: Sol rewrites a prompt's worked examples in everyday words, and nothing else.

On the raw Anthropic API, `claude-haiku-5-5`'s safety classifier blocks some harmless dictations
outright, `stop_reason: refusal`, "content related to the development of high-yield explosives",
when the from-scratch lineage's prompt is the system prompt; `final-r6` never trips it. The
trigger is the prompt as a whole, not one sentence: dropping almost any one example clears it. The
lineage's examples are built from invented nouns ("tunes the nyxcoil", "seals the vault") beside
rules that replace one thing with another, which reads like a codeword-substitution jailbreak.
Here Sol rewrites each `“…” becomes “…”` example in ordinary words, keeping its surface pattern,
and every rule sentence stays verbatim. `propose.leaked` still rejects any example that quotes the
corpus.

  ./plain_examples.py --prompt candidates/confirm3/r8-sc2.txt --out candidates/s-plain
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "prompt-tuning-haiku"))

import propose  # noqa: E402

sys.path.insert(0, str(propose.tune.CORPUS))
import corpus_cleanup  # noqa: E402

ATTEMPTS = 3
EXAMPLE = re.compile(r"“[^”]*” becomes “[^”]*”")

SYSTEM = """\
You are editing the worked examples in a system prompt for a dictation cleanup model. A safety \
classifier blocks requests under this prompt because its examples are built from invented, \
exotic-sounding nouns, which read like coded substitutions. Rewrite every example in plain, \
everyday words: ordinary household, office, or errand vocabulary and common first names.

Hard constraints:
- You receive the examples numbered, one per line. Return exactly the same number of lines, \
numbered the same way, each one rewritten example and nothing else.
- Keep each example's form: “spoken input” becomes “cleaned output”, with the same curly quotes.
- Keep each example's surface pattern exactly: the same spoken commands, symbols, fillers, \
correction cues, spelled letters, and line breaks, in the same order, and the same kind of token \
in each position (an identifier stays an identifier, an email address stays an email address, a \
misspelled name stays a misspelled name corrected by the same letters).
- Keep every example harmless and dull. No weapons, chemicals, security, locks, vaults, or \
anything dangerous.
- Use the reserved domain .invalid for any email address.
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prompt", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--candidates", type=int, default=4)
    args = parser.parse_args()

    base = args.prompt.read_text(encoding="utf-8").strip()
    examples = EXAMPLE.findall(base)
    numbered = "\n".join(
        f"{index}. {example.replace(chr(10), '⏎')}"
        for index, example in enumerate(examples, 1)
    )
    user = (
        f"THE PROMPT, FOR CONTEXT\n{base}\n\nTHE EXAMPLES TO REWRITE, ONE PER LINE, LINE "
        f"BREAKS INSIDE AN EXAMPLE WRITTEN AS ⏎\n{numbered}\n\nReturn only the numbered lines."
    )

    args.out.mkdir(parents=True, exist_ok=True)
    with (
        propose.codex_transport(None, args.candidates * ATTEMPTS) as complete,
        ThreadPoolExecutor(max_workers=args.candidates) as pool,
    ):

        def write(index: int) -> str:
            name = f"plain-{index}"
            problem = ""
            for attempt in range(1, ATTEMPTS + 1):
                reply = corpus_cleanup.shape(complete(SYSTEM, user)[0])
                lines = [
                    re.sub(r"^\d+\.\s*", "", line).replace("⏎", "\n")
                    for line in reply.splitlines()
                    if line.strip()
                ]
                if len(lines) != len(examples) or not all(
                    EXAMPLE.fullmatch(line) for line in lines
                ):
                    problem = (
                        f"returned {len(lines)} lines, not {len(examples)} examples"
                    )
                    continue
                candidate = base
                for old, new in zip(examples, lines, strict=True):
                    candidate = candidate.replace(old, new, 1)
                quotes = propose.leaked(candidate, base)
                if not quotes:
                    (args.out / f"{name}.txt").write_text(
                        candidate + "\n", encoding="utf-8"
                    )
                    return f"{name}: {len(candidate.split())} words, kept on attempt {attempt}"
                problem = ", ".join(f"{where}: {what!r}" for where, what in quotes[:3])
            return f"{name}: rejected {ATTEMPTS} times, last for {problem}"

        for line in pool.map(write, range(1, args.candidates + 1)):
            print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
