#!/usr/bin/env python3
"""Replay real dictations from a channel's History under each screen-context and thinking arm.

Expanded context stores what it read beside each dictation: the screen text, the text Vision
recognized, and the window's screenshot. This replays every entry that has them through the app's
own prompt, lifted from CleanupPrompt.swift, once per context arm:

  field   what the app sends with Expanded context off: transcript, field, bundle
  text    what the app sends with it on: + SCREEN_CONTEXT, from tmux or Accessibility, or from
          Vision's recognized text when the target reported none
  image   transcript, bundle, and the screenshot alone (no field, no screen text)
  both    text's message with the screenshot attached
  shot    field's message with the screenshot attached, as the app's Screenshot setting sends it

crossed with each thinking arm:

  default what the app sends today: no reasoning control, so the model thinks as it likes
  off     the provider's own way to turn reasoning off, chosen by the endpoint's host:
          Anthropic   `thinking: {"type": "disabled"}`, the one control its OpenAI-compatible
                      endpoint honours; it ignores `reasoning_effort` and turns `budget_tokens`
                      into adaptive thinking
          OpenAI      `reasoning_effort: "none"`; GPT-6 models refuse `minimal`
          Cerebras    `reasoning_effort: "low"`, the least gpt-oss-120b accepts; it refuses
                      `none` and `minimal`, so its "off" still reasons a little
  any other  sent as `reasoning_effort`, such as `high`, for a provider that takes one

Any directory shaped like History works, so hand-written scenes replay the same way as captured
ones. With --field-cases, entries adjudicated in that file (keyed by `source`, the history id)
are scored: exactly against `expect`, or by substrings, every `must` present and no `forbid`.
The score is of the cleanup's output, before the field join re-cases and spaces it for the paste.
A regression is a case field+default passes and the arm fails.

  ./replay_history.py --history ~/Library/Application\\ Support/MiniWhisper\\ Dev/History \\
      --endpoint https://api.anthropic.com/v1 --model claude-haiku-5-5 --api-key-env KEY
"""

from __future__ import annotations

import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import sys
import textwrap
import time
import urllib.error
import urllib.parse
import urllib.request

REPO = Path(__file__).resolve().parents[3]
PROMPT_SWIFT = (
    REPO / "Packages/TranscriptCleanup/Sources/TranscriptCleanup/CleanupPrompt.swift"
)
ARMS = ("field", "text", "image", "both", "shot")
THINKING = ("default", "off")
OFF = {
    "api.anthropic.com": {"thinking": {"type": "disabled"}},
    "api.openai.com": {"reasoning_effort": "none"},
    "api.cerebras.ai": {"reasoning_effort": "low"},
}
BASELINE = ("field", "default")
RETRYABLE = (429, 500, 502, 503, 529)
# CleanupResponseShaping drops these blocks whole before delivery, so a scratchpad is not output.
REASONING_BLOCK = re.compile(
    r"<(think|thinking|reasoning|reflection)>.*?</\1>", re.DOTALL | re.IGNORECASE
)


def lift_prompts() -> tuple[str, str, str]:
    """The built-in prompt, its screen-context variant, and the sentence that introduces
    Additional Instructions, exactly as the app assembles them."""
    source = PROMPT_SWIFT.read_text(encoding="utf-8")
    built_in = textwrap.dedent(
        re.search(
            r'public static let builtIn = """\n(.*?)\n  """', source, re.DOTALL
        ).group(1)
    )
    rules = {
        name: re.search(rf'static let {name} =\s*"(.*?)"\n', source, re.DOTALL).group(1)
        for name in ("fieldContextRule", "screenContextRule")
    }
    assert rules["fieldContextRule"] in built_in, (
        "builtIn lost the rule screen context edits"
    )
    preamble = re.search(
        r"\n    (Additional Instructions follow\..*?)\n", source
    ).group(1)
    return (
        built_in,
        built_in.replace(rules["fieldContextRule"], rules["screenContextRule"]),
        preamble,
    )


def system_message(rules: str, preamble: str, instructions: str) -> str:
    """Mirrors CleanupPrompt.systemMessage."""
    instructions = instructions.strip()
    return f"{rules}\n\n{preamble}\n\n{instructions}" if instructions else rules


def tagged(tag: str, body: str) -> str:
    return f"<{tag}>\n{body}\n</{tag}>"


