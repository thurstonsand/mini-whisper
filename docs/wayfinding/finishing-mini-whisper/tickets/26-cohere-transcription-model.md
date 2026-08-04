---
status: open
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
