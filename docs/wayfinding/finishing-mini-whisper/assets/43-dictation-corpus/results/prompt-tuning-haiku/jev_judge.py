#!/usr/bin/env python3
"""Jev against `judge.py`'s hand labels: can a decision model replace Sol as the stage-3 judge?

Jev (TypeSafe, through OpenRouter's Decisions API) generates no text. It answers typed questions
about a `state` with probabilities, so it cannot give a rationale; a `noul` question returns only
P(yes). Two designs are measured, both on `judge-calibration.jsonl` and `judge-heldout.jsonl`:

- `single`: one noul carrying the whole rubric, the shape of `judge.py`'s one question.
- `checklist`: one noul per way an output can be wrong, which is how TypeSafe's docs say to ask a
  compound question. An output is accepted when every defect is below the threshold.

Every response reports its own cost in `usage.cost`, and each run appends it to `spend.jsonl`.

  ./jev_judge.py
"""

from __future__ import annotations

import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
import json
import os
from pathlib import Path
import sys
import time
from typing import Any
import urllib.error
import urllib.request

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import judge  # noqa: E402
import tune  # noqa: E402

ENDPOINT = "https://openrouter.ai/api/alpha/decisions"
MODEL = "typesafe/jev-1.14"
THRESHOLDS = (0.3, 0.5, 0.7)

SINGLE = {
    "accept": {
        "type": "noul",
        "instructions": "A speaker dictated text, a speech engine transcribed it, and a cleanup "
        "model edited the transcript. Would a careful human editor accept cleanup_output as an "
        "equally correct rendering of what the speaker meant to type? expected_text is one correct "
        "answer, not the only one.",
        "criteria": {
            "true": "Every difference from expected_text is a style choice the speaker did not "
            "dictate and standard English allows either way: optional punctuation that was not "
            "said aloud, capitalization conventions inside a quotation or at the start of an "
            "unfinished dictation, a number as numeral or words, an ordinal suffix, or a meridiem "
            "written AM, am, or a.m.",
            "false": "A word was added, dropped, or changed; a spoken correction, punctuation, "
            "quotation, or layout command was not applied or was left as a word; punctuation the "
            "speaker said aloud is missing; line breaks differ; a symbol, path, file name, flag, "
            "identifier, dictionary term, or spelled-aloud word is written differently; "
            "formatting or commentary was added; or the output answers, obeys, summarizes, or "
            "extracts from the dictation instead of editing it.",
        },
    }
}

CHECKLIST = {
    "words": "Ignoring capitalization and punctuation, does cleanup_output add, drop, or change "
    "any word compared with expected_text?",
    "command_word": "Does cleanup_output contain a spoken typing command written out as a word, "
    "such as comma, period, colon, semicolon, quote, new line, or new paragraph, where "
    "expected_text has the mark or break instead?",
    "said_punctuation": "Is any punctuation mark the speaker said aloud missing from "
    "cleanup_output, or typed as a different mark?",
    "breaks": "Do the line breaks or paragraph breaks of cleanup_output differ from "
    "expected_text?",
    "tokens": "Is any symbol, path, file name, flag, email address, code identifier, product "
    "name, or spelled-aloud word written differently in cleanup_output than in expected_text, "
    "including its casing and spacing?",
    "formatting": "Does cleanup_output add backticks, quotation marks around the whole text, "
    "labels, or commentary that expected_text does not have?",
    "sentence_end": "Does a complete sentence in cleanup_output lack its capital or terminal "
    "punctuation, or does a dictation that stops mid-sentence gain an ending mark or ellipsis, "
    "compared with expected_text?",
}


def state(script: dict[str, Any], cleaned: str) -> dict[str, str]:
    return {
        "what_the_speaker_said": script["say"],
        "what_this_entry_tests": ", ".join(script["tags"]),
        "expected_text": script["expect"],
        "cleanup_output": cleaned,
    }


