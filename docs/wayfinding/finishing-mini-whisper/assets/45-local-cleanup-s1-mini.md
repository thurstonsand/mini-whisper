# S1-mini spike findings

Spike code: [`spikes/s1-mini-cleanup/`](../../../spikes/s1-mini-cleanup/). Corpus: the first six dev-channel history entries (real dictations), plus targeted probes at the design's failure boundaries. All legs greedy/temp-0. Machine: M4 Pro, 48 GB.

## Latency

| Leg | Median | Min | Max | Footprint |
| --- | --- | --- | --- | --- |
| GGUF Q4_K_M, llama.cpp server | **222 ms** | 127 ms | 364 ms | 462 MiB |
| MLX, bf16 | 391 ms | 278 ms | 1174 ms | ~1.2 GB |
| gpt-5.6-luna via gateway (baseline) | 3295 ms | 1556 ms | 7962 ms | — |

15× faster than the gateway at Q4. GGUF beats MLX because bf16 pays ~2.4× the memory bandwidth; an MLX 4-bit conversion would likely close that gap, so the runtime choice is not decided by these two numbers alone — but both local legs are an order of magnitude inside the 3 s skip-reveal threshold, and either would make the Polishing pill phase nearly invisible.

## Quality

Strong at its trained task, on both runtimes:

- Disfluency and self-correction: `so um i need to like send the the report by uh friday no wait make that thursday` → `So I need to send the report by Thursday.` — identical to the frontier baseline.
- The styling axes work as documented: `casual` → `so i need to send the report by thursday`; `formal` expands contractions. `[Structure: lists]` and `[Context: email]` untested (not dictation-shaped).
- Questions stay questions. Inverse text normalization is aggressive: `five hundred milliseconds` → `500 milliseconds` (the frontier baseline kept the words; taste, not correctness).
- Filler-only input returns the empty string — documented, deliberate, and philosophically identical to the app's silence gate.
- More conservative than luna on judgment calls: left a sentence fragment luna smoothed; guessed `open app` → `Open App` (GGUF) where MLX chose `an open app`.

## The gaps that make it a tier, not a drop-in

1. **Coded speech fails**: `run swift test dash dash filter cleanup comma then uh report back` → `run swift test -dash -filter cleanup, then report back.` The gateway with the shipped prompt produces `swift test --filter cleanup,` correctly. S1-mini was not trained for spoken-symbol conversion, and it cannot be taught: the system prompt is fixed.
2. **No prompt surface at all**: no dictionary vocabulary, no field context, no additional instructions. The control line's three enumerated axes are the entire steering mechanism. The pane's custom-instructions field must grey out for this engine; styling becomes a radio (casual / semi-formal / formal).
3. **Empty output is valid here**: the package's degeneracy rule treats empty-after-shaping as failure (correct for chat models); a local S1-mini engine must treat empty as "nothing worth delivering" instead — closer to the gate's rejection than to a cleanup failure.
4. English only; inputs capped ~1,000 tokens (chunking needed for very long latches).

## Other facts for the integration decision

- License: Apache 2.0 + naming clause — must render as "S1-mini" by "Superwhisper", exact capitalization, wherever used. Attribution surface like Parakeet's CC-BY.
- Provenance: fine-tune by Superwhisper (US) on Qwen3-0.6B (Alibaba). The user's provenance rule ("made in USA/Europe") is not cleanly satisfied by the base model; flagged, undecided.
- Runtime candidates: llama.cpp (GGUF is the vendor-shipped on-device format; Whispering precedent covers local GGUF inference) vs MLX (needs a 4-bit conversion to compete; unallowlisted) vs Core ML (cleanest posture, most engineering). User has since relaxed the MLX/GGUF distinction — choose easiest-and-most-performant.
- The input format is load-bearing: exact system prompt, control line, `enable_thinking=false`. Every integration bug traces to one of those (vendor's own words, and our first blank outputs confirmed it).
