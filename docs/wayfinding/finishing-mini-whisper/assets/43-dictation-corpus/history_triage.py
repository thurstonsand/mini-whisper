#!/usr/bin/env python3
"""Rank the dev channel's own dictation history by how likely it is to be wrong.

The corpus is scripted: known input, known intended output. Real dictations are the opposite —
hundreds of recordings whose only ground truth is the person who spoke them, and adjudicating
them means listening to all of them. This pass reads the history log and the audio vault without
touching either, and ranks the entries whose text looks semantically dubious, so the ones worth
listening to surface first and the rest stay unheard. What survives adjudication becomes a
`reference` on the entry and, eventually, an organic stage of the corpus.

Four heuristics, no model in the loop. A cleanup pass that rewrote most of the transcript, a raw
transcript shaped like a gate failure or a decoder loop, a cleanup that dropped a number or an
identifier the engine heard, and — the dangerous one — a cleanup that introduced a content word
nobody said. Each flag carries the sentence explaining itself, because a rank without a reason is
just another list to listen through.

  ./history_triage.py
  ./history_triage.py --history ~/Library/Application\\ Support/MiniWhisper/History \\
      --output .build/release-triage.md
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import datetime
import json
from pathlib import Path
import re
import sys
from typing import Any

from score_corpus import edits, normalize, word_diff

DEV_HISTORY_DIRECTORY = (
    Path.home() / "Library/Application Support/MiniWhisper Dev/History"
)
DEFAULT_OUTPUT = Path(__file__).resolve().parent / ".build/history-triage.md"

# HistoryLog.version — the log rejects files it does not know rather than misreading them, and so
# does this: a shape change means the heuristics below are reading fields that moved.
LOG_VERSION = 2
# Foundation encodes Date as seconds since 2001-01-01 UTC.
REFERENCE_DATE_EPOCH = 978_307_200

REWRITE_THRESHOLD = 0.40
IDENTIFIER = re.compile(r"\d|[a-z][A-Z]|\w[._/]\w")
SENTENCE_PUNCTUATION = ".,!?;:"
# What the engine returns when it heard breathing rather than speech. A one-word dictation is
# otherwise ordinary — "Hello." is a real thing to say to a microphone.
FILLERS = frozenset({"uh", "um", "hmm", "mhm", "huh", "ah", "oh", "mm"})
HALLUCINATION_BOILERPLATE = (
    "thanks for watching",
    "thank you for watching",
    "please subscribe",
    "like and subscribe",
    "subtitles by",
    "transcription by",
    "amara.org",
    "www.",
)
FUNCTION_WORDS = """a an and are as at be been but by do does did for from had has have he her
his i if in is it its me my no not of on or our she so than that the their them then there these
they this to too us was we were what when which who will with would you your it's i'm don't we're
that's can could should just like about"""
STOPWORDS = frozenset(FUNCTION_WORDS.split())


@dataclass(frozen=True)
class Entry:
    """One dictation, flattened to what triage asks of it: the newest transcription's raw text,
    whatever the cleanup pass made of it, and where to listen."""

    id: str
    created_at: datetime.datetime
    target_app: str | None
    raw: str
    engine: str
    cleaned: str | None
    cleanup_model: str | None
    audio: Path | None


def transcription(entry: dict[str, Any]) -> dict[str, Any] | None:
    """HistoryEntry.currentTranscription — the newest opinion on the audio, original included."""
    retranscriptions = entry["retranscriptions"]
    if retranscriptions:
        return retranscriptions[-1]
    return entry.get("original")


