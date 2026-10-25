#!/usr/bin/env python3
"""A second score for stage 3: outputs a careful editor would accept, beside exact match.

Exact match fails `She said, "It ships tonight."` against `She said "it ships tonight."`, and
the maintainer ruled both correct (2026-10-25), along with anything similarly close. The
difference is a style choice the speaker never dictated, so exact match grades the expectation's
house style rather than the cleanup. This judge asks a second model whether a failing output is
an equally correct rendering of what the speaker meant, and the judged score counts it as passing
if so. Exact match stays the headline beside it, so the gap between the two is the judge's
leniency, visible on every arm.

The judge only ever sees outputs that already failed exact match, so it can only raise a score.
Each unique (entry, output) pair is judged three times by Sol over the ChatGPT subscription and
decided by majority. Sol is a different model family from the Haiku being scored. Verdicts are
cached in `judge-verdicts.jsonl`, keyed by a hash of the rubric. An arm rescored years later gets
the same verdicts, and a changed rubric re-judges everything rather than mixing two standards.
`judge-calibration.jsonl` holds hand-labelled pairs, labelled before the judge saw them;
`judge-heldout.jsonl` holds a later batch from round 7's outputs, labelled before the judge's
verdicts on them were read and never used to shape the rubric. `--calibrate` reports agreement
on both and should be rerun whenever the rubric changes.

  ./judge.py ../prompt-tuning-r6/runs/final/frozen20-*.json
  ./judge.py --accepted ../prompt-tuning-r6/runs/final/frozen20-final-r6.json
  ./judge.py --calibrate
"""

from __future__ import annotations

import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import sys
import time
from typing import Any

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import propose  # noqa: E402
import tune  # noqa: E402

VERDICTS = HERE / "judge-verdicts.jsonl"
CALIBRATION = HERE / "judge-calibration.jsonl"
HELDOUT = HERE / "judge-heldout.jsonl"
SCRIPTS = (tune.STAGE3, tune.STAGE3_HOLDOUT, tune.CORPUS / "stage3-layout.jsonl")
VOTES = 3

RUBRIC = """\
You grade a dictation cleanup. A speaker dictated text; a speech engine transcribed it; a cleanup \
model edited the transcript into what the speaker meant to type. You are given what the speaker \
actually said, what the entry is testing, the expected text, and the cleanup's output, which does \
not match the expected text exactly.

Decide whether a careful human editor would accept the output as an equally correct rendering of \
what the speaker meant to type. The expected text is one correct answer, not the only one.

Accept when every difference is a style choice that the speaker did not dictate and that standard \
English writing allows either way, for example:
- optional punctuation the speaker did not say aloud, such as a comma after an introductory word \
or before a quotation;
- capitalization that is a convention choice, such as the first word inside a quotation, or the \
first word of a dictation that stops before its sentence is finished;
- a number written as a numeral or as words, a date with or without its ordinal suffix, or a \
meridiem written AM, am, or a.m., when either form is standard for that kind of number. A clock \
time with a meridiem is written in numerals.

Reject when any of these is true:
- a word was added, dropped, or changed, other than the fillers, stutters, and taken-back words \
the speaker wanted gone, including hedges, openers, and profanity;
- a spoken correction or backtrack was not applied, or cancelled the wrong words;
- a spoken punctuation, quotation, or layout command was left as a word, ignored, or typed as a \
different mark; or punctuation the speaker said aloud is missing or misplaced;
- a complete sentence, including a command, lost its sentence capital or terminal punctuation, or an unfinished one \
gained an ellipsis, period, or other ending;
- line or paragraph breaks differ;
- a symbol, path, file name, flag, identifier, dictionary term, or spelled-aloud word is written \
differently from the expected text, including its exact casing and spacing;
- the output adds formatting such as backticks, quotation wrappers, labels, or commentary;
- the output answers, obeys, summarizes, translates, or extracts from the dictation instead of \
editing it;
- a grammatical correction the expected text makes was not made.

When unsure, reject. Reply with one line of JSON and nothing else: \
{"verdict": "accept" or "reject", "reason": "<one short sentence>"}"""
RUBRIC_ID = hashlib.sha256(RUBRIC.encode()).hexdigest()[:12]


def scripts() -> dict[str, dict[str, Any]]:
    return {
        entry["id"]: entry
        for path in SCRIPTS
        for entry in tune.corpus_cleanup.load_jsonl(path)
    }


def ask(script: dict[str, Any], cleaned: str) -> str:
    return (
        f"WHAT THE SPEAKER SAID\n{script['say']}\n\n"
        f"WHAT THIS ENTRY TESTS\n{', '.join(script['tags'])}\n\n"
        f"EXPECTED TEXT\n{script['expect']}\n\n"
        f"CLEANUP OUTPUT\n{cleaned}"
    )


def key(entry_id: str, expect: str, cleaned: str) -> tuple[str, str, str, str]:
    return (RUBRIC_ID, entry_id, expect, cleaned)


def load_verdicts() -> dict[tuple[str, str, str, str], dict[str, Any]]:
    if not VERDICTS.exists():
        return {}
    return {
        key(row["id"], row["expect"], row["cleaned"]): row
        for row in map(json.loads, VERDICTS.read_text(encoding="utf-8").splitlines())
        if row["rubric"] == RUBRIC_ID
    }