def user_message(entry: dict, arm: str) -> str:
    """Mirrors CleanupPrompt.userMessage's block order; an absent block is omitted whole."""
    blocks = [tagged("TRANSCRIPT", entry["original"]["text"])]
    field = entry.get("fieldContext")
    if field and arm != "image":
        slices = [
            tagged(tag, field[key])
            for tag, key in (
                ("BEFORE_CARET", "before"),
                ("SELECTED_TEXT", "selected"),
                ("AFTER_CARET", "after"),
            )
            if field.get(key)
        ]
        if slices:
            blocks.append(tagged("FOCUSED_TEXT_CONTEXT", "\n".join(slices)))
    screen = entry.get("screenContext") or {}
    visible = None
    if arm in ("text", "both"):
        visible = (screen.get("structured") or {}).get("text") or screen.get(
            "recognizedText"
        )
    if visible:
        title = screen.get("windowTitle")
        parts = ([tagged("WINDOW_TITLE", title)] if title else []) + [
            tagged("VISIBLE_TEXT", visible)
        ]
        blocks.append(tagged("SCREEN_CONTEXT", "\n".join(parts)))
    bundle = (entry.get("targetApp") or {}).get("bundleID")
    if bundle:
        blocks.append(tagged("TARGET_BUNDLE_ID", bundle))
    return "\n\n".join(blocks)


def available(entry: dict, arm: str, media: Path) -> bool:
    screen = entry.get("screenContext") or {}
    return (
        {
            "field": True,
            "text": bool(
                (screen.get("structured") or {}).get("text")
                or screen.get("recognizedText")
            ),
            "image": bool(entry.get("screenshot"))
            and (media / f"{entry['id']}.jpg").exists(),
        }["image" if arm == "shot" else arm]
        if arm != "both"
        else available(entry, "text", media) and available(entry, "image", media)
    )


def reasoning(endpoint: str, thinking: str) -> dict:
    if thinking == "default":
        return {}
    if thinking == "off":
        return OFF[urllib.parse.urlparse(endpoint).hostname]
    return {"reasoning_effort": thinking}


def complete(args: argparse.Namespace, system: str, user, thinking: str) -> dict:
    body = json.dumps(
        {
            "model": args.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "stream": False,
            **reasoning(args.endpoint, thinking),
            **({"service_tier": args.service_tier} if args.service_tier else {}),
        }
    ).encode()
    headers = {
        "Content-Type": "application/json",
        "User-Agent": "miniwhisper-screen-replay/1",
    }
    if args.api_key_env:
        headers["Authorization"] = f"Bearer {os.environ[args.api_key_env]}"
    request = urllib.request.Request(
        f"{args.endpoint.rstrip('/')}/chat/completions", data=body, headers=headers
    )
    for attempt in range(4):
        started = time.perf_counter()
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = json.load(response)
            usage = payload.get("usage") or {}
            content = payload["choices"][0]["message"].get("content") or ""
            return {
                # A reasoning model can spend its turn thinking and return no content field at all.
                "output": REASONING_BLOCK.sub("", content).strip(),
                "scratch": "\n".join(
                    m.group(0) for m in REASONING_BLOCK.finditer(content)
                ),
                "ms": (time.perf_counter() - started) * 1000,
                "prompt_tokens": usage.get("prompt_tokens"),
                "completion_tokens": usage.get("completion_tokens"),
            }
        except urllib.error.HTTPError as error:
            if error.code not in RETRYABLE or attempt == 3:
                raise
            time.sleep(2**attempt)
        # A connection that never answered says nothing about the model, so it is tried again.
        except urllib.error.URLError, TimeoutError:
            if attempt == 3:
                raise
            time.sleep(2**attempt)


def verdict(case: dict | None, output: str) -> bool | None:
    if case is None:
        return None
    if "expect" in case:
        return output == case["expect"]
    return all(term in output for term in case.get("must", [])) and not any(
        term in output for term in case.get("forbid", [])
    )


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(fraction * len(ordered)))]


