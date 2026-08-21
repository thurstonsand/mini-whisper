#!/usr/bin/env python3
"""Replay a corpus stage through a hosted transcription API, writing asr-replay's JSONL contract.

The local engines are measured with a stopwatch on the model. These are measured with a stopwatch
on the network, and that is a different quantity: `latencyMs` here is the whole round trip from
this machine — upload, queue, inference, response — so it is honest about what the pipeline would
wait for and dishonest about what the provider's hardware costs. Treat every hosted number as
network-dependent and re-measure it before betting a profile on it.

Each provider gets a vocabulary channel of its own, because they are not the same mechanism and
should not be reported as if they were:

  groq        `prompt` on the OpenAI-shaped endpoint, which whisper treats as decoder
              conditioning — text pretended to precede the audio, 224 tokens, last ones
              weighing most. Terms only, exact spelling, no instructions: whisper does not
              follow them, it imitates them. Comma-separated on one line, because newlines
              silence the model entirely.
  elevenlabs  `keyterms`, Scribe v2's own biasing list (1000 terms, 50 characters each).
  gemini      real instructions, since the transcriber is a language model.

  ./transcribe_hosted.py --provider groq --stage stage1-intelligibility.jsonl \\
      --recordings recordings/stage1-intelligibility-built-in \\
      --output results/groq-whisper-large-v3-turbo/stage1.jsonl

  ./transcribe_hosted.py --provider groq --stage stage2-dictionary.jsonl --vocabulary-from-wants \\
      --recordings recordings/stage2-dictionary-built-in \\
      --output results/asr-prompting/stage2-groq-prompted.jsonl
"""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
from pathlib import Path
import secrets
import statistics
import sys
import time
from typing import Any
import urllib.error
import urllib.request
import wave

USER_AGENT = "miniwhisper-corpus-hosted/1"

GEMINI_INSTRUCTION = (
    "Transcribe the speech in this audio verbatim. Preserve every word, including "
    "fillers and false starts, and spell out spoken punctuation as the speaker said "
    "it. Output only the transcript, with no preamble and no commentary."
)
GEMINI_VOCABULARY_INSTRUCTION = (
    "These terms may appear in the audio. When you hear one, spell it exactly as "
    "written here. Do not force a term in that was not spoken:"
)


def audio_seconds(path: Path) -> float:
    with wave.open(str(path)) as wav:
        return wav.getnframes() / wav.getframerate()


def multipart(fields: list[tuple[str, str]], filename: Path) -> tuple[bytes, str]:
    """A file upload without the `requests` dependency the rest of this corpus does not have.
    Fields are pairs rather than a mapping because ElevenLabs takes `keyterms` as a repeated
    part, one term each, and rejects a JSON array as a single over-long keyword."""
    boundary = secrets.token_hex(16)
    body = bytearray()
    for name, value in fields:
        body += f"--{boundary}\r\n".encode()
        body += f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode()
        body += value.encode() + b"\r\n"
    content_type = mimetypes.guess_type(filename.name)[0] or "application/octet-stream"
    body += f"--{boundary}\r\n".encode()
    body += (
        f'Content-Disposition: form-data; name="file"; filename="{filename.name}"\r\n'
    ).encode()
    body += f"Content-Type: {content_type}\r\n\r\n".encode()
    body += filename.read_bytes() + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    return bytes(body), f"multipart/form-data; boundary={boundary}"


def post(
    request: urllib.request.Request, timeout: float, retries: int
) -> tuple[Any, float, float]:
    """Returns the payload, the latency of the request that answered, and the seconds spent
    waiting out rate limits. A free tier that throttles is a throughput fact, not a latency one,
    so the two are never mixed into one number."""
    throttled = 0.0
    for attempt in range(retries + 1):
        started = time.perf_counter()
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                payload = json.load(response)
            return payload, (time.perf_counter() - started) * 1000, throttled
        except urllib.error.HTTPError as error:
            detail = error.read()[:300]
            retryable = error.code == 429 or 500 <= error.code < 600
            if not retryable or attempt == retries:
                raise RuntimeError(
                    f"HTTP {error.code} {error.reason}: {detail!r}"
                ) from error
            named = error.headers.get("Retry-After")
            delay = float(named) if named and named.isdigit() else 2.0**attempt
            print(f"    HTTP {error.code}; waiting {delay:.0f} s", file=sys.stderr)
            time.sleep(delay)
            throttled += delay
    raise RuntimeError("unreachable")


def groq_request(
    wav: Path, model: str, api_key: str, vocabulary: list[str]
) -> urllib.request.Request:
    fields = [("model", model), ("language", "en"), ("response_format", "json")]
    if vocabulary:
        # Terms only, comma-separated on one line: whisper imitates the prompt's spelling, it
        # does not obey it. Newline separation is not cosmetic — it made the model return an
        # empty transcript for all 24 stage-2 entries; see results/asr-prompting/.
        fields.append(("prompt", ", ".join(vocabulary)))
    body, content_type = multipart(fields, wav)
    return urllib.request.Request(
        "https://api.groq.com/openai/v1/audio/transcriptions",
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": content_type,
            "User-Agent": USER_AGENT,
        },
        method="POST",
    )


