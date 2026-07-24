#!/usr/bin/env python3

import json
import re
import resource
import statistics
import sys
import time
from pathlib import Path

import mlx.core as mx

root = Path(__file__).resolve().parent.parent.parent
family, output_path = sys.argv[1:]
hub = root / ".artifacts/huggingface/hub"
configurations = {
    "parakeet": {
        "checkpoint": "nvidia/parakeet-tdt-0.6b-v3",
        "artifact": "mlx-community/parakeet-tdt-0.6b-v3",
        "artifactRevision": "ed2b7e8c15f9aaa0b5772e2efb986255eaef7e15",
        "quantization": "F32 weights; BF16 inference",
        "modelBytes": 2_508_288_736,
        "snapshot": hub
        / "models--mlx-community--parakeet-tdt-0.6b-v3/snapshots/ed2b7e8c15f9aaa0b5772e2efb986255eaef7e15",
    },
    "whisper": {
        "checkpoint": "openai/whisper-small.en",
        "artifact": "mlx-community/whisper-small.en-mlx-4bit",
        "artifactRevision": "78852d6d86b5fd23b5d9315e7fcbadbf844bd85b",
        "quantization": "4-bit",
        "modelBytes": 196_535_960,
        "snapshot": hub
        / "models--mlx-community--whisper-small.en-mlx-4bit/snapshots/78852d6d86b5fd23b5d9315e7fcbadbf844bd85b",
    },
}
configuration = configurations[family]

load_start = time.perf_counter()
if family == "parakeet":
    from mlx_audio.stt.utils import load_audio, load_model

    model = load_model(configuration["snapshot"])

    def transcribe(fixture):
        audio = load_audio(root / "fixtures" / fixture["filename"])
        start = time.perf_counter()
        output = model.generate(audio)
        mx.synchronize()
        return output.text.strip(), (time.perf_counter() - start) * 1_000

else:
    from mlx_whisper.audio import load_audio
    from mlx_whisper.transcribe import ModelHolder, transcribe as whisper_transcribe

    ModelHolder.get_model(str(configuration["snapshot"]), mx.float16)

    def transcribe(fixture):
        audio = load_audio(str(root / "fixtures" / fixture["filename"]))
        start = time.perf_counter()
        output = whisper_transcribe(
            audio,
            path_or_hf_repo=str(configuration["snapshot"]),
            language="en",
            verbose=None,
        )
        mx.synchronize()
        return output["text"].strip(), (time.perf_counter() - start) * 1_000

cold_load_milliseconds = (time.perf_counter() - load_start) * 1_000
fixtures = json.loads((root / "fixtures/local-manifest.json").read_text())["fixtures"]
warmup = min(fixtures, key=lambda fixture: fixture["durationSeconds"])
transcribe(warmup)


def words(text):
    return re.findall(r"[a-z0-9]+", text.lower())


def distance(reference, hypothesis):
    previous = list(range(len(hypothesis) + 1))
    for reference_index, reference_word in enumerate(reference, 1):
        current = [reference_index]
        for hypothesis_index, hypothesis_word in enumerate(hypothesis, 1):
            current.append(
                min(
                    current[-1] + 1,
                    previous[hypothesis_index] + 1,
                    previous[hypothesis_index - 1] + (reference_word != hypothesis_word),
                )
            )
        previous = current
    return previous[-1]


fixture_results = []
total_errors = 0
total_reference_words = 0
for fixture in fixtures:
    error = None
    try:
        transcript, latency_milliseconds = transcribe(fixture)
    except Exception as caught:
        transcript = ""
        latency_milliseconds = 0
        error = str(caught)
    reference_words = words(fixture["reference"])
    errors = distance(reference_words, words(transcript))
    total_errors += errors
    total_reference_words += len(reference_words)
    fixture_results.append(
        {
            "id": fixture["id"],
            "durationSeconds": fixture["durationSeconds"],
            "reference": fixture["reference"],
            "transcript": transcript,
            "error": error,
            "holdReleaseMilliseconds": latency_milliseconds,
            "wordErrors": errors,
            "referenceWords": len(reference_words),
            "wordErrorRate": errors / len(reference_words),
        }
    )

successful_latencies = [
    fixture["holdReleaseMilliseconds"] for fixture in fixture_results if fixture["error"] is None
]
result = {
    "runtime": "MLX",
    "implementation": "mlx-audio" if family == "parakeet" else "mlx-whisper",
    "runtimeVersion": "mlx 0.32.0",
    "implementationVersion": "mlx-audio 0.4.5" if family == "parakeet" else "mlx-whisper 0.4.3",
    "backend": "MLX Metal",
    "model": {key: value for key, value in configuration.items() if key != "snapshot"},
    "coldLoadMilliseconds": cold_load_milliseconds,
    "warmMedianMilliseconds": statistics.median(successful_latencies),
    "peakResidentBytes": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
    "corpusWordErrors": total_errors,
    "corpusReferenceWords": total_reference_words,
    "corpusWordErrorRate": total_errors / total_reference_words,
    "fixtures": fixture_results,
}
output = root / output_path
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
print(
    f"MLX {family}: cold {result['coldLoadMilliseconds']:.0f} ms | "
    f"warm median {result['warmMedianMilliseconds']:.0f} ms | "
    f"WER {result['corpusWordErrorRate'] * 100:.2f}% | "
    f"peak {result['peakResidentBytes'] / 1_048_576:.0f} MiB"
)
