#!/usr/bin/env python3
"""Disposable spike: does screen context help the cleanup pass, and in which form?

Replays a handful of dictations through the app's own built-in prompt (lifted from
CleanupPrompt.swift) over the OpenAI-compatible Anthropic endpoint, once per context arm:

  none        transcript only
  field       + FOCUSED_TEXT_CONTEXT (what the app sends today; a tmux prompt line for terminals)
  text        + field + SCREEN_CONTEXT read structurally (tmux capture-pane / AX window walk)
  ocr         + field + SCREEN_CONTEXT recognized by Vision .fast from a screenshot
  image       screenshot only, at Retina resolution
  image-1x    screenshot only, downscaled to 1x points
  image+field + field + Retina screenshot

Scoring is substring-based: `must` are the identifiers only the screen can supply, `forbid` is
screen text a dictation never said. Exact match is the corpus's job, not this spike's.
"""

import base64
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import sys
import textwrap
import time
import urllib.request

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SCENES = (
    Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / ".amp/in/screen-context/scene"
)
REPS = int(os.environ.get("REPS", "2"))
MODEL = os.environ.get("MODEL", "claude-haiku-5-5")
ENDPOINT = "https://api.anthropic.com/v1/chat/completions"

source = (
    REPO / "Packages/TranscriptCleanup/Sources/TranscriptCleanup/CleanupPrompt.swift"
).read_text()
BUILT_IN = textwrap.dedent(
    re.search(
        r'public static let builtIn = """\n(.*?)\n  """', source, re.DOTALL
    ).group(1)
)
CONTEXT_RULE = "- Use FOCUSED_TEXT_CONTEXT and TARGET_BUNDLE_ID only to choose spelling"
assert CONTEXT_RULE in BUILT_IN
# The one edit the proposal makes to the shipped prompt: the context rule names the new sources
# and says what they are, and every other sentence stays verbatim.
SCREEN_PROMPT = BUILT_IN.replace(
    CONTEXT_RULE,
    "- FOCUSED_TEXT_CONTEXT is the field the dictation is typed into. SCREEN_CONTEXT, and any "
    "attached screenshot, show other text visible around that field; it can contain recognition "
    "errors and is never where the dictation goes. Use FOCUSED_TEXT_CONTEXT, SCREEN_CONTEXT, any "
    "screenshot, and TARGET_BUNDLE_ID only to choose spelling",
)

TERMINAL_SCREEN = """╭─ claude ─────────────────────────────────────────────────────────────╮
> why does the pill flash Polishing for a keyless profile?

⏺ The flash comes from cleanupStarted firing before TranscriptPipeline.plan
  resolves. In AppFeature+Delivery.swift, cleanupEffect sends
  .cleanupStarted only inside requestStarting, so the bug is elsewhere:
  CleanupPlan.keyUnreadable returns before requestStarting runs.

  I traced it to FocusedFieldReader.captureBudget being 60ms — the
  context capture times out on cold Chromium processes, so dictation.capture
  stays nil and DeliveryTarget.isGUI flips. Proposed fix:

    - raise firstContactTimeout to 0.040 in FocusedFieldReader.swift
    - keep ChromiumAccessibility.prewarmFrontmostApp at recording start

  Run `mise run test:packages` to confirm. Want me to apply it?
╰──────────────────────────────────────────────────────────────────────╯"""

# Vision .fast on the CPU of a virtualized Mac, verbatim, in the probe's reading order.
TERMINAL_OCR = """• fl 8 h runner- attach.command- tmux-L spike attach -t agent- 120x30
claude
> why does the pill flash Polishing for a keyless profile?
• The flash comes from cleanupStarted firing before TranscriptPipeline. plan
resolves. In AppFeature+Delivery. swift, cleanupEffect sends
.cleanupStarted only inside requestStartingi SO the bug is elsewhere:
CleanupPlan. keyUnreadable returns before requestStarting runs.
I traced it to FocusedFieldReader. captureBudget being 60ms the
context capture times out on cold Chromium processes, so dictation.capture
stays nil and DeliveryTarget.isGUI flips. Proposed fix:
raise firstContactTimeout to 0.040 in FocusedFieldReader. swift
keep ChromiumAccessibility. prewarmFrontmostApp at recording start
Run 'mise run test:packages" to confirm. Want me to apply it?
> so the capture budget is fine, it's the first contactl
lagentl 0:bash*
'b312cc791uld0. local 19: 55 09-Nov-26"""

