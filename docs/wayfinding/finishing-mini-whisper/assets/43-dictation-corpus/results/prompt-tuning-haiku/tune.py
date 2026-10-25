#!/usr/bin/env python3
"""The prompt-search loop: one candidate prompt in, a frozen-set score and its failures out.

`corpus_cleanup.py` is the measurement of record — it lifts the prompt out of the Swift source and
sends the app's body serially, so its latency is the pipeline's latency. That serial run is 20 s a
candidate, and a search wants dozens of candidates, so this runner imports that harness and changes
exactly two things: the system prompt comes from a plain text file instead of `CleanupPrompt.swift`,
and the entries run concurrently. **Concurrency destroys the latency measurement**, so nothing here
reports one; headline numbers are always re-measured with `corpus_cleanup.py` itself.

The objective is frozen: stage 3 minus `polish-11` and `polish-38`, the two entries Parakeet's raw
cannot support (it deletes the quote/unquote and the letter-by-letter spelling before cleanup ever
sees them). Scoring those would grade the engine, not the prompt.

The headline is the judged score: an exact miss that `judge.py` rules an equally correct rendering,
such as an optional comma the speaker never dictated, counts as a pass. Exact match is printed and
saved beside it, so the judge's leniency stays visible on every arm.

`proxy-haiku` is the scorer of record: `claude-haiku-5-5`, the factory profile's model, reached
through CLIProxyAPI on the Claude subscription. Rounds 4 and 5 scored `claude-haiku-4-5` through
`sdk-haiku` instead, and their numbers belong to that model. CLIProxyAPI does not send our prompt
the way the app does: it puts a Claude Code identity line in the system prompt, a date reminder in
the transcript's turn, and our prompt in a system turn after the transcript; see
[`prompt-tuning-r7/`](../prompt-tuning-r7/README.md#the-transport). `api.anthropic.com` is gone from `PROVIDERS`
entirely, because rounds 1 to 3 quietly spent real money on scoring loops that had a free path to
the identical model. The transport is not free of consequences — Claude Code injects about 119
tokens of environment context ahead of every request, measured in
[`agent-sdk-cleanup/`](../../agent-sdk-cleanup/README.md) — but it is a constant, and a constant
that every arm pays is a comparison that still works.

  ./tune.py stage3 --prompt candidates/baseline.txt --label baseline
  ./tune.py stage3 --prompt candidates/final.txt --repeat 5
  ./tune.py stage2 --prompt candidates/baseline.txt --output runs/stage2-baseline.jsonl
"""

from __future__ import annotations

import argparse
from collections.abc import Callable, Iterator
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from difflib import unified_diff
import json
import os
from pathlib import Path
import sys
import time
from typing import Any

HERE = Path(__file__).resolve().parent
CORPUS = HERE.parent.parent
sys.path.insert(0, str(CORPUS))

import corpus_cleanup  # noqa: E402

# Parakeet ate the material these two entries test; see the run README.
EXCLUDED = ("polish-11", "polish-38")

STAGE3 = CORPUS / "stage3-polish.jsonl"
STAGE3_HOLDOUT = CORPUS / "stage3-holdout.jsonl"
STAGE3_HOLDOUT_RAW = CORPUS / "results/holdout/stage3-raw.jsonl"
STAGE3_RAW = CORPUS / "results/built-in-r2/stage3-raw.jsonl"
STAGE2 = CORPUS / "stage2-dictionary.jsonl"
STAGE2_RAW = CORPUS / "results/built-in/stage2-bare.jsonl"

