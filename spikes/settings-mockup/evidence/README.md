# Evidence

Screenshots that settled decisions in [Settings UI](../../../docs/wayfinding/finishing-mini-whisper/tickets/16-settings-ui.md). Each was produced by compiling a variant of the mock-up and photographing it, so the conclusions rest on rendered pixels rather than on reasoning about documentation. Kept because the findings outlive the variants that proved them.

## Liquid Glass review

| file | what it shows |
| --- | --- |
| [radius-ladder.png](radius-ladder.png) | The system's own selection highlight above hand-drawn radii 4, 6, 8, 10, 12. Radius **8** matches; the 6 that had been shipping is visibly tighter, and 12 is too round. |
| [radius-mismatch-in-situ.png](radius-mismatch-in-situ.png) | Hover, copied, and system selection forced onto adjacent History rows. The mismatch is invisible in isolation and obvious side by side, which is why it survived several passes. |
| [banner-safeareainset.png](banner-safeareainset.png) → [banner-safeareabar.png](banner-safeareabar.png) | The History caption before and after `safeAreaBar`. The replacement supplies its own material and separator, so `.background(.bar)` and `Divider()` came out. |
| [glasseffect-on-content.png](glasseffect-on-content.png) | `glassEffect` applied to History rows. It renders as a stray grey outline and nothing else — the HIG's "don't use Liquid Glass in the content layer" made visible rather than quoted. |
| [listrowbackground-rejected.png](listrowbackground-rejected.png) | `.listRowBackground` tested as the native alternative to the hand-drawn hover fill. It is worse: a full-bleed square band that swallows the separators and loses the hover fill entirely. Combined with `hoverEffect` being unavailable on macOS, the hand-drawn highlight is the only option, not a workaround. |
| [menustyle-button.png](menustyle-button.png) | `MoreMenu` with `.menuStyle(.button)`, which borders the ellipsis to match neighbouring bordered buttons in `Form` rows. Left unapplied: History's hover accessory wants borderless, so adopting it means splitting the component. |

## Copied confirmation

Captured from a probe with every phase slowed down, so each step could be photographed unambiguously; the mock-up itself keeps its real timings of 1.2s held, 0.5s out, 0.25s in.

| file | what it shows |
| --- | --- |
| [fade-1-held.png](fade-1-held.png) | Held: tint, solid `✓ Copied`, no duration. |
| [fade-2-leaving.png](fade-2-leaving.png) | Leaving: tint paler, badge translucent, duration still absent. |
| [fade-3-returning.png](fade-3-returning.png) | Returning: tint gone, duration fading in. |

The point of the sequence is what it never shows — the two texts sharing the slot. Crossfading them superimposed `Copied` over `11.8s` at half opacity for the length of the transition, which is why the confirmation leaves in two transactions instead of one.