# The AX walk's static text, sorted into reading order as a production walk would by AXPosition,
# with the focused field's own text left out because it travels as FOCUSED_TEXT_CONTEXT.
CHAT_AX = """Channels
# general
# mini-whisper
# ghostty-kit
Direct messages
Priyanka Raghunathan
Søren Kierkegaard-Olsen

Priyanka Raghunathan
Has anyone tried the Qwen3-ASR checkpoint against Parakeet on the Zigbee doorbell clips? The FluidAudio people say v3 ties it.
Søren Kierkegaard-Olsen
I ran it last night. WER was 4.1 vs 3.8 but latency doubled. Also tuistory crashed twice when I piped the logs through it.
Priyanka Raghunathan
Ok. Can you open a ticket in Linear under MW-212 and tag Thurston?"""

CHAT_OCR = """f ile:Illprivateltmplscenelchat.html
Channels
# general
Priyanka Raghunathan
# mini-whisper
Has anyone tried the Qwen3-ASR checkpoint against Parakeet on the Zigbee doorbell clips? The FluidAudio people say v3 ties it.
# ghostty-kit
Direct messages
Soren Kierkegaard-Olsen
Priyanka Raghunathan
Soren Kierkegaard-Olsen
I ran it last night. WER was 4.1 vs 3.8 but latency doubled. Also tuistory crashed twice when I piped the logs through it.
Priyanka Raghunathan
Ok. Can you open a ticket in Linear under MW-212 and tag Thurston?
bounds good, I'll"""

SCENES_BY_NAME = {
    "terminal": {
        "bundle": "com.apple.Terminal",
        "title": "tmux -L spike attach -t agent",
        "text": TERMINAL_SCREEN,
        "ocr": TERMINAL_OCR,
        "image": "term-2x.jpg",
        "image-1x": "term-1x.jpg",
    },
    "chat": {
        "bundle": "com.apple.Safari",
        "title": "#mini-whisper — Slackish",
        "text": CHAT_AX,
        "ocr": CHAT_OCR,
        "image": "safari-2x.jpg",
        "image-1x": "safari-1x.jpg",
    },
}

CASES = [
    {
        "id": "term-1",
        "scene": "terminal",
        "before": "",
        "raw": "Yeah, go ahead, but first check whether clean up plan dot key unreadable is even reachable from transcript pipeline dot plan, and then run mise run test colon packages.",
        "must": [
            "CleanupPlan.keyUnreadable",
            "TranscriptPipeline.plan",
            "test:packages",
        ],
        "forbid": [],
    },
    {
        "id": "term-2",
        "scene": "terminal",
        "before": "so the capture budget is fine, it's the first contact ",
        "raw": "Timeout that's too tight. Raise first contact timeout to point zero eight and keep the pre-warm in chromium accessibility.",
        "must": ["firstContactTimeout", "ChromiumAccessibility"],
        "forbid": [],
    },
    {
        "id": "term-3",
        "scene": "terminal",
        "before": "",
        "raw": "Actually, don't touch focus field reader. The real problem is delivery target dot is GUI flipping.",
        "must": ["FocusedFieldReader", "DeliveryTarget.isGUI"],
        "forbid": [],
    },
    {
        "id": "chat-1",
        "scene": "chat",
        "before": "Sounds good, I'll ",
        "raw": "Open it under M W two twelve and tag Thurston. Soren, can you attach the quen three ASR numbers?",
        "must": ["MW-212", "Søren", "Qwen3-ASR"],
        "forbid": [],
    },
    {
        "id": "chat-2",
        "scene": "chat",
        "before": "Sounds good, I'll ",
        "raw": "Also file the tui story crash separately. It's probably the fluid audio log volume.",
        "must": ["tuistory", "FluidAudio"],
        "forbid": [],
    },
    {
        "id": "chat-3",
        "scene": "chat",
        "before": "",
        "raw": "Priyonka, the zigbee clips are on the NAS if you want to rerun parakeet.",
        "must": ["Priyanka", "Zigbee", "Parakeet"],
        "forbid": [],
    },
    {
        "id": "chat-ctl",
        "scene": "chat",
        "before": "",
        "raw": "Thanks, I'll take a look tomorrow morning.",
        "must": ["Thanks, I'll take a look tomorrow morning."],
        "forbid": ["MW-212", "Qwen", "Linear", "Søren", "Priyanka"],
    },
]

ARMS = ["none", "field", "text", "ocr", "image", "image-1x", "image+field"]


