#!/usr/bin/env python3

import json
import statistics
from pathlib import Path

root = Path(__file__).resolve().parent.parent
results = root / "results"
raw_results = root / ".artifacts" / "results"


def load(name, required=True):
    path = raw_results / name
    if not path.exists() and not required:
        return None
    return json.loads(path.read_text())


def p95(result):
    values = sorted(fixture["holdReleaseMilliseconds"] for fixture in result["fixtures"])
    return values[round(0.95 * (len(values) - 1))]


def longest(result):
    return max(result["fixtures"], key=lambda fixture: fixture["durationSeconds"])


v2 = load("fluid-audio-parakeet-v2-default-pass-2.json")
v3 = load("fluid-audio-parakeet-v3-default-pass-2.json")
v2_first = load("fluid-audio-parakeet-v2-default-first-specialization.json", required=False) or load(
    "fluid-audio-parakeet-v2-default-pass-1.json"
)
v3_first = load("fluid-audio-parakeet-v3-default-first-specialization.json", required=False) or load(
    "fluid-audio-parakeet-v3-default-pass-1.json"
)
v3_no_mel = load("fluid-audio-parakeet-v3-no-mel.json")
v3_dual = load("fluid-audio-parakeet-v3-dual.json")
transcribe_v3 = load("matrix-transcribe-cpp-parakeet-v3-metal.json", required=False)
whisper_medium = load("maturity-whisper-medium-en-metal.json", required=False)

rows = [
    ("FluidAudio", "Parakeet v2", "Default 15 s overlap", v2),
    ("FluidAudio", "Parakeet v3", "Default 15 s overlap", v3),
    ("FluidAudio", "Parakeet v3", "No mel context", v3_no_mel),
    ("FluidAudio", "Parakeet v3", "Dual-decode arbitration", v3_dual),
]
if transcribe_v3:
    rows.append(("transcribe.cpp", "Parakeet v3", "One-shot Metal", transcribe_v3))
if whisper_medium:
    rows.append(("whisper.cpp", "Whisper Medium.en", "One-shot Metal", whisper_medium))

lines = [
    "# FluidAudio Parakeet bakeoff",
    "",
    "FluidAudio v0.15.5 was built as an isolated Swift package and tested against the same 24 personal fixtures (11.7 minutes, 1,214 Aqua-reference words). The Core ML model bundles were loaded from immutable Hugging Face revisions rather than FluidAudio's moving default branch.",
    "",
    "## Results",
    "",
    "| Runtime | Model | Long-form path | Cached load | Warm median | Warm p95 | 93.5 s fixture | Corpus WER | Peak RSS | Cancel response |",
    "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
]
for runtime, model, mode, result in rows:
    cancellation = result.get("cancellation")
    cancel = (
        f"{cancellation['responseMilliseconds']:.0f} ms"
        if cancellation and cancellation.get("responseMilliseconds") is not None
        else "not measured"
    )
    lines.append(
        f"| {runtime} | {model} | {mode} | {result['coldLoadMilliseconds']:.0f} ms | "
        f"{result.get('warmMedianMilliseconds', statistics.median(f['holdReleaseMilliseconds'] for f in result['fixtures'])):.0f} ms | "
        f"{p95(result):.0f} ms | {longest(result)['holdReleaseMilliseconds']:.0f} ms | "
        f"{result['corpusWordErrorRate'] * 100:.2f}% | {result['peakResidentBytes'] / 1_048_576:.0f} MiB | {cancel} |"
    )
lines += [
    "",
    "The FluidAudio RSS values are later-process high-water marks. Core ML and ANE allocations are not directly comparable with native Metal process accounting.",
    "",
    "## First-use behavior",
    "",
    f"The supplied `.mlmodelc` bundles still required one-time Core ML specialization on this Mac. Parakeet v2's first load took **{v2_first['coldLoadMilliseconds'] / 1_000:.1f} seconds** and v3's took **{v3_first['coldLoadMilliseconds'] / 1_000:.1f} seconds**. Later processes loaded in {min(v2['coldLoadMilliseconds'], v3['coldLoadMilliseconds']):.0f}–{max(v2['coldLoadMilliseconds'], v3['coldLoadMilliseconds']):.0f} ms. This must happen during model installation/onboarding, never on the first dictation.",
    "",
    f"The first-use process reached about 560 MiB RSS for either model. Later-process RSS was {v2['peakResidentBytes'] / 1_048_576:.0f} MiB for v2 and {v3['peakResidentBytes'] / 1_048_576:.0f} MiB for v3, but that does not include every Core ML/ANE allocation in a comparable way.",
    "",
    "## Quality observations",
    "",
    "- **Parakeet v2 was the strongest FluidAudio lane.** It had one fewer private-reference word error than v3, no obvious dropped clause or repetition loop, and the lowest latency. Several scored errors were punctuation, casing, or word-boundary formatting rather than recognition.",
    "- v3's default path duplicated short words around long-form seams. The failures were small, but they are the exact stitching class FluidAudio's long-transcription documentation warns about.",
    "- Disabling mel context made v3 worse on this English corpus (3.87% WER). Dual-decode arbitration produced the same transcript while doubling median latency, so neither alternate is justified here.",
]
if whisper_medium:
    lines.append(
        f"- FluidAudio v2 was about 6× faster than whisper.cpp Medium.en at the median and completed the 93.5-second fixture in {longest(v2)['holdReleaseMilliseconds']:.0f} ms because four 15-second windows run concurrently. Its raw Aqua-reference WER was effectively tied with Medium.en (3.21% vs. 3.13%)."
    )
