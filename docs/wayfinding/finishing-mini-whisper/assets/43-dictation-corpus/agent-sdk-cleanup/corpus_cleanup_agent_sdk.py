#!/usr/bin/env python3
"""Replay stage 3 through the Claude subscription instead of a metered endpoint.

`corpus_cleanup.py` measures cleanup over HTTP; Anthropic no longer sells the subscription that
way, so the only route to a Max-plan Haiku is Claude Code, driven by the Claude Agent SDK. This
runner keeps every measured thing identical — the same `CleanupPrompt.builtIn` lifted out of the
Swift source, the same tagged user message, the same response shaping, the same score file — and
swaps only the transport, so `results/agent-sdk-haiku/` compares line for line against the
API-direct run in `results/built-in-r2/`.

The swap is literally one line: `corpus_cleanup.complete` is rebound to a method on the SDK pipe
before `corpus_cleanup.run_stage3` is called. Scoring, the report shape, and the output files are
then the harness's own, and cannot drift from it.

Two arms, because the SDK charges a fixed cost an HTTP endpoint does not:

  --mode fresh    one Claude Code subprocess per entry, no shared history — the app's shape.
  --mode session  one subprocess for the whole run, every entry another turn in one conversation.

And `--thinking`, because Claude Code enables adaptive thinking by default and the endpoint this
run is compared against does not: `off` is the parity arm, `on` is what the SDK does unasked.

Subscription auth only. ANTHROPIC_APIKEY and its siblings are scrubbed out of the child's
environment, and the run aborts unless Claude Code reports a first-party subscription account.

  ./corpus_cleanup_agent_sdk.py ../stage3-polish.jsonl \\
      --raw ../results/built-in-r2/stage3-raw.jsonl --results-dir ../results/agent-sdk-haiku
"""

from __future__ import annotations

import argparse
from itertools import pairwise
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time
from typing import Any

CORPUS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(CORPUS))

import corpus_cleanup  # noqa: E402

CLIENT = Path(__file__).resolve().parent / "agent_sdk_client.mjs"
# Anything the SDK would read a key out of. Scrubbed so a subscription measurement cannot silently
# become a metered one; `.env` in this repo does carry an ANTHROPIC_APIKEY.
API_KEY_VARIABLES = (
    "ANTHROPIC_API_KEY",
    "ANTHROPIC_APIKEY",
    "ANTHROPIC_AUTH_TOKEN",
    "CLAUDE_CODE_OAUTH_TOKEN",
    "ANTHROPIC_BASE_URL",
)


