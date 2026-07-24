#!/usr/bin/env python3

import json
import re
import statistics
from pathlib import Path

root = Path(__file__).resolve().parent.parent
results = root / "results"
raw_results = root / ".artifacts" / "results"


def load(name):
    return json.loads((raw_results / name).read_text())


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


def corpus_wer(result):
    if "corpusWordErrorRate" in result:
        return result["corpusWordErrorRate"]
    errors = 0
    reference_words = 0
    for fixture in result["fixtures"]:
        reference = words(fixture["reference"])
        errors += distance(reference, words(fixture.get("transcript") or ""))
        reference_words += len(reference)
    return errors / reference_words


def median(result):
    return result.get("warmMedianMilliseconds") or statistics.median(
        fixture["holdReleaseMilliseconds"] for fixture in result["fixtures"]
    )


def percentile95(result):
    values = sorted(fixture["holdReleaseMilliseconds"] for fixture in result["fixtures"])
    return values[int((len(values) - 1) * 0.95)]


def longest(result):
    return max(result["fixtures"], key=lambda fixture: fixture["durationSeconds"])


selection_files = [
    ("Parakeet v2 Q5", "selection-parakeet-v2.json"),
    ("Parakeet v3 Q5", "selection-parakeet-v3.json"),
    ("Whisper base.en Q5", "selection-whisper-base-en.json"),
    ("Whisper small.en Q5", "selection-whisper-small-en.json"),
    ("Whisper medium.en Q5", "selection-whisper-medium-en.json"),
    ("Whisper Turbo Q5", "selection-whisper-turbo.json"),
    ("Whisper large-v3 Q5", "selection-whisper-large-v3.json"),
]
selection = [(name, load(filename)) for name, filename in selection_files]

matrix_rows = [
    ("Parakeet v3", "transcribe.cpp", "Metal", "Q5_K_M", "matrix-transcribe-cpp-parakeet-v3-metal.json", "precedent"),
    ("Parakeet v3", "transcribe.cpp", "CPU", "Q5_K_M", "matrix-transcribe-cpp-parakeet-v3-cpu.json", "precedent"),
    ("Parakeet v3", "whisper.cpp", "Metal", "Q4_K", "matrix-whisper-cpp-parakeet-metal.json", "allowed"),
    ("Parakeet v3", "whisper.cpp", "CPU", "Q4_K", "matrix-whisper-cpp-parakeet-cpu.json", "allowed"),
    ("Parakeet v3", "sherpa-onnx", "ONNX CPU", "INT8", "matrix-sherpa-onnx-parakeet-cpu.json", "not allowed"),
    ("Parakeet v3", "sherpa-onnx", "ONNX Core ML EP", "INT8", "matrix-sherpa-onnx-parakeet-coreml.json", "not allowed"),
    ("Parakeet v3", "mlx-audio", "MLX Metal", "F32/BF16", "matrix-mlx-parakeet.json", "not allowed"),
    ("Whisper small.en", "transcribe.cpp", "Metal", "Q5_K_M", "matrix-transcribe-cpp-whisper-small-en-metal.json", "precedent"),
    ("Whisper small.en", "transcribe.cpp", "CPU", "Q5_K_M", "matrix-transcribe-cpp-whisper-small-en-cpu.json", "precedent"),
    ("Whisper small.en", "whisper.cpp", "Metal", "Q5_1", "matrix-whisper-cpp-whisper-metal.json", "allowed"),
    ("Whisper small.en", "whisper.cpp", "CPU", "Q5_1", "matrix-whisper-cpp-whisper-cpu.json", "allowed"),
    ("Whisper small.en", "sherpa-onnx", "ONNX CPU", "INT8", "matrix-sherpa-onnx-whisper-cpu.json", "not allowed"),
    ("Whisper small.en", "sherpa-onnx", "ONNX Core ML EP", "INT8", "matrix-sherpa-onnx-whisper-coreml.json", "not allowed"),
    ("Whisper small.en", "mlx-whisper", "MLX Metal", "4-bit", "matrix-mlx-whisper.json", "not allowed"),
    ("Whisper small.en", "WhisperKit", "Core ML/ANE preferred", "217 MB compressed", "matrix-whisperkit-whisper-coreml-pass-2.json", "not allowed"),
]
matrix = [(model, runtime, backend, quant, load(filename), allowlist) for model, runtime, backend, quant, filename, allowlist in matrix_rows]

lines = [
    "# Expanded engine runtime matrix",
    "",
    "Measured on the target M4 Pro against 24 retained personal dictation fixtures totaling 11.7 minutes and 1,214 Aqua-reference words. Aqua's raw transcript is an independent baseline, not hand-corrected truth.",
    "",
    "## Model selection through transcribe.cpp/Metal",
    "",
    "| Candidate | Corpus WER | Warm median | Warm p95 | 93.5 s fixture | Peak RSS |",
    "| --- | ---: | ---: | ---: | ---: | ---: |",
]
for name, result in selection:
    longest_fixture = longest(result)
    lines.append(
        f"| {name} | {corpus_wer(result) * 100:.2f}% | {median(result):.0f} ms | "
        f"{percentile95(result):.0f} ms | {longest_fixture['holdReleaseMilliseconds']:.0f} ms | "
        f"{result['peakResidentBytes'] / 1_048_576:.0f} MiB |"
    )
