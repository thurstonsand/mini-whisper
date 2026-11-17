#!/usr/bin/env python3
"""Collect one screen-context scene: every capture source, the spoken line, and optionally a live
dictation through MiniWhisper Dev, into recordings/stage4-screen/<id>/.

  capture/      screen-collect's output: ax, tmux, ocr, field, screenshots, timings
  say.wav       the line rendered by `say` at 16 kHz mono, for asr-replay
  scene.json    the stage entry this scene was staged from
  app/          with --live: the History entry MiniWhisper Dev wrote, its WAV and its JPEG

The scene must already be on screen with the dictation's text box focused, except kind "vscode",
which this stages itself: it opens the file at the line and focuses the Chat input.

  ./collect.py --id screen-vscode-01 --live
  ./collect.py --id screen-pi-tmux-01 --tmux-socket /tmp/tmux-501/pi --tmux-pane %0 --live
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import time

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
CORPUS = REPO / "docs/wayfinding/finishing-mini-whisper/assets/43-dictation-corpus"
COLLECTOR = HERE / ".build/release/screen-collect"
HOTKEY = HERE / ".build/release/hotkey"
CODE = "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
HISTORY = Path.home() / "Library/Application Support/MiniWhisper Dev/History"


def cua(tool: str, args: dict) -> dict:
    result = subprocess.run(
        ["cua-driver", "call", tool],
        input=json.dumps(args),
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout) if result.stdout.strip().startswith("{") else {}


def pid_of(name: str) -> int:
    return int(
        subprocess.run(
            ["pgrep", "-x", name], capture_output=True, text=True
        ).stdout.split()[0]
    )


def stage_vscode(scene: dict) -> None:
    subprocess.run(
        [CODE, "--reuse-window", "-g", f"{REPO / scene['file']}:{scene['line']}"],
        check=True,
    )
    time.sleep(2)
    pid = pid_of("Code")
    cua("bring_to_front", {"pid": pid})
    time.sleep(0.5)
    # Focus Chat, then empty it, so the dictation's field is the blank agent prompt.
    cua(
        "hotkey",
        {"pid": pid, "keys": ["ctrl", "cmd", "i"], "delivery_mode": "foreground"},
    )
    time.sleep(0.7)
    cua("hotkey", {"pid": pid, "keys": ["cmd", "a"], "delivery_mode": "foreground"})
    cua("press_key", {"pid": pid, "key": "delete", "delivery_mode": "foreground"})
    time.sleep(0.5)


def entries() -> list[dict]:
    return json.loads((HISTORY / "history.json").read_text())["entries"]


def dictate(line: str, out: Path) -> None:
    before = {entry["id"] for entry in entries()}
    subprocess.run([HOTKEY, "down"], check=True)
    time.sleep(0.4)
    subprocess.run(["say", "-a", "BlackHole 2ch", line], check=True)
    time.sleep(0.4)
    subprocess.run([HOTKEY, "up"], check=True)
    for _ in range(40):
        time.sleep(0.5)
        fresh = [
            entry
            for entry in entries()
            if entry["id"] not in before and entry.get("delivery")
        ]
        if fresh:
            entry = fresh[0]
            app = out / "app"
            app.mkdir(exist_ok=True)
            (app / "entry.json").write_text(
                json.dumps(entry, ensure_ascii=False, indent=1)
            )
            for suffix in ("wav", "jpg"):
                media = HISTORY / "audio" / f"{entry['id']}.{suffix}"
                if media.exists():
                    shutil.copy(media, app / f"dictation.{suffix}")
            print(
                f"  live: {entry['original']['text']!r} -> {entry['delivery']['text']!r}"
            )
            return
    raise SystemExit("no History entry was delivered within 20 s")


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument("--stage", type=Path, default=CORPUS / "stage4-screen.jsonl")
    parser.add_argument("--id", required=True)
    parser.add_argument("--out", type=Path, default=CORPUS / "recordings/stage4-screen")
    parser.add_argument(
        "--live", action="store_true", help="Also dictate it through MiniWhisper Dev."
    )
    parser.add_argument("--tmux-socket")
    parser.add_argument("--tmux-pane")
    args = parser.parse_args()

    entry = next(
        json.loads(line)
        for line in args.stage.read_text().splitlines()
        if line.strip() and json.loads(line)["id"] == args.id
    )
    out = args.out / entry["id"]
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    (out / "scene.json").write_text(json.dumps(entry, ensure_ascii=False, indent=1))

    if entry["scene"]["kind"] == "vscode":
        stage_vscode(entry["scene"])
    tmux = (
        ["--tmux-socket", args.tmux_socket, "--tmux-pane", args.tmux_pane]
        if args.tmux_socket
        else []
    )
    subprocess.run([COLLECTOR, "--out", out / "capture", *tmux], check=True)
    subprocess.run(
        [
            "say",
            "-o",
            out / "say.wav",
            "--file-format=WAVE",
            "--data-format=LEI16@16000",
            entry["say"],
        ],
        check=True,
    )
    if args.live:
        dictate(entry["say"], out)


if __name__ == "__main__":
    main()
