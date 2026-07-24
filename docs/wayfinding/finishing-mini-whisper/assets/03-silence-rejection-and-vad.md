# Silence rejection and VAD landscape

Research date: 2026-07-18. Recommendations are inputs to the MVP grilling tickets, not product decisions.

## Recommendation

Use whisper.cpp's public Silero VAD API as the MVP's pre-transcription speech gate. On right-Option release, run the completed 16 kHz mono float buffer through `whisper_vad_segments_from_samples`. If it returns no speech segments, return a successful no-transcript result and never invoke Whisper decoding. If it finds speech, transcribe the original buffer and retain whisper.cpp's default decoder no-speech/log-probability filter as a second, independent defense.

Do not make RMS the deciding gate. It cheaply distinguishes digital silence from nonzero signal, but it cannot distinguish quiet speech from a quiet microphone or speech from fans, music, and keyboard noise. Do not put `SNClassifySoundRequest` in the MVP either: Apple's built-in model is a broad sound classifier whose shortest window is 500 ms, not a boundary detector. AVAudioEngine voice processing may improve captured speech in echo/noise conditions, but it is preprocessing, not silence rejection.

This approach reuses the exact primitive needed later rather than hiding VAD inside a batch-only transcription call. Current whisper.cpp exposes state-preserving streaming detection with `whisper_vad_detect_speech_no_reset` and an explicit `whisper_vad_reset_state`; future endpointing can feed the same detector successive PCM frames and place a pure endpoint policy over its probabilities. The MVP and future feature share acoustic evidence, while keeping their policies separate:

- **MVP policy:** after capture ends, did this complete recording contain enough speech to justify transcription?
- **Endpoint policy:** while capture is active, when do speech onset, hangover, and sustained silence constitute an utterance boundary?

The VAD model is a separate installed artifact even though whisper.cpp supplies its runtime and conversion. The current official `ggml-silero-v6.2.0.bin` is 885,098 bytes, MIT-licensed, and published by ggml-org. Whispering also distributes Silero: its `@ricky0123/vad-web` package contains `silero_vad_v5.onnx`, and Whispering copies that model into its shipped static assets.[^whispering-model-distribution] That materially strengthens the allowlist case for Silero weights because Whispering is already available at work.

It does not make the files interchangeable. Whispering's 2,327,524-byte v5 ONNX model and whisper.cpp's 885,098-byte v6.2 GGML model are different revisions and runtime formats. whisper.cpp cannot load the ONNX file, and its supported converter reads Silero's Python state dictionary rather than ONNX. Since the allowlist applies to the library/model family rather than exact artifact versions, Whispering resolves the practical policy concern; MiniWhisper should use whisper.cpp's current v6.2 GGML artifact. The mismatch is engineering detail, not a reason to fall back to Apple Sound Analysis.

## Responsibility boundary

| Responsibility                                                   | Owner                                         | Reason                                                                                                                                                                                                       |
| ---------------------------------------------------------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Capture every microphone sample for the active recording         | `AudioCapture`                                | Capture should not irreversibly discard low-level input based on content.                                                                                                                                    |
| Convert the boundary representation to 16 kHz, mono, `Float` PCM | `AudioCapture`                                | This is signal conformance at the system edge and is already useful to every ASR engine.                                                                                                                     |
| Compute RMS/peak levels                                          | `AudioCapture`                                | Levels describe captured signal and support metering/diagnostics. They are not transcript acceptance decisions.                                                                                              |
| Load, validate, retain, and reset the Silero context             | `ASREngine`                                   | It is model inference through whisper.cpp and must share the engine's serialized C-runtime ownership. Missing/incompatible VAD data should fail engine construction, not silently disable a fixed guarantee. |
| Classify PCM as speech/non-speech                                | `ASREngine`                                   | This is acoustic-model inference. If a second engine later has its own VAD, the package can expose the same speech-activity capability without teaching capture about model implementations.                 |
| Skip Whisper decoding for a no-speech recording                  | `ASREngine`                                   | The engine can return no transcript before expensive ASR and guarantee that decoder hallucinations never become output for VAD-empty audio.                                                                  |
| Apply Whisper's decoder no-speech/log-probability rules          | `ASREngine`                                   | These signals and thresholds are Whisper-specific.                                                                                                                                                           |
| Decide an automatic future endpoint from VAD transitions         | neither package; a pure feature/state machine | `AudioCapture` supplies frames and `ASREngine` supplies acoustic evidence. Orchestration owns the policy for onset, minimum utterance, hangover, stop, and commit.                                           |
| Paste nothing when the engine returns no transcript              | app feature/delivery orchestration            | Empty is a legitimate successful outcome, not an error and not text to deliver.                                                                                                                              |

If forced into an `AudioCapture` versus `ASREngine` binary choice, VAD belongs in `ASREngine`. Putting it in capture would make an AVFoundation boundary own a whisper.cpp model and would couple future engine-specific behavior to microphone mechanics.

