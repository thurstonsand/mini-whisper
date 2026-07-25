# Silence rejection bakeoff

Disposable macOS arm64 prototype for calibrating MiniWhisper's utterance gate. Its VAD regression target depends on the local production `ASREngine` package so framing and segmentation policy cannot drift.

## Shipping pipeline

```text
complete canonical 16 kHz mono Float32 recording
  ├─ empty → noSpeech
  └─ copy and zero-pad to ceil(sampleCount / 4096) × 4096
       └─ one FluidAudio VadManager.process call
            ├─ no qualifying segment → noSpeech
            └─ speech → original unpadded recording to resident AsrManager
```

Only the gate copy is padded. Segmentation receives the original sample count, so release padding cannot manufacture speech duration. Accepted audio is never trimmed, concatenated, padded, chunked, or stitched before ASR; FluidAudio alone owns its existing 15-second overlap/merge path.

## Why 4096 replaced 512

The original whisper.cpp bakeoff used genuine 512-sample Silero windows and one zero-padded release tail. FluidAudio v0.15.5's public `VadManager` cannot reproduce that geometry: its model requires 4096 new samples (256 ms), whole-input processing strides by 4096, and every partial `processChunk` is repeat-last-padded. Passing 512 samples through the public streaming API would therefore infer over 512 real samples plus 3584 repeated samples while reporting only 512 samples of progress.

Phase 4 amended the contract before deleting the corpus. MiniWhisper app-zero-pads the complete gate copy to a 4096 multiple before one whole-utterance call, which guarantees every internal chunk is exactly 4096 and prevents FluidAudio's repeat-last branch. Empty recordings do not manufacture a frame.

## Pins and test machine

- Test machine: Apple M4 Pro, macOS 26.5.2 (`25F84`), arm64.
- FluidAudio `v0.15.5`: `19600a485baa4998812e4654b70d2bab8f2c9949`.
- Silero VAD Core ML: `FluidInference/silero-vad-coreml@b419383c55c110e2c9271fa6ee0ea83d03c70d96`, `silero-vad-unified-256ms-v6.2.1.mlmodelc`.
- Parakeet TDT 0.6B v2 Core ML: `FluidInference/parakeet-tdt-0.6b-v2-coreml@ee09c569f73759e6d44c9bd16766f477b2b36d39`, English-only int8 encoder.
- VAD compute units: CPU-only, matching production calibration.
- ASR configuration: ordinary resident `AsrManager`, four parallel chunks, mel context enabled, no dual-decode arbitration.
- Capture devices: MacBook Pro Microphone and work-approved Shure MV7.
- Capture format: mono 16 kHz PCM16 WAV; production receives equivalent canonical Float32 samples from `AudioCapture`.

FluidAudio v0.15.5 hard-codes Hugging Face `main` in both model listing and resolve URLs. Setup and production therefore use immutable revision URLs. Production validates sizes and available LFS SHA-256 values, writes provenance, atomically promotes the complete cache, enables `ModelHub.offlineMode`, and only then loads local models. A missing or corrupt pin fails degraded; it never self-heals from mutable `main`.

## Setup and run

```sh
cd docs/wayfinding/finishing-mini-whisper/assets/10-silence-rejection-bakeoff
./scripts/setup.sh
./scripts/run.py fixtures/local-manifest.json --output results/fluid-vad-raw.json
./scripts/publish-results.py results/fluid-vad-raw.json results/fluid-vad-final.json
```

`setup.sh` resolves the production package's exact FluidAudio dependency, downloads both Core ML repositories at immutable revisions, builds the VAD and ASR harnesses, and generates synthetic fixtures. `SilenceBakeoffVad` imports `ASREngine` and calls `GateFraming.zeroPaddedCopy` plus each candidate `GateConfiguration.segmentationConfiguration`; these regressions therefore exercise production gate construction rather than a restated harness copy. Raw output contains private probabilities, transcripts, and fixture decisions and is ignored. Only [`results/fluid-vad-final.json`](results/fluid-vad-final.json) and [`results/fluid-vad-final.md`](results/fluid-vad-final.md) are publishable.

