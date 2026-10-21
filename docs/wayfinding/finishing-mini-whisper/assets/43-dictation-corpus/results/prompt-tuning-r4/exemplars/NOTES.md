# Cleanup-prompt exemplar research

Checked 2026-08-21. This memo keeps the licence boundary deliberately hard: only MIT prompts are copied into the adjacent machine-readable `.txt` files. GPL, AGPL, unknown, and non-permissive prompts are characterized but never quoted. URLs below pin the exact inspected commit.

## Re-check of the surveyed projects

### VoiceInk

- **Repo / inspected commit:** [`Beingpax/VoiceInk@fda316996d87bc0c7b68d11a741b5c5aec8d8617`](https://github.com/Beingpax/VoiceInk/tree/fda316996d87bc0c7b68d11a741b5c5aec8d8617)
- **Licence:** GPL-3.0-only. [LICENSE:1-29](https://github.com/Beingpax/VoiceInk/blob/fda316996d87bc0c7b68d11a741b5c5aec8d8617/LICENSE#L1-L29). No verbatim copy.
- **LLM cleanup:** yes, the enhancement system template remains in [AIPrompts.swift:4-52](https://github.com/Beingpax/VoiceInk/blob/fda316996d87bc0c7b68d11a741b5c5aec8d8617/VoiceInk/Models/AIPrompts.swift#L4-L52).
- **Change since `304db118f655`:** no template change. The one intervening commit changed model defaults and app icons, not `AIPrompts.swift`; the [pinned comparison](https://github.com/Beingpax/VoiceInk/compare/304db118f655...fda316996d87bc0c7b68d11a741b5c5aec8d8617) establishes this.
- **Register:** Markdown heading plus 16 dash rules, followed by two worked input/output examples. The rules are short, imperative clauses. It names the tagged inputs, says tagged text is data, preserves questions and commands instead of acting on them, enumerates punctuation and layout words, then ends with an output-only rule. This is operational documentation, but its executable portion is list-shaped rather than paragraph-shaped.

### Whispering / Epicenter

- **Repo / inspected commit:** [`EpicenterHQ/epicenter@abe10f3867e4e8b367bcc48d30ce69c8ed8c59da`](https://github.com/EpicenterHQ/epicenter/tree/abe10f3867e4e8b367bcc48d30ce69c8ed8c59da)
- **Licence:** AGPL-3.0-only for the Whispering app. [apps/whispering/LICENSE:1-12](https://github.com/EpicenterHQ/epicenter/blob/abe10f3867e4e8b367bcc48d30ce69c8ed8c59da/apps/whispering/LICENSE#L1-L12). No verbatim copy.
- **LLM cleanup:** yes. The Polish scaffold and dictionary combiner are in [build-system-prompt.ts:16-63](https://github.com/EpicenterHQ/epicenter/blob/abe10f3867e4e8b367bcc48d30ce69c8ed8c59da/apps/whispering/src/lib/operations/build-system-prompt.ts#L16-L63).
- **Change since `210c3d3691a0`:** no change to the builder or scaffold in the [pinned comparison](https://github.com/EpicenterHQ/epicenter/compare/210c3d3691a0...abe10f3867e4e8b367bcc48d30ce69c8ed8c59da). The current app licence is now explicitly AGPL at the app boundary, so its text is excluded even though the monorepo root is a licence index.
- **Register:** one opening anti-assistant paragraph, a user-editable directive slot, then three dash bullets. It is the tersest guard in the set: it calls the model a filter, treats the entire user message as dictated data, preserves questions and commands, and uses an output-only final bullet. It has no spoken-punctuation or layout conversion rule and no worked examples.

### FluidVoice

- **Repo / inspected commit:** [`altic-dev/FluidVoice@ab46bf3dd29fd33d79f9fed00172f51af3982625`](https://github.com/altic-dev/FluidVoice/tree/ab46bf3dd29fd33d79f9fed00172f51af3982625)
- **Licence:** GPL-3.0-only. [LICENSE:1-12](https://github.com/altic-dev/FluidVoice/blob/ab46bf3dd29fd33d79f9fed00172f51af3982625/LICENSE#L1-L12). No verbatim copy.
- **LLM cleanup:** yes. Current dictation prompt selection and built-in prompt body are in [SettingsStore.swift:844-1097](https://github.com/altic-dev/FluidVoice/blob/ab46bf3dd29fd33d79f9fed00172f51af3982625/Sources/Fluid/Persistence/SettingsStore.swift#L844-L1097).
- **Change since `b44a898c0749`:** the default cleanup body did not change in the [pinned comparison](https://github.com/altic-dev/FluidVoice/compare/b44a898c0749...ab46bf3dd29fd33d79f9fed00172f51af3982625). The changes add dictation finalization and spoken-send settings, plus private-model selection plumbing; they do not add a cleanup rule.
- **Register:** structured prose with labelled sections and many short directives. It has examples and explicit spoken punctuation and layout handling, but its separate deterministic formatter remains the primary symbol layer. The guard says cleanup is not answering and requests transformed text alone. Its detail level is higher than Whispering's, but its rules stay mostly single-purpose.

### Hex

- **Repo / inspected commit:** [`kitlangton/Hex@881c46f236f529a8f6c7eed61ed1f4cbca9ac267`](https://github.com/kitlangton/Hex/tree/881c46f236f529a8f6c7eed61ed1f4cbca9ac267)
- **Licence:** MIT. [LICENSE:1-22](https://github.com/kitlangton/Hex/blob/881c46f236f529a8f6c7eed61ed1f4cbca9ac267/LICENSE#L1-L22).
- **LLM cleanup:** no. Its transcription feature is deterministic postprocessing, including optional filler removal, remapping, lowercasing, and punctuation removal. [TranscriptionFeature.swift:441-503](https://github.com/kitlangton/Hex/blob/881c46f236f529a8f6c7eed61ed1f4cbca9ac267/Hex/Features/Transcription/TranscriptionFeature.swift#L441-L503).
- **Change since `881c46f236f5`:** none: the survey pin resolves to this same full HEAD commit. There is therefore no prompt to copy and no cleanup register to measure.

## New or newly useful OSS sources

### Quotable permissive exemplars

| Project | Why it qualifies | Prompt source and licence | Register |
| --- | --- | --- | --- |
| **Yappy** | VS Code dictation extension that calls Copilot to refine the raw transcription. | MIT [LICENSE:1-9](https://github.com/karandeepbhardwaj/Yappy/blob/e347f33a12a99a858afb88d4734c806b5ebb45b0/LICENSE#L1-L9); [prompt:4-31](https://github.com/karandeepbhardwaj/Yappy/blob/e347f33a12a99a858afb88d4734c806b5ebb45b0/src/llm/CopilotRefiner.ts#L4-L31); `yappy.txt`. | One two-sentence role statement, seven numbered rules, two examples, one output-only sentence. Rules are direct imperatives. It has no injection boundary, and it asks mixed language to become English. Spoken punctuation and layout are implicit under grammar and structure. |
| **Whisper Dictate** | Windows dictation app with a local OpenAI-compatible cleanup endpoint, including LM Studio. | MIT [LICENSE:1-21](https://github.com/dancwilliams/whisper-dictate/blob/ce4b65f5350a2116146fab26762f0b161c2adc28/LICENSE#L1-L21); [default prompt:27-65](https://github.com/dancwilliams/whisper-dictate/blob/ce4b65f5350a2116146fab26762f0b161c2adc28/whisper_dictate/config.py#L27-L65); `whisper-dictate.txt`. | Section headings plus 18 dash rules and a single wrong-versus-correct example. It repeatedly uses terse imperatives and an explicit no-answer rule. It allows list/paragraph formatting and emoji conversion; spoken punctuation is not enumerated. The dense headings make it read more like a checklist than prose. |
| **Whisper Local** | Windows/macOS dictation app with an opt-in local Ollama polish after deterministic formatting. | MIT [LICENSE:1-22](https://github.com/drajb/whisper-local/blob/0138c6b19af57d36ad79809d1888035eca7b22b3/LICENSE#L1-L22); [default template:484-494](https://github.com/drajb/whisper-local/blob/0138c6b19af57d36ad79809d1888035eca7b22b3/src/whisper_key/config.defaults.yaml#L484-L494); `whisper-local.txt`. | Four short imperative sentences, 21 words before the transcript placeholder. No examples, no anti-answer guard, and no spoken-layout instruction because the deterministic prepass owns those conversions. This is the clearest example of the minimal register. |
| **OpenWhispr** | Mature cross-platform dictation app with separate cleanup and command modes. | MIT [LICENSE:1-21](https://github.com/OpenWhispr/openwhispr/blob/8b77a599ce91172e421ca0cd4f8bd5fd3cbae47f/LICENSE#L1-L21); [English cleanup prompt](https://github.com/OpenWhispr/openwhispr/blob/8b77a599ce91172e421ca0cd4f8bd5fd3cbae47f/src/locales/en/prompts.json#L2); `openwhispr.txt`. | Headed, 8-bullet checklist with four worked examples. Its anti-answering boundary is unusually explicit, including attempts to alter the prompt. It enumerates punctuation, layout, numeric conversion, and limited optional formatting. Sentence length is moderate, but the rule units remain compact. |
| **Voicebox** | Local LLM refinement with the three default-on toggles assembled into the captured text file. | MIT [LICENSE:1-21](https://github.com/jamiepine/voicebox/blob/51f49dea198384b4eb6087b72c17057c6eb1c1cd/LICENSE#L1-L21); [sections and default assembly:140-195](https://github.com/jamiepine/voicebox/blob/51f49dea198384b4eb6087b72c17057c6eb1c1cd/backend/services/refinement.py#L140-L195); `voicebox.txt`. | The counterexample. It uses 19 bullets, three examples, and explicit technical-symbol rules, but its prose sentences are often long and clause-bearing. The anti-answer guard is strong and repeated. It shows that list structure alone does not prevent documentation register. |

### Checked but not exemplars

- **Handy** is a high-use MIT offline STT app, but its current transcription manager imports deterministic normalization and filler removal rather than an LLM cleanup call. [MIT LICENSE](https://github.com/cjpais/Handy/blob/0e5036721ef6f26c3b89ab31bc10cd2ffd6096fb/LICENSE#L1-L21); [transcription manager](https://github.com/cjpais/Handy/blob/0e5036721ef6f26c3b89ab31bc10cd2ffd6096fb/src-tauri/src/managers/transcription.rs). No LLM cleanup prompt.
- **Vibe** is MIT and has LLM prompt templates, but its built-ins summarize, turn transcripts into meeting notes, translate, or write articles, rather than pasteable transcript cleanup. [MIT LICENSE](https://github.com/thewh1teagle/vibe/blob/949149631cdc58ef5644495f3db9701231baf17b/LICENSE#L1-L21); [templates](https://github.com/thewh1teagle/vibe/blob/949149631cdc58ef5644495f3db9701231baf17b/desktop/src/lib/prompt-templates.ts#L1-L29). No cleanup exemplar.
- **Whisper Writer** is GPL-3.0-only and its last HEAD is `370333b115417b03bf51c9f5bffd6578ecf6986e`; its source tree has ASR postprocessing, not an LLM cleanup component. [LICENSE](https://github.com/savbell/whisper-writer/blob/370333b115417b03bf51c9f5bffd6578ecf6986e/LICENSE#L1-L12); [tree](https://github.com/savbell/whisper-writer/tree/370333b115417b03bf51c9f5bffd6578ecf6986e/src). No prompt is reproduced.
- **andrew99666/whisper-dictate** does have Gemini polish prompts, but its current licence is PolyForm Noncommercial 1.0.0, not permissive. It is consequently treated as restricted and omitted from the text files. [LICENSE:1-12](https://github.com/andrew99666/whisper-dictate/blob/25c32ea7f436d4a1a69b8ffec32934282a6dff70/LICENSE#L1-L12); [LLM implementation](https://github.com/andrew99666/whisper-dictate/blob/25c32ea7f436d4a1a69b8ffec32934282a6dff70/llm.py).
- `heyito/ito` and `owhisper/owhisper` did not resolve as public GitHub repositories when checked, so no source-backed prompt claim is made. Search-result-only candidates `tristan-mcinnis/local-dictation` and `Quobi-AI/Quobi` likewise returned no public GitHub API resource at check time. A search snippet is not evidence. Sensible policy, despite the internet's repeated attempt to make it otherwise.

## Register findings

The comparison uses the same mechanical measure for every captured prompt: ASCII word tokens divided by sentences ending in `.`, `!`, or `?`; bullets count lines beginning with a dash or a numbered marker. This understates fragments and headings, so it favors prose. The source extracts are the five adjacent `.txt` files; MiniWhisper's measurement is `CleanupPrompt.swift:48-62`.

| Prompt | Words | Terminal-punctuation sentences | Words / sentence | Bullets | Worked examples |
| --- | ---: | ---: | ---: | ---: | ---: |
| MiniWhisper current `builtIn` | 523 | 26 | **20.1** | 0 | 3 inline |
| Yappy | 205 | 23 | 8.9 | 7 | 2 |
| Whisper Dictate | 216 | 9 | 24.0 | 18 | 1 |
| Whisper Local | 21 | 3 | 7.0 | 0 | 0 |
| OpenWhispr | 338 | 22 | 15.4 | 8 | 4 |
| Voicebox default-on composition | 552 | 36 | 15.3 | 19 | 3 |

Across the five permissive app prompts, the token-weighted baseline is **14.3 words per terminal-punctuation sentence** and **52 list rules over 1,332 words**. MiniWhisper is 41% longer by this sentence measure and is the only measured prompt that expresses all executable rules as paragraphs. The common OSS register is a one-line role or boundary, then short imperative rules in a list, then one output-only line. Three of five include examples. Two separate the transcript from instruction execution explicitly, and the stronger two also enumerate spoken punctuation or symbols. The outlier is Whisper Dictate: it has a long apparent average because most of its 18 bullet fragments lack terminal punctuation, which is exactly why raw sentence length alone cannot rescue documentation-shaped rules.

So the evidence supports a register rewrite, not wholesale rule deletion: retain the MiniWhisper boundary, punctuation, context, and output constraints, but split independent requirements into compact imperative list items. Do not copy any exemplar sentence into shipping code.