## Option comparison

| Signal                           | MVP all-silence rejection                                                                                      | Future streaming endpointing                                                                         | Main failure mode                                                          | Recommendation                                                                      |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| RMS/energy threshold             | Excellent for exact zeroes; fragile for quiet speech and ambient noise                                         | Fast enough, but requires adaptive noise estimation, hysteresis, minimum-active frames, and hangover | Absolute amplitude is not speech identity                                  | Meter/diagnostic only; no deciding threshold in MVP                                 |
| whisper.cpp Silero VAD           | Purpose-built speech probability; runs before Whisper                                                          | 32 ms model windows, persistent recurrent state, public reset/no-reset API                           | A separate model artifact and normal VAD false positives/negatives         | Primary primitive                                                                   |
| Apple `SNClassifySoundRequest`   | Can report `speech`, `whispering`, and `silence`, but needs at least 500 ms context                            | Coarse and delayed; overlap improves result cadence, not initial context latency                     | General environmental classifier, confidence calibration, short utterances | Do not use for MVP or endpointing                                                   |
| Apple voice processing / HAL VAD | Noise suppression may improve another detector; HAL can expose activity transitions on supported macOS devices | Potential device-owned activity signal, but tied to Core Audio HAL/device behavior                   | Capture/routing changes, no probability/tuning contract, device coupling   | Evaluate only for an independently justified capture mode, not the silence contract |
| Whisper no-speech probability    | Useful backstop after a decode has already begun                                                               | Whisper's batch windows are too slow/coarse to be the endpoint primitive                             | Model-dependent probability and confident hallucinations                   | Keep upstream combined filter; never use alone                                      |
| Text/phrase blacklist            | Catches known repeated artifacts after damage is done                                                          | No endpoint information                                                                              | Deletes legitimate dictation and grows without bound                       | Do not add                                                                          |

## Comparative evidence

There is no honest single benchmark covering every row above. RMS and dedicated VAD classify raw audio, Sound Analysis classifies broad sound categories, Whisper's no-speech probability exists only after decoding, and a phrase blacklist operates on text. Apple publishes no speech-boundary benchmark for `SNClassifySoundRequest` or its HAL VAD. Any table pretending these are one interchangeable contest would be tidy and wrong.

Two narrower comparisons are useful.

### VAD accuracy

Silero's official quality report compares models on 16 kHz, 31.25 ms chunks across meeting, call, read-speech, and noisy-speech datasets. The multi-domain set is 17 hours; thresholds were selected on that set but the exact values and some private data were not published, so these are vendor-reported rather than independently reproducible results.[^silero-quality]

| Detector | Multi-domain ROC-AUC | Multi-domain frame accuracy | ESC-50 no-speech file accuracy |
| --- | ---: | ---: | ---: |
| WebRTC VAD | 0.73 | 0.74 | 0.00 |
| Silero v5 | 0.96 | 0.91 | 0.61 |
| Silero v6 | 0.97 | 0.92 | 0.87 |

The ESC-50 rule counts a whole environmental-noise file correct only when the detector never produces 100 ms of consecutive speech. It exposes the remaining risk: even v6 is not a proof that arbitrary noise cannot pass the gate. Silero's report does not include RMS or Apple Sound Analysis. Its only runtime table measures v5 ONNX at 189 µs per 31.25 ms frame on one Threadripper CPU thread—roughly 165 times real time—but that is not the whisper.cpp GGML implementation or Apple Silicon.[^silero-runtime]

### Whisper hallucination mitigation

An ICASSP 2025 study provides the most relevant directional comparison found. It used Whisper large-v3 on roughly 10-second Common Voice utterances augmented before/after with unseen non-speech audio at 9 dB SNR, both non-overlapping (NO) and overlapping (OL). VAD-retained speech segments were concatenated before Whisper. The published results were:[^hallucination-vad-study]

| Mitigation | Detected hallucinations NO / OL | WER NO / OL |
| --- | ---: | ---: |
| None | 21.3% / 20.3% | 104.8% / 112.0% |
| Whisper hallucination-silence threshold, 20 s | 14.6% / 14.4% | 39.8% / 53.7% |
| WebRTC VAD | 12.5% / 15.4% | 68.3% / 75.4% |
| Silero VAD | 0.2% / 0.2% | 8.0% / 10.8% |
| Silero VAD plus the paper's de-looping/phrase filter | 0.0% / 0.0% | 6.5% / 9.4% |

This is not a MiniWhisper benchmark and it did not test RMS, Apple APIs, or Whisper's `no_speech_prob` in isolation. Its phrase filter was built from a research corpus and should not become a product blacklist. The strong result is narrower: a dedicated, effective pre-ASR VAD reduced hallucinations far more than Whisper parameter tuning, and Silero materially outperformed WebRTC in this setup.

### What open-source dictation apps ship