class AgentSdkPipe:
    """One `agent_sdk_client.mjs` process, spoken to one request at a time.

    Node holds the SDK, so the harness holds a pipe. Keeping the process alive across the run
    charges the SDK's module load once instead of 27 times; every per-entry cost that remains —
    the Claude Code subprocess, its session init, the model round trip — is the thing under test.
    """

    def __init__(
        self,
        model: str,
        mode: str,
        thinking: str,
        timeout: float,
        announce: bool = True,
    ) -> None:
        environment = {
            key: value
            for key, value in os.environ.items()
            if key not in API_KEY_VARIABLES
        }
        self.timeout = timeout
        self.process = subprocess.Popen(
            [
                "node",
                str(CLIENT),
                "--mode",
                mode,
                "--model",
                model,
                "--thinking",
                thinking,
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            env=environment,
            text=True,
            bufsize=1,
        )
        self.timings: list[dict[str, Any]] = []
        self.init: dict[str, Any] | None = None
        self.probe = self.receive()
        if self.probe["type"] != "probe":
            raise RuntimeError(f"expected an auth probe, got {self.probe}")
        account = self.probe["account"]
        if account.get("apiProvider") != "firstParty" or not account.get(
            "subscriptionType"
        ):
            raise RuntimeError(f"not a subscription account: {account}")
        if not self.probe["serves"]:
            raise RuntimeError(f"Claude Code does not serve {model}")
        # A pool of these announces once; twelve identical subscription lines are not evidence.
        if not announce:
            return
        print(
            f"Subscription: {account['subscriptionType']} ({account.get('email')}); "
            f"model resolves to {self.probe['resolved']}"
        )

    def receive(self) -> dict[str, Any]:
        line = self.process.stdout.readline()
        if not line:
            raise RuntimeError(
                f"agent_sdk_client.mjs exited ({self.process.wait()}) before answering"
            )
        message = json.loads(line)
        if message["type"] == "error":
            raise RuntimeError(message["message"])
        return message

    def complete(
        self,
        endpoint: str,
        api_key: str | None,
        model: str,
        system: str,
        user: str,
        timeout: float,
        extra_body: dict[str, Any],
        retries: int,
    ) -> tuple[str, float, float]:
        """`corpus_cleanup.complete`'s signature, so `clean()` cannot tell the difference. The SDK
        exposes no temperature or token switches, so a non-empty `extra_body` is a mistake rather
        than something to silently drop; the subscription is not rate limited per request, so the
        throttled seconds are always zero."""
        if extra_body:
            raise ValueError("the Agent SDK takes no extra request body")
        entry_id = f"entry-{len(self.timings) + 1}"
        started = time.perf_counter()
        self.process.stdin.write(
            json.dumps(
                {"id": entry_id, "system": system, "user": user}, ensure_ascii=False
            )
            + "\n"
        )
        self.process.stdin.flush()
        message = self.receive()
        while message["type"] == "init":
            self.init = message
            message = self.receive()
        elapsed = (time.perf_counter() - started) * 1_000
        self.timings.append({key: message[key] for key in message if key != "text"})
        return message["text"], elapsed, 0.0

    def close(self) -> None:
        self.process.stdin.close()
        self.process.wait(timeout=self.timeout)


def per_turn_api(timings: list[dict[str, Any]], mode: str) -> list[float]:
    """A reused session reports `duration_api_ms` for the session rather than the turn, so the
    figure climbs monotonically; differencing it recovers the round trip each entry paid."""
    charged = [row["apiMs"] for row in timings]
    if mode != "session":
        return charged
    return [charged[0]] + [later - earlier for earlier, later in pairwise(charged)]


def summarize(values: list[float]) -> dict[str, float]:
    ordered = sorted(values)
    return {
        "medianMs": round(statistics.median(ordered), 1),
        "meanMs": round(statistics.fmean(ordered), 1),
        "minMs": round(ordered[0], 1),
        "maxMs": round(ordered[-1], 1),
    }


def write_timing(
    pipe: AgentSdkPipe, destination: Path, arguments: argparse.Namespace
) -> None:
    """The startup tax, separated from the model round trip.

    `apiMs` is what the endpoint charged; everything above it is the SDK's own — spawning Claude
    Code, session init, the control handshake. That difference is the whole question this arm was
    run to answer, and it has no home in the harness's score file."""
    api = per_turn_api(pipe.timings, arguments.mode)
    total = [row["totalMs"] for row in pipe.timings]
    overhead = [
        row["totalMs"] - charged for row, charged in zip(pipe.timings, api, strict=True)
    ]
    init = [row["initMs"] for row in pipe.timings if row["initMs"] is not None]
    report = {
        "model": arguments.model,
        "mode": arguments.mode,
        "thinking": arguments.thinking,
        "account": pipe.probe["account"],
        "resolvedModel": pipe.probe["resolved"],
        "session": pipe.init,
        "entries": len(pipe.timings),
        "wallLatency": summarize(total),
        "apiLatency": summarize(api),
        "sdkOverhead": summarize(overhead),
        "sessionInit": summarize(init) if init else None,
        "distinctSessions": len({row["sessionId"] for row in pipe.timings}),
        "entriesDetail": pipe.timings,
    }
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"\nWall {report['wallLatency']}\nAPI  {report['apiLatency']}")
    print(f"SDK overhead {report['sdkOverhead']}")
    print(f"Wrote {destination}")


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", type=Path)
    parser.add_argument(
        "--raw", type=Path, required=True, help="asr-replay output for the same stage."
    )
    parser.add_argument("--model", default="claude-haiku-4-5")
    parser.add_argument(
        "--mode",
        choices=("fresh", "session"),
        default="fresh",
        help="fresh: a Claude Code subprocess per entry. session: one for the whole run.",
    )
    parser.add_argument(
        "--thinking",
        choices=("off", "on"),
        default="off",
        help="off matches the HTTP endpoint this run is compared against.",
    )
    parser.add_argument("--entry", action="append", help="Replay only these IDs.")
    parser.add_argument("--timeout", type=float, default=120.0)
    parser.add_argument("--results-dir", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = arguments()
    pipe = AgentSdkPipe(args.model, args.mode, args.thinking, args.timeout)
    # The one substitution. Everything downstream of it is the harness's own code, so the score
    # file, the JSONL, and the failure diffs are the same artifacts the API-direct run produced.
    corpus_cleanup.complete = pipe.complete
    stage_arguments = argparse.Namespace(
        stage=args.stage,
        raw=args.raw,
        endpoint=f"claude-agent-sdk://subscription?mode={args.mode}&thinking={args.thinking}",
        api_key_env="ANTHROPIC_APIKEY",
        no_api_key=True,
        model=[args.model],
        timeout=args.timeout,
        retries=0,
        prompt="built-in",
        entry=args.entry,
        prompt_source=corpus_cleanup.CLEANUP_PROMPT_SWIFT,
        results_dir=args.results_dir,
    )
    try:
        status = corpus_cleanup.run_stage3(stage_arguments)
    finally:
        pipe.close()
    slug = args.model.replace("/", "-")
    write_timing(pipe, args.results_dir / f"stage3-{slug}-sdk-timing.json", args)
    return status


if __name__ == "__main__":
    raise SystemExit(main())
