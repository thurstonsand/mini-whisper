---
status: closed
type: grilling
blocked-by: [4, 5, 6, 7, 9, 10]
---

# MVP spec

## Question

Fold every resolved ticket into one accepted design doc — the map's destination. A `grill-me` session that starts at Gate 1 only to sweep leftovers (interfaces between packages and clients, test seams, permission onboarding order), then Gate 2: a design doc in `docs/designs/` covering the full MVP vertical — hotkey pipeline, capture, silence rejection, engine, delivery, UX states, distribution — cut into functional slices, each independently demonstrable. Gate 3 execution planning happens in that doc per `grill-me`, outside this map.

## Resolution

The accepted design doc is [docs/designs/01-mvp.md](../../../designs/01-mvp.md) — the map's destination. Gate 1 swept the leftovers with Thurston: FluidAudio's `VadManager` replaces whisper.cpp's Silero for the gate (thresholds re-derived against the bakeoff corpus before the raw fixtures are deleted — whisper.cpp leaves the dependency set entirely); model acquisition is a consent-gated onboarding download of the pinned Parakeet v2 revision; the TCC permission set is proven empirically when the tap and paste paths land (a Phase 0 spike was built and deliberately discarded); App Sandbox dropped, Hardened Runtime kept; settings JSON is `{ hotkey, soundsEnabled }`; no voice audio is ever committed — manifests, scripts, and aggregates are the reproduction recipe. FluidAudio v0.15.5 formally joins the dependency set (Renovate-tracked; every bump gates on dependency review + regression corpus), Parakeet's CC-BY-4.0 attribution ships in README and the about surface, and post-MVP stake #5 is reworded to "second engine / fallback hardening." Gate 3 cut the build into nine phases, each owning one demonstrable surface; Phase 0 (agent-ready repo) is already executed and reviewed.
