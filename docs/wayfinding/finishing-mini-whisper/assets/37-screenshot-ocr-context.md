# Screenshot/OCR context capture

Research date: 2026-08-17. This scouts a later enrichment for [LLM cleanup](../tickets/18-llm-cleanup.md); it does not add it to cleanup's first release. No capture probe was run: granting Screen Recording or causing a system prompt would violate this ticket's background-only constraints.

## Recommendation

**Keep screenshot/OCR outside the first cleanup pass, but retain it as a credible later experiment.** It can supply local visual text where the existing focused-field Accessibility (AX) contract is absent or dishonest, most notably canvas editors. It is not a replacement for that contract: OCR supplies a fallible hint about visible pixels, not document text or caret semantics.

If it is explored, make it a separately enabled, default-off context source with an explicit Screen Recording/privacy explanation. Capture a small screen-space rectangle around the AX focused element, run OCR entirely locally, immediately discard the image, and send only a strictly bounded OCR-text excerpt to the controlled OpenAI-compatible gateway. Never fall back automatically to a whole display, and never let unavailable, slow, or failed visual context delay raw delivery. The existing `transcribe → cleanup → deliver` backstop must remain intact.[^cleanup]

The stronger product question is privacy, not framework availability. A controlled network narrows the recipient but does not make nearby passwords, chat, source, customer data, or unrelated windows safe to transmit as context.

## Mechanism

### The smallest capture that current APIs permit

`SCScreenshotManager` is the one-shot ScreenCaptureKit API: `captureImage(contentFilter:configuration:)` returns a `CGImage` asynchronously without creating an `SCStream`, available from macOS 14.[^screenshot-manager][^wwdc-screenshot] It supports two relevant capture shapes:

| Shape                     | API                                                                                                | What it really acquires                                                    | Recommendation                                                                                                                                                                                                                                            |
| ------------------------- | -------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Focused visual region** | `SCScreenshotManager.captureImage(in: focusedRect)` (macOS 15.2+)                                  | The specified display-space rectangle, across displays if necessary.       | **Preferred.** Use AX only to obtain the current focused element/window geometry, expand it by a small fixed margin, and capture that rectangle. It minimizes pixels acquired, not merely pixels later uploaded.[^rect-capture]                           |
| **One window**            | `SCShareableContent` → `SCContentFilter(desktopIndependentWindow:)` → one-shot capture (macOS 14+) | The whole selected `SCWindow`.                                             | Compatibility fallback only. Apple documents that `SCStreamConfiguration.sourceRect` is ignored for a single-window capture, so an apparent near-caret crop is actually a full-window acquisition followed by a local crop.[^window-filter][^source-rect] |
| **One display**           | Display `SCContentFilter`, then one-shot capture                                                   | The whole display unless its display-relative source rectangle is applied. | Do not use automatically. It acquires unrelated material and does not improve a focused-context contract enough to earn that exposure.[^capture-sample]                                                                                                   |

There is no ScreenCaptureKit “frontmost/focused window” selector. `SCShareableContent` offers shareable windows and their owner/window identifiers, while AX provides the focused window of an application.[^shareable-content][^ax-focused-window][^window-id] A macOS 14 whole-window path consequently needs a carefully tested bridge, not “the first on-screen window for the frontmost PID”; one process can own document, inspector, dialog, and utility windows. The macOS 15.2 rectangle API avoids that identity problem when AX can produce focused-element geometry.

Do **not** use a cursor location as a silent fallback. It can be in a different window than the insertion point. If AX cannot provide a trustworthy location, classify visual context as unavailable rather than widening collection to a screen or window. The existing focused-field reader already identifies this class of unavailable target.[^context-capture]

### OCR

Vision text recognition is local. Apple says all Vision text-recognition processing happens on the device.[^vision-guide] The current Swift-concurrency request is `RecognizeTextRequest` (macOS 15+); it produces `RecognizedTextObservation`s directly through `perform(on:)`. `VNRecognizeTextRequest` remains the compatible macOS 10.15+ API.[^recognize-text][^vision-swift]

For a static UI crop, start with `.accurate`, explicit English recognition languages, language correction, and a small `customWords` list drawn from the already-local dictionary. Apple describes `.fast` as character detection plus a smaller model, while `.accurate` recognizes strings/lines before words and sentences; the latter is the appropriate quality-first path for an occasional cleanup hint. Both requests expose confidence and geometry, so low-confidence lines, tiny text, and text outside a fixed near-focus band can be omitted instead of presented to cleanup as fact.[^vision-guide]

`RecognizeDocumentsRequest` is a macOS 26 document-layout API for tables, lists, and paragraphs. It is unnecessary for a bounded nearby-text hint; revisit only if a future feature needs structural document interpretation rather than terms/casing.[^recognize-documents]

### Accuracy and latency evidence

