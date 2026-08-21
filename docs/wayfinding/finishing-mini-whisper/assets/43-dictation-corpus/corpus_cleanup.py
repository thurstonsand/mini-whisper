#!/usr/bin/env python3
"""Replay a stage's raw ASR transcripts through the real cleanup prompt.

The sibling harness in 38-cleanup-model-benchmark replays private History originals against an
ad-hoc prompt to compare model latency. This one replays the corpus: known input, known intended
output, so a model's cleanup can be scored rather than only read. The system prompt is lifted out
of CleanupPrompt.swift at run time and the user message is assembled the way CleanupPrompt does
it, because a prompt copied into Python is a prompt that silently stops matching the app.

Stage 3 is scored here, against `expect`. Stage 2 is not: its cleaned transcripts are written in
asr-replay's own shape so `score_corpus.py sweep` scores them exactly as it scores an engine run,
which is the whole point — an arm that ends in cleanup and an arm that ends in the sidecar are
compared on the same final text.

  ./corpus_cleanup.py stage3 stage3-polish.jsonl --raw results/built-in/stage3-raw.jsonl \\
      --endpoint https://aig.thurstons.house/v1 --api-key-env AIG_APIKEY \\
      --model gpt-5.6-luna --results-dir results/built-in

  ./corpus_cleanup.py stage2 stage2-dictionary.jsonl --raw results/built-in/stage2-bare.jsonl \\
      --dictionary-from-wants --endpoint ... --model gpt-5.6-luna \\
      --results-dir results/dictionary-three-way --arm bare
"""

from __future__ import annotations

import argparse
from difflib import unified_diff
import json
import os
from pathlib import Path
import re
import statistics
import sys
import textwrap
import time
from typing import Any
import urllib.error
import urllib.request

CLEANUP_PROMPT_SWIFT = (
    Path(__file__).resolve().parents[5]
    / "Packages/TranscriptCleanup/Sources/TranscriptCleanup/CleanupPrompt.swift"
)
BUILT_IN = re.compile(r'public static let builtIn = """\n(.*?)\n  """', re.DOTALL)


def built_in_prompt(source: Path) -> str:
    """The app's own system message. Additional user instructions are deliberately excluded: the
    corpus `expect` values are written against the built-in rules alone."""
    match = BUILT_IN.search(source.read_text(encoding="utf-8"))
    if match is None:
        sys.exit(f"{source}: no `builtIn` prompt literal found")
    return textwrap.dedent(match.group(1))


def tagged(tag: str, body: str) -> str:
    return f"<{tag}>\n{body}\n</{tag}>"


def user_message(
    transcript: str, context_before: str | None, vocabulary: list[str]
) -> str:
    """Mirrors CleanupPrompt.userMessage, including its field order. The corpus stages no bundle
    identifier, and an absent field is omitted whole rather than sent empty."""
    blocks = [tagged("TRANSCRIPT", transcript)]
    if context_before:
        blocks.append(
            tagged("FOCUSED_TEXT_CONTEXT", tagged("BEFORE_CARET", context_before))
        )
    if vocabulary:
        blocks.append(
            tagged("DICTIONARY", "\n".join(f"- {term}" for term in vocabulary))
        )
    return "\n\n".join(blocks)


REASONING_TAGS = ("think", "thinking", "reasoning", "reflection")
OUTPUT_TAGS = ("answer", "output", "response", "text", "transcript")
LEADING_LABELS = (
    "cleaned transcript",
    "cleaned text",
    "edited transcript",
    "edited text",
    "transcript",
    "output",
    "result",
    "final text",
)
QUOTE_PAIRS = (('"', '"'), ("'", "'"), ("\u201c", "\u201d"), ("\u2018", "\u2019"))


def shape(raw: str) -> str:
    """The obvious wrappers CleanupResponseShaping peels, so a model is scored on its edit rather
    than on its packaging. Kept in step with
    Packages/TranscriptCleanup/Sources/TranscriptCleanup/CleanupResponse.swift."""
    text = raw.strip()
    for _ in range(4):
        peeled = text
        for tag in REASONING_TAGS:
            peeled = re.sub(
                rf"<{tag}>.*?</{tag}>", "", peeled, flags=re.DOTALL | re.I
            ).strip()
        for tag in OUTPUT_TAGS:
            match = re.fullmatch(
                rf"<{tag}>(.*)</{tag}>", peeled, flags=re.DOTALL | re.I
            )
            if match:
                peeled = match.group(1).strip()
        lines = peeled.split("\n")
        if (
            len(lines) >= 2
            and lines[0].startswith("```")
            and lines[-1].startswith("```")
        ):
            peeled = "\n".join(lines[1:-1]).strip()
        head, separator, tail = peeled.partition(":")
        if separator and head.lower().strip(" \t*#-") in LEADING_LABELS:
            peeled = tail.lstrip("*").strip()
        if len(peeled) >= 2:
            for opening, closing in QUOTE_PAIRS:
                inner = peeled[1:-1]
                if (
                    peeled[0] == opening
                    and peeled[-1] == closing
                    and opening not in inner
                ):
                    peeled = inner.strip()
                    break
        if peeled == text:
            return text
        text = peeled
    return text


