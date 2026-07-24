#!/usr/bin/env python3

import json
import statistics
from pathlib import Path

root = Path(__file__).resolve().parent.parent
raw = root / ".artifacts" / "results"
output = root / "results" / "aggregate.json"


def load(name):
    path = raw / name
    return json.loads(path.read_text()) if path.exists() else None


def public_model(model):
    if not model:
        return None
    allowed = {
        "id",
        "checkpoint",
        "artifact",
        "artifactRevision",
        "repository",
        "revision",
        "filename",
        "quantization",
        "bytes",
        "modelBytes",
        "tokenizerRevision",
        "encoderPrecision",
    }
    return {key: value for key, value in model.items() if key in allowed}


def summary(name, label):
    result = load(name)
    if result is None:
        return None
    fixtures = result.get("fixtures", [])
    latencies = sorted(fixture["holdReleaseMilliseconds"] for fixture in fixtures)
    longest = max(fixtures, key=lambda fixture: fixture["durationSeconds"]) if fixtures else None
    corpus_wer = result.get("corpusWordErrorRate")
    if corpus_wer is None and fixtures and all(fixture.get("wordErrors") is not None for fixture in fixtures):
        errors = sum(fixture["wordErrors"] for fixture in fixtures)
        reference_words = sum(fixture["referenceWords"] for fixture in fixtures)
        corpus_wer = errors / reference_words
    cancellation = result.get("cancellation")
    public_cancellation = None
    if cancellation:
        public_cancellation = {
            "outcome": cancellation.get("outcome"),
            "responseMilliseconds": cancellation.get("responseMilliseconds"),
        }
    return {
        "label": label,
        "runtime": result.get("runtime", "transcribe.cpp"),
        "runtimeVersion": result.get("runtimeVersion"),
        "runtimeRevision": result.get("runtimeRevision"),
        "backend": result.get("backend") or result.get("wrapper", {}).get("backend"),
        "model": public_model(result.get("model")),
        "longFormConfiguration": result.get("longFormConfiguration"),
        "coldLoadMilliseconds": result.get("coldLoadMilliseconds"),
        "warmMedianMilliseconds": result.get("warmMedianMilliseconds")
        or (statistics.median(latencies) if latencies else None),
        "warmP95Milliseconds": latencies[round(0.95 * (len(latencies) - 1))] if latencies else None,
        "longestFixtureDurationSeconds": longest.get("durationSeconds") if longest else None,
        "longestFixtureMilliseconds": longest.get("holdReleaseMilliseconds") if longest else None,
        "corpusWordErrorRate": corpus_wer,
        "meanFixtureWordErrorRate": result.get("averageWordErrorRate"),
        "peakResidentMiB": result.get("peakResidentBytes", 0) / 1_048_576,
        "failedFixtureCount": sum(1 for fixture in fixtures if fixture.get("error")),
        "cancellation": public_cancellation,
    }


def summaries(specifications):
    return [result for name, label in specifications if (result := summary(name, label)) is not None]


selection = summaries(
    [
        ("selection-parakeet-v2.json", "Parakeet v2 Q5_K_M"),
        ("selection-parakeet-v3.json", "Parakeet v3 Q5_K_M"),
        ("selection-whisper-base-en.json", "Whisper Base.en Q5_K_M"),
        ("selection-whisper-small-en.json", "Whisper Small.en Q5_K_M"),
        ("selection-whisper-medium-en.json", "Whisper Medium.en Q5_K_M"),
        ("selection-whisper-turbo.json", "Whisper large-v3-turbo Q5_K_M"),
        ("selection-whisper-large-v3.json", "Whisper large-v3 Q5_K_M"),
    ]
)

runtime_matrix = summaries(
    [
        ("matrix-transcribe-cpp-parakeet-v3-metal.json", "transcribe.cpp / Parakeet v3 / Metal"),
        ("matrix-transcribe-cpp-parakeet-v3-cpu.json", "transcribe.cpp / Parakeet v3 / CPU"),
        ("matrix-whisper-cpp-parakeet-metal.json", "whisper.cpp / Parakeet v3 / Metal"),
        ("matrix-whisper-cpp-parakeet-cpu.json", "whisper.cpp / Parakeet v3 / CPU"),
        ("matrix-sherpa-onnx-parakeet-cpu.json", "sherpa-onnx / Parakeet v3 / CPU"),
        ("matrix-sherpa-onnx-parakeet-coreml.json", "sherpa-onnx / Parakeet v3 / Core ML"),
        ("matrix-mlx-parakeet.json", "MLX / Parakeet v3"),
        ("matrix-transcribe-cpp-whisper-small-en-metal.json", "transcribe.cpp / Whisper Small.en / Metal"),
        ("matrix-transcribe-cpp-whisper-small-en-cpu.json", "transcribe.cpp / Whisper Small.en / CPU"),
        ("matrix-whisper-cpp-whisper-metal.json", "whisper.cpp / Whisper Small.en / Metal"),
        ("matrix-whisper-cpp-whisper-cpu.json", "whisper.cpp / Whisper Small.en / CPU"),
        ("matrix-sherpa-onnx-whisper-cpu.json", "sherpa-onnx / Whisper Small.en / CPU"),
        ("matrix-sherpa-onnx-whisper-coreml.json", "sherpa-onnx / Whisper Small.en / Core ML"),
        ("matrix-mlx-whisper.json", "MLX / Whisper Small.en"),
        ("matrix-whisperkit-whisper-coreml-pass-2.json", "WhisperKit / Whisper Small.en / Core ML"),
    ]
)