def summarize(
    results: list[dict], arms: list[str], thinking: list[str], timeout_ms: float
) -> None:
    baseline = {
        (r["id"], r["rep"]): r["pass"]
        for r in results
        if (r["arm"], r["thinking"]) == BASELINE and r["pass"] is not None
    }
    print(
        f"\n{'arm':<6} {'thinking':<8} {'n':>4} {'pass':>9} {'regress':>7} {'out tok p50':>11} "
        f"{'p50 ms':>7} {'p95 ms':>7} {'>timeout':>8}"
    )
    for arm in arms:
        for mode in thinking:
            rows = [r for r in results if r["arm"] == arm and r["thinking"] == mode]
            if not rows:
                continue
            scored = [r for r in rows if r["pass"] is not None]
            regressions = sum(
                1 for r in scored if baseline.get((r["id"], r["rep"])) and not r["pass"]
            )
            tokens = [
                r["completion_tokens"]
                for r in rows
                if r["completion_tokens"] is not None
            ]
            latency = [r["ms"] for r in rows]
            print(
                f"{arm:<6} {mode:<8} {len(rows):>4} "
                f"{sum(r['pass'] for r in scored):>4}/{len(scored):<4} {regressions:>7} "
                f"{percentile(tokens, 0.5) if tokens else '-':>11} "
                f"{percentile(latency, 0.5):>7.0f} {percentile(latency, 0.95):>7.0f} "
                f"{sum(ms > timeout_ms for ms in latency):>8}"
            )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "--history",
        type=Path,
        required=True,
        help="The channel's History directory, holding history.json and audio/.",
    )
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument(
        "--api-key-env", help="Environment variable holding the key, if any."
    )
    parser.add_argument(
        "--field-cases", type=Path, help="Adjudicated entries to score."
    )
    parser.add_argument("--arms", default=",".join(ARMS))
    parser.add_argument("--thinking", default=",".join(THINKING))
    parser.add_argument(
        "--service-tier",
        help="OpenAI's processing tier, such as `fast`; omitted when unset.",
    )
    parser.add_argument("--reps", type=int, default=1)
    parser.add_argument(
        "--workers",
        type=int,
        default=1,
        help="Requests in flight; more than one makes latency a queueing number.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=10,
        help="The app's cleanup timeout in seconds, to count the runs past it.",
    )
    parser.add_argument(
        "--additional-instructions",
        default="",
        help="The user's Additional Instructions, appended as the app does.",
    )
    parser.add_argument(
        "--screen-prompt",
        type=Path,
        help="Replaces the screen-context variant of the built-in prompt, to try a rewording.",
    )
    parser.add_argument("--output", type=Path, help="Write every result as JSONL here.")
    args = parser.parse_args()
    arms = args.arms.split(",")
    thinking = args.thinking.split(",")

    built_in, screen_prompt, preamble = lift_prompts()
    if args.screen_prompt:
        screen_prompt = args.screen_prompt.read_text(encoding="utf-8").strip()
    systems = {
        False: system_message(built_in, preamble, args.additional_instructions),
        True: system_message(screen_prompt, preamble, args.additional_instructions),
    }
    media = args.history / "audio"
    entries = [
        entry
        for entry in json.loads((args.history / "history.json").read_text())["entries"]
        if entry.get("original")
        and (entry.get("screenContext") or entry.get("screenshot"))
    ]
    if not entries:
        sys.exit(
            "No entry carries screen context; dictate with Expanded context on first."
        )
    cases = {}
    if args.field_cases:
        for line in args.field_cases.read_text().splitlines():
            if line.strip():
                case = json.loads(line)
                cases[case["source"]] = case

    def run(job: tuple[dict, str, str, int]) -> dict:
        entry, arm, mode, rep = job
        user = user_message(entry, arm)
        if arm in ("image", "both", "shot"):
            data = base64.b64encode(
                (media / f"{entry['id']}.jpg").read_bytes()
            ).decode()
            user = [
                {"type": "text", "text": user},
                {
                    "type": "image_url",
                    "image_url": {"url": f"data:image/jpeg;base64,{data}"},
                },
            ]
        result = complete(args, systems[arm != "field"], user, mode)
        return {
            "id": entry["id"],
            "arm": arm,
            "thinking": mode,
            "rep": rep,
            **result,
            "pass": verdict(cases.get(entry["id"]), result["output"]),
        }

    jobs = [
        (entry, arm, mode, rep)
        for entry in entries
        for arm in arms
        if available(entry, arm, media)
        for mode in thinking
        for rep in range(args.reps)
    ]
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = list(pool.map(run, jobs))

    for entry in entries:
        print(
            f"\n=== {entry['id']}  {(entry.get('targetApp') or {}).get('bundleID', '?')}"
        )
        print(f"    raw: {entry['original']['text']}")
        for r in (r for r in results if r["id"] == entry["id"]):
            mark = "" if r["pass"] is None else ("PASS " if r["pass"] else "FAIL ")
            print(
                f"  {r['arm']:<5} {r['thinking']:<7} {r['ms']:6.0f} ms "
                f"{r['completion_tokens'] or 0:>5} tok  {mark}{r['output']}"
            )
    if args.output:
        args.output.write_text(
            "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in results)
        )
    summarize(results, arms, thinking, args.timeout * 1000)
    return 0


if __name__ == "__main__":
    sys.exit(main())