def load_entries(history_file: Path, audio_directory: Path) -> tuple[list[Entry], int]:
    """The history log is untrusted input: its version is checked once, its shape is conformed
    once, and everything downstream reads `Entry`. Returns the entries that reached transcription
    and the count of those that did not — a dictation can die before the engine answers."""
    log = json.loads(history_file.read_text(encoding="utf-8"))
    if log["version"] != LOG_VERSION:
        sys.exit(
            f"{history_file}: history log version {log['version']}; this reads {LOG_VERSION}"
        )

    entries, unfinished = [], 0
    for record in log["entries"]:
        current = transcription(record)
        if current is None:
            unfinished += 1
            continue
        cleanup = current.get("cleanup")
        cleaned = cleanup["disposition"].get("text") if cleanup else None
        audio = audio_directory / f"{record['id']}.wav"
        target_app = record.get("targetApp")
        entries.append(
            Entry(
                id=record["id"],
                created_at=datetime.datetime.fromtimestamp(
                    record["createdAt"] + REFERENCE_DATE_EPOCH, datetime.UTC
                ).astimezone(),
                target_app=target_app["name"] or target_app["bundleID"]
                if target_app
                else None,
                raw=current["text"],
                engine=current["engine"],
                cleaned=cleaned,
                cleanup_model=cleanup["model"] if cleanup else None,
                audio=audio if record.get("audio") and audio.exists() else None,
            )
        )
    return entries, unfinished


@dataclass(frozen=True)
class Flag:
    heuristic: str
    weight: float
    reason: str


def repeated_loop(tokens: list[str]) -> str | None:
    """A decoder that stopped advancing says the same n-gram three times in a row."""
    for size in (1, 2, 3, 4):
        for start in range(len(tokens) - size * 3 + 1):
            window = tokens[start : start + size]
            repeats = 1
            while (
                tokens[start + size * repeats : start + size * (repeats + 1)] == window
            ):
                repeats += 1
            if repeats >= 3:
                return f"{' '.join(window)!r} repeated {repeats} times in a row"
    return None


def suspicious_raw(entry: Entry) -> Flag | None:
    tokens = normalize(entry.raw)
    if not tokens or (len(tokens) == 1 and tokens[0] in FILLERS):
        return Flag(
            "suspicious-raw",
            2.0,
            f"near-empty transcript ({entry.raw.strip()!r}) — the gate let through "
            "something that was probably not speech",
        )
    if len(tokens) > 1 and len(set(tokens)) == 1:
        return Flag(
            "suspicious-raw",
            2.0,
            f"the whole transcript is {tokens[0]!r} repeated {len(tokens)} times",
        )
    lowered = entry.raw.lower()
    for phrase in HALLUCINATION_BOILERPLATE:
        if phrase in lowered:
            return Flag(
                "suspicious-raw",
                2.0,
                f"canned ASR hallucination: contains {phrase!r}, which belongs to training "
                "captions rather than to this microphone",
            )
    loop = repeated_loop(tokens)
    if loop:
        return Flag("suspicious-raw", 2.0, f"decoder loop: {loop}")
    return None


def cleanup_rewrite(entry: Entry) -> Flag | None:
    """Cleanup is meant to polish, not to paraphrase. Past a threshold it is doing something the
    speaker did not ask for, and the diff is the evidence."""
    if entry.cleaned is None:
        return None
    raw, cleaned = normalize(entry.raw), normalize(entry.cleaned)
    if not raw:
        return None
    substitutions, deletions, insertions = edits(raw, cleaned)
    changed = (substitutions + deletions + insertions) / len(raw)
    if changed <= REWRITE_THRESHOLD:
        return None
    return Flag(
        "cleanup-rewrite",
        1.0 + changed,
        f"cleanup changed {changed * 100:.0f}% of the {len(raw)} transcribed words "
        f"({substitutions}S {deletions}D {insertions}I)",
    )


def identifiers(text: str) -> list[str]:
    """Numbers, versions, and anything wearing an identifier's punctuation — the tokens whose
    exact form is the content, so losing one loses the dictation's point."""
    return [
        token
        for token in text.split()
        if IDENTIFIER.search(token.strip(SENTENCE_PUNCTUATION))
    ]


def dropped_identifiers(entry: Entry) -> Flag | None:
    if entry.cleaned is None:
        return None
    folded = entry.cleaned.lower()
    dropped = [
        token
        for token in identifiers(entry.raw)
        if token.strip(SENTENCE_PUNCTUATION).lower() not in folded
    ]
    if not dropped:
        return None
    return Flag(
        "dropped-identifier",
        2.5,
        f"cleanup dropped {', '.join(repr(token) for token in dropped)} — "
        "numbers and identifiers survive polish or the dictation was rewritten",
    )


