#!/usr/bin/env python3
"""Replay MiniWhisper History originals through an OpenAI-compatible cleanup endpoint.

The script has no third-party dependencies and only reads the History JSON. It sends each
original ASR transcript, plus a persisted field-context payload when one is present, to the
configured endpoint. Results deliberately stay on stdout so private dictation text is not
written into this repository.
"""

from __future__ import annotations

import argparse
from difflib import unified_diff
import json
import math
import os
from pathlib import Path
import statistics
import sys
import time
from typing import Any
import urllib.error
import urllib.request

DEFAULT_HISTORY = (
    Path.home() / "Library/Application Support/MiniWhisper Dev/History/history.json"
)
SYSTEM_PROMPT = """You clean a dictated transcript before it is delivered into a text field.
Return only the cleaned transcript, with no quotes, commentary, markdown, or explanation.
Preserve the speaker's meaning and every asserted fact. Never add, infer, summarize, or rewrite
content. Apply only punctuation, casing, removal of obvious spoken disfluencies, spoken-symbol
conversion, and common technical notation. Field context and target-app identity are advisory:
use them only to resolve formatting or local grammatical ambiguity; do not repeat, alter, or
invent text from them."""


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--endpoint",
        required=True,
        help="OpenAI-compatible API base URL; /chat/completions is appended.",
    )
    parser.add_argument(
        "--api-key",
        default=os.environ.get("OPENAI_API_KEY"),
        help="Bearer token (defaults to OPENAI_API_KEY; prefer --api-key-env).",
    )
    parser.add_argument(
        "--api-key-env",
        help="Environment variable containing the bearer token, e.g. GROQ_API_KEY.",
    )
    parser.add_argument(
        "--model",
        action="append",
        required=True,
        help="Model ID to test; repeat this option to compare models.",
    )
    parser.add_argument("--history", type=Path, default=DEFAULT_HISTORY)
    parser.add_argument(
        "--limit", type=int, help="Use at most this many newest usable entries."
    )
    parser.add_argument(
        "--entry", action="append", help="Replay only these History entry UUIDs."
    )
    parser.add_argument("--max-completion-tokens", type=int, default=96)
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument(
        "--timeout", type=float, default=10.0, help="Per-request wall-clock limit."
    )
    parser.add_argument(
        "--without-context",
        action="store_true",
        help="Do not send any stored field context (useful for A/B comparison).",
    )
    return parser.parse_args()


def field_context(entry: dict[str, Any]) -> Any | None:
    """Accept the likely persisted names without prescribing the future storage schema."""
    for container in (entry, entry.get("delivery", {})):
        if not isinstance(container, dict):
            continue
        for key in ("fieldContext", "focusedTextContext", "cleanupContext"):
            value = container.get(key)
            if value is not None:
                return value
    return None


def load_entries(
    path: Path, requested_ids: set[str] | None, limit: int | None
) -> list[dict[str, Any]]:
    with path.open(encoding="utf-8") as source:
        history = json.load(source)
    # Version 2 moved each cleanup record onto the transcription it polished; the corpus this
    # harness reads — original text and field context — sits where it always did.
    if history.get("version") not in (1, 2):
        raise ValueError(f"Unsupported HistoryLog version: {history.get('version')!r}")

    entries = []
    for entry in history.get("entries", []):
        original = entry.get("original")
        if not isinstance(original, dict) or not isinstance(original.get("text"), str):
            continue
        if not original["text"].strip():
            continue
        if requested_ids is not None and entry.get("id") not in requested_ids:
            continue
        entries.append(entry)
        if limit is not None and len(entries) >= limit:
            break
    return entries


def message_content(response: dict[str, Any]) -> str:
    try:
        content = response["choices"][0]["message"]["content"]
    except (IndexError, KeyError, TypeError) as error:
        raise ValueError("Response has no chat-completion message content") from error

    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        return "".join(
            part.get("text", "")
            for part in content
            if isinstance(part, dict) and part.get("type") == "text"
        ).strip()
    raise ValueError("Chat-completion content is neither a string nor text parts")