The implementation evidence points the same way. Three audited apps that truly reject/segment silence use Silero; Hex does not have an equivalent gate.

| App | Actual mechanism | Policy |
| --- | --- | --- |
| Hex | RMS/peak for UI; WhisperKit energy VAD only chooses split points for oversized clips | No short-utterance silence gate; user release ends batch capture |
| VoiceInk | Bundled whisper.cpp `ggml-silero-v5.1.2.bin`, enabled by default | Integrated pre-ASR speech filtering with upstream defaults; user stop commits streaming |
| Whispering / Epicenter | Shipped Silero v5 ONNX through `@ricky0123/vad-web` | VAD start/end creates utterance WAVs; misfires are discarded; VAD mode auto-segments |
| Handy | Shipped Silero v4 ONNX, threshold `0.30`, 60 ms onset, 450 ms pre-roll/tail | Drops non-speech frames; user stop still finalizes recording[^handy-vad] |

The closed-source apps in the feature survey advertise VAD, silence removal, or streaming behavior, but do not disclose the detector or thresholds. They are taste evidence, not implementation evidence. Among auditable implementations, dedicated Silero VAD before ASR is the normal robust choice; RMS remains metering, and decoder/output filters remain secondary safeguards.

## Energy and RMS gating

For normalized float samples, frame RMS is `sqrt(sum(sample²) / count)`; dBFS is commonly `20 * log10(rms)`. It is deterministic, model-free, almost free to compute, and immediately catches an empty buffer, literal zeroes, a disconnected input, or some accidental near-zero recordings. WhisperKit's `EnergyVAD`, which Hex receives through WhisperKit, is representative prior art: 100 ms frames and a fixed `0.02` threshold by default.[^whisperkit-energy]

The threshold is the problem. Hardware gain, microphone distance, voice-processing AGC, speaking style, and ambient noise all move the distributions. Raising it rejects soft consonants and low-volume speech; lowering it admits breathing, fans, music, keyboard impacts, and electrical noise. An adaptive noise floor is better, but then the implementation needs a trustworthy period of noise, smoothing, an SNR threshold, onset hysteresis, hangover, and tests for a moving noise floor. That is a VAD implementation in installments. Current speech-processing guidance describes fixed energy thresholding as suitable for the low-noise trivial case and highly threshold-sensitive at low SNR.[^energy-vad]

MiniWhisper should still calculate levels because metering and diagnostics need them. It may assert obvious structural failures such as an empty sample buffer. It should not reject a nonempty utterance merely because one absolute RMS statistic is below a chosen number.

## whisper.cpp's Silero VAD

### Current stable API