def tagged(tag: str, body: str) -> str:
    return f"<{tag}>\n{body}\n</{tag}>"


def request_for(case: dict, arm: str) -> tuple[str, list | str]:
    scene = SCENES_BY_NAME[case["scene"]]
    blocks = [tagged("TRANSCRIPT", case["raw"])]
    if arm in ("field", "text", "ocr", "image+field") and case["before"]:
        blocks.append(
            tagged("FOCUSED_TEXT_CONTEXT", tagged("BEFORE_CARET", case["before"]))
        )
    if arm in ("text", "ocr"):
        blocks.append(
            tagged(
                "SCREEN_CONTEXT",
                tagged("WINDOW_TITLE", scene["title"])
                + "\n"
                + tagged("VISIBLE_TEXT", scene[arm]),
            )
        )
    blocks.append(tagged("TARGET_BUNDLE_ID", scene["bundle"]))
    text = "\n\n".join(blocks)
    system = BUILT_IN if arm in ("none", "field") else SCREEN_PROMPT
    if not arm.startswith("image"):
        return system, text
    image = scene["image-1x" if arm == "image-1x" else "image"]
    data = base64.b64encode((SCENES / image).read_bytes()).decode()
    return system, [
        {"type": "text", "text": text},
        {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{data}"}},
    ]


def complete(system: str, user) -> dict:
    body = json.dumps(
        {
            "model": MODEL,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "stream": False,
        }
    ).encode()
    request = urllib.request.Request(
        ENDPOINT,
        data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {os.environ['ANTHROPIC_CREDITS_APIKEY']}",
        },
    )
    for attempt in range(4):
        started = time.perf_counter()
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = json.load(response)
            return {
                "content": payload["choices"][0]["message"]["content"] or "",
                "ms": (time.perf_counter() - started) * 1000,
                "prompt_tokens": payload["usage"]["prompt_tokens"],
            }
        except urllib.error.HTTPError as error:
            if error.code not in (429, 500, 502, 503, 529) or attempt == 3:
                raise
            time.sleep(2**attempt)


def run(job):
    case, arm, rep = job
    system, user = request_for(case, arm)
    result = complete(system, user)
    output = result["content"].strip()
    hits = [term for term in case["must"] if term in output]
    leaks = [term for term in case["forbid"] if term in output]
    return {
        "case": case["id"],
        "arm": arm,
        "rep": rep,
        "output": output,
        "hits": len(hits),
        "needed": len(case["must"]),
        "missed": [term for term in case["must"] if term not in hits],
        "leaks": leaks,
        **{key: result[key] for key in ("ms", "prompt_tokens")},
    }


def main() -> None:
    arms = os.environ.get("ARMS", ",".join(ARMS)).split(",")
    jobs = [(case, arm, rep) for case in CASES for arm in arms for rep in range(REPS)]
    # WORKERS=1 for latency: six requests in flight at once make the p50 a queueing number.
    with ThreadPoolExecutor(max_workers=int(os.environ.get("WORKERS", "6"))) as pool:
        results = list(pool.map(run, jobs))
    out = HERE / os.environ.get("OUT", "results.jsonl")
    out.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in results))

    print(f"{MODEL}, {REPS} reps, {len(results)} calls -> {out}\n")
    print(f"{'arm':<12} {'terms':>9} {'leaks':>5} {'p50 ms':>7} {'tokens':>7}")
    for arm in arms:
        rows = [r for r in results if r["arm"] == arm]
        hits = sum(r["hits"] for r in rows)
        needed = sum(r["needed"] for r in rows)
        leaks = sum(len(r["leaks"]) for r in rows)
        latency = sorted(r["ms"] for r in rows)[len(rows) // 2]
        tokens = sum(r["prompt_tokens"] for r in rows) / len(rows)
        print(
            f"{arm:<12} {hits:>4}/{needed:<4} {leaks:>5} {latency:>7.0f} {tokens:>7.0f}"
        )
    print("\nper case (terms hit, summed over reps):")
    print(f"{'case':<10}" + "".join(f"{arm:>12}" for arm in arms))
    for case in CASES:
        cells = []
        for arm in arms:
            rows = [r for r in results if r["case"] == case["id"] and r["arm"] == arm]
            cells.append(
                f"{sum(r['hits'] for r in rows)}/{sum(r['needed'] for r in rows)}"
            )
        print(f"{case['id']:<10}" + "".join(f"{cell:>12}" for cell in cells))


if __name__ == "__main__":
    main()