def elevenlabs_request(
    wav: Path, model: str, api_key: str, vocabulary: list[str]
) -> urllib.request.Request:
    fields = [("model_id", model), ("language_code", "eng")]
    fields.extend(("keyterms", term) for term in vocabulary)
    body, content_type = multipart(fields, wav)
    return urllib.request.Request(
        "https://api.elevenlabs.io/v1/speech-to-text",
        data=body,
        headers={
            "xi-api-key": api_key,
            "Content-Type": content_type,
            "User-Agent": USER_AGENT,
        },
        method="POST",
    )


def gemini_request(
    wav: Path, model: str, api_key: str, vocabulary: list[str]
) -> urllib.request.Request:
    instruction = GEMINI_INSTRUCTION
    if vocabulary:
        terms = "\n".join(f"- {term}" for term in vocabulary)
        instruction = f"{instruction}\n\n{GEMINI_VOCABULARY_INSTRUCTION}\n{terms}"
    body = json.dumps(
        {
            "contents": [
                {
                    "parts": [
                        {"text": instruction},
                        {
                            "inline_data": {
                                "mime_type": "audio/wav",
                                "data": base64.b64encode(wav.read_bytes()).decode(),
                            }
                        },
                    ]
                }
            ]
        }
    ).encode()
    return urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
        data=body,
        headers={
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
            "x-goog-api-key": api_key,
        },
        method="POST",
    )


def gemini_text(response: dict[str, Any]) -> str:
    parts = response["candidates"][0]["content"]["parts"]
    return "".join(part["text"] for part in parts if "text" in part)


PROVIDERS = {
    "groq": {
        "model": "whisper-large-v3-turbo",
        "key_env": "GROQ_APIKEY",
        "request": groq_request,
        "text": lambda response: response["text"],
    },
    "elevenlabs": {
        "model": "scribe_v2",
        "key_env": "ELEVENLABS_APIKEY",
        "request": elevenlabs_request,
        "text": lambda response: response["text"],
    },
    "gemini": {
        "model": "gemini-3.6-flash",
        "key_env": "GEMINI_APIKEY",
        "request": gemini_request,
        "text": gemini_text,
    },
}


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--provider", choices=sorted(PROVIDERS), required=True)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--recordings", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--model", help="defaults to the provider's flagship")
    parser.add_argument("--api-key-env", help="defaults to the provider's own variable")
    parser.add_argument("--timeout", type=float, default=120.0)
    parser.add_argument("--retries", type=int, default=3)
    parser.add_argument(
        "--vocabulary-from-wants",
        action="store_true",
        help="condition on the union of the stage file's `wants` terms.",
    )
    parser.add_argument(
        "--vocabulary", type=Path, help="condition on a newline-separated term list."
    )
    return parser.parse_args()


def vocabulary_terms(
    args: argparse.Namespace, entries: list[dict[str, Any]]
) -> list[str]:
    if args.vocabulary:
        return [
            line.strip()
            for line in args.vocabulary.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
    if not args.vocabulary_from_wants:
        return []
    terms: list[str] = []
    for entry in entries:
        for term in entry.get("wants", []):
            if term not in terms:
                terms.append(term)
    return terms


def main() -> int:
    args = arguments()
    provider = PROVIDERS[args.provider]
    model = args.model or provider["model"]
    api_key = os.environ.get(args.api_key_env or provider["key_env"])
    if not api_key:
        sys.exit(f"No API key in ${args.api_key_env or provider['key_env']}.")

    entries = [
        json.loads(line)
        for line in args.stage.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    recordings = [(entry, args.recordings / f"{entry['id']}.wav") for entry in entries]
    missing = [path for _, path in recordings if not path.exists()]
    if missing:
        raise FileNotFoundError(f"missing recording: {missing[0]}")

    vocabulary = vocabulary_terms(args, entries)
    print(
        f"{args.provider} {model}: {len(recordings)} entries, "
        f"{len(vocabulary)} conditioning terms"
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)

    latencies = []
    throttled = 0.0
    with args.output.open("w", encoding="utf-8") as sink:
        for entry, wav in recordings:
            request = provider["request"](wav, model, api_key, vocabulary)
            response, latency_ms, waited = post(request, args.timeout, args.retries)
            throttled += waited
            transcript = provider["text"](response).strip()
            latencies.append(latency_ms)
            sink.write(
                json.dumps(
                    {
                        "audioSeconds": audio_seconds(wav),
                        "id": entry["id"],
                        "latencyMs": latency_ms,
                        "outcome": "transcript",
                        "transcript": transcript,
                    },
                    sort_keys=True,
                )
                + "\n"
            )
            print(f"{entry['id']}: {latency_ms:.0f} ms  {transcript}")

    print(
        f"round trip median {statistics.median(latencies):.0f} ms, "
        f"mean {statistics.fmean(latencies):.0f} ms, max {max(latencies):.0f} ms "
        f"(network-dependent); {throttled:.0f} s throttled",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