# `anthropic` is deliberately absent. It was the default scorer for rounds 1 to 3 and it was the
# whole bill: a search is thousands of scoring calls, and the Claude subscription reaches the same
# `claude-haiku-4-5` for nothing. It is removed rather than gated so a future round cannot rediscover
# it by leaving a flag off. Numbers measured against it keep their provenance in their own READMEs;
# nothing new is comparable to them.
PROVIDERS = {
    "gemini": {
        "endpoint": "https://generativelanguage.googleapis.com/v1beta/openai/",
        "model": "gemini-3.6-flash",
        "env": "GEMINI_APIKEY",
    },
    # The same model through the gateway. It scores identically to Google direct and costs about
    # 600 ms more per call (results/gemini-direct/), which a score comparison does not care about.
    "gateway": {
        "endpoint": "https://aig.thurstons.house/v1",
        "model": "gemini-3.6-flash",
        "env": "AIG_APIKEY",
    },
    "cerebras": {
        "endpoint": "https://api.cerebras.ai/v1",
        "model": "gpt-oss-120b",
        "env": "CEREBRAS_APIKEY",
    },
    # The factory profile's model, through CLIProxyAPI on the Claude subscription: an ordinary
    # OpenAI-compatible endpoint, so the scorer speaks the same protocol the app's client does and
    # costs one HTTP request a call instead of a Claude Code process. The proxy injects about 135
    # tokens of its own ahead of every request; like the SDK's 119, every arm pays it.
    "proxy-haiku": {
        "endpoint": "https://aig.thurstons.house/v1",
        "model": "claude-haiku-5-5",
        "env": "AIG_APIKEY",
        "subscription": True,
    },
    # Not an endpoint at all: Claude Code over the subscription's OAuth session. It scored
    # identically to the metered Haiku above (results/agent-sdk-haiku/) and bills nothing.
    # Claude Code names its own models: `haiku` resolves to claude-haiku-4-5, `opus[1m]` to
    # claude-opus-5. The API's own identifiers are not accepted for Opus.
    "sdk-haiku": {"sdk": True, "subscription": True, "model": "claude-haiku-4-5"},
    "sdk-opus": {"sdk": True, "subscription": True, "model": "opus[1m]"},
}

# `corpus_cleanup.complete`'s two arguments that vary per call; the rest belong to the transport.
Completion = Callable[[str, str], tuple[str, float, float]]


def api_key(provider: dict[str, str]) -> str:
    key = os.environ.get(provider["env"])
    if not key:
        sys.exit(f"No API key in ${provider['env']}; source the repo's .env first.")
    return key


def resolve_model(name: str, override: str | None) -> str:
    return override or PROVIDERS[name]["model"]


def transport_arguments(parser: argparse.ArgumentParser) -> None:
    """The transport switches, in one place, so a new tool cannot invent a different default.

    `proxy-haiku` is the default because it is the factory profile's model and it is free;
    `anthropic` was neither. Three rounds of this harness defaulted the other way and the bill
    arrived accordingly."""
    parser.add_argument("--provider", choices=sorted(PROVIDERS), default="proxy-haiku")
    parser.add_argument("--model")
    parser.add_argument("--workers", type=int, default=9)
    parser.add_argument(
        "--metered",
        action="store_true",
        help="Authorize a provider that bills per call. Required by every non-SDK provider.",
    )


def authorize(name: str, model: str, calls: int, metered: bool) -> None:
    """What this run will spend, said out loud before the first request goes out.

    Cerebras and Gemini still bill. Neither has an ambient credential to fall back to, so they are
    announced rather than refused — gating them would gate the measurement itself. What they do not
    get is silence: a sweep that cannot say how many calls it is about to make does not start."""
    if PROVIDERS[name].get("subscription"):
        return
    plan = f"{calls} calls to {model} via {name}"
    if not metered:
        sys.exit(
            f"Refusing {plan}: {name} bills per call. Pass --metered to spend deliberately."
        )
    print(f"METERED: {plan}")


@contextmanager
def transport(
    name: str, override: str | None, workers: int, *, calls: int, metered: bool
) -> Iterator[Completion]:
    """How a candidate reaches the model. An HTTP provider is a closure over its endpoint and key;
    a subscription provider is a pool of Claude Code pipes that has to be torn down, which is the
    only reason this is a context manager rather than a function returning a callable.

    `calls` and `metered` are keyword-only and have no defaults on purpose. This function is the
    single door to inference in the harness, so a caller that has not worked out what its sweep
    will cost cannot get through it."""
    provider = PROVIDERS[name]
    model = resolve_model(name, override)
    authorize(name, model, calls, metered)
    if not provider.get("sdk"):
        endpoint, key = provider["endpoint"], api_key(provider)

        def over_http(system: str, user: str) -> tuple[str, float, float]:
            # The harness retries the statuses a server sends deliberately; a dropped socket over
            # a long search is neither deliberate nor rare, and losing a search to one is worse.
            for attempt in range(4):
                try:
                    return corpus_cleanup.complete(
                        endpoint, key, model, system, user, 90.0, {}, 4
                    )
                except OSError:
                    if attempt == 3:
                        raise
                    time.sleep(2.0**attempt)
            raise AssertionError("unreachable")

        yield over_http
        return

    sys.path.insert(0, str(CORPUS / "agent-sdk-cleanup"))
    import sdk_pool

    pool = sdk_pool.AgentSdkPool(model, workers)

    def over_subscription(system: str, user: str) -> tuple[str, float, float]:
        return pool.complete("subscription", None, model, system, user, 120.0, {}, 0)

    try:
        yield over_subscription
    finally:
        print(pool.report())
        pool.close()


