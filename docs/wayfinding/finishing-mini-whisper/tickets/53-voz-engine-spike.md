---
status: closed
claimed: subagent:gpt-6-astra
type: research
blocked-by: [43]
---

# Voz engine spike: Desert Ant's Parakeet v3 against the shipping engine

## Question

[Desert Ant Labs' Voz](https://huggingface.co/desert-ant-labs/voz) is Parakeet TDT 0.6B v3, converted to Core ML, compressed to 467 MB, and driven by a Swift runtime that keeps the whole graph on the Neural Engine (`desert-ant-core` ≥ 3.1.0, product `Voz`, macOS 15+, Swift 6.2+). Measure it on the [dictation corpus](43-coded-speech-corpus.md) against every engine already in the [results rollup](../assets/43-dictation-corpus/results/README.md), and separate the model from the runtime: is any gain over the shipping FluidAudio + Parakeet v2 the v3 weights, or Desert Ant's dispatch?

## Notes

- The comparison is the corpus, not the old bakeoff. Stage 1 intelligibility is the headline (WER + warm latency), stage 1 long-form matters because Voz cuts at a fixed 15 s window and joins on word overlap, exactly the seam FluidAudio's merger owns today. Stage 2 bare shows what it does to the `wants` terms with no conditioning channel. Stage 3 raw is input to the cleanup matrix, not a score; produce it so the [e2e-combos](../assets/43-dictation-corpus/results/e2e-combos/README.md) table can add a column later.
- Three arms, same recordings: Voz; FluidAudio v0.15.5 + Parakeet v3 if `asr-replay --model-root` or the bakeoff's `run-fluid-audio.sh` can load the v3 artifact; and the existing `results/built-in` v2 numbers as the incumbent. Without the middle arm a Voz win is unattributable.
- Harness shape: a disposable SwiftPM executable under `assets/53-voz-engine-spike/`, following the [Cohere prototype](../assets/26-cohere-transcription-model/) and mirroring `asr-replay`'s contract exactly, so `score_corpus.py` scores it unchanged: `{id, transcript, latencyMs, outcome, audioSeconds}` per line, model loaded once, one excluded warmup, latency from samples-in-hand to final text via `transcribe(samples:)` at `voz.sampleRate`. Record cold and warm load, the one-time ANE specialization, and `getrusage` peak RSS the way the bakeoff did. Pin the SDK revision and the Hugging Face weights revision with byte counts and hashes.
- Voz has no language detection and no way to pass a language; it is 25-language multilingual with English at 7.36% on its own FLEURS protocol. Note whether any English-specific behavior exists in the SDK, and whether the multilingual vocabulary shows up as errors on the confusable-word entries where v2 already stumbles (colonel/kernel, cash/cache, daemon/demon).
- Licensing is a finding, not a footnote. The [Desert Ant Source-Available License 1.0](https://license.desertant.com/1.0) is not open source, requires a visible "Powered by Desert Ant Labs" attribution, and states the SDK sends a usage signal to count monthly active devices that the licensee may not disable. Establish from the SDK source what that signal is, where it goes, and when: an unsanctioned egress from the installed artifact collides with the map's controlled-network constraint no matter what the WER says. Parakeet's own CC-BY-4.0 attribution still applies on top.
- The runtime is the interesting part if the numbers are close: preallocated buffers, `outputBackings`, a 16-lane batched decode. Read enough of the Swift to say whether FluidAudio could adopt the same techniques, since that would be the cheaper route to the same speed.
- Write findings to `assets/53-voz-engine-spike/README.md` and the run directory to `assets/43-dictation-corpus/results/voz/` with a README in the same shape as the sibling runs; add the Voz row to the rollup's engine table. Recommend; do not decide. Adoption, if any, belongs to [Second engine](15-second-engine.md).

## Resolution

[Findings, pinned harness, reproduction and source audit](../assets/53-voz-engine-spike/README.md). Both arms ran all 97 entries across short-form, long-form, dictionary bare, polish raw and dictionary holdout on the existing recordings; the [Voz](../assets/43-dictation-corpus/results/voz/) and [FluidAudio v3](../assets/43-dictation-corpus/results/fluid-parakeet-v3/) rows are in the engine table. No production code or recording changed.

Voz scored **5.85% WER / 52.5 ms median**, versus FluidAudio v3 **2.93% / 55.4 ms** and shipping v2 **1.95% / 55 ms**. Five Voz errors truncate final words; a separate in-memory 500 ms zero-tail diagnostic recovers all five, reaching 3.41% / 55.3 ms, still behind v2. Bare dictionary recall was 2/18 for Voz, 3/18 for FluidAudio v3 and 5/18 for v2, all with zero exact trap hits. Holdout recall was 3/10, 2/10 and 5/10 respectively. Both new arms produced stage-3 raw files; FluidAudio v3 returned empty on the deliberately unfinished `polish-30` phrase.

Long-form: Voz **8.64% / 217.1 ms**, FluidAudio v3 **13.05% / 131.3 ms**, incumbent existing run **8.11% / 119.1 ms**. Curly-apostrophe normalization and delimiter-shaped speech absent from the literary references contaminate all three WERs, so they are not clean stitching scores. FluidAudio v3 additionally omits an entire passage in `longform-02` that v2 retains.

Voz fresh-path load was **16,169.8 ms**, reload **110.7 ms**, giving an estimated **16,059.1 ms one-time specialization tax**. Fresh-load peak RSS was **506.3 MiB**; the separately cached replay peaked at **75.5 MiB**. FluidAudio v3 loaded in **14,743.7 ms**, reloaded in **133.1 ms**, and peaked at **540.7 MiB including its slow first load**. These are Darwin process high-water marks, not total accelerator memory. Both consume the corpus's 16 kHz directly. SDK revisions, weight revisions, per-file byte counts/SHA-256 and input hashes are retained.

The license is source-available, requires discoverable linked Desert Ant credit and preserved Parakeet CC-BY-4.0 attribution, and **forbids tampering with usage reporting**. The shared SDK targets `https://platform.desertant.ai/api/v1/ingest` with generated persistent UUID, app/SDK identity and call counts, not audio/transcripts. **This pinned Voz path never invokes that client**, and debug-enabled runs emitted no ingest logs. Source inspection plus SDK diagnostics, not a packet capture, establishes the finding; reporting was not disabled. An implementation omission is not contractual offline permission, so controlled-network eligibility needs explicit vendor terms.

Recommend retaining v2 and independently profiling public Core ML buffer reuse/output-backing and batching techniques, not porting source-available SDK code. Voz's fused lane-batched decoder also requires a different export; the measured 3 ms short-form gain does not justify a rewrite, and it loses long-form latency. Neither tested v3 arm earns adoption on this corpus. The decision remains with [ticket 15](15-second-engine.md).
