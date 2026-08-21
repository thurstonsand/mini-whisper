#!/usr/bin/env python3
"""Score asr-replay output against the dictation corpus.

Two stages have an ASR score. Stage 1 is word error rate against the verbatim `say`; stage 2 is
`wants` recall and `traps` false positives, bare against boosted, with the boost's latency cost.
Stage 3 has no ASR score at all: its raw transcripts are the input to corpus_cleanup.py.

  ./score_corpus.py stage1 stage1-intelligibility.jsonl results/built-in/stage1.jsonl
  ./score_corpus.py stage2 stage2-dictionary.jsonl \\
      --bare results/built-in/stage2-bare.jsonl --boosted results/built-in/stage2-boosted.jsonl
  ./score_corpus.py sweep stage2-dictionary.jsonl \\
      --run 0.65=results/boost-sweep/stage2-boosted-0.65.jsonl ...
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import statistics
import sys
from typing import Any

PUNCTUATION = re.compile(r"[^\w\s']")


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    entries = []
    for number, line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        if line.strip():
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError as error:
                sys.exit(f"{path}:{number}: {error}")
    return entries


def by_id(entries: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {entry["id"]: entry for entry in entries}


def normalize(text: str) -> list[str]:
    """Lowercase, drop punctuation that is not an apostrophe, collapse whitespace."""
    return PUNCTUATION.sub(" ", text.lower()).split()


def edits(reference: list[str], hypothesis: list[str]) -> tuple[int, int, int]:
    """Levenshtein over words, returning (substitutions, deletions, insertions)."""
    # Each cell carries its own error breakdown so the report can name what went wrong.
    row = [(index, 0, index, 0) for index in range(len(hypothesis) + 1)]
    for r, reference_word in enumerate(reference, start=1):
        previous = row
        row = [(r, 0, 0, r)]
        for h, hypothesis_word in enumerate(hypothesis, start=1):
            if reference_word == hypothesis_word:
                row.append(previous[h - 1])
                continue
            substitution = (
                previous[h - 1][0] + 1,
                previous[h - 1][1] + 1,
                previous[h - 1][2],
                previous[h - 1][3],
            )
            deletion = (
                previous[h][0] + 1,
                previous[h][1],
                previous[h][2],
                previous[h][3] + 1,
            )
            insertion = (
                row[h - 1][0] + 1,
                row[h - 1][1],
                row[h - 1][2] + 1,
                row[h - 1][3],
            )
            row.append(min(substitution, deletion, insertion))
    total = row[-1]
    return total[1], total[3], total[2]


def word_diff(reference: list[str], hypothesis: list[str]) -> str:
    from difflib import SequenceMatcher

    pieces = []
    matcher = SequenceMatcher(None, reference, hypothesis)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            pieces.append(" ".join(reference[i1:i2]))
        elif tag == "replace":
            pieces.append(
                f"[{' '.join(reference[i1:i2])} → {' '.join(hypothesis[j1:j2])}]"
            )
        elif tag == "delete":
            pieces.append(f"[-{' '.join(reference[i1:i2])}]")
        else:
            pieces.append(f"[+{' '.join(hypothesis[j1:j2])}]")
    return " ".join(piece for piece in pieces if piece)


def latency_summary(values: list[float]) -> dict[str, float]:
    ordered = sorted(values)
    return {
        "n": len(ordered),
        "medianMs": round(statistics.median(ordered), 1),
        "meanMs": round(statistics.fmean(ordered), 1),
        "minMs": round(ordered[0], 1),
        "maxMs": round(ordered[-1], 1),
    }


def score_stage1(args: argparse.Namespace) -> dict[str, Any]:
    scripts = by_id(load_jsonl(args.stage))
    results = load_jsonl(args.results)
    rows = []
    for result in results:
        reference = normalize(scripts[result["id"]]["say"])
        hypothesis = normalize(result["transcript"])
        substitutions, deletions, insertions = edits(reference, hypothesis)
        rows.append(
            {
                "id": result["id"],
                "words": len(reference),
                "substitutions": substitutions,
                "deletions": deletions,
                "insertions": insertions,
                "wer": (substitutions + deletions + insertions) / len(reference),
                "latencyMs": result["latencyMs"],
                "diff": word_diff(reference, hypothesis),
                "reference": scripts[result["id"]]["say"],
                "transcript": result["transcript"],
            }
        )

    words = sum(row["words"] for row in rows)
    errors = sum(
        row["substitutions"] + row["deletions"] + row["insertions"] for row in rows
    )
    report = {
        "stage": "stage1-intelligibility",
        "entries": len(rows),
        "words": words,
        "substitutions": sum(row["substitutions"] for row in rows),
        "deletions": sum(row["deletions"] for row in rows),
        "insertions": sum(row["insertions"] for row in rows),
        "wer": round(errors / words, 4),
        "cleanEntries": sum(1 for row in rows if row["wer"] == 0),
        "latency": latency_summary([row["latencyMs"] for row in rows]),
        "entriesByWer": sorted(rows, key=lambda row: -row["wer"]),
    }

    print(
        f"Stage 1 — intelligibility ({report['entries']} entries, {words} reference words)"
    )
    print(
        f"WER {report['wer'] * 100:.2f}%  "
        f"({report['substitutions']}S {report['deletions']}D {report['insertions']}I)  "
        f"clean entries {report['cleanEntries']}/{report['entries']}"
    )
    latency = report["latency"]
    print(
        f"Latency median {latency['medianMs']:.0f} ms, "
        f"mean {latency['meanMs']:.0f} ms, max {latency['maxMs']:.0f} ms"
    )
    print("\nWorst entries:")
    for row in report["entriesByWer"]:
        if row["wer"] == 0:
            break
        print(f"  {row['id']}  WER {row['wer'] * 100:5.1f}%  {row['diff']}")
    return report


def contains(term: str, transcript: str, fold_case: bool) -> bool:
    """Substring, because the corpus terms carry their own punctuation (`llama.cpp`)."""
    if fold_case:
        return term.lower() in transcript.lower()
    return term in transcript


def score_terms(
    scripts: dict[str, dict[str, Any]], results: dict[str, dict[str, Any]]
) -> dict[str, Any]:
    """One run's `wants` recall and `traps` false positives. Transcripts come from anywhere that
    keys them by corpus id — the ASR replay, or a cleanup pass run over it."""
    wants_rows, traps_rows = [], []
    for entry_id, script in scripts.items():
        transcript = results[entry_id]["transcript"]
        for term in script.get("wants", []):
            wants_rows.append(
                {
                    "id": entry_id,
                    "term": term,
                    "hit": contains(term, transcript, fold_case=False),
                    "hitIgnoringCase": contains(term, transcript, fold_case=True),
                    "transcript": transcript,
                }
            )
        for term in script.get("traps", []):
            traps_rows.append(
                {
                    "id": entry_id,
                    "term": term,
                    "bitten": contains(term, transcript, fold_case=False),
                    "bittenIgnoringCase": contains(term, transcript, fold_case=True),
                    "transcript": transcript,
                }
            )
    return {
        "wantsTotal": len(wants_rows),
        "wantsHit": sum(row["hit"] for row in wants_rows),
        "wantsHitIgnoringCase": sum(row["hitIgnoringCase"] for row in wants_rows),
        "trapsTotal": len(traps_rows),
        "trapsBitten": sum(row["bitten"] for row in traps_rows),
        "trapsBittenIgnoringCase": sum(row["bittenIgnoringCase"] for row in traps_rows),
        "latency": latency_summary([results[key]["latencyMs"] for key in scripts]),
        "wants": wants_rows,
        "traps": traps_rows,
    }


def term_row(name: str, run: dict[str, Any]) -> str:
    recall = run["wantsHit"] / run["wantsTotal"]
    false_positives = run["trapsBitten"] / run["trapsTotal"]
    return (
        f"{name:9} {run['wantsHit']:3}/{run['wantsTotal']:<3} {recall * 100:6.1f}%  "
        f"{run['trapsBitten']:3}/{run['trapsTotal']:<3} {false_positives * 100:6.1f}%  "
        f"{run['latency']['medianMs']:6.0f} ms"
    )


def score_stage2(args: argparse.Namespace) -> dict[str, Any]:
    scripts = by_id(load_jsonl(args.stage))
    runs = {
        "bare": by_id(load_jsonl(args.bare)),
        "boosted": by_id(load_jsonl(args.boosted)),
    }

    report: dict[str, Any] = {"stage": "stage2-dictionary", "runs": {}}
    for name, results in runs.items():
        report["runs"][name] = score_terms(scripts, results)

    bare, boosted = report["runs"]["bare"], report["runs"]["boosted"]
    report["latencyOverheadMs"] = round(
        boosted["latency"]["medianMs"] - bare["latency"]["medianMs"], 1
    )

    print(f"Stage 2 — the sidecar ({len(scripts)} entries)")
    print(f"{'':9} {'wants recall':>16} {'traps bitten':>16} {'median':>9}")
    for name in ("bare", "boosted"):
        print(term_row(name, report["runs"][name]))
    print(
        f"Boost latency overhead: +{report['latencyOverheadMs']:.0f} ms at the median"
    )

    for name in ("bare", "boosted"):
        run = report["runs"][name]
        print(f"\n{name}: missed wants")
        for row in run["wants"]:
            if not row["hit"]:
                folded = " (present but miscased)" if row["hitIgnoringCase"] else ""
                print(f"  {row['id']:8} {row['term']:12}{folded}  {row['transcript']}")
        print(f"{name}: bitten traps")
        for row in run["traps"]:
            if row["bitten"]:
                print(f"  {row['id']:8} {row['term']:12}  {row['transcript']}")
            elif row["bittenIgnoringCase"]:
                print(
                    f"  {row['id']:8} {row['term']:12}  (case-folded only) {row['transcript']}"
                )
    return report


def score_sweep(args: argparse.Namespace) -> dict[str, Any]:
    """Stage 2's score across a parameter sweep: one labelled boosted run per point."""
    scripts = by_id(load_jsonl(args.stage))
    report: dict[str, Any] = {"stage": "stage2-dictionary", "runs": {}}
    for specification in args.run:
        label, separator, path = specification.partition("=")
        if not separator:
            sys.exit(f"--run wants LABEL=PATH, got {specification!r}")
        report["runs"][label] = score_terms(scripts, by_id(load_jsonl(Path(path))))

    print(f"Stage 2 sweep ({len(scripts)} entries, {len(report['runs'])} runs)")
    print(f"{'':9} {'wants recall':>16} {'traps bitten':>16} {'median':>9}")
    for label, run in report["runs"].items():
        print(term_row(label, run))

    for label, run in report["runs"].items():
        bitten = sorted({row["term"] for row in run["traps"] if row["bitten"]})
        missed = sorted({row["term"] for row in run["wants"] if not row["hit"]})
        print(f"\n{label}")
        print(f"  bitten traps: {', '.join(bitten) or 'none'}")
        print(f"  missed wants: {', '.join(missed) or 'none'}")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--report", type=Path, help="Write the full scoring detail as JSON."
    )
    stages = parser.add_subparsers(dest="command", required=True)

    stage1 = stages.add_parser("stage1", help="WER against the verbatim scripts.")
    stage1.add_argument("stage", type=Path)
    stage1.add_argument("results", type=Path)
    stage1.set_defaults(score=score_stage1)

    stage2 = stages.add_parser("stage2", help="wants recall and traps false positives.")
    stage2.add_argument("stage", type=Path)
    stage2.add_argument("--bare", type=Path, required=True)
    stage2.add_argument("--boosted", type=Path, required=True)
    stage2.set_defaults(score=score_stage2)

    sweep = stages.add_parser(
        "sweep", help="the same score across several boosted runs."
    )
    sweep.add_argument("stage", type=Path)
    sweep.add_argument(
        "--run",
        action="append",
        required=True,
        metavar="LABEL=PATH",
        help="One boosted run, labelled by the setting it varied.",
    )
    sweep.set_defaults(score=score_sweep)

    args = parser.parse_args()
    report = args.score(args)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"\nWrote {args.report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
