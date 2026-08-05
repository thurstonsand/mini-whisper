---
status: open
type: grilling
blocked-by: [8]
---

# Streaming transcription and the live-text pill

## Decided while inventorying settings

**Streaming is not a setting.** It is selected by gesture, following Aqua Voice: hold does not stream, latch does. So this ticket inherits a constraint rather than a preference toggle — both paths must exist and the engine must support batch and live modes side by side.

The division falls out of what the two gestures already mean. Hold is a short utterance the user is waiting on, where live text is noise and only the final result matters. Latch is hands-free long-form, where the user has stopped watching the keyboard and live text is the only feedback there is. The pill already distinguishes the two states visually, so the surface for this exists.

## Question

Excluded from the stakes, reopened by the Parakeet-first verdict: FluidAudio has streaming ASR paths whisper.cpp lacks. Decide whether live streaming transcription is worth its complexity, and design the pill's grow-into-live-text affordance recorded in the UX ticket (plus click-drag repositioning and the destination-app label, deferred there).
