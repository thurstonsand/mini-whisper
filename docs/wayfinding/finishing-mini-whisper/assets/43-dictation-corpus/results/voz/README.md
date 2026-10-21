# Voz, built-in microphone

The same corpus recordings as the shipping engine, replayed through Desert Ant Labs' Voz Swift SDK. [Powered by Desert Ant Labs](https://desertant.com). Model: NVIDIA Parakeet TDT 0.6B v3, converted and 6-bit-palettized for Core ML by Desert Ant; NVIDIA CC-BY-4.0 and Desert Ant Source-Available License 1.0 both apply.

Measured 2026-09-09 on Apple M4 Pro / 48 GiB, macOS 26.5.2 (25F84), Xcode 26.6, Swift 6.3.3. Release SwiftPM build. SDK revision `a7a70e4e42958d6b9c1eb67402d84cb47a14c507` (3.1.0), HF `desert-ant-labs/voz` revision `8e7ab8ca342c6bb00f9347a25e53fe44543b2a40`. Runtime files: 488,794,892 bytes / 466.15 MiB, all hashes in the [spike](../../../53-voz-engine-spike/weights.json). Weights stay outside the repository under `~/.cache/miniwhisper-research/voz/<revision>/`.

| file | what it is |
| --- | --- |
| `stage1.jsonl`, `stage1-score.json` | short-form raw output and WER detail |
| `stage1-longform.jsonl`, `stage1-longform-score.json` | six long recordings and unchanged corpus WER |
| `stage2-bare.jsonl`, `stage2-score.json` | bare dictionary output; scored beside existing shipping-v2 bare |
| `stage2-holdout-bare.jsonl`, `stage2-holdout-score.json` | same comparison on recorded dictionary holdout |
| `stage3-raw.jsonl` | 27 raw transcripts for the cleanup matrix, not a cleanup score |
| `run.log` | load, excluded warmup, per-entry timings and `getrusage` peak RSS |
| `fresh-path-load.log`, `fresh-path-reload.log` | separate fresh-path and cached load-only measurements |
| `warm-load.log` | later original-path load-only measurement |
| `cold-run.log` | first-ever load, followed by a warmup-path typo; no inference ran |
| `tail-padding-probe/`, `tail-padding-probe.log` | separate diagnostic with 500 ms zeros appended in memory |
| `validation.json` | 97 ordered IDs, exact JSONL fields, recording hashes/format/duration verified in both runs |

## Headline

| stage | result |
| --- | --- |
| 1 | **5.85% WER**, 12S 0D 0I / 205 words; 13/25 clean; **52.5 ms median**, 52.3 ms mean, 60.9 ms max |
| 1 long-form | **8.64% WER**, 13S 10D 26I / 567 words; 217.1 ms median |
| 2 bare | **2/18 exact wants**, 4/18 case-folded; 0/8 exact traps, 2/8 case-folded; 50.7 ms median |
| 2 holdout bare | **3/10 exact wants**, 4/10 case-folded; 0/6 exact traps, 1/6 case-folded; 53.2 ms median |
| 3 raw | 27 text outputs, 57.2 ms median; no cleanup or scoring |

The shipping engine is 1.95% / 55 ms on stage 1; the new [FluidAudio v3 arm](../fluid-parakeet-v3/) is 2.93% / 55.4 ms. Voz's roughly 3 ms advantage does not pay for eight extra errors versus the incumbent. Stage-2 bare recall also trails shipping v2's 5/18 and holdout 5/10.

Five of Voz's short-form errors truncate the last word: `backgro`, `dis`, `bowl`, `tru`, `chang`. Appending 500 ms of zero samples recovers all five, scoring **3.41% / 55.3 ms** in the diagnostic, not the rollup. The remaining seven are confusable-word errors, including the incumbent's colonel/kernel, cash/cache and daemon/demon. No SDK language setting exists, and this run applies no English-specific treatment. No audio was written for the diagnostic, and its `audioSeconds` retains the original duration.

The incumbent's [existing long-form run](../prompt-tuning-r3/stage1-longform-score.json) scores 8.11% / 119.1 ms; FluidAudio v3 scores 13.05% / 131.3 ms and drops a passage in `longform-02`. All long-form WERs also contain reference defects: curly/straight apostrophes normalize differently, and both old and new outputs contain delimiter-shaped speech absent from the literary reference. Do not interpret those WERs as pure stitching error rates. No references or normalizer were changed.

Voz retains spelled letters in `polish-38`: `My last name is Sandberg, S A-N-D-B-E-R-G, period.` Its `polish-11` is `She said, It ships tonight, unquote, period.` These are cleanup inputs, not evidence that the final intended text was delivered.

## Timing and reproduction

The [disposable harness](../../../53-voz-engine-spike/) loads Voz once, does one excluded transcription of `harvard-01-01`, then replays all five stages. Timings start with float samples already loaded and end at final `result.text`; WAV I/O and any conversion are excluded. `voz.sampleRate` is 16 kHz, matching the mono corpus: **no resampling**. No VAD, dictionary, language argument or cleanup. Every entry returned `transcript` in the main run.

From the spike directory:

```sh
bash scripts/setup.sh
bash scripts/run.sh
# After running the optional tail-padding diagnostic documented in the spike:
python3 scripts/validate.py
```

Fresh-path load: **16,169.8 ms**, followed by **110.7 ms** same-path reload in another process. Their **16,059.1 ms** difference estimates one-time ANE specialization, rather than isolating it with Instruments. The main cache-hot replay loaded in 164.1 ms, warmed up in 63.0 ms, and reached **75.5 MiB peak process RSS**. Fresh-path load peaked at **506.3 MiB**; cached load-only at 38.4 MiB. Darwin `ru_maxrss` does not count all accelerator/system model memory. Downloads are excluded. See the spike for the preserved first-attempt typo and all load evidence.

## Licensing and egress

The license is source-available, not open source. It requires discoverable Desert Ant attribution linked to its site, preserves Parakeet CC-BY-4.0, and forbids interfering with its usage telemetry. The shared SDK's nominal telemetry is a generated persistent device UUID, app/SDK identity and call counts sent to `https://platform.desertant.ai/api/v1/ingest`, not audio or transcript text.

**This pinned Voz path does not instantiate or invoke the Usage client.** Its direct Core ML initializer/transcription path contains no tracking calls, and every recorded run with `DAL_HTTP_DEBUG=1` emitted no ingest log. This is source inspection plus SDK-debug evidence, not packet-capture proof. We disabled nothing. Treat the implementation omission and the contractual reporting requirement separately; controlled-network adoption needs explicit terms, not reliance on a missing call. Full source anchors, payload/cadence, runtime analysis and recommendation are in the [spike findings](../../../53-voz-engine-spike/README.md).
