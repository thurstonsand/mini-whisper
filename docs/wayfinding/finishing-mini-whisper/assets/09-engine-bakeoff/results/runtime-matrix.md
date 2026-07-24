# Expanded engine runtime matrix

Measured on the target M4 Pro against 24 retained personal dictation fixtures totaling 11.7 minutes and 1,214 Aqua-reference words. Aqua's raw transcript is an independent baseline, not hand-corrected truth.

## Model selection through transcribe.cpp/Metal

| Candidate            | Corpus WER | Warm median | Warm p95 | 93.5 s fixture | Peak RSS |
| -------------------- | ---------: | ----------: | -------: | -------------: | -------: |
| Parakeet v2 Q5       |      3.95% |      168 ms |   816 ms |        1088 ms | 1590 MiB |
| Parakeet v3 Q5       |      2.55% |      173 ms |   876 ms |        1108 ms | 1653 MiB |
| Whisper base.en Q5   |      4.28% |      118 ms |   345 ms |         396 ms |  241 MiB |
| Whisper small.en Q5  |      3.29% |      267 ms |   738 ms |         895 ms |  430 MiB |
| Whisper medium.en Q5 |      6.26% |      617 ms |  1912 ms |        2593 ms |  935 MiB |
| Whisper Turbo Q5     |      3.21% |      711 ms |  2096 ms |        3286 ms |  885 MiB |
| Whisper large-v3 Q5  |      2.80% |     1269 ms |  3825 ms |        4284 ms | 1675 MiB |

**Selected checkpoints:** Parakeet TDT 0.6B v3 and Whisper small.en. V3 beat English-only Parakeet v2 by 17 word errors at effectively the same latency. Whisper small.en missed one more reference word than Turbo (40 vs. 39) while using about half the memory and 38% of Turbo's median latency. Full large-v3 recovered six words relative to small.en but cost 4.8× the median latency and 3.9× the memory. Medium.en suffered a severe repeated/truncated decode on one fixture.

## Runtime and backend matrix

The checkpoint is held constant, but each runtime requires its own available model conversion and quantization. This is a practical artifact comparison, not a bit-identical kernel benchmark.

| Model            | Runtime        | Backend               | Artifact          | Cold load | Warm median | Warm p95 |            93.5 s fixture | Corpus WER |  Peak RSS | Work status |
| ---------------- | -------------- | --------------------- | ----------------- | --------: | ----------: | -------: | ------------------------: | ---------: | --------: | ----------- |
| Parakeet v3      | transcribe.cpp | Metal                 | Q5_K_M            |    120 ms |      172 ms |   853 ms |                   1087 ms |      2.55% |  1654 MiB | precedent   |
| Parakeet v3      | transcribe.cpp | CPU                   | Q5_K_M            |    153 ms |      683 ms |  3311 ms |                   4010 ms |      2.39% |  1733 MiB | precedent   |
| Parakeet v3      | whisper.cpp    | Metal                 | Q4_K              |    147 ms |      210 ms |   860 ms |                   1052 ms |      4.28% |  1395 MiB | allowed     |
| Parakeet v3      | whisper.cpp    | CPU                   | Q4_K              |    182 ms |      569 ms |  2566 ms |                   3147 ms |      4.20% |  1162 MiB | allowed     |
| Parakeet v3      | sherpa-onnx    | ONNX CPU              | INT8              |    746 ms |      417 ms |  2020 ms |                   2285 ms |      6.67% |  3225 MiB | not allowed |
| Parakeet v3      | sherpa-onnx    | ONNX Core ML EP       | INT8              |   3382 ms |      938 ms |  4898 ms |                  15868 ms |      6.34% | 29296 MiB | not allowed |
| Parakeet v3      | mlx-audio      | MLX Metal             | F32/BF16          |   3034 ms |      130 ms |   488 ms |                    589 ms |      2.47% |  2824 MiB | not allowed |
| Whisper small.en | transcribe.cpp | Metal                 | Q5_K_M            |     60 ms |      267 ms |   743 ms |                    902 ms |      3.29% |   429 MiB | precedent   |
| Whisper small.en | transcribe.cpp | CPU                   | Q5_K_M            |     60 ms |      997 ms |  2944 ms |                   3802 ms |      2.88% |   465 MiB | precedent   |
| Whisper small.en | whisper.cpp    | Metal                 | Q5_1              |     93 ms |      272 ms |   753 ms |                    945 ms |      3.38% |   432 MiB | allowed     |
| Whisper small.en | whisper.cpp    | CPU                   | Q5_1              |     84 ms |      682 ms |  2150 ms |                   2715 ms |      3.38% |   644 MiB | allowed     |
| Whisper small.en | sherpa-onnx    | ONNX CPU              | INT8              |    591 ms |     1643 ms |  2477 ms | 1727 ms (first 30 s only) |    33.86%† |  1896 MiB | not allowed |
| Whisper small.en | sherpa-onnx    | ONNX Core ML EP       | INT8              |   2905 ms |     4509 ms |  6956 ms | 4725 ms (first 30 s only) |    33.94%† | 11635 MiB | not allowed |
| Whisper small.en | mlx-whisper    | MLX Metal             | 4-bit             |   1181 ms |      257 ms |   610 ms |                    813 ms |      3.71% |   613 MiB | not allowed |
| Whisper small.en | WhisperKit     | Core ML/ANE preferred | 217 MB compressed |    475 ms |      802 ms |  1809 ms |                   3696 ms |      3.79% |   172 MiB | not allowed |

