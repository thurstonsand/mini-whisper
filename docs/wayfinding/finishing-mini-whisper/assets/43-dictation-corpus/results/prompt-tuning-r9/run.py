#!/usr/bin/env python3
"""Round 9: old prompt vs new prompt, with and without the user's own instructions.

The app's transport, the app's model, no judge: the Sol judge needs ChatGPT OAuth this machine
does not have. Every arm is scored mechanically — exact match on the frozen 25 and the holdout,
perturb.py's rule checks on the nine-rule grid, and empty or refused completions counted apart.

    CLEANUP_ENDPOINT=… CLEANUP_MODEL=… CLEANUP_APIKEY=… ./run.py --source old.swift --label old
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
import dataclasses
import json
import os
from pathlib import Path
import re
import sys
import threading

HAIKU = Path(__file__).resolve().parents[1] / "prompt-tuning-haiku"
sys.path[:0] = [str(HAIKU), str(HAIKU.parents[1])]

import corpus_cleanup  # noqa: E402
import perturb  # noqa: E402
import tune  # noqa: E402

EMPTY = "<EMPTY>"


def completer():
    endpoint = os.environ["CLEANUP_ENDPOINT"]
    model = os.environ["CLEANUP_MODEL"]
    key = os.environ["CLEANUP_APIKEY"]
    lock = threading.Lock()
    spent = {"calls": 0, "empty": 0}

    def complete(system: str, user: str) -> str:
        for attempt in range(4):
            try:
                content, _, _ = corpus_cleanup.complete(
                    endpoint, key, model, system, user, 90.0, {}, 4
                )
                break
            except ValueError:
                content = ""
                break
            except OSError:
                if attempt == 3:
                    raise
        with lock:
            spent["calls"] += 1
            if not content.strip():
                spent["empty"] += 1
        return content if content.strip() else EMPTY

    return complete, spent


def folded(variant: perturb.Variant, cleaned: str) -> bool:
    """The rule check with case taken out, because the instructions under test lowercase proper
    nouns on purpose."""
    lowered = dataclasses.replace(
        variant,
        required=tuple(n.lower() for n in variant.required),
        forbidden=tuple(n.lower() for n in variant.forbidden),
    )
    return lowered.obeyed(cleaned.lower())


def instruction_checks(cleaned: str) -> dict[str, bool]:
    letters = [c for c in cleaned if c.isalpha()]
    words = re.findall(r"[A-Za-z']+", cleaned)
    return {
        "lowercaseStart": bool(letters) and letters[0].islower(),
        "noFinalPeriod": not cleaned.rstrip().endswith("."),
        "endsHappy": bool(words) and words[-1].lower() == "happy",
    }


def normalized(text: str) -> str:
    """What is left once the three instructions are undone: content and the built-in rules."""
    text = text.strip().lower()
    text = re.sub(r"[\s,.;:!-]*happy[\s.!\"”]*$", "", text)
    return text.rstrip(".").strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--instructions")
    parser.add_argument("--repeat", type=int, default=3)
    parser.add_argument("--grid-repeat", type=int, default=2)
    parser.add_argument("--workers", type=int, default=12)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--rule", action="append")
    args = parser.parse_args()

    system = corpus_cleanup.system_message(
        corpus_cleanup.built_in_prompt(args.source), args.instructions, args.source
    )
    complete, spent = completer()

    jobs = []
    for stage, script, raw in (
        ("frozen", tune.STAGE3, tune.STAGE3_RAW),
        ("holdout", tune.STAGE3_HOLDOUT, tune.STAGE3_HOLDOUT_RAW),
    ):
        for entry in tune.entries(script, raw, False):
            for attempt in range(args.repeat):
                jobs.append((stage, entry, None, attempt))
    for variant in perturb.grid(args.rule or sorted(perturb.RULES)):
        for attempt in range(args.grid_repeat):
            jobs.append(("grid", None, variant, attempt))

    def one(job):
        stage, entry, variant, attempt = job
        if variant is None:
            user = corpus_cleanup.user_message(
                entry["raw"], (entry.get("context") or {}).get("before"), [], None
            )
            expect = entry["expect"].strip()
            ident, rule = entry["id"], None
        else:
            user = corpus_cleanup.user_message(
                variant.raw, variant.context, list(variant.dictionary)
            )
            expect = variant.expect
            ident, rule = variant.id, variant.rule
        content = complete(system, user)
        cleaned = content if content == EMPTY else corpus_cleanup.shape(content)
        row = {
            "stage": stage,
            "id": ident,
            "rule": rule,
            "attempt": attempt,
            "expect": expect,
            "cleaned": cleaned,
            "exact": cleaned == expect,
            "normalizedMatch": normalized(cleaned) == normalized(expect),
            "refused": "content safety filter" in cleaned,
            "leak": cleaned != EMPTY and len(cleaned) > 1.5 * len(expect) + 20,
            **instruction_checks(cleaned),
        }
        if variant is not None:
            row["obeyed"] = variant.obeyed(cleaned)
            row["obeyedFolded"] = folded(variant, cleaned)
        return row

    print(f"{args.label}: {len(jobs)} calls", flush=True)
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        rows = list(pool.map(one, jobs))

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        json.dumps(
            {
                "label": args.label,
                "instructions": args.instructions,
                "system": system,
                "calls": spent["calls"],
                "empty": spent["empty"],
                "rows": rows,
            },
            indent=1,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"{args.label}: done, {spent['empty']} empty of {spent['calls']}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
