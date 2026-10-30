# Nemotron 3.5: full model, Core ML Lite, and prompted Whisper

**Keep Parakeet v2 for short dictation. Reject this Core ML Lite configuration as a dictation replacement. Full Nemotron is worth comparing with vocabulary-conditioned Whisper, not just bare Parakeet, but this run does not justify changing the shipped engine.** No app code or profile changed. Further experiments were deferred by the user; the two downloaded Nemotron models were removed afterward.

The request came from [Artificial Analysis's announcement](https://x.com/artificialanlys/status/2115459886045942161) and [the Core ML conversion demo](https://x.com/alex_tra_memory/status/2115468824392704337). The full local candidate is a community **EA 4-bit MLX conversion**, not NVIDIA's official BF16 checkpoint or the Artificial Analysis serving configuration. The Lite candidate removes the language model and greedily decodes its CTC timestamp head; it is not an accuracy-preserving optimization of the full model.

## Bare recognition

All four engines processed the same 112 recordings: intelligibility (25), intelligibility holdout (15), longform (6), dictionary (24), dictionary holdout (15), and polish raw (27). No gate, vocabulary conditioning, or cleanup in these arms. WER is lower-is-better.

| Engine | Short WER, 40 clips / 327 words | Longform WER, 6 clips / 567 words | Short median, primary 25 clips | Longform median | Model files |
| --- | ---: | ---: | ---: | ---: | ---: |
| Parakeet TDT v2 | **2.14%** (7 errors) | 8.11% | **39.5 ms** | **109.0 ms** | **464 MB** |
| Whisper large-v3-turbo | 2.75% (9 errors) | 10.23% | 454.6 ms | 1,298.8 ms | 1,625 MB |
| Nemotron full, MLX 4-bit | 3.67% (12 errors) | **5.82%** | 363.7 ms | 1,956.3 ms | 19,276 MB |
| Nemotron Core ML Lite | 9.48% (31 errors) | 6.53% | 172.5 ms | 181.1 ms | 1,364 MB |

Short WER combines the primary and holdout sets; the latency column uses the primary set only. The existing rollup's stage-1-only scores are therefore a different denominator: this run has 1.95%, 3.41%, 4.39%, and 9.76% respectively on those 25 clips alone.

Lite is smaller and faster than full Nemotron, but still about four times slower than Parakeet on short clips, with many more errors. Examples include `lemons` → `lons` and `Sandberg` → `Sandbg`; it recovers only 2/28 exact dictionary terms without conditioning. Its 48-second fixed input windows and meeting-throughput headline do not establish short-dictation latency. The longform result is more competitive, but six passages are not evidence of a general bulk-transcription advantage.

Full Nemotron retains useful material Parakeet loses: `polish-11` includes `quote` and `unquote`, and `polish-38` includes the complete spelled surname. Both engines transcribe rather than obey the embedded request for a poem in `polish-28`. These are raw recognition observations, not a cleanup-quality evaluation.

## Vocabulary-conditioned Whisper is the fairer comparison

Each model received the same sorted union of its dictionary stage's `wants` terms, including on trap recordings. No sentence reference was supplied. Whisper receives a comma-separated decoder prompt; Nemotron receives the MLX port's contextual vocabulary appended to the fixed transcription instruction. Neither has a downstream cleanup pass.

| Arm | Primary exact wants | Holdout exact wants | Combined | Exact trap hits | Median across 39 clips |
| --- | ---: | ---: | ---: | ---: | ---: |
| Whisper + prompt | 12/18 | **10/10** | 22/28 | 0/14 | 468.6 ms |
| Nemotron + context | **16/18** | 9/10 | **25/28** | 0/14 | **402.3 ms** |

Bare Whisper recovers 13/28 terms; bare Nemotron recovers 7/28. Conditioning makes a substantial difference to both. Nemotron wins the combined conditioned result, but Whisper wins the holdout and uses roughly one-twelfth the weight storage. Nemotron misses `llama.cpp` twice and `Keychain` once; Whisper's five primary misses are `Cerebras`, `Ghostty`, `Homebrew`, `Keychain`, and `tuistory`. Fourteen unbitten traps on one voice are not a general hallucination guarantee; these are the existing scorer's case-sensitive substring checks.

## Runtime and measurement contract

- Hardware: Apple M4 Pro, 48 GiB unified memory, macOS 27.0.1. Serial inference, one measured pass per recording. Parakeet and full Nemotron were measured first; Lite and Whisper were added later in the same investigation, not an interleaved repeated timing study.
- Timers start after decoding WAVs to mono 16 kHz float samples and end at text. Feature extraction is included; model loading and warmup are excluded. All candidates run locally; no recordings were uploaded.
- Parakeet uses release `asr-replay`, with an isolated model library and the production gate-bypassing replay path. One process per stage.
- Full Nemotron stays resident across six stages. `mlx-audio` revision `92decb7577878ef8e9274c1a7e33084760be03aa`, MLX 0.32.4, Python 3.12.13; strict model loading, temperature 0, thinking off, 1,024-token cap, synchronized timing, one excluded real-audio warmup. No output hit the token cap. The separate vocabulary process uses the same configuration.
- Nemotron's fixed prompt: `Audio transcription. Language: as spoken. Wording: verbatim, including fillers and repetitions. Formatting: punctuation and capitalization. Output: transcript only.` No prompt tuning was performed.
- Lite uses the upstream `demo/frontend.py` and `demo/lite_meeting.py` recognizer components unchanged: fp16 `lite_encoder_w48.mlpackage` and `lite_ctc_head_w48.mlpackage`, CPU_AND_GPU, NumPy preprocessing, greedy CTC. No diarizer or LLM. One resident instance, synthetic and real-audio warmups. coremltools 9.0, NumPy 1.26.4, sentencepiece 0.2.2, soundfile 0.13.1, Python 3.12.13. The snapshot was materialized without symlinks because the demo locates assets relative to its resolved source path.
- Whisper uses resident whisper.cpp v1.9.1, revision `f049fff95a089aa9969deb009cdd4892b3e74916`, not one CLI/model load per clip. Metal, flash attention, four threads, English, beam size 5, best-of 5, no timestamps, previous-clip context disabled, remaining decoding defaults. One process and excluded real-audio warmup per stage. The existing native bakeoff harness was adapted only to accept the vocabulary prompt, select these decoder settings, and include text retrieval in its timer.
- Full Nemotron peaked at 20.30 GB of MLX Metal allocations. Its recorded process RSS is not total GPU memory. Core ML/ANE memory is also not captured equivalently by RSS; do not add or directly rank these counters as universal memory footprints.
- Longform references have known spoken-punctuation and apostrophe-normalization discrepancies. All arms use the unchanged corpus scorer; these scores mix recognition errors with reference formatting. The field cases, seam fixtures, layout set, cleanup passes, quantized Whisper, Lite's ANE/int8/4-bit variants, and NVIDIA GPU serving optimizations were not tested here.

## Exact artifacts

| Engine | Artifact identity |
| --- | --- |
| Parakeet v2 | `FluidInference/parakeet-tdt-0.6b-v2-coreml@ee09c569f73759e6d44c9bd16766f477b2b36d39` |
| Full Nemotron | `nativ-community/Nemotron-3.5-Transcribe-30B-A4B-EA-4bit@c47153ca2ce4024d43e216b81e6db4f67b886545` |
| Lite | `FluidInference/nemotron-3.5-transcribe-lite-coreml@fe237a37e9042b9de88827fcdbdae2efc4fd4bba` |
| Whisper | `ggml-large-v3-turbo.bin`, fp16, SHA-256 `1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69` |

Each engine directory retains per-recording transcripts and timings in the existing replay schema, plus runtime records. The two `*-context` directories use the same `stage2-bare.jsonl` and `stage2-holdout-bare.jsonl` filenames for scorer compatibility, but their transcripts **are conditioned**. The Nemotron `runtime/stage1.json` files describe the entire resident process; the contextual process did not run stage 1. Whisper runtime records exclude warmup from load time; Nemotron and Lite include it. First-load numbers are not a controlled cold-start comparison.

[`summary.json`](summary.json) retains the combined headline numbers. Rescore the four base engine directories with `bakeoff.py compare`, and the vocabulary files with `score_corpus.py sweep`, from the parent corpus directory. All 112 IDs per base engine and all 39 IDs per conditioned engine were checked against the expected stage manifests. The disposable runners and full logs remain attached to the [investigation thread](https://ampcode.com/threads/T-01a183c9-9f69-718c-9550-c089ff6f4930); no experimental runner was added to the production engine catalogue.
