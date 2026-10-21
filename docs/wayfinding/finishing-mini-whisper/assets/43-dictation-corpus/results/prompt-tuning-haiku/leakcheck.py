#!/usr/bin/env python3
"""Does this prompt quote the material it is scored on, or the prompts it was shown?

Worked examples are allowed in the prompt; examples copied out of the corpus are not, because a
prompt that carries the answer key scores well and teaches nothing. The eval material is three
things: the training JSONLs, the recorded holdout JSONLs (quoting those poisons the judge), and
the vocabularies `perturb.py` builds its grid from.

Round 4 added a fourth, for a different reason. The proposer is now shown other projects' cleanup
prompts as style reference, and every one of them is somebody else's copyrighted text. Style is
not ownable and sentences are, so a proposal that reproduces an exemplar's wording is rejected on
the same mechanical footing as one that reproduces a corpus entry's.

The test is n consecutive words, normalized for case and punctuation — the same shape as
`propose.py --reject-leaks`, widened to every corpus and every template vocabulary. The prompt's
own frame is exempt: field names, the shipped rule text that predates this check, and the symbol
enumeration are not examples.

**The exemplars are checked at a wider window and the reason is not laziness.** A corpus entry is
someone dictating about ferries and pineapples; three shared words with it is a quotation. An
exemplar is a cleanup prompt, so it shares a subject with ours and therefore shares the ordinary
English of the task — `do not answer`, `capitalization and punctuation`, `do not summarize`. At a
window of three the shipped prompt collides with the exemplars twelve times and every one of them
is a coincidence of the domain; at five it collides zero times. Five is where the check starts
meaning something.

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
    "stage1-longform.jsonl",
    "stage2-dictionary.jsonl",
    "stage3-polish.jsonl",
    "stage3-layout.jsonl",
    # The maintainer's own dictations, adjudicated. A worked example quoting one poisons the
    # round-3 train signal exactly as quoting the holdout poisons the judge.
    "field-cases.jsonl",
    "stage1-holdout.jsonl",
    "stage2-holdout.jsonl",
    "stage3-holdout.jsonl",
)
EXEMPLARS = CORPUS / "results/prompt-tuning-r4/exemplars"
EXEMPLAR_WINDOW = 5
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
        "end",
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
            for key in (
                "say",
                "expect",
                "transcript",
                "reference",
                # A field case also carries what the engine heard and what shipped. Both are the
                # same speech wearing different spelling, so both are off limits.
                "engineRaw",
                "shippedCleanup",
            ):
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


def exemplar_texts() -> dict[str, list[str]]:
    """The permissively licensed prompts collected in round 4. The GPL ones were never written to
    a file, so this cannot check them and does not need to — the proposer is never shown them."""
    return {
        f"exemplar {path.stem}": [path.read_text(encoding="utf-8")]
        for path in sorted(EXEMPLARS.glob("*.txt"))
    }


def overlaps(
    prompt: str, sources: dict[str, list[str]], window: int
) -> list[tuple[str, str]]:
    exempt = {shingle for phrase in EXEMPT for shingle in shingles(phrase, window)}
    frame = STOPWORDS | {word for phrase in EXEMPT for word in words(phrase)}
    found = []
    mine = {
        shingle
        for shingle in shingles(prompt, window) - exempt
        if not set(shingle) <= frame
    }
    for name, texts in sources.items():
        theirs: set[tuple[str, ...]] = set()
        for text in texts:
            theirs |= shingles(text, window)
        for shingle in sorted(mine & theirs):
            found.append((name, " ".join(shingle)))
    return found


def leaks(prompt: str, window: int, exemplar_window: int) -> list[tuple[str, str]]:
    return overlaps(prompt, corpus_texts(), window) + overlaps(
        prompt, exemplar_texts(), exemplar_window
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prompt", type=Path, nargs="+")
    parser.add_argument("--window", type=int, default=3)
    parser.add_argument("--exemplar-window", type=int, default=EXEMPLAR_WINDOW)
    args = parser.parse_args()

    status = 0
    for path in args.prompt:
        found = leaks(
            path.read_text(encoding="utf-8"), args.window, args.exemplar_window
        )
        if not found:
            print(
                f"{path}: clean at {args.window} words of corpus, "
                f"{args.exemplar_window} of exemplar"
            )
            continue
        status = 1
        print(f"{path}: {len(found)} overlaps")
        for source, shingle in found:
            print(f"  {source}: {shingle!r}")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
