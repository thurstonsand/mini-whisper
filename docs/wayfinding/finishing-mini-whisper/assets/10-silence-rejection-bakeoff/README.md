# Silence rejection bakeoff

Disposable macOS arm64 prototype for choosing MiniWhisper's utterance-level speech gate. It is isolated from the app and production packages.

The pipeline is deliberately narrow:

```text
complete 16 kHz mono recording
  ├─ RMS measurements (comparison only)
  └─ whisper.cpp Silero v6.2 classification
       ├─ no speech → successful empty result; FluidAudio is never called
       └─ speech → pass the original complete recording to FluidAudio AsrManager
                    (its existing 15-second overlap/merge remains unchanged)
```

Silero does not trim, concatenate, chunk, or stitch audio. That prevents the gate from changing FluidAudio's tested long-form geometry.

## Pins and test machine

- Test machine: Apple M4 Pro, macOS 26.5.2 (`25F84`), arm64.
- whisper.cpp `v1.9.1`: `f049fff95a089aa9969deb009cdd4892b3e74916`, CPU VAD path.
- Silero `v6.2.0`: `ggml-silero-v6.2.0.bin`, SHA-256 `2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987`.
- FluidAudio `v0.15.5`: `19600a485baa4998812e4654b70d2bab8f2c9949`.
- Parakeet TDT 0.6B v2 Core ML: `FluidInference/parakeet-tdt-0.6b-v2-coreml@ee09c569f73759e6d44c9bd16766f477b2b36d39`, English-only, int8 encoder.
- FluidAudio configuration: ordinary `AsrManager`, four parallel chunks, mel context enabled, no dual-decode arbitration. This is its upstream 15-second overlap/merge path.
- Capture devices: MacBook Pro Microphone and work-approved Shure MV7.
- Capture format: mono 16 kHz PCM16 WAV. `ffmpeg` performs the microphone-edge conversion.

The setup script pins source and model revisions. Its Python virtual environment is setup tooling only; MiniWhisper does not acquire a Python dependency.

## Setup

```sh
cd docs/wayfinding/finishing-mini-whisper/assets/10-silence-rejection-bakeoff
./scripts/setup.sh
```

This clones pinned sources, verifies Silero's hash, builds whisper.cpp and the FluidAudio transcription harness, downloads the pinned Core ML model, and generates committed synthetic fixtures.

A synthetic smoke run requires no microphone:

```sh
./scripts/run.py fixtures/synthetic-manifest.json --output results/synthetic.json
```

The synthetic corpus is not evidence for speech recall. It proves WAV validation, RMS and VAD sweeps, decoder skipping, hallucination measurement, and capture-buffer-invariant framing. In the first full smoke run, Parakeet hallucinated `I'm not sure if I can do it.` on synthetic impulses with no gate; Silero rejected the clip and skipped the decoder.

## Private fixture capture

List the current AVFoundation indexes immediately before capture; indexes are not stable across reconnects:

```sh
ffmpeg -f avfoundation -list_devices true -i ''
```

At prototype creation the available physical inputs were MacBook Pro Microphone, Arctis Nova Elite, and Shure MV7. Thurston confirmed the Shure MV7 as the approved work microphone. The manifest still names device roles so it remains readable if AVFoundation indexes change.

Capture every missing local fixture interactively:

```sh
./scripts/capture-corpus.py --built-in 1 --work-headset 2
```

Replace the example indexes with the current MacBook and approved-work-device indexes. The script records under `fixtures/local/`; every WAV there is ignored by git. It will not overwrite an existing fixture, so interrupted runs resume safely.

`fixtures/local-manifest.json` is committed. It describes the absent private corpus, including literal and long room tone, lone taps, fan/HVAC, keyboard, mouse, headphone media isolation, quiet and whispered speech, short words, clipped release, leading/trailing silence, and quiet spans around FluidAudio's 15-second boundaries. Calibration and holdout membership was fixed before capture. Audio and video use headphones in the representative environment, so the media fixtures correctly test leakage through that path rather than an irrelevant open-speaker scenario.

Do not record private work content. The scripted phrases are intentionally inert. For the two long boundary fixtures, use a non-private paragraph and update `reference` afterward.

## Fixture label format

Each manifest entry has:

| Field | Meaning |
| --- | --- |
| `id` | Stable result identity. |
| `file` | WAV path relative to the manifest. Local WAV paths live below the ignored `local/` directory. |
| `split` | `calibration` or `holdout`; settings are selected only from calibration. |
| `label` | User-intent label: `speech` or `no_speech`. |
| `category` | Failure class used during review. |
| `device` / `room` | Hardware role and representative acoustic condition. |
| `capture_seconds` / `prompt` | Reproduction instruction for the capture helper. |
| `reference` | Expected transcript, or empty for no-speech. |
| `speech_spans` | Reserved `[startSeconds, endSeconds]` annotations for later endpoint studies. The MVP result does not depend on them because accepted audio is never trimmed. |

Private WAVs remain uncommitted. `results/raw.*`, no-gate transcripts, review HTML, frame probabilities, timelines, and per-fixture decisions are gitignored. Only aggregate metrics and conclusions are published.

## Run the real bakeoff

```sh
./scripts/run.py fixtures/local-manifest.json --output results/raw.json
./scripts/make-review.py results/raw.json fixtures/local-manifest.json --output results/review.html
open results/review.html
# After human review, publish aggregates and conclusions only:
./scripts/publish-results.py results/raw.json results/final.json
```

`run.py` performs one Silero inference per fixture, then applies a small segmentation sweep without re-running the model:

