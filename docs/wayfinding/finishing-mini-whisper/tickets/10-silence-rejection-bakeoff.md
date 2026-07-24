---
status: closed
type: prototype
blocked-by: [3, 9]
claimed: silence-rejection-bakeoff
---

# Silence rejection bakeoff: prove the gate on real audio

## Question

Which Silero settings and pipeline shape reliably make a silent right-Option hold a no-op without rejecting Thurston's quiet, whispered, clipped, or short English dictation on the target Mac and microphones?

Create a cheap, disposable macOS arm64 prototype under `../assets/10-silence-rejection-bakeoff/`, isolated from the MiniWhisper app and production packages. It should:

- use the runtime/model direction selected by [Engine bakeoff: feel the latency before choosing](09-engine-bakeoff.md) for end-to-end checks, while keeping Silero speech classification independently measurable;
- consume labeled 16 kHz mono WAV fixtures captured with the actual built-in microphone and approved work headset/microphone in representative rooms;
- keep private work recordings out of git, committing only synthetic/public fixtures and a manifest describing uncommitted local fixtures;
- compare no gate, whole-clip and framed RMS baselines, and whisper.cpp's Silero v6.2 VAD at upstream defaults plus a deliberately small threshold/minimum-speech sweep;
- report utterance-level false accepts on silence/noise, false rejects on speech, nonempty hallucinated transcripts, skipped decoder calls, VAD runtime, and final transcript differences;
- include literal silence, lone-tap room tone, long room tone, fan/HVAC, keyboard and mouse noise, nearby media, quiet and whispered speech, short words, clipped boundaries, and leading/trailing silence;
- replay fixtures through irregular capture-buffer sizes and report onset clipping and trailing-silence endpoint latency so the MVP gate and future endpointing use the same framing correctly;
- select settings on a calibration subset and report final results on a separate holdout subset rather than tuning against every failure;
- define an explicit acceptance bar: no nonempty transcript for the no-speech hold corpus, no rejected quiet/short phrase in the speech corpus, and VAD cost negligible beside transcription;
- include a README with exact hardware/runtime/model revisions, reproduction commands, fixture-label format, raw machine-readable results, and a compact comparison table.

This is HITL. Present the recordings, classifications, transcripts, and boundary timelines to Thurston; let him judge false accepts, false rejects, and clipping; then record the recommended MVP settings and any unresolved failure class for the MVP spec. The artifact is deliberately rough. Production APIs and package ownership remain design work for the MVP spec after the behavior is proven.

## Resolution

Select **whisper.cpp Silero v6.2 with speech threshold `0.35` and upstream's `250 ms` minimum speech** for the MVP utterance gate. On release, classify the complete conformed 16 kHz mono recording once. Return a successful empty result when no segment qualifies; when speech qualifies, hand the original complete recording unchanged to FluidAudio's ordinary `AsrManager`. The gate must not trim, concatenate, overlap, chunk, or stitch audio.

The disposable [prototype and reproduction guide](../assets/10-silence-rejection-bakeoff/README.md) ran 34 private fixtures captured on the target M4 Pro Mac through its built-in microphone and the work-approved Shure MV7, split before tuning into 14 calibration and 20 holdout fixtures. The selected setting produced zero false accepts and zero false rejects on both splits. It skipped all 14 no-speech decoder calls, delivered no nonempty no-speech transcript, and preserved every quiet, whispered, short, clipped, and long-form speech recording. Upstream `0.50` / `250 ms` rejected the Shure calibration whisper, so the lower threshold is evidence-driven; lowering below `0.35` would spend unused noise margin without fixing an observed failure.

Whole-clip RMS at its best calibration setting produced 3 false accepts and 1 false reject on calibration, then 5 false accepts on holdout. Framed RMS produced 6 calibration and 6 holdout false accepts. RMS remains metering evidence, never the deciding gate.

Irregular capture buffers reproduced one-shot Silero probabilities exactly when an accumulator emitted complete 512-sample frames and zero-padded only one tail at release. The MVP gate causes `0 ms` onset clipping because accepted audio remains intact. Reusing the same framing for future endpointing yielded 186 ms median and 376 ms maximum confirmation latency under the deliberately broad callback-size replay; endpoint policy remains later design work.

Median VAD inference was 10.1 ms beside 59.7 ms median FluidAudio transcription. The provisional 10% ratio check failed, but Thurston judged the 10.1 ms absolute addition negligible for release-to-text feel; carry a 15 ms absolute regression budget into the MVP spec and keep reporting the ratio separately.

Thurston listened to the local recordings, classifications, transcripts, and timelines and accepted that there was no gate-induced clipping or changed 15-second stitching. The perceived digital character was not PCM saturation—no speech fixture contained a clipped sample—and does not justify changing the gate. Media in the representative environment plays through headphones, so those fixtures test headphone leakage as room tone rather than an irrelevant open-speaker case.

One unresolved failure class belongs in the MVP spec: FluidAudio/Parakeet returned empty transcripts for the accepted built-in-microphone “yes” and “no” fixtures even though Silero speech probabilities reached 1.000 and 0.999; paired Shure short words transcribed correctly. FluidAudio previously rejected all recordings under one second before inference, but [FluidAudio #531](https://github.com/FluidInference/FluidAudio/pull/531) lowered that guard to 300 ms in the selected v0.15.5. These 1.5- and 1.2-second clips reached inference, so they are not that known bug, and no documented general Parakeet v2 short-word defect was found. Production results and regression tests must distinguish `gate rejected`, `engine rejected audio`, and `engine accepted audio but returned empty`; do not weaken the gate or add a phrase workaround for this unproven engine behavior.

Durable evidence:

- [Prototype, pins, fixture schema, and compact comparison](../assets/10-silence-rejection-bakeoff/README.md)
- [Aggregate machine-readable results](../assets/10-silence-rejection-bakeoff/results/final.json)
- [Aggregate compact report](../assets/10-silence-rejection-bakeoff/results/final.md)
