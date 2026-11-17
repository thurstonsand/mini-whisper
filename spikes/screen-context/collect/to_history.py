#!/usr/bin/env python3
"""Turn collected scenes into History-shaped directories, one per screen source, so
replay_history.py replays the same dictations under each source:

  app    what MiniWhisper Dev sends from these captures: tmux, else the Accessibility walk when it
         placed all it found, else OCR
  ax     the Accessibility walk, composed as the app composes it
  tmux   the pane capture (tmux scenes only)
  ocr    Vision .accurate on the window, composed as the app composes it

Each directory holds history.json and audio/<id>.jpg (the 1x screenshot, for the image arm), and
cases.jsonl scores every entry by its `must` and `forbid` terms. The transcript is the live
dictation's raw text, or with --transcripts, an asr-replay JSONL (one {id, transcript} per line):
of each scene's say.wav, or of Thurston's own recordings of the same lines.

  ./to_history.py --out /tmp/screen-eval
  ../eval/replay_history.py --history /tmp/screen-eval/ocr --field-cases /tmp/screen-eval/ocr/cases.jsonl ...
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
CORPUS = (
    HERE.parents[2]
    / "docs/wayfinding/finishing-mini-whisper/assets/43-dictation-corpus"
)
SCENES = CORPUS / "recordings/stage4-screen"
# Expectations are read from the stage file, not the copy each scene kept, so an adjudication
# made after a scene was collected still scores it.
STAGE = CORPUS / "stage4-screen.jsonl"


def screen_context(source: str, capture: Path, meta: dict) -> dict | None:
    if source == "app":
        for chosen in ("tmux", "ax", "ocr"):
            if chosen == "ax" and meta.get("axUnplaced"):
                continue
            if screen := screen_context(chosen, capture, meta):
                return screen
        return None
    path = capture / f"{source}.txt"
    if not path.exists() or not path.read_text().strip():
        return None
    text = path.read_text()
    title = meta.get("windowTitle")
    if source == "ocr":
        return {"windowTitle": title, "recognizedText": text}
    return {
        "windowTitle": title,
        "structured": {
            "source": "accessibility" if source == "ax" else "tmux",
            "text": text,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument("--scenes", type=Path, default=SCENES)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument(
        "--transcripts",
        type=Path,
        help="asr-replay JSONL to use instead of the live raw text.",
    )
    args = parser.parse_args()
    transcripts = {}
    if args.transcripts:
        for line in args.transcripts.read_text().splitlines():
            if line.strip():
                row = json.loads(line)
                transcripts[row["id"]] = row["transcript"]

    specs = {
        spec["id"]: spec
        for spec in map(json.loads, STAGE.read_text().splitlines())
        if spec
    }
    for source in ("app", "ax", "tmux", "ocr"):
        out = args.out / source
        if out.exists():
            shutil.rmtree(out)
        (out / "audio").mkdir(parents=True)
        entries, cases = [], []
        for scene_dir in sorted(
            p for p in args.scenes.iterdir() if (p / "scene.json").exists()
        ):
            scene = json.loads((scene_dir / "scene.json").read_text())
            capture = scene_dir / "capture"
            meta = json.loads((capture / "meta.json").read_text())
            screen = screen_context(source, capture, meta)
            if screen is None:
                continue
            field = json.loads((capture / "field.json").read_text())
            entries.append(
                {
                    "id": scene["id"],
                    "original": {
                        "text": transcripts[scene["id"]]
                        if args.transcripts
                        else json.loads((scene_dir / "app/entry.json").read_text())[
                            "original"
                        ]["text"]
                    },
                    "fieldContext": field,
                    "screenContext": screen,
                    "screenshot": {
                        "byteCount": (capture / "screen-1x.jpg").stat().st_size
                    },
                    "targetApp": {"bundleID": meta["bundleID"]},
                }
            )
            shutil.copy(capture / "screen-1x.jpg", out / "audio" / f"{scene['id']}.jpg")
            cases.append(
                {
                    "source": scene["id"],
                    "must": specs[scene["id"]]["must"],
                    "forbid": specs[scene["id"]].get("forbid", []),
                }
            )
        (out / "history.json").write_text(
            json.dumps({"version": 1, "entries": entries}, ensure_ascii=False)
        )
        (out / "cases.jsonl").write_text(
            "".join(json.dumps(c, ensure_ascii=False) + "\n" for c in cases)
        )
        print(f"{source:<5} {len(entries)} entries -> {out}")


if __name__ == "__main__":
    main()