def prompt_text(args: argparse.Namespace) -> str:
    """The candidate, plus the user's own instructions when an arm stages them.

    The app has always sent `CleanupPrompt.systemMessage(additionalInstructions:)` and this harness
    has always scored `builtIn`, so every arm before round 4 measured a prompt no configured user
    receives. The frame sentence comes out of the Swift, not out of a copy of it."""
    return corpus_cleanup.system_message(
        args.prompt.read_text(encoding="utf-8").strip(),
        corpus_cleanup.instruction_text(args.additional_instructions),
        corpus_cleanup.CLEANUP_PROMPT_SWIFT,
    )


def entries(stage: Path, raw: Path, keep_excluded: bool) -> list[dict[str, Any]]:
    scripts = {e["id"]: e for e in corpus_cleanup.load_jsonl(stage)}
    transcripts = {e["id"]: e for e in corpus_cleanup.load_jsonl(raw)}
    return [
        script | {"raw": transcripts[key]["transcript"]}
        for key, script in scripts.items()
        if key in transcripts and (keep_excluded or key not in EXCLUDED)
    ]


def fan_out(
    work: list[dict[str, Any]],
    prompt: str,
    complete: Completion,
    vocabulary: list[str],
    workers: int,
    bundle_id: str | None = None,
) -> list[dict[str, Any]]:
    def one(entry: dict[str, Any]) -> dict[str, Any]:
        user = corpus_cleanup.user_message(
            entry["raw"],
            (entry.get("context") or {}).get("before"),
            vocabulary,
            bundle_id,
        )
        content, _, _ = complete(prompt, user)
        return entry | {"cleaned": corpus_cleanup.shape(content)}

    with ThreadPoolExecutor(max_workers=workers) as pool:
        return list(pool.map(one, work))


def run_stage3(args: argparse.Namespace) -> int:
    model = resolve_model(args.provider, args.model)
    prompt = prompt_text(args)
    work = entries(args.script, args.raw, args.include_excluded)
    if args.entry:
        work = [entry for entry in work if entry["id"] in set(args.entry)]
    label = args.label or args.prompt.stem
    if args.additional_instructions:
        label = f"{label}+ai"

    # Repeats, because the models are non-deterministic and a one-run delta of ±1 is noise. The
    # per-entry pass count over the repeats is what a candidate is actually judged on.
    repeats = []
    misses: dict[str, list[dict[str, Any]]] = {}
    with transport(
        args.provider,
        args.model,
        args.workers,
        calls=len(work) * args.repeat,
        metered=args.metered,
    ) as complete:
        for _ in range(args.repeat):
            rows = fan_out(work, prompt, complete, [], args.workers, args.bundle_id)
            for row in rows:
                row["match"] = row["cleaned"] == row["expect"].strip()
                if not row["match"]:
                    misses.setdefault(row["id"], []).append(row)
            repeats.append(rows)

    # The judged score is the headline; exact match stays beside it so the judge's leniency is
    # visible on every arm. `judge.py` imports this module, so it is imported here, not above.
    import judge

    scores = [sum(row["match"] for row in rows) for rows in repeats]
    judged = judge.score(repeats, args.workers)
    total = len(work)
    print(
        f"{label}  {model}  judged "
        + " ".join(f"{score}/{total}" for score in judged)
        + f"  mean {sum(judged) / len(judged):.2f}  (exact "
        + " ".join(f"{score}/{total}" for score in scores)
        + f"  mean {sum(scores) / len(scores):.2f})"
    )
    for entry_id, failures in sorted(misses.items()):
        row = failures[0]
        print(
            f"\n  {entry_id} [{', '.join(row['tags'])}] failed {len(failures)}/{args.repeat}"
        )
        print(f"    raw: {row['raw']}")
        for variant in {failure["cleaned"] for failure in failures}:
            print(
                "\n".join(
                    f"    {line}"
                    for line in unified_diff(
                        row["expect"].splitlines(),
                        variant.splitlines(),
                        fromfile="expect",
                        tofile="cleaned",
                        lineterm="",
                    )
                )
            )
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(
                {
                    "label": label,
                    "model": model,
                    "prompt": str(args.prompt),
                    "raw": str(args.raw),
                    "bundleID": args.bundle_id,
                    "additionalInstructions": args.additional_instructions,
                    "scores": scores,
                    "judged": judged,
                    "rubric": judge.RUBRIC_ID,
                    "entries": total,
                    "failCounts": {
                        entry_id: len(failures)
                        for entry_id, failures in sorted(misses.items())
                    },
                    "repeats": repeats,
                },
                indent=2,
                ensure_ascii=False,
            )
            + "\n",
            encoding="utf-8",
        )
    return 0


