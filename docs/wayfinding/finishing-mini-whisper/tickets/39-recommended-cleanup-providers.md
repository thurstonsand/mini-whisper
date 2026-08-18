---
status: open
type: grilling
blocked-by: [18]
---

# Recommended cleanup providers: a shortlist over the custom endpoint

## Question

Make picking a good cleanup setup easy: a curated shortlist of well-known providers/models ("recommended" cleanups) layered over the existing custom-endpoint surface, which always remains. What earns a spot on the shortlist is performance-test-driven — the [benchmark harness](../assets/38-cleanup-model-benchmark.md) and real perf runs feed it. Design the pane UX (how a recommendation prefills endpoint/model, how it coexists with Custom), the update story for the list, and the criteria for inclusion. Depends on the shipped cleanup pass and on [native endpoints research](40-native-llm-endpoints.md) if provider-specific APIs join the menu.
