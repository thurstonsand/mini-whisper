#!/usr/bin/env python3
"""Prompt-by-prompt recorder for the dictation corpus.

Reads a stage JSONL, shows each script, and records one 16 kHz mono WAV per
entry via a small AVAudioEngine recorder (mic-record.swift, compiled on first
use). Files land in recordings/<stage>/<id>.wav; an existing file marks its
entry recorded, so the session resumes wherever it stopped. ffmpeg is still
used for the silence check.

Usage:
  ./record.py stage1-intelligibility.jsonl --label built-in

Capture follows the system input device — switch microphones in System
Settings → Sound. --label suffixes the output directory
(recordings/stage1-intelligibility-built-in/) so the same stage can be
recorded per microphone or listening condition.
"""

import argparse
import json
from pathlib import Path
import re
import signal
import subprocess
import sys
import termios
import textwrap
import wave

MINIMUM_DURATION = 1.0

GREEN = "\033[32m"
RED = "\033[31m"
DIM = "\033[2m"
BOLD = "\033[1m"
RESET = "\033[0m"


def load_entries(path: Path) -> list[dict]:
    entries = []
    for line_number, line in enumerate(path.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        entry = json.loads(line)
        if "id" not in entry or "say" not in entry:
            sys.exit(f"{path}:{line_number}: entry needs 'id' and 'say'")
        entries.append(entry)
    return entries


def recorder_binary() -> Path:
    """Compile mic-record.swift on first use. AVAudioEngine is the same capture
    path the app uses; ffmpeg's avfoundation input drops buffer fragments and
    leaves audible crackle in the takes."""
    source = Path(__file__).parent / "mic-record.swift"
    binary = Path(__file__).parent / ".build" / "mic-record"
    if not binary.exists() or binary.stat().st_mtime < source.stat().st_mtime:
        binary.parent.mkdir(exist_ok=True)
        subprocess.run(["swiftc", "-O", str(source), "-o", str(binary)], check=True)
    return binary


def record(binary: Path, out: Path) -> bool:
    """Record until Enter, then finalize the WAV. Returns False on failure."""
    proc = subprocess.Popen(
        [str(binary), str(out)],
        stdin=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    print(f"  {RED}● recording{RESET} — Enter to stop", end="", flush=True)
    # A second Enter queued behind the one that armed the recorder would be read
    # here instantly and end the take before a word of it.
    termios.tcflush(sys.stdin, termios.TCIFLUSH)
    input()
    try:
        proc.stdin.write(b"\n")
        proc.stdin.flush()
        proc.stdin.close()
        proc.wait(timeout=3)
    except BrokenPipeError, subprocess.TimeoutExpired:
        proc.send_signal(signal.SIGINT)
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
    if proc.returncode != 0 or not out.exists() or out.stat().st_size < 1024:
        stderr = proc.stderr.read().decode(errors="replace").strip()
        print(f"\n  {RED}recorder failed{RESET}: {stderr or f'exit {proc.returncode}'}")
        out.unlink(missing_ok=True)
        return False
    with wave.open(str(out)) as wav:
        duration = wav.getnframes() / wav.getframerate()
    if duration < MINIMUM_DURATION:
        print(
            f"\n  {RED}too short{RESET} — {duration:.2f}s; the take ended before the script did"
        )
        out.unlink()
        return False
    volume = subprocess.run(
        ["ffmpeg", "-i", str(out), "-af", "volumedetect", "-f", "null", "-"],
        capture_output=True,
        text=True,
    ).stderr
    if (match := re.search(r"max_volume: (-?[\d.]+) dB", volume)) and float(
        match.group(1)
    ) < -60:
        print(
            f"\n  {RED}recorded silence{RESET} — wrong input device? "
            f"({match.group(1)} dB peak; check System Settings → Sound)"
        )
        out.unlink()
        return False
    return True


def show(entry: dict, position: int, total: int) -> None:
    print("\033[2J\033[H", end="")
    print(f"{DIM}[{position}/{total}]{RESET} {BOLD}{entry['id']}{RESET}", end="")
    if tags := entry.get("tags"):
        print(f"  {DIM}{', '.join(tags)}{RESET}", end="")
    print("\n")
    for line in entry["say"].split("\n"):
        print(
            textwrap.fill(line, width=76, initial_indent="  ", subsequent_indent="  ")
        )
    print()
    if wants := entry.get("wants"):
        print(f"  {DIM}dictionary terms in play: {', '.join(wants)}{RESET}")
    if traps := entry.get("traps"):
        print(f"  {DIM}must NOT surface: {', '.join(traps)}{RESET}")
    if entry.get("context"):
        print(
            f"  {DIM}staged field context rides along at eval time — just read the script{RESET}"
        )
    print()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("stage", type=Path, help="stage JSONL file")
    parser.add_argument(
        "--label", help="condition label suffixing the output directory"
    )
    parser.add_argument(
        "--redo", action="store_true", help="re-record entries that already have audio"
    )
    parser.add_argument(
        "--only", nargs="+", metavar="ID", help="re-record just these entry ids"
    )
    args = parser.parse_args()

    entries = load_entries(args.stage)
    directory = args.stage.stem + (f"-{args.label}" if args.label else "")
    out_dir = args.stage.parent / "recordings" / directory
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.only:
        by_id = {entry["id"]: entry for entry in entries}
        if unknown := [i for i in args.only if i not in by_id]:
            sys.exit(f"unknown ids: {', '.join(unknown)}")
        pending = [by_id[i] for i in args.only]
    else:
        pending = [
            entry
            for entry in entries
            if args.redo or not (out_dir / f"{entry['id']}.wav").exists()
        ]
    done = len(entries) - len(pending)
    if not pending:
        print(f"All {len(entries)} entries already recorded in {out_dir}/")
        return
    print(f"{len(pending)} to record ({done} already done) → {out_dir}/")
    binary = recorder_binary()
    input("Enter to begin")

    for position, entry in enumerate(pending, start=1):
        out = out_dir / f"{entry['id']}.wav"
        while True:
            show(entry, position, len(pending))
            print("  Enter to record, s to skip, q to quit: ", end="", flush=True)
            command = input().strip().lower()
            if command == "q":
                print(f"Stopped. Rerun to resume; recordings are in {out_dir}/")
                return
            if command == "s":
                break
            if not record(binary, out):
                input("  Enter to retry")
                continue
            print(
                f"\n  {GREEN}saved{RESET} — Enter for next, r to redo, p to play: ",
                end="",
                flush=True,
            )
            verdict = input().strip().lower()
            if verdict == "r":
                continue
            if verdict == "p":
                subprocess.run(["afplay", str(out)])
                print("  Enter to keep, r to redo: ", end="", flush=True)
                if input().strip().lower() == "r":
                    continue
            break

    print(f"\nDone. Recordings in {out_dir}/")


if __name__ == "__main__":
    main()
