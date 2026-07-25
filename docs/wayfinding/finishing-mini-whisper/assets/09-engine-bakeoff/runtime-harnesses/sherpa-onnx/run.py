#!/usr/bin/env python3

import json
from pathlib import Path
import re
import resource
import statistics
import sys
import time
import wave

import numpy as np
import sherpa_onnx

root = Path(__file__).resolve().parent.parent.parent
family, provider, output_path = sys.argv[1:]
models_root = root / ".artifacts/onnx-models"
configurations = {
    "parakeet": {
        "checkpoint": "nvidia/parakeet-tdt-0.6b-v3",
        "artifact": "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8",
        "quantization": "INT8",
        "archiveSHA256": "5793d0fd397c5778d2cf2126994d58e9d56b1be7c04d13c7a15bb1b4eafb16bf",
    },
    "whisper": {
        "checkpoint": "openai/whisper-small.en",
        "artifact": "sherpa-onnx-whisper-small.en",
        "quantization": "INT8",
        "archiveSHA256": "0cdba2b8aaab69e04847f3427cc9709574112e67913a1a84b7fec3a8729faa9a",
    },
}
configuration = configurations[family]
model_root = models_root / configuration["artifact"]

load_start = time.perf_counter()
if family == "parakeet":
    recognizer = sherpa_onnx.OfflineRecognizer.from_transducer(
        encoder=str(model_root / "encoder.int8.onnx"),
        decoder=str(model_root / "decoder.int8.onnx"),
        joiner=str(model_root / "joiner.int8.onnx"),
        tokens=str(model_root / "tokens.txt"),
        num_threads=4,
        provider=provider,
        model_type="nemo_transducer",
    )
else:
    recognizer = sherpa_onnx.OfflineRecognizer.from_whisper(
        encoder=str(model_root / "small.en-encoder.int8.onnx"),
        decoder=str(model_root / "small.en-decoder.int8.onnx"),
        tokens=str(model_root / "small.en-tokens.txt"),
        language="en",
        task="transcribe",
        num_threads=4,
        provider=provider,
    )
cold_load_milliseconds = (time.perf_counter() - load_start) * 1_000

fixtures = json.loads((root / "fixtures/local-manifest.json").read_text())["fixtures"]


def load_audio(path):
    with wave.open(str(path), "rb") as audio:
        if (
            audio.getnchannels() != 1
            or audio.getsampwidth() != 2
            or audio.getframerate() != 16_000
        ):
            raise RuntimeError(f"unsupported WAV format: {path}")
        samples = np.frombuffer(audio.readframes(audio.getnframes()), dtype="<i2")
    return samples.astype(np.float32) / 32_768


def transcribe(fixture):
    stream = recognizer.create_stream()
    stream.accept_waveform(16_000, load_audio(root / "fixtures" / fixture["filename"]))
    start = time.perf_counter()
    recognizer.decode_stream(stream)
    latency_milliseconds = (time.perf_counter() - start) * 1_000
    return stream.result.text.strip(), latency_milliseconds


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
                    previous[hypothesis_index - 1]
                    + (reference_word != hypothesis_word),
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
            "truncatedByRuntime": family == "whisper"
            and fixture["durationSeconds"] >= 30,
        }
    )

successful_latencies = [
    fixture["holdReleaseMilliseconds"]
    for fixture in fixture_results
    if fixture["error"] is None
]
result = {
    "runtime": "sherpa-onnx",
    "runtimeRevision": "142807252687d81b40d6315f23470a1512a00de3",
    "runtimeVersion": sherpa_onnx.__version__,
    "onnxRuntimeVersion": "bundled by sherpa-onnx-core 1.13.4",
    "backend": provider,
    "model": configuration,
    "longFormLimitSeconds": 30 if family == "whisper" else None,
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
    f"sherpa-onnx {family}/{provider}: cold {result['coldLoadMilliseconds']:.0f} ms | "
    f"warm median {result['warmMedianMilliseconds']:.0f} ms | "
    f"WER {result['corpusWordErrorRate'] * 100:.2f}% | "
    f"peak {result['peakResidentBytes'] / 1_048_576:.0f} MiB"
)