if transcribe_v3:
    lines.append(
        "- transcribe.cpp v3 remained closest to Aqua (2.55%), but FluidAudio's v2 transcript is qualitatively competitive and avoids the young native runtime."
    )
lines += [
    "",
    "## Cancellation",
    "",
    f"A Swift task was cancelled about 10 ms into the 93.5-second fixture. FluidAudio v2 returned `CancellationError` {v2['cancellation']['responseMilliseconds']:.0f} ms later; v3 returned it {v3['cancellation']['responseMilliseconds']:.0f} ms later. No dependency patch was required.",
    "",
    "## Integration and maintenance",
    "",
    "- The tested v0.15.5 tag is source-only SwiftPM: no external package dependency or binary target. It compiles local `FastClusterWrapper` and `MachTaskSelfWrapper` C/C++ targets alongside the monolithic `FluidAudio` library.",
    "- Current FluidAudio `main` has already added a mandatory `NemoTextProcessing.xcframework`. That rapid dependency change is evidence for pinning the exact qualified tag rather than following a broad version range.",
    "- Production should follow [Hex's pinned FluidAudio Parakeet client](https://github.com/kitlangton/Hex/blob/ca9642799024/Hex/Clients/ParakeetClient.swift): actor-owned loaded models, explicit cache validation, a fresh decoder state per file, and FluidAudio's complete-file transcription API. MiniWhisper must not replace FluidAudio's chunker or merger.",
    "- The package is not modular: importing Parakeet compiles the repository's TTS, diarization, and other ASR implementations too. Dead stripping limits the shipped binary, but build surface and compiler warnings remain broader than MiniWhisper needs.",
    "- v0.15.5 repeatedly logged `E5RT ... zero shape error` while loading v2 on macOS 26.5.2, then recovered and produced deterministic output. It did not affect results, but should be tracked before declaring the integration quiet.",
    "- Ordinary TDT v2/v3 remains stateless 15-second chunking plus overlap merge, not genuine cache-aware streaming. That is acceptable for hold-release dictation; FluidAudio's separate Parakeet EOU model is the genuine streaming family.",
    "",
    "## Artifact pins",
    "",
    "- FluidAudio v0.15.5: `19600a485baa4998812e4654b70d2bab8f2c9949`",
    "- Parakeet v2 Core ML: `FluidInference/parakeet-tdt-0.6b-v2-coreml@ee09c569f73759e6d44c9bd16766f477b2b36d39`, 444 MiB required files",
    "- Parakeet v3 Core ML: `FluidInference/parakeet-tdt-0.6b-v3-coreml@aed02740059203c4a87495924f685de3722ae9ce`, 474 MiB required files",
    "- Per-file SHA-256 values: [`fluid-audio-model-hashes.txt`](fluid-audio-model-hashes.txt)",
    "",
    "## Prototype verdict",
    "",
    "**FluidAudio v0.15.5 + Parakeet TDT 0.6B v2 is viable for MiniWhisper.** It provides the preferred model family through a substantially more established Swift dictation ecosystem, with excellent release latency, working cancellation, low observed process RSS, and competitive personal-corpus quality.",
    "",
    "The costs are a three-and-a-half-minute first specialization, 15-second stitching complexity, a broad monolithic package, pre-1.0 update discipline, and one noisy Core ML diagnostic. Thurston tentatively selected this direction while retaining whisper.cpp Medium.en as fallback.",
    "",
    "Raw fixture outputs are intentionally retained only under the gitignored `.artifacts/results/` directory.",
]
(results / "fluid-audio.md").write_text("\n".join(lines) + "\n")

print(results / "fluid-audio.md")
