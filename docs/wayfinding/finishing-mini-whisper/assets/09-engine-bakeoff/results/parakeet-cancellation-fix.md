# Parakeet cancellation patch probe

The pinned transcribe.cpp v0.1.3 one-shot Parakeet path polled cancellation only before inference. The experimental patch in [`../runtime-harnesses/transcribe-cpp/parakeet-cancellation.patch`](../runtime-harnesses/transcribe-cpp/parakeet-cancellation.patch) wires the existing GGML CPU/Metal backend abort mechanism into the Parakeet encoder, maps backend aborts to `TRANSCRIBE_ERR_ABORTED`, and polls the TDT host decoder between token steps.

Patch SHA-256: `6759ebf71e282e870b3b7d1e3c9498b6b0a010cd73f0eb7d933e20e83d372c7d`

Patched macOS XCFramework executable SHA-256: `3e16fecbcbb5624efc6e64c4f9dfea8e5b334fb0b9af0a2da61a048b10e422c9`

The 93.5-second fixture normally completes in roughly 915 ms. Cancellation requests throughout inference produced:

```text
request at 10 ms: aborted after 13.8 ms
request at 100 ms: aborted after 74.9 ms
request at 300 ms: aborted after 13.9 ms
request at 700 ms: aborted after 21.9 ms
request at 850 ms: aborted after 0.2 ms
request at 860 ms: aborted after 0.3 ms
request at 870 ms: aborted after 0.1 ms
request at 880 ms: completed-before-cancel after 915.1 ms
```

The final request was scheduled after inference had already finished. Among requests observed during inference, the worst measured cancellation response was 74.9 ms.

A full 24-fixture rerun retained the same 2.55% corpus WER and 171 ms warm median, versus 172 ms before the patch. The patch therefore showed no measurable quality or latency regression on the target M4 Pro.

This is a disposable proof, not production vendoring. It should be submitted upstream; if upstream declines it, MiniWhisper can carry the 138-line patch against its pinned XCFramework build.
