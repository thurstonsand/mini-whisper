#!/usr/bin/env python3
"""A concurrent `complete()` over the Claude subscription, for the search loops.

`corpus_cleanup_agent_sdk.py` measures one entry at a time, because latency is what it is
measuring. A prompt search measures nothing but the score, fans its entries out across threads,
and pays about ten dollars a run against `api.anthropic.com`. This pool is the same transport
with the serial constraint lifted: one `AgentSdkPipe` per worker thread, each pipe answering one
request at a time, checked out of a queue and returned.

Fresh mode only, and not as a default — as the invariant. A reused session accumulates every
prior transcript and every prior answer into the next entry's context, which
[the round-3 run](../results/agent-sdk-haiku/) caught changing the answers. A search that scores
25 entries in one conversation would be scoring the conversation. Each entry here gets its own
Claude Code subprocess, and `sessions()` reports how many distinct session IDs the run actually
used so the isolation is a measurement rather than a claim.

Thinking is disabled for the same reason the runner disables it: adaptive thinking costs 4.4 s
and two entries of accuracy on work that is a reflex.
"""

from __future__ import annotations

from pathlib import Path
from queue import SimpleQueue
import statistics
import sys
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

from corpus_cleanup_agent_sdk import AgentSdkPipe


class AgentSdkPool:
    """`workers` subscription pipes behind one `complete()` with `corpus_cleanup.complete`'s
    signature, so a caller cannot tell it from the HTTP transport."""

    def __init__(self, model: str, workers: int, timeout: float = 120.0) -> None:
        self.model = model
        self.pipes = [
            AgentSdkPipe(model, "fresh", "off", timeout, announce=index == 0)
            for index in range(workers)
        ]
        self.free: SimpleQueue[AgentSdkPipe] = SimpleQueue()
        for pipe in self.pipes:
            self.free.put(pipe)

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
        pipe = self.free.get()
        try:
            return pipe.complete(
                endpoint, api_key, model, system, user, timeout, extra_body, retries
            )
        finally:
            self.free.put(pipe)

    def timings(self) -> list[dict[str, Any]]:
        return [row for pipe in self.pipes for row in pipe.timings]

    def sessions(self) -> int:
        return len({row["sessionId"] for row in self.timings()})

    def report(self) -> str:
        """Per-call latency, honestly labelled: these calls overlapped, so this is what one call
        cost while `workers` of them were in flight, not what a serial dictation would pay."""
        rows = self.timings()
        if not rows:
            return f"{self.model}: no calls"
        wall = sorted(row["totalMs"] for row in rows)
        api = sorted(row["apiMs"] for row in rows)
        return (
            f"{self.model} via subscription: {len(rows)} calls across {len(self.pipes)} pipes, "
            f"{self.sessions()} distinct sessions; "
            f"wall median {statistics.median(wall):.0f} ms "
            f"(min {wall[0]:.0f}, max {wall[-1]:.0f}), "
            f"model round trip median {statistics.median(api):.0f} ms"
        )

    def close(self) -> None:
        for pipe in self.pipes:
            pipe.close()