Apple documents the qualitative accuracy/speed tradeoff and per-observation confidence, but does not publish screenshot character/word-error figures or a named Apple-silicon latency SLA. Do not convert a confidence score into an accuracy guarantee.[^vision-guide]

The useful public measurements are indicative rather than a product promise:

| Stage                            | Evidence                                                                                                                                                                                                                        | Planning interpretation                                                                                                           |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| One 1080p ScreenCaptureKit image | The `screencapturekit-rs` benchmark guide reports a 20–50 ms typical `CGImage` screenshot range and 5–15 ms to enumerate shareable content. It is a third-party range, not a named-machine result.[^sck-bench]                  | The rect route avoids shareable-content enumeration; a full-window route does not.                                                |
| Vision text recognition          | `ocrmac` measures its Python/PyObjC wrapper on an M3 Max at 207 ms mean for Vision `.accurate` and 131 ms for `.fast`. Its image and wrapper overhead are not specified, so this is an order-of-magnitude result only.[^ocrmac] | Budget roughly 150–300 ms for one small accurate OCR pass on current Apple silicon, then measure MiniWhisper's native Swift path. |

That work can begin at recording start and race transcription, so it need not add to perceived delivery time. But cleanup must proceed with the existing field context alone if OCR is not ready by the cleanup request; it must never wait for visual context. Before adopting it, benchmark representative, _pre-supplied_ screenshots for character error rate and proper-noun recall across Retina and non-Retina scale, light/dark themes, small code fonts, terminals, canvas editors, and occlusion. Canned images test Vision without acquiring a user's screen.

Open-source precedent is consistent with the shape, not a quality claim: Ambient Voice uses ScreenCaptureKit plus Vision OCR around a focus region, defaults its `context_ocr_enabled` setting to false, and documents Screen Recording as optional while polish still works without it.[^ambient-code][^ambient-config] Its macOS 14 implementation also demonstrates the `sourceRect`/window-filter trap above, so it must not be copied blindly.

## Permission cost and degradation

Screen Recording is a new capability channel. It is independent of MiniWhisper's existing Microphone, Input Monitoring, Accessibility/Paste Access grants; Accessibility may help locate a crop, but it does not authorize pixels. Apple’s current ScreenCaptureKit overview says to request Screen Recording permission and supply `NSScreenCaptureUsageDescription`.[^sck-overview] Its sample says first capture prompts and the app must restart after the grant before capture works.[^capture-sample]

Use the CoreGraphics capability probes, available from macOS 10.15:

```swift
CGPreflightScreenCaptureAccess() // check only
CGRequestScreenCaptureAccess()   // request; may prompt
```

The SDK labels the first as the check for existing screen-capture access and the second as a potentially prompting request.[^cgwindow-header] `preflight == false` deliberately does not distinguish first-run from denied/revoked. Model that distinction in MiniWhisper's own UI only from whether it previously made the explained request; do not infer it from the Boolean or spin a prompt loop.

Recommended future state machine:

1. **Off:** visual context’s own toggle is off. Do not preflight, request, or enumerate screen content.
2. **Enable requested, unavailable:** explain the exact capture boundary and gateway egress first; only then invoke `CGRequestScreenCaptureAccess()`. Record the local request attempt.
3. **Granted:** `CGPreflight…` succeeds. Capture may run, but recheck when the app becomes active and treat capture errors as revocation/unavailability. Do not cache approval as permanent.
4. **Not available:** after denial, revocation, or capture failure, leave cleanup/dictation on the existing path and offer a quiet Settings repair row. Never reprompt on a dictation.

There **is** a lighter scoped route, but not for automatic current-window capture: macOS's `SCContentSharingPicker` lets a person choose content and then authorizes that selection for the capture duration without a separate Screen Recording permission.[^apple-privacy-picker] That picker is an explicit, visible sharing session, appropriate for user-initiated screen sharing or a chosen persistent source. It cannot silently follow whatever is focused on every dictation, so it is not a substitute for the broad TCC grant this feature needs. The macOS 15.2 one-shot rect API removes stream setup, not the permission boundary.

## Privacy contract

The consent copy must say all four facts together:

- **What is acquired:** one screenshot rectangle near the focused writing area at dictation time; it can include text other than the dictated transcript.
- **What stays local:** pixels and Vision OCR processing. The bitmap is held only long enough to OCR, then discarded; do not write a PNG, history attachment, debug log, or crash-report attachment.
- **What leaves the Mac:** only selected OCR text, bounded in characters/tokens and labeled to the cleanup prompt as untrusted visual context, plus the existing transcript/field context. The raw screenshot must never be a gateway request field.
- **What controls it:** a default-off visual-context toggle, the separate macOS Screen Recording switch, clear live unavailable/degraded state, and an obvious off switch. A sensitive-app denylist or an allowlist can be evaluated later, but neither replaces the primary opt-in.

