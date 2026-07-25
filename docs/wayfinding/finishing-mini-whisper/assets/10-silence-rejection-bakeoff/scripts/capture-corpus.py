#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(
        description="Capture the private local fixture corpus with ffmpeg."
    )
    parser.add_argument(
        "--manifest", type=Path, default=ROOT / "fixtures" / "local-manifest.json"
    )
    parser.add_argument(
        "--built-in", required=True, help="AVFoundation audio device index"
    )
    parser.add_argument(
        "--work-headset", required=True, help="AVFoundation audio device index"
    )
    args = parser.parse_args()
    manifest = args.manifest.resolve()
    indexes = {"built-in": args.built_in, "approved-work-headset": args.work_headset}
    fixtures = json.loads(manifest.read_text())

    print("Private WAVs remain under fixtures/local/ and are gitignored.")
    for position, fixture in enumerate(fixtures, 1):
        path = manifest.parent / fixture["file"]
        if path.exists():
            print(f"[{position}/{len(fixtures)}] keep {path.name}")
            continue
        print(f"\n[{position}/{len(fixtures)}] {fixture['id']} ({fixture['split']})")
        print(
            f"Device: {fixture['device']} | Room: {fixture['room']} | Duration: {fixture['capture_seconds']} s"
        )
        print(f"Action: {fixture['prompt']}")
        response = input("Enter to record; s to skip; q to quit: ").strip().lower()
        if response == "q":
            break
        if response == "s":
            continue
        subprocess.run(
            [
                str(ROOT / "scripts" / "record.sh"),
                indexes[fixture["device"]],
                str(fixture["capture_seconds"]),
                str(path),
            ],
            check=True,
        )


if __name__ == "__main__":
    main()