def added_content(entry: Entry) -> Flag | None:
    """The most dangerous class: a content word in the output that nobody spoke. Inflections are
    forgiven by a shared four-character prefix, so `option`/`options` is polish and `Cerebras` in
    a transcript that never said it is not."""
    if entry.cleaned is None:
        return None
    spoken = set(normalize(entry.raw))
    prefixes = {token[:4] for token in spoken}
    added = [
        token
        for token in dict.fromkeys(normalize(entry.cleaned))
        if token not in spoken and token not in STOPWORDS and token[:4] not in prefixes
    ]
    if not added:
        return None
    return Flag(
        "added-content",
        3.0 + 0.5 * len(added),
        f"cleanup introduced {', '.join(repr(token) for token in added)}, "
        "absent from what the engine heard",
    )


HEURISTICS = (suspicious_raw, cleanup_rewrite, dropped_identifiers, added_content)
HEURISTIC_NAMES = (
    "suspicious-raw",
    "cleanup-rewrite",
    "dropped-identifier",
    "added-content",
)


@dataclass(frozen=True)
class Suspect:
    entry: Entry
    flags: list[Flag]

    @property
    def score(self) -> float:
        return sum(flag.weight for flag in self.flags)


def triage(entries: list[Entry]) -> list[Suspect]:
    suspects = []
    for entry in entries:
        flags = [flag for flag in (test(entry) for test in HEURISTICS) if flag]
        if flags:
            suspects.append(Suspect(entry, flags))
    return sorted(suspects, key=lambda suspect: (-suspect.score, suspect.entry.id))


def quote(text: str) -> str:
    return "\n".join(f"> {line}" if line else ">" for line in text.splitlines())


def render(
    suspects: list[Suspect], entries: list[Entry], unfinished: int, history_file: Path
) -> str:
    counts = dict.fromkeys(HEURISTIC_NAMES, 0)
    for suspect in suspects:
        for flag in suspect.flags:
            counts[flag.heuristic] += 1
    cleaned = sum(1 for entry in entries if entry.cleaned is not None)
    audible = sum(1 for entry in entries if entry.audio)

    lines = [
        "# History triage",
        "",
        f"`{history_file}` — {len(entries)} transcribed entries "
        f"({cleaned} with a cleanup pass, {audible} with audio still in the vault; "
        f"{unfinished} entries never reached transcription and are not scored).",
        "",
        f"**{len(suspects)} flagged**, ranked most suspicious first.",
        "",
        "| heuristic | entries |",
        "| --- | --- |",
    ]
    lines += [f"| {name} | {count} |" for name, count in counts.items()]
    lines.append("")

    for rank, suspect in enumerate(suspects, start=1):
        entry = suspect.entry
        heading = f"## {rank}. {entry.created_at:%Y-%m-%d %H:%M}"
        if entry.target_app:
            heading += f" — {entry.target_app}"
        lines += [heading, "", f"score {suspect.score:.1f} · `{entry.id}`", ""]
        lines += [f"- **{flag.heuristic}** — {flag.reason}" for flag in suspect.flags]
        lines += [
            "",
            f"Audio: `{entry.audio}`"
            if entry.audio
            else "Audio: not retained — adjudicate from the text alone.",
            "",
            "Raw:",
            "",
            quote(entry.raw),
            "",
        ]
        if entry.cleaned is not None:
            lines += [
                f"Cleaned ({entry.cleanup_model}):",
                "",
                quote(entry.cleaned),
                "",
                "Diff:",
                "",
                f"```\n{word_diff(normalize(entry.raw), normalize(entry.cleaned))}\n```",
                "",
            ]
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--history",
        type=Path,
        default=DEV_HISTORY_DIRECTORY,
        help="The channel's History directory, holding history.json and audio/.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help="Where to write the ranked markdown report.",
    )
    args = parser.parse_args()

    entries, unfinished = load_entries(
        args.history / "history.json", args.history / "audio"
    )
    suspects = triage(entries)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        render(suspects, entries, unfinished, args.history / "history.json"),
        encoding="utf-8",
    )

    print(f"{len(entries)} transcribed entries, {len(suspects)} flagged")
    for suspect in suspects[:10]:
        heuristics = ", ".join(flag.heuristic for flag in suspect.flags)
        print(f"  {suspect.score:5.1f}  {suspect.entry.id}  {heuristics}")
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