The engine research selected whisper.cpp stable `v1.9.1` at commit [`f049fff95a08`](https://github.com/ggml-org/whisper.cpp/tree/f049fff95a089aa9969deb009cdd4892b3e74916). That release has first-class exported C VAD APIs in `include/whisper.h`, not only example helpers:

- context defaults and `whisper_vad_init_from_file_with_params`;
- batch `whisper_vad_detect_speech`, which resets recurrent state first;
- streaming `whisper_vad_detect_speech_no_reset` plus `whisper_vad_reset_state` between utterances;
- probability access through `whisper_vad_n_probs` / `whisper_vad_probs`;
- `whisper_vad_segments_from_probs` and the one-call `whisper_vad_segments_from_samples`;
- segment count/start/end accessors and explicit free functions.[^whisper-vad-api]

`whisper_full_params` also has integrated `vad`, `vad_model_path`, and `vad_params` fields. With integrated VAD enabled, `whisper_full` runs VAD first, keeps detected speech ranges with padding/overlap, inserts short separators between retained ranges, and maps result timestamps back to the original audio. If there are no VAD segments, it clears the result and returns success without Whisper inference.[^whisper-integrated]

The integrated switch is the fewest-call MVP, and VoiceInk uses it. The standalone call is the better MiniWhisper seam because it makes the gate explicit, lets the engine avoid decoding without rewriting/cutting the original utterance, and has a direct evolution into frame-by-frame activity. It also avoids running VAD twice: preflight once, then call Whisper with integrated VAD disabled when speech exists.

### Audio and model requirements

The API accepts a `const float *` and sample count but no sample-rate argument. whisper.cpp fixes speech audio at 16,000 Hz; callers must provide mono 16 kHz float PCM. The converted Silero v6.2.0 model uses 512-sample windows—32 ms at 16 kHz—and 64 samples of context. whisper.cpp zero-pads an incomplete final window.[^whisper-vad-implementation]

The VAD artifact is not a normal Silero Torch/ONNX file. It must be whisper.cpp's converted GGML form. The official download script currently offers `silero-v5.1.2` and `silero-v6.2.0` from `ggml-org/whisper-vad`; use v6.2.0 unless the pinned whisper.cpp release or local tests reveal a regression.[^whisper-vad-download] The repository metadata is MIT and v6.2.0's published SHA-256 is `2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987`.[^whisper-vad-artifact]

The upstream segmentation defaults are:

- speech probability threshold: `0.5`;
- minimum speech: `250 ms`;
- minimum silence: `100 ms`;
- maximum speech: unlimited;
- speech padding: `30 ms`;
- inter-segment sample overlap: `0.1 s`.[^whisper-vad-defaults]

Start evaluation with those defaults rather than inventing values. The 250 ms minimum usefully rejects key taps and impulses, but it might reject a clipped or very short word. The MVP fixture corpus must include quiet speech, whispered speech, short “yes/no” utterances, a lone Option tap, fan noise, keyboard noise, music/TV leakage, and literal silence before deciding whether to tune it.

### Future endpointing path

Silero produces one probability per model window. A future streaming session can retain one VAD context, accumulate capture buffers into complete 512-sample frames, feed those frames through `whisper_vad_detect_speech_no_reset`, read each call's probabilities, and reset at a committed/cancelled utterance boundary. This framing matters: whisper.cpp zero-pads every partial final frame, so passing arbitrary tap-buffer tails on every call would manufacture repeated silence and make results depend on callback sizes. Do not equate one probability crossing with an endpoint. A pure endpoint detector should own at least:

- threshold/hysteresis for speech start and end;
- minimum confirmed speech before an utterance is valid;
- trailing-silence duration/hangover before commit;
- speech padding/pre-roll so onset audio is not clipped;
- maximum utterance safety duration;
- explicit user release/cancel precedence;
- reset behavior after interruptions and stale session IDs.

Those are policy choices and need scenario tests. They do not belong in the AVAudioEngine tap or inside the C callback. The future endpoint detector can reuse upstream's segment defaults as priors, but streaming UX must choose its own latency/false-end tradeoff.

## Apple options

### `SNClassifySoundRequest`

Sound Analysis is on-device and allowlist-compatible as an Apple framework. `SNClassifySoundRequest(classifierIdentifier: .version1)` uses Apple's built-in classifier, and `SNAudioStreamAnalyzer` can consume the buffers already captured by MiniWhisper, so it would not require another microphone permission or network access. The model recognizes hundreds of environmental sounds; its known identifiers include `speech`, `whispering`, and `silence`.[^apple-sound-analysis]

It is still the wrong primitive. Apple documents a 0.5–15 second supported window range and recommends one second or longer as a starting point. Each result covers a complete analysis window, so the first result cannot arrive before the first window is buffered. `overlapFactor` defaults to `0.5`; higher overlap produces predictions more frequently at more computational cost but does not shorten the context needed for the first result. Results can describe audio in the past because classification requires complete blocks.[^apple-sound-window]

That shape is useful for tagging laughter, applause, alarms, and other environmental sounds. It is coarse for a short push-to-talk utterance and gives no speech-boundary-specific latency or calibration contract. A custom Core ML speech detector could improve this, but it would add a model and training/validation work while whisper.cpp already ships a supported VAD path.

### AVAudioEngine voice processing

`AVAudioIONode.setVoiceProcessingEnabled(true)` is available on macOS 10.15+. It enables Apple's voice-oriented signal processing, including echo cancellation, noise suppression, and automatic gain control. Enabling either I/O node switches both input and output nodes into voice-processing mode; the engine must be stopped while changing the mode, and it only works while rendering to a device, not manual rendering.[^apple-voice-processing]

This can change levels, device/routing behavior, and the captured signal. It may make speech easier for Silero to classify when speaker echo or persistent noise is a demonstrated problem. It does not itself answer whether an utterance contains speech, so adopting it solely to satisfy silence rejection would couple a broad capture-mode change to the wrong requirement. Evaluate standard versus voice-processed recordings separately on the actual Mac and microphones.

The AVAudioEngine muted-speech callback is not a general escape hatch. `setMutedSpeechActivityEventListener` reports `.started`/`.ended` only while voice processing is enabled and `isVoiceProcessingInputMuted` is true; Apple designed it to prompt a VoIP user who talks while muted. An unmuted dictation recorder has no supported callback contract.[^apple-muted-speech]

macOS 14 also added Core Audio HAL properties `kAudioDevicePropertyVoiceActivityDetectionEnable` and `kAudioDevicePropertyVoiceActivityDetectionState`. Unlike the muted callback, the HAL state works regardless of process mute and detects activity from echo-cancelled microphone input.[^apple-hal-vad] It is a real Apple VAD option, but it is device-level state rather than probability-bearing PCM analysis. It brings lower-level device selection/listener lifecycle, no public threshold/window tuning, and coupling to the active input device. It also does not provide the same cross-engine, recorded-fixture-testable primitive as Silero. Keep it as a fallback experiment if the converted model cannot pass the allowlist, not the preferred architecture.

## Whisper no-speech probability and output filtering

Whisper has its own `<|nospeech|>` token. In whisper.cpp, `no_speech_prob` is the softmax probability of that token from the first unfiltered decoder pass. With defaults, a decode window is omitted only when both:

```text
no_speech_prob > 0.6
and average generated-token log probability < -1.0
```

The combined predicate matters: high no-speech probability is overridden by confident text. The same values also influence temperature fallback. Current whisper.cpp exposes `whisper_full_get_segment_no_speech_prob`, but only for emitted result segments; a skipped window has no public result index. `suppress_nst` masks non-speech text tokens during decoding and is a different feature, not VAD.[^whisper-no-speech]

Keep the upstream defaults as defense in depth. Do not use this as the sole silence gate because it spends decoder work first, is model/decoding dependent, and can fail precisely when Whisper emits a confident hallucination. OpenAI's own implementation uses the same default `0.6` no-speech and `-1.0` log-probability conjunction; its maintainer has also described `no_speech_prob` as imperfect VAD evidence.[^openai-no-speech]

Post-transcription handling should remain conservative:

- accept an empty engine result as the correct no-op;
- trim structural whitespace before deciding whether anything is deliverable;
- do not maintain a blacklist such as “thank you for watching”—it can be legitimately dictated and will never be complete;
- do not copy VoiceInk's broad removal of every bracketed/parenthesized phrase as a silence fix; that is text sanitation and can delete intended prose;
- retain structured segment confidence internally if later evidence justifies a narrowly specified filter, but do not invent one before fixture results exist.

## Prior art

### Hex

Hex is architecturally useful but does not currently satisfy MiniWhisper's silence guarantee. It records a complete WAV and transcribes after hotkey release. Its RMS/peak values drive UI metering only. A pure `RecordingDecisionEngine` rejects modifier-only recordings under 300 ms, which makes a lone tap cheap, but a long silent hold still reaches ASR.[^hex-recording]

For Whisper models, Hex passes WhisperKit's `.vad` chunking strategy. WhisperKit uses its energy VAD only to choose a split point when audio exceeds the model window; a normal short dictation remains one batch. Although that WhisperKit revision exposes a no-speech threshold, its decoder hard-codes `noSpeechProb` to zero, so the threshold cannot reject silence. Hex adds no audio gate or hallucination blacklist and only refuses exactly empty output.[^hex-transcription]

Steal Hex's separation: capture reports audio/levels, a pure decision layer owns gesture timing, and the transcription client owns model behavior. Do not mistake its current VAD label for short-utterance silence rejection.

### VoiceInk

VoiceInk is the closest MVP precedent. Its local Whisper wrapper defaults VAD on, resolves a bundled `ggml-silero-v5.1.2.bin`, and maps the upstream `0.5` / 250 ms / 100 ms / 30 ms / 0.1 s values into `whisper_full_params` before batch transcription.[^voiceink-vad] Its recorder computes RMS/peak only for its visual meter.[^voiceink-meter]

VoiceInk silently disables VAD if the model cannot be located. MiniWhisper should not copy that fallback because “silence pastes nothing” is fixed: a missing required model is a configuration/load failure. VoiceInk's generic streaming providers are committed when the user stops recording; they do not expose an app-owned silence endpoint. Its shared output filter removes tags, bracketed text, and configured filler words after ASR, which is not evidence for a safe hallucination filter.[^voiceink-pipeline]

### Whispering / Epicenter

Whispering's automatic VAD mode uses `@ricky0123/vad-web` with Silero v5. The npm package ships the ONNX model, and Whispering's Vite build copies it with the worklet and ONNX Runtime assets into the application.[^whispering-model-distribution] Speech-start/end events drive a recording state machine; a completed VAD utterance becomes a WAV blob and then goes through ordinary batch transcription, while a VAD misfire returns to listening without transcription.[^whispering-vad] This is good evidence for separating acoustic events from recording/endpoint policy.

Its RMS values are also UI-only. Manual recordings have no silence gate, and desktop code pads nonempty clips shorter than one second to 1.25 seconds as a hallucination mitigation rather than rejecting silence. Whispering does not configure Whisper no-speech filtering or a phrase blacklist in its active path, and its transcription is batch/upload after an utterance—not incremental ASR.[^whispering-batch]

## Prototype before implementation

Yes—prototype this next, before production package design fixes the model, thresholds, or result types. The external evidence selects a dedicated neural VAD and strongly favors Silero, but it cannot establish the operating point for the actual microphone, room, voice, and whisper.cpp conversion. This is exactly where a small empirical spike is cheaper than confidence.

Keep the prototype disposable and local. It should accept labeled WAV fixtures and compare:

1. whole-clip and framed RMS as a baseline;
2. whisper.cpp Silero v6.2 probabilities/segments at the upstream defaults, plus a small threshold/minimum-speech sweep;
3. Whisper output with no gate versus the proposed Silero gate, retaining segment no-speech/log-probability metadata;
4. optionally Sound Analysis as a comparison only if later evidence reopens it—it is not worth delaying the Silero result.

Measure utterance-level false accepts on no-speech recordings, false rejects on real speech, hallucinated nonempty transcripts, skipped Whisper decodes, and VAD runtime. For future endpointing, also measure onset clipping, trailing-silence endpoint latency, and decisions across arbitrary capture-buffer boundaries. A false reject is more damaging than a false accept at the acoustic gate because rejected speech cannot be recovered; a false accept can still be caught by Whisper's output filter.

Use a small calibration subset to choose settings and a separate holdout subset to report them. Do not commit private work recordings; commit only synthetic/public fixtures and expected labels. The initial acceptance target should be explicit: zero nonempty transcripts for the no-speech hold corpus, zero rejected quiet/short phrases in the speech corpus, and VAD time negligible beside Whisper inference.

The recommendation is incomplete until it survives real recordings. Build a deterministic fixture suite from the actual target Mac/microphones and assert whether the VAD gate returns speech, without running Whisper:

- exact zeroes and empty input: no speech;
- 0.1–0.3 second lone-tap room tone: no speech;
- 2, 10, and 60 seconds of room tone: no speech;
- fan/HVAC, keyboard, mouse clicks, music, and nearby playback: no speech unless intelligible background speech is deliberately considered active;
- quiet, whispered, ordinary, and loud speech at normal distances: speech;
- short words and clipped onset/release: speech;
- leading/trailing silence around speech: speech;
- built-in microphone, approved headset, and any work-desk microphone separately.

Then run the full pipeline against the no-speech fixtures and prove all three invariants: Whisper's decode callback is never entered, the engine result contains no transcript, and delivery performs no paste/clipboard mutation. Also record VAD latency and false decisions. Tune thresholds only in response to named fixture failures.

For future endpointing, replay the same fixtures as irregularly sized frame chunks and prove chunk boundaries do not change activity/endpoint decisions. Add onset, brief internal pause, long pause, release-before-endpoint, cancel, interruption, maximum duration, and state-reset scenarios. The endpoint policy should use an injected monotonic timeline and no AVFoundation types.

## Audit trail

Primary snapshots and platform documentation:

- whisper.cpp [`v1.9.1` / `f049fff95a08`](https://github.com/ggml-org/whisper.cpp/tree/f049fff95a089aa9969deb009cdd4892b3e74916), 2026-06-19.
- Hex [`ca9642799024`](https://github.com/kitlangton/Hex/tree/ca96427990249223cc31027d14c1f2c9ded57910), 2026-07-09.
- VoiceInk [`69ed170c1d7f`](https://github.com/Beingpax/VoiceInk/tree/69ed170c1d7f582e76f3f63a2ac2c30ddb3a2d75), 2026-07-16.
- Epicenter/Whispering [`cb12bccfdeba`](https://github.com/epicenter-so/epicenter/tree/cb12bccfdeba2ba6bad65bd905d78ea92130e99d).
- Handy [`cdbc22390987`](https://github.com/cjpais/Handy/tree/cdbc22390987643237756382ef367f7244b2844f).
- Apple [Sound Analysis WWDC21](https://developer.apple.com/videos/play/wwdc2021/10036/), [AVAudioEngine voice processing WWDC19](https://developer.apple.com/videos/play/wwdc2019/510), and [voice processing/HAL VAD WWDC23](https://developer.apple.com/videos/play/wwdc2023/10235/).

[^whisperkit-energy]: WhisperKit, [`EnergyVAD.swift`](https://github.com/argmaxinc/WhisperKit/blob/664e1b5a65296cd957dfdf262cd120ca88f3b24b/Sources/WhisperKit/Core/Audio/EnergyVAD.swift#L7-L54), the revision pinned by Hex.

[^energy-vad]: Aalto University, [Introduction to Speech Processing: Voice Activity Detection](https://speechprocessingbook.aalto.fi/Recognition/Voice_activity_detection.html).

[^whisper-vad-api]: whisper.cpp v1.9.1, [`include/whisper.h`](https://github.com/ggml-org/whisper.cpp/blob/f049fff95a089aa9969deb009cdd4892b3e74916/include/whisper.h#L686-L731).

[^whisper-integrated]: whisper.cpp v1.9.1, [`whisper_full_params`](https://github.com/ggml-org/whisper.cpp/blob/f049fff95a089aa9969deb009cdd4892b3e74916/include/whisper.h#L580-L590), [VAD preprocessing](https://github.com/ggml-org/whisper.cpp/blob/f049fff95a089aa9969deb009cdd4892b3e74916/src/whisper.cpp#L6651-L6788), and [empty-segment return](https://github.com/ggml-org/whisper.cpp/blob/f049fff95a089aa9969deb009cdd4892b3e74916/src/whisper.cpp#L7770-L7794).

[^whisper-vad-implementation]: whisper.cpp v1.9.1, [windowed detection](https://github.com/ggml-org/whisper.cpp/blob/f049fff95a089aa9969deb009cdd4892b3e74916/src/whisper.cpp#L5104-L5188) and [Silero converter](https://github.com/ggml-org/whisper.cpp/blob/f049fff95a089aa9969deb009cdd4892b3e74916/models/convert-silero-vad-to-ggml.py#L6-L40).

[^whisper-vad-download]: whisper.cpp v1.9.1, [VAD documentation](https://github.com/ggml-org/whisper.cpp/blob/f049fff95a089aa9969deb009cdd4892b3e74916/README.md#L789-L831) and [`download-vad-model.sh`](https://github.com/ggml-org/whisper.cpp/blob/f049fff95a089aa9969deb009cdd4892b3e74916/models/download-vad-model.sh).

[^whisper-vad-artifact]: ggml-org, [`whisper-vad` model repository](https://huggingface.co/ggml-org/whisper-vad/tree/main) and [v6.2.0 commit metadata](https://huggingface.co/ggml-org/whisper-vad/commit/9ffd54a1e1ee413ddf265af9913beaf518d1639b).

[^whisper-vad-defaults]: whisper.cpp v1.9.1, [default VAD parameters](https://github.com/ggml-org/whisper.cpp/blob/f049fff95a089aa9969deb009cdd4892b3e74916/src/whisper.cpp#L4443-L4461).

[^apple-sound-analysis]: Apple, [`SNClassifySoundRequest`](https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest) and [built-in sound classification](https://developer.apple.com/videos/play/wwdc2021/10036/).

[^apple-sound-window]: Apple, [WWDC21 window-duration guidance](https://developer.apple.com/videos/play/wwdc2021/10036/?time=680) and `SNClassifySoundRequest` [`overlapFactor`](https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest/overlapfactor) / [`windowDurationConstraint`](https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest/windowdurationconstraint).

[^apple-voice-processing]: Apple, [`setVoiceProcessingEnabled`](<https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:)>) and [WWDC19 AVAudioEngine discussion](https://developer.apple.com/videos/play/wwdc2019/510/?time=46).

[^apple-muted-speech]: Apple, [WWDC23 muted-talker contract](https://developer.apple.com/videos/play/wwdc2023/10235/?time=503) and [`setMutedSpeechActivityEventListener`](<https://developer.apple.com/documentation/avfaudio/avaudioinputnode/setmutedspeechactivityeventlistener(_:)>).

[^apple-hal-vad]: Apple, [WWDC23 macOS HAL VAD](https://developer.apple.com/videos/play/wwdc2023/10235/?time=697).

[^whisper-no-speech]: whisper.cpp v1.9.1, [`whisper_full_params`](https://github.com/ggml-org/whisper.cpp/blob/f049fff95a089aa9969deb009cdd4892b3e74916/include/whisper.h#L535-L590), [defaults](https://github.com/ggml-org/whisper.cpp/blob/f049fff95a089aa9969deb009cdd4892b3e74916/src/whisper.cpp#L5970-L6014), and [exact skip predicate](https://github.com/ggml-org/whisper.cpp/blob/f049fff95a089aa9969deb009cdd4892b3e74916/src/whisper.cpp#L7598-L7622).

[^openai-no-speech]: OpenAI Whisper, [`transcribe.py`](https://github.com/openai/whisper/blob/main/whisper/transcribe.py) and maintainer discussion [#29](https://github.com/openai/whisper/discussions/29).

[^hex-recording]: Hex, [`RecordingDecision.swift`](https://github.com/kitlangton/Hex/blob/ca96427990249223cc31027d14c1f2c9ded57910/HexCore/Sources/HexCore/Logic/RecordingDecision.swift#L6-L75) and [`SuperFastCaptureController.swift`](https://github.com/kitlangton/Hex/blob/ca96427990249223cc31027d14c1f2c9ded57910/Hex/Clients/SuperFastCaptureController.swift#L358-L435).

[^hex-transcription]: Hex, [`TranscriptionFeature.swift`](https://github.com/kitlangton/Hex/blob/ca96427990249223cc31027d14c1f2c9ded57910/Hex/Features/Transcription/TranscriptionFeature.swift#L319-L557), and its pinned WhisperKit [`WhisperKit.swift`](https://github.com/argmaxinc/WhisperKit/blob/664e1b5a65296cd957dfdf262cd120ca88f3b24b/Sources/WhisperKit/Core/WhisperKit.swift#L850-L963), [`AudioChunker.swift`](https://github.com/argmaxinc/WhisperKit/blob/664e1b5a65296cd957dfdf262cd120ca88f3b24b/Sources/WhisperKit/Core/Audio/AudioChunker.swift#L34-L103), and [`TextDecoder.swift`](https://github.com/argmaxinc/WhisperKit/blob/664e1b5a65296cd957dfdf262cd120ca88f3b24b/Sources/WhisperKit/Core/TextDecoder.swift#L980-L1005).

[^voiceink-vad]: VoiceInk, [`LibWhisper.swift`](https://github.com/Beingpax/VoiceInk/blob/69ed170c1d7f582e76f3f63a2ac2c30ddb3a2d75/VoiceInk/Transcription/Whisper/LibWhisper.swift#L24-L108) and [`VADModelManager.swift`](https://github.com/Beingpax/VoiceInk/blob/69ed170c1d7f582e76f3f63a2ac2c30ddb3a2d75/VoiceInk/Transcription/Whisper/VADModelManager.swift#L4-L20).

[^voiceink-meter]: VoiceInk, [`CoreAudioRecorder.swift`](https://github.com/Beingpax/VoiceInk/blob/69ed170c1d7f582e76f3f63a2ac2c30ddb3a2d75/VoiceInk/CoreAudioRecorder.swift#L833-L869).

[^voiceink-pipeline]: VoiceInk, [`TranscriptionSession.swift`](https://github.com/Beingpax/VoiceInk/blob/69ed170c1d7f582e76f3f63a2ac2c30ddb3a2d75/VoiceInk/Transcription/Engine/TranscriptionSession.swift#L48-L165) and [`TranscriptionOutputFilter.swift`](https://github.com/Beingpax/VoiceInk/blob/69ed170c1d7f582e76f3f63a2ac2c30ddb3a2d75/VoiceInk/Transcription/Processing/TranscriptionOutputFilter.swift#L3-L47).

[^whispering-vad]: Epicenter/Whispering, [`vad-recorder.ts`](https://github.com/epicenter-so/epicenter/blob/cb12bccfdeba2ba6bad65bd905d78ea92130e99d/packages/recorder/src/vad-recorder.ts#L141-L170), [state adapter](https://github.com/epicenter-so/epicenter/blob/cb12bccfdeba2ba6bad65bd905d78ea92130e99d/apps/whispering/src/lib/state/vad-recorder.svelte.ts#L91-L115), and [recording operation](https://github.com/epicenter-so/epicenter/blob/cb12bccfdeba2ba6bad65bd905d78ea92130e99d/apps/whispering/src/lib/operations/recording.ts#L252-L306).

[^whispering-batch]: Epicenter/Whispering, [desktop recorder finalization](https://github.com/epicenter-so/epicenter/blob/cb12bccfdeba2ba6bad65bd905d78ea92130e99d/apps/epicenter/src-tauri/src/recorder/recorder.rs#L344-L361), [local model path](https://github.com/epicenter-so/epicenter/blob/cb12bccfdeba2ba6bad65bd905d78ea92130e99d/apps/epicenter/src-tauri/src/transcription/model_cache.rs#L85-L113), and [`transcribeAudio`](https://github.com/epicenter-so/epicenter/blob/cb12bccfdeba2ba6bad65bd905d78ea92130e99d/apps/whispering/src/lib/operations/transcribe.ts#L246-L264).

[^whispering-model-distribution]: Epicenter/Whispering, [`vad-assets.ts`](https://github.com/epicenter-so/epicenter/blob/cb12bccfdeba2ba6bad65bd905d78ea92130e99d/packages/recorder/src/vad-assets.ts#L4-L43) and [`vite.config.ts`](https://github.com/epicenter-so/epicenter/blob/cb12bccfdeba2ba6bad65bd905d78ea92130e99d/apps/whispering/vite.config.ts#L1-L45); vad-web, [`build.sh`](https://github.com/ricky0123/vad/blob/8941bbf91162/packages/web/scripts/build.sh#L1-L11), [model loading](https://github.com/ricky0123/vad/blob/8941bbf91162/packages/web/src/real-time-vad.ts#L270-L290), and [license](https://github.com/ricky0123/vad/blob/8941bbf91162/LICENSE).

[^silero-quality]: Silero VAD, official wiki [Quality Metrics](https://github.com/snakers4/silero-vad/wiki/Quality-Metrics).

[^silero-runtime]: Silero VAD, official wiki [Performance Metrics](https://github.com/snakers4/silero-vad/wiki/Performance-Metrics).

[^hallucination-vad-study]: Barański et al., [“Investigation of Whisper ASR Hallucinations Induced by Non-Speech Audio,”](https://arxiv.org/html/2501.11378v1#S5) ICASSP 2025, Table VII.

[^handy-vad]: Handy, [`silero.rs`](https://github.com/cjpais/Handy/blob/cdbc22390987643237756382ef367f7244b2844f/src-tauri/src/audio_toolkit/vad/silero.rs#L7-L57), [VAD policy constants](https://github.com/cjpais/Handy/blob/cdbc22390987643237756382ef367f7244b2844f/src-tauri/src/audio_toolkit/vad/mod.rs#L1-L35), and [`smoothed.rs`](https://github.com/cjpais/Handy/blob/cdbc22390987643237756382ef367f7244b2844f/src-tauri/src/audio_toolkit/vad/smoothed.rs#L37-L105).
