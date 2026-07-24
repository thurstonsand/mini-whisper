# MiniWhisper engine bakeoff

Disposable arm64 prototypes for choosing a local English dictation engine before production integration. Everything remains under documentation; no MiniWhisper target or production package imports these harnesses.

## Result set

The expanded bakeoff uses 24 private local dictation recordings totaling 11.7 minutes, with individual utterances from 3.5 to 93.5 seconds. Audio, fixture metadata, reference text, and raw engine output remain gitignored. [`fixtures/manifest.json`](fixtures/manifest.json) contains only anonymous corpus-level dimensions.

Two checkpoint candidates survived the first pass:

- **Parakeet TDT 0.6B v3**: 2.55% corpus WER through `transcribe.cpp`/Metal, versus v2's 3.95%, at effectively the same latency.
- **Whisper small.en**: the practical English-only tradeoff. It missed one more reference word than large-v3-turbo while using about half the memory and 38% of Turbo's median latency.

Whisper's named sizes are Tiny (39M parameters), Base (74M), Small (244M), Medium (769M), and Large (1.55B). `.en` English-only checkpoints exist through Medium. Large-v3-turbo is a separate 809M multilingual derivative with a pruned decoder; it is not a size between Medium and Large. This prototype measured Base.en, Small.en, Medium.en, large-v3-turbo, and full large-v3 before selecting Small.en.

The selected checkpoints were then tested across:

- `transcribe.cpp` v0.1.3: Metal and CPU
- `whisper.cpp` v1.9.1: Metal and CPU
- WhisperKit v1.0.0: Core ML defaults, Whisper only
- sherpa-onnx v1.13.4: ONNX CPU and Core ML execution provider
- MLX: `mlx-audio` for Parakeet and `mlx-whisper` for Whisper
- FluidAudio v0.15.5: Core ML/ANE, Parakeet v2 and v3

WhisperKit has no Parakeet implementation. That cell is unsupported rather than silently replaced. The ONNX, MLX, and WhisperKit lanes are comparison prototypes outside the current allowlist; their presence is evidence, not approval.

Read the [runtime matrix and findings](results/runtime-matrix.md) and the machine-readable [`results/aggregate.json`](results/aggregate.json). They retain aggregate timings, quality scores, artifact identities, and conclusions without individual fixture data. Raw runs exist only under gitignored `.artifacts/results/` when generated locally.

A subsequent stability review rejected transcribe.cpp's young dependency posture and established **Whisper Medium.en Q5_0 through whisper.cpp/Metal** as the conservative fallback: 605 ms warm median, 3.13% corpus WER, and 901 MiB peak RSS.

Relaxing the dependency screen then produced a stronger Swift/Parakeet option. [FluidAudio v0.15.5 with Parakeet v2](results/fluid-audio.md) measured 98 ms warm median, 3.21% raw-reference WER, 170 MiB later-process RSS, and working cancellation. Its first Core ML specialization took 213 seconds, so model installation must include explicit onboarding/prewarm.

## Measurement contract

Every batch harness loads its model once and keeps it resident while processing the corpus. Each fixture is already-decoded 16 kHz mono PCM before the simulated hold-release timer begins; warm latency ends when final text is available. Cold load measures runtime/model initialization after artifacts have been downloaded. Peak RSS is the process high-water mark from macOS `getrusage`; GPU, ANE, and Core ML allocations are not necessarily reflected equivalently.

Runtime-specific artifacts use the closest pinned conversion available for the same upstream checkpoint. Quantization therefore differs: transcribe.cpp Q5_K_M, whisper.cpp Q4_K/Q5_1, sherpa INT8, MLX F32/BF16 or 4-bit, and WhisperKit's 217 MB Core ML compression. This is a practical shippable-artifact comparison, not a bit-identical kernel benchmark.

## Reproduce

To reproduce only the selected FluidAudio comparison:

```sh
./scripts/setup-fluid-audio.sh
./scripts/run-fluid-audio.sh
```

This downloads the two pinned Core ML Parakeet artifacts rather than the entire runtime matrix. The first load can spend roughly three and a half minutes specializing each model; later runs are fast.

The original transcribe.cpp prototype and complete research matrix remain reproducible when needed:

```sh
./scripts/setup.sh
./scripts/run.sh

./scripts/setup-matrix.sh
./scripts/run-matrix.sh
./scripts/run-maturity-options.sh
```