The runner sweeps thresholds `0.35`, `0.40`, `0.45`, `0.50`, `0.55`, `0.65`, `0.75`, `0.85`, and `0.90` with minimum speech durations `0`, `150`, `250`, and `500 ms`. All five regenerable synthetic probes belong to calibration; synthetic data does not consume scarce field holdout slots. The runner combines them with the fixed real calibration split, selects the lowest threshold with zero calibration false accepts/rejects, then chooses the minimum-speech duration nearest FluidAudio's `150 ms` default. The 20-fixture real holdout never participates in selection.

It asserts:

- zero false accepts and zero false rejects on both real splits;
- warm corpus median at or below the accepted 15 ms absolute VAD budget;
- every nonempty gate input is an exact 4096-sample multiple;
- accepted original audio remains unchanged.

Five generated calibration no-speech fixtures exercise silence, low noise, impulses, and a pure tone. Threshold `0.85` accepted the labeled tone at probability `0.89160156`; because it is a supplied no-speech probe, that is a false accept. Threshold `0.90` rejects all five without losing any real calibration speech. No frequency blacklist is needed.

## Private fixture capture

`fixtures/local-manifest.json` is committed, but `fixtures/local/` is ignored and normally absent. It defines 34 recordings fixed before tuning: 14 calibration and 20 holdout, including room tone, lone taps, keyboard/mouse noise, fan/HVAC, headphone leakage, ordinary/quiet/whispered speech, short words, clipped boundaries, leading/trailing silence, and long dictation crossing FluidAudio's 15-second boundaries.

List current AVFoundation indexes immediately before capture; indexes are not stable across reconnects:

```sh
ffmpeg -f avfoundation -list_devices true -i ''
./scripts/capture-corpus.py --built-in <index> --work-headset <index>
```

The helper does not overwrite existing files, so an interrupted capture can resume. Use the MacBook microphone and the currently approved work microphone, record only the inert prompts in the manifest, listen to every result, and fill long-fixture references with the non-private paragraph actually spoken. Then run the complete calibration and ASR regression before accepting a FluidAudio/model change.

Future re-record procedure:

1. Record all 34 entries without changing their preassigned split.
2. Validate every WAV is mono 16 kHz PCM16 and every manifest entry is present.
3. Run the VAD harness and inspect the raw confusion matrix; selection uses calibration only.
4. Require zero false accepts/rejects on calibration and holdout plus the 15 ms warm-median budget.
5. Run Parakeet over accepted originals and the engine-bakeoff long corpus; inspect errors, empty short words, reference WER, and all 15-second boundary fixtures.
6. Publish aggregate-only results, then delete every personal/generated WAV and all raw output again.

## Recalibration verdict

The combined real-plus-synthetic calibration selected threshold `0.90`, minimum speech `150 ms`: the lowest swept threshold rejecting every supplied calibration no-speech probe while preserving every calibration speech fixture. It produced `0 / 0` false accepts/rejects on the 14 real calibration fixtures, rejected all `5 / 5` synthetic calibration fixtures, and then produced `0 / 0` on the untouched 20-fixture real holdout. The strongest real holdout no-speech probability was about `0.489`; the weakest real calibration speech reached about `0.971`.

Warm wall VAD median was `13.782 ms`; model-reported median was `13.502 ms`. The cold/maximum fixture took `150.540 ms`, so setup/prewarm remains mandatory while the warm release path passes the accepted `15 ms` budget. Maximum release zero padding was 4011 samples. All internal chunks were exact 4096-sample frames.

The no-gate ASR regression retained the known distinction: built-in “yes” and “no” speech reached VAD but returned empty Parakeet transcripts, while the two 0.2–0.3-second lone-tap clips produced `invalidAudioData` when deliberately sent to ASR without the gate. Production reports gate rejection, accepted engine-empty, and engine failure separately.

A separate 24-fixture engine corpus (11.7 minutes, up to 93.5 seconds) completed with no ASR errors or empty transcripts, including all 15 long/boundary recordings, at 3.21% corpus WER. This confirms MiniWhisper still passes accepted originals into FluidAudio's established long-form merger.
