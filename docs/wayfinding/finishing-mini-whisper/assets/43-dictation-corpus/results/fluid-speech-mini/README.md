# Fluid Speech Mini

The measured bakeoff for [Fluid Speech Mini](https://huggingface.co/FluidVoice-Labs/fluid-speech-mini-coreml) (`FluidVoice-Labs/fluid-speech-mini-coreml @ d81c316`), a compressed Parakeet TDT 0.6B v3 / Moondream Parakeet Ultra derivative. It ran through the real `ASREngine`, with every stage replayed by `asr-replay` and the app benchmarked live, against a same-session rerun of the shipping Parakeet v2 in [`v2-rerun/`](v2-rerun/). The rerun reproduces [built-in](../built-in/)'s stage-1 result word for word, so the comparison is between engines, not between sessions.

**Verdict: do not adopt.** Mini misses the one prescribed accuracy bar, stage-1 WER no worse than v2's 1.95%, and wins nothing on the dictation path that would offset that. Its real gains are 200 MB less disk, a 200 MB lower load-time memory peak, and a faster cold compile, which are conveniences, not reasons to switch engines.

## Conditions

- MacBook built-in microphone recordings, the same files as every other run. Measured 2026-10-21 on this Mac (arm64, macOS 27.0, Xcode 27.1, Swift 6.4).
- FluidAudio **0.17.5**, unchanged. Mini loads through `AsrModels.loadLocal(from:version: .ultra)` from the pinned artifact directory. The repository's `JointDecision.mlmodelc` is installed as `JointDecisionv3.mlmodelc`, the name FluidAudio hardcodes for v3-family joints. `ASRConfig(parallelChunkConcurrency: 4, streamingEnabled: false, melChunkContext: true, dualDecodeArbitration: false)` and the CTC-110m boost helper are both unchanged.
- Placement is identical for both engines: preprocessor on CPU, everything else on CPU and Neural Engine.
- Mini was installed by the dev app's own pinned downloader into a separate engine root, `Engine/pinned-fluid-speech-mini`, so v2's `pinned-v1` stayed in place for the baseline. That download is the first-setup timing below.
- `asr-replay` gained one stderr line, `engine ready in …`. Each stage ran as its own process under `/usr/bin/time -l`. v2 ran all stages first, then Mini, serially, with nothing else running.

## Headline

| measure | Parakeet v2 | Fluid Speech Mini |
| --- | --- | --- |
| Stage 1 WER (205 words) | **1.95%** (4S) | 2.93% (6S) |
| Stage 1 holdout WER (122 words) | 2.46% (3S) | 2.46% (3S) |
| Stage 2 bare `wants` / traps | **5/18** · 0/8 | 4/18 · 0/8 |
| Stage 2 boosted `wants` / traps | 16/18 · 5/8 | **17/18 · 4/8** |
| Stage 2 holdout boosted | 9/10 · 0/6 | 9/10 · 0/6 |
| Boost overhead (median) | +114 ms | +112 ms |
| Longform WER (6 entries, 567 words) | **8.11%** | 9.70% |
| Longform WER, spoken punctuation stripped | **3.88%** (22) | 4.23% (24) |
| Seam fixtures: duplicated or dropped words | 0 | 0 |
| Short-utterance latency (stage 1 median, 3 reps) | 40–42 ms | **36–38 ms** |
| Long-audio latency (longform median / seam median) | **108 / 157 ms** | 156 / 214 ms |
| ASR artifact on disk | 443 MB | **243 MB** |
| First compile + prewarm, in app | 213 s historical | **21.5 s** (9.4 s + 12.1 s) |
| Cold first replay process load | 24.8 s | **21.1 s** |
| Warm load (replay / app) | 0.29 s / 0.31–0.43 s | **0.26 s / 0.28–0.35 s** |
| App RSS 1.5 s after launch, engine ready (3 runs) | 184–186 MiB | 178–184 MiB |
| App `phys_footprint` steady / load peak | 85–99 MB / 651–686 MB | 93–96 MB / **451–453 MB** |
| Replay peak RSS, short / long audio | 104.6 / 131.5 MiB | 101.6 / 146.0 MiB |
| `benchmark:live` budgets | pill FAIL ×3 on run 1 (26–34 ms) | PASS ×3 (pill max 13–25 ms) |

Stage 1's six Mini errors are colonel→kernel, daemon→demon, cache→cash, steady→study, chopped→chops, and their→the. Mini fixes v2's week→weak and cash→cache but adds four of its own. It is the same 2.93% stock v3 scored in [fluid-parakeet-v3](../fluid-parakeet-v3/) and in the same shape, with confusables resolved differently and nothing dropped. WER is deterministic: three stage-1 replays per engine gave identical transcripts.

## Long audio

**No seam defects.** [`seam_fixtures.py`](../../seam_fixtures.py) concatenates stage-1 recordings into six 30, 60, and 90-second fixtures. Each length comes in two forms: `tight`, with 50 ms between utterances so words straddle window boundaries, and `gapped`, with 1.5 s of room-level noise so quiet pauses straddle them. Each engine's transcript of a fixture is then diffed against the same engine's transcripts of the isolated utterances, so only what long audio introduces can show up.

Across the 1,005 words, neither engine duplicates or drops a word. Every difference is a homophone flipping under longer context. v2 flips 15 words, mostly brake→break, site→sight, and steady→study. Mini flips 27, mostly cash→cache, heir→air, the→their, and brake→break. Detail is in `seam-diff.json`.

**Mini does not lose the passage stock v3 lost.** On the real 36-second `longform-02`, v3 skipped from "a very deep well" to "Why I wouldn't". Mini keeps every word v2 keeps. Its extra long-form errors are mostly spoken "quote" words that the reader actually said and the typographic reference leaves out. With spoken punctuation stripped from both hypotheses, the gap narrows to two words in 567. The longform script and recordings, `stage1-longform.jsonl` and `recordings/stage1-longform/`, are not committed yet. They were read from the main checkout, and the scores here depend on them.

Mini is about 45% slower on long audio: 156 ms against 108 ms median over 35-second recordings. It is about 10% faster on everything under 15 s.

## Stage 3: different, not better

Scored as WER against the verbatim `say`, Mini's raw polish transcripts look far better: 8.81% (26/295) against 12.88% (38/295). Most of that gap is formatting, because v2 renders spoken punctuation as symbols:

| entry | v2 | Mini |
| --- | --- | --- |
| polish-06 | `Add milk, eggs, and bread period.` | `Add milk, comma, eggs, comma, and bread, period.` |
| polish-14 | `thurston at example.com period.` | `thurston at example dot com, period.` |
| polish-11 | `She said it ships tonight, period.` | `She said, quote, it ships tonight, unquote, period.` |
| polish-38 | `My last name is Sandberg, San Dberg.` | `My last name is Sandberg, comma, SANDBERG, period.` |

The genuine differences are narrow. Mini keeps quote/unquote and fillers, and its spell-out arrives as one word instead of a broken one. Those touch v2's one documented weakness, meta-speech deletion. Against that, Mini mishears "write a poem" as "write at home" (`polish-28`), tier as year, Grok as Groc, and Katherine as Catherine. On the holdout it is one error worse: 10.69% (17/159) against 10.06% (16/159). Whether the meta-speech it keeps converts into cleanup wins would take an e2e cleanup run, which was not part of this bakeoff.

## Live benchmark

`benchmark:live`'s script launches the app binary directly, which makes the launching shell the TCC-responsible process. From an agent runner without a microphone grant, every capture failed with "Microphone permission remains undetermined". Both engines were therefore launched with `open --env MINIWHISPER_BENCHMARK_ACTIVATION=1`, with the same log predicate and the same `report_interaction_latencies.py`.

The benchmark records whatever the room holds, and it cannot tell these engines apart. `release→transcription` stops at `transcription-started`, before the decoder runs. Most cycles were silence the gate rejected. Two cycles caught nearby speech, and the app transcribed it, cleaned it up, and pasted it into the focused field. The first-activation pill sits on the 25 ms budget for both engines (v2 26–34 ms, Mini 13–36 ms including an earlier unrepeated run), so it is pill noise, not an engine effect.

## Files

| file | what it is |
| --- | --- |
| `stage1*.jsonl`, `stage2-*.jsonl`, `stage3-*raw.jsonl` | Mini's raw `asr-replay` output, per stage and holdout |
| `stage1-longform.jsonl` | the six uncommitted longform recordings |
| `seam.jsonl`, `seam-fixtures.jsonl` | fixture transcripts, and the fixture definitions `seam_fixtures.py build` writes (deterministic, seed 43) |
| `*-score.json` | `score_corpus.py` detail; `seam-diff.json` is `seam_fixtures.py diff` |
| `runtime.txt` | per-process load and peak RSS, the in-app first setup, all six live runs, app memory |
| `v2-rerun/` | the same files for Parakeet v2, same session |

```sh
./seam_fixtures.py build stage1-intelligibility.jsonl \
  recordings/stage1-intelligibility-built-in /tmp/seam
$REPLAY --stage /tmp/seam/seam-fixtures.jsonl --recordings /tmp/seam \
  --output results/fluid-speech-mini/seam.jsonl
./seam_fixtures.py diff /tmp/seam/seam-fixtures.jsonl \
  results/fluid-speech-mini/seam.jsonl results/fluid-speech-mini/stage1.jsonl
```

The engine integration was a throwaway diff and is not kept. It repinned `PinnedModelStore`'s ASR repository and revision, renamed the joint on download and validation, swapped `AsrModels.load(…, version: .v2)` for `loadLocal(…, version: .ultra)` in `LocalASREngine`, and pointed `Channel.engineRoot` and `asr-replay`'s default root at `Engine/pinned-fluid-speech-mini`.