def complete(
    endpoint: str,
    api_key: str | None,
    model: str,
    system: str,
    user: str,
    timeout: float,
    extra_body: dict[str, Any],
    retries: int,
) -> tuple[str, float, float]:
    """The app's request body exactly: model, messages, stream=false. No temperature or token cap,
    so the measured latency is the latency the pipeline would see. `extra_body` exists for the one
    model whose own card demands more — s1-mini's temperature and thinking switch.

    Returns the content, the latency of the request that answered, and the seconds spent waiting
    out rate limits. A free tier that throttles is a throughput fact, not a latency one, so the
    two are never mixed into one number."""
    body = json.dumps(
        {
            "model": model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "stream": False,
            **extra_body,
        },
        ensure_ascii=False,
    ).encode()
    headers = {
        "Content-Type": "application/json",
        # Gateways behind Cloudflare reject the default Python-urllib agent (error 1010).
        "User-Agent": "miniwhisper-corpus-cleanup/1",
    }
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    request = urllib.request.Request(
        f"{endpoint.rstrip('/')}/chat/completions",
        data=body,
        headers=headers,
        method="POST",
    )
    throttled = 0.0
    for attempt in range(retries + 1):
        started = time.perf_counter()
        try:
            with urllib.request.urlopen(request, timeout=timeout) as result:
                response = json.load(result)
            break
        except urllib.error.HTTPError as error:
            detail = error.read()[:300]
            retryable = error.code == 429 or 500 <= error.code < 600
            if not retryable or attempt == retries:
                raise RuntimeError(
                    f"HTTP {error.code} {error.reason}: {detail!r}"
                ) from error
            # Retry-After when the server names a delay, exponential backoff when it does not.
            named = error.headers.get("Retry-After")
            delay = float(named) if named and named.isdigit() else 2.0**attempt
            print(f"    HTTP {error.code}; waiting {delay:.0f} s")
            time.sleep(delay)
            throttled += delay
    elapsed = time.perf_counter() - started
    content = response["choices"][0]["message"]["content"]
    if not isinstance(content, str):
        raise ValueError("chat-completion content is not a string")
    return content, elapsed * 1_000, throttled


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def diff(expected: str, actual: str) -> str:
    return "\n".join(
        unified_diff(
            expected.splitlines(),
            actual.splitlines(),
            fromfile="expect",
            tofile="cleaned",
            lineterm="",
        )
    )


# The model's own card, verbatim: s1-mini is a normalizer with no prompt surface, and any rewording
# degrades it to garbage. It receives no dictionary and no built-in prompt by construction.
S1_MINI_SYSTEM = (
    "You are a text normalizer for speech-to-text transcripts. The input begins "
    "with a control line specifying the styling, structure, and context settings; "
    "clean the transcript to match those settings and output only the cleaned text."
)
S1_MINI_CONTROL = "[Styling: semi-formal] [Structure: prose] [Context: general]"
S1_MINI_BODY = {"temperature": 0, "chat_template_kwargs": {"enable_thinking": False}}


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    stages = parser.add_subparsers(dest="command", required=True)

    for name, help_text in (
        ("stage3", "score cleaned text against `expect`."),
        ("stage2", "emit cleaned text for score_corpus.py to score."),
    ):
        stage = stages.add_parser(name, help=help_text)
        stage.add_argument("stage", type=Path)
        stage.add_argument(
            "--raw",
            type=Path,
            required=True,
            help="asr-replay output for the same stage.",
        )
        stage.add_argument(
            "--endpoint",
            help="API base URL; /chat/completions is appended. Unused by --prompt none.",
        )
        stage.add_argument("--api-key-env", default="AIG_APIKEY")
        stage.add_argument(
            "--no-api-key",
            action="store_true",
            help="Local servers authenticate nothing.",
        )
        stage.add_argument("--model", action="append")
        stage.add_argument("--timeout", type=float, default=60.0)
        stage.add_argument(
            "--retries",
            type=int,
            default=3,
            help="Retries on 429 and 5xx, honouring Retry-After.",
        )
        stage.add_argument(
            "--prompt",
            choices=("built-in", "s1-mini", "none"),
            default="built-in",
            help="s1-mini takes its own card's format and nothing else; none skips cleanup.",
        )
        stage.add_argument("--entry", action="append", help="Replay only these IDs.")
        stage.add_argument(
            "--prompt-source",
            type=Path,
            default=CLEANUP_PROMPT_SWIFT,
            help="CleanupPrompt.swift",
        )
        stage.add_argument(
            "--results-dir",
            type=Path,
            help="Write the run's output files here.",
        )

    stages.choices["stage3"].set_defaults(run=run_stage3)
    stage2 = stages.choices["stage2"]
    stage2.add_argument(
        "--dictionary-from-wants",
        action="store_true",
        help="Stage the union of the stage file's `wants` terms as the DICTIONARY block.",
    )
    stage2.add_argument(
        "--arm",
        required=True,
        help="Names the output file: stage2-<arm>-<model>.jsonl.",
    )
    stage2.set_defaults(run=run_stage2)
    return parser.parse_args()