def clean(
    endpoint: str,
    api_key: str,
    model: str,
    entry: dict[str, Any],
    max_completion_tokens: int,
    temperature: float,
    timeout: float,
    include_context: bool,
) -> tuple[str, float]:
    original = entry["original"]["text"]
    payload: dict[str, Any] = {
        "transcript": original,
        "target_app": entry.get("targetApp"),
    }
    if include_context:
        context = field_context(entry)
        if context is not None:
            payload["field_context"] = context

    body = json.dumps(
        {
            "model": model,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
            ],
            "temperature": temperature,
            "max_tokens": max_completion_tokens,
            "stream": False,
        },
        ensure_ascii=False,
    ).encode()
    request = urllib.request.Request(
        f"{endpoint.rstrip('/')}/chat/completions",
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            # Gateways behind Cloudflare reject the default Python-urllib agent (error 1010).
            "User-Agent": "miniwhisper-cleanup-benchmark/1",
        },
        method="POST",
    )
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as result:
            response = json.load(result)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"HTTP {error.code} {error.reason}") from error
    elapsed = time.perf_counter() - started
    return message_content(response), elapsed


def print_diff(raw: str, cleaned: str) -> None:
    diff = list(
        unified_diff(
            raw.splitlines(),
            cleaned.splitlines(),
            fromfile="raw",
            tofile="cleaned",
            lineterm="",
        )
    )
    print("\n".join(diff) if diff else "(unchanged)")


def main() -> int:
    args = arguments()
    api_key = os.environ.get(args.api_key_env) if args.api_key_env else args.api_key
    if not api_key:
        print("No API key: pass --api-key or --api-key-env NAME.", file=sys.stderr)
        return 2
    if args.limit is not None and args.limit < 1:
        print("--limit must be positive.", file=sys.stderr)
        return 2

    requested_ids = set(args.entry) if args.entry else None
    entries = load_entries(args.history, requested_ids, args.limit)
    if not entries:
        print("No usable original transcriptions matched.", file=sys.stderr)
        return 2

    contexts = sum(field_context(entry) is not None for entry in entries)
    print(f"History: {args.history} (read only)")
    print(
        f"Entries: {len(entries)}; field context available: {contexts}; timeout: {args.timeout:.1f}s"
    )
    if contexts and args.without_context:
        print("Field context is available but suppressed by --without-context.")

    failures = 0
    for model in args.model:
        print(f"\n=== {model} ===")
        elapsed: list[float] = []
        for index, entry in enumerate(entries, start=1):
            entry_id = entry["id"]
            try:
                cleaned, seconds = clean(
                    args.endpoint,
                    api_key,
                    model,
                    entry,
                    args.max_completion_tokens,
                    args.temperature,
                    args.timeout,
                    not args.without_context,
                )
            except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
                failures += 1
                print(f"\n[{index}/{len(entries)}] {entry_id} ERROR: {error}")
                continue
            elapsed.append(seconds)
            print(
                f"\n[{index}/{len(entries)}] {entry_id} wall: {seconds * 1_000:.0f} ms"
            )
            print_diff(entry["original"]["text"], cleaned)

        if elapsed:
            sorted_elapsed = sorted(elapsed)
            p95_index = min(
                len(sorted_elapsed) - 1, math.ceil(len(sorted_elapsed) * 0.95) - 1
            )
            print(
                "\nSummary: "
                f"n={len(elapsed)}, median={statistics.median(elapsed) * 1_000:.0f} ms, "
                f"p95={sorted_elapsed[p95_index] * 1_000:.0f} ms, "
                f"min={sorted_elapsed[0] * 1_000:.0f} ms, max={sorted_elapsed[-1] * 1_000:.0f} ms",
            )

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
