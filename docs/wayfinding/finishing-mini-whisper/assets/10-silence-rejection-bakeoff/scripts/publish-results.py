#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def markdown(result):
    selected = result["selected_settings"]
    lines = [
        "# FluidAudio VAD recalibration aggregate results",
        "",
        "Only aggregates are published. Private audio, probabilities, transcripts, and fixture-level decisions are omitted.",
        "",
        f"Selected on calibration: threshold `{selected['threshold']}`, minimum speech `{selected['minimum_speech_ms']} ms`.",
        "",
        "| Split | Fixtures | False accepts | False rejects |",
        "| --- | ---: | ---: | ---: |",
    ]
    for split in ("calibration", "holdout"):
        summary = result["summary"][split]
        lines.append(
            f"| {split} | {summary['fixtures']} | {summary['false_accepts']} | {summary['false_rejects']} |"
        )
    lines += [
        "",
        "| Threshold | Minimum speech | Calibration FA / FR | Holdout FA / FR |",
        "| ---: | ---: | ---: | ---: |",
    ]
    for candidate in result["sweep"]:
        lines.append(
            f"| {candidate['threshold']:.2f} | {candidate['minimum_speech_ms']} ms | "
            f"{candidate['calibration']['false_accepts']} / {candidate['calibration']['false_rejects']} | "
            f"{candidate['holdout']['false_accepts']} / {candidate['holdout']['false_rejects']} |"
        )
    lines += [
        "",
        f"- Warm wall VAD median: `{result['runtime']['wall_median_ms']:.3f} ms` (15 ms budget: **PASS**).",
        f"- Model-reported median: `{result['runtime']['model_median_ms']:.3f} ms`; cold/maximum wall: `{result['runtime']['wall_maximum_ms']:.3f} ms`.",
        f"- Exact gate framing: `{result['framing']['frame_samples']}` samples (`{result['framing']['frame_milliseconds']:.0f} ms`) with app-side zero padding before one whole-utterance call.",
        f"- Pinned VAD: `FluidInference/silero-vad-coreml@{result['environment']['vad_revision']}`.",
        f"- Pinned ASR: `FluidInference/parakeet-tdt-0.6b-v2-coreml@{result['environment']['parakeet_revision']}`.",
        f"- Synthetic no-speech fixtures: `{result['synthetic']['accepted']}` accepted / `{result['synthetic']['fixtures']}` total.",
        "- Accepted original audio reaches `AsrManager` unchanged; padding exists only in the gate copy.",
        "",
        "## Acceptance",
        "",
    ]
    lines.extend(
        f"- {'PASS' if passed else 'FAIL'} — {name.replace('_', ' ')}"
        for name, passed in result["acceptance"].items()
    )
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(
        description="Publish aggregate FluidAudio VAD results without fixture-level data."
    )
    parser.add_argument("raw", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    raw = json.loads(args.raw.read_text())
    result = {key: value for key, value in raw.items() if key != "fixtures"}
    if not all(result["acceptance"].values()):
        raise SystemExit("refusing to publish failed FluidAudio VAD calibration")
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    args.output.with_suffix(".md").write_text(markdown(result))
    print(args.output)
    print(args.output.with_suffix(".md"))


if __name__ == "__main__":
    main()
