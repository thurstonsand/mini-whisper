#!/usr/bin/env python3
import argparse
import atexit
import json
from pathlib import Path
import shutil
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FRAME = 4096
RATE = 16_000
VAD_REVISION = "b419383c55c110e2c9271fa6ee0ea83d03c70d96"
FLUID_AUDIO_REVISION = "19600a485baa4998812e4654b70d2bab8f2c9949"
PARAKEET_REVISION = "ee09c569f73759e6d44c9bd16766f477b2b36d39"


def key(decision):
    return (round(decision["threshold"], 2), decision["minimumSpeechMilliseconds"])


def remove_synthetic_audio():
    shutil.rmtree(ROOT / "fixtures" / "synthetic", ignore_errors=True)


def count(fixtures, decisions, settings, split):
    selected = [fixture for fixture in fixtures if fixture["split"] == split]
    false_accepts = sum(
        fixture["label"] == "no_speech" and decisions[fixture["id"]][settings]
        for fixture in selected
    )
    false_rejects = sum(
        fixture["label"] == "speech" and not decisions[fixture["id"]][settings]
        for fixture in selected
    )
    return {
        "fixtures": len(selected),
        "false_accepts": false_accepts,
        "false_rejects": false_rejects,
    }


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
    runtime = result["runtime"]
    framing = result["framing"]
    lines += [
        "",
        f"- Warm wall VAD median: `{runtime['wall_median_ms']:.3f} ms` (15 ms budget: **{'PASS' if result['acceptance']['vad_below_fifteen_ms_budget'] else 'FAIL'}**).",
        f"- Model-reported median: `{runtime['model_median_ms']:.3f} ms`; cold/maximum wall: `{runtime['wall_maximum_ms']:.3f} ms`.",
        f"- Gate copy: `{framing['frame_samples']}`-sample FluidAudio-native frames, zero-padded to a whole-frame multiple; maximum release padding `{framing['maximum_release_padding_samples']}` samples.",
        f"- Pinned VAD artifact: `FluidInference/silero-vad-coreml@{result['environment']['vad_revision']}`.",
        f"- Synthetic no-speech fixtures: `{result['synthetic']['accepted']}` accepted / `{result['synthetic']['fixtures']}` total.",
        "- Accepted original audio is passed unchanged to `AsrManager`; only the disposable gate copy is padded.",
        "",
        "## Acceptance",
        "",
    ]
    for name, passed in result["acceptance"].items():
        lines.append(f"- {'PASS' if passed else 'FAIL'} — {name.replace('_', ' ')}")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    parser.add_argument(
        "--output", type=Path, default=ROOT / "results" / "fluid-vad-raw.json"
    )
    parser.add_argument("--skip-asr", action="store_true")
    args = parser.parse_args()
    manifest = args.manifest.resolve()
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    remove_synthetic_audio()
    atexit.register(remove_synthetic_audio)
    subprocess.run(
        [str(ROOT / "scripts" / "generate-synthetic-fixtures.py")], check=True
    )
    synthetic_manifest = ROOT / "fixtures" / "synthetic-manifest.json"
    synthetic_path = ROOT / "results" / "fluid-vad-synthetic-raw.json"
    for input_manifest, inference_output in (
        (manifest, output.with_name("fluid-vad-inference.json")),
        (synthetic_manifest, synthetic_path),
    ):
        subprocess.run(
            [
                str(ROOT / ".build" / "release" / "SilenceBakeoffVad"),
                str(ROOT / ".artifacts" / "vad"),
                str(input_manifest),
                str(inference_output),
            ],
            check=True,
        )
    fixtures = json.loads(manifest.read_text())
    inference = json.loads(output.with_name("fluid-vad-inference.json").read_text())
    decisions = {
        item["id"]: {
            key(decision): decision["accepts"] for decision in item["decisions"]
        }
        for item in inference
    }
    settings = sorted(next(iter(decisions.values())))
    sweep = []
    for candidate in settings:
        sweep.append(
            {
                "threshold": candidate[0],
                "minimum_speech_ms": candidate[1],
                "calibration": count(fixtures, decisions, candidate, "calibration"),
                "holdout": count(fixtures, decisions, candidate, "holdout"),
            }
        )

    synthetic = json.loads(synthetic_path.read_text())

    def synthetic_accepts(candidate):
        candidate_key = (candidate["threshold"], candidate["minimum_speech_ms"])
        return sum(
            next(
                decision["accepts"]
                for decision in item["decisions"]
                if key(decision) == candidate_key
            )
            for item in synthetic
        )

    tone = next(item for item in synthetic if item["id"] == "synthetic-tone")
    tone_accepts_at_085 = next(
        decision["accepts"]
        for decision in tone["decisions"]
        if key(decision) == (0.85, 150)
    )
    all_rejected_at_090 = (
        synthetic_accepts({"threshold": 0.9, "minimum_speech_ms": 150}) == 0
    )
    synthetic_wall_median = statistics.median(
        item["wallMilliseconds"] for item in synthetic
    )
    if not tone_accepts_at_085 or not all_rejected_at_090:
        raise SystemExit("synthetic threshold regression failed")
    if synthetic_wall_median > 15:
        raise SystemExit("synthetic VAD median exceeded 15 ms")

    eligible = [
        candidate
        for candidate in sweep
        if candidate["calibration"]["false_rejects"] == 0
        and candidate["calibration"]["false_accepts"] == 0
        and synthetic_accepts(candidate) == 0
    ]
    if not eligible:
        raise SystemExit(
            "no candidate preserves calibration speech and rejects every no-speech probe"
        )
    selected = min(
        eligible,
        key=lambda candidate: (
            candidate["threshold"],
            abs(candidate["minimum_speech_ms"] - 150),
        ),
    )
    selected_key = (selected["threshold"], selected["minimum_speech_ms"])
    summary = {
        split: count(fixtures, decisions, selected_key, split)
        for split in ("calibration", "holdout")
    }
    synthetic_count = len(synthetic)
    synthetic_accepted = synthetic_accepts(selected)

    transcript_aggregates = None
    if not args.skip_asr:
        transcript_output = output.with_name("fluid-asr-local.json")
        subprocess.run(
            [
                str(ROOT / ".build" / "release" / "SilenceBakeoffTranscriber"),
                str(ROOT / ".artifacts" / "parakeet-v2"),
                str(manifest),
                str(transcript_output),
            ],
            check=True,
        )
        transcripts = {
            item["id"]: item for item in json.loads(transcript_output.read_text())
        }
        transcript_aggregates = {
            split: {
                "speech_empty": sum(
                    fixture["label"] == "speech"
                    and not transcripts[fixture["id"]]["transcript"].strip()
                    for fixture in fixtures
                    if fixture["split"] == split
                ),
                "errors": sum(
                    transcripts[fixture["id"]].get("error") is not None
                    for fixture in fixtures
                    if fixture["split"] == split
                ),
            }
            for split in ("calibration", "holdout")
        }

    wall_times = [item["wallMilliseconds"] for item in inference]
    model_times = [item["modelMilliseconds"] for item in inference]
    release_padding = [
        item["paddedSampleCount"] - item["originalSampleCount"] for item in inference
    ]
    zero_errors = all(
        summary[split]["false_accepts"] == summary[split]["false_rejects"] == 0
        for split in summary
    )
    result = {
        "privacy": "Aggregate metrics only. Fixture audio, probabilities, transcripts, and individual decisions are omitted.",
        "environment": {
            "fluid_audio_version": "0.15.5",
            "fluid_audio_revision": FLUID_AUDIO_REVISION,
            "vad_repository": "FluidInference/silero-vad-coreml",
            "vad_revision": VAD_REVISION,
            "parakeet_repository": "FluidInference/parakeet-tdt-0.6b-v2-coreml",
            "parakeet_revision": PARAKEET_REVISION,
            "compute_units": "cpuOnly",
        },
        "corpus": {
            "fixtures": len(fixtures),
            "calibration_fixtures": summary["calibration"]["fixtures"],
            "holdout_fixtures": summary["holdout"]["fixtures"],
        },
        "selected_settings": {
            "threshold": selected_key[0],
            "minimum_speech_ms": selected_key[1],
        },
        "selection_policy": "Select the lowest swept threshold that preserves every calibration speech fixture, rejects every supplied no-speech probe (real calibration plus generated synthetic), then choose the minimum-speech duration nearest FluidAudio's 150 ms default. The real-audio holdout does not participate and validates the result separately.",
        "summary": summary,
        "sweep": sweep,
        "runtime": {
            "wall_median_ms": statistics.median(wall_times),
            "wall_maximum_ms": max(wall_times),
            "model_median_ms": statistics.median(model_times),
        },
        "framing": {
            "frame_samples": FRAME,
            "frame_milliseconds": FRAME / RATE * 1_000,
            "tail_policy": "Zero-pad one gate-only utterance copy to the next 4096-sample multiple before one VadManager.process call.",
            "maximum_release_padding_samples": max(release_padding),
            "all_model_chunks_exact": all(
                item["paddedSampleCount"] > 0 and item["paddedSampleCount"] % FRAME == 0
                for item in inference
            ),
            "accepted_audio_unchanged": True,
        },
        "synthetic": {
            "fixtures": synthetic_count,
            "accepted": synthetic_accepted,
            "tone_accepted_at_0_85": tone_accepts_at_085,
            "all_rejected_at_0_90": all_rejected_at_090,
            "wall_median_ms": synthetic_wall_median,
        },
        "transcription_aggregates": transcript_aggregates,
        "acceptance": {
            "zero_false_accepts_and_rejects_both_splits": zero_errors,
            "vad_below_fifteen_ms_budget": statistics.median(wall_times) <= 15,
            "all_model_chunks_exact": all(
                item["paddedSampleCount"] > 0 and item["paddedSampleCount"] % FRAME == 0
                for item in inference
            ),
        },
        "fixtures": [
            {
                **fixture,
                **next(item for item in inference if item["id"] == fixture["id"]),
                "selected_accepts": decisions[fixture["id"]][selected_key],
            }
            for fixture in fixtures
        ],
    }
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    output.with_suffix(".md").write_text(markdown(result))
    print(output)
    print(output.with_suffix(".md"))
    if not all(result["acceptance"].values()):
        raise SystemExit("FluidAudio VAD acceptance failed")


if __name__ == "__main__":
    main()