- probability thresholds `0.35`, `0.50`, `0.65`;
- minimum speech durations `96`, `160`, `250` ms;
- upstream defaults are therefore included exactly (`0.50` / `250` ms; upstream's 100 ms minimum silence and 30 ms speech padding remain unchanged).

It selects settings on calibration by minimizing false rejects first, false accepts second, and distance from upstream defaults third. Holdout data never participates in selection.

The runner also compares whole-clip and 100 ms framed RMS at `0.001`, `0.005`, `0.010`, and `0.020`; runs every clip through FluidAudio with no gate to expose hallucinations; derives the gated result without decoding rejected clips; records decoder calls skipped, VAD and decoder latency, raw probabilities, segments, transcripts, and errors; and emits JSON plus a compact Markdown table.

For framing, it replays each fixture through capture buffers of 73, 511, 128, 2048, 17, 960, 333, 4096, and 255 samples. An accumulator sends only complete 512-sample Silero windows, with exactly one zero-padded tail at release. The streamed probabilities must exactly match one-shot inference. Never pass each arbitrary callback tail directly to Silero: whisper.cpp pads every partial call, so doing that manufactures silence and makes classification callback-size-dependent.

The HTML review keeps recordings local and presents an audio control, selected classification, no-gate transcript, segments, and a frame-probability timeline for every fixture. Thurston—not the script—judges mistaken labels, clipped boundaries, transcript changes, and headphone isolation.

## Acceptance bar

The MVP setting is acceptable only when the separately reported holdout preserves all of these:

- no final nonempty transcript for any no-speech hold;
- no rejected quiet, whispered, clipped, or short speech fixture;
- VAD median runtime within the accepted 15 ms absolute release-latency budget; the original provisional 10% ratio remains reported separately;
- irregular capture-buffer replay produces the same probabilities as one-shot framing;
- accepted audio reaches FluidAudio unchanged, including quiet spans around 15-second boundaries.

Nearby intelligible open-speaker speech remains a general acoustic-VAD ambiguity, but it is not representative of this headphone-only environment. Do not add a transcript blacklist for it.

## Results and verdict

The real corpus contains 34 fixtures: 14 calibration and 20 holdout, split across the MacBook microphone and Shure MV7. Calibration selected Silero threshold `0.35` with upstream's `250 ms` minimum speech. This is the highest tested threshold with zero calibration false rejects. Upstream `0.50` rejected the Shure whispered calibration fixture; `0.35` preserved it while all calibration and holdout no-speech recordings remained far below the speech boundary.

Thurston listened to the recordings and accepted the classifications, the absence of gate-induced clipping, and unchanged long-form stitching. PCM inspection found no saturated samples; the digital character he heard is therefore capture/playback behavior, not waveform clipping or gate trimming. The MVP gate passes complete accepted audio, so measured gate-induced onset clipping is exactly `0 ms`.

Irregular capture-buffer replay matched one-shot Silero probabilities exactly. Under the deliberately broad buffer sequence, future endpoint confirmation measured `186 ms` median and `376 ms` maximum after the last above-threshold frame; that includes upstream's 100 ms silence requirement plus frame and callback scheduling. This is endpointing evidence only—the MVP still ends on key release.

Median VAD inference was `10.1 ms`; median FluidAudio transcription was `59.7 ms`. The provisional ratio check failed at roughly 17%, but Thurston accepted the 10.1 ms absolute addition as negligible for release-to-text feel. The durable MVP budget is therefore 15 ms absolute, while the ratio remains visible in machine results rather than being rewritten into a pass.

FluidAudio returned empty transcripts for the accepted built-in-microphone “yes” and “no” fixtures. Silero probabilities were `1.000` and `0.999`, so this is not a silence-gate false reject. The paired Shure “yes” and “no” fixtures transcribed correctly, which argues against a universal Parakeet single-word limit.

FluidAudio did have a known integration defect: before [FluidAudio #531](https://github.com/FluidInference/FluidAudio/pull/531), `AsrManager` rejected every recording shorter than one second before Parakeet ran—explicitly including 500–700 ms words such as “yes,” “no,” and “stop.” The selected v0.15.5 contains the fix and admits recordings of at least 300 ms. These built-in-microphone clips were 1.5 and 1.2 seconds, reached inference, and returned empty rather than `invalidAudioData`, so they are not that known bug. No upstream report or real-model regression test was found establishing that Parakeet v2 itself generally loses sub-second words. An all-blank TDT decode can mechanically return empty, but the cause here remains unproven. Production regression tests must distinguish `gate rejected`, `engine rejected audio`, and `engine accepted audio but returned empty`.

| Gate | Calibration false accepts / rejects | Holdout false accepts / rejects | No-speech hallucinations delivered | Decoder calls skipped | Role |
| --- | ---: | ---: | ---: | ---: | --- |
| No gate | 6 / 0 by definition | 8 / 0 by definition | 0 | 0 | Hallucination control |
| Whole-clip RMS `0.001` | 3 / 1 | 5 / 0 | 0 after gate | 7 | Baseline only |
| 100 ms framed RMS `0.001` | 6 / 0 | 6 / 0 | 0 after gate | 2 | Baseline only |
| Silero upstream `0.50` / `250 ms` | 0 / 1 | 0 / 0 | 0 | 15 | Rejects the Shure calibration whisper |
| **Silero selected `0.35` / `250 ms`** | **0 / 0** | **0 / 0** | **0** | **14** | **MVP recommendation** |

Aggregate machine-readable metrics and conclusions are in [`results/final.json`](results/final.json); the aggregate report is [`results/final.md`](results/final.md). Private WAVs and all individual-run evidence remain gitignored; the committed manifest and harness reproduce the experiment when those local fixtures are available.
