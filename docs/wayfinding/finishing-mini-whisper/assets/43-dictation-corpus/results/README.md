# Results — the verdicts

One microphone (built-in), one voice, every run on the same recordings. Each subdirectory is one run with its own README (conditions, versions, per-entry detail); this file is the rollup. **The full engine × cleanup matrix lives in [e2e-combos/](e2e-combos/README.md)** — that is the single table comparing everything at once. The per-profile answer, from these numbers alone, is [profiles-recommendation.md](profiles-recommendation.md).

## Engines (stage 1: WER + latency)

| engine                               | WER       | median    | run                                                         |
| ------------------------------------ | --------- | --------- | ----------------------------------------------------------- |
| **ElevenLabs Scribe v2** (hosted)    | **0.98%** | 638 ms    | [elevenlabs-scribe-v2](elevenlabs-scribe-v2/)               |
| **Parakeet TDT v2 (shipping)**       | 1.95%     | **55 ms** | [built-in](built-in/)                                       |
| Cohere Transcribe (mlx-audio)        | 3.41%     | 97 ms     | [cohere-transcribe](cohere-transcribe/)                     |
| Groq whisper-large-v3-turbo (hosted) | 3.41%     | 523 ms    | [groq-whisper-large-v3-turbo](groq-whisper-large-v3-turbo/) |
| whisper large-v3-turbo               | 3.90%     | 487 ms    | [whisper-large-v3-turbo](whisper-large-v3-turbo/)           |
| whisper medium.en                    | 3.90%     | 422 ms    | [whisper-medium-en](whisper-medium-en/)                     |
| Gemini 3.6 Flash as engine (hosted)  | 4.39%     | 2339 ms   | [gemini-transcribe](gemini-transcribe/)                     |

Hosted latencies are network round trips measured from this machine, not provider inference time — network-dependent, and re-measure before betting on them.

**Scribe v2 is the first engine to beat Parakeet on accuracy**, at half the error rate, and it wins every e2e cleanup column except s1-mini's. It costs 583 ms more per utterance, a network, and an account. Parakeet remains the only engine that is free, offline, and instant. Groq's whisper is the same weights as the local whisper at the same speed — hosting whisper buys nothing on an M4 Pro. Gemini-as-engine is last on both axes and paraphrases what it hears.

Parakeet's one measured weakness is unchanged: it deletes meta-speech (quote/unquote, spelled letters) that every other engine hears. With Scribe's raw, the spelled-name entry converts.

## Cleanup models (stage 3 on Parakeet raw, exact match /27, e2e median)

| cleanup                                           | exact     | e2e latency | notes                                 |
| ------------------------------------------------- | --------- | ----------- | ------------------------------------- |
| **gemini-3.6-flash** (direct)                     | **19/27** | 1914 ms     | the crown; gateway costs +618 ms      |
| claude-haiku-4-5 (Anthropic direct)               | 17/27     | 696 ms      | dominates luna: same score, ¼ latency |
| claude-haiku-4-5 (Claude subscription, Agent SDK) | 17/27     | 1047 ms     | 685 ms on a warm session              |
| gpt-5.6-luna                                      | 17/27     | 2579 ms     | no remaining argument                 |
| gpt-oss-120b (Cerebras)                           | 15/27     | 420 ms      | rule failures, incl. one invariant    |
| s1-mini (local)                                   | 12/27     | **107 ms**  | fully offline; misses are structural  |

Those cleanup scores are the prompt as it stood before [prompt-tuning-haiku](prompt-tuning-haiku/), which tuned `CleanupPrompt.builtIn` against Parakeet raw + haiku and removed its worked examples. Two stage-3 expectations were amended there (`polish-01`, `polish-22`), so scores measured before it are not directly comparable to scores measured after.

Detail: [built-in-r2](built-in-r2/) (four providers, per-tag tables, the seven entries all four fail), [gemini-direct](gemini-direct/) (what the gateway costs: identical score, 618 ms), [agent-sdk-haiku](agent-sdk-haiku/) (the same Haiku on the Claude subscription: identical score, 255 ms of per-call Claude Code startup, 4 ms if the session is reused, and 4.4 s if adaptive thinking is left on).

The superwhisper offline stack, Cohere+s1-mini, loses to Parakeet+s1-mini on both axes (9/27 @ 172 ms vs 12/27 @ 107 ms).

## Vocabulary (stage 2: where a dictionary should be spent)

Four places, now that hosted engines are in the table — the sidecar before the transcript, the engine's own conditioning channel, the DICTIONARY block after the transcript, or nowhere:

| strategy                                | recall    | traps   | added latency |
| --------------------------------------- | --------- | ------- | ------------- |
| recognition sidecar (Parakeet boost)    | 16/18     | 5/8     | +98 ms        |
| whisper `prompt` (local `--prompt`)     | 12/18     | **0/8** | **+3 ms**     |
| whisper `prompt` (Groq)                 | 11/18     | **0/8** | +46 ms        |
| Scribe v2 `keyterms`                    | 17/18     | 2/8     | +99 ms        |
| Gemini transcription instructions       | **18/18** | 4/8     | −181 ms       |
| **DICTIONARY block, bare ASR + gemini** | **18/18** | **0/8** | +1954 ms      |
| DICTIONARY block, bare ASR + haiku      | 17/18     | 2/8     | +671 ms       |

Two runs, two findings. [dictionary-three-way](dictionary-three-way/): across four models and ten arms, every model bites strictly more traps on sidecar-boosted input and recovers zero terms for it; the [boost sweep](boost-sweep/) found no threshold above 80% recall under two traps. [asr-prompting](asr-prompting/): whisper's decoder prompt raises recall by five terms and **bites no traps at all** — the documented hallucination risk did not materialize once — because the prompt enters the same decoder that is already reading the sentence, where the sidecar only ever hears acoustics.

So the sidecar is not merely redundant, it is the only mechanism measured whose errors are both frequent and irreversible. And **Parakeet is the only engine with no conditioning channel of its own**, which makes "where does vocabulary go" a question the engine choice answers. Consequence routed to [ticket 47](../../../tickets/47-cleanup-endpoint-profiles.md).

## Superseded runs

[built-in](built-in/) stage-3 scores predate the spell-out prompt rule and the four re-recorded entries; [built-in-spellout](built-in-spellout/) has the rule but the old raw. [built-in-r2](built-in-r2/) supersedes both for stage 3. Stage 1/2 numbers in [built-in](built-in/) remain current.

## Not measured

No credentials, so these are named rather than ranked — each is a plausible way one of the answers below changes:

- **Deepgram Nova-3** — a `keyterm` channel of the same family as Scribe's `keyterms`, and the streaming-latency incumbent. AssemblyAI's own comparison (citing Hamming.ai over 4M production calls) puts it at 516 ms P50 / 9.87% WER on telephony, which is a different task than dictation; the reason to care is the keyterm channel plus a streaming path Parakeet does not have.
- **AssemblyAI Universal-3 Pro Streaming** — the same benchmark's winner at 307 ms P50 / 8.14% WER, with natural-language prompting and dynamic key terms. If a streaming profile ever exists, this is the first thing to measure.
- **OpenAI gpt-transcribe** — takes both a prompt and a keyword list, so it would land as a third point on the ASR-conditioning curve between whisper's imitation and Gemini's obedience.
- **Mistral Voxtral** (Apache 2.0, incl. a 4B realtime variant) — the only unmeasured candidate that could be a *local* engine, which is the one axis where Scribe cannot compete.

Benchmarks quoted here are the providers' own or their competitors'; none of them is this corpus, and the only number worth acting on is one measured on your own audio.
