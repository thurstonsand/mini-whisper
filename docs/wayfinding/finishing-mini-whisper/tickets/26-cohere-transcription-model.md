---
status: closed
claimed: subagent:gpt-5.6-sol
type: research
blocked-by: [8]
---

# Cohere's transcription model: precedent, prototype, integration

## Question

Cohere has a transcription model that is reportedly worth hearing about. Establish three things in order: what it actually is, whether Whispering already uses it, and what integrating it into MiniWhisper would cost. The middle question is the one that decides the other two — Whispering is allowlisted at work, so a capability it embeds is a capability MiniWhisper can argue for.

## Notes

- Answer "what is it" before anything else: hosted API only, or open weights that can run locally? Local weights make this an engine candidate under the existing `ASREngine` protocol and nothing more. A hosted API collides with two standing constraints and has to earn its way past both.
- The constraints it collides with: the map puts cloud transcription services out of scope ("speech-to-text stays local; only cleanup may cross the network, and only via the controlled gateway"), and the one sanctioned egress at work is an OpenAI-compatible gateway. Cohere's own endpoint is neither. Establish whether the gateway fronts it, whether Whispering reaches it directly, and what shape of egress would actually clear review.
- The Whispering question is evidence, not permission. Find out which version added it, what it talks to, and whether the allowlisted build has it enabled — a feature present in the upstream repository but absent from the reviewed artifact proves nothing.
- Prototyping should reuse the bakeoff shape rather than inventing one: the [engine bakeoff](09-engine-bakeoff.md) harness measured warm median latency, edit distance against a personal corpus, and RSS, and the personal corpus got the last word. A cloud engine adds a dimension the local bakeoff never had to measure — network latency and its variance under a real work connection, which is the thing that decides whether hold-to-talk still feels immediate.
- Integration cost is mostly known already: `ASREngine`'s protocol is model-agnostic by design and [second engine](15-second-engine.md) owns the fallback story, so a new engine is a conformance and a settings key. What is *not* known is what a network engine does to the vertical's failure modes — a dead gateway during a dictation has no local answer, and the pill's error taxonomy currently assumes failures are instant.
- Recording a deliberate exclusion is a valid outcome. If the answer is "hosted only, no gateway path, no Whispering precedent," say so plainly and the map's out-of-scope line stands unamended.
- Write findings as an asset (`assets/26-cohere-transcription-model.md`) per research-ticket convention and link it from the resolution.

## Resolution

[Cohere Transcribe is an open-weight Apache-2.0 model that can run locally](../assets/26-cohere-transcription-model/README.md), so the investigation reached Phase 3 rather than taking the hosted-only early escape. Whispering supplies no precedent: Cohere is absent from its source and shipped v7.11.0 artifact, and the only upstream record is an open feature request.

The pinned FluidAudio/Core ML harness was built and smoke-tested, but the required same-corpus comparison could not run because all 24 historical private WAVs are gone; only their manifest and prior Parakeet aggregates remain. A separate 27-file, 414.5-second private smoke run measured 532 ms warm p50, 1,599 ms p95, 2,298 ms worst case, and 12,135 MiB peak process RSS, versus Parakeet's controlled 98 ms p50, 222 ms p95, and 170 MiB later-process RSS. Its references were unavailable, so no Cohere WER is claimed.

The [public-accuracy addendum](../assets/26-cohere-transcription-model/README.md#addendum-public-accuracy-evidence-after-the-private-corpus-loss) changes the disposition to **revisit later while excluding the current artifact from adoption**. Open ASR shows a real but version-sensitive 0.19–0.63-point average WER advantage over v2, and a full public FluidAudio Core ML LibriSpeech archive measures Cohere at 2.07% macro versus v2 at 2.57%; independent and community evidence is mixed on more dictation-like audio. That gain does not currently outweigh a 434 ms median / 1,377 ms p95 hold-release tax, a 2.19 GB artifact, roughly 12 GB peak RSS, ambiguous converted-artifact licensing, no genuine streaming, and no Whispering precedent. Retain Parakeet v2 now; rerun Cohere when a faster, lower-memory Apple artifact or a deliberately re-baselined private dictation corpus can test whether its clean-speech, punctuation, and proper-noun advantages survive MiniWhisper's domain. Hosted Cohere remains outside the local-STT and controlled-gateway lines.