lines += [
    "",
    "**Selected checkpoints:** Parakeet TDT 0.6B v3 and Whisper small.en. V3 beat English-only Parakeet v2 by 17 word errors at effectively the same latency. Whisper small.en missed one more reference word than Turbo (40 vs. 39) while using about half the memory and 38% of Turbo's median latency. Full large-v3 recovered six words relative to small.en but cost 4.8× the median latency and 3.9× the memory. Medium.en suffered a severe repeated/truncated decode on one fixture.",
    "",
    "## Runtime and backend matrix",
    "",
    "The checkpoint is held constant, but each runtime requires its own available model conversion and quantization. This is a practical artifact comparison, not a bit-identical kernel benchmark.",
    "",
    "| Model | Runtime | Backend | Artifact | Cold load | Warm median | Warm p95 | 93.5 s fixture | Corpus WER | Peak RSS | Work status |",
    "| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
]
for model, runtime, backend, quant, result, allowlist in matrix:
    longest_fixture = longest(result)
    long_latency = f"{longest_fixture['holdReleaseMilliseconds']:.0f} ms"
    wer = f"{corpus_wer(result) * 100:.2f}%"
    if runtime == "sherpa-onnx" and model == "Whisper small.en":
        long_latency += " (first 30 s only)"
        wer += "†"
    lines.append(
        f"| {model} | {runtime} | {backend} | {quant} | {result['coldLoadMilliseconds']:.0f} ms | "
        f"{median(result):.0f} ms | {percentile95(result):.0f} ms | {long_latency} | {wer} | "
        f"{result['peakResidentBytes'] / 1_048_576:.0f} MiB | {allowlist} |"
    )
lines += [
    "",
    "WhisperKit has no Parakeet implementation. Its first uncached Core ML specialization took 15,112 ms; the immediately repeated process loaded in 503 ms. whisper.cpp's first Metal use took 7,359 ms, including 7,247 ms loading/specializing its embedded Metal library. MLX Parakeet's first process loaded in 9,579 ms and a later process in 3,034 ms. Later-process measurements are shown above; aggregate first-use observations are in [`aggregate.json`](aggregate.json).",
    "",
    "† sherpa-onnx's Whisper implementation explicitly discards audio after 30 seconds. Eight fixtures exceeded that limit, so its full-corpus WER is not comparable.",
    "",
    "## What the matrix says",
    "",
    "- `transcribe.cpp`/Metal was the strongest allowed-precedent Parakeet lane: 172 ms median, 2.55% corpus WER, and a roughly 120 ms resident load. MLX was marginally faster and one word better, but its first process loaded in 9.6 seconds (3.0 seconds after caching), used 2.8 GiB RSS, and brings a large unapproved dependency graph.",
    "- For Whisper small.en, `transcribe.cpp` and `whisper.cpp`/Metal were effectively tied: 267 vs. 272 ms median and 3.29% vs. 3.38% WER. `transcribe.cpp` keeps the cross-family seam; `whisper.cpp` remains the more mature, explicitly allowed runtime.",
    "- CPU was consistently slower. It changed a few hypotheses because floating-point reductions differ, but offered no responsiveness win on the target M4 Pro.",
    "- WhisperKit's compressed small.en artifact was slower here (roughly 800 ms median) than the GGUF/GGML and MLX lanes. Its low process RSS does not include Core ML/ANE device accounting in a form comparable to the native runtimes.",
    "- sherpa-onnx/CPU used more memory and produced worse Parakeet text. Its Core ML execution provider was slower, reached a 29 GiB process high-water mark for Parakeet, and repeatedly logged `Context leak detected`. The Whisper path's 30-second hard limit disqualifies it for unconstrained hold dictation without an additional chunk/stitch layer.",
    "- MLX requires two separate Python libraries in the working prototype: `mlx-audio` for Parakeet and `mlx-whisper` for Whisper. The supposedly unified `mlx-audio` Whisper path produced corrupt repeated output on the tested quantized small.en artifacts, so it was not substituted into the working cell.",
    "- Released `transcribe.cpp` v0.1.3 Parakeet polls cancellation only before inference. A disposable native patch wired its existing GGML Metal/CPU abort mechanism into the encoder and polled the host decoder; active requests then aborted within 74.9 ms without changing corpus WER or median latency. The fix can be upstreamed or carried with the pinned XCFramework build.",
    "",
    "## Support and integration shape",
    "",
    "| Runtime | Parakeet v3 | Whisper small.en | Production shape |",
    "| --- | --- | --- | --- |",
    "| transcribe.cpp | Yes | Yes | One Swift XCFramework and one wrapper; direct Whispering allowlist precedent |",
    "| whisper.cpp | Yes, newer API/artifact | Yes | Mature C/C++ runtime; explicit allowlist entry; family-specific native APIs |",
    "| WhisperKit | No | Yes | Swift/Core ML/ANE; separate unapproved dependency and model bundle |",
    "| sherpa-onnx | Yes | Yes, but 30 s limit | C/C++ plus ONNX Runtime; unapproved dependency |",
    "| MLX | Yes via mlx-audio | Yes via mlx-whisper | Two Python implementations and broad dependency graphs; unsuitable as-is for the signed app |",
    "",
    "## Measurement cautions",
    "",
    "- Peak RSS is each process's macOS high-water mark. GPU, ANE, and Core ML allocations are not accounted identically, so compare it as integration evidence rather than a universal device-memory measure.",
    "- Warm latency starts after the 16 kHz PCM fixture is available and ends at final text, matching simulated hold-release. Models remain resident within each process.",
    "- Cold load excludes download and measures runtime/model initialization. Core ML and Metal may create persistent OS caches, so first-ever and later-process measurements are recorded separately where observed.",
    "- Available runtime conversions differ in quantization: transcribe.cpp Q5_K_M, whisper.cpp Q4_K/Q5_1, sherpa INT8, MLX F32/BF16 or 4-bit, and WhisperKit's 217 MB Core ML compression.",
    "",
    "Raw fixture outputs are intentionally retained only under the gitignored `.artifacts/results/` directory.",
]
(results / "runtime-matrix.md").write_text("\n".join(lines) + "\n")

print(results / "runtime-matrix.md")