maturity = summaries(
    [
        ("maturity-whisper-medium-en-metal.json", "whisper.cpp / Whisper Medium.en / Metal"),
        ("maturity-whisper-turbo-metal.json", "whisper.cpp / Whisper large-v3-turbo / Metal"),
        ("maturity-whisper-large-v3-metal.json", "whisper.cpp / Whisper large-v3 / Metal"),
    ]
)

fluid_audio = summaries(
    [
        ("fluid-audio-parakeet-v2-default-pass-2.json", "FluidAudio / Parakeet v2 / default"),
        ("fluid-audio-parakeet-v3-default-pass-2.json", "FluidAudio / Parakeet v3 / default"),
        ("fluid-audio-parakeet-v3-no-mel.json", "FluidAudio / Parakeet v3 / no mel context"),
        ("fluid-audio-parakeet-v3-dual.json", "FluidAudio / Parakeet v3 / dual-decode arbitration"),
    ]
)

first_use = []
for names, label in [
    (
        [
            "fluid-audio-parakeet-v2-default-first-specialization.json",
            "fluid-audio-parakeet-v2-default-pass-1.json",
        ],
        "FluidAudio / Parakeet v2",
    ),
    (
        [
            "fluid-audio-parakeet-v3-default-first-specialization.json",
            "fluid-audio-parakeet-v3-default-pass-1.json",
        ],
        "FluidAudio / Parakeet v3",
    ),
    (["matrix-whisperkit-whisper-coreml-first-specialization.json"], "WhisperKit / Whisper Small.en"),
]:
    result = next((loaded for name in names if (loaded := load(name)) is not None), None)
    if result:
        first_use.append(
            {
                "label": label,
                "coldLoadMilliseconds": result["coldLoadMilliseconds"],
                "peakResidentMiB": result["peakResidentBytes"] / 1_048_576,
            }
        )
observations = load("first-use-observations.json")
if observations:
    for label, observation in observations.items():
        first_use.append(
            {
                "label": label,
                "coldLoadMilliseconds": observation.get("coldLoadMilliseconds"),
                "observation": observation.get("observation"),
            }
        )

streaming = load("moonshine-streaming-tiny.json")
streaming_summary = None
if streaming:
    events = streaming["streaming"]["events"]
    first_tentative = next(event for event in events if event["tentative"])
    first_committed = next(event for event in events if event["committed"])
    streaming_summary = {
        "model": public_model(streaming["model"]),
        "coldLoadMilliseconds": streaming["coldLoadMilliseconds"],
        "peakResidentMiB": streaming["peakResidentBytes"] / 1_048_576,
        "firstTentativeInputMilliseconds": first_tentative["inputReceivedMilliseconds"],
        "firstCommittedInputMilliseconds": first_committed["inputReceivedMilliseconds"],
        "eventCount": len(events),
    }

aggregate = {
    "schemaVersion": 1,
    "privacy": {
        "containsIndividualFixtures": False,
        "containsReferenceText": False,
        "containsTranscripts": False,
        "rawResultsLocation": ".artifacts/results/ (gitignored)",
    },
    "corpus": json.loads((root / "fixtures" / "manifest.json").read_text())["corpus"],
    "modelSelection": selection,
    "runtimeMatrix": runtime_matrix,
    "maturityOptions": maturity,
    "fluidAudio": fluid_audio,
    "firstUse": first_use,
    "streamingCapability": streaming_summary,
    "conclusion": {
        "tentativeEngine": "FluidAudio v0.15.5 with Parakeet TDT 0.6B v2",
        "fallback": "whisper.cpp v1.9.1 with Whisper Medium.en Q5_0",
        "stitchingPolicy": "Use FluidAudio AsrManager's existing 15-second overlap merger; do not implement app-level stitching.",
    },
}
output.write_text(json.dumps(aggregate, indent=2, sort_keys=True) + "\n")
print(output)
