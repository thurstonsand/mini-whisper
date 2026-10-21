#!/usr/bin/env python3
"""Listen to real dictations and write down what was actually said and what should have come out.

The scripted stages are the opposite of field data: they know the answer before the microphone
opens. A real dictation knows nothing — only the person who spoke it can say what the words were,
and only they can say what they wanted typed. This serves a small local page with the audio, a
scrubber, and two editable boxes, and collects both answers into a corpus-shaped JSONL: `say` is
the verbatim truth (what the engine should have heard) and `expect` is the intended final text
(what cleanup should have produced from it).

Adjudicating is listening and typing at the same time — scrub back three seconds, fix a word,
scrub back again — so the page keeps the audio and both boxes on screen at once and never asks
anyone to hold a sentence in their head between hearing it and writing it down.

A dictation is chosen, never merely encountered. Most of the log is dictations that went fine, and
adjudicating those is an afternoon spent confirming the corpus already knows something — so this
asks for a selector and refuses without one. `--defect` names a failure and finds the entries that
exhibit it; `--id` takes the entry `history_triage.py` already ranked; `--match` is the escape
hatch for a failure nobody has written a detector for yet.

The audio is copied out of the vault on the way past, because retention deletes the vault's copy
and an adjudicated entry without its recording is an opinion rather than a fixture.

  ./adjudicate.py --defect unrequested-break --list   # what would be adjudicated, and why
  ./adjudicate.py --defect unrequested-break          # then adjudicate them, in the browser
  ./adjudicate.py --id 3947C08F                       # one entry, by history id or a prefix
  ./adjudicate.py --match 'sidecar' --history ~/Library/Application\\ Support/MiniWhisper/History
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import mimetypes
from pathlib import Path
import re
import shutil
import sys
import threading
import webbrowser

from history_triage import DEV_HISTORY_DIRECTORY, FILLERS, Entry, load_entries

DEFAULT_OUTPUT = Path(__file__).resolve().parent / "field-cases.jsonl"
DEFAULT_RECORDINGS = Path(__file__).resolve().parent / "recordings" / "field-cases"
PAGE = Path(__file__).resolve().parent / "adjudicate.html"

BOLD = "\033[1m"
DIM = "\033[2m"
GREEN = "\033[32m"
RESET = "\033[0m"

# A break the speaker asked for out loud. Cleanup is meant to honour these, so an entry containing
# one is not evidence of anything when its output has line breaks in it.
SPOKEN_BREAK = re.compile(r"new\s+(line|paragraph)", re.IGNORECASE)
# A hesitation sound standing alone between words, as opposed to one the speaker is quoting.
STANDALONE_FILLER = re.compile(
    r"(?<![\w'])(" + "|".join(sorted(FILLERS)) + r")(?![\w'])", re.IGNORECASE
)


# MARK: - Selection


def unrequested_break(entry: Entry) -> str | None:
    """Cleanup put the transcript on more than one line without being asked to. The spoken commands
    are the whole legitimate reason to do that, so their absence is what makes it a defect."""
    if not entry.cleaned or "\n" not in entry.cleaned:
        return None
    if SPOKEN_BREAK.search(entry.raw):
        return None
    breaks = entry.cleaned.count("\n")
    return f"{breaks} line break{'s' if breaks > 1 else ''} nobody asked for"


def surviving_filler(entry: Entry) -> str | None:
    """A hesitation the engine heard and cleanup was supposed to delete. Only counts when it is
    still there afterwards — the raw transcript is allowed to be honest."""
    if not entry.cleaned:
        return None
    survivors = {
        match.group(1).lower()
        for match in STANDALONE_FILLER.finditer(entry.cleaned)
        if STANDALONE_FILLER.search(entry.raw)
    }
    if not survivors:
        return None
    return f"filler survived cleanup: {', '.join(sorted(survivors))}"


# Named failures worth harvesting. A detector answers with the sentence explaining itself, because
# a list of ids says nothing about why any of them is on it.
DEFECTS = {
    "unrequested-break": unrequested_break,
    "surviving-filler": surviving_filler,
}


@dataclass
class Candidate:
    entry: Entry
    reasons: list[str]

    def payload(self, saved: dict | None) -> dict:
        """What the page needs to show this entry, with any previous adjudication of it winning
        over the seeds — reopening a saved entry must show what was written, not what was
        suggested."""
        return {
            "source": self.entry.id,
            "when": self.entry.created_at.strftime("%Y-%m-%d %H:%M"),
            "app": self.entry.target_app,
            "reasons": self.reasons,
            "raw": self.entry.raw,
            "cleaned": self.entry.cleaned,
            "cleanupModel": self.entry.cleanup_model,
            "hasAudio": self.entry.audio is not None,
            "savedAs": saved["id"] if saved else None,
            "tags": ", ".join(saved["tags"]) if saved else "",
            "say": saved["say"] if saved else self.entry.raw,
            "expect": (saved or {}).get("expect")
            or self.entry.cleaned
            or self.entry.raw,
        }


# MARK: - Storage


class Store:
    """The output file, keyed by the history entry it came from. Saving rewrites the whole file
    rather than appending, so adjudicating the same entry twice corrects it instead of recording
    two opinions about it."""

    def __init__(self, output: Path, recordings: Path):
        self.output = output
        self.recordings = recordings
        self.records: dict[str, dict] = {}
        if output.exists():
            for number, line in enumerate(
                output.read_text(encoding="utf-8").splitlines(), start=1
            ):
                if not line.strip():
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError as error:
                    sys.exit(f"{output}:{number}: {error}")
                self.records[record["source"]] = record

    def next_identifier(self) -> str:
        used = {
            int(suffix)
            for record in self.records.values()
            if (suffix := record["id"].rsplit("-", 1)[-1]).isdigit()
        }
        return f"field-{max(used, default=0) + 1:02d}"

    def save(self, entry: Entry, tags: list[str], say: str, expect: str) -> str:
        existing = self.records.get(entry.id)
        identifier = existing["id"] if existing else self.next_identifier()
        self.records[entry.id] = {
            "id": identifier,
            "tags": tags,
            "say": say,
            "expect": expect,
            "source": entry.id,
            "recordedAt": entry.created_at.isoformat(),
            "targetApp": entry.target_app,
            "engine": entry.engine,
            "engineRaw": entry.raw,
            "shippedCleanup": entry.cleaned,
            "cleanupModel": entry.cleanup_model,
        }
        if entry.audio is not None:
            self.recordings.mkdir(parents=True, exist_ok=True)
            shutil.copy2(entry.audio, self.recordings / f"{identifier}.wav")
        ordered = sorted(self.records.values(), key=lambda record: record["id"])
        self.output.write_text(
            "\n".join(json.dumps(record, ensure_ascii=False) for record in ordered)
            + "\n",
            encoding="utf-8",
        )
        return identifier


# MARK: - Server


def handler_class(candidates: list[Candidate], store: Store, done: threading.Event):
    by_source = {candidate.entry.id: candidate for candidate in candidates}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args) -> None:
            """The page's own requests are not news; saves print themselves."""

        def respond(
            self, status: int, body: bytes, content_type: str, extra: dict | None = None
        ):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            for header, value in (extra or {}).items():
                self.send_header(header, value)
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:
            if self.path in ("/", "/index.html"):
                self.respond(200, PAGE.read_bytes(), "text/html; charset=utf-8")
            elif self.path == "/api/queue":
                payload = [
                    candidate.payload(store.records.get(candidate.entry.id))
                    for candidate in candidates
                ]
                self.respond(
                    200,
                    json.dumps(payload).encode("utf-8"),
                    "application/json; charset=utf-8",
                )
            elif self.path.startswith("/audio/"):
                self.serve_audio(self.path.removeprefix("/audio/"))
            else:
                self.respond(404, b"not found", "text/plain")

        def serve_audio(self, source: str) -> None:
            """Range requests, because a scrubber that cannot seek is a progress bar. Safari will
            not seek at all without them."""
            candidate = by_source.get(source)
            if candidate is None or candidate.entry.audio is None:
                self.respond(404, b"no audio", "text/plain")
                return
            data = candidate.entry.audio.read_bytes()
            kind = mimetypes.guess_type(candidate.entry.audio.name)[0] or "audio/wav"
            requested = self.headers.get("Range", "")
            if match := re.fullmatch(r"bytes=(\d*)-(\d*)", requested.strip()):
                start = int(match.group(1)) if match.group(1) else 0
                end = int(match.group(2)) if match.group(2) else len(data) - 1
                end = min(end, len(data) - 1)
                if start > end:
                    self.respond(
                        416, b"", kind, {"Content-Range": f"bytes */{len(data)}"}
                    )
                    return
                self.respond(
                    206,
                    data[start : end + 1],
                    kind,
                    {
                        "Content-Range": f"bytes {start}-{end}/{len(data)}",
                        "Accept-Ranges": "bytes",
                    },
                )
                return
            self.respond(200, data, kind, {"Accept-Ranges": "bytes"})

        def do_POST(self) -> None:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
            if self.path == "/api/save":
                candidate = by_source.get(body["source"])
                if candidate is None:
                    self.respond(404, b"unknown entry", "text/plain")
                    return
                tags = [
                    tag.strip()
                    for tag in body.get("tags", "").split(",")
                    if tag.strip()
                ]
                identifier = store.save(
                    candidate.entry, tags, body["say"].strip(), body["expect"].strip()
                )
                print(
                    f"  {GREEN}saved{RESET} {identifier} {DIM}← {candidate.entry.id}{RESET}"
                    f"  ({len(store.records)} in {store.output.name})"
                )
                self.respond(
                    200, json.dumps({"id": identifier}).encode(), "application/json"
                )
            elif self.path == "/api/quit":
                self.respond(200, b"{}", "application/json")
                done.set()
            else:
                self.respond(404, b"not found", "text/plain")

    return Handler