def clean(
    args: argparse.Namespace,
    model: str,
    transcript: str,
    context_before: str | None,
    vocabulary: list[str],
    api_key: str | None,
) -> tuple[str, float, float]:
    if args.prompt == "none":
        return transcript, 0.0, 0.0
    if args.prompt == "s1-mini":
        system, user = S1_MINI_SYSTEM, f"{S1_MINI_CONTROL}\n{transcript}"
        extra_body = S1_MINI_BODY
    else:
        system = built_in_prompt(args.prompt_source)
        user = user_message(transcript, context_before, vocabulary)
        extra_body = {}
    content, latency, throttled = complete(
        args.endpoint,
        api_key,
        model,
        system,
        user,
        args.timeout,
        extra_body,
        args.retries,
    )
    return shape(content), latency, throttled


def prepare(
    args: argparse.Namespace,
) -> tuple[
    str | None,
    dict[str, dict[str, Any]],
    dict[str, dict[str, Any]],
    list[str],
]:
    api_key = (
        None
        if args.no_api_key or args.prompt == "none"
        else os.environ.get(args.api_key_env)
    )
    if not args.no_api_key and args.prompt != "none" and not api_key:
        sys.exit(f"No API key in ${args.api_key_env}.")
    if args.prompt == "none":
        args.model = ["none"]
    elif not args.model or not args.endpoint:
        sys.exit("--model and --endpoint are required unless --prompt none.")
    scripts = {entry["id"]: entry for entry in load_jsonl(args.stage)}
    raw = {entry["id"]: entry for entry in load_jsonl(args.raw)}
    ids = [key for key in scripts if key in raw]
    if args.entry:
        ids = [key for key in ids if key in set(args.entry)]
    if not ids:
        sys.exit("No corpus entries matched.")
    print(f"Prompt: {args.prompt}; entries: {len(ids)}; endpoint: {args.endpoint}")
    return api_key, scripts, raw, ids


