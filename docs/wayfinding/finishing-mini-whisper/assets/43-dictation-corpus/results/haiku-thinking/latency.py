#!/usr/bin/env python3
"""Serial, interleaved latency A/B: `thinking` omitted against `{"type": "disabled"}`.

Every frozen, holdout, and layout entry, both arms back to back with the order alternating, one
request in flight at a time, so the two arms see the same network and the same server load.

  ./latency.py runs/latency.jsonl 3
"""

from datetime import UTC, datetime
import json
import os
from pathlib import Path
import statistics
import sys

H = Path(__file__).resolve().parent.parent / "prompt-tuning-haiku"
OUT = Path(sys.argv[1])
REPEAT = int(sys.argv[2])
sys.path.insert(0, str(H))
sys.path.insert(0, str(H.parent.parent))
import corpus_cleanup  # noqa: E402
import tune  # noqa: E402

prompt = corpus_cleanup.system_message(
    corpus_cleanup.built_in_prompt(corpus_cleanup.CLEANUP_PROMPT_SWIFT),
    None,
    corpus_cleanup.CLEANUP_PROMPT_SWIFT,
)
work = (
    tune.entries(tune.STAGE3, tune.STAGE3_RAW, keep_excluded=False)
    + tune.entries(tune.STAGE3_HOLDOUT, tune.STAGE3_HOLDOUT_RAW, keep_excluded=False)
    + tune.entries(
        tune.CORPUS / "stage3-layout.jsonl",
        H.parent / "prompt-tuning-r4/stage3-layout-raw.jsonl",
        keep_excluded=True,
    )
)
ARMS = {"default": {}, "disabled": {"thinking": {"type": "disabled"}}}
key = os.environ["ANTHROPIC_CREDITS_APIKEY"]
rows = []
spent = {"in": 0, "out": 0}
for rep in range(REPEAT):
    for index, entry in enumerate(work):
        user = corpus_cleanup.user_message(
            entry["raw"], (entry.get("context") or {}).get("before"), [], None
        )
        order = list(ARMS) if (rep + index) % 2 == 0 else list(reversed(ARMS))
        for arm in order:
            usage = {}
            content, ms, waited = corpus_cleanup.complete(
                "https://api.anthropic.com/v1",
                key,
                "claude-haiku-5-5",
                prompt,
                user,
                90.0,
                ARMS[arm],
                4,
                on_usage=usage.update,
            )
            spent["in"] += usage["prompt_tokens"]
            spent["out"] += usage["completion_tokens"]
            rows.append(
                {
                    "rep": rep,
                    "id": entry["id"],
                    "arm": arm,
                    "ms": round(ms, 1),
                    "throttledS": waited,
                    "out": usage["completion_tokens"],
                    "in": usage["prompt_tokens"],
                    "chars": len(content),
                }
            )
        print(
            rep,
            entry["id"],
            *(f"{r['arm']} {r['ms']:.0f}ms/{r['out']}t" for r in rows[-2:]),
            flush=True,
        )

OUT.write_text("".join(json.dumps(r) + "\n" for r in rows))


def q(values, p):
    values = sorted(values)
    return values[min(len(values) - 1, round(p * (len(values) - 1)))]


for arm in ARMS:
    mine = [r for r in rows if r["arm"] == arm]
    ms = [r["ms"] for r in mine]
    out = [r["out"] for r in mine]
    print(
        f"{arm:9} n={len(mine)} median {statistics.median(ms):.0f} ms  p90 {q(ms, 0.9):.0f}  p95 {q(ms, 0.95):.0f}"
        f"  max {max(ms):.0f}  mean {statistics.mean(ms):.0f}  out tokens median {statistics.median(out)} mean {statistics.mean(out):.1f} max {max(out)}"
    )
pairs = {}
for r in rows:
    pairs.setdefault((r["rep"], r["id"]), {})[r["arm"]] = r
deltas = [p["default"]["ms"] - p["disabled"]["ms"] for p in pairs.values()]
print(
    f"paired default-disabled: median {statistics.median(deltas):.0f} ms, mean {statistics.mean(deltas):.0f} ms,"
    f" disabled faster in {sum(d > 0 for d in deltas)}/{len(deltas)}"
)
thought = [p for p in pairs.values() if p["default"]["out"] > p["disabled"]["out"] + 20]
print(
    f"default spent >20 more output tokens (i.e. thought) on {len(thought)}/{len(pairs)} pairs"
)
usd = (spent["in"] * 0.10 + spent["out"] * 0.50) / 1e6
print(f"SPENT {len(rows)} calls, {spent['in']} in + {spent['out']} out, ${usd:.4f}")
with (H / "spend.jsonl").open("a") as sink:
    sink.write(
        json.dumps(
            {
                "at": datetime.now(UTC).isoformat(timespec="seconds"),
                "command": " ".join(sys.argv),
                "provider": "anthropic-api",
                "model": "claude-haiku-5-5",
                "calls": len(rows),
                "inputTokens": spent["in"],
                "outputTokens": spent["out"],
                "usd": round(usd, 6),
                "pricePerMTok": {"input": 0.10, "output": 0.50},
            }
        )
        + "\n"
    )
