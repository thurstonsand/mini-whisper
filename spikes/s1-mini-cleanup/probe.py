#!/usr/bin/env python3
"""One-off probes: styling axes and the failure boundaries the design cares about."""

from __future__ import annotations

import json
import urllib.request

SYSTEM = (
    "You are a text normalizer for speech-to-text transcripts. The input begins "
    "with a control line specifying the styling, structure, and context settings; "
    "clean the transcript to match those settings and output only the cleaned text."
)


def normalize(transcript: str, styling: str) -> str:
    body = json.dumps(
        {
            "model": "s1-mini",
            "messages": [
                {"role": "system", "content": SYSTEM},
                {
                    "role": "user",
                    "content": (
                        f"[Styling: {styling}] [Structure: prose] [Context: general]\n{transcript}"
                    ),
                },
            ],
            "temperature": 0,
            "chat_template_kwargs": {"enable_thinking": False},
        }
    ).encode()
    request = urllib.request.Request(
        "http://localhost:8317/v1/chat/completions",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)["choices"][0]["message"]["content"].strip()


DISFLUENT = (
    "so um i need to like send the the report by uh friday no wait make that thursday"
)
PROBES = [
    ("disfluent, semi-formal", DISFLUENT, "semi-formal"),
    ("disfluent, casual", DISFLUENT, "casual"),
    ("disfluent, formal", DISFLUENT, "formal"),
    (
        "coded speech",
        "um so run swift test dash dash filter cleanup comma then uh report back",
        "semi-formal",
    ),
    (
        "question stays",
        "why does the uh the silence gate reject clips under five hundred milliseconds",
        "semi-formal",
    ),
    ("filler only", "um uh hmm", "semi-formal"),
]

for name, transcript, styling in PROBES:
    print(f"== {name}: {normalize(transcript, styling)!r}")
