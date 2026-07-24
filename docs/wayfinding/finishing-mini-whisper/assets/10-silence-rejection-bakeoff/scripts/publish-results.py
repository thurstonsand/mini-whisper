#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="Publish aggregate bakeoff results without fixture-level data.")
    parser.add_argument("raw", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    raw = json.loads(args.raw.read_text())

    speech_empty_by_split = {}
    no_speech_hallucinations_by_split = {}
    for split in ("calibration", "holdout"):
        fixtures = [fixture for fixture in raw["fixtures"] if fixture["split"] == split]
        speech_empty_by_split[split] = sum(
            fixture["label"] == "speech" and not (fixture.get("no_gate_transcript") or "").strip()
            for fixture in fixtures
        )
        no_speech_hallucinations_by_split[split] = sum(
            fixture["label"] == "no_speech" and bool((fixture.get("no_gate_transcript") or "").strip())
            for fixture in fixtures
        )

    result = {
        "privacy": "Aggregate metrics only. Fixture audio, transcripts, probabilities, timelines, and individual decisions are omitted.",
        "environment": raw["environment"],
        "corpus": {
            "fixtures": len(raw["fixtures"]),
            "calibration_fixtures": raw["summary"]["calibration"]["fixtures"],
            "holdout_fixtures": raw["summary"]["holdout"]["fixtures"],
        },
        "selected_settings": raw["selected_settings"],
        "summary": raw["summary"],
        "calibration_sweep": raw["calibration_sweep"],
        "rms_baselines": raw["rms_baselines"],
        "runtime": raw["runtime"],
        "boundary": raw["boundary"],
        "acceptance": raw["acceptance"],
        "transcription_aggregates": {
            "speech_empty_by_split": speech_empty_by_split,
            "no_speech_nonempty_without_gate_by_split": no_speech_hallucinations_by_split,
        },
        "conclusions": [
            "Select Silero v6.2 at threshold 0.35 and minimum speech 250 ms.",
            "Pass accepted utterances to FluidAudio unchanged; the gate does not trim, chunk, or stitch.",
            "RMS baselines do not satisfy the speech/no-speech acceptance bar.",
            "Two accepted short-word speech fixtures produced empty Parakeet transcripts.",
        ],
    }
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")

    selected = result["selected_settings"]
    lines = [
        "# Silence rejection bakeoff aggregate results",
        "",
        "Only aggregates and conclusions are published. Private WAVs, transcripts, frame probabilities, timelines, and per-fixture decisions remain local and gitignored.",
        "",
        f"Selected on calibration: Silero threshold `{selected['threshold']}`, minimum speech `{selected['minimum_speech_ms']} ms`.",
        "",
        "| Split | Fixtures | False accepts | False rejects | Final nonempty no-speech transcripts | Skipped decodes | Empty speech transcripts |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for split in ("calibration", "holdout"):
        summary = result["summary"][split]
        lines.append(
            f"| {split} | {summary['fixtures']} | {summary['false_accepts']} | {summary['false_rejects']} | {summary['final_nonempty_no_speech_transcripts']} | {summary['skipped_decodes']} | {speech_empty_by_split[split]} |"
        )

    lines += [
        "",
        "| RMS baseline | Threshold | Calibration FA / FR | Holdout FA / FR |",
        "| --- | ---: | ---: | ---: |",
    ]
    for baseline in result["rms_baselines"]:
        lines.append(
            f"| {baseline['shape']} | {baseline['threshold']:.3f} | {baseline['calibration']['false_accepts']} / {baseline['calibration']['false_rejects']} | {baseline['holdout']['false_accepts']} / {baseline['holdout']['false_rejects']} |"
        )

    lines += [
        "",
        f"- Median VAD runtime: `{result['runtime']['vad_median_ms']:.1f} ms`.",
        f"- Median decoder runtime: `{result['runtime']['decoder_median_ms']:.1f} ms`.",
        f"- Irregular-buffer probability delta: `{result['boundary']['maximum_probability_delta']}`.",
        f"- MVP onset clipping: `{result['boundary']['mvp_onset_clipping_ms']} ms`.",
        f"- Future endpoint confirmation: `{result['boundary']['future_endpoint_confirmation_median_ms']:.0f} ms` median, `{result['boundary']['future_endpoint_confirmation_maximum_ms']:.0f} ms` maximum.",
        "",
        "## Conclusions",
        "",
    ]
    lines.extend(f"- {conclusion}" for conclusion in result["conclusions"])
    args.output.with_suffix(".md").write_text("\n".join(lines) + "\n")
    print(args.output)
    print(args.output.with_suffix(".md"))


if __name__ == "__main__":
    main()
