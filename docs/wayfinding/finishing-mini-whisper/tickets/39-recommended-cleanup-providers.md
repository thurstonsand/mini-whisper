---
status: open
type: grilling
blocked-by: [18]
---

# Recommended cleanup providers: a shortlist over the custom endpoint

## Question

Make picking a good cleanup setup easy: a curated shortlist of well-known providers/models ("recommended" cleanups) layered over the existing custom-endpoint surface, which always remains. What earns a spot on the shortlist is performance-test-driven — the [benchmark harness](../assets/38-cleanup-model-benchmark.md) and real perf runs feed it. Design the pane UX (how a recommendation prefills endpoint/model, how it coexists with Custom), the update story for the list, and the criteria for inclusion. Depends on the shipped cleanup pass and on [native endpoints research](40-native-llm-endpoints.md) if provider-specific APIs join the menu.

## Scope notes (2026-08-20, user)

- The shape is **presets**: well-known sources — Groq, Cerebras, and a local option like "S1-mini" by "Superwhisper" ([ticket 45](45-local-cleanup-s1-mini.md)) — that prefill or replace the endpoint/model surface, with Custom always remaining.
- Presets open the door to **per-preset custom prompts**: a model-specific built-in prompt (or prompt fragment) where a model needs one — S1-mini's fixed control-line format is the extreme case; a fast host's quirks (lowercased first words, typographic hyphens) could be patched per-preset without touching the shipped default.
- First measured runs (in the [benchmark asset](../assets/38-cleanup-model-benchmark.md)): Cerebras gpt-oss-120b ~394 ms is the leading full-contract fast candidate; Cerebras gemma-4-31b deterministically hallucinates dictionary terms and is disqualified; Groq gpt-oss-20b/120b ~700 ms; frontier gateway ~3 s and alone in passing all boundary probes.