# MARK: - Entry point


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--history",
        type=Path,
        default=DEV_HISTORY_DIRECTORY,
        help="The channel's History directory, holding history.json and audio/.",
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--recordings", type=Path, default=DEFAULT_RECORDINGS)
    parser.add_argument(
        "--id",
        action="append",
        dest="ids",
        metavar="UUID",
        help="adjudicate these entries, by history id or a unique prefix of one",
    )
    parser.add_argument(
        "--defect",
        action="append",
        dest="defects",
        choices=sorted(DEFECTS),
        help="adjudicate the entries exhibiting this failure; repeatable",
    )
    parser.add_argument(
        "--match",
        help="adjudicate entries whose transcript matches this regular expression",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="print what the selectors found, with the reason each entry was picked, and stop",
    )
    parser.add_argument("--limit", type=int, help="take only this many candidates")
    parser.add_argument("--port", type=int, default=0, help="serve on a fixed port")
    args = parser.parse_args()
    if not (args.ids or args.defects or args.match):
        parser.error(
            "choose what to adjudicate: --defect "
            f"{{{','.join(sorted(DEFECTS))}}}, --id UUID, or --match REGEX"
        )

    entries, _ = load_entries(args.history / "history.json", args.history / "audio")
    store = Store(args.output, args.recordings)
    selected: dict[str, Candidate] = {}

    def select(entry: Entry, reason: str) -> None:
        selected.setdefault(entry.id, Candidate(entry, [])).reasons.append(reason)

    for prefix in args.ids or []:
        matches = [
            entry for entry in entries if entry.id.lower().startswith(prefix.lower())
        ]
        if not matches:
            sys.exit(f"no history entry starts with {prefix!r}")
        if len(matches) > 1:
            sys.exit(f"{prefix!r} matches {len(matches)} entries; give more of the id")
        select(matches[0], "named by id")
    for name in args.defects or []:
        detector = DEFECTS[name]
        for entry in entries:
            if reason := detector(entry):
                select(entry, f"{name}: {reason}")
    if args.match:
        pattern = re.compile(args.match, re.IGNORECASE)
        for entry in entries:
            if pattern.search(entry.raw) or (
                entry.cleaned and pattern.search(entry.cleaned)
            ):
                select(entry, f"matches /{args.match}/")

    candidates = (
        list(selected.values())[: args.limit] if args.limit else list(selected.values())
    )
    if not candidates:
        print(
            "Nothing selected. Widen the selector, or check --history points at the right channel."
        )
        return 0

    if args.list:
        for candidate in candidates:
            entry = candidate.entry
            where = f" · {entry.target_app}" if entry.target_app else ""
            mark = (
                f"  {GREEN}already adjudicated{RESET}"
                if entry.id in store.records
                else ""
            )
            print(
                f"\n{BOLD}{entry.id}{RESET}  {entry.created_at:%Y-%m-%d %H:%M}{DIM}{where}{RESET}{mark}"
            )
            for reason in candidate.reasons:
                print(f"  {DIM}• {reason}{RESET}")
            print(f"  {entry.raw[:150]}{'…' if len(entry.raw) > 150 else ''}")
        print(
            f"\n{len(candidates)} selected. Rerun without --list to work through them."
        )
        return 0

    done = threading.Event()
    server = ThreadingHTTPServer(
        ("127.0.0.1", args.port), handler_class(candidates, store, done)
    )
    url = f"http://127.0.0.1:{server.server_address[1]}/"
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    print(f"{len(candidates)} to adjudicate → {args.output}")
    print(f"{DIM}{url} — the page's Done button or ctrl-C stops the server{RESET}")
    webbrowser.open(url)
    try:
        done.wait()
    except KeyboardInterrupt:
        print()
    server.shutdown()
    print(f"{len(store.records)} entries in {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
