---
status: closed
type: research
claimed: subagent:prompt-prior-art
blocked-by: []
---

# Cleanup prompt prior art

## Question

What do shipping dictation apps actually put in their cleanup prompts? Survey the open-source ones whose prompts are readable (Hex, VoiceInk, Whispering/Epicenter, FluidVoice — GPL: describe, never copy — and any others with public prompts) and whatever the closed ones (Wispr Flow, Aqua Voice, Monologue, Superwhisper) disclose or leak through documentation. Extract: how they instruct punctuation/casing/disfluency handling, spoken-command conversion (explicit "comma"/"period"/"new line"), spoken-symbol conversion ("dash dash help" → `--help`), how they inject surrounding-text context and custom vocabulary, how they prevent the model answering the transcript instead of cleaning it, and how they constrain output shape (no fences, no commentary). Deliver a comparative table plus 2–3 candidate built-in prompts for MiniWhisper synthesizing the strongest patterns, ready for the [coded-speech corpus spike](43-coded-speech-corpus.md) to evaluate. Findings to `../assets/42-cleanup-prompt-prior-art.md`, cited; recommend, don't decide.

## Resolution

Findings and three original, GPL-clean corpus candidates are in [Cleanup prompt prior art](../assets/42-cleanup-prompt-prior-art.md). The recommendation is Candidate A as the conservative control, then an A/B/C replay against real coded dictation: all candidates carry a fixed text-filter boundary, tagged context/vocabulary as source rather than instructions, explicit dictated punctuation/symbol handling, and final-text-only output. The corpus, not this research, chooses the shipped wording.