def run_stage3(args: argparse.Namespace) -> int:
    api_key, scripts, raw, ids = prepare(args)
    failures = 0
    for model in args.model:
        print(f"\n=== {model} ===")
        rows = []
        throttled = 0.0
        wall_started = time.perf_counter()
        for index, entry_id in enumerate(ids, start=1):
            script = scripts[entry_id]
            transcript = raw[entry_id]["transcript"]
            try:
                cleaned, latency, waited = clean(
                    args,
                    model,
                    transcript,
                    (script.get("context") or {}).get("before"),
                    [],
                    api_key,
                )
                throttled += waited
            except (
                OSError,
                RuntimeError,
                ValueError,
                KeyError,
                json.JSONDecodeError,
            ) as error:
                failures += 1
                print(f"[{index}/{len(ids)}] {entry_id} ERROR: {error}")
                continue
            rows.append(
                {
                    "id": entry_id,
                    "tags": script.get("tags", []),
                    "raw": transcript,
                    "expect": script["expect"],
                    "cleaned": cleaned,
                    "match": cleaned == script["expect"].strip(),
                    "latencyMs": round(latency, 1),
                    "asrLatencyMs": raw[entry_id]["latencyMs"],
                }
            )
            mark = "ok  " if rows[-1]["match"] else "FAIL"
            print(f"[{index}/{len(ids)}] {mark} {entry_id} {latency:.0f} ms  {cleaned}")

        if not rows:
            continue
        by_tag: dict[str, list[bool]] = {}
        for row in rows:
            for tag in row["tags"]:
                by_tag.setdefault(tag, []).append(row["match"])
        wall = time.perf_counter() - wall_started
        latencies = sorted(row["latencyMs"] for row in rows)
        end_to_end = sorted(row["latencyMs"] + row["asrLatencyMs"] for row in rows)
        passed = sum(row["match"] for row in rows)
        report = {
            "model": model,
            "prompt": args.prompt,
            "endpoint": args.endpoint,
            "raw": str(args.raw),
            "entries": len(rows),
            "passed": passed,
            "passRate": round(passed / len(rows), 4),
            "byTag": {
                tag: {"passed": sum(results), "total": len(results)}
                for tag, results in sorted(by_tag.items())
            },
            "latency": {
                "medianMs": round(statistics.median(latencies), 1),
                "meanMs": round(statistics.fmean(latencies), 1),
                "minMs": latencies[0],
                "maxMs": latencies[-1],
            },
            "endToEndLatency": {
                "medianMs": round(statistics.median(end_to_end), 1),
                "meanMs": round(statistics.fmean(end_to_end), 1),
                "minMs": round(end_to_end[0], 1),
                "maxMs": round(end_to_end[-1], 1),
            },
            "throughput": {
                "wallSeconds": round(wall, 1),
                "throttledSeconds": round(throttled, 1),
                "entriesPerMinute": round(len(rows) / wall * 60, 1),
            },
            "entriesDetail": rows,
        }

        print(f"\nExact match: {passed}/{len(rows)} ({report['passRate'] * 100:.1f}%)")
        print(f"{'tag':22} pass")
        for tag, counts in report["byTag"].items():
            print(f"{tag:22} {counts['passed']}/{counts['total']}")
        latency = report["latency"]
        print(
            f"Cleanup latency median {latency['medianMs']:.0f} ms, "
            f"mean {latency['meanMs']:.0f} ms, max {latency['maxMs']:.0f} ms"
        )
        print(
            f"End to end median {report['endToEndLatency']['medianMs']:.0f} ms "
            "(ASR + cleanup)"
        )
        throughput = report["throughput"]
        print(
            f"Throughput {throughput['entriesPerMinute']:.1f} entries/min over "
            f"{throughput['wallSeconds']:.0f} s, {throughput['throttledSeconds']:.0f} s throttled"
        )
        print("\nFailures:")
        for row in rows:
            if row["match"]:
                continue
            print(f"\n  {row['id']} [{', '.join(row['tags'])}]")
            print(f"    raw:    {row['raw']}")
            print(textwrap.indent(diff(row["expect"], row["cleaned"]), "    "))

        if args.results_dir:
            args.results_dir.mkdir(parents=True, exist_ok=True)
            slug = model.replace("/", "-")
            (args.results_dir / f"stage3-{slug}.jsonl").write_text(
                "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows),
                encoding="utf-8",
            )
            (args.results_dir / f"stage3-{slug}-score.json").write_text(
                json.dumps(report, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            print(f"\nWrote {args.results_dir}/stage3-{slug}.jsonl and -score.json")

    return 1 if failures else 0


def run_stage2(args: argparse.Namespace) -> int:
    """Cleaned text in asr-replay's shape, latency charged end to end. The arm competing with it
    is a sidecar-boosted transcript, so the comparable cost is ASR plus whatever followed it."""
    api_key, scripts, raw, ids = prepare(args)
    vocabulary: list[str] = []
    if args.dictionary_from_wants:
        for entry_id in scripts:
            for term in scripts[entry_id].get("wants", []):
                if term not in vocabulary:
                    vocabulary.append(term)
    print(f"Dictionary: {len(vocabulary)} terms")

    failures = 0
    for model in args.model:
        print(f"\n=== {model} ===")
        rows = []
        for index, entry_id in enumerate(ids, start=1):
            transcript = raw[entry_id]["transcript"]
            try:
                cleaned, latency, _ = clean(
                    args, model, transcript, None, vocabulary, api_key
                )
            except (
                OSError,
                RuntimeError,
                ValueError,
                KeyError,
                json.JSONDecodeError,
            ) as error:
                failures += 1
                print(f"[{index}/{len(ids)}] {entry_id} ERROR: {error}")
                continue
            rows.append(
                {
                    "id": entry_id,
                    "transcript": cleaned,
                    "latencyMs": round(raw[entry_id]["latencyMs"] + latency, 1),
                    "asrLatencyMs": raw[entry_id]["latencyMs"],
                    "cleanupLatencyMs": round(latency, 1),
                    "raw": transcript,
                }
            )
            print(f"[{index}/{len(ids)}] {entry_id} {latency:.0f} ms  {cleaned}")

        if not rows or not args.results_dir:
            continue
        args.results_dir.mkdir(parents=True, exist_ok=True)
        slug = model.replace("/", "-")
        destination = args.results_dir / f"stage2-{args.arm}-{slug}.jsonl"
        destination.write_text(
            "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows),
            encoding="utf-8",
        )
        print(f"\nWrote {destination}")

    return 1 if failures else 0


def main() -> int:
    args = arguments()
    return args.run(args)


if __name__ == "__main__":
    raise SystemExit(main())
