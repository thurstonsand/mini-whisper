# Fluid Speech Pro

The measured bakeoff for [Fluid Speech Pro](https://huggingface.co/FluidVoice-Labs/fluid-speech-pro) (`FluidVoice-Labs/fluid-speech-pro @ 53f490b`), FluidVoice's Parakeet TDT 0.6B v3 / Moondream Parakeet Ultra fine-tune, announced as "#1 on the Open ASR benchmark (9 public sets)" and published on 2026-10-30. FluidVoice ships only a 2.5 GB `.nemo` plus a clean-mode adapter, so it ran three ways against a same-session rerun of the shipping Parakeet v2 in [`parakeet-v2/`](parakeet-v2/), which reproduces [built-in](../built-in/)'s stage 1 word for word:

- `fluid-speech-pro`: the `.nemo` itself, verbatim, through NeMo on the GPU, by [`transcribe_fluid_speech.py`](../../transcribe_fluid_speech.py). This is the model's accuracy as published.
- `fluid-speech-pro-coreml`: [`cyron/fluid-speech-pro-coreml @ ec52e16`](https://huggingface.co/cyron/fluid-speech-pro-coreml), an unofficial fp16 Core ML conversion of the same revision, through the real `ASREngine` and `asr-replay`. This is what MiniWhisper could actually ship, and its runtime numbers are the perf measurement.
- `fluid-speech-pro-clean`: the `.nemo` with its clean-mode adapter folded in, which drops fillers and repeated words. NeMo only; no Core ML conversion includes it.

Produced with `./bakeoff.py run fluid-speech-pro fluid-speech-pro-coreml fluid-speech-pro-clean --label fluid-speech-pro`; the full table is [comparison.txt](comparison.txt).

**Verdict: do not adopt.** Pro misses the one prescribed accuracy bar, stage 1 WER no worse than v2's 1.95%, in every form MiniWhisper could run. On short dictation it is Fluid Speech Mini again: the same 2.93%, from the same confusables. The Core ML build matches v2's short-dictation speed, but it is 40% slower on long audio, loses long-form accuracy, takes 2.6× the disk, and hits 3 of the 18 bare dictionary terms where v2 hits 5. The benchmark win does not transfer to this voice and this microphone.

## Conditions

- MacBook built-in microphone recordings, the same files as every other run. Measured 2026-11-03 on this Mac (M4 Pro, macOS 27.0.1, Xcode 27.2, Swift 6.4.2).
- Core ML: FluidAudio **0.17.5**, unchanged, loaded as `.ultra` from `.build/bakeoff-models/`. The conversion already names its joint `JointDecisionv3.mlmodelc`, so the catalogue entry needs no rename. `ASRConfig` and the CTC-110m boost helper are unchanged, so the boosted rows are real.
- NeMo: `nemo_toolkit[asr]` 3.0.0, torch 2.15.0, Python 3.12, MPS, one `transcribe()` call per recording. The script rebuilds the repository's extra pre-Conformer block and clean-mode fold itself instead of importing its `fluid_speech.py`, then loads every tensor strictly. CPU gives identical transcripts at about 12× the latency. NeMo has no recognition sidecar, so its boosted rows are dashes.
- The NeMo weights were downloaded before the run (10.3 s for 2.6 GB), so its download row reads "already installed".
- Every run was serial, one process per stage, with nothing else running. `benchmark:live` was not run.

## Headline

| measure | Parakeet v2 | Pro, Core ML | Pro, `.nemo` | Pro, clean mode |
| --- | --- | --- | --- | --- |
| Stage 1 WER (205 words) | **1.95%** (4S) | 2.93% (6S) | 2.93% (6S) | 2.44% (5S) |
| Stage 1 holdout WER (122 words) | 2.46% | 2.46% | 2.46% | 2.46% |
| Longform WER (567 words) | 8.11% | 9.17% | 7.23% | **5.64%** |
| Field cases WER (say seeded from v2) | **0.38%** | 3.77% | 1.89% | 6.42% |
| Stage 3 raw vs verbatim `say` | 12.88% | 9.15% | 9.83% | **5.42%** |
| Stage 2 bare `wants` / holdout | **5/18 · 5/10** | 3/18 · 3/10 | 3/18 · 3/10 | 2/18 · 4/10 |
| Stage 2 boosted `wants` · traps | 16/18 · 5/8 | **17/18** · 5/8 | — | — |
| Stage 2 holdout boosted | 9/10 · 0/6 | 9/10 · 0/6 | — | — |
| Seam fixtures: duplicated or dropped | 0 | 0 | 0 | 0 |
| Short-utterance latency (stage 1 median) | 39.9 ms | **37.8 ms** | 75.1 ms | 75.3 ms |
| Long-audio latency (longform / seam median) | **109 / 160 ms** | 154 / 199 ms | 574 / 620 ms | 326 / 645 ms |
| Model on disk | **464 MB** | 1,228 MB | 2,518 MB | 2,628 MB |
| First process load (download + compile) | 25.9 s | 22.4 s | 12.2 s | 12.7 s |
| Warm load (median) | 0.30 s | **0.28 s** | 11.2 s | 11.5 s |
| Replay peak RSS, first / warm processes | **968 / 104–133 MiB** | 2,374 / 102–148 MiB | 5.8 GiB every process | 5.8 GiB |

The Core ML build's six stage 1 errors are colonel→kernel and daemon→demon, which v2 shares, plus steady→study, their→the, brake→break and cache→cash; it fixes v2's week→weak and cash→cache. Five of the six are [fluid-speech-mini](../fluid-speech-mini/)'s errors, and the total is the 2.93% that both Mini and stock v3 in [fluid-parakeet-v3](../fluid-parakeet-v3/) scored. Pro trades Mini's chopped→chops for brake→break. Whatever FluidVoice trained into Pro does not reach these confusables. The `.nemo` makes the same errors, except that it hears colonel correctly and writes colonel for "kernel" instead.

## The Core ML build is the one that counts

The conversion is faithful on short audio: its stage 1 and holdout transcripts match the `.nemo`'s except one colonel/kernel swap. Long audio is where they part. The `.nemo` wins long-form outright at 7.23%, but the Core ML build scores 9.17%, worse than v2's 8.11% and close to Mini's 9.70% on the same engine. The loss sits in `longform-01` (3 → 6 errors) and `longform-06` (9 → 13). The likely cause is FluidAudio's 15-second chunking rather than the fp16 conversion, since NeMo hears each recording whole; this run did not isolate it.

Speed is a split. Under 15 s, Pro on Core ML is v2's equal, 37.8 ms against 39.9 ms. On 35-second recordings it is 41% slower, 154 ms against 109 ms, the same penalty Mini paid. Warm memory is the same as v2's, but the model is 2.6× v2 on disk and its first compile peaks at 2.4 GiB against v2's 0.97 GiB. An int8 conversion (`TalkMate/fluid-speech-pro-coreml`, about 0.6 GB) exists but was not run.

The dictionary loses ground. Bare, Pro misses MiniWhisper (MiniWisper), llama.cpp (lama.cpp), Homebrew (lowercased) and SwiftUI (Swift UI), and gains Zigbee and the spoken llama.cpp port. With the boost sidecar it recovers to 17/18, one better than v2, at the same +119 ms. The field cases' `say` is seeded from v2, so their 3.77% leans toward v2. The Core ML build still inserts a repeated "want" and joins the spelled "g r o q" that the field case exists to keep.

## Stage 3: meta-speech kept, again

Like Mini, Pro keeps the meta-speech v2 deletes, which is most of its stage 3 gain: `polish-11` keeps "quote … unquote" and `polish-06` keeps "comma". On the holdout it never drops a word (0 deletions against v2's 6). `polish-38`'s spelled surname arrives as one word, `SANDBERG`, rather than v2's broken `San Dberg`. Whether that converts into cleanup wins would take a `tune.py` run on these raws. The four contract files are in each engine directory.

## Defects in the published model

- **The `.nemo` emits `<unk>`.** NeMo renders SentencePiece id 0 as `⁇`, and the verbatim model produces it in `longform-01` and `hpolish-13` ("Email Mia ⁇ that's M-I-A-N-W8 ⁇ Email Mara"). CPU and MPS agree, so it is the weights, not the runtime. The Core ML build has a comma at the same spot, so FluidAudio's vocabulary path hides it.
- **Clean mode is not usable for dictation.** Its numbers look best wherever the reference is edited prose, and its stage 1 drops one error. But it emits `⁇` in `polish-11` and `trap-04`, spells acronyms out ("l l m", "m m", "T. C. A."), and mishears Grok as Groc. It also exists only as a NeMo adapter.

## Files

| file | what it is |
| --- | --- |
| `<engine>/*.jsonl` | per-run transcripts, `asr-replay` or `transcribe_fluid_speech.py` |
| `<engine>/runtime/*.json` | per-process identity, load seconds, peak RSS, model bytes, download seconds |
| `<engine>/seam-fixtures.jsonl` | fixture definitions `seam_fixtures.py build` writes (deterministic, seed 43) |
| `comparison.txt` | `bakeoff.py compare` over all four engines |

The Core ML candidate is the `fluidSpeechPro` entry in `SpeechModel.catalogue`, kept as the worked example of a third-party conversion. The NeMo engines are `SCRIPTED` targets in `bakeoff.py`.