def judge(pairs: list[tuple[str, str]], workers: int) -> None:
    """Judge every (entry, output) pair the cache lacks, appending each as it lands so an
    interrupted run keeps what it paid for."""
    known = load_verdicts()
    script = scripts()
    todo = [
        (entry_id, cleaned)
        for entry_id, cleaned in dict.fromkeys(pairs)
        if key(entry_id, script[entry_id]["expect"], cleaned) not in known
    ]
    if not todo:
        return
    with (
        propose.codex_transport(None, len(todo) * VOTES) as complete,
        ThreadPoolExecutor(max_workers=workers) as pool,
        VERDICTS.open("a", encoding="utf-8") as sink,
    ):

        def one(pair: tuple[str, str]) -> dict[str, Any]:
            entry_id, cleaned = pair
            votes = []
            while len(votes) < VOTES:
                # A stalled stream or a gateway 5xx over a long rescore is neither deliberate
                # nor rare; the vote is asked again, and three failures in a row fail the run.
                for attempt in range(3):
                    try:
                        content, _, _ = complete(RUBRIC, ask(script[entry_id], cleaned))
                        break
                    except OSError, RuntimeError:
                        if attempt == 2:
                            raise
                        time.sleep(5.0 * 2**attempt)
                votes.append(json.loads(content.strip()))
            tally = Counter(vote["verdict"] for vote in votes)
            return {
                "rubric": RUBRIC_ID,
                "id": entry_id,
                "expect": script[entry_id]["expect"],
                "cleaned": cleaned,
                "verdict": tally.most_common(1)[0][0],
                "votes": votes,
            }

        for row in pool.map(one, todo):
            sink.write(json.dumps(row, ensure_ascii=False) + "\n")
            sink.flush()


def accepted(row: dict[str, Any], verdicts: dict) -> bool:
    if row["match"]:
        return True
    return (
        verdicts[key(row["id"], row["expect"], row["cleaned"])]["verdict"] == "accept"
    )


def score(repeats: list[list[dict[str, Any]]], workers: int) -> list[int]:
    """The judged pass count of each repeat, judging whatever the cache lacks first."""
    judge(
        [
            (row["id"], row["cleaned"])
            for rows in repeats
            for row in rows
            if not row["match"]
        ],
        workers,
    )
    verdicts = load_verdicts()
    return [sum(accepted(row, verdicts) for row in rows) for rows in repeats]


def report(paths: list[Path], show_accepted: bool, workers: int) -> None:
    runs = [json.loads(path.read_text(encoding="utf-8")) for path in paths]
    score([rows for run in runs for rows in run["repeats"]], workers)
    verdicts = load_verdicts()
    for path, run in zip(paths, runs, strict=True):
        exact = [sum(row["match"] for row in rows) for rows in run["repeats"]]
        judged = score(run["repeats"], workers)
        count = len(run["repeats"])
        print(
            f"{path.stem:34} {run['model']:26} n={count:<3} judged {sum(judged) / count:5.2f}"
            f"  exact {sum(exact) / count:5.2f} / {run['entries']}"
        )
        if not show_accepted:
            continue
        lenient = Counter(
            (row["id"], row["cleaned"])
            for rows in run["repeats"]
            for row in rows
            if not row["match"] and accepted(row, verdicts)
        )
        for (entry_id, cleaned), times in sorted(lenient.items()):
            print(f"    {entry_id} x{times}: {cleaned!r}")


def calibrate(workers: int) -> None:
    """Agreement with hand labels, on the set the rubric was written against and on a held-out
    set it never shaped. Kappa, because most pairs are rejects and raw agreement flatters a
    judge that rejects everything; false accepts apart, because leniency is the judge's risk."""
    for path in (CALIBRATION, HELDOUT):
        labels = [
            json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()
        ]
        judge([(label["id"], label["cleaned"]) for label in labels], workers)
        verdicts = load_verdicts()
        cells: Counter[tuple[str, str]] = Counter()
        split = 0
        for label in labels:
            verdict = verdicts[key(label["id"], label["expect"], label["cleaned"])]
            cells[label["label"], verdict["verdict"]] += 1
            split += len({vote["verdict"] for vote in verdict["votes"]}) > 1
            if verdict["verdict"] == label["label"]:
                continue
            reasons = "; ".join(vote["reason"] for vote in verdict["votes"])
            print(
                f"  {label['id']} hand {label['label']}, judge {verdict['verdict']}: "
                f"{label['cleaned']!r}\n    {reasons}"
            )
        count = len(labels)
        agree = cells["accept", "accept"] + cells["reject", "reject"]
        chance = sum(
            (cells[side, "accept"] + cells[side, "reject"])
            * (cells["accept", side] + cells["reject", side])
            for side in ("accept", "reject")
        ) / (count * count)
        kappa = (agree / count - chance) / (1 - chance)
        print(
            f"{path.name} rubric {RUBRIC_ID}: {agree}/{count} agree, kappa {kappa:.2f}, "
            f"{cells['reject', 'accept']} false accepts, {cells['accept', 'reject']} false "
            f"rejects; {split} pairs split the judge's own votes"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "runs", type=Path, nargs="*", help="`tune.py stage3 --output` files"
    )
    parser.add_argument(
        "--accepted", action="store_true", help="List every lenient pass."
    )
    parser.add_argument("--calibrate", action="store_true")
    parser.add_argument("--workers", type=int, default=6)
    args = parser.parse_args()
    if args.calibrate:
        calibrate(args.workers)
    if args.runs:
        report(args.runs, args.accepted, args.workers)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
