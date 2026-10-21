# Voz: corpus replay and license audit

Measured 2026-09-09. [Powered by Desert Ant Labs](https://desertant.com). Voz derives from [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), CC-BY-4.0; Desert Ant converted, 6-bit-palettized and repackaged it for Core ML.

## Recommendation

Keep the shipping FluidAudio + Parakeet v2. Neither tested v3 path earns replacement on this corpus. Voz saves about 3 ms on short utterances but triples the word errors, and its long-form median is 98 ms slower than the incumbent. Its compact artifact and buffer/dispatch techniques merit independent investigation, not an engine switch. Adoption remains [ticket 15](../../tickets/15-second-engine.md)'s decision.

The licensing result needs precision: **the license prohibits disabling usage reporting, but this pinned Voz implementation never invokes the SDK's telemetry client.** We found no usage egress in its execution path, rather than a mandatory request that actually fired. This implementation omission is not contractual permission to suppress reporting later. Obtain explicit controlled-network terms before treating Voz as eligible for the installed artifact.

## Main comparison

All local results use the existing built-in-microphone recordings, one speaker. Stage 1 has only 205 words; one error changes WER by 0.49 percentage points. These are point measurements, not a statistically established ordering of close engines.

| Engine | Stage 1 WER | Warm median | Evidence |
| --- | ---: | ---: | --- |
| ElevenLabs Scribe v2, hosted | 0.98% | 638 ms | [existing run](../43-dictation-corpus/results/elevenlabs-scribe-v2/) |
| FluidAudio + Parakeet v2, shipping | 1.95%, 4 errors | 55 ms | [existing run](../43-dictation-corpus/results/built-in/) |
| FluidAudio + Parakeet v3 | 2.93%, 6 errors | 55.4 ms | [new run](../43-dictation-corpus/results/fluid-parakeet-v3/) |
| Cohere Transcribe, mlx-audio | 3.41% | 97 ms | [existing run](../43-dictation-corpus/results/cohere-transcribe/) |
| Groq whisper-large-v3-turbo, hosted | 3.41% | 523 ms | [existing run](../43-dictation-corpus/results/groq-whisper-large-v3-turbo/) |
| whisper large-v3-turbo, local | 3.90% | 487 ms | [existing run](../43-dictation-corpus/results/whisper-large-v3-turbo/) |
| whisper medium.en, local | 3.90% | 422 ms | [existing run](../43-dictation-corpus/results/whisper-medium-en/) |
| Gemini 3.6 Flash, hosted engine | 4.39% | 2339 ms | [existing run](../43-dictation-corpus/results/gemini-transcribe/) |
| Voz, unmodified samples | 5.85%, 12 errors | 52.5 ms | [new run](../43-dictation-corpus/results/voz/) |

Hosted timing includes network round trips. The old local runs have their own timing caveats: Cohere includes WAV decoding; whisper reports internal transcription time excluding process/load overhead. Voz and the new FluidAudio arm both time samples-in-hand through final text, excluding WAV I/O, load, and one warmup.

| Stage | Shipping v2 | FluidAudio v3 | Voz |
| --- | --- | --- | --- |
| Stage 1 long-form, 6 / 567 words | 8.11%, 119.1 ms | 13.05%, 131.3 ms | 8.64%, 217.1 ms |
| Stage 2 bare exact `wants` | 5/18, 55.5 ms | 3/18, 56.3 ms | 2/18, 50.7 ms |
| Stage 2 exact traps bitten | 0/8 | 0/8 | 0/8 |
| Stage 2 holdout bare exact `wants` | 5/10, 56.9 ms | 2/10 | 3/10, 53.2 ms |
| Stage 2 holdout exact traps bitten | 0/6 | 0/6 | 0/6 |
| Stage 3 raw | existing input | 27 transcripts, 57.8 ms median | 27 transcripts, 57.2 ms median |

Incumbent long-form already exists in [prompt-tuning-r3](../43-dictation-corpus/results/prompt-tuning-r3/stage1-longform-score.json), so no incumbent rebuild or rerun was necessary. Short-form/stage-2 incumbent is `results/built-in`; holdout is `results/holdout`. Long-form recordings are in `recordings/stage1-longform`, without a `-built-in` suffix. No substitute audio was used.

The long-form scorer has two important limitations. It turns curly apostrophes into spaces while retaining straight apostrophes, so reference `I’ll` and transcript `I'll` receive different tokenization. All three engines also emit spoken-delimiter-shaped text such as `quote`, `end quote`, and `parentheses` absent from the literary references. These recordings need verbatim adjudication before their WER can isolate stitching accuracy. We left both references and scoring unchanged. FluidAudio v3 nevertheless has a concrete omission: `longform-02` loses the passage from “Well, thought Alice” through “How brave they'll all think me at home” that the incumbent retains. Its 36 deletions versus v2's 9 are not just punctuation normalization. Voz has 10 deletions, 13 substitutions and 26 insertions.

### Short-clip truncation diagnostic

Voz shares the incumbent's colonel→kernel, cash→cache and daemon→demon errors; it fixes week/weak but adds their→the, brake→break, site→sight and steady→study. Five additional failures are clipped final words: `background`→`backgro`, `dish`→`dis`, `bowls`→`bowl`, `truck`→`tru`, `changes`→`chang`. This is not a language-selection result: the SDK has 25 supported languages, no language argument/detection and no English-only decode branch.

An explicitly separate [tail-padding probe](../43-dictation-corpus/results/voz/tail-padding-probe/) appends 500 ms of zero samples in memory after WAV decoding. **All five clipped endings recover**, reducing stage-1 WER from 5.85% to 3.41% at 55.3 ms median. Stage-2 exact recall rises from 2/18 to 3/18. This identifies endpoint sensitivity, not its exact internal cause; the unmodified primary run remains the rollup row. Padding does not recover the seven remaining confusable-word errors and is not an adoption recommendation. The diagnostic does not write or copy audio; `audioSeconds` stays the original recording duration.

The FluidAudio v3 arm makes attribution possible but not perfect: its v3 export and Voz's v3 export differ in precision, graph layout, decoder and window management. FluidAudio v3's 2.93% versus v2's 1.95% provides no evidence for a v3-weight advantage here. Voz's extra unpadded errors implicate this export/runtime path, and the padding result narrows five of them to endpoint handling. It would be wrong to ascribe every remaining difference to Swift dispatch alone.

Stage 3 is raw input, not a cleanup score. Voz retains the spelled letters in `polish-38` as `My last name is Sandberg, S A-N-D-B-E-R-G, period.`; FluidAudio v3 instead emits `My last name is Sandberg, SANDBERG.` It also returns `engineEmpty` for `polish-30`, the deliberately unfinished “and then we could maybe” phrase; 96 of its 97 entries produce text. Voz's `polish-11` drops the opening `quote` but retains `unquote, period.` The cleanup matrix can judge these once crossed with its prompts.

## Load, specialization and memory

| Measurement | Voz | FluidAudio v3 |
| --- | ---: | ---: |
| First measured load, downloaded files already local | 16,169.8 ms, fresh path | 14,743.7 ms, existing path |
| Same-path reload, separate process | 110.7 ms | 133.1 ms |
| Approximate one-time specialization overhead | 16,059.1 ms | not separately isolated |
| First-load process peak RSS | 506.3 MiB | 540.7 MiB |
| Cached replay load | 164.1 ms | first process above |
| One excluded first-recording warmup | 63.0 ms | 69.3 ms |
| Replay process peak RSS | 75.5 MiB | 540.7 MiB, includes first load |
| Cached load-only process peak RSS | 38.4 MiB | 38.3 MiB |

Voz's first-ever original-path load took 17,363.7 ms. That attempt then failed opening a misspelled warmup filename before any inference; [cold-run.log](../43-dictation-corpus/results/voz/cold-run.log) preserves it. The corrected main replay used the now-specialized path. To obtain a complete cold-load/RSS measurement we copied **weights only** to a fresh `/tmp/voz-cold-53` directory and ran load-only twice, recording [fresh-path-load.log](../43-dictation-corpus/results/voz/fresh-path-load.log) and [fresh-path-reload.log](../43-dictation-corpus/results/voz/fresh-path-reload.log). A later original-path warm-load-only process took 197.7 ms / 38.2 MiB. The 111–198 ms spread warns against treating one load value as a guarantee.

“Specialization” here is the fresh-path minus same-path cached-load delta, consistent with the SDK's documented path-keyed Core ML/ANE cache, not an Instruments measurement separating compiler work from every other first-load cost. No model download is timed. `getrusage(RUSAGE_SELF).ru_maxrss` is bytes on Darwin; it includes CPU process memory but is not total accelerator-resident memory. In particular, the low warm RSS does not mean the 466 MiB model stopped occupying system memory. FluidAudio's replay high-water includes its slow first measured load and is not a comparable steady-state footprint. That arm reused an existing artifact path and did not clear earlier Core ML caches, so its 14.7-second load is not a fresh-install specialization measurement.

## Pinned environment and artifacts

- Apple M4 Pro, 48 GiB; macOS 26.5.2 (25F84), Xcode 26.6 (17F113), Apple Swift 6.3.3 (`swiftlang-6.3.3.1.3`). Both executables built with `swift build -c release`.
- Voz SDK `a7a70e4e42958d6b9c1eb67402d84cb47a14c507`, reporting version 3.1.0. SwiftPM product `Voz`; no MLX or Xet trait. [Package.swift](Package.swift), [resolved pins](resolved-pins.json); the only other resolved package is swift-numerics 1.1.1, `0c0290ff6b24942dadb83a929ffaaa1481df04a2`.
- Model `desert-ant-labs/voz`, SDK tag `v0.1.0` resolved to immutable HF commit `8e7ab8ca342c6bb00f9347a25e53fe44543b2a40`. [weights.json](weights.json) has every file's bytes and SHA-256. Runtime files total **488,794,892 bytes / 466.15 MiB**; all 17 downloaded files including README/notices total 488,797,301 bytes. The “467 MB” description is approximate and mixes unit conventions. FluidAudio's measured v3 files total 483,105,645 bytes / 460.73 MiB, so Voz does not save disk space over that arm.
- Encoder weight: 460,717,376 bytes, SHA-256 `afdc12527e014af6a92f8ca9f62884cd31e5e4ad9835e8bf54f5cf7605259179`; decoder weight: 15,831,820 bytes, `78a83d56efcd294e598e159916b3f0a3dd6d9cc394ce7c58ca806d54dbb37580`; embedding: 10,487,040 bytes, `3173388aaf6b5b4ae292d8777940bb8fb5c7c02e30adf708b9dde4d909c2000f`. The full manifest also covers the mel weight and compiled graph metadata.
- Model `meta.json`: 16 kHz, 15-second / 240,000-sample windows, float16 I/O, 8192-token vocabulary, five TDT durations, decode width 8. Decoder graph has 16 lanes. **No resampling was required.** Harness validates 16 kHz mono WAVs and contains an AVAudioConverter path for a different `voz.sampleRate`; that unused path was not benchmarked.
- Default SDK cache is `~/Library/Caches/desert-ant-models/desert-ant-labs/voz/v0.1.0/`, from `ModelStore.location` and `FoundationFileSystem.defaultCacheRoot`. This spike explicitly adopts pinned files at `~/.cache/miniwhisper-research/voz/8e7ab8ca342c6bb00f9347a25e53fe44543b2a40/` through `Voz(directory:)`. It does not depend on a mutable tag at replay time.
- [inputs.json](inputs.json) hashes all 97 recording inputs and five stage files without copying audio. Production targets, `Packages/`, the map, and git staging remain untouched.

## Reproduce

From this directory:

```sh
bash scripts/setup.sh
bash scripts/run.sh
```

Setup downloads at the immutable model commit, verifies the retained hashes and builds the pinned SDK. The executable loads one Voz actor, reads the first stage-1 WAV for one excluded warmup, then replays five stages serially into `results/voz`. Each line has exactly `{id, transcript, latencyMs, outcome, audioSeconds}`; errors abort instead of becoming successful records. There is no VAD, vocabulary, language setting or cleanup. Files decode before timing; resampling, if needed, also precedes timing. The two scored stages use `score_corpus.py` unchanged, with `sweep` for bare-only stage 2. Full JSON reports include case-folded recall/traps alongside the exact headlines.

The scripts overwrite only this run's output, so preserve results separately before rerunning if comparing dates. A cache-hot run will not reproduce the initial specialization tax. To measure it without deleting system caches:

```sh
model="$HOME/.cache/miniwhisper-research/voz/8e7ab8ca342c6bb00f9347a25e53fe44543b2a40"
fresh="$(mktemp -d /tmp/voz-cold.XXXXXX)"
ditto "$model" "$fresh"
DAL_HTTP_DEBUG=1 .build/release/VozReplay "$fresh" --load-only
DAL_HTTP_DEBUG=1 .build/release/VozReplay "$fresh" --load-only
```

The optional endpoint diagnostic is separate from the main run:

```sh
DAL_HTTP_DEBUG=1 .build/release/VozReplay "$model" ../43-dictation-corpus \
  ../43-dictation-corpus/results/voz/tail-padding-probe --pad-tail-500ms
python3 ../43-dictation-corpus/score_corpus.py \
  --report ../43-dictation-corpus/results/voz/tail-padding-probe/stage1-score.json \
  stage1 ../43-dictation-corpus/stage1-intelligibility.jsonl \
  ../43-dictation-corpus/results/voz/tail-padding-probe/stage1.jsonl
```

After the optional diagnostic, `python3 scripts/validate.py` checks all input hashes, ordered stage IDs, exact output fields, WAV format/duration and outcome consistency. [validation.json](../43-dictation-corpus/results/voz/validation.json) records 97/97 successful text outputs for both unpadded and padded runs. The final release build completed without warnings, and setup reverified every downloaded file hash after inference.

The independent FluidAudio v3 harness and reproduce commands are in the [FluidAudio v3 run README](../43-dictation-corpus/results/fluid-parakeet-v3/README.md). `asr-replay --model-root` cannot select v3: the production backend explicitly selects v2. The disposable harness instead calls FluidAudio's public v3 loader against its already-downloaded pinned snapshot. No production adaptation was necessary.

## License and egress

Primary terms: [Desert Ant Labs Source-Available License 1.0](https://license.desertant.com/1.0), dated 3 July 2026. It is not open source. Free use is **below** 100,000 monthly active devices independently per model and OS-family platform, aggregated across common-control apps. At the threshold a commercial license is required. Section 9 requires a discoverable credit naming Desert Ant Labs, linked to `https://desertant.com` in a digital About/Settings screen; exact wording is flexible, and it need not accompany every result. Retain delivered license/copyright notices. The [pinned weight notices](https://huggingface.co/desert-ant-labs/voz/blob/8e7ab8ca342c6bb00f9347a25e53fe44543b2a40/THIRD_PARTY_NOTICES.md) explicitly preserve NVIDIA's CC-BY-4.0 and identify the conversion changes.

Section 6 prohibits tampering with telemetry or interfering with reporting; section 7 describes the generated MAD identifier and says inputs, outputs and user content are not sent. The linked generic SDK code implements more detail:

| Question | Pinned shared SDK implementation |
| --- | --- |
| Host / request | HTTPS POST `https://platform.desertant.ai/api/v1/ingest`, JSON body, fire-and-forget; errors swallowed, no persisted outbox/retry |
| Body | required `platform`, `sdk: {name, version}`, `sentAt`, `events`; optional `key`, `app: {id}` |
| Event | `name: "load"`, `deviceId`; optional positive `callCount`, `timestamp`, string-valued `context` |
| App identity | bundle identifier, falling back to process name; optional publishable key is in the JSON body |
| Device identity | generated random UUID v4 persisted as `ai.desertant.usage.deviceId` in the host's `UserDefaults.standard`; re-emit/count state is namespaced by app/key and device ID |
| Nominal cadence | native 24-hour active window, server delta events coalesced hourly; generic inference calls start/recordCall, then flush after 3-second idle or on lifecycle/deinit; macOS is encoded as `server`, despite the license treating macOS as its own platform |
| User content | no audio/transcript field in the wire schema |
| Debugging | `DAL_HTTP_DEBUG=1` prints URL/body/response; an endpoint override and CI disable switch exist, but disabling reporting is not a permitted shipped-product workaround |

**Voz does not instantiate that machinery.** Its initializer resolves files and constructs `Assets`/`Pipeline`; `transcribe(samples:)` calls the pipeline directly. No `UsageClient`, usage tracker, `start`, `recordCall`, or flush call exists in `Sources/Voz`. The model catalog exposes SDK identity but resolving files does not start telemetry. Merely linking the shared module does not instantiate its clients.

Every recorded Voz invocation enabled `DAL_HTTP_DEBUG=1`; none printed an ingest URL/body. Source inspection explains the absence. This is source-level plus SDK-debug evidence, **not packet-capture proof of machine-wide zero traffic**. Downloading still contacts Hugging Face during setup; adopted complete local files require no model download during replay. We did not disable reporting or reroute it to a mock endpoint.

The discrepancy matters more than a superficial “offline” label: today's pin has no usage request, but its license reserves mandatory reporting and future revisions may wire the omitted calls. Recommend asking Desert Ant for an explicit offline/controlled-network agreement and clarification of this pin, not silently depending on the omission. SDK-derived code remains under its license; do not copy it into the Apache-licensed incumbent.

## Can FluidAudio adopt the speed techniques?

The general ideas are implementable independently. Voz allocates float16 `MLMultiArray` inputs, outputs and recurrent state once, reuses feature providers, binds `MLPredictionOptions.outputBackings`, and memory-maps the embedding lookup table. An actor serializes the mutable pipeline. It batches independent window decode states into 16 lanes so one Core ML dispatch advances several sequences, admitting another window when a lane finishes. Groups of up to 64 encoded windows bound projection memory. Its compiled `.mlmodelc` files have stable paths, avoiding per-load temporary-path specialization.

These are not free improvements from changing one wrapper. Buffer reuse/output backings use public Apple APIs; FluidAudio already [preallocates TDT v3 joint inputs and providers](https://github.com/FluidInference/FluidAudio/blob/19600a485baa4998812e4654b70d2bab8f2c9949/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT/Decoder/TdtDecoderV3.swift#L169-L180), reuses decoder state and caches compiled models, so profile what still allocates rather than assuming it does none of this. Its separate [Nemotron runtime already uses output backings](https://github.com/FluidInference/FluidAudio/blob/19600a485baa4998812e4654b70d2bab8f2c9949/Sources/FluidAudio/ASR/Parakeet/Streaming/Nemotron/StreamingNemotronMultilingualAsrManager.swift#L713), providing an independently licensed in-repository precedent. Voz's fused, float16, lane-shaped decoder requires a compatible export; FluidAudio's batch-one separate decoder/joint artifact cannot acquire 16 independent lanes merely by setting `outputBackings`. Independent re-export and correctness tests would be required. The measured short-utterance result is only about 3 ms faster than FluidAudio v3, while long-form is slower, so this corpus does not establish a throughput payoff worth a rewrite.

Do not translate Voz's buffers, index layouts, lane scheduler, seam repair or retry logic into FluidAudio. Derive an implementation from public Core ML APIs and Parakeet's architecture, with fresh structures/tests and legal review of any licensing/patent constraints. This report identifies techniques to profile, not legal clearance to port source.

### Source anchors

All SDK links are pinned to the measured revision:

- [Voz API](https://github.com/Desert-Ant-Labs/desert-ant-core/blob/a7a70e4e42958d6b9c1eb67402d84cb47a14c507/Sources/Voz/Voz.swift#L102-L153): initialization and direct transcription; [catalog](https://github.com/Desert-Ant-Labs/desert-ant-core/blob/a7a70e4e42958d6b9c1eb67402d84cb47a14c507/Sources/Voz/Catalog.swift): model version, files, cache rationale.
- [Buffers](https://github.com/Desert-Ant-Labs/desert-ant-core/blob/a7a70e4e42958d6b9c1eb67402d84cb47a14c507/Sources/Voz/Buffers.swift), [assets](https://github.com/Desert-Ant-Labs/desert-ant-core/blob/a7a70e4e42958d6b9c1eb67402d84cb47a14c507/Sources/Voz/Assets.swift#L58-L84), [pipeline](https://github.com/Desert-Ant-Labs/desert-ant-core/blob/a7a70e4e42958d6b9c1eb67402d84cb47a14c507/Sources/Voz/Pipeline.swift#L58-L122): allocations/output backings; pipeline lines 180–290 cover lane decode and 470–505 cover batch encoding.
- [Usage transport](https://github.com/Desert-Ant-Labs/desert-ant-core/blob/a7a70e4e42958d6b9c1eb67402d84cb47a14c507/Sources/Usage/Transport.swift#L8-L47), [wire schema](https://github.com/Desert-Ant-Labs/desert-ant-core/blob/a7a70e4e42958d6b9c1eb67402d84cb47a14c507/Sources/Usage/Wire.swift#L48-L127), [storage](https://github.com/Desert-Ant-Labs/desert-ant-core/blob/a7a70e4e42958d6b9c1eb67402d84cb47a14c507/Sources/Usage/Storage.swift#L34-L109), [usage client](https://github.com/Desert-Ant-Labs/desert-ant-core/blob/a7a70e4e42958d6b9c1eb67402d84cb47a14c507/Sources/Usage/UsageClient.swift), [generic inference tracking](https://github.com/Desert-Ant-Labs/desert-ant-core/blob/a7a70e4e42958d6b9c1eb67402d84cb47a14c507/Sources/Inference/UsageTracking.swift): reporting machinery that Voz does not call.
- [Model-store path](https://github.com/Desert-Ant-Labs/desert-ant-core/blob/a7a70e4e42958d6b9c1eb67402d84cb47a14c507/Sources/ModelStore/ModelStore.swift#L35-L42), [platform cache root](https://github.com/Desert-Ant-Labs/desert-ant-core/blob/a7a70e4e42958d6b9c1eb67402d84cb47a14c507/Sources/ModelStore/FoundationBackend.swift#L187-L195).