WhisperKit has no Parakeet implementation. Its first uncached Core ML specialization took 15,112 ms; the immediately repeated process loaded in 503 ms. whisper.cpp's first Metal use took 7,359 ms, including 7,247 ms loading/specializing its embedded Metal library. MLX Parakeet's first process loaded in 9,579 ms and a later process in 3,034 ms. Later-process measurements are shown above; aggregate first-use observations are in [`aggregate.json`](aggregate.json).

† sherpa-onnx's Whisper implementation explicitly discards audio after 30 seconds. Eight fixtures exceeded that limit, so its full-corpus WER is not comparable.

## What the matrix says

- `transcribe.cpp`/Metal was the strongest allowed-precedent Parakeet lane: 172 ms median, 2.55% corpus WER, and a roughly 120 ms resident load. MLX was marginally faster and one word better, but its first process loaded in 9.6 seconds (3.0 seconds after caching), used 2.8 GiB RSS, and brings a large unapproved dependency graph.
- For Whisper small.en, `transcribe.cpp` and `whisper.cpp`/Metal were effectively tied: 267 vs. 272 ms median and 3.29% vs. 3.38% WER. `transcribe.cpp` keeps the cross-family seam; `whisper.cpp` remains the more mature, explicitly allowed runtime.
- CPU was consistently slower. It changed a few hypotheses because floating-point reductions differ, but offered no responsiveness win on the target M4 Pro.
- WhisperKit's compressed small.en artifact was slower here (roughly 800 ms median) than the GGUF/GGML and MLX lanes. Its low process RSS does not include Core ML/ANE device accounting in a form comparable to the native runtimes.
- sherpa-onnx/CPU used more memory and produced worse Parakeet text. Its Core ML execution provider was slower, reached a 29 GiB process high-water mark for Parakeet, and repeatedly logged `Context leak detected`. The Whisper path's 30-second hard limit disqualifies it for unconstrained hold dictation without an additional chunk/stitch layer.
- MLX requires two separate Python libraries in the working prototype: `mlx-audio` for Parakeet and `mlx-whisper` for Whisper. The supposedly unified `mlx-audio` Whisper path produced corrupt repeated output on the tested quantized small.en artifacts, so it was not substituted into the working cell.
- Released `transcribe.cpp` v0.1.3 Parakeet polls cancellation only before inference. A disposable native patch wired its existing GGML Metal/CPU abort mechanism into the encoder and polled the host decoder; active requests then aborted within 74.9 ms without changing corpus WER or median latency. The fix can be upstreamed or carried with the pinned XCFramework build.

## Support and integration shape

| Runtime        | Parakeet v3             | Whisper small.en    | Production shape                                                                            |
| -------------- | ----------------------- | ------------------- | ------------------------------------------------------------------------------------------- |
| transcribe.cpp | Yes                     | Yes                 | One Swift XCFramework and one wrapper; direct Whispering allowlist precedent                |
| whisper.cpp    | Yes, newer API/artifact | Yes                 | Mature C/C++ runtime; explicit allowlist entry; family-specific native APIs                 |
| WhisperKit     | No                      | Yes                 | Swift/Core ML/ANE; separate unapproved dependency and model bundle                          |
| sherpa-onnx    | Yes                     | Yes, but 30 s limit | C/C++ plus ONNX Runtime; unapproved dependency                                              |
| MLX            | Yes via mlx-audio       | Yes via mlx-whisper | Two Python implementations and broad dependency graphs; unsuitable as-is for the signed app |

## Measurement cautions

- Peak RSS is each process's macOS high-water mark. GPU, ANE, and Core ML allocations are not accounted identically, so compare it as integration evidence rather than a universal device-memory measure.
- Warm latency starts after the 16 kHz PCM fixture is available and ends at final text, matching simulated hold-release. Models remain resident within each process.
- Cold load excludes download and measures runtime/model initialization. Core ML and Metal may create persistent OS caches, so first-ever and later-process measurements are recorded separately where observed.
- Available runtime conversions differ in quantization: transcribe.cpp Q5_K_M, whisper.cpp Q4_K/Q5_1, sherpa INT8, MLX F32/BF16 or 4-bit, and WhisperKit's 217 MB Core ML compression.

Raw fixture outputs are intentionally retained only under the gitignored `.artifacts/results/` directory.