def run_stage2(args: argparse.Namespace) -> int:
    """The dictionary gate, in `asr-replay`'s shape so `score_corpus.py sweep` scores it."""
    prompt = prompt_text(args)
    work = entries(STAGE2, args.raw, keep_excluded=True)
    vocabulary: list[str] = []
    for entry in work:
        for term in entry.get("wants", []):
            if term not in vocabulary:
                vocabulary.append(term)
    with transport(
        args.provider, args.model, args.workers, calls=len(work), metered=args.metered
    ) as complete:
        rows = fan_out(work, prompt, complete, vocabulary, args.workers)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        "".join(
            json.dumps(
                {"id": row["id"], "transcript": row["cleaned"], "latencyMs": 0.0},
                ensure_ascii=False,
            )
            + "\n"
            for row in sorted(rows, key=lambda row: row["id"])
        ),
        encoding="utf-8",
    )
    print(f"Wrote {args.output}")
    return 0


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    stages = parser.add_subparsers(dest="command", required=True)
    for name in ("stage3", "stage2"):
        stage = stages.add_parser(name)
        stage.add_argument("--prompt", type=Path, required=True)
        transport_arguments(stage)
        stage.add_argument("--output", type=Path)
        stage.add_argument("--label")
        stage.add_argument(
            "--additional-instructions",
            help="Stage the user's own instructions, as the app appends them. `@path` reads a "
            "file. Absent, the arm measures the built-in rules alone.",
        )
    stages.choices["stage3"].add_argument(
        "--bundle-id",
        help="Stage TARGET_BUNDLE_ID, as the app does. A field case needs the app it was "
        "dictated into; the scripted stages are written to need none.",
    )
    stages.choices["stage3"].add_argument("--repeat", type=int, default=1)
    stages.choices["stage3"].add_argument("--entry", action="append")
    stages.choices["stage3"].add_argument(
        "--raw",
        type=Path,
        help="Another engine's replay of the same scripts, such as one `bakeoff.py` wrote. "
        "Defaults to Parakeet's, for the frozen set or, with --holdout, the holdout.",
    )
    stages.choices["stage2"].add_argument("--raw", type=Path, default=STAGE2_RAW)
    stages.choices["stage3"].add_argument(
        "--script",
        type=Path,
        default=STAGE3,
        help="The scripts to score against; the recorded holdout is judged, never searched.",
    )
    stages.choices["stage3"].add_argument(
        "--holdout",
        action="store_const",
        const=True,
        help="Shorthand for the recorded holdout's scripts and, unless --raw names another "
        "engine's, its Parakeet replays.",
    )
    stages.choices["stage3"].add_argument(
        "--include-excluded",
        action="store_true",
        help="Score all 27, including the two entries Parakeet's raw cannot support.",
    )
    stages.choices["stage3"].set_defaults(run=run_stage3)
    stages.choices["stage2"].set_defaults(run=run_stage2)
    return parser.parse_args()


if __name__ == "__main__":
    args = arguments()
    if args.command == "stage3":
        if args.holdout:
            args.script = STAGE3_HOLDOUT
            args.raw = args.raw or STAGE3_HOLDOUT_RAW
        else:
            args.raw = args.raw or STAGE3_RAW
    raise SystemExit(args.run(args))