Local OCR narrows the risk; it does not erase it. Extracted text may still contain a password, API key, private message, health data, or another person's document. Sending fewer pixels is insufficient if the text itself is then sent to the cleanup endpoint. Bound it aggressively, exclude suspected secret-looking lines only as defense in depth, and make the gateway/retention rules explicit in the feature disclosure. The cleanup prompt must also say context is reference material, never content to invent or paste.

Public competitors treat this as a separate gate:

- **Aqua Voice** says Deep Context reads what is on screen, stays off until enabled, and is not stored; it says Privacy Mode controls transcript retention. Its terminal guide says Deep Context can see visible paths and flags.[^aqua-faq][^aqua-terminal] Aqua does not publish a client implementation, crop bounds, whether it sends pixels versus OCR text, or a per-target fallback. Its marketing is evidence for the capability and opt-in posture, not a safe implementation blueprint.
- **Wispr Flow** is more specific: its security FAQ says AX context is separately toggled and default on, but full-display Screen OCR is default off; it captures the display containing the cursor only when both toggles are on. It also says screen context is stripped when Privacy Mode is on/Cloud Sync is off, while it may persist alongside a transcript otherwise.[^wispr-security] That is strong evidence that screen context needs its own retention disclosure. MiniWhisper should be stricter: no raw screenshot egress at all.
- **Monologue** labels Screen Recording optional for richer Deep Context, offers “Not now,” and keeps ordinary dictation usable without it.[^monologue-setup] That is the correct degradation posture.

## Coverage versus AX

This source complements, rather than broadens, the accepted focused-field contract. The August AX probe found Google Docs' canvas editor exposes only a zero-width-character text sink while Terminal.app/nvim and Ghostty expose a visible **grid**, not document semantics.[^context-capture]

| Target gap                                             | What screenshot/OCR adds                                                                                                                                                              | What it cannot honestly claim                                                                                                                                                                                                                                   |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Canvas editors, including Google Docs**              | It can read the text visibly painted in the editor, including nearby names and prior prose, where AX reads the sink rather than the document. This is the clearest incremental value. | No document model, selection, caret offset, hidden text, or proof that a recognized line is adjacent to the actual insertion point. Treat it only as a casing/proper-noun hint.                                                                                 |
| **Terminal/TUI with weak or absent AX**                | It can recover visible command/path/flag text if AX exposes nothing. Aqua publicly claims this kind of terminal context.[^aqua-terminal]                                              | It sees the same volatile screen-grid-shaped material as a human. It does not recover shell history, a buffer, nvim's document, or trustworthy cursor semantics. Where AX already exposes the grid, OCR adds little coverage and introduces recognition errors. |
| **Native text fields and well-exposed web editors**    | Usually none worth its cost; AX supplies exact text/range/caret context without pixels or a new grant.                                                                                | OCR is not a higher-fidelity replacement for structured text.                                                                                                                                                                                                   |
| **Images, diagrams, offscreen content, obscured text** | At most visibly rendered textual labels.                                                                                                                                              | OCR does not read nontext semantics, content outside the rectangle/viewport, or anything covered by another window.                                                                                                                                             |

The future experiment should therefore run OCR only where AX context is unavailable or classified as an unsuitable sink/grid, not redundantly for every dictation. It should preserve target identity and source provenance (`field` versus `visual`) so cleanup can discount visual text. That gives the later grilling session an honest comparison: a privacy-costly hint for a narrowly defined gap, not “screen-wide awareness.”

## Sources

Primary sources:

