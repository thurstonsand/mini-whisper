# Cohere Transcribe: precedent, prototype, integration

## Verdict

**Exclude the current Cohere lane from MiniWhisper.** Cohere Transcribe is a real local-engine candidate, not a cloud-only service, so the cloud-STT scope boundary does not rule out the model itself. The candidate still loses on the evidence available here: Whispering provides no shipped precedent, the practical FluidAudio/Core ML artifact is 2.19 GB and has contradictory license metadata, and an auxiliary 27-file local run measured 532 ms warm p50, 1,599 ms p95, 2,298 ms worst case, and 12,135 MiB peak process RSS. The incumbent's controlled-corpus results are 98 ms p50, 222 ms p95, and 170 MiB later-process RSS.

The required quality comparison could not be completed. The prior bakeoff's manifest and aggregate results remain, but all 24 selected private WAVs are gone from both the bakeoff fixture directory and Aqua Voice's retained-audio directory. New recordings were not substituted: that would create a new corpus while presenting it as the old controlled comparison. Revisit only with a materially lighter/faster local artifact and a restored or deliberately re-baselined private corpus.

## Phase 1: what it is

[Cohere Transcribe `cohere-transcribe-03-2026`](https://docs.cohere.com/docs/transcribe) is a 2-billion-parameter, audio-in/text-out Fast-Conformer encoder-decoder [released on March 26, 2026](https://cohere.com/blog/transcribe). More than 90% of its parameters are in the encoder; its small autoregressive decoder is intended to preserve throughput. It is an open-weight model available for local inference, not merely a name for Cohere's hosted service.

| Property | Finding |
| --- | --- |
| Weights and license | [Downloadable weights](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026), 2B BF16 parameters, Apache-2.0. Hugging Face requires accepting the repository's contact-sharing gate for the upstream files. |
| Architecture | Fast-Conformer encoder plus 8-layer Transformer decoder; 16 kHz waveform input. The official processor chunks long audio. |
| Languages | 14: English, German, French, Italian, Spanish, Portuguese, Greek, Dutch, Polish, Vietnamese, Mandarin Chinese, Arabic, Japanese, and Korean. The caller must specify one; there is no automatic language detection and code-switching is inconsistent. |
| Output | Final text with punctuation by default. No timestamps or speaker diarization. The model card warns that non-speech can hallucinate, so MiniWhisper's silence gate remains required. |
| Local runtimes | Officially documented `transformers` offline inference and vLLM serving, plus ecosystem support for MLX on Apple Silicon, Rust, and WebGPU. Pinned FluidAudio v0.15.5 already contains a beta `CoherePipeline`, so the most direct Swift prototype needs no new runtime dependency. |
| Streaming | No genuine streaming contract was found. Cohere exposes batch file transcription; the local reference path chunks complete audio, and FluidAudio slides fixed windows then returns merged final text. This is not incremental decoder-state streaming. |
| Accuracy posture | Cohere reports 5.42% average English WER on the Hugging Face Open ASR Leaderboard and up to 3× the offline throughput of similarly sized ASR models. Those are throughput/benchmark claims, not hold-release latency measurements. |
| Local footprint | The tested FluidAudio artifact uses a 1.88 GB INT8 Core ML encoder and a 304 MB static-shape decoder; the downloaded snapshot occupies 2,189,520,896 bytes. Its encoder processes a fixed 35-second mel shape even for short utterances. |

### Hosted access is optional and still out of scope

Cohere also exposes [`POST https://api.cohere.com/v2/audio/transcriptions`](https://docs.cohere.com/reference/create-audio-transcription), a multipart batch upload accepting files up to 25 MB. The request requires `model`, `language`, and `file` and returns one final `text` value. This is Cohere's own v2 API, not the sanctioned OpenAI-compatible gateway contract.

[Evaluation access is free but limited](https://docs.cohere.com/docs/rate-limits) to 5 audio-transcription requests per minute and 1,000 trial API calls per month. Production Audio Transcriptions access and [dedicated Model Vault pricing](https://docs.cohere.com/docs/model-vault) require sales contact; Cohere publishes no per-minute Transcribe price. A Model Vault is isolated, Cohere-managed infrastructure and can enable zero data retention, but Cohere still processes the input audio.

The [open weights can also be served through vLLM's OpenAI-shaped `/v1/audio/transcriptions` route](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026). That proves an administrator could build a compatible private service; it does not prove the workplace gateway currently fronts the model. No evidence was available that it does. In any case, MiniWhisper's map excludes cloud STT. Uploading the private dictation corpus to Cohere would cross the project's local-only privacy line, so no hosted prototype was attempted and no API key was requested.

### Licensing wrinkle in the practical Swift artifact

The upstream Cohere weights and FluidAudio source are Apache-2.0. The tested [`FluidInference/cohere-transcribe-03-2026-coreml`](https://huggingface.co/FluidInference/cohere-transcribe-03-2026-coreml) repository is internally inconsistent: its Hugging Face card metadata says Apache-2.0, while the README's license section says CC-BY-NC-4.0 and incorrectly claims that matches the Apache-2.0 upstream model. Shipping that conversion requires written clarification or a reproducible conversion from the upstream weights. Repository metadata is not enough when the repository contradicts itself.

## Phase 2: Whispering precedent

Whispering does not use Cohere Transcribe. There is therefore no version that added it and no Cohere endpoint or local runtime to identify.

The current upstream [provider registry](https://github.com/EpicenterHQ/epicenter/blob/main/apps/whispering/src/lib/services/transcription/providers.ts) exposes Epicenter, OpenAI, Groq, ElevenLabs, Deepgram, Mistral, local, and Speaches providers; its dispatch has no Cohere branch. [Issue #1658](https://github.com/EpicenterHQ/epicenter/issues/1658) is an open, uncommented request to add local Cohere Transcribe and states that the app does not include it.

The negative result also holds at the shipped-artifact boundary:

- [Whispering v7.11.0](https://github.com/EpicenterHQ/epicenter/releases/tag/v7.11.0), the current download advertised by Whispering's site, shipped on December 27, 2025, before Cohere Transcribe's March 2026 release. Its release notes enumerate local Parakeet, Moonshine, and whisper.cpp only.
- The v7.11.0 [registry](https://github.com/EpicenterHQ/epicenter/blob/v7.11.0/apps/whispering/src/lib/services/isomorphic/transcription/registry.ts) and [closed dispatch](https://github.com/EpicenterHQ/epicenter/blob/v7.11.0/apps/whispering/src/lib/query/isomorphic/transcription.ts) expose those three local engines plus Groq, OpenAI, ElevenLabs, Deepgram, Mistral, and Speaches. A configuration value cannot activate an unregistered implementation.
- An extracted official v7.11.0 amd64 Debian artifact contained neither `Cohere` nor `cohere-transcribe-03-2026` in its installed payload or printable application strings. Its SHA-256 was `c1fa1ffa19122fbe4e3a8f91a16c6b0f04c1e577f2403a207cf196edb228e28d`.
- Repository history contains no Cohere implementation commit or merged pull request. The open feature request is the only related record.

Whispering therefore supplies neither capability precedent nor evidence that a reviewed artifact can enable this model.

## Phase 3: local prototype

The disposable harness in this directory uses the same pinned FluidAudio v0.15.5 revision as the engine bakeoff and the immutable Core ML snapshot at `fccec19ecf93b40969d4888f27e10d714daeb3cf`. Setup verifies the two large weight files by byte count and SHA-256. It loads and decodes every source WAV before timing, loads the model once, performs one excluded warmup, times hold-release through final merged text, scores the same normalized word edit distance, and records macOS `getrusage` peak RSS. Audio, references, transcripts, and raw result JSON remain gitignored.

```sh
./scripts/setup.sh
./scripts/run.sh
```

`run.sh` deliberately fails before inference when any historical WAV is absent. On this machine it reports that 24 of 24 required private WAVs are missing.

### Controlled comparison

| Runtime | Corpus | Cached load | Warm p50 | Warm p95 | Worst | Corpus WER | Peak RSS |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| FluidAudio v0.15.5 + Parakeet v2 | Original 24 files / 700.4 s | 125 ms | 98 ms | 222 ms | not retained as a corpus statistic | 3.21% | 170 MiB |
| FluidAudio v0.15.5 + Cohere Transcribe | Same original corpus | — | — | — | — | — | — |

The Cohere row is intentionally empty. Prior transcripts cannot be used to synthesize the missing audio, and measuring a different corpus would not answer the ticket's comparison question.

### Auxiliary smoke test

To prove the harness and practical runtime path, it was separately run against 27 other private WAVs totaling 414.5 seconds. Their reference text was unavailable, so this is a latency/RSS smoke test only. No transcript or voice content is retained in the report.

| Cached load | Warm p50 | Warm p95 | Worst | Peak RSS | Inference failures |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 2,698 ms | 532 ms | 1,599 ms | 2,298 ms | 12,135 MiB | 0 / 27 |

These are not controlled head-to-head numbers, but the latency posture is already poor for hold-to-talk: the Cohere smoke p50 was 5.4× Parakeet's controlled p50 and its p95 was 7.2× Parakeet's controlled p95. Peak RSS is a process high-water mark and Core ML/ANE accounting is not fully comparable between models, but 12 GiB is large enough to be a product concern without pretending the accounting is exact. [FluidAudio's own Cohere notes](https://github.com/FluidInference/FluidAudio/blob/v0.15.5/Documentation/ASR/Cohere.md) explain the shape: every call processes a fixed 35-second encoder window, then audio over 35 seconds uses 5-second-overlap windows and sequential token merging.

## Integration and failure cost

The source integration is smaller than the operating cost. A local implementation would conform `CoherePipeline` to `ASREngine`, always pass an explicit language, use `transcribeLong`, add an engine setting, and teach model installation to download, verify, prewarm, and remove a 2.19 GB artifact. The existing silence gate remains in front. No production target needs to import the prototype.

The model would also complicate the fallback owned by [Second engine / fallback hardening](../../tickets/15-second-engine.md). Keeping Cohere and Parakeet resident together is unattractive after the observed Cohere high-water mark; loading the fallback only after failure adds seconds. That ticket would need an explicit residency policy, engine-specific deadlines, cancellation behavior, and one-delivery semantics before this engine could be considered reliable.

A hosted implementation is worse. The pill currently assumes local failures arrive promptly. Network STT adds upload progress, authentication, rate limits, gateway rejection, timeout, connection loss after the recording has left the machine, and an ambiguous response when cancellation races completion. A dead gateway mid-dictation has no answer unless the original captured audio remains available for a local retry. Second engine / fallback hardening would therefore need to classify retryable network failures, set a deadline, retain the utterance until delivery, fall back locally without double-pasting, and present a delayed/fallback notice. It would also have to decide whether to retry an upload at all. None of this makes hosted Cohere compatible with the current local-only line.

## Recommendation

Exclude this candidate rather than adopt it or leave an open-ended integration stake. Its attractive upstream quality and Apache-2.0 weights justify the completed prototype, but MiniWhisper cannot accept an engine without personal-corpus quality evidence, and the measured local tail, memory high-water mark, artifact size, conversion-license ambiguity, lack of streaming, and lack of Whispering precedent all point the same direction.

A future candidate can be evaluated afresh if it provides a clearly licensed Apple-local artifact, materially reduces fixed-window latency and memory, and the private corpus is restored or deliberately re-baselined across both engines. The hosted API is not that future candidate.

## Addendum: public accuracy evidence after the private-corpus loss

This addendum changes the disposition from categorical exclusion to **revisit later, while still excluding the current Core ML artifact from adoption**. The accuracy advantage is real on controlled public read-speech benchmarks and is large enough to keep the model family under consideration. It is smaller or absent on some more dictation-like evaluations, and no source found answers MiniWhisper's personal technical-dictation corpus.

### Standard benchmark evidence

The March 2026 [Open ASR Leaderboard paper](https://arxiv.org/html/2510.06961v4) is independent of Cohere and standardizes normalization and inference across models on A100 hardware. Its published short-form English table puts Cohere at 5.42% average WER and 525× RTFx, Parakeet v2 at 6.05% and 3,390×, and Parakeet v3 at 6.32% and 3,330×. Cohere is 0.63 percentage points / 10.4% relatively better than v2 and 0.90 points / 14.2% relatively better than v3, while Parakeet has roughly 6.4× the batched throughput. The paper's conclusion is the same tradeoff MiniWhisper sees: Transformer decoders lead WER; TDT/CTC decoders trade a modest amount of accuracy for much higher speed.

The per-dataset values below combine Cohere's [technical release table](https://huggingface.co/blog/CohereLabs/cohere-transcribe-03-2026-release) with NVIDIA's [v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) and [v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) model-card reproductions of that leaderboard. They are vendor-published rows from the common public benchmark, not independent MiniWhisper results.

| WER | Cohere | Parakeet v2 | Parakeet v3 |
| --- | ---: | ---: | ---: |
| Macro average | **5.42%** | 6.05% | 6.34% |
| AMI | **8.15%** | 11.16% | 11.31% |
| Earnings-22 | **10.84%** | 11.15% | 11.42% |
| GigaSpeech | **9.33%** | 9.74% | 9.59% |
| LibriSpeech test-clean | **1.25%** | 1.69% | 1.93% |
| LibriSpeech test-other | **2.37%** | 3.19% | 3.59% |
| SPGISpeech | 3.08% | **2.17%** | 3.97% |
| TED-LIUM v3 | **2.49%** | 3.38% | 2.75% |
| VoxPopuli | **5.87%** | 5.95% | 6.14% |

Cohere beats v2 on seven of eight sets and v3 on all eight in that snapshot. AMI and LibriSpeech-other drive much of the gap; Cohere does not dominate every domain, as v2's SPGISpeech result shows.

The leaderboard has since changed its normalizer, hardware, cleaned splits, and included datasets. Its [July 31 result CSV](https://huggingface.co/datasets/hf-audio/open-asr-leaderboard-results/blob/main/english_short_latest.csv) narrows the cleaned seven-set macro to 5.20% Cohere, 5.39% v2, and 5.66% v3: a 0.19-point / 3.6% relative advantage over the actual English incumbent and a 0.46-point / 8.2% advantage over v3. Cohere still wins AMI, Earnings-22, GigaSpeech, and both LibriSpeech splits; v2 wins SPGISpeech and VoxPopuli. The public leaderboard page currently places Cohere fourth, v2 ninth, and v3 tenth. Version drift changes the size, not the direction, of the average Cohere-v2 delta.

For multilingual European speech, the paper reports 3.83% Cohere versus 4.81% Parakeet v3 across CoVoST-2, FLEURS, and MLS, a 0.98-point / 20.4% relative advantage. No controlled English Common Voice head-to-head was found. Cohere's vendor chart averages Common Voice 17 with FLEURS, MLS, and Wenet by language and does not expose a separable Cohere-versus-Parakeet Common Voice row; both Parakeet versions also include Common Voice in training, making that test less clean for this decision.

Long-form evidence is similar but smaller: the paper reports 9.73% Cohere versus 10.7% Parakeet v3, with Cohere at 418× and Parakeet at 1,000× RTFx. Cohere is more accurate; Parakeet is 2.4× faster even in the long-form throughput regime.

### Direct Apple-local Core ML comparison

[MacParakeet's benchmark archive](https://github.com/moona3k/macparakeet/blob/b9ed08cd04c8/benchmarks/asr/README.md) is the closest public analogue to the missing MiniWhisper run. It scores frozen hypotheses for all 2,620 LibriSpeech test-clean and 2,939 test-other files through FluidAudio Core ML on an M4 Pro with 48 GB RAM.

| Engine | test-clean | test-other | Equal-split macro |
| --- | ---: | ---: | ---: |
| Cohere q8 | **1.49%** | **2.65%** | **2.07%** |
| Parakeet Unified | 1.64% | 3.13% | 2.38% |
| Parakeet v2 | 1.86% | 3.27% | 2.57% |
| Parakeet v3 | 2.31% | 4.14% | 3.22% |

Against v2, Cohere improves the macro by 0.50 points / 19.5% relatively. That is a substantial and directly relevant artifact-level accuracy result, not merely Cohere's marketing. The committed hypotheses and scorer make re-scoring reproducible, but the original end-to-end rerun is only partially pinned: exact model artifact revisions, the CLI build, macOS point release, and thermal state are missing. The corpus is clean read speech, not dictation, AMI, Earnings-22, or technical language.

The same source reports Cohere's older FluidAudio CLI path at roughly 73 seconds cold, 11× steady throughput, and 11.6 GB peak RSS, versus 0.38–0.93 seconds, 81–93×, and 115–131 MB for its Parakeet family. That independently corroborates MiniWhisper's 12,135 MiB high-water mark. It does not prove every Cohere runtime must consume 12 GB; it shows that the practical FluidAudio q8 path does.

The original MiniWhisper smoke run was itself Core ML, not a Python/MLX path: the harness loaded FluidAudio's q8 encoder and static decoder with `MLComputeUnits.all`. FluidAudio documents the encoder as INT8 and the v2 decoder as ANE-oriented; the model artifact says `coreml-cli` observed no encoder CPU fallback. Neither MiniWhisper nor MacParakeet captured a Core ML execution trace, so actual per-operation ANE residency remains an inference from configuration and FluidAudio's artifact validation. A separate [community Core ML-encoder/ONNX-decoder port](https://huggingface.co/Aayush9029/cohere-transcribe-2b-coreml-onnx) reports about two seconds for four seconds of audio, which is slower still. The poor memory and latency are therefore properties of today's Apple-local conversions, not proof that the 2B model can never improve.

### Independent and community evidence

The non-leaderboard evidence does not support a universal accuracy win. Hacker News and r/LocalLLaMA search results were largely announcement repetition or stated plans to test, not first-hand Cohere-versus-Parakeet evidence worth treating as a result:

- [Artificial Analysis AA-WER v2](https://artificialanalysis.ai/speech-to-text/models/cohere-transcribe) uses about eight hours weighted across AgentTalk, cleaned VoxPopuli, and cleaned Earnings-22, covering accents, domain language, and difficult channels. It reports Cohere's hosted route at 4.6%, Together's Parakeet v3 at 4.5%, and NVIDIA Parakeet v2 at 6.4%. Cohere clearly beats v2 there but is effectively tied with, and nominally behind, v3. Provider inference settings differ, so this is a system comparison rather than local-weight isolation.
- A [Whisperian Android test](https://www.reddit.com/r/Whisperian/comments/1scexgi/testing_the_new_cohere_transcribe_local_model/) directly compared local Cohere with Parakeet v3 and found Cohere heavier and slower, usually similar in recognition accuracy, occasionally malfunctioning, but better at punctuation. A second user who tried both still preferred Parakeet. An [OpenWhispr issue comment](https://github.com/OpenWhispr/openwhispr/issues/533) reports that Cohere was excellent in Polish and handled punctuation much better than Parakeet. These are useful product impressions, not controlled scores.
- One [M4/MPS local test](https://github.com/jaxson/tests-public/blob/main/transcription/2026-03-27-cohere-vs-whisper-steve-jobs.md) found Cohere strong on proper nouns in a 15-minute English speech, including names and typography terms that Whisper base missed. It compared Whisper, not Parakeet, so it establishes plausibility rather than an incumbent advantage.
- An [independent H100 probe](https://inferencebench.io/blog/cohere-transcribe-03-2026-benchmark/) measured 1.46% on LibriSpeech-clean and 6.25% on VoxPopuli, but 17.74% on AMI-IHM and 29.17% on AMI-SDM. It used only 30 samples per set and acknowledges likely split, VAD, and inference-setting mismatches, so it does not overturn the full leaderboard. It does warn that clean-speech strength may not transfer intact to overlapping or far-field speech.
- [Cohere claims a 61% average human-preference win](https://cohere.com/blog/transcribe) on real-world audio, including named-entity recognition and formatting, but its displayed competitor set does not include Parakeet. Cohere also [publicized a third-party far-field leaderboard result](https://x.com/cohere/status/2064805574101905493) of 17.9% versus Parakeet's 21.5%; the accessible evidence is Cohere's own summary and the leaderboard's result storage is not public, so this remains a vendor-reported claim.

No first-hand, controlled Cohere-versus-Parakeet evidence was found for English technical vocabulary, coding proper nouns, or natural hold-to-talk utterances. Punctuation is the one repeated community advantage, but MiniWhisper can potentially address punctuation separately without paying a 2B-model tax.

### Hold-to-talk decision

The accuracy delta is **real but domain-dependent**. Public aggregate evidence ranges from 0.19 to 0.63 fewer errors per 100 words against v2, while the clean Core ML LibriSpeech archive shows 0.50 fewer. On a notional 20-word dictation, that is roughly 0.04–0.13 fewer expected word errors; error distributions are not uniform, and a saved proper noun can matter more than this arithmetic suggests. The current Cohere path nevertheless charges every dictation: versus Parakeet's controlled numbers, the measured median tax is 434 ms and the p95 tax is 1,377 ms, before considering 2.19 GB on disk and roughly 12 GB peak RSS.

That asymmetry keeps Cohere out of the current product. Latency is felt on every release; the average recognition gain is realized intermittently. But the full Core ML LibriSpeech result is too strong to call the model uninteresting. The revised recommendation is **revisit later**: retain Parakeet v2 now, and rerun Cohere when a faster/lower-memory Apple artifact appears or when a deliberately re-baselined private dictation corpus can test whether its clean-speech, punctuation, and proper-noun advantages survive MiniWhisper's actual domain. A future result near Parakeet's latency with the observed 10–20% relative WER improvement would justify adoption; today's artifact does not.