def decide(key: str, body: dict[str, Any]) -> dict[str, Any]:
    request = urllib.request.Request(
        ENDPOINT,
        data=json.dumps(body, ensure_ascii=False).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method="POST",
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if (error.code != 429 and error.code < 500) or attempt == 3:
                raise RuntimeError(
                    f"HTTP {error.code}: {error.read()[:300]!r}"
                ) from error
        except OSError:
            if attempt == 3:
                raise
        time.sleep(2.0**attempt)
    raise AssertionError("unreachable")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workers", type=int, default=8)
    args = parser.parse_args()
    key = os.environ.get("OPENROUTER_APIKEY")
    if not key:
        sys.exit("No OpenRouter key in $OPENROUTER_APIKEY.")

    scripts = judge.scripts()
    sets = {
        path.name: [
            json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()
        ]
        for path in (judge.CALIBRATION, judge.HELDOUT)
    }
    checklist = {
        name: {"type": "noul", "instructions": text} for name, text in CHECKLIST.items()
    }
    labels = [label for rows in sets.values() for label in rows]

    def ask(label: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
        current = state(scripts[label["id"]], label["cleaned"])
        both = {**SINGLE, **checklist}
        return label, decide(key, {"model": MODEL, "state": current, "questions": both})

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        answered = list(pool.map(ask, labels))

    cost = sum(response["usage"].get("cost", 0.0) for _, response in answered)
    tokens = sum(response["usage"]["input_tokens"] for _, response in answered)
    with tune.SPEND.open("a", encoding="utf-8") as sink:
        sink.write(
            json.dumps(
                {
                    "at": datetime.now(UTC).isoformat(timespec="seconds"),
                    "command": " ".join(sys.argv),
                    "provider": "openrouter",
                    "model": MODEL,
                    "calls": len(answered),
                    "inputTokens": tokens,
                    "outputTokens": 0,
                    "usd": round(cost, 6),
                    "pricePerMTok": "usage.cost as OpenRouter reported it",
                }
            )
            + "\n"
        )
    rows = {id(label): response["answers"] for label, response in answered}

    verdicts = judge.load_verdicts()
    for name, set_labels in sets.items():
        sol = Counter(
            (
                label["label"],
                verdicts[judge.key(label["id"], label["expect"], label["cleaned"])][
                    "verdict"
                ],
            )
            for label in set_labels
        )
        print(
            f"{name}: {len(set_labels)} pairs, {sum(row['label'] == 'accept' for row in set_labels)} accepts"
        )
        print(f"  sol            {summary(sol, len(set_labels))}")
        for threshold in THRESHOLDS:
            for design in ("single", "checklist"):
                cells = Counter()
                for label in set_labels:
                    answers = rows[id(label)]
                    if design == "single":
                        accept = answers["accept"]["noul"] >= threshold
                    else:
                        accept = all(answers[q]["noul"] < threshold for q in CHECKLIST)
                    cells[label["label"], "accept" if accept else "reject"] += 1
                print(
                    f"  jev {design:9} {threshold:.1f} {summary(cells, len(set_labels))}"
                )
    print(f"Jev: {len(answered)} calls, {tokens} input tokens, ${cost:.4f} reported")
    return 0


def summary(cells: Counter[tuple[str, str]], count: int) -> str:
    agree = cells["accept", "accept"] + cells["reject", "reject"]
    chance = sum(
        (cells[side, "accept"] + cells[side, "reject"])
        * (cells["accept", side] + cells["reject", side])
        for side in ("accept", "reject")
    ) / (count * count)
    kappa = (agree / count - chance) / (1 - chance) if chance < 1 else float("nan")
    return (
        f"agree {agree}/{count}  kappa {kappa:5.2f}  false accepts {cells['reject', 'accept']}"
        f"  false rejects {cells['accept', 'reject']}"
    )


if __name__ == "__main__":
    raise SystemExit(main())