- Apple, [ScreenCaptureKit overview](https://developer.apple.com/documentation/screencapturekit), [Capturing screen content in macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos), and WWDC23, [What’s new in ScreenCaptureKit](https://developer.apple.com/videos/play/wwdc2023/10136/).
- Apple, [What’s new in privacy](https://developer.apple.com/videos/play/wwdc2023/10053/) (the system picker’s scoped authorization); [SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager); [rect capture](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage%28in%3Acompletionhandler%3A); [single-window filter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init%28desktopindependentwindow%3A%29); and [sourceRect](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/sourcerect).
- Apple, [Recognizing Text in Images](https://developer.apple.com/documentation/vision/recognizing-text-in-images), [RecognizeTextRequest](https://developer.apple.com/documentation/vision/recognizetextrequest), [RecognizeDocumentsRequest](https://developer.apple.com/documentation/vision/recognizedocumentsrequest), and WWDC24, [Discover Swift enhancements in the Vision framework](https://developer.apple.com/videos/play/wwdc2024/10163/).
- Aqua Voice, [FAQ](https://aquavoice.com/info/faq), [privacy policy](https://aquavoice.com/info/privacy), and [Claude Code/terminal guide](https://aquavoice.com/blog/voice-dictation-claude-code); Wispr Flow, [security and compliance FAQ](https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq); Monologue, [Mac setup](https://help.monologue.to/en/articles/14178193-quick-setup-guide).

Supporting, non-primary measurements/source precedent:

- `screencapturekit-rs`, [benchmark guide](https://github.com/doom-fish/screencapturekit-rs/blob/2a9f13bcbead/docs/BENCHMARKS.md); `ocrmac`, [M3 Max timing note](https://github.com/straussmaximilian/ocrmac/blob/a38d01c65327/README.md#speed); Ambient Voice, [ScreenContextProvider](https://github.com/Marvinngg/ambient-voice/blob/0d6367d4c072/client/Sources/ScreenContextProvider.swift), [default configuration](https://github.com/Marvinngg/ambient-voice/blob/0d6367d4c072/client/Sources/RuntimeConfig.swift), and [permission documentation](https://github.com/Marvinngg/ambient-voice/blob/0d6367d4c072/docs/configuration.md).

[^cleanup]: Parent-session Gate 1 context for ticket 18: cleanup has a 10-second raw-text fallback and must not add a delivery-blocking failure mode.

[^screenshot-manager]: [Apple: SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager).

[^wwdc-screenshot]: [Apple WWDC23, 9:44–12:55](https://developer.apple.com/videos/play/wwdc2023/10136/?time=584).

[^rect-capture]: [Apple: `captureImage(in:completionHandler:)`](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage%28in%3Acompletionhandler%3A).

[^window-filter]: [Apple: `SCContentFilter.init(desktopIndependentWindow:)`](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init%28desktopindependentwindow%3A%29).

[^source-rect]: [Apple: `SCStreamConfiguration.sourceRect`](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/sourcerect).

[^capture-sample]: [Apple: Capturing screen content in macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos).

[^shareable-content]: [Apple: SCShareableContent](https://developer.apple.com/documentation/screencapturekit/scshareablecontent).

[^ax-focused-window]: [Apple: `kAXFocusedWindowAttribute`](https://developer.apple.com/documentation/applicationservices/kaxfocusedwindowattribute).

[^window-id]: [Apple: `SCWindow.windowID`](https://developer.apple.com/documentation/screencapturekit/scwindow/windowid).

[^context-capture]: [MiniWhisper context-capture probe](20-context-capture.md), “Target matrix” and “Canvas editors: the Google Docs sink.”

[^vision-guide]: [Apple: Recognizing Text in Images](https://developer.apple.com/documentation/vision/recognizing-text-in-images).

[^recognize-text]: [Apple: RecognizeTextRequest](https://developer.apple.com/documentation/vision/recognizetextrequest).

[^vision-swift]: [Apple WWDC24, 11:49–16:24](https://developer.apple.com/videos/play/wwdc2024/10163/?time=709).

[^recognize-documents]: [Apple: RecognizeDocumentsRequest](https://developer.apple.com/documentation/vision/recognizedocumentsrequest).

[^sck-bench]: [`screencapturekit-rs` benchmark guide](https://github.com/doom-fish/screencapturekit-rs/blob/2a9f13bcbead/docs/BENCHMARKS.md).

[^ocrmac]: [`ocrmac` README, Speed](https://github.com/straussmaximilian/ocrmac/blob/a38d01c65327/README.md#speed).

[^ambient-code]: [Ambient Voice: `ScreenContextProvider`](https://github.com/Marvinngg/ambient-voice/blob/0d6367d4c072/client/Sources/ScreenContextProvider.swift).

[^ambient-config]: [Ambient Voice: configuration](https://github.com/Marvinngg/ambient-voice/blob/0d6367d4c072/docs/configuration.md).

[^sck-overview]: [Apple: ScreenCaptureKit overview](https://developer.apple.com/documentation/screencapturekit).

[^cgwindow-header]: macOS 26.5 SDK, [`CGWindow.h`](https://github.com/apple-oss-distributions/CG/blob/main/CGWindow.h) declares both APIs as available from macOS 10.15; the installed SDK was inspected during this research. Apple’s rendered symbol pages are [preflight](<https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess()>) and [request](<https://developer.apple.com/documentation/coregraphics/cgrequestscreencaptureaccess()>).

[^apple-privacy-picker]: [Apple WWDC23, “What’s new in privacy,” 5:44–7:26](https://developer.apple.com/videos/play/wwdc2023/10053/?time=344).

[^aqua-faq]: [Aqua Voice FAQ](https://aquavoice.com/info/faq).

[^aqua-terminal]: [Aqua Voice: Voice dictation for Claude Code](https://aquavoice.com/blog/voice-dictation-claude-code).

[^wispr-security]: [Wispr Flow security and compliance FAQ](https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq).

[^monologue-setup]: [Monologue: Set up on Mac](https://help.monologue.to/en/articles/14178193-quick-setup-guide).
