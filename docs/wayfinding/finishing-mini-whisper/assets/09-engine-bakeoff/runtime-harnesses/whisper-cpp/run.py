#!/usr/bin/env python3

import json
import re
import resource
import statistics
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent.parent
family, backend, output_path = sys.argv[1:]
configurations = {
    "parakeet": {
        "checkpoint": "nvidia/parakeet-tdt-0.6b-v3",
        "artifact": "whispercpp-parakeet-v3-q4_k.bin",
        "quantization": "Q4_K",
        "sha256": "8b205b8b39c6535e153de6fb11c51db46125d45c4f16ba496fe41a0fe71b885e",
    },
    "whisper": {
        "checkpoint": "openai/whisper-small.en",
        "artifact": "whispercpp-small.en-q5_1.bin",
        "quantization": "Q5_1",
        "sha256": "bfdff4894dcb76bbf647d56263ea2a96645423f1669176f4844a1bf8e478ad30",
    },
    "whisper-medium-en": {
        "checkpoint": "openai/whisper-medium.en",
        "artifact": "whispercpp-medium.en-q5_0.bin",
        "quantization": "Q5_0",
        "sha256": "76733e26ad8fe1c7a5bf7531a9d41917b2adc0f20f2e4f5531688a8c6cd88eb0",
    },
    "whisper-turbo": {
        "checkpoint": "openai/whisper-large-v3-turbo",
        "artifact": "whispercpp-large-v3-turbo-q5_0.bin",
        "quantization": "Q5_0",
        "sha256": "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
    },
    "whisper-large-v3": {
        "checkpoint": "openai/whisper-large-v3",
        "artifact": "whispercpp-large-v3-q5_0.bin",
        "quantization": "Q5_0",
        "sha256": "d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1",
    },
}
configuration = configurations[family]
fixtures = json.loads((root / "fixtures/local-manifest.json").read_text())["fixtures"]
fixture_by_name = {fixture["filename"]: fixture for fixture in fixtures}
warmup = min(fixtures, key=lambda fixture: fixture["durationSeconds"])
command = [
    str(root / ".artifacts/whisper-cpp-harness"),
    "parakeet" if family == "parakeet" else "whisper",
    backend,
    str(root / ".artifacts/runtime-models" / configuration["artifact"]),
    str(root / "fixtures" / warmup["filename"]),
    *[str(root / "fixtures" / fixture["filename"]) for fixture in fixtures],
]
completed = subprocess.run(command, check=True, capture_output=True, text=True)
peak_resident_bytes = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
records = [json.loads(line) for line in completed.stdout.splitlines() if line.startswith("{")]
meta = next(record for record in records if record["type"] == "meta")


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
for record in records:
    if record["type"] != "result":
        continue
    fixture = fixture_by_name[Path(record["path"]).name]
    reference_words = words(fixture["reference"])
    errors = distance(reference_words, words(record["transcript"]))
    total_errors += errors
    total_reference_words += len(reference_words)
    fixture_results.append(
        {
            "id": fixture["id"],
            "durationSeconds": fixture["durationSeconds"],
            "reference": fixture["reference"],
            "transcript": record["transcript"].strip(),
            "holdReleaseMilliseconds": record["latencyMilliseconds"],
            "wordErrors": errors,
            "referenceWords": len(reference_words),
            "wordErrorRate": errors / len(reference_words),
        }
    )

result = {
    "runtime": "whisper.cpp",
    "runtimeRevision": "f049fff95a089aa9969deb009cdd4892b3e74916",
    "runtimeVersion": "v1.9.1",
    "backend": backend,
    "model": configuration,
    "coldLoadMilliseconds": meta["coldLoadMilliseconds"],
    "warmMedianMilliseconds": statistics.median(
        fixture["holdReleaseMilliseconds"] for fixture in fixture_results
    ),
    "peakResidentBytes": peak_resident_bytes,
    "corpusWordErrors": total_errors,
    "corpusReferenceWords": total_reference_words,
    "corpusWordErrorRate": total_errors / total_reference_words,
    "fixtures": fixture_results,
}
output = root / output_path
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
print(
    f"whisper.cpp {family}/{backend}: cold {result['coldLoadMilliseconds']:.0f} ms | "
    f"warm median {result['warmMedianMilliseconds']:.0f} ms | "
    f"WER {result['corpusWordErrorRate'] * 100:.2f}% | "
    f"peak {result['peakResidentBytes'] / 1_048_576:.0f} MiB"
)