Setup checks out immutable runtime revisions, installs the committed Python dependency locks, downloads models from immutable revisions, checks direct-download byte counts and SHA-256 digests, creates a private local fixture manifest, and builds release harnesses. It needs retained Aqua Voice history under `~/Library/Application Support/Aqua Voice`. The exact historical selection remains in gitignored `.artifacts/fixture-selection.json` on the benchmark machine; on a fresh clone the importer deterministically selects 24 retained entries across the available duration range. Equivalent 16 kHz mono signed 16-bit PCM fixtures can also be described manually in gitignored `fixtures/local-manifest.json`.

To feel the selected resident-model release paths directly:

```sh
.build/release/EngineBakeoff feel parakeet-v3
.build/release/EngineBakeoff feel whisper-small-en
```

The genuine Moonshine streaming capability probe runs as part of `scripts/run.sh`. Its raw committed/tentative text stays under `.artifacts/results/`; only timing and capability aggregates are retained.

## Pinned environment

- MacBook Pro `Mac16,8`, Apple M4 Pro, 14 CPU cores, 48 GB RAM, arm64
- macOS 26.5.2 (`25F84`), Xcode 26.6 (`17F113`), Swift 6.3.3
- `transcribe.cpp` v0.1.3 at `a94e021ef658dc7c788837341a13f6acea3baf3c`
- `whisper.cpp` v1.9.1 at `f049fff95a089aa9969deb009cdd4892b3e74916`
- WhisperKit/argmax-oss-swift v1.0.0 at `25c62997041c134b03ca82731ce2f6fd2cae1eb9`
- FluidAudio v0.15.5 at `19600a485baa4998812e4654b70d2bab8f2c9949`
- sherpa-onnx 1.13.4
- mlx-audio 0.4.5, mlx-whisper 0.4.3, MLX 0.32.0
- Exact transcribe.cpp model repositories, revisions, sizes, and hashes: [`models.tsv`](models.tsv)
- Other runtime revisions, model revisions, sizes, and hashes: [`scripts/setup-matrix.sh`](scripts/setup-matrix.sh) and the model objects in [`results/aggregate.json`](results/aggregate.json)
- Captured machine environment and transcribe.cpp hashes: [`results/environment.txt`](results/environment.txt)

## Integration findings

`ResidentTranscriber` proves one app-level Swift seam can load every compatible transcribe.cpp GGUF without model-family branching. That runtime produced the strongest allowed-precedent Parakeet result: 172 ms warm median and 2.55% corpus WER on Metal. For Whisper small.en, transcribe.cpp and whisper.cpp/Metal were effectively tied at 267–272 ms and 3.29–3.38% WER.

The first broader lanes did not reveal a hidden winner. MLX Parakeet was fast but heavy and unsuitable as an app dependency; WhisperKit Small.en was slower; sherpa-onnx was weaker and hard-truncated Whisper at 30 seconds.

FluidAudio did change the result. Its v2 Core ML conversion was faster than every other lane, qualitatively competitive with the best transcripts, and integrated through a considerably broader Swift project than transcribe.cpp. It remains pre-1.0 and uses 15-second overlap stitching, so exact pinning and the long-fixture regression corpus are part of the dependency contract.

### Cancellation defect and patch proof

Pinned transcribe.cpp Whisper aborts in flight. Its released Parakeet one-shot path checks the token only before inference, so a later cancellation request returns only after the complete transcript.

The native machinery needed to fix this already exists in GGML. The disposable [`parakeet-cancellation.patch`](runtime-harnesses/transcribe-cpp/parakeet-cancellation.patch) wires the Metal/CPU backend abort callback into Parakeet's encoder and polls its host TDT decoder. On the 93.5-second fixture, cancellation requests throughout inference returned in at most 74.9 ms. A complete corpus rerun retained 2.55% WER and a 171 ms median. See the [patch probe](results/parakeet-cancellation-fix.md).

This can be submitted upstream or carried against MiniWhisper's pinned XCFramework build. The remaining issue is dependency maintenance, not technical feasibility.

## Genuine streaming result

Moonshine Streaming Tiny Q8 loaded through the same transcribe.cpp XCFramework and reported genuine streaming support. Its encoder consumed 100 ms frames while retaining state rather than repeatedly decoding a whole window. Tentative text began after 0.5 seconds of received audio and committed text after 1.7 seconds. Raw event text is intentionally excluded from the repository; numeric evidence remains in [`results/aggregate.json`](results/aggregate.json).

One v0.1.3 edge remains: after finalize, authoritative `full` included the final phrase while the last committed/tentative snapshot omitted it. A streaming UI must therefore use authoritative `full` for final text until that contract is fixed upstream.

Thurston tentatively selected FluidAudio with Parakeet v2. The MVP specification still has to accept the dependency and installed-artifact compliance posture; whisper.cpp Medium.en remains the fallback.
