#!/usr/bin/env python3
"""Does this prompt quote the material it is scored on?

Worked examples are allowed in the prompt; examples copied out of the corpus are not, because a
prompt that carries the answer key scores well and teaches nothing. The eval material is three
things: the training JSONLs, the recorded holdout JSONLs (quoting those poisons the judge), and
the vocabularies `perturb.py` builds its grid from.

The test is n consecutive words, normalized for case and punctuation — the same shape as
`propose.py --reject-leaks`, widened to every corpus and every template vocabulary. The prompt's
own frame is exempt: field names, the shipped rule text that predates this check, and the symbol
enumeration are not examples.

  ./leakcheck.py candidates/final2.txt
  ./leakcheck.py candidates/*.txt --window 3
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import perturb  # noqa: E402
import tune  # noqa: E402

CORPUS = tune.CORPUS
SOURCES = (
    "stage1-intelligibility.jsonl",
    "stage2-dictionary.jsonl",
    "stage3-polish.jsonl",
    "stage1-holdout.jsonl",
    "stage2-holdout.jsonl",
    "stage3-holdout.jsonl",
)
# A window of three ordinary function words is a coincidence of English, not a quotation.
STOPWORDS = frozenset(
    [
        "a",
        "an",
        "and",
        "are",
        "as",
        "at",
        "be",
        "but",
        "by",
        "do",
        "does",
        "for",
        "from",
        "he",
        "her",
        "his",
        "in",
        "is",
        "it",
        "its",
        "me",
        "my",
        "no",
        "not",
        "of",
        "on",
        "or",
        "she",
        "so",
        "that",
        "the",
        "them",
        "then",
        "they",
        "this",
        "to",
        "up",
        "us",
        "was",
        "we",
        "what",
        "when",
        "which",
        "who",
        "with",
        "you",
        "your",
        "it's",
        "i",
    ]
)
# The prompt's own furniture, not examples: field names it must say, and the enumeration of
# symbol names, which is the rule itself rather than a quotation of any entry.
EXEMPT = (
    "transcript",
    "dictionary",
    "focused_text_context",
    "target_bundle_id",
    "new line",
    "new paragraph",
    "full stop",
    "question mark",
    "exclamation point",
    "dash dash",
    "at sign",
    # A Harvard carrier says "use a pencil to write the first draft" and the spell-out rule says
    # "how to write the word". Three shared words of English, and no quotation of anything.
    "to write the",
)


def words(text: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", text.lower())


def shingles(text: str, window: int) -> set[tuple[str, ...]]:
    tokens = words(text)
    return {
        tuple(tokens[index : index + window])
        for index in range(len(tokens) - window + 1)
    }


def corpus_texts() -> dict[str, list[str]]:
    """Every string a scored entry is made of: what the speaker says, what the answer must be,
    and the context and vocabulary staged alongside them."""
    texts: dict[str, list[str]] = {}
    for name in SOURCES:
        collected = []
        for entry in (
            json.loads(line)
            for line in (CORPUS / name).read_text(encoding="utf-8").splitlines()
            if line.strip()
        ):
            for key in ("say", "expect", "transcript", "reference"):
                if isinstance(entry.get(key), str):
                    collected.append(entry[key])
            collected.extend(entry.get("wants") or [])
            collected.extend(entry.get("traps") or [])
            context = entry.get("context") or {}
            for value in context.values():
                if isinstance(value, str):
                    collected.append(value)
        texts[name] = collected
    texts["perturb.py templates"] = [
        variant.raw for variant in perturb.grid(sorted(perturb.RULES))
    ] + [variant.expect for variant in perturb.grid(sorted(perturb.RULES))]
    return texts


def leaks(prompt: str, window: int) -> list[tuple[str, str]]:
    exempt = {shingle for phrase in EXEMPT for shingle in shingles(phrase, window)}
    frame = STOPWORDS | {word for phrase in EXEMPT for word in words(phrase)}
    found = []
    mine = {
        shingle
        for shingle in shingles(prompt, window) - exempt
        if not set(shingle) <= frame
    }
    for name, texts in corpus_texts().items():
        theirs: set[tuple[str, ...]] = set()
        for text in texts:
            theirs |= shingles(text, window)
        for shingle in sorted(mine & theirs):
            found.append((name, " ".join(shingle)))
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prompt", type=Path, nargs="+")
    parser.add_argument("--window", type=int, default=3)
    args = parser.parse_args()

    status = 0
    for path in args.prompt:
        found = leaks(path.read_text(encoding="utf-8"), args.window)
        if not found:
            print(f"{path}: clean at {args.window} consecutive words")
            continue
        status = 1
        print(f"{path}: {len(found)} overlaps at {args.window} consecutive words")
        for source, shingle in found:
            print(f"  {source}: {shingle!r}")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
